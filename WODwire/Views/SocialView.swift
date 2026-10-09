import SwiftUI

/// Identifiable wrapper so a user id can drive `.fullScreenCover(item:)`.
struct ProfileTarget: Identifiable, Hashable { let id: String }

/// Prefill for the Create Post sheet ("I did this too!" sets a linked session + comment).
struct CreatePrefill: Identifiable {
    let id = UUID()
    var linkedSessionId: String? = nil
    var comment: String = ""
}

// MARK: - Social screen (Android SocialScreen.kt)

struct SocialView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @State private var tab = 0
    @State private var showNotifications = false
    @State private var notificationSnapshot: [NotificationDto] = []
    @State private var showShareProgress = false
    @State private var createPrefill: CreatePrefill?
    @State private var profileTarget: ProfileTarget?
    @State private var showChallengePrompt = false
    @Environment(\.openURL) private var openURL

    private var unreadCount: Int { vm.notifications.filter { !$0.is_read }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.currentUser == nil {
                Spacer()
                Text("Sign in to use Social features")
                    .font(.system(size: 15))
                    .foregroundStyle(p.dim)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                tabBar
                Group {
                    switch tab {
                    case 0:
                        FeedTab(
                            onOpenProfile: { profileTarget = ProfileTarget(id: $0) },
                            onDidThisToo: { sid, text in createPrefill = CreatePrefill(linkedSessionId: sid, comment: text) }
                        )
                    case 1:
                        FriendsTab(onOpenProfile: { profileTarget = ProfileTarget(id: $0) })
                    default:
                        GroupsTab(onOpenProfile: { profileTarget = ProfileTarget(id: $0) })
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(p.bg.ignoresSafeArea())
        .task(id: vm.currentUser?.userId) {
            guard vm.currentUser != nil else { return }
            await vm.fetchSocialAll()
            // Android polls feed / friends / notifications every 15 s while Social is visible.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                await vm.fetchFeed()
                await vm.fetchFriends()
                await vm.fetchNotifications()
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet(notifications: notificationSnapshot) { n in
                showNotifications = false
                vm.openNotification(n)
            }
            .themed(vm)
        }
        .onAppear { consumeRoute() }
        .onChange(of: vm.notificationRoute) { _, _ in consumeRoute() }
        .confirmationDialog("Challenges", isPresented: $showChallengePrompt, titleVisibility: .visible) {
            Button("Open Challenges") {
                if let url = URL(string: "https://wodwire.com/#social-challenges") { openURL(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Accept, track and compare challenges on the WODwire dashboard.")
        }
        .sheet(item: $createPrefill) { pre in
            CreatePostSheet(prefill: pre, onPosted: { tab = 0 })
                .themed(vm)
        }
        .sheet(isPresented: $showShareProgress) {
            ShareProgressSheet()
                .themed(vm)
        }
        .fullScreenCover(item: $profileTarget) { t in
            UserProfileView(userId: t.id)
                .themed(vm)
        }
    }

    /// Applies a notification tap (from the banner, bell list or a system notification).
    private func consumeRoute() {
        guard let route = vm.notificationRoute else { return }
        vm.notificationRoute = nil
        withAnimation(.easeInOut(duration: 0.2)) { tab = route.socialTab }
        if route == .challenge { showChallengePrompt = true }
        Task { await vm.fetchSocialAll() }
    }

    private var header: some View {
        HStack(spacing: 18) {
            ScreenTitle(text: "SOCIAL")
            Spacer()
            if vm.currentUser != nil {
                Button {
                    notificationSnapshot = vm.notifications
                    showNotifications = true
                    if unreadCount > 0 { vm.markNotificationsRead() }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(p.text)
                        if unreadCount > 0 {
                            Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Brand.likeRed, in: Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                }
                Button { showShareProgress = true } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 20))
                        .foregroundStyle(Brand.cyanGlow)
                }
                Button { createPrefill = CreatePrefill() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Brand.deepOrange)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { tab = i }
                } label: {
                    VStack(spacing: 8) {
                        Text(["Feed", "Friends", "Groups"][i])
                            .font(.system(size: 14, weight: tab == i ? .bold : .medium))
                            .foregroundStyle(tab == i ? Brand.deepOrange : p.dim)
                        Rectangle()
                            .fill(tab == i ? Brand.deepOrange : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(p.dim.opacity(0.15)).frame(height: 1) }
    }
}

extension View {
    /// Re-applies the app theme + view model inside sheets / full-screen covers.
    func themed(_ vm: PhoneViewModel) -> some View {
        self
            .environmentObject(vm)
            .environment(\.palette, vm.isDarkMode ? Palette.dark : Palette.light)
            .preferredColorScheme(vm.isDarkMode ? .dark : .light)
    }
}

// MARK: - Feed

struct FeedTab: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    let onOpenProfile: (String) -> Void
    let onDidThisToo: (String, String) -> Void

    var body: some View {
        ScrollView {
            if vm.feed.isEmpty {
                VStack(spacing: 8) {
                    Text("No posts yet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(p.text)
                    Text("Share a workout or add friends!")
                        .font(.system(size: 14))
                        .foregroundStyle(p.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(vm.feed) { post in
                        PostCard(post: post, onOpenProfile: onOpenProfile, onDidThisToo: onDidThisToo)
                            .onAppear {
                                // Load more when one of the last 3 posts scrolls into view.
                                if vm.feed.suffix(3).contains(where: { $0.id == post.id }) {
                                    Task { await vm.loadMoreFeed() }
                                }
                            }
                    }
                }
                .padding(16)
            }
        }
        .refreshable { await vm.fetchFeed() }
    }
}

// MARK: - Post card

struct PostCard: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    let post: SocialPostDto
    var onOpenProfile: (String) -> Void = { _ in }
    var onDidThisToo: ((String, String) -> Void)? = nil

    @State private var showCommentDialog = false
    @State private var commentText = ""
    @State private var expandedComments: [SocialCommentDto]?
    @State private var loadingComments = false

    private var isMine: Bool { post.user_id == vm.currentUser?.userId }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            if let s = post.session {
                sessionBox(s).padding(.bottom, 8)
            }
            if let s = post.session, let linked = post.linked_session {
                linkedRow(s, linked).padding(.bottom, 8)
            }
            if post.post_type == "progress", let payload = post.payload {
                ProgressPostCard(payload: payload).padding(.bottom, 8)
            }
            if post.post_type == "badge", let badge = post.badge_name {
                HStack(spacing: 12) {
                    Text("🏆").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge).font(.system(size: 14, weight: .bold)).foregroundStyle(p.text)
                        if let cat = post.badge_category {
                            Text(cat).font(.system(size: 12)).foregroundStyle(p.dim)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(p.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 8)
            }
            if let c = post.comment, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(c)
                    .font(.system(size: 14))
                    .foregroundStyle(p.text)
                    .lineSpacing(4)
                    .padding(.bottom, 8)
            }

            Rectangle().fill(p.dim.opacity(0.15)).frame(height: 1).padding(.bottom, 8)
            actions
            comments
        }
        .padding(16)
        .background(isMine ? p.myPostTint : p.glass)
        .overlay(alignment: .leading) {
            if isMine { Rectangle().fill(Brand.myPostAccent).frame(width: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isMine ? Brand.myPostAccent.opacity(0.45) : p.dim.opacity(0.15), lineWidth: 1)
        )
        .alert("Add a comment", isPresented: $showCommentDialog) {
            TextField("Write your comment here...", text: $commentText)
            Button("Cancel", role: .cancel) { commentText = "" }
            Button("Post") {
                let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    vm.addComment(postId: post.id, content: text)
                    expandedComments = nil
                }
                commentText = ""
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { onOpenProfile(post.user_id) } label: {
                UserAvatar(avatarUrl: post.author_avatar_url, name: post.displayName, size: 36)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                    if isMine {
                        Text("You")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Brand.myPostAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(Brand.myPostAccent.opacity(0.2), in: Capsule())
                    }
                }
                if let d = Fmt.serverDate(post.created_at) {
                    Text(d).font(.system(size: 11)).foregroundStyle(p.dim)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenProfile(post.user_id) }
            Spacer(minLength: 4)
            if let gn = post.group_name {
                let gc = Color(hexString: post.group_color) ?? Brand.electricBlue
                Text(gn)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gc)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(gc.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func sessionBox(_ s: SessionSnapshotDto) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.exercise_type).font(.system(size: 14, weight: .bold)).foregroundStyle(Brand.deepOrange)
                    Text("\(s.duration_minutes) min").font(.system(size: 12)).foregroundStyle(p.dim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.calories ?? 0) kcal").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text)
                    if let hr = s.avg_heart_rate {
                        Text("♡ \(hr) bpm").font(.system(size: 12)).foregroundStyle(Brand.likeRed)
                    }
                }
            }
            let samples = s.hr_samples ?? []
            if samples.count > 1 {
                let lo = samples.map { $0.bpm }.min() ?? 60
                let hi = samples.map { $0.bpm }.max() ?? 180
                InteractiveHRGraph(
                    samples: samples,
                    durationSec: max(s.duration_minutes * 60, samples.last?.timeOffsetSec ?? 1, 1),
                    minHr: max(lo - 5, 30),
                    maxHr: max(hi + 5, lo + 10),
                    interactive: false,
                    paddingX: 2
                )
                .frame(height: 60)
                .padding(.top, 12)
            }
        }
        .padding(12)
        .background(p.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func linkedRow(_ s: SessionSnapshotDto, _ linked: SessionSnapshotDto) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(post.author_name ?? "You").font(.system(size: 11)).foregroundStyle(p.dim)
                Text("\(s.calories ?? 0) kcal").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
                Text("\(s.duration_minutes) min").font(.system(size: 12)).foregroundStyle(Brand.deepOrange)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(p.dim.opacity(0.3)).frame(width: 1, height: 40)
            VStack(spacing: 2) {
                Text(linked.author_name ?? "Friend").font(.system(size: 11)).foregroundStyle(p.dim)
                Text("\(linked.calories ?? 0) kcal").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
                Text("\(linked.duration_minutes) min").font(.system(size: 12)).foregroundStyle(Brand.purple)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(p.dim.opacity(0.3)).frame(width: 1, height: 40)
            VStack(spacing: 2) {
                Text("Great job!").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.success)
                Text("Both crushed it 💪").font(.system(size: 11)).foregroundStyle(p.dim)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Brand.electricBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.electricBlue.opacity(0.2), lineWidth: 1))
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button { vm.toggleLike(post.id) } label: {
                HStack(spacing: 4) {
                    Image(systemName: post.user_liked > 0 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 14))
                    Text("\(post.like_count)").font(.system(size: 13))
                }
                .foregroundStyle(post.user_liked > 0 ? Brand.deepOrange : p.dim)
            }
            Button { showCommentDialog = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble").font(.system(size: 14))
                    Text("\(post.comment_count)").font(.system(size: 13))
                }
                .foregroundStyle(p.dim)
            }
            Spacer()
            if post.post_type == "workout", let sid = post.session_id, !isMine, let onDidThisToo {
                Button { onDidThisToo(sid, "I did this workout too! 💪") } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 13))
                        Text("I did this too!").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Brand.cyanGlow)
                }
            }
            if isMine {
                Button { vm.deletePost(post.id) } label: {
                    Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(p.dim.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var comments: some View {
        let shown = expandedComments ?? post.recent_comments ?? []
        let recentCount = post.recent_comments?.count ?? 0
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(p.dim.opacity(0.1)).frame(height: 1).padding(.vertical, 6)
                ForEach(shown) { c in
                    (Text("\(c.author_nickname ?? c.author_name ?? "Unknown"):  ").bold().foregroundColor(p.text)
                        + Text(c.content).foregroundColor(p.dim))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if expandedComments == nil && post.comment_count > recentCount {
                    if loadingComments {
                        Text("Loading...").font(.system(size: 13)).foregroundStyle(p.dim).padding(.top, 4)
                    } else {
                        Button("View all \(post.comment_count) comments") { loadAllComments() }
                            .font(.system(size: 13)).foregroundStyle(p.dim).buttonStyle(.plain).padding(.top, 4)
                    }
                } else if expandedComments != nil && post.comment_count > recentCount {
                    Button("Collapse comments") { expandedComments = nil }
                        .font(.system(size: 13)).foregroundStyle(p.dim).buttonStyle(.plain).padding(.top, 4)
                }
            }
            .padding(.top, 6)
        }
    }

    private func loadAllComments() {
        loadingComments = true
        Task {
            if let all = try? await APIClient.shared.getComments(postId: post.id) { expandedComments = all }
            loadingComments = false
        }
    }
}

// MARK: - Progress post card

struct ProgressPostCard: View {
    @Environment(\.palette) private var p
    let payload: ProgressPayloadDto

    var body: some View {
        let up = payload.pctGain >= 0
        let pctText = (up ? "+" : "") + String(format: "%.1f%%", payload.pctGain)
        let best = payload.bestE1rm ?? payload.currentE1rm
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("📈 " + payload.exercise.uppercased())
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                Spacer()
                Text(pctText)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(up ? Brand.success : Brand.deepOrange)
            }
            Text("\(Fmt.trim(payload.startE1rm.rounded())) → \(Fmt.trim(best.rounded())) lb e1RM")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(p.text)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(p.dim)
            let values = (payload.series ?? []).map { $0.e1rm }
            if values.count > 1 {
                TrendLine(values: values)
                    .frame(height: 56)
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Color(hex: 0xFF8A1F).opacity(0.28), Color(hex: 0xE11D48).opacity(0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var subtitle: String {
        var s = "over \(payload.weeks) week\(payload.weeks == 1 ? "" : "s")"
        if let bw = payload.bestWeight, bw > 0 { s += " · heaviest set \(Fmt.trim(bw)) lb" }
        return s
    }
}

/// Small gradient trend line with a white dot on the last point.
struct TrendLine: View {
    let values: [Double]
    var colors: [Color] = [Color(hex: 0xFF8A1F), Color(hex: 0xE11D48)]

    var body: some View {
        GeometryReader { geo in
            let pts = points(geo.size)
            ZStack {
                Path { path in
                    guard let first = pts.first else { return }
                    path.move(to: first)
                    for pt in pts.dropFirst() { path.addLine(to: pt) }
                }
                .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(Color.white).frame(width: 8, height: 8).position(last)
                }
            }
        }
    }

    private func points(_ size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let range = max(hi - lo, 1)
        let inset: CGFloat = 5
        let w = size.width - inset * 2
        let h = size.height - inset * 2
        return values.indices.map { i in
            CGPoint(x: inset + w * CGFloat(i) / CGFloat(values.count - 1),
                    y: inset + h * (1 - CGFloat((values[i] - lo) / range)))
        }
    }
}

// MARK: - Notifications

struct NotificationsSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let notifications: [NotificationDto]
    var onSelect: (NotificationDto) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notifications").font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
                Spacer()
                Button("Close") { dismiss() }.foregroundStyle(Brand.cyanGlow)
            }
            if notifications.isEmpty {
                Spacer()
                Text("No notifications yet").foregroundStyle(p.dim).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(notifications) { n in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon(n.type))
                                    .font(.system(size: 16))
                                    .foregroundStyle(Brand.cyanGlow)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.message).font(.system(size: 14)).foregroundStyle(p.text)
                                    if let d = Fmt.serverDate(n.created_at) {
                                        Text(d).font(.system(size: 11)).foregroundStyle(p.dim)
                                    }
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(n.is_read ? p.glass : Brand.cyanGlow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(n) }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(p.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "comment": return "text.bubble.fill"
        case "linked_session": return "link"
        case "group_post": return "person.3.fill"
        default: return "bell.fill"
        }
    }
}

// MARK: - Friends

struct FriendsTab: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    let onOpenProfile: (String) -> Void

    @State private var query = ""
    @State private var results: [UserSearchResult] = []
    @State private var searching = false

    private var me: String { vm.currentUser?.userId ?? "" }
    private var pending: [FriendDto] { vm.friends.filter { $0.status == "pending" && $0.friend_id == me } }
    private var sent: [FriendDto] { vm.friends.filter { $0.status == "pending" && $0.user_id == me } }
    private var accepted: [FriendDto] { vm.friends.filter { $0.status == "accepted" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    OutlinedField(placeholder: "Search users...", text: $query)
                        .submitLabel(.search)
                        .onSubmit(search)
                    Button(action: search) {
                        Text(searching ? "..." : "Search")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Brand.deepOrange, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                if !results.isEmpty {
                    section("SEARCH RESULTS") {
                        ForEach(results) { u in
                            row(name: u.nickname ?? u.name ?? u.email ?? "?", avatar: nil, subtitle: u.email) {
                                smallButton("Add", Brand.cyanGlow) {
                                    vm.sendFriendRequest(u.id)
                                    results.removeAll { $0.id == u.id }
                                }
                            }
                        }
                    }
                }

                if !pending.isEmpty {
                    section("PENDING REQUESTS") {
                        ForEach(pending) { f in
                            row(name: f.displayName, avatar: f.friend_avatar_url, subtitle: nil) {
                                HStack(spacing: 6) {
                                    smallButton("Accept", Brand.success) { vm.handleFriendAction(id: f.id, action: "accept") }
                                    smallButton("Decline", Brand.deepOrange) { vm.handleFriendAction(id: f.id, action: "decline") }
                                }
                            }
                        }
                    }
                }

                if !sent.isEmpty {
                    section("SENT REQUESTS") {
                        ForEach(sent) { f in
                            row(name: f.displayName, avatar: f.friend_avatar_url, subtitle: nil) {
                                Text("Waiting...").font(.system(size: 12)).foregroundStyle(p.dim)
                            }
                        }
                    }
                }

                section("MY FRIENDS") {
                    if accepted.isEmpty {
                        Text("No friends yet. Search for users above!")
                            .font(.system(size: 14))
                            .foregroundStyle(p.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(accepted) { f in
                            row(name: f.displayName, avatar: f.friend_avatar_url, subtitle: f.friend_email) {
                                smallButton("Remove", Brand.likeRed) {
                                    vm.removeFriend(f.friend_user_id ?? f.friend_id)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let target = f.friend_user_id ?? (f.friend_id.isEmpty ? f.user_id : f.friend_id)
                                onOpenProfile(target)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await vm.fetchFriends() }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        searching = true
        Task {
            results = (try? await APIClient.shared.searchUsers(q)) ?? []
            searching = false
            if results.isEmpty { vm.showToast("No users found") }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            content()
        }
    }

    private func row<Trailing: View>(name: String, avatar: String?, subtitle: String?, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            UserAvatar(avatarUrl: avatar, name: name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(p.dim).lineLimit(1)
                }
            }
            Spacer()
            trailing()
        }
        .padding(12)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 12))
    }

    private func smallButton(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Groups

struct GroupsTab: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    let onOpenProfile: (String) -> Void
    @State private var openGroup: GroupDto?

    var body: some View {
        ScrollView {
            if vm.groups.isEmpty {
                VStack(spacing: 8) {
                    Text("No groups yet").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
                    Text("Create groups from the web app").font(.system(size: 14)).foregroundStyle(p.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.groups) { g in
                        let color = Color(hexString: g.color) ?? Brand.myPostAccent
                        Button { openGroup = g } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(color)
                                    Text(String(g.name.prefix(1)).uppercased())
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                                    Text("\(g.member_count) members").font(.system(size: 12)).foregroundStyle(p.dim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(p.dim)
                            }
                            .padding(14)
                            .background(p.glass, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .refreshable { await vm.fetchGroups() }
        .sheet(item: $openGroup) { g in
            GroupPostsSheet(group: g, onOpenProfile: onOpenProfile)
                .themed(vm)
        }
    }
}

struct GroupPostsSheet: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let group: GroupDto
    let onOpenProfile: (String) -> Void

    var body: some View {
        let posts = vm.feed.filter { $0.group_id == group.id }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(Color(hexString: group.color) ?? Brand.myPostAccent).frame(width: 14, height: 14)
                Text(group.name).font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
                Spacer()
                Button("Close") { dismiss() }.foregroundStyle(Brand.cyanGlow)
            }
            if posts.isEmpty {
                Spacer()
                Text("No posts in this group yet").foregroundStyle(p.dim).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(posts) { post in
                            PostCard(post: post, onOpenProfile: { id in
                                dismiss()
                                onOpenProfile(id)
                            })
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(p.bg.ignoresSafeArea())
    }
}

// MARK: - Create post

struct CreatePostSheet: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let prefill: CreatePrefill
    let onPosted: () -> Void

    @State private var selectedSessionId: String?
    @State private var comment = ""

    private var recentSessions: [ExerciseSessionDto] {
        Array(vm.sessions.filter { !$0.isHidden }.sorted { $0.startTime > $1.startTime }.prefix(20))
    }

    /// Friends whose name starts with the "@partial" word currently being typed.
    private var mentionSuggestions: [FriendDto] {
        guard let last = comment.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("@") else { return [] }
        let q = last.dropFirst().lowercased()
        return Array(vm.friends.filter { $0.status == "accepted" }
            .filter { q.isEmpty || $0.displayName.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(q) }
            .prefix(5))
    }

    private var canPost: Bool {
        selectedSessionId != nil || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Attach Workout (optional)").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.dim)
                    Menu {
                        Button("-- None --") { selectedSessionId = nil }
                        ForEach(recentSessions) { s in
                            Button(label(for: s)) { selectedSessionId = s.id }
                        }
                    } label: {
                        HStack {
                            Text(selectedLabel).foregroundStyle(p.text).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").foregroundStyle(p.dim)
                        }
                        .font(.system(size: 14))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(p.dim.opacity(0.5), lineWidth: 1))
                    }

                    if prefill.linkedSessionId != nil {
                        Label("Linked to your friend's workout", systemImage: "link")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.purple)
                    }

                    Text("Comment").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.dim)
                    TextField("Great session today! 💪", text: $comment, axis: .vertical)
                        .lineLimit(4...8)
                        .font(.system(size: 14))
                        .foregroundStyle(p.text)
                        .tint(Brand.cyanGlow)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(p.dim.opacity(0.5), lineWidth: 1))

                    if !mentionSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(mentionSuggestions) { f in
                                Button { insertMention(f) } label: {
                                    HStack(spacing: 10) {
                                        UserAvatar(avatarUrl: f.friend_avatar_url, name: f.displayName, size: 26)
                                        Text(f.displayName).font(.system(size: 14)).foregroundStyle(p.text)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(p.menu, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }
            .background(p.bg.ignoresSafeArea())
            .navigationTitle("Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(p.dim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                        vm.createPost(sessionId: selectedSessionId, comment: text.isEmpty ? nil : text,
                                      groupId: nil, linkedSessionId: prefill.linkedSessionId)
                        onPosted()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(canPost ? Brand.deepOrange : p.dim)
                    .disabled(!canPost)
                }
            }
        }
        .onAppear { comment = prefill.comment }
    }

    private func label(for s: ExerciseSessionDto) -> String {
        "\(Fmt.date(s.startDate, "MMM d")) — \(s.exerciseType) (\(s.durationMinutes) min)"
    }

    private var selectedLabel: String {
        guard let id = selectedSessionId, let s = vm.sessions.first(where: { $0.id == id }) else { return "-- None --" }
        return label(for: s)
    }

    private func insertMention(_ f: FriendDto) {
        var words = comment.split(separator: " ", omittingEmptySubsequences: false).map { String($0) }
        if !words.isEmpty { words.removeLast() }
        words.append("@" + f.displayName.replacingOccurrences(of: " ", with: ""))
        comment = words.joined(separator: " ") + " "
    }
}

// MARK: - Share lift progress

struct ShareProgressSheet: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var caption = ""
    @State private var sharing = false

    /// Exercises with weighted sets, most-logged first.
    private var exercises: [String] {
        var counts: [String: Int] = [:]
        for log in vm.logs where log.weightLbs > 0 {
            let name = log.exercise.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { counts[name, default: 0] += 1 }
        }
        return counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share lift progress").font(.system(size: 18, weight: .bold)).foregroundStyle(p.text)
            if exercises.isEmpty {
                Text("Log some sets first — then show off the gains.")
                    .font(.system(size: 14)).foregroundStyle(p.dim)
            } else {
                ScrollView {
                    FlowLayout(spacing: 8) {
                        ForEach(exercises, id: \.self) { ex in
                            ChipButton(text: ex, selected: selected == ex) { selected = ex }
                        }
                    }
                }
                .frame(maxHeight: 180)

                VStack(alignment: .trailing, spacing: 4) {
                    OutlinedField(placeholder: "Caption (optional)", text: $caption, axis: .vertical)
                        .onChange(of: caption) { _, v in
                            if v.count > 280 { caption = String(v.prefix(280)) }
                        }
                    Text("\(caption.count)/280").font(.system(size: 11)).foregroundStyle(p.dim)
                }
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }.foregroundStyle(p.dim)
                Spacer()
                Button {
                    guard let ex = selected else { return }
                    sharing = true
                    Task {
                        let result = await vm.shareLiftProgress(exercise: ex, caption: caption)
                        sharing = false
                        vm.showToast(result.1)
                        if result.0 { dismiss() }
                    }
                } label: {
                    Text(sharing ? "Sharing…" : "Share")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background((selected == nil || sharing) ? p.dim : Brand.deepOrange, in: Capsule())
                }
                .disabled(selected == nil || sharing)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(p.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

/// Minimal wrapping layout for chips (iOS 16+ Layout protocol).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
