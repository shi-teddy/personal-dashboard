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
    let activityName: String
}

@MainActor
final class ScreenTimeTracker: ObservableObject {
    @Published private(set) var sessions: [ScreenTimeSession] = []
    @Published private(set) var isTracking = false
    @Published private(set) var lastError: String?

    private struct ActivityIdentity: Equatable {
        let appName: String
        let bundleIdentifier: String
        let websiteDomain: String?
    }

    private let sampleInterval: TimeInterval = 5
    private let retentionInterval: TimeInterval = 90 * 24 * 60 * 60
    private let enabledKey = "personal-dashboard.screen-time-enabled.v1"
    private let defaults: UserDefaults
    private let workspace: NSWorkspace
    private var timer: Timer?
    private var lastSampleAt: Date?
    private var activeSessionID: UUID?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard, workspace: NSWorkspace = .shared) {
        self.defaults = defaults
        self.workspace = workspace
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadSessions()
        removeExpiredSessions()
        if defaults.bool(forKey: enabledKey) { startTracking() }
    }

    deinit { timer?.invalidate() }

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        defaults.set(true, forKey: enabledKey)
        recordSample()
        timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordSample() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stopTracking() {
        guard isTracking else { return }
        finishCurrentSession(at: Date())
        timer?.invalidate()
        timer = nil
        lastSampleAt = nil
        activeSessionID = nil
        isTracking = false
        defaults.set(false, forKey: enabledKey)
    }

    func clearHistory() {
        sessions.removeAll()
        lastSampleAt = nil
        activeSessionID = nil
        saveSessions()
        if isTracking { recordSample() }
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

    func chartSegments(for date: Date) -> [ScreenTimeChartSegment] {
        let interval = trackingInterval(for: date)
        var segments: [ScreenTimeChartSegment] = []

        for index in 0..<24 {
            guard let start = Calendar.current.date(byAdding: .hour, value: index, to: interval.start),
                  let end = Calendar.current.date(byAdding: .hour, value: index + 1, to: interval.start) else {
                continue
            }
            let hour = DateInterval(start: start, end: min(end, interval.end))
            for session in sessions {
                let segmentStart = max(session.startedAt, hour.start)
                let segmentEnd = min(session.endedAt, hour.end)
                guard segmentEnd > segmentStart else { continue }

                let startMinute = segmentStart.timeIntervalSince(hour.start) / 60
                let endMinute = segmentEnd.timeIntervalSince(hour.start) / 60
                segments.append(
                    ScreenTimeChartSegment(
                        id: "\(session.id.uuidString)-\(index)",
                        hourIndex: index,
                        startMinute: max(0, min(60, startMinute)),
                        endMinute: max(0, min(60, endMinute)),
                        activityName: session.websiteDomain ?? session.appName
                    )
                )
            }
        }
        return segments
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

    var storagePath: String { storageURL.path }

    private func recordSample(now: Date = Date()) {
        removeExpiredSessions(now: now)
        if let previous = lastSampleAt, now.timeIntervalSince(previous) > sampleInterval * 3 {
            finishCurrentSession(at: previous.addingTimeInterval(sampleInterval))
            activeSessionID = nil
        }

        guard let identity = currentActivity() else {
            finishCurrentSession(at: now)
            activeSessionID = nil
            lastSampleAt = now
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
        let currentEnd = sessions[index].endedAt
        sessions[index].endedAt = max(currentEnd, date)
        saveSessions()
    }

    private func currentActivity() -> ActivityIdentity? {
        guard let application = workspace.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return ActivityIdentity(
            appName: application.localizedName ?? bundleIdentifier,
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
        return "<1m"
    }

    private var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PersonalDashboard", isDirectory: true)
            .appendingPathComponent("screen-time-sessions.json")
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            sessions = try decoder.decode([ScreenTimeSession].self, from: data)
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

    private func removeExpiredSessions(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        let originalCount = sessions.count
        sessions.removeAll { $0.endedAt < cutoff }
        if sessions.count != originalCount { saveSessions() }
    }
}
