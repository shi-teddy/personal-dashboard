import SwiftUI

@main
struct PersonalDashboardApp: App {
    @StateObject private var store = DashboardStore()
    @StateObject private var screenTimeTracker = ScreenTimeTracker()
    @StateObject private var focusCat = FocusCatController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(screenTimeTracker)
                .environmentObject(focusCat)
                .frame(minWidth: 1280, minHeight: 800)
                .onAppear { focusCat.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1512, height: 982)
        .commands {
            CommandMenu("Focus Cat") {
                Button(focusCat.isEnabled ? "Hide Focus Cat" : "Show Focus Cat") {
                    focusCat.setEnabled(!focusCat.isEnabled)
                }
                Button("Preview Intervention") {
                    focusCat.previewIntervention()
                }
                .disabled(!focusCat.isEnabled)
            }
        }
    }
}
