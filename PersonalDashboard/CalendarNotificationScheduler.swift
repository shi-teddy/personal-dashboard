import Foundation
import os
import UserNotifications

struct CalendarNotificationDescriptor: Equatable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let eventID: UUID
}

enum CalendarNotificationPlanner {
    private static let reminderOffsets: [(suffix: String, seconds: TimeInterval, label: String)] = [
        ("30-minutes", 30 * 60, "30 minutes"),
        ("2-minutes", 2 * 60, "2 minutes")
    ]

    static func descriptors(for events: [CalendarEvent], now: Date) -> [CalendarNotificationDescriptor] {
        events.flatMap { event in
            reminderOffsets.compactMap { reminder in
                let fireDate = event.startAt.addingTimeInterval(-reminder.seconds)
                guard fireDate > now else { return nil }
                return CalendarNotificationDescriptor(
                    identifier: identifier(for: event.id, suffix: reminder.suffix),
                    title: reminder.seconds == 2 * 60 ? "Starting soon: \(event.title)" : "Upcoming: \(event.title)",
                    body: "Starts in \(reminder.label) at \(event.startAt.formatted(date: .omitted, time: .shortened)).",
                    fireDate: fireDate,
                    eventID: event.id
                )
            }
        }
    }

    static let identifierPrefix = "personal-dashboard.calendar-event."

    private static func identifier(for eventID: UUID, suffix: String) -> String {
        "\(identifierPrefix)\(eventID.uuidString).\(suffix)"
    }
}

@MainActor
protocol CalendarNotificationScheduling: AnyObject {
    func synchronize(events: [CalendarEvent], requestAuthorizationIfNeeded: Bool)
}

@MainActor
final class CalendarNotificationScheduler: CalendarNotificationScheduling {
    static let shared = CalendarNotificationScheduler()

    private let center: UNUserNotificationCenter
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.teddyshi.PersonalDashboard",
        category: "CalendarNotifications"
    )
    private var revision = 0

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func synchronize(events: [CalendarEvent], requestAuthorizationIfNeeded: Bool) {
        revision += 1
        let requestedRevision = revision
        let now = Date()
        let descriptors = CalendarNotificationPlanner.descriptors(for: events, now: now)

        Task { [weak self] in
            guard let self else { return }
            var settings = await center.notificationSettings()
            logger.info("Authorization status: \(settings.authorizationStatus.rawValue)")

            if settings.authorizationStatus == .notDetermined,
               requestAuthorizationIfNeeded,
               !descriptors.isEmpty {
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
                } catch {
                    logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                }
                settings = await center.notificationSettings()
            }

            guard requestedRevision == revision else { return }
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            guard allowed else { return }

            let desiredIdentifiers = Set(descriptors.map(\.identifier))
            let pending = await center.pendingNotificationRequests()
            guard requestedRevision == revision else { return }
            let staleIdentifiers = pending.lazy
                .map(\.identifier)
                .filter { identifier in
                    identifier.hasPrefix(CalendarNotificationPlanner.identifierPrefix)
                        && !desiredIdentifiers.contains(identifier)
                }
            center.removePendingNotificationRequests(withIdentifiers: Array(staleIdentifiers))

            for descriptor in descriptors {
                guard requestedRevision == revision else { return }
                let content = UNMutableNotificationContent()
                content.title = descriptor.title
                content.body = descriptor.body
                content.sound = .default
                content.userInfo = ["calendarEventID": descriptor.eventID.uuidString]

                let components = Calendar.current.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                    from: descriptor.fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: descriptor.identifier,
                    content: content,
                    trigger: trigger
                )
                do {
                    try await center.add(request)
                } catch {
                    logger.error("Could not schedule \(descriptor.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
