import AppKit
import Combine
import Foundation

struct ScreenTimeSession: Identifiable, Codable, Equatable {
    var id = UUID()
    let appName: String
    let bundleIdentifier: String
    let websiteDomain: String?
    let startedAt: Date
    var endedAt: Date

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

struct ScreenTimeActivitySample: Equatable {
    let appName: String
    let bundleIdentifier: String
    let websiteDomain: String?
}

struct ScreenTimeSummary: Equatable {
    let name: String
    let duration: TimeInterval
    let sessionCount: Int

    var averageDuration: TimeInterval {
        sessionCount == 0 ? 0 : duration / Double(sessionCount)
    }
}

struct ScreenTimeChartSegment: Identifiable, Equatable {
    let id: String
    let hourIndex: Int
    let startMinute: Double
    let endMinute: Double
    let activityWindowStartMinute: Double
    let activityWindowEndMinute: Double
    let trackedDuration: TimeInterval
    let activityName: String
    let classification: ProductivityClassification
}

struct FocusDriftPoint: Identifiable, Equatable {
    let windowIndex: Int
    let focusScore: Double
    let driftScore: Double

    var id: Int { windowIndex }
}

struct ScreenTimeProductivitySummary: Equatable {
    let focusDuration: TimeInterval
    let neutralDuration: TimeInterval
    let driftDuration: TimeInterval

    var totalDuration: TimeInterval { focusDuration + neutralDuration + driftDuration }

    var score: Int {
        guard totalDuration > 0 else { return 0 }
        let weightedDuration = focusDuration + (neutralDuration * 0.5)
        return Int((weightedDuration / totalDuration * 100).rounded())
    }

    var grade: String {
        guard totalDuration > 0 else { return "—" }
        return switch score {
        case 97...: "A+"
        case 93...: "A"
        case 90...: "A−"
        case 87...: "B+"
        case 83...: "B"
        case 80...: "B−"
        case 77...: "C+"
        case 73...: "C"
        case 70...: "C−"
        case 67...: "D+"
        case 63...: "D"
        case 60...: "D−"
        default: "F"
        }
    }

    func duration(for classification: ProductivityClassification) -> TimeInterval {
        switch classification {
        case .flow: focusDuration
        case .neutral: neutralDuration
        case .brainrot: driftDuration
        }
    }
}

struct ScreenTimeActivitySummary: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: ActivitySourceKind
    let classification: ProductivityClassification
    let duration: TimeInterval
    let sessionCount: Int
}

@MainActor
final class ScreenTimeTracker: ObservableObject {
    @Published private(set) var sessions: [ScreenTimeSession] = []
    @Published private(set) var isTracking = false
    @Published private(set) var lastError: String?

    private let sampleInterval: TimeInterval = 5
    private let idleThreshold: TimeInterval
    private let retentionInterval: TimeInterval = 90 * 24 * 60 * 60
    private let clearedSourcesKey = "personal-dashboard.cleared-unclassified-sources.v1"
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private let storageURL: URL
    private let nowProvider: () -> Date
    private let activitySampleProvider: (() -> ScreenTimeActivitySample?)?
    private let idleSecondsProvider: () -> TimeInterval
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastSampleAt: Date?
    private var activeSessionID: UUID?
    enum SuspensionReason: Hashable {
        case systemSleep
        case sessionInactive
        case displaySleep
    }
    private var suspensionReasons: Set<SuspensionReason> = []
    private var clearedSourceCutoffs: [String: Date] = [:]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let ignoredBundleIdentifiers: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.LockScreen",
        "com.apple.ScreenSaver.Engine",
        "com.apple.ScreenSaver.Engine.legacy"
    ]

    private static let ignoredApplicationNames: Set<String> = [
        "loginwindow",
        "Lock Screen",
        "ScreenSaverEngine"
    ]

    init(
        workspace: NSWorkspace = .shared,
        defaults: UserDefaults = .standard,
        storageURL: URL? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        activitySampleProvider: (() -> ScreenTimeActivitySample?)? = nil,
        idleSecondsProvider: @escaping () -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: CGEventType(rawValue: UInt32.max)!
            )
        },
        idleThreshold: TimeInterval = 5 * 60,
        automaticallyStarts: Bool = true
    ) {
        self.workspace = workspace
        self.defaults = defaults
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.nowProvider = nowProvider
        self.activitySampleProvider = activitySampleProvider
        self.idleSecondsProvider = idleSecondsProvider
        self.idleThreshold = idleThreshold
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadClearedSourceCutoffs()
        loadSessions()
        removeExpiredSessions(now: nowProvider())
        if automaticallyStarts {
            installLifecycleObservers()
            startTracking()
        }
    }

    deinit {
        timer?.invalidate()
        for observer in workspaceObservers {
            workspace.notificationCenter.removeObserver(observer)
        }
    }

    private func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        recordSample(now: nowProvider())
        timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recordSample(now: self.nowProvider())
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func clearHistory() {
        sessions.removeAll()
        lastSampleAt = nil
        activeSessionID = nil
        saveSessions()
        if isTracking { recordSample(now: nowProvider()) }
    }

    func refresh() {
        if isTracking { recordSample(now: nowProvider()) }
        objectWillChange.send()
    }

    /// Hides the sources currently awaiting classification without deleting their
    /// screen-time history. If one is tracked again after this cutoff, it appears
    /// in Unclassified again so new activity is never silently ignored.
    func clearUnclassifiedSources(_ sources: [TrackedActivitySource], now: Date = Date()) {
        guard !sources.isEmpty else { return }
        for source in sources {
            clearedSourceCutoffs[source.id] = now
        }
        saveClearedSourceCutoffs()
        objectWillChange.send()
    }

    var todayDuration: TimeInterval {
        duration(for: trackingDay(containing: Date()))
    }

    var formattedTodayDuration: String {
        formatDuration(todayDuration, includeMinutesLabel: true)
    }

    func duration(for date: Date) -> TimeInterval {
        let interval = trackingInterval(for: date)
        return sessions.reduce(0) { $0 + overlap(of: $1, with: interval) }
    }

    func formattedDuration(for date: Date) -> String {
        formatDuration(duration(for: date), includeMinutesLabel: true)
    }

    func chartSegments(
        for date: Date,
        classificationRules: [ActivityClassificationRule]
    ) -> [ScreenTimeChartSegment] {
        let interval = trackingInterval(for: date)
        var segments: [ScreenTimeChartSegment] = []
        let bucketMinutes = 5
        let bucketCount = 60 / bucketMinutes

        for index in 0..<24 {
            guard let start = Calendar.current.date(byAdding: .hour, value: index, to: interval.start),
                  let end = Calendar.current.date(byAdding: .hour, value: index + 1, to: interval.start) else {
                continue
            }
            let hour = DateInterval(start: start, end: min(end, interval.end))
            var durationByBucket = Array(repeating: TimeInterval.zero, count: bucketCount)
            var earliestMinuteByBucket = Array(repeating: 60.0, count: bucketCount)
            var latestMinuteByBucket = Array(repeating: Double.zero, count: bucketCount)
            var activityByBucket = Array(repeating: [String: TimeInterval](), count: bucketCount)
            var classificationByBucket = Array(
                repeating: [ProductivityClassification: TimeInterval](),
                count: bucketCount
            )

            for session in sessions {
                let segmentStart = max(session.startedAt, hour.start)
                let segmentEnd = min(session.endedAt, hour.end)
                guard segmentEnd > segmentStart else { continue }

                let startMinute = segmentStart.timeIntervalSince(hour.start) / 60
                let endMinute = segmentEnd.timeIntervalSince(hour.start) / 60
                let firstBucket = max(0, min(bucketCount - 1, Int(startMinute / Double(bucketMinutes))))
                let lastBucket = max(0, min(bucketCount - 1, Int(endMinute.nextDown / Double(bucketMinutes))))
                let activityName = session.websiteDomain ?? session.appName
                let classification = classification(for: session, rules: classificationRules)

                for bucket in firstBucket...lastBucket {
                    let bucketStart = hour.start.addingTimeInterval(Double(bucket * bucketMinutes * 60))
                    let bucketEnd = min(hour.end, bucketStart.addingTimeInterval(Double(bucketMinutes * 60)))
                    let overlapStart = max(segmentStart, bucketStart)
                    let overlapEnd = min(segmentEnd, bucketEnd)
                    let occupied = max(0, overlapEnd.timeIntervalSince(overlapStart))
                    durationByBucket[bucket] += occupied
                    earliestMinuteByBucket[bucket] = min(
                        earliestMinuteByBucket[bucket],
                        overlapStart.timeIntervalSince(hour.start) / 60
                    )
                    latestMinuteByBucket[bucket] = max(
                        latestMinuteByBucket[bucket],
                        overlapEnd.timeIntervalSince(hour.start) / 60
                    )
                    activityByBucket[bucket][activityName, default: 0] += occupied
                    classificationByBucket[bucket][classification, default: 0] += occupied
                }
            }

            var firstBucket = 0
            while firstBucket < bucketCount {
                guard durationByBucket[firstBucket] > 0 else {
                    firstBucket += 1
                    continue
                }

                var endBucket = firstBucket
                while endBucket + 1 < bucketCount, durationByBucket[endBucket + 1] > 0 {
                    endBucket += 1
                }

                struct ClassificationChunk {
                    let classification: ProductivityClassification
                    let firstBucket: Int
                    var lastBucket: Int
                    var duration: TimeInterval
                    var earliestMinute: Double
                    var latestMinute: Double
                    var activityDurations: [String: TimeInterval]
                }

                var chunks: [ClassificationChunk] = []
                for bucket in firstBucket...endBucket {
                    let bucketClassification = dominantClassification(
                        in: classificationByBucket[bucket]
                    )
                    if chunks.last?.classification == bucketClassification {
                        let lastIndex = chunks.count - 1
                        chunks[lastIndex].lastBucket = bucket
                        chunks[lastIndex].duration += durationByBucket[bucket]
                        chunks[lastIndex].earliestMinute = min(
                            chunks[lastIndex].earliestMinute,
                            earliestMinuteByBucket[bucket]
                        )
                        chunks[lastIndex].latestMinute = max(
                            chunks[lastIndex].latestMinute,
                            latestMinuteByBucket[bucket]
                        )
                        for (name, duration) in activityByBucket[bucket] {
                            chunks[lastIndex].activityDurations[name, default: 0] += duration
                        }
                    } else {
                        chunks.append(ClassificationChunk(
                            classification: bucketClassification,
                            firstBucket: bucket,
                            lastBucket: bucket,
                            duration: durationByBucket[bucket],
                            earliestMinute: earliestMinuteByBucket[bucket],
                            latestMinute: latestMinuteByBucket[bucket],
                            activityDurations: activityByBucket[bucket]
                        ))
                    }
                }

                let latestMinute = chunks.map(\.latestMinute).max() ?? 0
                let totalDuration = chunks.reduce(0) { $0 + $1.duration }
                let availableDuration = max(0, (latestMinute - Double(firstBucket * bucketMinutes)) * 60)
                let displayedDuration = min(totalDuration, availableDuration)
                let durationScale = totalDuration > 0 ? displayedDuration / totalDuration : 0
                var cursorMinute = latestMinute - displayedDuration / 60

                for chunk in chunks {
                    let chunkDuration = chunk.duration * durationScale
                    let chunkEndMinute = cursorMinute + chunkDuration / 60
                    let dominantActivity = dominantActivityName(in: chunk.activityDurations)
                    segments.append(ScreenTimeChartSegment(
                        id: "hour-\(index)-buckets-\(chunk.firstBucket)-\(chunk.lastBucket)-\(chunk.classification.rawValue)",
                        hourIndex: index,
                        startMinute: cursorMinute,
                        endMinute: chunkEndMinute,
                        activityWindowStartMinute: chunk.earliestMinute,
                        activityWindowEndMinute: chunk.latestMinute,
                        trackedDuration: chunkDuration,
                        activityName: dominantActivity,
                        classification: chunk.classification
                    ))
                    cursorMinute = chunkEndMinute
                }

                firstBucket = endBucket + 1
            }
        }
        return segments
    }

    func productivitySummary(
        for date: Date,
        classificationRules: [ActivityClassificationRule]
    ) -> ScreenTimeProductivitySummary {
        let durations = classificationDurations(for: date, rules: classificationRules)
        return ScreenTimeProductivitySummary(
            focusDuration: durations[.flow, default: 0],
            neutralDuration: durations[.neutral, default: 0],
            driftDuration: durations[.brainrot, default: 0]
        )
    }

    func focusDriftPoints(
        for date: Date,
        classificationRules: [ActivityClassificationRule]
    ) -> [FocusDriftPoint] {
        let day = trackingInterval(for: date)
        let relevantSessions = sessions.filter { overlap(of: $0, with: day) > 0 }
        guard let latestEnd = relevantSessions.map({ min($0.endedAt, day.end) }).max() else { return [] }

        let windowDuration: TimeInterval = 30 * 60
        let lastWindow = min(47, max(0, Int(latestEnd.timeIntervalSince(day.start) / windowDuration)))
        var focusScore = 0.0
        var driftScore = 0.0
        var points = [FocusDriftPoint(windowIndex: 0, focusScore: 0, driftScore: 0)]

        for windowIndex in 0...lastWindow {
            let start = day.start.addingTimeInterval(Double(windowIndex) * windowDuration)
            let end = min(day.end, start.addingTimeInterval(windowDuration))
            let window = DateInterval(start: start, end: end)
            let chronologicalSessions = relevantSessions.compactMap {
                session -> (Date, TimeInterval, ProductivityClassification)? in
                let clippedStart = max(session.startedAt, window.start)
                let clippedEnd = min(session.endedAt, window.end)
                let duration = clippedEnd.timeIntervalSince(clippedStart)
                guard duration > 0 else { return nil }
                return (clippedStart, duration, classification(for: session, rules: classificationRules))
            }.sorted { lhs, rhs in lhs.0 < rhs.0 }

            for (_, duration, classification) in chronologicalSessions {
                let minutes = duration / 60
                switch classification {
                case .flow:
                    focusScore = min(30, focusScore + minutes)
                    driftScore = max(0, driftScore - minutes)
                case .neutral:
                    break
                case .brainrot:
                    focusScore = max(0, focusScore - minutes)
                    driftScore = min(30, driftScore + minutes)
                }
            }
            points.append(FocusDriftPoint(
                windowIndex: windowIndex + 1,
                focusScore: focusScore,
                driftScore: driftScore
            ))
        }
        return points
    }

    func topActivities(
        for date: Date,
        classificationRules: [ActivityClassificationRule],
        limit: Int = 3
    ) -> [ScreenTimeActivitySummary] {
        let day = trackingInterval(for: date)
        var durations: [String: TimeInterval] = [:]
        var counts: [String: Int] = [:]
        var sources: [String: TrackedActivitySource] = [:]
        var classifications: [String: ProductivityClassification] = [:]

        for session in sessions {
            let duration = overlap(of: session, with: day)
            guard duration > 0 else { continue }
            let source = source(for: session)
            durations[source.id, default: 0] += duration
            counts[source.id, default: 0] += 1
            sources[source.id] = source
            classifications[source.id] = classification(for: session, rules: classificationRules)
        }

        return durations
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(max(0, limit))
            .compactMap { id, duration in
                guard let source = sources[id], let classification = classifications[id] else { return nil }
                return ScreenTimeActivitySummary(
                    id: id,
                    name: source.displayName,
                    kind: source.kind,
                    classification: classification,
                    duration: duration,
                    sessionCount: counts[id, default: 0]
                )
            }
    }

    func trackingDay(containing moment: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: moment)
        let fourAM = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: startOfDay) ?? startOfDay
        if moment < fourAM {
            return calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        }
        return startOfDay
    }

    var topActivityToday: ScreenTimeSummary? {
        let day = trackingInterval(for: trackingDay(containing: Date()))
        var durations: [String: TimeInterval] = [:]
        var counts: [String: Int] = [:]
        for session in sessions {
            let duration = overlap(of: session, with: day)
            guard duration > 0 else { continue }
            let name = session.websiteDomain ?? session.appName
            durations[name, default: 0] += duration
            counts[name, default: 0] += 1
        }
        guard let top = durations.max(by: { $0.value < $1.value }) else { return nil }
        return ScreenTimeSummary(name: top.key, duration: top.value, sessionCount: counts[top.key, default: 0])
    }

    func shortDuration(_ duration: TimeInterval) -> String {
        formatDuration(duration, includeMinutesLabel: false)
    }

    var knownSources: [TrackedActivitySource] {
        var sources: [String: TrackedActivitySource] = [:]
        let currentTrackingDay = trackingInterval(for: trackingDay(containing: nowProvider()))
        for session in sessions.reversed() {
            guard session.endedAt > currentTrackingDay.start,
                  session.startedAt < currentTrackingDay.end else { continue }
            let source: TrackedActivitySource
            if let domain = session.websiteDomain, !domain.isEmpty {
                source = TrackedActivitySource(
                    displayName: domain,
                    identifier: domain,
                    kind: .website
                )
            } else {
                source = TrackedActivitySource(
                    displayName: session.appName,
                    identifier: session.bundleIdentifier,
                    kind: .application
                )
            }
            if let clearedAt = clearedSourceCutoffs[source.id], session.endedAt <= clearedAt {
                continue
            }
            sources[source.id] = sources[source.id] ?? source
        }
        return sources.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var storagePath: String { storageURL.path }

    private func classificationDurations(
        for date: Date,
        rules: [ActivityClassificationRule]
    ) -> [ProductivityClassification: TimeInterval] {
        let day = trackingInterval(for: date)
        var durations: [ProductivityClassification: TimeInterval] = [:]
        for session in sessions {
            let duration = overlap(of: session, with: day)
            guard duration > 0 else { continue }
            durations[classification(for: session, rules: rules), default: 0] += duration
        }
        return durations
    }

    private func source(for session: ScreenTimeSession) -> TrackedActivitySource {
        if let domain = session.websiteDomain, !domain.isEmpty {
            return TrackedActivitySource(displayName: domain, identifier: domain, kind: .website)
        }
        return TrackedActivitySource(
            displayName: session.appName,
            identifier: session.bundleIdentifier,
            kind: .application
        )
    }

    private func classification(
        for session: ScreenTimeSession,
        rules: [ActivityClassificationRule]
    ) -> ProductivityClassification {
        let source = source(for: session)
        return rules.first { rule in
            guard rule.kind == source.kind else { return false }
            if rule.kind == .website {
                let domain = source.identifier.lowercased()
                let configured = rule.identifier.lowercased()
                return domain == configured || domain.hasSuffix(".\(configured)")
            }
            return rule.identifier.caseInsensitiveCompare(source.identifier) == .orderedSame
                || rule.identifier.caseInsensitiveCompare(source.displayName) == .orderedSame
                || rule.displayName.caseInsensitiveCompare(source.displayName) == .orderedSame
        }?.classification ?? .neutral
    }

    /// Dictionary iteration order is intentionally unspecified. Resolve equal-duration
    /// buckets using the declaration order of the classifications so an unrelated
    /// SwiftUI update can never make an old chart segment change color.
    private func dominantClassification(
        in durations: [ProductivityClassification: TimeInterval]
    ) -> ProductivityClassification {
        guard let longestDuration = durations.values.max() else { return .neutral }
        return ProductivityClassification.allCases.first {
            durations[$0] == longestDuration
        } ?? .neutral
    }

    private func dominantActivityName(in durations: [String: TimeInterval]) -> String {
        durations.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }.first?.key ?? "Tracked activity"
    }

    func recordSample(now: Date) {
        guard suspensionReasons.isEmpty else { return }
        removeExpiredSessions(now: now)
        if let previous = lastSampleAt, now.timeIntervalSince(previous) > sampleInterval * 3 {
            finishCurrentSession(at: previous.addingTimeInterval(sampleInterval))
            activeSessionID = nil
        }

        guard let identity = currentActivity() else {
            finishCurrentSession(at: now)
            activeSessionID = nil
            lastSampleAt = now
            saveSessions()
            return
        }

        if let last = sessions.last,
           activeSessionID == last.id,
           last.appName == identity.appName,
           last.bundleIdentifier == identity.bundleIdentifier,
           last.websiteDomain == identity.websiteDomain,
           now.timeIntervalSince(last.endedAt) <= sampleInterval * 3 {
            sessions[sessions.count - 1].endedAt = now
        } else {
            finishCurrentSession(at: now)
            let session = ScreenTimeSession(
                appName: identity.appName,
                bundleIdentifier: identity.bundleIdentifier,
                websiteDomain: identity.websiteDomain,
                startedAt: now,
                endedAt: now
            )
            sessions.append(session)
            activeSessionID = session.id
        }
        lastSampleAt = now
        saveSessions()
    }

    private func finishCurrentSession(at date: Date) {
        guard let activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let sampledBoundary = lastSampleAt?.addingTimeInterval(sampleInterval) ?? date
        let boundedEnd = min(date, sampledBoundary)
        sessions[index].endedAt = max(sessions[index].endedAt, boundedEnd)
    }

    func suspendTracking(for reason: SuspensionReason, now: Date) {
        finishCurrentSession(at: now)
        suspensionReasons.insert(reason)
        activeSessionID = nil
        lastSampleAt = nil
        saveSessions()
    }

    func resumeTracking(from reason: SuspensionReason, now: Date) {
        suspensionReasons.remove(reason)
        guard suspensionReasons.isEmpty else { return }
        recordSample(now: now)
    }

    private func installLifecycleObservers() {
        let center = workspace.notificationCenter
        let suspensions: [(Notification.Name, SuspensionReason)] = [
            (NSWorkspace.willSleepNotification, .systemSleep),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive),
            (NSWorkspace.screensDidSleepNotification, .displaySleep)
        ]
        for (name, reason) in suspensions {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.suspendTracking(for: reason, now: self.nowProvider())
                }
            })
        }
        let resumptions: [(Notification.Name, SuspensionReason)] = [
            (NSWorkspace.didWakeNotification, .systemSleep),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive),
            (NSWorkspace.screensDidWakeNotification, .displaySleep)
        ]
        for (name, reason) in resumptions {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.resumeTracking(from: reason, now: self.nowProvider())
                }
            })
        }
    }

    private func currentActivity() -> ScreenTimeActivitySample? {
        // Passive reading and video playback remain activity for five minutes; after
        // that, the tracker waits for fresh input instead of manufacturing idle time.
        guard idleSecondsProvider() < idleThreshold else { return nil }
        if let activitySampleProvider { return activitySampleProvider() }
        guard let application = workspace.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier else { return nil }
        let appName = application.localizedName ?? bundleIdentifier
        guard !Self.ignoredBundleIdentifiers.contains(bundleIdentifier),
              !Self.ignoredApplicationNames.contains(appName) else { return nil }
        return ScreenTimeActivitySample(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            websiteDomain: activeWebsiteDomain(for: bundleIdentifier)
        )
    }

    private func activeWebsiteDomain(for bundleIdentifier: String) -> String? {
        let script: String
        switch bundleIdentifier {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            script = """
            tell application id "\(bundleIdentifier)"
                if (count of windows) is 0 then return ""
                return URL of front document
            end tell
            """
        case "com.google.Chrome", "com.google.Chrome.canary",
             "com.microsoft.edgemac", "com.microsoft.edgemac.Dev",
             "com.brave.Browser", "com.brave.Browser.beta":
            script = """
            tell application id "\(bundleIdentifier)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """
        default:
            return nil
        }

        var error: NSDictionary?
        guard let value = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
              error == nil,
              let components = URLComponents(string: value),
              var host = components.host?.lowercased(),
              !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private func overlap(of session: ScreenTimeSession, with interval: DateInterval) -> TimeInterval {
        let start = max(session.startedAt, interval.start)
        let end = min(session.endedAt, interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    private func trackingInterval(for date: Date) -> DateInterval {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: day) ?? day
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
        let end = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: nextDay) ?? nextDay
        return DateInterval(start: start, end: end)
    }

    private func formatDuration(_ duration: TimeInterval, includeMinutesLabel: Bool) -> String {
        let totalMinutes = max(0, Int(duration / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if includeMinutesLabel { return "\(hours)h \(minutes)min" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if totalMinutes > 0 { return "\(totalMinutes)m" }
        return duration > 0 ? "<1m" : "0m"
    }

    private static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PersonalDashboard", isDirectory: true)
            .appendingPathComponent("screen-time-sessions.json")
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            sessions = try decoder.decode([ScreenTimeSession].self, from: data)
            let originalCount = sessions.count
            sessions.removeAll { session in
                Self.ignoredBundleIdentifiers.contains(session.bundleIdentifier)
                    || Self.ignoredApplicationNames.contains(session.appName)
            }
            if sessions.count != originalCount { saveSessions() }
        } catch {
            lastError = "The saved screen-time history could not be read."
        }
    }

    private func saveSessions() {
        do {
            let folder = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try encoder.encode(sessions)
            try data.write(to: storageURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Screen-time history could not be saved."
        }
    }

    private func loadClearedSourceCutoffs() {
        guard let data = defaults.data(forKey: clearedSourcesKey),
              let cutoffs = try? decoder.decode([String: Date].self, from: data) else { return }
        clearedSourceCutoffs = cutoffs
    }

    private func saveClearedSourceCutoffs() {
        guard let data = try? encoder.encode(clearedSourceCutoffs) else { return }
        defaults.set(data, forKey: clearedSourcesKey)
    }

    private func removeExpiredSessions(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        let originalCount = sessions.count
        sessions.removeAll { $0.endedAt < cutoff }
        if sessions.count != originalCount { saveSessions() }
    }
}
