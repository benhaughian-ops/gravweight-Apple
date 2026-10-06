import SwiftUI

@main
struct WODwireWatchApp: App {
    @StateObject private var vm = WatchViewModel()

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                .environmentObject(vm)
        }
    }
}
