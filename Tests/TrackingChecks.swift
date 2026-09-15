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
        try checkTopActivityAggregation(in: root, defaults: defaults)
        try checkUnsampledTimeIsNotRecorded(in: root, defaults: defaults)
        try checkBatchingAndCaches(in: root, defaults: defaults)
        checkNeutralIsExcludedFromProductivityScore()
        checkOverlappingSamples(in: root, defaults: defaults)
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
        _ end: String,
        websiteDomain: String? = nil
    ) -> ScreenTimeSession {
        ScreenTimeSession(
            appName: name,
            bundleIdentifier: identifier,
            websiteDomain: websiteDomain,
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

    private static func checkTopActivityAggregation(in root: URL, defaults: UserDefaults) throws {
        let storage = root.appendingPathComponent("top-activities.json")
        try write([
            session("Work", "test.work", "2026-09-11T03:50:00-04:00", "2026-09-11T04:10:00-04:00"),
            session("Work", "test.work", "2026-09-11T05:00:00-04:00", "2026-09-11T05:30:00-04:00"),
            session("Chrome", "com.google.Chrome", "2026-09-11T06:00:00-04:00", "2026-09-11T06:20:00-04:00", websiteDomain: "example.com"),
            session("Safari", "com.apple.Safari", "2026-09-11T07:00:00-04:00", "2026-09-11T07:10:00-04:00", websiteDomain: "example.com"),
            session("Chrome", "com.google.Chrome", "2026-09-11T08:00:00-04:00", "2026-09-11T08:08:00-04:00", websiteDomain: "newtab"),
            session("Messages", "test.messages", "2026-09-12T03:50:00-04:00", "2026-09-12T04:10:00-04:00")
        ], to: storage)
        let subject = tracker(
            storageURL: storage,
            now: { date("2026-09-12T04:30:00-04:00") },
            defaults: defaults
        )
        let rules = [
            rule("Work", "test.work", .flow),
            rule("Example", "example.com", .brainrot, kind: .website)
        ]
        let day = date("2026-09-11T12:00:00-04:00")
        let activities = subject.topActivities(for: day, classificationRules: rules, limit: 10)

        precondition(activities.count == 4)
        precondition(activities[0].id == "application:test.work")
        precondition(activities[0].duration == 40 * 60 && activities[0].sessionCount == 2)
        precondition(activities[0].classification == .flow)
        precondition(activities[1].id == "website:example.com")
        precondition(activities[1].duration == 30 * 60 && activities[1].sessionCount == 2)
        precondition(activities[1].classification == .brainrot)
        precondition(activities[2].duration == 10 * 60 && activities[2].sessionCount == 1)
        precondition(activities[3].id == "application:com.google.chrome")
        precondition(activities[3].name == "Chrome" && activities[3].kind == .application)
        precondition(activities[3].duration == 8 * 60 && activities[3].sessionCount == 1)
        precondition(activities.reduce(0) { $0 + $1.duration } == subject.duration(for: day))
        precondition(subject.topActivities(for: day, classificationRules: rules, limit: 2) == Array(activities.prefix(2)))
        precondition(subject.shortDuration(activities[0].duration) == "40m")
        print("PASS: top apps/sites aggregate, group, clip, sort, limit, and display exact durations")
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

    private static func checkBatchingAndCaches(in root: URL, defaults: UserDefaults) throws {
        let storage = root.appendingPathComponent("batching.json")
        var now = date("2026-09-11T12:00:00-04:00")
        let subject = tracker(storageURL: storage, now: { now }, defaults: defaults,
            samples: { ScreenTimeActivitySample(appName: "Flow", bundleIdentifier: "test.flow", websiteDomain: nil) })
        for _ in 0..<12 {
            subject.recordSample(now: now)
            now = now.addingTimeInterval(5)
        }
        precondition(subject.persistenceWriteCount == 2)
        let flow = [rule("Flow", "test.flow", .flow)]
        let summary = subject.productivitySummary(for: now, classificationRules: flow)
        let chart = subject.chartSegments(for: now, classificationRules: flow)
        let points = subject.focusDriftPoints(for: now, classificationRules: flow)
        let activities = subject.topActivities(for: now, classificationRules: flow)
        let count = subject.analyticsComputationCount
        for _ in 0..<10 {
            precondition(subject.productivitySummary(for: now, classificationRules: flow) == summary)
            precondition(subject.chartSegments(for: now, classificationRules: flow) == chart)
            precondition(subject.focusDriftPoints(for: now, classificationRules: flow) == points)
            precondition(subject.topActivities(for: now, classificationRules: flow) == activities)
        }
        precondition(subject.analyticsComputationCount == count)
        let drift = [rule("Flow", "test.flow", .brainrot)]
        precondition(subject.productivitySummary(for: now, classificationRules: drift).driftDuration == summary.focusDuration)
        precondition(subject.chartSegments(for: now, classificationRules: drift).allSatisfy { $0.classification == .brainrot })
        precondition(subject.focusDriftPoints(for: now, classificationRules: drift).last!.driftScore > 0)
        precondition(subject.topActivities(for: now, classificationRules: drift).first!.classification == .brainrot)
        subject.recordSample(now: now)
        precondition(subject.productivitySummary(for: now, classificationRules: flow).totalDuration > summary.totalDuration)
        subject.flushPersistence()
        let writes = subject.persistenceWriteCount
        subject.flushPersistence()
        precondition(subject.persistenceWriteCount == writes)
        let reloaded = tracker(storageURL: storage, now: { now }, defaults: defaults)
        precondition(subject.sessions == reloaded.sessions)
        precondition(subject.chartSegments(for: now, classificationRules: flow) == reloaded.chartSegments(for: now, classificationRules: flow))
        subject.clearHistory()
        precondition(subject.productivitySummary(for: now, classificationRules: flow).totalDuration == 0)
        precondition(subject.chartSegments(for: now, classificationRules: flow).isEmpty)
        precondition(subject.focusDriftPoints(for: now, classificationRules: flow).isEmpty)
        precondition(subject.topActivities(for: now, classificationRules: flow).isEmpty)
        let lifecycle = ScreenTimeTracker(defaults: defaults, storageURL: root.appendingPathComponent("lifecycle.json"),
            nowProvider: { now }, activitySampleProvider: { nil }, idleSecondsProvider: { 0 })
        precondition(lifecycle.hasSamplingTimer)
        lifecycle.suspendTracking(for: .systemSleep, now: now)
        precondition(!lifecycle.hasSamplingTimer)
        lifecycle.resumeTracking(from: .systemSleep, now: now)
        precondition(lifecycle.hasSamplingTimer)
        lifecycle.prepareForTermination()
        precondition(!lifecycle.hasSamplingTimer)
        print("PASS: batching, explicit flush, unchanged-write suppression, session/rule/clear cache invalidation")
    }

    private static func checkNeutralIsExcludedFromProductivityScore() {
        let summary = ScreenTimeProductivitySummary(
            focusDuration: 4 * 60 * 60,
            neutralDuration: 10 * 60 * 60,
            driftDuration: 60 * 60
        )
        precondition(summary.totalDuration == 15 * 60 * 60)
        precondition(summary.scoredDuration == 5 * 60 * 60)
        precondition(summary.score == 80 && summary.grade == "B−")

        let neutralOnly = ScreenTimeProductivitySummary(
            focusDuration: 0,
            neutralDuration: 10 * 60 * 60,
            driftDuration: 0
        )
        precondition(neutralOnly.score == 0 && neutralOnly.grade == "—")
        print("PASS: Neutral time is excluded from productivity score and grade eligibility")
    }

    private static func checkOverlappingSamples(in root: URL, defaults: UserDefaults) {
        let now = date("2026-09-11T12:00:00-04:00")
        let subject = tracker(storageURL: root.appendingPathComponent("overlap.json"), now: { now }, defaults: defaults)
        var finished = false
        Task { @MainActor in
            var resume: CheckedContinuation<ScreenTimeActivitySample?, Never>?
            let pending = Task { @MainActor in
                await subject.requestSample(provider: { await withCheckedContinuation { resume = $0 } })
            }
            while resume == nil { await Task.yield() }
            await subject.requestSample(provider: { preconditionFailure("Overlapping sample") })
            subject.suspendTracking(for: .sessionInactive, now: now)
            resume?.resume(returning: ScreenTimeActivitySample(appName: "Stale", bundleIdentifier: "test.stale", websiteDomain: nil))
            await pending.value
            precondition(subject.sessions.isEmpty && !subject.sampleInFlight)
            finished = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        precondition(finished)
        print("PASS: overlapping samples prevented; pre-lock replies discarded")
    }

    private static func rule(
        _ name: String,
        _ identifier: String,
        _ classification: ProductivityClassification,
        kind: ActivitySourceKind = .application
    ) -> ActivityClassificationRule {
        ActivityClassificationRule(
            displayName: name,
            identifier: identifier,
            kind: kind,
            classification: classification,
            subgroupID: UUID()
        )
    }
}
