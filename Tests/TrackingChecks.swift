import Foundation

@main
@MainActor
struct TrackingChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("personal-dashboard-tracking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsSuite = "personal-dashboard-tracking-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        try checkTrackingDaySourceExpiry(in: root, defaults: defaults)
        try checkChronologicalFocusDrift(in: root, defaults: defaults)
        try checkStableChartTie(in: root, defaults: defaults)
        try checkUnsampledTimeIsNotRecorded(in: root, defaults: defaults)
        print("Tracking regression checks passed.")
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func write(_ sessions: [ScreenTimeSession], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sessions).write(to: url, options: .atomic)
    }

    private static func session(
        _ name: String,
        _ identifier: String,
        _ start: String,
        _ end: String
    ) -> ScreenTimeSession {
        ScreenTimeSession(
            appName: name,
            bundleIdentifier: identifier,
            websiteDomain: nil,
            startedAt: date(start),
            endedAt: date(end)
        )
    }

    private static func tracker(
        storageURL: URL,
        now: @escaping () -> Date,
        defaults: UserDefaults,
        samples: (() -> ScreenTimeActivitySample?)? = nil,
        idleSeconds: @escaping () -> TimeInterval = { 0 }
    ) -> ScreenTimeTracker {
        ScreenTimeTracker(
            defaults: defaults,
            storageURL: storageURL,
            nowProvider: now,
            activitySampleProvider: samples,
            idleSecondsProvider: idleSeconds,
            automaticallyStarts: false
        )
    }

    private static func checkTrackingDaySourceExpiry(in root: URL, defaults: UserDefaults) throws {
        let storage = root.appendingPathComponent("sources.json")
        var now = date("2026-09-11T00:30:00-04:00")
        let original = session(
            "Midnight App", "test.midnight",
            "2026-09-10T23:50:00-04:00", "2026-09-11T00:10:00-04:00"
        )
        try write([original], to: storage)
        let subject = tracker(storageURL: storage, now: { now }, defaults: defaults)
        precondition(subject.knownSources.map(\.identifier) == ["test.midnight"])

        subject.clearUnclassifiedSources(subject.knownSources, now: date("2026-09-11T00:35:00-04:00"))
        precondition(subject.knownSources.isEmpty)

        let reopened = session(
            "Midnight App", "test.midnight",
            "2026-09-11T00:40:00-04:00", "2026-09-11T00:41:00-04:00"
        )
        try write([original, reopened], to: storage)
        let reloaded = tracker(storageURL: storage, now: { now }, defaults: defaults)
        precondition(reloaded.knownSources.map(\.identifier) == ["test.midnight"])

        now = date("2026-09-11T04:00:00-04:00")
        precondition(reloaded.knownSources.isEmpty)
    }

    private static func checkChronologicalFocusDrift(in root: URL, defaults: UserDefaults) throws {
        let storage = root.appendingPathComponent("focus.json")
        try write([
            session("Flow", "test.flow", "2026-09-11T04:00:00-04:00", "2026-09-11T04:25:00-04:00"),
            session("Flow", "test.flow", "2026-09-11T04:30:00-04:00", "2026-09-11T04:40:00-04:00"),
            session("Drift", "test.drift", "2026-09-11T04:40:00-04:00", "2026-09-11T04:50:00-04:00"),
            session("Neutral", "test.neutral", "2026-09-11T04:50:00-04:00", "2026-09-11T04:55:00-04:00")
        ], to: storage)
        let subject = tracker(
            storageURL: storage,
            now: { date("2026-09-11T05:00:00-04:00") },
            defaults: defaults
        )
        let rules = [
            rule("Flow", "test.flow", .flow),
            rule("Drift", "test.drift", .brainrot),
            rule("Neutral", "test.neutral", .neutral)
        ]
        let points = subject.focusDriftPoints(for: date("2026-09-11T12:00:00-04:00"), classificationRules: rules)
        precondition(points[1].focusScore == 25 && points[1].driftScore == 0)
        precondition(points[2].focusScore == 20 && points[2].driftScore == 10)
    }

    private static func checkStableChartTie(in root: URL, defaults: UserDefaults) throws {
        let storage = root.appendingPathComponent("chart.json")
        try write([
            session("Drift", "test.drift", "2026-09-11T06:02:00-04:00", "2026-09-11T06:04:00-04:00"),
            session("Flow", "test.flow", "2026-09-11T06:00:00-04:00", "2026-09-11T06:02:00-04:00")
        ], to: storage)
        let subject = tracker(
            storageURL: storage,
            now: { date("2026-09-11T07:00:00-04:00") },
            defaults: defaults
        )
        let segments = subject.chartSegments(
            for: date("2026-09-11T12:00:00-04:00"),
            classificationRules: [
                rule("Flow", "test.flow", .flow),
                rule("Drift", "test.drift", .brainrot)
            ]
        )
        precondition(segments.count == 1 && segments[0].classification == .flow)
    }

    private static func checkUnsampledTimeIsNotRecorded(in root: URL, defaults: UserDefaults) throws {
        let storage = root.appendingPathComponent("sampling.json")
        var samples: [ScreenTimeActivitySample?] = [
            ScreenTimeActivitySample(appName: "Work", bundleIdentifier: "test.work", websiteDomain: nil),
            ScreenTimeActivitySample(appName: "Work", bundleIdentifier: "test.work", websiteDomain: nil),
            ScreenTimeActivitySample(appName: "Work", bundleIdentifier: "test.work", websiteDomain: nil),
            ScreenTimeActivitySample(appName: "Work", bundleIdentifier: "test.work", websiteDomain: nil)
        ]
        var now = date("2026-09-11T05:00:00-04:00")
        var idleSeconds: TimeInterval = 0
        let subject = tracker(
            storageURL: storage,
            now: { now },
            defaults: defaults,
            samples: { samples.removeFirst() },
            idleSeconds: { idleSeconds }
        )
        subject.recordSample(now: date("2026-09-11T05:00:00-04:00"))
        subject.recordSample(now: date("2026-09-11T05:00:05-04:00"))
        idleSeconds = 301
        subject.recordSample(now: date("2026-09-11T05:05:06-04:00"))
        precondition(subject.sessions.count == 1 && subject.sessions[0].duration == 10)
        let persisted = tracker(storageURL: storage, now: { now }, defaults: defaults)
        precondition(persisted.sessions.count == 1 && persisted.sessions[0].duration == 10)

        idleSeconds = 0
        subject.recordSample(now: date("2026-09-11T06:00:00-04:00"))
        precondition(subject.sessions.count == 2 && subject.sessions[0].duration == 10)
        now = date("2026-09-11T06:00:00-04:00")
        subject.suspendTracking(for: .sessionInactive, now: now)
        subject.suspendTracking(for: .displaySleep, now: now)
        subject.resumeTracking(from: .displaySleep, now: date("2026-09-12T05:00:00-04:00"))
        subject.recordSample(now: date("2026-09-12T05:00:00-04:00"))
        precondition(subject.sessions.count == 2)
        now = date("2026-09-12T05:00:00-04:00")
        subject.resumeTracking(from: .sessionInactive, now: now)
        precondition(subject.sessions.count == 3 && subject.sessions[1].duration == 0)
    }

    private static func rule(
        _ name: String,
        _ identifier: String,
        _ classification: ProductivityClassification
    ) -> ActivityClassificationRule {
        ActivityClassificationRule(
            displayName: name,
            identifier: identifier,
            kind: .application,
            classification: classification,
            subgroupID: UUID()
        )
    }
}
