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

enum ProductivityClassification: String, Codable, CaseIterable, Identifiable, Hashable {
    case flow
    case neutral
    case brainrot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flow: "Flow"
        case .neutral: "Neutral"
        case .brainrot: "Brainrot"
        }
    }

    var detail: String {
        switch self {
        case .flow: "Flow-state productivity"
        case .neutral: "Miscellaneous or necessary activity"
        case .brainrot: "Distracting or unproductive activity"
        }
    }
}

enum ActivitySourceKind: String, Codable, CaseIterable, Identifiable {
    case application
    case website

    var id: String { rawValue }
    var displayName: String { self == .application ? "Application" : "Website" }
}

struct ClassificationSubgroup: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var classification: ProductivityClassification
    var createdAt = Date()
}

struct ActivityClassificationRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var displayName: String
    var identifier: String
    var kind: ActivitySourceKind
    var classification: ProductivityClassification
    var subgroupID: UUID
    var createdAt = Date()
}

struct TrackedActivitySource: Identifiable, Hashable {
    let displayName: String
    let identifier: String
    let kind: ActivitySourceKind

    var id: String { "\(kind.rawValue):\(identifier.lowercased())" }
}
