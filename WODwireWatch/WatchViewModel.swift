import Foundation
import SwiftUI
import WatchConnectivity
import WatchKit

/// Watch-side state + WatchConnectivity link (Android `WatchViewModel` + Wear Data Layer).
///  • Plate changes are applied optimistically and pushed to the phone.
///  • LOG WEIGHT sends a `log_trigger` (live message when reachable, queued userInfo otherwise).
///  • Phone-side changes arrive via applicationContext / message.
final class WatchViewModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var state = BarbellState()
    @Published var toast: String?

    private var toastWork: DispatchWorkItem?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Actions

    func addPlate(_ plate: PlateType) {
        state = state.addingPlate(plate)
        WKInterfaceDevice.current().play(.click)
        pushState()
    }

    func removePlate(_ plate: PlateType) {
        guard state.count(plate) > 0 else { return }
        state = state.removingPlate(plate)
        WKInterfaceDevice.current().play(.click)
        pushState()
    }

    func clear() {
        state = state.cleared()
        WKInterfaceDevice.current().play(.directionDown)
        pushState()
    }

    func logWeight() {
        let payload: [String: Any] = [
            WatchKeys.kind: WatchKeys.kindLogTrigger,
            WatchKeys.weight: state.totalLoadLbs,
            WatchKeys.timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            WatchKeys.nonce: UUID().uuidString
        ]
        if WCSession.isSupported() {
            let s = WCSession.default
            if s.activationState == .activated && s.isReachable {
                s.sendMessage(payload, replyHandler: nil) { _ in
                    // Fall back to the guaranteed (queued) channel; the phone dedupes by nonce.
                    WCSession.default.transferUserInfo(payload)
                }
            } else {
                s.transferUserInfo(payload)
            }
        }
        WKInterfaceDevice.current().play(.success)
        showToast("Log successful!")
    }

    private func pushState() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var payload = state.toDictionary()
        payload[WatchKeys.kind] = WatchKeys.kindState
        payload[WatchKeys.timestamp] = Int64(Date().timeIntervalSince1970 * 1000)
        let s = WCSession.default
        try? s.updateApplicationContext(payload)
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func showToast(_ message: String) {
        toastWork?.cancel()
        withAnimation { toast = message }
        let work = DispatchWorkItem { [weak self] in withAnimation { self?.toast = nil } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    // MARK: Incoming

    private func handle(_ payload: [String: Any]) {
        guard (payload[WatchKeys.kind] as? String) == WatchKeys.kindState else { return }
        let incoming = BarbellState.from(payload)
        DispatchQueue.main.async { [weak self] in
            guard let self, incoming != self.state else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.state = incoming }
        }
    }

    // MARK: WCSessionDelegate (watchOS only needs these)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { handle(ctx) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
}
