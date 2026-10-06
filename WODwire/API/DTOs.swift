import Foundation

// Swift mirrors of `Dtos.kt` + `SocialDtos.kt`. Property names match the JSON keys exactly
// (camelCase for core endpoints, snake_case for social), so no CodingKeys are needed.

// MARK: - Logs

/// Workout log entry. Mirrors `com.gravweight.shared.LogEntry` and `LogEntryDto` (same JSON).
struct LogEntry: Codable, Identifiable, Equatable {
    @FlexD var id: String = UUID().uuidString
    /// epoch milliseconds
    @FlexD var timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    @FlexD var weightLbs: Double = 0
    @FlexD var exercise: String = ""
    @FlexD var reps: Int = 0
    @Flex var notes: String? = nil
    @Flex var rpe: Int? = nil
    @Flex var tempo: String? = nil
    @Flex var variant: String? = nil

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000) }

    static func == (a: LogEntry, b: LogEntry) -> Bool {
        a.id == b.id && a.timestamp == b.timestamp && a.weightLbs == b.weightLbs && a.exercise == b.exercise &&
            a.reps == b.reps && a.notes == b.notes && a.rpe == b.rpe && a.tempo == b.tempo && a.variant == b.variant
    }
}

struct GetLogsResponse: Decodable { var logs: [LogEntry]? }
struct BatchUpsertRequest: Encodable { let logs: [LogEntry] }
struct UserSyncRequest: Encodable { let email: String; let name: String }

// MARK: - Health

struct HealthMetricDto: Codable, Identifiable {
    var id: String { date }
    @FlexD var date: String = ""
    @FlexD var steps: Int = 0
    @Flex var avgHeartRate: Int? = nil
    @Flex var calories: Int? = nil
    @Flex var bmr: Int? = nil
    @Flex var weightLbs: Double? = nil
    @Flex var vo2Max: Double? = nil
    @Flex var bodyFatPercentage: Double? = nil
    @Flex var leanMassLbs: Double? = nil
    @Flex var boneMassLbs: Double? = nil
    @Flex var floorsClimbed: Double? = nil
    @Flex var restingHeartRate: Int? = nil
    @Flex var bloodPressureSystolic: Double? = nil
    @Flex var bloodPressureDiastolic: Double? = nil
    @Flex var oxygenSaturation: Double? = nil
    @Flex var bloodGlucose: Double? = nil
    @Flex var bodyTemperatureCelsius: Double? = nil
    @Flex var respiratoryRate: Double? = nil
    @Flex var heightInches: Double? = nil
    @Flex var hydrationOunces: Double? = nil
    @Flex var proteinGrams: Double? = nil
    @Flex var carbsGrams: Double? = nil
    @Flex var fatGrams: Double? = nil
    @Flex var activeCalories: Int? = nil
    @Flex var activeMinutes: Int? = nil
    @Flex var maxHeartRate: Int? = nil
    @Flex var updatedAt: String? = nil
}

struct BatchHealthUpsertRequest: Encodable { let metrics: [HealthMetricDto] }
struct GetHealthResponse: Decodable { var metrics: [HealthMetricDto]? }

// MARK: - Sessions

struct HrSample: Codable, Hashable {
    @FlexD var timeOffsetSec: Int = 0
    @FlexD var bpm: Int = 0

    static func == (a: HrSample, b: HrSample) -> Bool { a.timeOffsetSec == b.timeOffsetSec && a.bpm == b.bpm }
    func hash(into h: inout Hasher) { h.combine(timeOffsetSec); h.combine(bpm) }
}

struct ExerciseSessionDto: Codable, Identifiable {
    @FlexD var id: String = ""
    /// epoch ms
    @FlexD var startTime: Int64 = 0
    /// epoch ms
    @FlexD var endTime: Int64 = 0
    @FlexD var durationMinutes: Int = 0
    @FlexD var exerciseType: String = "Workout"
    @Flex var title: String? = nil
    @Flex var avgHeartRate: Int? = nil
    @Flex var peakHeartRate: Int? = nil
    @Flex var calories: Int? = nil
    @Flex var distanceMeters: Double? = nil
    var hrSamples: [HrSample]? = nil
    @Flex var notes: String? = nil
    @FlexD var isHidden: Bool = false

    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(startTime) / 1000) }
    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? exerciseType }
}

struct BatchSessionUpsertRequest: Encodable { let sessions: [ExerciseSessionDto] }
struct GetSessionsResponse: Decodable { var sessions: [ExerciseSessionDto]? }

// MARK: - Progress / leaderboard

struct UserProgressDto: Codable {
    @FlexD var date: String = ""
    @Flex var weightLbs: Double? = nil
    @Flex var bodyFatPercentage: Double? = nil
    @Flex var leanMassLbs: Double? = nil
    @Flex var bmr: Int? = nil
    @Flex var notes: String? = nil
}

struct GetProgressResponse: Decodable { var progress: [UserProgressDto]? }

struct PrBoardEntry: Codable {
    @FlexD var rank: Int = 0
    @Flex var nickname: String? = nil
    @FlexD var exercise: String = ""
    @Flex var variant: String? = nil
    @FlexD var max_weight: Double = 0
    @FlexD var max_1rm: Double = 0
    @FlexD var date: String = ""
}

struct GetLeaderboardResponse: Decodable { var leaderboard: [PrBoardEntry]? }

// MARK: - Social

struct SocialPostDto: Codable, Identifiable {
    @FlexD var id: String = ""
    @FlexD var user_id: String = ""
    @FlexD var post_type: String = "workout"
    @Flex var session_id: String? = nil
    @Flex var comment: String? = nil
    @Flex var group_id: String? = nil
    @Flex var linked_session_id: String? = nil
    @Flex var author_name: String? = nil
    @Flex var author_nickname: String? = nil
    @Flex var author_email: String? = nil
    @Flex var author_avatar_url: String? = nil
    @FlexD var like_count: Int = 0
    @FlexD var user_liked: Int = 0
    @FlexD var comment_count: Int = 0
    @Flex var group_name: String? = nil
    @Flex var group_color: String? = nil
    @Flex var created_at: String? = nil
    var session: SessionSnapshotDto? = nil
    var linked_session: SessionSnapshotDto? = nil
    @Flex var badge_name: String? = nil
    @Flex var badge_category: String? = nil
    var logs: [LogEntry]? = nil
    var recent_comments: [SocialCommentDto]? = nil
    var payload: ProgressPayloadDto? = nil

    var displayName: String { author_nickname ?? author_name ?? author_email ?? "Unknown" }
}

/// Structured data for `progress` posts (lift progression cards).
struct ProgressPayloadDto: Codable {
    @FlexD var exercise: String = ""
    @FlexD var startE1rm: Double = 0
    @FlexD var currentE1rm: Double = 0
    @Flex var bestE1rm: Double? = nil
    @Flex var bestWeight: Double? = nil
    @FlexD var pctGain: Double = 0
    @FlexD var weeks: Int = 0
    var series: [WeekPointDto]? = nil
}

struct WeekPointDto: Codable {
    @FlexD var week: String = ""
    @FlexD var e1rm: Double = 0
}

struct SessionSnapshotDto: Codable {
    @FlexD var id: String = ""
    @FlexD var user_id: String = ""
    @FlexD var start_time: String = "0"
    @FlexD var end_time: String = "0"
    @FlexD var duration_minutes: Int = 0
    @FlexD var exercise_type: String = "Workout"
    @Flex var title: String? = nil
    @Flex var avg_heart_rate: Int? = nil
    @Flex var peak_heart_rate: Int? = nil
    @Flex var calories: Int? = nil
    @Flex var distance_meters: Double? = nil
    var hr_samples: [HrSample]? = nil
    @Flex var notes: String? = nil
    @FlexD var is_hidden: Bool = false
    @Flex var author_name: String? = nil
}

struct FriendDto: Codable, Identifiable {
    @FlexD var id: String = ""
    @FlexD var user_id: String = ""
    @FlexD var friend_id: String = ""
    @FlexD var status: String = ""
    @Flex var friend_name: String? = nil
    @Flex var friend_nickname: String? = nil
    @Flex var friend_email: String? = nil
    @Flex var friend_user_id: String? = nil
    @Flex var friend_avatar_url: String? = nil

    var displayName: String { friend_nickname ?? friend_name ?? friend_email ?? "?" }
    var initial: String { String((friend_nickname ?? friend_name ?? "?").prefix(1)).uppercased() }
}

struct NotificationDto: Codable, Identifiable {
    @FlexD var id: String = ""
    @FlexD var type: String = ""
    @FlexD var message: String = ""
    @FlexD var is_read: Bool = false
    @Flex var created_at: String? = nil
    @Flex var link_id: String? = nil
}

struct GroupDto: Codable, Identifiable {
    @FlexD var id: String = ""
    @FlexD var name: String = ""
    @FlexD var color: String = "#3b82f6"
    @FlexD var member_count: Int = 0
    @Flex var owner_id: String? = nil
}

struct SocialCommentDto: Codable, Identifiable {
    @FlexD var id: String = UUID().uuidString
    @FlexD var post_id: String = ""
    @FlexD var user_id: String = ""
    @FlexD var content: String = ""
    @Flex var author_name: String? = nil
    @Flex var author_nickname: String? = nil
    @Flex var created_at: String? = nil
}

struct UserSearchResult: Codable, Identifiable {
    @FlexD var id: String = ""
    @Flex var name: String? = nil
    @Flex var nickname: String? = nil
    @Flex var email: String? = nil
}

struct PrEntryDto: Codable {
    @FlexD var exercise: String = ""
    @Flex var max_weight: Double? = nil
}

struct UserProfileDto: Codable {
    @FlexD var id: String = ""
    @Flex var name: String? = nil
    @Flex var nickname: String? = nil
    @Flex var email: String? = nil
    @FlexD var total_workouts: Int = 0
    @FlexD var total_sets: Int = 0
    @Flex var favorite_workout: String? = nil
    @Flex var bio: String? = nil
    @Flex var avatar_url: String? = nil
    @FlexD var is_public: Bool = false
    @FlexD var is_self: Bool = false
    @FlexD var friendship_status: String = "none"
    @Flex var friendship_id: String? = nil
    var prs: [PrEntryDto]? = nil
    @FlexD var friends_count: Int = 0
    var recent_sessions: [ExerciseSessionDto]? = nil
    var recent_posts: [SocialPostDto]? = nil
}

struct GetFeedResponse: Decodable { var posts: [SocialPostDto]? }
struct GetFriendsResponse: Decodable { var friends: [FriendDto]? }
struct GetNotificationsResponse: Decodable { var notifications: [NotificationDto]? }
struct GetGroupsResponse: Decodable { var groups: [GroupDto]? }
struct SearchUsersResponse: Decodable { var users: [UserSearchResult]? }
struct GetCommentsResponse: Decodable { var comments: [SocialCommentDto]? }
struct GetProfileResponse: Decodable { var profile: UserProfileDto }

/// Partial update: nil fields are omitted from JSON and left unchanged server-side.
struct UpdateProfileRequest: Encodable {
    @Flex var nickname: String? = nil
    @Flex var isPublic: Bool? = nil
    @Flex var bio: String? = nil
    @Flex var avatarUrl: String? = nil
    @Flex var gender: String? = nil
    @Flex var weightLbs: Double? = nil
    /// JSON string shared with the web app: {steps, workouts, activeKcal, activeMinutes, ...}
    @Flex var goals: String? = nil
}

struct MyProfileDto: Codable {
    @Flex var id: String? = nil
    @Flex var name: String? = nil
    @Flex var email: String? = nil
    @Flex var nickname: String? = nil
    @Flex var gender: String? = nil
    @Flex var weightLbs: Double? = nil
    @Flex var isPublic: Bool? = nil
    @Flex var bio: String? = nil
    @Flex var avatarUrl: String? = nil
    @Flex var goals: String? = nil
}

struct GetMyProfileResponse: Decodable { var profile: MyProfileDto }

struct CreatePostRequest: Encodable {
    var postType: String = "workout"
    @Flex var sessionId: String? = nil
    @Flex var comment: String? = nil
    @Flex var groupId: String? = nil
    @Flex var linkedSessionId: String? = nil
    var payload: ProgressPayloadDto? = nil
}

struct FriendActionRequest: Encodable { let action: String }
struct FriendRequestBody: Encodable { let friendId: String }
struct CommentBody: Encodable { let content: String }

// MARK: - Versus

struct CompareCardDto: Codable {
    @FlexD var id: String = ""
    @FlexD var name: String = "Athlete"
    @Flex var avatarUrl: String? = nil
}

struct CompareCategoryDto: Codable, Identifiable {
    var id: String { key + label }
    @FlexD var key: String = ""
    @FlexD var label: String = ""
    @FlexD var unit: String = ""
    @FlexD var me: Double = 0
    @FlexD var them: Double = 0
    @FlexD var winner: String = "tie"
}

struct LiftSideDto: Codable {
    @FlexD var best: Double = 0
    @FlexD var bestWeight: Double = 0
    var series: [WeekPointDto]? = nil
}

struct SharedLiftDto: Codable, Identifiable {
    var id: String { key + exercise }
    @FlexD var exercise: String = ""
    @FlexD var key: String = ""
    @FlexD var winner: String = "tie"
    var me: LiftSideDto? = nil
    var them: LiftSideDto? = nil
}

struct ScoreDto: Codable {
    @FlexD var me: Int = 0
    @FlexD var them: Int = 0
}

struct CompareResponse: Codable {
    var me: CompareCardDto? = nil
    var them: CompareCardDto? = nil
    var categories: [CompareCategoryDto]? = nil
    var score: ScoreDto? = nil
    var lifts: [SharedLiftDto]? = nil
}

/// Daily goals stored inside the profile's `goals` JSON string (shared with the web app).
struct DailyGoals: Equatable {
    var steps = 10_000
    var activeKcal = 500
    var activeMinutes = 30

    static func parse(_ raw: String?) -> DailyGoals {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return DailyGoals() }
        func n(_ k: String) -> Int? {
            let v: Double?
            if let d = obj[k] as? Double { v = d }
            else if let s = obj[k] as? String { v = Double(s) }
            else if let i = obj[k] as? Int { v = Double(i) }
            else { v = nil }
            guard let v, v > 0 else { return nil }
            return Int(v)
        }
        return DailyGoals(steps: n("steps") ?? 10_000, activeKcal: n("activeKcal") ?? 500, activeMinutes: n("activeMinutes") ?? 30)
    }
}
