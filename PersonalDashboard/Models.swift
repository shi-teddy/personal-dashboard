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

struct CompletedGoalRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var goalID: UUID
    var title: String
    var createdAt: Date
    var completedAt: Date
}

struct TodoCompletionRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var todoID: UUID
    var title: String
    var completedAt: Date
}

enum CalendarEventTag: String, Codable, CaseIterable, Identifiable {
    case school
    case college
    case extracurriculars
    case fun
    case misc

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct CalendarEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var startAt: Date
    var endAt: Date
    var notes: String
    var tag: CalendarEventTag
    var createdAt = Date()

    private enum CodingKeys: String, CodingKey {
        case id, title, startAt, endAt, notes, tag, color, createdAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        startAt: Date,
        endAt: Date,
        notes: String,
        tag: CalendarEventTag,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.notes = notes
        self.tag = tag
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        startAt = try container.decode(Date.self, forKey: .startAt)
        endAt = try container.decode(Date.self, forKey: .endAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        if let savedTag = try container.decodeIfPresent(CalendarEventTag.self, forKey: .tag) {
            tag = savedTag
        } else {
            let legacyColor = try container.decodeIfPresent(String.self, forKey: .color)
            tag = switch legacyColor {
            case "green": .school
            case "purple": .college
            default: .misc
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encode(notes, forKey: .notes)
        try container.encode(tag, forKey: .tag)
        try container.encode(createdAt, forKey: .createdAt)
    }
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

enum DeepFocusDuration: Int, CaseIterable, Identifiable {
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    var displayName: String {
        switch self {
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        }
    }
}

enum DeepFocusPolicy {
    static func isFlowApplication(bundleIdentifier: String?, displayName: String,
                                  rules: [ActivityClassificationRule]) -> Bool {
        rules.contains { rule in
            guard rule.kind == .application, rule.classification == .flow else { return false }
            if let bundleIdentifier,
               rule.identifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame { return true }
            return rule.identifier.caseInsensitiveCompare(displayName) == .orderedSame
                || rule.displayName.caseInsensitiveCompare(displayName) == .orderedSame
        }
    }

    static func isFlowWebsite(urlString: String, rules: [ActivityClassificationRule]) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return rules.contains { rule in
            guard rule.kind == .website, rule.classification == .flow else { return false }
            let configured = rule.identifier.lowercased()
            return host == configured || host.hasSuffix(".\(configured)")
        }
    }

    static func fiveMinuteWarningDate(endDate: Date, now: Date) -> Date? {
        let warning = endDate.addingTimeInterval(-5 * 60)
        return warning > now ? warning : nil
    }
}
