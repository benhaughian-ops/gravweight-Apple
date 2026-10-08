import SwiftUI
import PhotosUI
import ClerkKit
import ClerkKitUI

/// ACCOUNT tab (Android AccountScreen.kt): sign-in, profile, sync, health, progress, settings.
struct AccountView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p

    @State private var myProfile: MyProfileDto?
    @State private var profileError = false
    @State private var showEdit = false
    @State private var showManualProgress = false
    @State private var showAuthView = false
    @State private var signingIn = false
    @State private var profileTarget: ProfileTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenTitle(text: "ACCOUNT")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                if let user = vm.currentUser {
                    myProfileCard
                    signedInCard(user)
                    syncStatusCard
                    HStack(spacing: 10) {
                        outlineButton("Sign Out", Brand.likeRed) { vm.signOut() }
                        outlineButton("Add Manual Progress", Brand.cyanGlow) { showManualProgress = true }
                    }
                    healthCard
                    ProgressOverviewCard()
                } else {
                    signInCard
                }
                settingsCard
                volumeCard
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(p.bg.ignoresSafeArea())
        .task(id: vm.currentUser?.userId) { await loadProfile() }
        .sheet(isPresented: $showEdit) {
            EditProfileSheet(initial: myProfile, onSaved: { Task { await loadProfile() } })
                .themed(vm)
        }
        .sheet(isPresented: $showManualProgress) {
            ManualProgressSheet().themed(vm)
        }
        .sheet(isPresented: $showAuthView) {
            AuthView()
                .environment(Clerk.shared)
        }
        .fullScreenCover(item: $profileTarget) { t in
            UserProfileView(userId: t.id).themed(vm)
        }
    }

    private func loadProfile() async {
        guard vm.currentUser != nil else { myProfile = nil; return }
        do {
            myProfile = try await APIClient.shared.getMyProfile()
            profileError = false
        } catch {
            profileError = true
        }
    }

    // MARK: Signed out

    private var signInCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 34))
                    .foregroundStyle(Brand.cyanGlow)
                Text("Sign in to back up your workout logs")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(p.text)
                    .multilineTextAlignment(.center)
                Button {
                    signingIn = true
                    Task {
                        do { 
                            try await AuthBridge.signInWithGoogle() 
                            if Clerk.shared.user == nil {
                                showAuthView = true
                            }
                        }
                        catch { showAuthView = true }
                        signingIn = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("G").font(.system(size: 18, weight: .heavy))
                        Text(signingIn ? "Signing in..." : "Sign in with Google").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(signingIn)
                Button("More sign-in options") { showAuthView = true }
                    .font(.system(size: 13))
                    .foregroundStyle(p.dim)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Signed in

    private var myProfileCard: some View {
        let name = myProfile?.nickname ?? myProfile?.name ?? vm.currentUser?.name ?? "Athlete"
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "MY PROFILE")
                HStack(spacing: 14) {
                    UserAvatar(avatarUrl: myProfile?.avatarUrl, name: name, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: 18, weight: .bold)).foregroundStyle(p.text).lineLimit(1)
                        Group {
                            if profileError {
                                Text("Couldn't load profile — tap to retry")
                            } else if let bio = myProfile?.bio, !bio.isEmpty {
                                Text(bio)
                            } else {
                                Text("No bio yet")
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(p.dim)
                        .lineLimit(2)
                        if myProfile != nil {
                            let isPublic = myProfile?.isPublic ?? false
                            Label(isPublic ? "Public" : "Private", systemImage: isPublic ? "globe" : "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isPublic ? Brand.success : p.dim)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { if profileError { Task { await loadProfile() } } }
                HStack(spacing: 10) {
                    if profileError {
                        outlineButton("Retry", Brand.cyanGlow) { Task { await loadProfile() } }
                    } else {
                        outlineButton("View Profile", Brand.cyanGlow) {
                            if let id = myProfile?.id ?? vm.currentUser?.userId { profileTarget = ProfileTarget(id: id) }
                        }
                    }
                    outlineButton("Edit", Brand.electricBlue) { showEdit = true }
                }
            }
        }
    }

    private func signedInCard(_ user: PhoneViewModel.UserInfo) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Brand.cyanGlow.opacity(0.2))
                    Text(String((user.name.isEmpty ? "A" : user.name).prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Brand.cyanGlow)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name.isEmpty ? "Athlete" : user.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
                    Text(user.email).font(.system(size: 12)).foregroundStyle(p.dim).lineLimit(1)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(vm.logs.count)").font(.system(size: 20, weight: .heavy)).foregroundStyle(Brand.cyanGlow)
                    Text("LOGGED SETS").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(p.dim)
                }
            }
        }
    }

    private var syncStatusCard: some View {
        let (text, color, icon): (String, Color, String) = {
            switch vm.syncState {
            case .idle: return ("Not synced yet", p.dim, "icloud")
            case .syncing: return ("Syncing...", Brand.cyanGlow, "arrow.triangle.2.circlepath")
            case .success: return ("Synced to cloud", Brand.success, "checkmark.icloud.fill")
            case .error(let m): return ("Sync error: \(m)", Brand.likeRed, "exclamationmark.icloud.fill")
            }
        }()
        return GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
                Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(color).lineLimit(2)
                Spacer()
                Button { vm.syncNow() } label: {
                    Text("Sync")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(vm.syncState == .syncing ? p.dim : Brand.cyanGlow, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.syncState == .syncing)
            }
        }
    }

    private var healthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill").foregroundStyle(Brand.heartRed)
                    Text("Apple Health").font(.system(size: 16, weight: .bold)).foregroundStyle(p.text)
                }
                Text("Sync steps and heart rate to your dashboard")
                    .font(.system(size: 13)).foregroundStyle(p.dim)
                Text("Last sync: \(Fmt.ago(vm.lastHealthSync))")
                    .font(.system(size: 11)).foregroundStyle(p.dim)
                Button {
                    Task { await vm.refreshHealth(force: true) }
                } label: {
                    Text(vm.healthRefreshing ? "SYNCING..." : "SYNC HEALTH DATA")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(vm.healthRefreshing ? p.dim : Brand.deepOrange, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(vm.healthRefreshing)
            }
        }
    }

    // MARK: Settings

    private var settingsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "SETTINGS")
                HStack {
                    Text("Units").font(.system(size: 15)).foregroundStyle(p.text)
                    Spacer()
                    Picker("Units", selection: Binding(get: { vm.isMetric }, set: { vm.setMetric($0) })) {
                        Text("LBS").tag(false)
                        Text("KG").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                toggleRow("Jokes Mode", $vm.isJokeMode)
                toggleRow("Dark Mode", $vm.isDarkMode)
            }
        }
    }

    private var volumeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "VOLUME ANALYSIS")
                toggleRow("Lifting Progress", $vm.showLiftingGraph)
                toggleRow("Body Composition", $vm.showBodyCompGraph)
                toggleRow("VO2 Max", $vm.showVo2MaxGraph)
            }
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(title).font(.system(size: 15)).foregroundStyle(p.text)
        }
        .tint(Brand.cyanGlow)
    }

    private func outlineButton(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress overview

struct ProgressOverviewCard: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @State private var expanded = true
    @State private var range = "1W"

    private var cutoff: Date? {
        switch range {
        case "1W": return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case "1M": return Calendar.current.date(byAdding: .month, value: -1, to: Date())
        default: return nil
        }
    }

    var body: some View {
        let cutKey = cutoff.map { HealthKitManager.dayKey($0) } ?? ""
        let metrics = vm.healthMetrics.filter { $0.date >= cutKey }
        let workouts = vm.sessions.filter { s in cutoff.map { s.startDate >= $0 } ?? true }.count
        let stepDays = metrics.filter { $0.steps > 0 }
        let avgSteps = stepDays.isEmpty ? 0 : stepDays.map { $0.steps }.reduce(0, +) / stepDays.count
        let calDays = metrics.compactMap { $0.calories }.filter { $0 > 0 }
        let avgCal = calDays.isEmpty ? 0 : calDays.reduce(0, +) / calDays.count
        let latestWeight = vm.healthMetrics.sorted { $0.date > $1.date }.compactMap { $0.weightLbs }.first
            ?? vm.userProgress.sorted { $0.date > $1.date }.compactMap { $0.weightLbs }.first

        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                    HStack {
                        Text("Progress Overview").font(.system(size: 16, weight: .bold)).foregroundStyle(p.text)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(p.dim)
                    }
                }
                .buttonStyle(.plain)
                if expanded {
                    RangeChips(ranges: ["1W", "1M", "All Time"], selected: $range)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        tile("Workouts", "\(workouts)", Brand.electricBlue)
                        tile("Avg Steps", Fmt.thousands(avgSteps), Brand.deepOrange)
                        tile("Avg Calories", Fmt.thousands(avgCal), Brand.cyanGlow)
                        tile("Latest Weight", weightText(latestWeight), p.text)
                    }
                }
            }
        }
    }

    private func weightText(_ lbs: Double?) -> String {
        guard let lbs else { return "--" }
        return vm.isMetric ? String(format: "%.1f kg", lbs / 2.2046) : "\(Int(lbs.rounded())) lbs"
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .heavy)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12)).foregroundStyle(p.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(p.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Edit profile

struct EditProfileSheet: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let initial: MyProfileDto?
    let onSaved: () -> Void

    @State private var loaded: MyProfileDto?
    @State private var avatar: String?
    @State private var originalAvatar: String?
    @State private var nickname = ""
    @State private var bio = ""
    @State private var gender = ""
    @State private var weight = ""
    @State private var steps = "10000"
    @State private var kcal = "500"
    @State private var minutes = "30"
    @State private var isPublic = false
    @State private var photoItem: PhotosPickerItem?
    @State private var saving = false
    @State private var errorText: String?
    @State private var didPopulate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 10) {
                        UserAvatar(avatarUrl: avatar, name: nickname.isEmpty ? (vm.currentUser?.name ?? "A") : nickname, size: 96)
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text("Change Photo").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.cyanGlow)
                            }
                            if avatar != nil {
                                Button("Remove") { avatar = nil }
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.likeRed)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    field("Display Name") {
                        OutlinedField(placeholder: "Display Name", text: $nickname)
                            .onChange(of: nickname) { _, v in if v.count > 40 { nickname = String(v.prefix(40)) } }
                    }
                    field("Bio") {
                        VStack(alignment: .trailing, spacing: 4) {
                            OutlinedField(placeholder: "Tell friends what you're training for", text: $bio, axis: .vertical)
                                .onChange(of: bio) { _, v in if v.count > 200 { bio = String(v.prefix(200)) } }
                            Text("\(bio.count)/200").font(.system(size: 11)).foregroundStyle(p.dim)
                        }
                    }
                    field("Gender") {
                        HStack(spacing: 8) {
                            ForEach(["Male", "Female", "Other"], id: \.self) { g in
                                ChipButton(text: g, selected: gender.lowercased() == g.lowercased()) { gender = g }
                            }
                        }
                    }
                    field("Body weight (lbs)") {
                        OutlinedField(placeholder: "e.g. 180", text: $weight, keyboard: .decimalPad)
                    }

                    SectionLabel(text: "DAILY GOALS").padding(.top, 4)
                    HStack(spacing: 10) {
                        field("Steps") { OutlinedField(placeholder: "10000", text: $steps, keyboard: .numberPad) }
                        field("Active kcal") { OutlinedField(placeholder: "500", text: $kcal, keyboard: .numberPad) }
                        field("Active min") { OutlinedField(placeholder: "30", text: $minutes, keyboard: .numberPad) }
                    }

                    Toggle(isOn: $isPublic) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Public Profile").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.text)
                            Text("Anyone can find you and view your profile. Friends can always see it.")
                                .font(.system(size: 12)).foregroundStyle(p.dim)
                        }
                    }
                    .tint(Brand.cyanGlow)

                    if let errorText {
                        Text(errorText).font(.system(size: 13)).foregroundStyle(Brand.likeRed)
                    }
                }
                .padding(20)
            }
            .background(p.bg.ignoresSafeArea())
            .navigationTitle("Edit My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(p.dim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving..." : "Save") { save() }
                        .fontWeight(.bold)
                        .foregroundStyle(Brand.cyanGlow)
                        .disabled(saving)
                }
            }
        }
        .task {
            guard !didPopulate else { return }
            var source = initial
            if source == nil { source = try? await APIClient.shared.getMyProfile() }
            populate(source)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let url = UserAvatar.dataUrl(from: img) {
                    avatar = url
                }
            }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.dim)
            content()
        }
    }

    private func populate(_ m: MyProfileDto?) {
        didPopulate = true
        loaded = m
        avatar = (m?.avatarUrl?.isEmpty == false) ? m?.avatarUrl : nil
        originalAvatar = avatar
        nickname = m?.nickname ?? m?.name ?? ""
        bio = m?.bio ?? ""
        gender = m?.gender ?? ""
        weight = m?.weightLbs.map { Fmt.trim($0) } ?? ""
        isPublic = m?.isPublic ?? false
        let g = DailyGoals.parse(m?.goals)
        steps = "\(g.steps)"
        kcal = "\(g.activeKcal)"
        minutes = "\(g.activeMinutes)"
    }

    /// Keeps unknown keys from the web app's goals JSON and overwrites the three daily goals.
    private func mergedGoals() -> (String?, DailyGoals) {
        var obj: [String: Any] = [:]
        if let raw = loaded?.goals, let data = raw.data(using: .utf8),
           let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            obj = existing
        }
        let g = DailyGoals(
            steps: Int(steps) ?? 10_000,
            activeKcal: Int(kcal) ?? 500,
            activeMinutes: Int(minutes) ?? 30
        )
        obj["steps"] = g.steps
        obj["activeKcal"] = g.activeKcal
        obj["activeMinutes"] = g.activeMinutes
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return (nil, g) }
        return (String(data: data, encoding: .utf8), g)
    }

    private func save() {
        saving = true
        errorText = nil
        let goals = mergedGoals()
        var req = UpdateProfileRequest()
        req.nickname = nickname.trimmingCharacters(in: .whitespaces)
        req.bio = bio
        req.gender = gender.isEmpty ? nil : gender
        req.weightLbs = Double(weight)
        req.isPublic = isPublic
        if avatar != originalAvatar { req.avatarUrl = avatar ?? "" }
        req.goals = goals.0
        Task {
            do {
                try await APIClient.shared.updateProfile(req)
                vm.goals = goals.1
                vm.showToast("Profile saved")
                onSaved()
                saving = false
                dismiss()
            } catch {
                errorText = "Save failed: \(error.localizedDescription)"
                saving = false
            }
        }
    }
}

// MARK: - Manual progress

struct ManualProgressSheet: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var date = HealthKitManager.dayKey(Date())
    @State private var weight = ""
    @State private var bodyFat = ""
    @State private var leanMass = ""
    @State private var bmr = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labeled("Date (YYYY-MM-DD)") { OutlinedField(placeholder: "YYYY-MM-DD", text: $date) }
                    labeled("Weight (lbs)") { OutlinedField(placeholder: "e.g. 180", text: $weight, keyboard: .decimalPad) }
                    labeled("Body Fat %") { OutlinedField(placeholder: "e.g. 15", text: $bodyFat, keyboard: .decimalPad) }
                    labeled("Lean Mass (lbs)") { OutlinedField(placeholder: "e.g. 150", text: $leanMass, keyboard: .decimalPad) }
                    labeled("BMR (kcal)") { OutlinedField(placeholder: "e.g. 1800", text: $bmr, keyboard: .numberPad) }
                }
                .padding(20)
            }
            .background(p.bg.ignoresSafeArea())
            .navigationTitle("Add Manual Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(p.dim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.addManualProgress(
                            date: date.trimmingCharacters(in: .whitespaces),
                            weight: Double(weight), bodyFat: Double(bodyFat),
                            leanMass: Double(leanMass), bmr: Int(bmr), notes: nil
                        )
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Brand.cyanGlow)
                    .disabled(date.count != 10)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func labeled<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.dim)
            content()
        }
    }
}
