import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI

enum FocusCatPose: Equatable {
    case sleeping
    case settling
    case waking
    case running
    case reaching
    case celebrating
}

private final class FocusCatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // The controller clamps the visible cat itself. AppKit's additional window
    // constraint would stop the transparent panel below a top-row tab forever.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class CatAnimationState: ObservableObject {
    @Published var phase = 0.0
}

@MainActor
final class FocusCatController: ObservableObject {
    @Published private(set) var pose: FocusCatPose = .sleeping
    @Published private(set) var facingRight = true
    let animation = CatAnimationState()
    var animationPhase: Double {
        get { animation.phase }
        set { animation.phase = newValue }
    }
    @Published private(set) var statusText = ""
    @Published private(set) var isEnabled: Bool

    struct ChromeTarget: Equatable, Sendable {
        let windowID: String
        let tabID: String
        let bundleIdentifier: String
        let tabIndex: Int
        let url: String
        let title: String
        let windowBounds: CGRect
        let label: String
        var closeContact: CGPoint? = nil
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
    private let panelSize = CatLayout.panelSize
    private let defaults: UserDefaults
    private let browserMonitoringEnabled: Bool
    private let clock: () -> Date
    private let browserAvailable: () -> Bool
    private var panel: FocusCatPanel?
    private var movementTimer: Timer?
    private var detectionTimer: Timer?
    private var idleTimer: Timer?
    private var browserObservers: [NSObjectProtocol] = []
    private var browserGeneration = 0
    private var closeCancellation: BrowserRequestCancellation?
    private(set) var browserScanInFlight = false
    private(set) var browserScanCount = 0
    private(set) var animationTimerCallbacks = 0
    private(set) var idleTimerCallbacks = 0
    private(set) var detectionInterval: TimeInterval = 2.5
    var hasMovementTimer: Bool { movementTimer != nil }
    var hasIdleTimer: Bool { idleTimer != nil }
    private var lastTick = Date()
    private var stalledTravelTime = 0.0
    private var travelSpeed = 0.0
    private var travelPhasePerPoint = 0.0
    private var destinationOrigin: CGPoint?
    private var pendingInterventionOrigin: CGPoint?
    private var intervention: Intervention?
    private var wakeEndsAt: Date?
    private var interventionStartedAt: Date?
    private var closeAttempted = false
    private var lastTargetCheck = Date.distantPast
    private var celebrationEndsAt: Date?
    // Both directions use the gait in the approved GIF.
    var isSprinting: Bool { false }
    var isDeparting: Bool { !isReturningHome }

    private var isReturningHome = false
    private var lastHandledURL = ""
    private var lastHandledAt = Date.distantPast
    private var hasStarted = false

    init(defaults: UserDefaults = .standard, browserMonitoringEnabled: Bool = true,
         clock: @escaping () -> Date = Date.init,
         browserAvailable: @escaping () -> Bool = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map {
                 FocusCatController.chromeBundleIdentifiers.contains($0)
             } ?? false
         }) {
        self.defaults = defaults
        self.browserMonitoringEnabled = browserMonitoringEnabled
        self.clock = clock
        self.browserAvailable = browserAvailable
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

    /// Runs the full approved wake, walk, paw, and return sequence without touching Chrome.
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
        beginWake(now: clock())
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
        updateAnimationTimer()
        guard browserMonitoringEnabled, browserObservers.isEmpty else { return }
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            browserObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isEnabled else { return }
                    self.detectionInterval = 2.5
                    self.scheduleDetection(after: 0)
                }
            })
        }
        scheduleDetection(after: 0)
    }

    private func updateAnimationTimer() {
        guard isEnabled else { return }
        if pose == .sleeping {
            movementTimer?.invalidate()
            movementTimer = nil
            guard idleTimer == nil else { return }
            lastTick = clock()
            // The authored sleeping clip breathes by a fraction of a point.
            // Retain its 2.4-second phase at 4 Hz without waking the whole app.
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.idleTimerCallbacks += 1
                    self.movementTick()
                }
            }
            timer.tolerance = 0.025
            RunLoop.main.add(timer, forMode: .common)
            idleTimer = timer
            return
        }
        idleTimer?.invalidate()
        idleTimer = nil
        guard movementTimer == nil else { return }
        lastTick = clock()
        let movementTimer = Timer(timeInterval: CatGait.updateInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animationTimerCallbacks += 1
                self.movementTick()
            }
        }
        RunLoop.main.add(movementTimer, forMode: .common)
        self.movementTimer = movementTimer

    }

    private func stopTimers() {
        closeCancellation?.cancel()
        movementTimer?.invalidate()
        detectionTimer?.invalidate()
        idleTimer?.invalidate()
        idleTimer = nil
        browserGeneration += 1
        for observer in browserObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        browserObservers.removeAll()
        movementTimer = nil
        detectionTimer = nil
    }

    func movementTick(now suppliedTime: Date? = nil) {
        let now = suppliedTime ?? clock()
        guard isEnabled, let panel else { return }
        let elapsed = pose == .sleeping ? max(0, now.timeIntervalSince(lastTick))
            : min(0.1, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now
        defer { updateAnimationTimer() }

        if browserMonitoringEnabled, now.timeIntervalSince(lastTargetCheck) >= 0.35 {
            requestTargetCheck(now: now)
        }

        switch pose {
        case .settling:
            animationPhase = min(CatLayout.settleDuration, animationPhase + elapsed)
            if animationPhase >= CatLayout.settleDuration {
                pose = .sleeping
                animationPhase = 0
                statusText = ""
            }
            return

        case .waking:
            animationPhase += elapsed
            if let wakeEndsAt, now >= wakeEndsAt {
                self.wakeEndsAt = nil
                destinationOrigin = pendingInterventionOrigin
                pendingInterventionOrigin = nil
                pose = .running
                animationPhase = 0
                prepareTravel()
                if let intervention { statusText = "Running to \(intervention.label)" }
            }
            return

        case .reaching:
            updateReach(now: now)
            return

        case .celebrating:
            animationPhase = min(CatLayout.recoverDuration, animationPhase + elapsed)
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
            let gait = isReturningHome ? CatGait.walk : CatGait.run
            let speed = CGFloat(travelSpeed > 0 ? travelSpeed : gait.speed)
            let step = speed * elapsed

            if distance <= step {
                movePanel(to: destinationOrigin)
                finishTravel(now: now)
            } else {
                if abs(dx) > 1, facingRight != (dx > 0) { facingRight = dx > 0 }
                if pose != .running { pose = .running }
                let previousOrigin = panel.frame.origin
                movePanel(to: CGPoint(
                    x: previousOrigin.x + dx / distance * step,
                    y: previousOrigin.y + dy / distance * step
                ))
                // Advance the feet by actual travel, including diagonal motion
                // and any screen-edge clamping. A stationary cat cannot skate.
                let travelled = hypot(panel.frame.origin.x - previousOrigin.x,
                                      panel.frame.origin.y - previousOrigin.y)
                animationPhase += Double(travelled) * (travelPhasePerPoint > 0 ? travelPhasePerPoint : 1/gait.speed)
                // A display/window constraint may make the final destination
                // unreachable. Once stopped at that boundary, finish the
                // approach instead of preventing the guarded close forever.
                stalledTravelTime = travelled < 0.01 ? stalledTravelTime + elapsed : 0
                if stalledTravelTime >= 0.5 {
                    finishTravel(now: now)
                }
            }
            return
        }

        if pose == .sleeping {
            animationPhase += elapsed
        }
    }

    /// Fit an integral number of the approved walk cycles to the trip. This
    /// finishes on the authored standing pose instead of snapping mid-stride.
    private func prepareTravel() {
        guard let panel, let destinationOrigin else { return }
        let length = Double(distance(from: panel.frame.origin, to: destinationOrigin))
        guard length > 0 else { travelSpeed = 0; travelPhasePerPoint = 0; return }
        let gait = CatGait.walk
        let cycles = max(1, (length / gait.distancePerLoop).rounded())
        let duration = cycles * gait.loopDuration
        travelSpeed = length / duration
        travelPhasePerPoint = duration / length
    }

    private func finishTravel(now: Date) {
        destinationOrigin = nil
        stalledTravelTime = 0
        if isReturningHome {
            finishReturnHome()
        } else if intervention != nil {
            beginReach(now: now)
        }
    }

    private func beginWake(now: Date) {
        stalledTravelTime = 0
        pose = .waking
        animationPhase = 0
        wakeEndsAt = now.addingTimeInterval(CatLayout.settleDuration)
        updateAnimationTimer()
        if let intervention { statusText = "Waking up — \(intervention.label) spotted" }
    }

    private func beginReach(now: Date) {
        if case .chrome(let target) = intervention, let panel {
            // Face the contact point even when the last movement was vertical.
            facingRight = closeContactPoint(for: target).x >= panel.frame.midX
        }
        pose = .reaching
        statusText = "Paw up…"
        interventionStartedAt = now
        closeAttempted = false
        animationPhase = 0
    }

    private func updateReach(now: Date) {
        guard let startedAt = interventionStartedAt else { return }
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        animationPhase = min(CatLayout.reachDuration, elapsed)

        if elapsed >= CatLayout.closeTime, !closeAttempted, !browserScanInFlight {
            closeAttempted = true
            switch intervention {
            case .chrome(let target):
                let generation = browserGeneration
                let cancellation = BrowserRequestCancellation()
                closeCancellation = cancellation
                browserScanInFlight = true
                Task { [weak self] in
                    let succeeded = await BrowserScriptRunner.shared.perform {
                        Self.performClose(target) { source in
                            guard !cancellation.isCancelled else { return nil }
                            return BrowserScriptRunner.execute(source)
                        }
                    }
                    guard let self else { return }
                    self.browserScanInFlight = false
                    guard self.isEnabled, generation == self.browserGeneration,
                          case .chrome(let current) = self.intervention, current == target else { return }
                    self.statusText = succeeded ? "Closed \(target.label)" : "Tab changed — leaving it alone"
                }
            case .preview:
                statusText = "Got it!"
            case .none:
                break
            }
        }
        // Match the GIF: finish the hold, then lower the same paw completely
        // before moving away. Never switch directly from a raised paw to walking.
        if elapsed >= CatLayout.reachDuration {
            pose = .celebrating
            animationPhase = 0
            celebrationEndsAt = now.addingTimeInterval(CatLayout.recoverDuration)
        }
    }

    private func beginReturnHome() {
        closeCancellation?.cancel()
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
        prepareTravel()
        if let destinationOrigin, distance(from: panel.frame.origin, to: destinationOrigin) < 1 {
            self.destinationOrigin = nil
            finishReturnHome()
        }
    }

    private func finishReturnHome() {
        isReturningHome = false
        destinationOrigin = nil
        statusText = "Settling down"
        facingRight = true
        pose = .settling
        animationPhase = 0
    }

    private func moveHome(animated: Bool) {
        guard let panel else { return }
        let currentScreen = screen(containing: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        let home = homeOrigin(in: currentScreen.visibleFrame)
        if animated {
            destinationOrigin = home
            isReturningHome = true
            pose = .running
            animationPhase = 0
            prepareTravel()
        } else {
            panel.setFrameOrigin(home)
            resetToSleep()
        }
    }

    private func resetToSleep() {
        closeCancellation?.cancel()
        browserGeneration += 1
        stalledTravelTime = 0
        travelSpeed = 0
        travelPhasePerPoint = 0
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

    private func scheduleDetection(after delay: TimeInterval) {
        detectionTimer?.invalidate()
        detectionTimer = nil
        guard isEnabled, browserMonitoringEnabled, browserAvailable() else { return }
        let timer = Timer(timeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.scanChrome()
                self.scheduleDetection(after: self.detectionInterval)
            }
        }
        timer.tolerance = min(0.5, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        detectionTimer = timer
    }

    func scanChrome(now: Date? = nil, provider: (() async -> ChromeTarget?)? = nil) async {
        let now = now ?? clock()
        guard isEnabled, browserMonitoringEnabled, browserAvailable(),
              pose == .sleeping, intervention == nil, !isReturningHome,
              !browserScanInFlight, now.timeIntervalSince(lastHandledAt) > 4 else { return }
        browserScanInFlight = true
        browserScanCount += 1
        let generation = browserGeneration
        let target: ChromeTarget?
        if let provider { target = await provider() } else { target = await activeChromeTarget() }
        browserScanInFlight = false
        guard generation == browserGeneration, isEnabled, pose == .sleeping else { return }
        guard let target else {
            detectionInterval = min(10, detectionInterval * 2)
            return
        }
        detectionInterval = 2.5
        guard target.url != lastHandledURL || now.timeIntervalSince(lastHandledAt) > 15 else { return }

        lastHandledURL = target.url
        lastHandledAt = now
        beginChromeIntervention(target, now: now)
    }

    func beginChromeIntervention(_ target: ChromeTarget, now: Date) {
        intervention = .chrome(target)
        lastTargetCheck = now
        pendingInterventionOrigin = targetOrigin(for: target)
        showPanel()
        beginWake(now: now)
    }

    /// Keep the existing tab-position estimate, but aim at the trailing close
    /// control rather than placing the cat's center underneath the tab center.
    private func closeContactPoint(for target: ChromeTarget) -> CGPoint {
        if let exact = target.closeContact { return exact }
        let tabWidth: CGFloat = 150
        let closeX = min(
            target.windowBounds.maxX - 42,
            target.windowBounds.minX + 96
                + CGFloat(max(0, target.tabIndex - 1)) * tabWidth
                + tabWidth / 2 - 18
        )
        let targetScreen = screen(containingX: closeX)
        return CGPoint(x: closeX,
                       y: targetScreen.frame.maxY - target.windowBounds.minY - 23)
    }

    /// Read only browser chrome, never page content. No permission prompts or
    /// new close APIs: this supplies coordinates to the existing intervention.
    nonisolated private static func accessibleCloseContact(for target: ChromeTarget, primaryTop: CGFloat) -> CGPoint? {
        guard AXIsProcessTrusted(),
              let process = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).first else { return nil }
        let application = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
            return value
        }
        guard let windowValue = attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        var queue: [(AXUIElement,Int)] = [(window,0)]
        var cursor=0
        while cursor < queue.count && cursor < 240 {
            let (element,depth)=queue[cursor]; cursor += 1
            let role=attribute(element,kAXRoleAttribute) as? String ?? ""
            if role == "AXWebArea" || depth > 10 { continue }
            let children=attribute(element,kAXChildrenAttribute) as? [AXUIElement] ?? []
            if role == kAXTabGroupRole {
                for tab in children {
                    let selected=(attribute(tab,kAXValueAttribute) as? NSNumber)?.boolValue == true
                        || (attribute(tab,kAXSelectedAttribute) as? NSNumber)?.boolValue == true
                    guard selected else { continue }
                    let label=(attribute(tab,kAXDescriptionAttribute) as? String ?? "")
                        + (attribute(tab,kAXTitleAttribute) as? String ?? "")
                    guard target.title.isEmpty || label.contains(target.title) else { continue }
                    let controls=attribute(tab,kAXChildrenAttribute) as? [AXUIElement] ?? []
                    for control in controls {
                        let description=attribute(control,kAXDescriptionAttribute) as? String ?? ""
                        guard (attribute(control,kAXRoleAttribute) as? String) == kAXButtonRole,
                              description.lowercased().contains("close"),
                              let position=attribute(control,kAXPositionAttribute),
                              let dimensions=attribute(control,kAXSizeAttribute),
                              CFGetTypeID(position) == AXValueGetTypeID(),
                              CFGetTypeID(dimensions) == AXValueGetTypeID() else { continue }
                        var origin=CGPoint.zero, size=CGSize.zero
                        guard AXValueGetValue(unsafeBitCast(position,to:AXValue.self),.cgPoint,&origin),
                              AXValueGetValue(unsafeBitCast(dimensions,to:AXValue.self),.cgSize,&size),
                              size.width > 0, size.height > 0 else { continue }
                        // Accessibility coordinates use the primary display's
                        // top-left origin, including for secondary monitors.
                        return CGPoint(x:origin.x+size.width/2,
                                       y:primaryTop-origin.y-size.height/2)
                    }
                }
                return nil
            }
            queue.append(contentsOf: children.map { ($0,depth+1) })
        }
        return nil
    }

    private func targetOrigin(for target: ChromeTarget) -> CGPoint {
        let contact = closeContactPoint(for: target)
        let targetScreen = screen(containingX: contact.x)
        let approachesFromLeft = contact.x >= (panel?.frame.midX ?? contact.x)
        let paw = CatLayout.pawContact(facingRight: approachesFromLeft)
        return clampOrigin(
            CGPoint(x: contact.x - paw.x, y: contact.y - paw.y),
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
        CGPoint(x: visibleFrame.minX + 12,
                y: visibleFrame.minY + 8 - CatLayout.visibleBounds.minY)
    }

    private func clampOrigin(_ origin: CGPoint, to screen: NSScreen) -> CGPoint {
        let ink = CatLayout.visibleBounds
        return CGPoint(
            x: min(max(origin.x, screen.visibleFrame.minX + 8 - ink.minX),
                   screen.visibleFrame.maxX - 8 - ink.maxX),
            y: min(max(origin.y, screen.visibleFrame.minY + 8 - ink.minY),
                   screen.frame.maxY - ink.maxY)
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

    private func activeChromeTarget() async -> ChromeTarget? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmost.bundleIdentifier,
              Self.chromeBundleIdentifiers.contains(bundleIdentifier) else { return nil }

        let script = """
        if application id "\(bundleIdentifier)" is not running then return ""
        tell application id "\(bundleIdentifier)"
            if (count of windows) is 0 then return ""
            set targetWindowID to id of front window
            set targetTabID to id of active tab of front window
            set tabNumber to active tab index of front window
            set tabURL to URL of active tab of front window
            set tabTitle to title of active tab of front window
            set windowBounds to bounds of front window
            return (tabNumber as text) & "~~~" & tabURL & "~~~" & tabTitle & "~~~" & ¬
                (item 1 of windowBounds as text) & "~~~" & (item 2 of windowBounds as text) & "~~~" & ¬
                (item 3 of windowBounds as text) & "~~~" & (item 4 of windowBounds as text) & "~~~" & ¬
                (targetWindowID as text) & "~~~" & (targetTabID as text)
        end tell
        """

        let response = await BrowserScriptRunner.shared.perform { () -> (String?, Int?) in
            var error: NSDictionary?
            let result = NSAppleScript(source: "with timeout of 2 seconds\n\(script)\nend timeout")?
                .executeAndReturnError(&error).stringValue
            return (result, error?[NSAppleScript.errorNumber] as? Int)
        }
        guard isEnabled else { return nil }
        let result = response.0
        if let code = response.1 {
            statusText = code == -1743
                ? "Allow Chrome control in System Settings → Privacy & Security → Automation"
                : "Chrome check failed (\(code))"
            return nil
        }
        guard let result, !result.isEmpty else { return nil }
        if statusText.hasPrefix("Allow Chrome control") || statusText.hasPrefix("Chrome check failed") {
            statusText = ""
        }
        let parts = result.components(separatedBy: "~~~")
        guard parts.count == 9,
              !parts[7].isEmpty, !parts[8].isEmpty,
              let tabIndex = Int(parts[0]),
              let left = Double(parts[3]),
              let top = Double(parts[4]),
              let right = Double(parts[5]),
              let bottom = Double(parts[6]),
              let label = Self.distractionLabel(for: parts[1]) else { return nil }

        var target = ChromeTarget(
            windowID: parts[7], tabID: parts[8],
            bundleIdentifier: bundleIdentifier,
            tabIndex: tabIndex,
            url: parts[1],
            title: parts[2],
            windowBounds: CGRect(x: left, y: top, width: right - left, height: bottom - top),
            label: label
        )
        // Resolve browser chrome once per trip, on the same serial worker as
        // Apple events. Reuse this contact at the paw instead of blocking a frame
        // on a second accessibility-tree traversal.
        let unresolved = target
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        target.closeContact = await BrowserScriptRunner.shared.perform {
            Self.accessibleCloseContact(for: unresolved, primaryTop: primaryTop)
        }
        return target
    }

    nonisolated static func scriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    nonisolated static func identityGuard(for target: ChromeTarget) -> String {
        // Chrome's scripting dictionary declares these IDs as TEXT. Comparing
        // them to integer literals incorrectly rejects the very same tab.
        """
        if (count of windows) is 0 then return "changed"
        if ((id of front window) as text) is not \(scriptLiteral(target.windowID)) then return "changed"
        if ((id of active tab of front window) as text) is not \(scriptLiteral(target.tabID)) then return "changed"
        """
    }

    func checkInterventionTarget(now: Date,
                                 execute: (String) -> String? = FocusCatController.executeChromeScript) {
        lastTargetCheck = now
        guard case .chrome(let target) = intervention, !closeAttempted,
              pose == .waking || pose == .running || pose == .reaching else { return }
        let script = """
        if application id "\(target.bundleIdentifier)" is not running then return "changed"
        tell application id "\(target.bundleIdentifier)"
            \(Self.identityGuard(for: target))
            return URL of active tab of front window
        end tell
        """
        // A temporary Apple-event error is not evidence that the tab vanished.
        guard let result = execute(script) else { return }
        guard Self.distractionLabel(for: result) != target.label else { return }
        cancelIntervention(now: now)
    }

    private func requestTargetCheck(now: Date) {
        guard !browserScanInFlight, case .chrome(let target) = intervention, !closeAttempted,
              pose == .waking || pose == .running || pose == .reaching else { return }
        lastTargetCheck = now
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty else {
            cancelIntervention(now: now)
            return
        }
        let script = """
        if application id "\(target.bundleIdentifier)" is not running then return "changed"
        tell application id "\(target.bundleIdentifier)"
            \(Self.identityGuard(for: target))
            return URL of active tab of front window
        end tell
        """
        let generation = browserGeneration
        browserScanInFlight = true
        Task { [weak self] in
            let result = await BrowserScriptRunner.shared.perform { BrowserScriptRunner.execute(script) }
            guard let self else { return }
            self.browserScanInFlight = false
            guard self.isEnabled, generation == self.browserGeneration, !self.closeAttempted,
                  case .chrome(let current) = self.intervention, current == target,
                  let result else { return }
            if Self.distractionLabel(for: result) != target.label {
                self.cancelIntervention(now: self.clock())
                self.updateAnimationTimer()
            }
        }
    }

    private func cancelIntervention(now: Date) {
        closeCancellation?.cancel()
        if pose == .waking {
            let settlePhase = max(0, CatLayout.settleDuration - animationPhase)
            resetToSleep()
            pose = .settling
            animationPhase = settlePhase
            statusText = "Tab gone — back to bed"
        } else if pose == .reaching {
            // Lower only as far as the paw has actually risen, then walk home.
            let raised = min(1, max(0, (animationPhase - 0.25) / 0.65))
            intervention = nil
            closeAttempted = true
            pose = .celebrating
            animationPhase = 0.65 * (1 - raised)
            celebrationEndsAt = now.addingTimeInterval(CatLayout.recoverDuration - animationPhase)
            statusText = "Tab gone — back to bed"
        } else {
            beginReturnHome()
        }
    }

    /// Resolve the original tab by identity, allowing navigation within the same
    /// distraction. Revalidate atomically at close time; never close a replacement tab.
    func closeChromeTab(_ target: ChromeTarget,
                        execute: (String) -> String? = FocusCatController.executeChromeScript) -> Bool {
        Self.performClose(target, execute: execute)
    }

    nonisolated private static func performClose(_ target: ChromeTarget,
                        execute: (String) -> String?) -> Bool {
        let identityGuard = Self.identityGuard(for: target)
        // A page can navigate between the read and close Apple events. Retry a
        // bounded number of times, always checking identity and classification.
        for _ in 0..<3 {
            let read = """
            if application id "\(target.bundleIdentifier)" is not running then return "changed"
            tell application id "\(target.bundleIdentifier)"
                \(identityGuard)
                return URL of active tab of front window
            end tell
            """
            guard let currentURL = execute(read),
                  Self.distractionLabel(for: currentURL) == target.label else { return false }
            let close = Self.closeScript(for: target, expectedURL: currentURL)
            let result = execute(close)
            if result == "closed" { return true }
            if result != "navigated" { return false }
        }
        return false
    }

    nonisolated static func closeScript(for target: ChromeTarget, expectedURL: String) -> String {
        """
        if application id "\(target.bundleIdentifier)" is not running then return "changed"
        tell application id "\(target.bundleIdentifier)"
            \(identityGuard(for: target))
            considering case
                if (URL of active tab of front window) is not \(scriptLiteral(expectedURL)) then return "navigated"
            end considering
            close tab id \(scriptLiteral(target.tabID)) of window id \(scriptLiteral(target.windowID))
            return "closed"
        end tell
        """
    }

    nonisolated private static func executeChromeScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        return error == nil ? result : nil
    }

    nonisolated private static func distractionLabel(for urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }
        if (host == "youtube.com" || host.hasSuffix(".youtube.com")),
           (url.path.lowercased() == "/shorts" || url.path.lowercased().hasPrefix("/shorts/")) {
            return "YouTube Shorts"
        }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            return "Instagram"
        }
        return nil
    }

    nonisolated private static let chromeBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary"
    ]
}
