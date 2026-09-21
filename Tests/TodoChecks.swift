import Foundation

@main
@MainActor
struct TodoChecks {
    private static let todoKey = "personal-dashboard.todos.v1"
    private static let dividerKey = "personal-dashboard.todo-divider-index.v1"
    private static let goalKey = "personal-dashboard.goals.v1"

    static func main() throws {
        try checkOrderingAndDividerDeletion()
        try checkDailyFourAMBoundary()
        try checkPersistence()
        try checkCompletionInsights()
        try checkCalendarNotifications()
        print("Dashboard persistence checks passed.")
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "todo-checks.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private static func store(
        defaults: UserDefaults,
        now: @escaping () -> Date,
        calendarNotificationScheduler: CalendarNotificationScheduling? = nil
    ) -> DashboardStore {
        DashboardStore(
            defaults: defaults,
            nowProvider: now,
            automaticallySchedulesTodoCleanup: false,
            calendarNotificationScheduler: calendarNotificationScheduler
                ?? RecordingCalendarNotificationScheduler()
        )
    }

    private static func removeSeedTodos(from subject: DashboardStore) {
        for todo in subject.todos {
            subject.deleteTodo(todo.id)
        }
    }

    private static func checkOrderingAndDividerDeletion() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = date("2026-09-11T12:00:00-04:00")
        let subject = store(defaults: defaults, now: { now })
        removeSeedTodos(from: subject)

        subject.addTodo(title: "First")
        subject.addTodo(title: "Second")
        subject.setTodoDividerIndex(1)
        let firstID = subject.todos.first { $0.title == "First" }!.id
        subject.toggleTodo(firstID)
        subject.addTodo(title: "Third")

        precondition(subject.todos.map(\.title) == ["Second", "Third", "First"])
        precondition(subject.todos.map(\.isCompleted) == [false, false, true])
        precondition(subject.todoDividerIndex == 1)

        subject.toggleTodo(firstID)
        precondition(subject.todos.map(\.title) == ["Second", "Third", "First"])
        precondition(subject.todos.allSatisfy { !$0.isCompleted })

        subject.setTodoDividerIndex(2)
        subject.deleteTodo(subject.todos[0].id)
        precondition(subject.todoDividerIndex == 1)
        subject.deleteTodo(subject.todos[1].id)
        precondition(subject.todoDividerIndex == 1)
        precondition(subject.todos.map(\.title) == ["Third"])

        subject.addTodo(title: "Fourth")
        precondition(subject.todoDividerIndex == 1)
        precondition(subject.todos.map(\.title) == ["Third", "Fourth"])
        subject.deleteTodo(subject.todos[0].id)
        precondition(subject.todoDividerIndex == 0)
        precondition(subject.todos.map(\.title) == ["Fourth"])
    }

    private static func checkDailyFourAMBoundary() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let beforeCutoff = date("2026-09-12T03:30:00-04:00")
        let todos = [
            TodoItem(title: "Unchecked"),
            TodoItem(title: "Before previous cutoff", completedAt: date("2026-09-11T03:59:00-04:00")),
            TodoItem(title: "Yesterday evening", completedAt: date("2026-09-11T20:00:00-04:00")),
            TodoItem(title: "Early this morning", completedAt: date("2026-09-12T03:00:00-04:00"))
        ]
        defaults.set(try JSONEncoder().encode(todos), forKey: todoKey)
        defaults.set(1, forKey: dividerKey)

        let subject = store(defaults: defaults, now: { beforeCutoff })
        precondition(subject.todos.map(\.title) == ["Unchecked", "Yesterday evening", "Early this morning"])
        precondition(subject.todoCompletionHistory.map(\.title) == ["Before previous cutoff", "Yesterday evening", "Early this morning"])
        precondition(subject.todoDividerIndex == 1)

        subject.removeCompletedTodosAtDailyCutoff(now: date("2026-09-12T04:00:00-04:00"))
        precondition(subject.todos.map(\.title) == ["Unchecked"])
        precondition(subject.todoCompletionHistory.count == 3)

        let persisted = try JSONDecoder().decode(
            [TodoItem].self,
            from: defaults.data(forKey: todoKey)!
        )
        precondition(persisted.map(\.title) == ["Unchecked"])
    }

    private static func checkPersistence() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = date("2026-09-11T12:00:00-04:00")

        var subject: DashboardStore? = store(defaults: defaults, now: { now })
        removeSeedTodos(from: subject!)
        subject!.addTodo(title: "Keep active")
        subject!.addTodo(title: "Keep completed")
        subject!.setTodoDividerIndex(1)
        let completedID = subject!.todos[1].id
        subject!.toggleTodo(completedID)
        subject = nil

        let restored = store(defaults: defaults, now: { now.addingTimeInterval(60) })
        precondition(restored.todos.map(\.title) == ["Keep completed", "Keep active"])
        precondition(restored.todos.map(\.isCompleted) == [false, true])
        precondition(restored.todoDividerIndex == 1)

        restored.addTodo(title: "New active")
        precondition(restored.todos.map(\.title) == ["Keep completed", "New active", "Keep active"])
        precondition(restored.todoDividerIndex == 1)
    }

    private static func checkCompletionInsights() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = date("2026-09-11T14:00:00-04:00")
        defaults.set(try JSONEncoder().encode([TodoItem]()), forKey: todoKey)
        defaults.set(try JSONEncoder().encode([GoalItem]()), forKey: goalKey)
        var subject: DashboardStore? = store(defaults: defaults, now: { now })

        subject!.addTodo(title: "Finish reading")
        let todoID = subject!.todos[0].id
        subject!.toggleTodo(todoID)
        precondition(subject!.todoCompletionHistory.map(\.title) == ["Finish reading"])
        subject!.toggleTodo(todoID)
        precondition(subject!.todoCompletionHistory.isEmpty)
        subject!.toggleTodo(todoID)

        subject!.addGoal(title: "Ship dashboard", progress: 90)
        let goalID = subject!.goals[0].id
        subject!.setGoalProgress(goalID, progress: 100)
        precondition(subject!.goals.isEmpty)
        precondition(subject!.completedGoals.map(\.title) == ["Ship dashboard"])
        precondition(subject!.goalCelebration?.title == "Ship dashboard")
        subject!.dismissGoalCelebration()
        precondition(subject!.goalCelebration == nil)
        subject = nil

        let restored = store(defaults: defaults, now: { now.addingTimeInterval(60) })
        precondition(restored.todoCompletionHistory.map(\.title) == ["Finish reading"])
        precondition(restored.completedGoals.map(\.title) == ["Ship dashboard"])
    }

    private static func checkCalendarNotifications() throws {
        let now = date("2026-09-21T10:00:00-04:00")
        let event = CalendarEvent(
            title: "College interview",
            startAt: date("2026-09-21T12:00:00-04:00"),
            endAt: date("2026-09-21T13:00:00-04:00"),
            notes: "",
            tag: .college
        )
        let descriptors = CalendarNotificationPlanner.descriptors(for: [event], now: now)
        precondition(descriptors.count == 2)
        precondition(descriptors.map(\.fireDate) == [
            date("2026-09-21T11:30:00-04:00"),
            date("2026-09-21T11:58:00-04:00")
        ])
        precondition(Set(descriptors.map(\.identifier)).count == 2)
        precondition(descriptors[0].body.contains("30 minutes"))
        precondition(descriptors[1].body.contains("2 minutes"))
        precondition(CalendarNotificationPlanner.descriptors(
            for: [event],
            now: date("2026-09-21T11:45:00-04:00")
        ).count == 1)

        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = RecordingCalendarNotificationScheduler()
        let subject = store(defaults: defaults, now: { now }, calendarNotificationScheduler: recorder)
        recorder.reset()
        subject.addCalendarEvent(
            title: event.title,
            startAt: event.startAt,
            endAt: event.endAt,
            notes: event.notes,
            tag: event.tag
        )
        precondition(recorder.snapshots.count == 1 && recorder.snapshots[0].events.count == 1)
        let eventID = subject.calendarEvents[0].id

        subject.updateCalendarEvent(
            eventID,
            title: "Updated interview",
            startAt: event.startAt.addingTimeInterval(60 * 60),
            endAt: event.endAt.addingTimeInterval(60 * 60),
            notes: "Bring questions",
            tag: .college
        )
        precondition(recorder.snapshots.count == 2)
        precondition(recorder.snapshots[1].events[0].id == eventID)
        precondition(recorder.snapshots[1].events[0].title == "Updated interview")

        subject.deleteCalendarEvent(eventID)
        precondition(recorder.snapshots.count == 3 && recorder.snapshots[2].events.isEmpty)
        precondition(recorder.snapshots.allSatisfy(\.requestAuthorizationIfNeeded))
        print("PASS: calendar events schedule, update, and cancel 30-minute and 2-minute alerts")
    }
}

@MainActor
private final class RecordingCalendarNotificationScheduler: CalendarNotificationScheduling {
    struct Snapshot {
        let events: [CalendarEvent]
        let requestAuthorizationIfNeeded: Bool
    }

    private(set) var snapshots: [Snapshot] = []

    func reset() {
        snapshots.removeAll()
    }

    func synchronize(events: [CalendarEvent], requestAuthorizationIfNeeded: Bool) {
        snapshots.append(Snapshot(
            events: events,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        ))
    }
}
