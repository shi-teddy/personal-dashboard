import AppKit
import Combine
import Darwin

@main
struct PerformanceProbe {
    static func cpu() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "PerformanceProbe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let launch = Date()
        let controller = FocusCatController(defaults: defaults, browserMonitoringEnabled: false)
        controller.start()
        print("cat_start_ms=\(Date().timeIntervalSince(launch) * 1000)")
        var callbacks = 0
        var lastFrame: Date?
        var gaps: [Double] = []
        let subscription = controller.animation.$phase.dropFirst().sink { _ in
            callbacks += 1
            if let previous = lastFrame { gaps.append(Date().timeIntervalSince(previous)) }
            lastFrame = Date()
        }
        let idleCPU = cpu()
        RunLoop.main.run(until: Date().addingTimeInterval(30))
        print("idle_30s_cpu_seconds=\(cpu() - idleCPU) phase_callbacks=\(callbacks)")
        callbacks = 0; gaps = []; lastFrame = nil
        let previewStart = Date()
        controller.previewIntervention()
        while controller.pose != .sleeping && Date().timeIntervalSince(previewStart) < 40 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let sorted = gaps.sorted()
        print("preview_seconds=\(Date().timeIntervalSince(previewStart)) frames=\(callbacks) gap_p95_ms=\(sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.95)] * 1000) gaps_over_33ms=\(gaps.filter { $0 > 0.0334 }.count)")
        controller.setEnabled(false)
        withExtendedLifetime(subscription) {}

        let now = Date(timeIntervalSince1970: 1_789_380_000)
        let storage = root.appendingPathComponent("sessions.json")
        let sessions = (0..<9000).map { index in
            let start = now.addingTimeInterval(-Double(index) * 800 - 60)
            return ScreenTimeSession(appName: "Fixture", bundleIdentifier: "test.fixture", websiteDomain: nil,
                                     startedAt: start, endedAt: start.addingTimeInterval(60))
        }.reversed()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Array(sessions)).write(to: storage)
        let tracker = ScreenTimeTracker(defaults: defaults, storageURL: storage, nowProvider: { now },
            activitySampleProvider: { ScreenTimeActivitySample(appName: "Fixture", bundleIdentifier: "test.fixture", websiteDomain: nil) },
            idleSecondsProvider: { 0 }, automaticallyStarts: false)
        let begin = cpu()
        for _ in 0..<100 {
            _ = tracker.chartSegments(for: now, classificationRules: [])
            _ = tracker.focusDriftPoints(for: now, classificationRules: [])
            _ = tracker.productivitySummary(for: now, classificationRules: [])
            _ = tracker.topActivities(for: now, classificationRules: [])
        }
        print("analytics_100_cpu_seconds=\(cpu() - begin)")
        var writes = 0
        for index in 0..<12 {
            let before = try FileManager.default.attributesOfItem(atPath: storage.path)[.systemFileNumber] as? NSNumber
            tracker.recordSample(now: now.addingTimeInterval(Double(index) * 5))
            let after = try FileManager.default.attributesOfItem(atPath: storage.path)[.systemFileNumber] as? NSNumber
            if before != after { writes += 1 }
        }
        print("twelve_samples_atomic_writes=\(writes)")
    }
}
