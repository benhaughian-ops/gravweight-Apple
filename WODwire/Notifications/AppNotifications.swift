import Foundation
import SwiftUI
import UserNotifications
import BackgroundTasks

/// Where a tapped notification should land inside the app.
enum NotificationRoute: Equatable {
    case feed(postId: String?)
    case friends(userId: String?)
    case group(groupId: String?)
    case challenge

    init(type: String, linkId: String?) {
        switch type {
        case "friend_request", "friend_accept": self = .friends(userId: nil)
        case "group_post": self = .group(groupId: linkId)
        case "challenge": self = .challenge
        case "comment": self = .feed(postId: linkId)
        default: self = .feed(postId: nil)
        }
    }

    /// Social sub-tab index (0 Feed · 1 Friends · 2 Groups).
    var socialTab: Int {
        switch self {
        case .friends: return 1
        case .group: return 2
        default: return 0
        }
    }
}

/// System (lock-screen / banner) notifications + background refresh so social alerts
/// reach the user on any screen — or when the app isn't open.
final class AppNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotifications()
    static let refreshTaskId = "com.WODwire.notifications.refresh"

    /// Called on the main actor when the user taps a system notification.
    var onTap: (@MainActor (NotificationRoute, String) -> Void)? {
        didSet {
            guard let route = pendingRoute, let handler = onTap else { return }
            pendingRoute = nil
            Task { @MainActor in handler(route, "") }
        }
    }
    /// A tap that launched the app before the UI was ready.
    private var pendingRoute: NotificationRoute?

    private let seenKey = "notif_announced_ids"
    private let defaults = UserDefaults.standard

    // MARK: Setup

    /// Must run before the app finishes launching (BGTaskScheduler requirement).
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.handleRefresh(task)
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: De-duplication (shared by foreground polling and background refresh)

    /// nil until the first successful fetch, so a fresh install doesn't replay history.
    var announcedIds: Set<String>? {
        get { (defaults.array(forKey: seenKey) as? [String]).map(Set.init) }
        set { defaults.set(newValue.map { Array($0.suffix(300)) }, forKey: seenKey) }
    }

    /// Returns unread notifications not yet announced, then records them as announced.
    func takeFresh(from list: [NotificationDto]) -> [NotificationDto] {
        let unread = list.filter { !$0.is_read }
        guard let seen = announcedIds else {
            announcedIds = Set(list.map(\.id))
            return []
        }
        let fresh = unread.filter { !seen.contains($0.id) }
        announcedIds = seen.union(list.map(\.id))
        return fresh
    }

    // MARK: Posting

    func post(_ n: NotificationDto) {
        let content = UNMutableNotificationContent()
        content.title = "WODwire"
        content.body = n.message
        content.sound = .default
        content.userInfo = ["type": n.type, "link_id": n.link_id ?? "", "id": n.id]
        let req = UNNotificationRequest(identifier: n.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }

    // MARK: Background refresh

    func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    private func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh() // keep the chain going
        let work = Task {
            defer { task.setTaskCompleted(success: true) }
            APIClient.shared.tokenProvider = { await AuthBridge.token() }
            guard let list = try? await APIClient.shared.getNotifications() else { return }
            let fresh = takeFresh(from: list)
            fresh.prefix(3).forEach(post)
            setBadge(list.filter { !$0.is_read }.count)
        }
        task.expirationHandler = { work.cancel() }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// In the foreground we show our own in-app banner, so suppress the system one.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String ?? ""
        let link = (info["link_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let message = response.notification.request.content.body
        let route = NotificationRoute(type: type, linkId: link)
        await MainActor.run {
            if let handler = onTap { handler(route, message) } else { pendingRoute = route }
        }
    }
}

// MARK: - In-app banner

/// Slide-down banner shown on any tab when a new social notification arrives. Tap to open it.
struct NotificationBanner: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack {
            if let n = vm.incomingNotification {
                HStack(spacing: 12) {
                    Button { vm.openNotification(n) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: n.type))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Brand.cyanGlow)
                                .frame(width: 36, height: 36)
                                .background(Brand.cyanGlow.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.message)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(p.text)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("Tap to view")
                                    .font(.system(size: 11))
                                    .foregroundStyle(p.dim)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    Button { vm.dismissBanner() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(p.dim)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Dismiss")
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.cyanGlow.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .gesture(DragGesture().onEnded { if $0.translation.height < -10 { vm.dismissBanner() } })
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.incomingNotification?.id)
    }

    private func icon(for type: String) -> String {
        switch type {
        case "challenge": return "flag.checkered"
        case "friend_request", "friend_accept": return "person.badge.plus"
        case "comment": return "bubble.left.fill"
        case "group_post": return "person.3.fill"
        case "linked_session": return "figure.strengthtraining.traditional"
        default: return "bell.fill"
        }
    }
}
