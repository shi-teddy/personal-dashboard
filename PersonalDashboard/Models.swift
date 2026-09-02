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

enum CalendarEventColor: String, Codable, CaseIterable, Identifiable {
    case green
    case purple
    case tan

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct CalendarEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var startAt: Date
    var endAt: Date
    var notes: String
    var color: CalendarEventColor
    var createdAt = Date()
}

enum StickyNoteColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case pink
    case blue
    case green
    case purple
    case paper

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum StickyNoteShape: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case rounded
    case circle

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .rectangle: "Rectangle"
        case .rounded: "Rounded"
        case .circle: "Circle"
        }
    }
}

struct StickyNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var color: StickyNoteColor
    var shape: StickyNoteShape
    var richTextData: Data
    var createdAt = Date()
    var updatedAt = Date()
}
