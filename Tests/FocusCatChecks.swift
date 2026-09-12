import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main
struct FocusCatChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let artwork = CatLayout.artwork
        precondition(artwork.manifest.source == "workcat-v3/workcat_final.gif")
        precondition(artwork.clips.count == 7)
        precondition(abs(CatLayout.closeTime - 1.3) < 1e-8)
        precondition(CatLayout.reachDuration > CatLayout.closeTime)
        precondition(CatLayout.recoverDuration >= 0.9)
        for (_, clip) in artwork.clips {
            precondition(!clip.frames.isEmpty)
            for frame in clip.frames {
                let b = frame.bounds.offsetBy(dx: artwork.manifest.paddingX, dy: artwork.manifest.paddingY)
                precondition(b.minX >= 0 && b.maxX <= CatLayout.drawingSize.width)
                precondition(b.minY >= 0 && b.maxY <= CatLayout.drawingSize.height)
            }
        }
        // Loop and endpoint selection must remain valid after long idle periods.
        _ = artwork.frame("sleep", seconds: 1e8)
        _ = artwork.frame("wake", seconds: .infinity)
        precondition(artwork.frame("reach", seconds: 100).body == artwork.clips["reach"]!.frames.last!.body)
        precondition(CatGait.walk.phaseAdvance(distance: 0) == 0)
        precondition(abs(CatGait.walk.phaseAdvance(distance: CatGait.walk.distancePerLoop) - 0.6) < 1e-8)
        let right = CatLayout.pawContact(facingRight: true), left = CatLayout.pawContact(facingRight: false)
        precondition(abs(right.y - left.y) < 1e-8)
        // Mirror around the source cat's x=72 axis, including transparent margins.
        precondition(abs((right.x + left.x)/2 - (15 + artwork.manifest.paddingX + 72)) < 1e-8)

        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases: [(String, FocusCatPose, Double, Bool)] = [
            ("sleep", .sleeping, 0.8, true), ("wake", .waking, 0.7, true),
            ("walk", .running, 0.25, true), ("reach", .reaching, 0.7, true),
            ("paw", .reaching, 1.1, true), ("recover", .celebrating, 0.4, true),
            ("settle", .settling, 0.7, true), ("mirror", .sleeping, 0.8, false)
        ]
        for (name, pose, phase, facing) in cases {
            let view = WhiteFocusCat(pose: pose, facingRight: facing, phase: phase)
                .frame(width: CatLayout.drawingSize.width, height: CatLayout.drawingSize.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            guard let image = renderer.cgImage,
                  let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("\(name).png") as CFURL,
                                                                    UTType.png.identifier as CFString, 1, nil) else {
                preconditionFailure("Native cat view did not render")
            }
            CGImageDestinationAddImage(destination, image, nil)
            precondition(CGImageDestinationFinalize(destination))
        }

        // Exercise the actual controller and NSPanel with a deterministic clock.
        // Browser monitoring is disabled; preview never closes a real tab.
        let suite = "FocusCatChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date()
        let controller = FocusCatController(defaults: defaults, browserMonitoringEnabled: false, clock: { now })
        let target = FocusCatController.ChromeTarget(windowID: "42", tabID: "73",
            bundleIdentifier: "com.google.Chrome", tabIndex: 2,
            url: "https://www.youtube.com/shorts/original", title: "Shorts",
            windowBounds: .zero, label: "YouTube Shorts")
        func checkClose(_ replies: [String?], expected: Bool) {
            var replies = replies
            let result = controller.closeChromeTab(target) { script in
                precondition(script.contains("((id of front window) as text) is not \"42\""))
                precondition(script.contains("((id of active tab of front window) as text) is not \"73\""))
                precondition(!script.contains("active tab index"))
                var compilationError: NSDictionary?
                precondition(NSAppleScript(source: script)!.compileAndReturnError(&compilationError), "Chrome script does not compile: \(String(describing: compilationError))")
                precondition(!replies.isEmpty)
                return replies.removeFirst()
            }
            precondition(result == expected && replies.isEmpty)
        }
        checkClose(["https://www.youtube.com/shorts/next", "closed"], expected: true)
        checkClose(["https://www.youtube.com/shorts/next", "navigated",
                    "https://www.youtube.com/shorts/third", "closed"], expected: true)
        checkClose(["https://www.youtube.com/watch?v=lesson"], expected: false)
        checkClose(["https://www.youtube.com/shortstuff"], expected: false)
        checkClose(["https://www.youtube.com.evil.test/shorts/a"], expected: false)
        checkClose(["changed"], expected: false)
        checkClose([nil], expected: false)
        checkClose(["https://www.youtube.com/shorts/next", "changed"], expected: false)
        checkClose(Array(repeating: ["https://www.youtube.com/shorts/next", "navigated"], count: 3).flatMap { $0 }, expected: false)
        let instagram = FocusCatController.ChromeTarget(windowID: "42", tabID: "73",
            bundleIdentifier: "com.google.Chrome", tabIndex: 2,
            url: "https://www.instagram.com/", title: "Instagram",
            windowBounds: .zero, label: "Instagram")
        var instagramResponses = ["https://www.instagram.com/reels/new/", "closed"]
        precondition(controller.closeChromeTab(instagram) { _ in instagramResponses.removeFirst() })
        precondition(WhiteFocusCat.attention(for: .waking, phase: 0.7) == 1)
        precondition(WhiteFocusCat.attention(for: .waking, phase: 1.4) == 0)
        precondition(WhiteFocusCat.attention(for: .running, phase: 0.7) == 0)
        print("PASS: stable tab identity, navigation retry, changed/safe tab guards, errors, retry limit, Instagram navigation, expression and wake cue")
        controller.start()
        precondition(controller.pose == .sleeping)
        controller.previewIntervention()
        precondition(controller.pose == .waking)
        var transitions: [String] = ["waking"]
        var prior = controller.pose
        var reachStart: Date?, recoverStart: Date?, clickTime: Double?
        var completed = false
        for _ in 0..<7200 {
            now = now.addingTimeInterval(1.0/60)
            controller.movementTick(now: now)
            if controller.pose != prior {
                transitions.append(String(describing: controller.pose))
                if controller.pose == .reaching { reachStart = now }
                if controller.pose == .celebrating { recoverStart = now }
                if prior == .celebrating {
                    precondition(now.timeIntervalSince(recoverStart!) >= CatLayout.recoverDuration - 0.02)
                }
                prior = controller.pose
            }
            if controller.statusText == "Got it!", clickTime == nil, let start = reachStart {
                clickTime = now.timeIntervalSince(start)
                precondition(controller.pose == .reaching)
                precondition(clickTime! >= CatLayout.closeTime - 0.02)
            }
            if controller.pose == .sleeping { completed = true; break }
        }
        precondition(completed && clickTime != nil)
        precondition(transitions == ["waking", "running", "reaching", "celebrating", "running", "settling", "sleeping"])
        precondition(controller.facingRight)
        // Manually closing/switching the tab during wake, walk, and reach must
        // cancel the intervention, with no delayed close against its replacement.
        for cancelPose in [FocusCatPose.waking, .running, .reaching] {
            controller.beginChromeIntervention(target, now: now)
            for _ in 0..<7200 {
                if controller.pose == cancelPose { break }
                now = now.addingTimeInterval(1.0/60)
                controller.movementTick(now: now)
            }
            precondition(controller.pose == cancelPose)
            controller.checkInterventionTarget(now: now, execute: { _ in nil })
            precondition(controller.pose == cancelPose) // transient error: wait
            controller.checkInterventionTarget(now: now, execute: { _ in "https://www.youtube.com/shorts/another" })
            precondition(controller.pose == cancelPose) // still the same distraction
            controller.checkInterventionTarget(now: now, execute: { _ in "changed" })
            var slept = false
            for _ in 0..<7200 {
                now = now.addingTimeInterval(1.0/60)
                controller.movementTick(now: now)
                precondition(controller.pose != .reaching)
                if controller.pose == .sleeping { slept = true; break }
            }
            precondition(slept)
        }
        print("PASS: tab removed during wake/walk/reach returns home; transient read errors do not cancel")
        // Cancelling a reach must not leave a delayed close or movement behind.
        controller.previewIntervention()
        controller.setEnabled(false)
        for _ in 0..<120 { now = now.addingTimeInterval(1.0/60); controller.movementTick(now: now) }
        precondition(controller.pose == .sleeping && !controller.isEnabled)
        controller.setEnabled(true)
        precondition(controller.pose == .sleeping)
        controller.setEnabled(false)
        if CommandLine.arguments.contains("--live-close-fixture") {
            // Only the explicitly created, uniquely named blank test tab is eligible.
            // Exercise the same generated close script against actual Chrome IDs.
            let marker = "about:blank#focus-cat-close-regression-20260911"
            func run(_ source: String) -> String {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
                precondition(error == nil, "Chrome integration error: \(String(describing: error))")
                return result ?? ""
            }
            let snapshot = run("""
            tell application id "com.google.Chrome"
                if (count of windows) is 0 then return ""
                if URL of active tab of front window is not "\(marker)" then return ""
                return ((id of front window) as text) & "~~~" & ((id of active tab of front window) as text)
            end tell
            """)
            let ids = snapshot.components(separatedBy: "~~~")
            precondition(ids.count == 2, "The dedicated blank test tab must be active")
            let fixture = FocusCatController.ChromeTarget(windowID: ids[0], tabID: ids[1],
                bundleIdentifier: "com.google.Chrome", tabIndex: 1, url: marker,
                title: "", windowBounds: .zero, label: "Fixture")
            precondition(run(FocusCatController.closeScript(for: fixture, expectedURL: marker + "-changed")) == "navigated")
            let wrongTab = FocusCatController.ChromeTarget(windowID: ids[0], tabID: "missing-fixture-id",
                bundleIdentifier: "com.google.Chrome", tabIndex: 1, url: marker,
                title: "", windowBounds: .zero, label: "Fixture")
            precondition(run(FocusCatController.closeScript(for: wrongTab, expectedURL: marker)) == "changed")
            precondition(run(FocusCatController.closeScript(for: fixture, expectedURL: marker)) == "closed")
            print("PASS: actual Chrome text IDs; URL and identity guards preserve fixture; exact fixture tab closes")
        }
        print("PASS: bundled frames, bounds, native view renders, gait calibration, paw contact, full intervention, hold/lower timing, cancel/re-enable")
        print("Sequence: \(transitions.joined(separator: " → "))")
    }
}
