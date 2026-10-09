import SwiftUI
import ClerkKit

@main
struct WODwireApp: App {
    @StateObject private var vm: PhoneViewModel

    init() {
        AuthBridge.configure()
        AppNotifications.shared.configure()
        _vm = StateObject(wrappedValue: PhoneViewModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .environment(Clerk.shared)
        }
    }
}

/// Applies the theme, watches Clerk for sign-in changes and refreshes health on foreground.
struct RootView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(Clerk.self) private var clerk
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let palette = vm.isDarkMode ? Palette.dark : Palette.light
        PhoneTabView()
            .environment(\.palette, palette)
            .preferredColorScheme(vm.isDarkMode ? .dark : .light)
            .overlay { ToastOverlay(message: vm.toast) }
            .overlay(alignment: .top) { NotificationBanner() }
            .onAppear {
                vm.onAuthChanged(AuthBridge.currentUser)
                let model = vm
                AppNotifications.shared.onTap = { [weak model] route, _ in model?.openRoute(route) }
            }
            .onChange(of: clerk.user?.id) { _, _ in vm.onAuthChanged(AuthBridge.currentUser) }
            // App-wide notification polling — alerts show on every tab, not just Social.
            .task(id: vm.currentUser?.userId) {
                guard vm.currentUser != nil else { return }
                AppNotifications.shared.requestAuthorization()
                while !Task.isCancelled {
                    await vm.fetchNotifications()
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { 
                    Task { 
                        await vm.refreshHealth(force: false) 
                        if vm.currentUser != nil {
                            await vm.fetchNotifications()
                        }
                    } 
                } else if phase == .background, vm.currentUser != nil {
                    AppNotifications.shared.scheduleRefresh()
                }
            }
            .onOpenURL { url in Task { await AuthBridge.handle(url: url) } }
    }
}

/// 0 HOME · 1 BARBELL · 2 SOCIAL · 3 TRAINING · 4 ACCOUNT — same order as Android.
struct PhoneTabView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @State private var selectedTab = 0
    @State private var trainingSubTab = 0
    @State private var focusedSessionId: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onOpenTraining: { selectedTab = 3 }, onOpenAccount: { selectedTab = 4 })
                .tabItem { Label("HOME", systemImage: "house.fill") }
                .tag(0)
            CompanionView()
                .tabItem { Label("BARBELL", systemImage: "dumbbell.fill") }
                .tag(1)
            SocialView()
                .tabItem { Label("SOCIAL", systemImage: "person.2.fill") }
                .badge(vm.unreadNotificationCount)
                .tag(2)
            TrainingView(subTab: $trainingSubTab, focusedSessionId: $focusedSessionId, onGoToSession: goToSession)
                .tabItem { Label("TRAINING", systemImage: "waveform.path.ecg") }
                .tag(3)
            AccountView()
                .tabItem { Label("ACCOUNT", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .tint(Brand.cyanGlow)
        .toolbarBackground(p.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        // Any notification tap jumps to Social; SocialView then opens the right sub-tab.
        .onChange(of: vm.openSocialRequest) { _, _ in selectedTab = 2 }
    }

    /// Log card ⓘ → the session that contains that log's timestamp.
    private func goToSession(_ logId: String) {
        guard let log = vm.logs.first(where: { $0.id == logId }),
              let session = vm.sessions.first(where: { $0.startTime <= log.timestamp && $0.endTime >= log.timestamp }) else {
            vm.showToast("No matching session found")
            return
        }
        focusedSessionId = session.id
        trainingSubTab = 1
        selectedTab = 3
    }
}
