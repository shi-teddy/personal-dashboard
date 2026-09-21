import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class DeepFocusController: ObservableObject {
    struct BrowserTab: Equatable, Sendable {
        let bundleIdentifier: String
        let windowID: String
        let tabID: String
        let url: String
        let title: String
    }

    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var statusText = "Ready"
    @Published var selectedDuration: DeepFocusDuration = .oneHour

    private weak var store: DashboardStore?
    private weak var focusCat: FocusCatController?
    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private let clock: () -> Date
    private var timer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var browserScanInFlight = false
    private var generation = 0

    private let endDateKey = "personal-dashboard.deep-focus.end-date.v1"
    private static let warningIdentifier = "personal-dashboard.deep-focus.five-minute-warning"
    private static let supportedBrowserBundleIdentifiers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary"
    ]

    init(defaults: UserDefaults = .standard,
         notificationCenter: UNUserNotificationCenter = .current(),
         clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.clock = clock
    }

    deinit {
        timer?.invalidate()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func start(store: DashboardStore, focusCat: FocusCatController) {
        self.store = store
        self.focusCat = focusCat
        guard !isActive else { return }
        if let savedEndDate = defaults.object(forKey: endDateKey) as? Date,
           savedEndDate > clock() {
            beginSession(endingAt: savedEndDate, scheduleWarning: true)
        } else {
            defaults.removeObject(forKey: endDateKey)
        }
    }

    func beginSelectedSession() {
        beginSession(endingAt: clock().addingTimeInterval(selectedDuration.seconds), scheduleWarning: true)
    }

    func endSession() {
        generation += 1
        isActive = false
        endDate = nil
        remainingSeconds = 0
        statusText = "Ready"
        browserScanInFlight = false
        timer?.invalidate()
        timer = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        defaults.removeObject(forKey: endDateKey)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.warningIdentifier])
        focusCat?.setBrowserInterventionsSuspended(false)
    }

    private func beginSession(endingAt endDate: Date, scheduleWarning: Bool) {
        endSession()
        guard endDate > clock() else { return }
        self.endDate = endDate
        remainingSeconds = endDate.timeIntervalSince(clock())
        isActive = true
        focusCat?.setBrowserInterventionsSuspended(true)
        statusText = "Only Flow apps and sites are available"
        defaults.set(endDate, forKey: endDateKey)

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluateFrontmostApplication() }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if scheduleWarning { scheduleFiveMinuteWarning(endingAt: endDate, generation: generation) }
        evaluateFrontmostApplication()
    }

    private func tick() {
        guard isActive, let endDate else { return }
        let now = clock()
        remainingSeconds = max(0, endDate.timeIntervalSince(now))
        guard now < endDate else {
            endSession()
            statusText = "Deep Focus complete"
            return
        }
        evaluateFrontmostApplication()
    }

    private func evaluateFrontmostApplication() {
        guard isActive, let store,
              let application = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier else { return }

        if bundleIdentifier == Bundle.main.bundleIdentifier { return }
        let displayName = application.localizedName ?? bundleIdentifier
        if Self.supportedBrowserBundleIdentifiers.contains(bundleIdentifier) {
            requestBrowserScan(bundleIdentifier: bundleIdentifier)
        } else if !DeepFocusPolicy.isFlowApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            rules: store.classificationRules
        ) {
            blockApplication(named: displayName)
        } else {
            statusText = "Flow: \(displayName)"
        }
    }

    private func requestBrowserScan(bundleIdentifier: String) {
        guard !browserScanInFlight else { return }
        browserScanInFlight = true
        let requestGeneration = generation
        Task { [weak self] in
            let tab = await BrowserScriptRunner.shared.perform {
                Self.readActiveTab(bundleIdentifier: bundleIdentifier)
            }
            guard let self else { return }
            self.browserScanInFlight = false
            guard self.isActive, requestGeneration == self.generation,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier,
                  let store = self.store else { return }
            guard let tab else {
                self.blockApplication(named: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Browser")
                return
            }
            if DeepFocusPolicy.isFlowWebsite(urlString: tab.url, rules: store.classificationRules) {
                self.statusText = "Flow: \(tab.title.isEmpty ? tab.url : tab.title)"
                return
            }
            self.closeBlockedTab(tab, generation: requestGeneration)
        }
    }

    private func closeBlockedTab(_ tab: BrowserTab, generation: Int) {
        browserScanInFlight = true
        Task { [weak self] in
            let result = await BrowserScriptRunner.shared.perform {
                BrowserScriptRunner.execute(Self.closeScript(for: tab))
            }
            guard let self else { return }
            self.browserScanInFlight = false
            guard self.isActive, generation == self.generation else { return }
            if result == "closed" {
                self.statusText = "Closed a non-Flow tab"
            } else if result == "changed" {
                self.statusText = "Tab changed; nothing was closed"
            } else {
                self.statusText = "Couldn’t close the blocked tab"
                self.blockApplication(named: "Chrome")
            }
        }
    }

    private func blockApplication(named name: String) {
        guard isActive else { return }
        statusText = "Blocked \(name)"
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    }

    private func scheduleFiveMinuteWarning(endingAt endDate: Date, generation: Int) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.warningIdentifier])
        guard let warningDate = DeepFocusPolicy.fiveMinuteWarningDate(endDate: endDate, now: clock()) else { return }
        Task {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
            guard isActive, self.generation == generation, self.endDate == endDate else { return }
            let content = UNMutableNotificationContent()
            content.title = "Deep Focus"
            content.body = "Your Deep Focus session ends in 5 minutes."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, warningDate.timeIntervalSince(clock())),
                repeats: false
            )
            try? await notificationCenter.add(UNNotificationRequest(
                identifier: Self.warningIdentifier,
                content: content,
                trigger: trigger
            ))
        }
    }

    nonisolated static func readActiveTab(bundleIdentifier: String) -> BrowserTab? {
        let script = """
        if application id "\(bundleIdentifier)" is not running then return ""
        tell application id "\(bundleIdentifier)"
            if (count of windows) is 0 then return \"\"
            set activeWindow to front window
            set activeBrowserTab to active tab of activeWindow
            return ((id of activeWindow) as text) & \"~~~\" & ((id of activeBrowserTab) as text) & \"~~~\" & (URL of activeBrowserTab) & \"~~~\" & (title of activeBrowserTab)
        end tell
        """
        guard let result = BrowserScriptRunner.execute(script), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "~~~")
        guard parts.count == 4, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return BrowserTab(bundleIdentifier: bundleIdentifier, windowID: parts[0], tabID: parts[1], url: parts[2], title: parts[3])
    }

    nonisolated static func closeScript(for tab: BrowserTab) -> String {
        let bundle = FocusCatController.scriptLiteral(tab.bundleIdentifier)
        let window = FocusCatController.scriptLiteral(tab.windowID)
        let tabID = FocusCatController.scriptLiteral(tab.tabID)
        let url = FocusCatController.scriptLiteral(tab.url)
        return """
        if application id \(bundle) is not running then return "changed"
        tell application id \(bundle)
            if (count of windows) is 0 then return "changed"
            if ((id of front window) as text) is not \(window) then return "changed"
            if ((id of active tab of front window) as text) is not \(tabID) then return "changed"
            considering case
                if (URL of active tab of front window) is not \(url) then return "changed"
            end considering
            close tab id \(tabID) of window id \(window)
            return "closed"
        end tell
        """
    }
}
