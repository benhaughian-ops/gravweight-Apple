import SwiftUI

/// Full-screen public profile (Android UserProfileScreen.kt).
struct UserProfileView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let userId: String

    @State private var profile: UserProfileDto?
    @State private var errorText: String?
    @State private var loading = true
    @State private var showEdit = false
    @State private var versusTarget: ProfileTarget?
    @State private var requestSent = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if loading && profile == nil {
                Spacer()
                ProgressView().tint(Brand.cyanGlow)
                Spacer()
            } else if let errorText {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.system(size: 32)).foregroundStyle(p.dim)
                    Text(errorText).font(.system(size: 15)).foregroundStyle(p.dim).multilineTextAlignment(.center)
                }
                .padding(32)
                Spacer()
            } else if let profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard(profile)
                        statsRow(profile)
                        if let fav = profile.favorite_workout, !fav.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                SectionLabel(text: "FAVORITE WORKOUT")
                                GlassCard(radius: 12, padding: 14) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "star.fill").foregroundStyle(Brand.cyanGlow)
                                        Text(fav).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                                    }
                                }
                            }
                        }
                        prsSection(profile)
                        sessionsSection(profile)
                        postsSection(profile)
                    }
                    .padding(16)
                }
                .refreshable { await load() }
            }
        }
        .background(p.bg.ignoresSafeArea())
        .task { await load() }
        .sheet(isPresented: $showEdit) {
            EditProfileSheet(initial: nil, onSaved: { Task { await load() } })
                .themed(vm)
        }
        .fullScreenCover(item: $versusTarget) { t in
            VersusView(friendId: t.id)
                .themed(vm)
        }
    }

    private var isSelf: Bool { profile?.is_self == true || userId == vm.currentUser?.userId }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(p.text)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text(isSelf ? "My Profile" : "Profile")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(p.text)
            Spacer()
            if isSelf {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Brand.cyanGlow)
                        .frame(width: 40, height: 40)
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            profile = try await APIClient.shared.getUserProfile(userId: userId)
            errorText = nil
        } catch let e as APIClient.HTTPError {
            switch e.code {
            case 403: errorText = "This profile is private"
            case 404: errorText = "User not found"
            default: errorText = "Couldn't load profile (HTTP \(e.code))"
            }
        } catch {
            errorText = "Couldn't load profile (HTTP 0)"
        }
    }

    // MARK: Header

    private func headerCard(_ u: UserProfileDto) -> some View {
        let name = u.nickname ?? u.name ?? u.email ?? "Athlete"
        return VStack(spacing: 10) {
            UserAvatar(avatarUrl: u.avatar_url, name: name, size: 88)
                .overlay(Circle().stroke(Brand.cyanGlow.opacity(0.6), lineWidth: 2))
            Text(name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(p.text)
                .multilineTextAlignment(.center)
            if !u.is_public {
                Label("Private profile", systemImage: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(p.dim)
            }
            if let bio = u.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(p.text.opacity(0.9))
                    .multilineTextAlignment(.center)
            } else if isSelf {
                Text("Add a bio so friends know what you're training for.")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(p.dim)
                    .multilineTextAlignment(.center)
            }
            if !isSelf {
                friendshipView(u)
                if u.friendship_status == "accepted" || u.is_public {
                    Button { versusTarget = ProfileTarget(id: u.id.isEmpty ? userId : u.id) } label: {
                        Text("⚔  Compare")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(Brand.myPostAccent, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private func friendshipView(_ u: UserProfileDto) -> some View {
        if u.friendship_status == "accepted" {
            Text("✓ Friends").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.success)
        } else if u.friendship_status == "pending_sent" || u.friendship_status == "sent" || requestSent {
            Text("Friend request sent").font(.system(size: 13)).foregroundStyle(p.dim)
        } else if u.friendship_status == "pending_received" || u.friendship_status == "received" {
            Text("Wants to be your friend — see the Friends tab")
                .font(.system(size: 13)).foregroundStyle(Brand.cyanGlow).multilineTextAlignment(.center)
        } else if u.friendship_status == "pending" {
            Text("Friend request pending").font(.system(size: 13)).foregroundStyle(p.dim)
        } else {
            Button {
                vm.sendFriendRequest(u.id.isEmpty ? userId : u.id)
                requestSent = true
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Brand.deepOrange, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Stats

    private func statsRow(_ u: UserProfileDto) -> some View {
        let diff = u.total_workouts - vm.sessions.count
        let vsText: String? = isSelf ? nil : (diff > 0 ? "+\(diff) vs You" : (diff < 0 ? "\(diff) vs You" : "Tied with You"))
        return HStack(spacing: 10) {
            stat("Workouts", "\(u.total_workouts)", Brand.cyanGlow, sub: vsText)
            stat("Sets", Fmt.thousands(u.total_sets), Brand.electricBlue, sub: nil)
            stat("Friends", "\(u.friends_count)", Brand.purple, sub: nil)
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color, sub: String?) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: 12)).foregroundStyle(p.dim)
            if let sub {
                Text(sub).font(.system(size: 10, weight: .semibold)).foregroundStyle(p.dim.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Sections

    private func prsSection(_ u: UserProfileDto) -> some View {
        let prs = (u.prs ?? []).filter { ($0.max_weight ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "PERSONAL RECORDS")
            GlassCard(radius: 12, padding: 14) {
                if prs.isEmpty {
                    Text("No personal records yet").font(.system(size: 14)).foregroundStyle(p.dim)
                } else {
                    VStack(spacing: 10) {
                        ForEach(prs.indices, id: \.self) { i in
                            HStack {
                                Text(prs[i].exercise).font(.system(size: 14)).foregroundStyle(p.text)
                                Spacer()
                                Text("\(Fmt.trim(prs[i].max_weight ?? 0)) lbs")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Brand.electricBlue)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionsSection(_ u: UserProfileDto) -> some View {
        let sessions = u.recent_sessions ?? []
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "RECENT SESSIONS")
                ForEach(sessions) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.displayTitle).font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.deepOrange)
                            Spacer()
                            Text(Fmt.date(s.startDate, "MMM d, yyyy")).font(.system(size: 12)).foregroundStyle(p.dim)
                        }
                        HStack(spacing: 14) {
                            Text("\(s.durationMinutes) min")
                            Text("\(s.calories ?? 0) kcal")
                            if let hr = s.avgHeartRate { Text("♡ \(hr) bpm").foregroundStyle(Brand.likeRed) }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(p.text)
                    }
                    .padding(12)
                    .background(p.session, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private func postsSection(_ u: UserProfileDto) -> some View {
        let posts = u.recent_posts ?? []
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "RECENT POSTS")
                ForEach(posts) { post in
                    PostCard(post: post)
                }
            }
        }
    }
}
