import Foundation
import SwiftUI

/// iOS port of Android's `PhoneViewModel`: barbell state, offline-first logs, cloud sync,
/// health, social feed and preferences. All UI state is published on the main actor.
@MainActor
final class PhoneViewModel: ObservableObject {

    struct UserInfo: Equatable {
        let userId: String
        let name: String
        let email: String
    }

    enum SyncState: Equatable {
        case idle, syncing, success
        case error(String)
    }

    // MARK: Published state

    @Published var state = BarbellState()
    @Published var logs: [LogEntry] = []
    @Published var healthMetrics: [HealthMetricDto] = []
    @Published var sessions: [ExerciseSessionDto] = []
    @Published var userProgress: [UserProgressDto] = []
    @Published var leaderboard: [PrBoardEntry] = []
    @Published var feed: [SocialPostDto] = []
    @Published var friends: [FriendDto] = []
    @Published var notifications: [NotificationDto] = []
    @Published var groups: [GroupDto] = []
    @Published var currentUser: UserInfo?
    @Published var syncState: SyncState = .idle
    @Published var isWatchConnected = false

    @Published var today: HealthKitManager.TodaySummary?
    @Published var week: [HealthMetricDto] = []
    @Published var lastHealthSync: Date?
    @Published var healthRefreshing = false
    @Published var goals = DailyGoals()

    /// Bottom toast message (Android `Toast` equivalent).
    @Published var toast: String?

    // MARK: Preferences (persisted)

    @Published var isDarkMode: Bool { didSet { defaults.set(isDarkMode, forKey: Keys.dark) } }
    @Published var isMetric: Bool { didSet { defaults.set(isMetric, forKey: Keys.metric) } }
    @Published var isJokeMode: Bool { didSet { defaults.set(isJokeMode, forKey: Keys.joke) } }
    @Published var showLiftingGraph: Bool { didSet { defaults.set(showLiftingGraph, forKey: Keys.lifting) } }
    @Published var showBodyCompGraph: Bool { didSet { defaults.set(showBodyCompGraph, forKey: Keys.bodyComp) } }
    @Published var showVo2MaxGraph: Bool { didSet { defaults.set(showVo2MaxGraph, forKey: Keys.vo2) } }

    private enum Keys {
        static let dark = "pref_dark_mode", metric = "pref_metric", joke = "pref_joke_mode"
        static let lifting = "pref_show_lifting", bodyComp = "pref_show_bodycomp", vo2 = "pref_show_vo2"
        static let lastHealthSync = "last_health_sync"
    }

    private let defaults = UserDefaults.standard
    private let api = APIClient.shared
    private let health = HealthKitManager.shared
    private let watch = PhoneConnectivity.shared

    private var feedLoadingMore = false
    private var feedReachedEnd = false
    private let feedPageSize = 20
    private var toastTask: Task<Void, Never>?

    // MARK: Init

    init() {
        let d = UserDefaults.standard
        isDarkMode = d.object(forKey: Keys.dark) as? Bool ?? true
        isMetric = d.object(forKey: Keys.metric) as? Bool ?? false
        isJokeMode = d.object(forKey: Keys.joke) as? Bool ?? false
        showLiftingGraph = d.object(forKey: Keys.lifting) as? Bool ?? true
        showBodyCompGraph = d.object(forKey: Keys.bodyComp) as? Bool ?? true
        showVo2MaxGraph = d.object(forKey: Keys.vo2) as? Bool ?? true
        if let t = d.object(forKey: Keys.lastHealthSync) as? Double { lastHealthSync = Date(timeIntervalSince1970: t) }

        state = BarbellState(isMetric: isMetric)
        logs = Storage.load([LogEntry].self, from: "logs.json") ?? []
        feed = Storage.load([SocialPostDto].self, from: "feed_cache.json") ?? []

        api.tokenProvider = { await AuthBridge.token() }

        watch.onState = { [weak self] s in self?.state = s }
        watch.onLogTrigger = { [weak self] weight, ts in self?.addLog(weightLbs: weight, timestamp: ts) }
        watch.onConnectionChange = { [weak self] c in self?.isWatchConnected = c }
        watch.activate()
        isWatchConnected = watch.isWatchConnected
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.toast = nil }
        }
    }

    // MARK: Barbell (phone ⇄ watch)

    func addPlate(_ p: PlateType) { state = state.addingPlate(p); watch.send(state: state) }
    func removePlate(_ p: PlateType) { state = state.removingPlate(p); watch.send(state: state) }
    func clear() { state = state.cleared(); watch.send(state: state) }

    func setMetric(_ metric: Bool) {
        isMetric = metric
        state = BarbellState(isMetric: metric) // switching units clears the bar, like Android
        watch.send(state: state)
    }

    /// Phone LOG button.
    func logWorkout() {
        addLog(weightLbs: state.totalLoadLbs, timestamp: Int64(Date().timeIntervalSince1970 * 1000))
    }

    // MARK: Logs (offline-first)

    private func addLog(weightLbs: Double, timestamp: Int64) {
        let entry = LogEntry(timestamp: timestamp, weightLbs: weightLbs)
        logs.insert(entry, at: 0)
        persistLogs()
        guard currentUser != nil else { return }
        Task { try? await api.batchUpsert([entry]) }
    }

    func updateLog(_ entry: LogEntry) {
        guard let i = logs.firstIndex(where: { $0.id == entry.id }) else { return }
        logs[i] = entry
        persistLogs()
        guard currentUser != nil else { return }
        Task {
            do { try await api.updateLog(entry) } catch { try? await api.batchUpsert([entry]) }
        }
    }

    func deleteLog(id: String) {
        logs.removeAll { $0.id == id }
        persistLogs()
        guard currentUser != nil else { return }
        Task { try? await api.deleteLog(id: id) }
    }

    private func persistLogs() { Storage.save(logs, to: "logs.json") }

    // MARK: Auth / sync

    /// Called whenever Clerk's signed-in user changes.
    func onAuthChanged(_ user: UserInfo?) {
        guard user != currentUser else { return }
        currentUser = user
        if user != nil {
            Task { await fullSync() }
        } else {
            syncState = .idle
            friends = []; notifications = []; groups = []
        }
    }

    func signOut() {
        Task {
            await AuthBridge.signOut()
            onAuthChanged(nil)
        }
    }

    /// syncUser → push all logs → fetch & merge → health / progress / leaderboard / sessions → social.
    func fullSync() async {
        guard let user = currentUser else { return }
        syncState = .syncing
        do {
            try await api.syncUser(email: user.email, name: user.name)
            if !logs.isEmpty { try await api.batchUpsert(logs) }
            let remote = try await api.getLogs()
            mergeRemoteLogs(remote)
            syncState = .success
        } catch {
            syncState = .error(error.localizedDescription)
        }
        async let h: Void = fetchHealth()
        async let p: Void = fetchProgress()
        async let l: Void = fetchLeaderboard()
        async let s: Void = fetchSessions()
        async let g: Void = fetchGoals()
        _ = await (h, p, l, s, g)
        await fetchSocialAll()
        await refreshHealth(force: false)
    }

    private func mergeRemoteLogs(_ remote: [LogEntry]) {
        var byId = Dictionary(uniqueKeysWithValues: logs.map { ($0.id, $0) })
        for r in remote {
            if var local = byId[r.id] {
                if local.exercise.trimmingCharacters(in: .whitespaces).isEmpty && !r.exercise.isEmpty {
                    local.exercise = r.exercise
                    if local.reps == 0 { local.reps = r.reps }
                    if local.variant == nil { local.variant = r.variant }
                    byId[r.id] = local
                }
            } else {
                byId[r.id] = r
            }
        }
        logs = byId.values.sorted { $0.timestamp > $1.timestamp }
        persistLogs()
    }

    func syncNow() { Task { await fullSync() } }

    func fetchHealth() async {
        if let m = try? await api.getHealth() { healthMetrics = m.sorted { $0.date > $1.date } }
    }

    func fetchSessions() async {
        if let s = try? await api.getSessions() { sessions = s.sorted { $0.startTime > $1.startTime } }
    }

    func fetchProgress() async {
        if let p = try? await api.getProgress() { userProgress = p }
    }

    func fetchLeaderboard() async {
        if let l = try? await api.getLeaderboard() { leaderboard = l }
    }

    func fetchGoals() async {
        if let me = try? await api.getMyProfile() { goals = DailyGoals.parse(me.goals) }
    }

    func addManualProgress(date: String, weight: Double?, bodyFat: Double?, leanMass: Double?, bmr: Int?, notes: String?) {
        let p = UserProgressDto(date: date, weightLbs: weight, bodyFatPercentage: bodyFat, leanMassLbs: leanMass, bmr: bmr, notes: notes)
        Task {
            do {
                try await api.addProgress(p)
                await fetchProgress()
                showToast("Progress saved")
            } catch {
                showToast("Couldn't save progress")
            }
        }
    }

    // MARK: Health (HealthKit replaces Health Connect)

    /// Reads today + last 30 days from Apple Health, uploads to the cloud when signed in.
    func refreshHealth(force: Bool) async {
        guard health.isAvailable else { return }
        if !force, let last = lastHealthSync, Date().timeIntervalSince(last) < 120, today != nil { return }
        healthRefreshing = true
        defer { healthRefreshing = false }
        _ = await health.requestAuthorization()
        today = await health.readToday()
        let metrics = await health.readHealthMetrics(days: 30)
        let todayKey = HealthKitManager.dayKey(Date())
        let weekStart = HealthKitManager.dayKey(Calendar.current.date(byAdding: .day, value: -6, to: Date())!)
        week = metrics.filter { $0.date >= weekStart && $0.date <= todayKey }
        guard currentUser != nil else { return }
        let workouts = await health.readExerciseSessions(days: 90)
        do {
            if !metrics.isEmpty { try await api.batchSyncHealth(metrics) }
            if !workouts.isEmpty { try await api.batchSyncSessions(workouts) }
            lastHealthSync = Date()
            defaults.set(lastHealthSync!.timeIntervalSince1970, forKey: Keys.lastHealthSync)
            await fetchHealth()
            await fetchSessions()
            if force { showToast("Health synced: \(metrics.count) days, \(workouts.count) workouts") }
        } catch {
            if force { showToast("Failed to sync to cloud: \(error.localizedDescription)") }
        }
    }

    // MARK: Social

    func fetchSocialAll() async {
        async let a: Void = fetchFeed()
        async let b: Void = fetchFriends()
        async let c: Void = fetchNotifications()
        async let d: Void = fetchGroups()
        _ = await (a, b, c, d)
    }

    func fetchFeed() async {
        guard currentUser != nil, let posts = try? await api.getFeed(limit: feedPageSize, offset: 0) else { return }
        feed = posts
        feedReachedEnd = posts.count < feedPageSize
        Storage.save(feed, to: "feed_cache.json")
    }

    func loadMoreFeed() async {
        guard currentUser != nil, !feedLoadingMore, !feedReachedEnd else { return }
        feedLoadingMore = true
        defer { feedLoadingMore = false }
        guard let more = try? await api.getFeed(limit: feedPageSize, offset: feed.count) else { return }
        let existing = Set(feed.map { $0.id })
        feed.append(contentsOf: more.filter { !existing.contains($0.id) })
        if more.count < feedPageSize { feedReachedEnd = true }
    }

    func fetchFriends() async {
        if let f = try? await api.getFriends() { friends = f }
    }

    func fetchNotifications() async {
        if let n = try? await api.getNotifications() { notifications = n }
    }

    func fetchGroups() async {
        if let g = try? await api.getGroups() { groups = g }
    }

    func sendFriendRequest(_ userId: String) {
        Task {
            do { try await api.sendFriendRequest(friendId: userId); showToast("Friend request sent") }
            catch { showToast("Couldn't send request") }
            await fetchFriends()
        }
    }

    func handleFriendAction(id: String, action: String) {
        Task { try? await api.handleFriendAction(id: id, action: action); await fetchFriends(); await fetchFeed() }
    }

    func removeFriend(_ friendId: String) {
        Task { try? await api.removeFriend(friendId: friendId); await fetchFriends() }
    }

    func createPost(sessionId: String?, comment: String?, groupId: String?, linkedSessionId: String?) {
        Task {
            do {
                try await api.createPost(CreatePostRequest(postType: "workout", sessionId: sessionId, comment: comment, groupId: groupId, linkedSessionId: linkedSessionId))
                showToast("Post shared successfully!")
                await fetchFeed()
            } catch {
                showToast("Couldn't share post")
            }
        }
    }

    /// Optimistic like toggle.
    func toggleLike(_ postId: String) {
        guard let i = feed.firstIndex(where: { $0.id == postId }) else {
            Task { try? await api.toggleLike(postId: postId) }
            return
        }
        let before = feed[i]
        var p = before
        if p.user_liked > 0 { p.user_liked = 0; p.like_count = max(0, p.like_count - 1) }
        else { p.user_liked = 1; p.like_count += 1 }
        feed[i] = p
        Task {
            do { try await api.toggleLike(postId: postId) }
            catch { if let j = feed.firstIndex(where: { $0.id == postId }) { feed[j] = before } }
        }
    }

    /// Optimistic comment.
    func addComment(postId: String, content: String) {
        if let i = feed.firstIndex(where: { $0.id == postId }) {
            var p = feed[i]
            p.comment_count += 1
            var c = SocialCommentDto(post_id: postId, user_id: currentUser?.userId ?? "", content: content)
            c.author_name = currentUser?.name
            p.recent_comments = (p.recent_comments ?? []) + [c]
            feed[i] = p
        }
        Task {
            try? await api.addComment(postId: postId, content: content)
            await fetchFeed()
        }
    }

    func deletePost(_ postId: String) {
        feed.removeAll { $0.id == postId }
        Task { try? await api.deletePost(id: postId); await fetchFeed() }
    }

    func markNotificationsRead() {
        notifications = notifications.map { var n = $0; n.is_read = true; return n }
        Task { try? await api.markNotificationsRead() }
    }

    func compare(friendId: String) async throws -> CompareResponse {
        try await api.compare(friendId: friendId)
    }

    /// Fetch the lift's progression and post it as a `progress` card (last 26 weekly points).
    func shareLiftProgress(exercise: String, caption: String) async -> (Bool, String) {
        do {
            var payload = try await api.liftProgress(exercise: exercise)
            let series = payload.series ?? []
            guard !series.isEmpty else { return (false, "Not enough data for \(exercise) yet") }
            payload.series = Array(series.suffix(26))
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            try await api.createPost(CreatePostRequest(postType: "progress", comment: trimmed.isEmpty ? nil : trimmed, payload: payload))
            await fetchFeed()
            return (true, "Progress shared!")
        } catch {
            return (false, "Couldn't share progress")
        }
    }
}

// MARK: - Simple JSON file storage (Android used SharedPreferences JSON)

enum Storage {
    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
