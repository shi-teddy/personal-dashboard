import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct PersonalDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .onAppear {
                    focusCat.start()
                    store.activateCalendarNotifications()
                }
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
