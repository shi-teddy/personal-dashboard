import Foundation
import Combine

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = [] {
        didSet { save(todos, key: todoKey) }
    }
    @Published private(set) var goals: [GoalItem] = [] {
        didSet { save(goals, key: goalKey) }
    }

    private let todoKey = "personal-dashboard.todos.v1"
    private let goalKey = "personal-dashboard.goals.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        todos = load([TodoItem].self, key: todoKey) ?? Self.sampleTodos
        goals = load([GoalItem].self, key: goalKey) ?? Self.sampleGoals
        removeExpiredTodos()
    }

    func addTodo(title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        todos.append(TodoItem(title: cleaned))
    }

    func toggleTodo(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].completedAt = todos[index].completedAt == nil ? Date() : nil
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
    }

    func removeExpiredTodos(now: Date = Date()) {
        let expiration = now.addingTimeInterval(-24 * 60 * 60)
        todos.removeAll { item in
            guard let completedAt = item.completedAt else { return false }
            return completedAt <= expiration
        }
    }

    func addGoal(title: String, progress: Int) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        goals.append(GoalItem(title: cleaned, progress: progress.clamped(to: 0...100)))
    }

    func deleteGoal(_ id: UUID) {
        goals.removeAll { $0.id == id }
    }

    func setGoalProgress(_ id: UUID, progress: Int) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].progress = progress.clamped(to: 0...100)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static let sampleTodos = [
        TodoItem(title: "Walk dog"),
        TodoItem(title: "Homework"),
        TodoItem(title: "Call home", completedAt: Date()),
        TodoItem(title: "Take out trash", completedAt: Date()),
        TodoItem(title: "Laundry", completedAt: Date())
    ]
    private static let sampleGoals = [GoalItem(title: "Hit GM", progress: 70)]
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
