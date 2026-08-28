import SwiftUI

@main
struct PersonalDashboardApp: App {
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1280, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1512, height: 982)
    }
}
