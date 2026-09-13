import Foundation

@main
@MainActor
struct TodoChecks {
    private static let todoKey = "personal-dashboard.todos.v1"
    private static let dividerKey = "personal-dashboard.todo-divider-index.v1"

    static func main() throws {
        try checkOrderingAndDividerDeletion()
        try checkDailyFourAMBoundary()
        try checkPersistence()
        print("Todo regression checks passed.")
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "todo-checks.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private static func store(defaults: UserDefaults, now: @escaping () -> Date) -> DashboardStore {
        DashboardStore(
            defaults: defaults,
            nowProvider: now,
            automaticallySchedulesTodoCleanup: false
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
        precondition(subject.todoDividerIndex == 0)

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
        precondition(subject.todoDividerIndex == 2)
        subject.deleteTodo(subject.todos[0].id)
        precondition(subject.todoDividerIndex == 1)
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
        precondition(subject.todoDividerIndex == 1)

        subject.removeCompletedTodosAtDailyCutoff(now: date("2026-09-12T04:00:00-04:00"))
        precondition(subject.todos.map(\.title) == ["Unchecked"])

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
        precondition(restored.todos.map(\.title) == ["Keep active", "Keep completed"])
        precondition(restored.todos.map(\.isCompleted) == [false, true])
        precondition(restored.todoDividerIndex == 1)

        restored.addTodo(title: "New active")
        precondition(restored.todos.map(\.title) == ["Keep active", "New active", "Keep completed"])
        precondition(restored.todoDividerIndex == 2)
    }
}
