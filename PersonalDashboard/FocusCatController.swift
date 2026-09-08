import AppKit
import Combine
import Foundation
import SwiftUI

enum FocusCatPose: Equatable {
    case sleeping
    case waking
    case running
    case reaching
    case celebrating
}

private final class FocusCatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FocusCatController: ObservableObject {
    @Published private(set) var pose: FocusCatPose = .sleeping
    @Published private(set) var facingRight = true
    @Published private(set) var animationPhase = 0.0
    @Published private(set) var statusText = ""
    @Published private(set) var isEnabled: Bool

    private struct ChromeTarget: Equatable {
        let bundleIdentifier: String
        let tabIndex: Int
        let url: String
        let title: String
        let windowBounds: CGRect
        let label: String
    }

    private enum Intervention {
        case chrome(ChromeTarget)
        case preview

        var label: String {
            switch self {
            case .chrome(let target): target.label
            case .preview: "the tab"
            }
        }
    }

    private let enabledKey = "personal-dashboard.focus-cat-enabled.v1"
    private let panelSize = NSSize(width: 154, height: 122)
    private let sprintSpeed: CGFloat = 720
    private let returnSpeed: CGFloat = 460
    private let defaults: UserDefaults
    private var panel: FocusCatPanel?
    private var movementTimer: Timer?
    private var detectionTimer: Timer?
    private var lastTick = Date()
    private var destinationOrigin: CGPoint?
    private var pendingInterventionOrigin: CGPoint?
    private var intervention: Intervention?
    private var wakeEndsAt: Date?
    private var interventionStartedAt: Date?
    private var closeAttempted = false
    private var celebrationEndsAt: Date?
    private var isReturningHome = false
    private var lastHandledURL = ""
    private var lastHandledAt = Date.distantPast
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: enabledKey)
        }
    }

    func start() {
        guard !hasStarted else {
            if isEnabled { showPanel() }
            return
        }
        hasStarted = true
        guard isEnabled else { return }
        showPanel()
        moveHome(animated: false)
        startTimers()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        if enabled {
            showPanel()
            moveHome(animated: false)
            startTimers()
        } else {
            stopTimers()
            resetToSleep()
            panel?.orderOut(nil)
        }
    }

    func showCat() {
        guard isEnabled else { return }
        showPanel()
        panel?.orderFrontRegardless()
    }

    /// Runs the full wake, sprint, paw, and return sequence without touching Chrome.
    func previewIntervention() {
        guard isEnabled, intervention == nil, !isReturningHome, let panel else { return }
        showPanel()
        let currentScreen = screen(containing: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        let previewPoint = CGPoint(
            x: currentScreen.visibleFrame.midX - panelSize.width / 2,
            y: currentScreen.visibleFrame.midY - panelSize.height / 2
        )
        intervention = .preview
        pendingInterventionOrigin = clampOrigin(previewPoint, to: currentScreen)
        beginWake(now: Date())
    }

    private func showPanel() {
        if panel == nil { makePanel() }
        guard let panel else { return }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makePanel() {
        let panel = FocusCatPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: FocusCatView(controller: self))

        let currentScreen = NSScreen.main ?? NSScreen.screens.first
        let frame = currentScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        panel.setFrameOrigin(homeOrigin(in: frame))
        self.panel = panel
    }

    private func startTimers() {
        guard movementTimer == nil else { return }
        lastTick = Date()
        let movementTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.movementTick() }
        }
        RunLoop.main.add(movementTimer, forMode: .common)
        self.movementTimer = movementTimer

        let detectionTimer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanChrome() }
        }
        RunLoop.main.add(detectionTimer, forMode: .common)
        self.detectionTimer = detectionTimer
        scanChrome()
    }

    private func stopTimers() {
        movementTimer?.invalidate()
        detectionTimer?.invalidate()
        movementTimer = nil
        detectionTimer = nil
    }

    private func movementTick(now: Date = Date()) {
        guard isEnabled, let panel else { return }
        let elapsed = min(0.1, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now

        switch pose {
        case .waking:
            animationPhase += elapsed * 2.4
            if let wakeEndsAt, now >= wakeEndsAt {
                self.wakeEndsAt = nil
                destinationOrigin = pendingInterventionOrigin
                pendingInterventionOrigin = nil
                pose = .running
                animationPhase = 0
                if let intervention { statusText = "Running to \(intervention.label)" }
            }
            return

        case .reaching:
            updateReach(now: now)
            return

        case .celebrating:
            animationPhase += elapsed * 7
            if let celebrationEndsAt, now >= celebrationEndsAt {
                beginReturnHome()
            }
            return

        case .sleeping, .running:
            break
        }

        if let destinationOrigin {
            let dx = destinationOrigin.x - panel.frame.origin.x
            let dy = destinationOrigin.y - panel.frame.origin.y
            let distance = hypot(dx, dy)
            let speed = isReturningHome ? returnSpeed : sprintSpeed
            let step = speed * elapsed

            if distance <= step || distance < 1 {
                movePanel(to: destinationOrigin)
                self.destinationOrigin = nil
                if isReturningHome {
                    finishReturnHome()
                } else if intervention != nil {
                    beginReach(now: now)
                }
            } else {
                if abs(dx) > 1 { facingRight = dx > 0 }
                pose = .running
                animationPhase += elapsed * 9
                movePanel(to: CGPoint(
                    x: panel.frame.origin.x + dx / distance * step,
                    y: panel.frame.origin.y + dy / distance * step
                ))
            }
            return
        }

        if pose == .sleeping {
            animationPhase += elapsed * 0.42
        }
    }

    private func beginWake(now: Date) {
        pose = .waking
        animationPhase = 0
        wakeEndsAt = now.addingTimeInterval(0.62)
        if let intervention { statusText = "Waking up — \(intervention.label) spotted" }
    }

    private func beginReach(now: Date) {
        pose = .reaching
        statusText = "Paw up…"
        interventionStartedAt = now
        closeAttempted = false
        animationPhase = 0
    }

    private func updateReach(now: Date) {
        guard let startedAt = interventionStartedAt else { return }
        let progress = min(1, max(0, now.timeIntervalSince(startedAt) / 1.15))
        animationPhase = progress

        if progress >= 0.62, !closeAttempted {
            closeAttempted = true
            let succeeded: Bool
            switch intervention {
            case .chrome(let target):
                succeeded = closeChromeTab(target)
                statusText = succeeded ? "Closed \(target.label)" : "Tab changed — leaving it alone"
            case .preview:
                succeeded = true
                statusText = "Got it!"
            case .none:
                succeeded = false
            }

            if succeeded {
                pose = .celebrating
                celebrationEndsAt = now.addingTimeInterval(1.05)
            } else {
                beginReturnHome()
            }
        }
    }

    private func beginReturnHome() {
        guard let panel else { return }
        intervention = nil
        wakeEndsAt = nil
        interventionStartedAt = nil
        closeAttempted = false
        celebrationEndsAt = nil
        pendingInterventionOrigin = nil
        statusText = "Back to bed"
        isReturningHome = true
        pose = .running
        animationPhase = 0

        let currentScreen = screen(containing: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        destinationOrigin = homeOrigin(in: currentScreen.visibleFrame)
        if let destinationOrigin, distance(from: panel.frame.origin, to: destinationOrigin) < 1 {
            self.destinationOrigin = nil
            finishReturnHome()
        }
    }

    private func finishReturnHome() {
        isReturningHome = false
        destinationOrigin = nil
        statusText = ""
        pose = .sleeping
        animationPhase = 0
        facingRight = true
    }

    private func moveHome(animated: Bool) {
        guard let panel else { return }
        let currentScreen = screen(containing: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        let home = homeOrigin(in: currentScreen.visibleFrame)
        if animated {
            destinationOrigin = home
            isReturningHome = true
            pose = .running
        } else {
            panel.setFrameOrigin(home)
            resetToSleep()
        }
    }

    private func resetToSleep() {
        intervention = nil
        wakeEndsAt = nil
        interventionStartedAt = nil
        closeAttempted = false
        celebrationEndsAt = nil
        pendingInterventionOrigin = nil
        destinationOrigin = nil
        isReturningHome = false
        statusText = ""
        pose = .sleeping
        animationPhase = 0
        facingRight = true
    }

    private func scanChrome(now: Date = Date()) {
        guard isEnabled, pose == .sleeping, intervention == nil, !isReturningHome,
              now.timeIntervalSince(lastHandledAt) > 4,
              let target = activeChromeTarget() else { return }
        guard target.url != lastHandledURL || now.timeIntervalSince(lastHandledAt) > 15 else { return }

        lastHandledURL = target.url
        lastHandledAt = now
        intervention = .chrome(target)
        pendingInterventionOrigin = targetOrigin(for: target)
        showPanel()
        beginWake(now: now)
    }

    /// Converts Chrome's top-left window coordinates into AppKit's bottom-left
    /// coordinates and places the cat so its raised paw overlaps the active tab.
    private func targetOrigin(for target: ChromeTarget) -> CGPoint {
        let tabWidth: CGFloat = 150
        let tabCenterX = min(
            target.windowBounds.maxX - 42,
            target.windowBounds.minX + 96 + CGFloat(max(0, target.tabIndex - 1)) * tabWidth
        )
        let targetScreen = screen(containingX: tabCenterX)
        let chromeTopInAppKit = targetScreen.frame.maxY - target.windowBounds.minY
        return clampOrigin(
            CGPoint(
                x: tabCenterX - panelSize.width * 0.62,
                y: chromeTopInAppKit - 74
            ),
            to: targetScreen
        )
    }

    private func movePanel(to origin: CGPoint) {
        guard let panel else { return }
        let requestedCenter = CGPoint(
            x: origin.x + panelSize.width / 2,
            y: origin.y + panelSize.height / 2
        )
        let targetScreen = screen(containing: requestedCenter)
        panel.setFrameOrigin(clampOrigin(origin, to: targetScreen))
    }

    private func homeOrigin(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.minX + 12, y: visibleFrame.minY + 8)
    }

    private func clampOrigin(_ origin: CGPoint, to screen: NSScreen) -> CGPoint {
        CGPoint(
            x: min(
                max(origin.x, screen.visibleFrame.minX + 8),
                screen.visibleFrame.maxX - panelSize.width - 8
            ),
            y: min(
                max(origin.y, screen.visibleFrame.minY + 8),
                screen.visibleFrame.maxY - panelSize.height - 8
            )
        )
    }

    private func screen(containing point: CGPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func screen(containingX x: CGFloat) -> NSScreen {
        NSScreen.screens.first { $0.frame.minX <= x && x <= $0.frame.maxX }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func activeChromeTarget() -> ChromeTarget? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmost.bundleIdentifier,
              Self.chromeBundleIdentifiers.contains(bundleIdentifier) else { return nil }

        let script = """
        tell application id "\(bundleIdentifier)"
            if (count of windows) is 0 then return ""
            set tabNumber to active tab index of front window
            set tabURL to URL of active tab of front window
            set tabTitle to title of active tab of front window
            set windowBounds to bounds of front window
            return (tabNumber as text) & "~~~" & tabURL & "~~~" & tabTitle & "~~~" & ¬
                (item 1 of windowBounds as text) & "~~~" & (item 2 of windowBounds as text) & "~~~" & ¬
                (item 3 of windowBounds as text) & "~~~" & (item 4 of windowBounds as text)
        end tell
        """

        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
              error == nil, !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "~~~")
        guard parts.count == 7,
              let tabIndex = Int(parts[0]),
              let left = Double(parts[3]),
              let top = Double(parts[4]),
              let right = Double(parts[5]),
              let bottom = Double(parts[6]),
              let label = Self.distractionLabel(for: parts[1]) else { return nil }

        return ChromeTarget(
            bundleIdentifier: bundleIdentifier,
            tabIndex: tabIndex,
            url: parts[1],
            title: parts[2],
            windowBounds: CGRect(x: left, y: top, width: right - left, height: bottom - top),
            label: label
        )
    }

    private func closeChromeTab(_ target: ChromeTarget) -> Bool {
        let escapedURL = target.url
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application id "\(target.bundleIdentifier)"
            if (count of windows) is 0 then return "missing"
            if (active tab index of front window) is not \(target.tabIndex) then return "changed"
            if (URL of active tab of front window) is not "\(escapedURL)" then return "changed"
            close active tab of front window
            return "closed"
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        return error == nil && result == "closed"
    }

    private static func distractionLabel(for urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }
        if (host == "youtube.com" || host.hasSuffix(".youtube.com")),
           url.path.lowercased().hasPrefix("/shorts") {
            return "YouTube Shorts"
        }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            return "Instagram"
        }
        return nil
    }

    private static let chromeBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary"
    ]
}
