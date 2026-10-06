import Foundation

/// URLSession equivalent of the Android Retrofit `GravWeightApi` + `ApiClient`.
/// Every request is sent with `Authorization: Bearer <Clerk session JWT>` when signed in.
final class APIClient {
    static let shared = APIClient()

    // Koyeb deployment URL (same as Android)
    let baseURL = URL(string: "https://annoyed-mitzi-nullvectorinteractive-42eae0eb.koyeb.app/")!

    /// Supplies a fresh Clerk token for each request (set by `PhoneViewModel`).
    var tokenProvider: (() async -> String?)?

    struct HTTPError: LocalizedError {
        let code: Int
        let body: String
        var errorDescription: String? { "HTTP \(code)" }
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Minutes behind UTC, like JavaScript's `getTimezoneOffset()` (server expects this for `tz`).
    static var tzOffsetMinutes: Int { -TimeZone.current.secondsFromGMT() / 60 }

    // MARK: Core

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: (any Encodable)?) async throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = await tokenProvider?() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw HTTPError(code: code, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> T {
        let data = try await perform(try await makeRequest(method, path, query: query, body: body))
        return try decoder.decode(T.self, from: data)
    }

    /// For endpoints whose response body we don't need (`OkResponse` on Android).
    func sendVoid(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws {
        _ = try await perform(try await makeRequest(method, path, query: query, body: body))
    }

    // MARK: Users

    func syncUser(email: String, name: String) async throws {
        try await sendVoid("POST", "api/users/sync", body: UserSyncRequest(email: email, name: name))
    }

    func getMyProfile() async throws -> MyProfileDto {
        let r: GetMyProfileResponse = try await send("GET", "api/users/profile")
        return r.profile
    }

    func updateProfile(_ body: UpdateProfileRequest) async throws {
        try await sendVoid("PUT", "api/users/profile", body: body)
    }

    // MARK: Logs

    func getLogs() async throws -> [LogEntry] {
        let r: GetLogsResponse = try await send("GET", "api/logs")
        return r.logs ?? []
    }

    func batchUpsert(_ logs: [LogEntry]) async throws {
        try await sendVoid("POST", "api/logs/batch", body: BatchUpsertRequest(logs: logs))
    }

    func updateLog(_ log: LogEntry) async throws {
        try await sendVoid("PUT", "api/logs/\(log.id)", body: log)
    }

    func deleteLog(id: String) async throws {
        try await sendVoid("DELETE", "api/logs/\(id)")
    }

    // MARK: Health / sessions / progress

    func getHealth() async throws -> [HealthMetricDto] {
        let r: GetHealthResponse = try await send("GET", "api/health")
        return r.metrics ?? []
    }

    func batchSyncHealth(_ metrics: [HealthMetricDto]) async throws {
        try await sendVoid("POST", "api/health/batch", body: BatchHealthUpsertRequest(metrics: metrics))
    }

    func getSessions() async throws -> [ExerciseSessionDto] {
        let r: GetSessionsResponse = try await send("GET", "api/sessions")
        return r.sessions ?? []
    }

    func batchSyncSessions(_ sessions: [ExerciseSessionDto]) async throws {
        try await sendVoid("POST", "api/sessions/batch", body: BatchSessionUpsertRequest(sessions: sessions))
    }

    func getProgress() async throws -> [UserProgressDto] {
        let r: GetProgressResponse = try await send("GET", "api/progress")
        return r.progress ?? []
    }

    func addProgress(_ p: UserProgressDto) async throws {
        try await sendVoid("POST", "api/progress", body: p)
    }

    func getLeaderboard() async throws -> [PrBoardEntry] {
        let r: GetLeaderboardResponse = try await send("GET", "api/leaderboard")
        return r.leaderboard ?? []
    }

    // MARK: Social

    func getFeed(limit: Int = 20, offset: Int = 0) async throws -> [SocialPostDto] {
        let r: GetFeedResponse = try await send("GET", "api/social/feed", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ])
        return r.posts ?? []
    }

    func getFriends() async throws -> [FriendDto] {
        let r: GetFriendsResponse = try await send("GET", "api/social/friends")
        return r.friends ?? []
    }

    func sendFriendRequest(friendId: String) async throws {
        try await sendVoid("POST", "api/social/friends/request", body: FriendRequestBody(friendId: friendId))
    }

    func handleFriendAction(id: String, action: String) async throws {
        try await sendVoid("PUT", "api/social/friends/\(id)", body: FriendActionRequest(action: action))
    }

    func removeFriend(friendId: String) async throws {
        try await sendVoid("DELETE", "api/social/friends/\(friendId)")
    }

    func createPost(_ body: CreatePostRequest) async throws {
        try await sendVoid("POST", "api/social/posts", body: body)
    }

    func deletePost(id: String) async throws {
        try await sendVoid("DELETE", "api/social/posts/\(id)")
    }

    func toggleLike(postId: String) async throws {
        try await sendVoid("POST", "api/social/posts/\(postId)/like")
    }

    func getComments(postId: String) async throws -> [SocialCommentDto] {
        let r: GetCommentsResponse = try await send("GET", "api/social/posts/\(postId)/comments")
        return r.comments ?? []
    }

    func addComment(postId: String, content: String) async throws {
        try await sendVoid("POST", "api/social/posts/\(postId)/comments", body: CommentBody(content: content))
    }

    func getNotifications() async throws -> [NotificationDto] {
        let r: GetNotificationsResponse = try await send("GET", "api/social/notifications")
        return r.notifications ?? []
    }

    func markNotificationsRead() async throws {
        try await sendVoid("PUT", "api/social/notifications/read")
    }

    func searchUsers(_ q: String) async throws -> [UserSearchResult] {
        let r: SearchUsersResponse = try await send("GET", "api/social/users/search", query: [URLQueryItem(name: "q", value: q)])
        return r.users ?? []
    }

    func getUserProfile(userId: String) async throws -> UserProfileDto {
        let r: GetProfileResponse = try await send("GET", "api/social/users/\(userId)/profile")
        return r.profile
    }

    func getGroups() async throws -> [GroupDto] {
        let r: GetGroupsResponse = try await send("GET", "api/social/groups")
        return r.groups ?? []
    }

    // MARK: Versus / progress

    func compare(friendId: String) async throws -> CompareResponse {
        try await send("GET", "api/compare/\(friendId)", query: [URLQueryItem(name: "tz", value: String(Self.tzOffsetMinutes))])
    }

    func liftProgress(exercise: String) async throws -> ProgressPayloadDto {
        let encoded = exercise.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? exercise
        // appendingPathComponent would double-encode, so build this URL path manually.
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.percentEncodedPath = "/api/compare/progress/\(encoded)"
        comps.queryItems = [URLQueryItem(name: "tz", value: String(Self.tzOffsetMinutes))]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        if let token = await tokenProvider?() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data = try await perform(req)
        return try decoder.decode(ProgressPayloadDto.self, from: data)
    }
}
