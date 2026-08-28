import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }
}

struct GoalItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var progress: Int
    var createdAt = Date()
}
