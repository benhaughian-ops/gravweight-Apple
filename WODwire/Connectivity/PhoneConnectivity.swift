import Foundation
import WatchConnectivity

/// iPhone side of the watch link — the Apple equivalent of the Android Wearable Data Layer.
///  • Barbell state is mirrored both ways (applicationContext + live message when reachable).
///  • The watch's LOG WEIGHT button arrives as a `log_trigger` (message or queued userInfo).
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    /// Called on the main actor when the watch changes the plates.
    var onState: ((BarbellState) -> Void)?
    /// Called on the main actor when the watch taps LOG WEIGHT: (weightLbs, timestampMs).
    var onLogTrigger: ((Double, Int64) -> Void)?
    /// Called on the main actor whenever pairing / install / reachability changes.
    var onConnectionChange: ((Bool) -> Void)?

    private var seenNonces = Set<String>()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var isWatchConnected: Bool {
        guard WCSession.isSupported() else { return false }
        let s = WCSession.default
        return s.activationState == .activated && s.isPaired && s.isWatchAppInstalled
    }

    /// Push the phone's barbell state to the watch.
    func send(state: BarbellState) {
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

    // MARK: Incoming

    private func handle(_ payload: [String: Any]) {
        guard let kind = payload[WatchKeys.kind] as? String else { return }
        switch kind {
        case WatchKeys.kindState:
            let state = BarbellState.from(payload)
            Task { @MainActor in self.onState?(state) }
        case WatchKeys.kindLogTrigger:
            // The same trigger can arrive twice (message + userInfo fallback) — dedupe by nonce.
            if let nonce = payload[WatchKeys.nonce] as? String {
                if seenNonces.contains(nonce) { return }
                seenNonces.insert(nonce)
            }
            let weight = (payload[WatchKeys.weight] as? NSNumber)?.doubleValue ?? 0
            let ts = (payload[WatchKeys.timestamp] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)
            Task { @MainActor in self.onLogTrigger?(weight, ts) }
        default:
            break
        }
    }

    private func publishConnection() {
        let connected = isWatchConnected
        Task { @MainActor in self.onConnectionChange?(connected) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        publishConnection()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required when switching between paired watches.
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) { publishConnection() }
    func sessionReachabilityDidChange(_ session: WCSession) { publishConnection() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
}
