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
    @Published private(set) var calendarEvents: [CalendarEvent] = [] {
        didSet { save(calendarEvents, key: calendarKey) }
    }
    @Published private(set) var stickyNotes: [StickyNote] = [] {
        didSet { save(stickyNotes, key: stickyNotesKey) }
    }
    @Published private(set) var classificationSubgroups: [ClassificationSubgroup] = [] {
        didSet { save(classificationSubgroups, key: classificationSubgroupsKey) }
    }
    @Published private(set) var classificationRules: [ActivityClassificationRule] = [] {
        didSet { save(classificationRules, key: classificationRulesKey) }
    }

    private let todoKey = "personal-dashboard.todos.v1"
    private let goalKey = "personal-dashboard.goals.v1"
    private let calendarKey = "personal-dashboard.calendar-events.v1"
    private let stickyNotesKey = "personal-dashboard.sticky-notes.v1"
    private let classificationSubgroupsKey = "personal-dashboard.classification-subgroups.v1"
    private let classificationRulesKey = "personal-dashboard.classification-rules.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        todos = load([TodoItem].self, key: todoKey) ?? Self.sampleTodos
        goals = load([GoalItem].self, key: goalKey) ?? Self.sampleGoals
        calendarEvents = load([CalendarEvent].self, key: calendarKey) ?? []
        stickyNotes = load([StickyNote].self, key: stickyNotesKey) ?? []
        classificationSubgroups = load([ClassificationSubgroup].self, key: classificationSubgroupsKey)
            ?? Self.defaultClassificationSubgroups
        classificationRules = load([ActivityClassificationRule].self, key: classificationRulesKey) ?? []
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

    func moveTodo(_ id: UUID, before targetID: UUID) {
        guard id != targetID,
              let sourceIndex = todos.firstIndex(where: { $0.id == id }) else { return }
        let item = todos.remove(at: sourceIndex)
        guard let targetIndex = todos.firstIndex(where: { $0.id == targetID }) else {
            todos.append(item)
            return
        }
        todos.insert(item, at: targetIndex)
    }

    func moveTodo(_ id: UUID, toIndex destinationIndex: Int) {
        guard let sourceIndex = todos.firstIndex(where: { $0.id == id }) else { return }
        let item = todos.remove(at: sourceIndex)
        todos.insert(item, at: destinationIndex.clamped(to: 0...todos.count))
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

    func addCalendarEvent(
        title: String,
        startAt: Date,
        endAt: Date,
        notes: String,
        color: CalendarEventColor
    ) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let safeEnd = max(endAt, startAt.addingTimeInterval(15 * 60))
        calendarEvents.append(CalendarEvent(
            title: cleaned,
            startAt: startAt,
            endAt: safeEnd,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color
        ))
        calendarEvents.sort { $0.startAt < $1.startAt }
    }

    func deleteCalendarEvent(_ id: UUID) {
        calendarEvents.removeAll { $0.id == id }
    }

    @discardableResult
    func addStickyNote(x: Double, y: Double) -> UUID {
        let color = StickyNoteColor.allCases[stickyNotes.count % StickyNoteColor.allCases.count]
        let note = StickyNote(
            positionX: x,
            positionY: y,
            width: 280,
            height: 220,
            color: color,
            shape: .rounded,
            richTextData: Data()
        )
        stickyNotes.append(note)
        return note.id
    }

    func deleteStickyNote(_ id: UUID) {
        stickyNotes.removeAll { $0.id == id }
    }

    func updateStickyNoteFrame(
        _ id: UUID,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) {
        guard let index = stickyNotes.firstIndex(where: { $0.id == id }) else { return }
        if let x { stickyNotes[index].positionX = x }
        if let y { stickyNotes[index].positionY = y }
        if let width { stickyNotes[index].width = width }
        if let height { stickyNotes[index].height = height }
        stickyNotes[index].updatedAt = Date()
    }

    func updateStickyNoteContent(_ id: UUID, data: Data) {
        guard let index = stickyNotes.firstIndex(where: { $0.id == id }),
              stickyNotes[index].richTextData != data else { return }
        stickyNotes[index].richTextData = data
        stickyNotes[index].updatedAt = Date()
    }

    func setStickyNoteColor(_ id: UUID, color: StickyNoteColor) {
        guard let index = stickyNotes.firstIndex(where: { $0.id == id }) else { return }
        stickyNotes[index].color = color
        stickyNotes[index].updatedAt = Date()
    }

    func setStickyNoteShape(_ id: UUID, shape: StickyNoteShape) {
        guard let index = stickyNotes.firstIndex(where: { $0.id == id }) else { return }
        stickyNotes[index].shape = shape
        stickyNotes[index].updatedAt = Date()
    }

    @discardableResult
    func addClassificationSubgroup(name: String, classification: ProductivityClassification) -> UUID? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let subgroup = ClassificationSubgroup(name: cleaned, classification: classification)
        classificationSubgroups.append(subgroup)
        return subgroup.id
    }

    func renameClassificationSubgroup(_ id: UUID, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let index = classificationSubgroups.firstIndex(where: { $0.id == id }) else { return }
        classificationSubgroups[index].name = cleaned
    }

    func deleteClassificationSubgroup(_ id: UUID) {
        classificationSubgroups.removeAll { $0.id == id }
        classificationRules.removeAll { $0.subgroupID == id }
    }

    @discardableResult
    func addClassificationRule(
        input: String,
        kind: ActivitySourceKind,
        subgroupID: UUID
    ) -> UUID? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let subgroup = classificationSubgroups.first(where: { $0.id == subgroupID }),
              let identifier = normalizedIdentifier(cleaned, kind: kind) else { return nil }
        let displayName = kind == .website ? identifier : cleaned
        return upsertClassificationRule(
            displayName: displayName,
            identifier: identifier,
            kind: kind,
            subgroup: subgroup
        )
    }

    @discardableResult
    func classifyTrackedSource(_ source: TrackedActivitySource, subgroupID: UUID) -> UUID? {
        guard let subgroup = classificationSubgroups.first(where: { $0.id == subgroupID }) else { return nil }
        return upsertClassificationRule(
            displayName: source.displayName,
            identifier: source.identifier,
            kind: source.kind,
            subgroup: subgroup
        )
    }

    func moveClassificationRule(_ id: UUID, to subgroupID: UUID) {
        guard let ruleIndex = classificationRules.firstIndex(where: { $0.id == id }),
              let subgroup = classificationSubgroups.first(where: { $0.id == subgroupID }) else { return }
        classificationRules[ruleIndex].subgroupID = subgroup.id
        classificationRules[ruleIndex].classification = subgroup.classification
    }

    func deleteClassificationRule(_ id: UUID) {
        classificationRules.removeAll { $0.id == id }
    }

    func classificationRule(for source: TrackedActivitySource) -> ActivityClassificationRule? {
        classificationRules.first { rule in
            guard rule.kind == source.kind else { return false }
            if rule.kind == .website {
                let domain = source.identifier.lowercased()
                let configured = rule.identifier.lowercased()
                return domain == configured || domain.hasSuffix(".\(configured)")
            }
            return rule.identifier.caseInsensitiveCompare(source.identifier) == .orderedSame
                || rule.identifier.caseInsensitiveCompare(source.displayName) == .orderedSame
                || rule.displayName.caseInsensitiveCompare(source.displayName) == .orderedSame
        }
    }

    func subgroups(for classification: ProductivityClassification) -> [ClassificationSubgroup] {
        classificationSubgroups
            .filter { $0.classification == classification }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func rules(in subgroupID: UUID) -> [ActivityClassificationRule] {
        classificationRules
            .filter { $0.subgroupID == subgroupID }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func upsertClassificationRule(
        displayName: String,
        identifier: String,
        kind: ActivitySourceKind,
        subgroup: ClassificationSubgroup
    ) -> UUID {
        if let index = classificationRules.firstIndex(where: {
            $0.kind == kind && $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame
        }) {
            classificationRules[index].displayName = displayName
            classificationRules[index].subgroupID = subgroup.id
            classificationRules[index].classification = subgroup.classification
            return classificationRules[index].id
        }
        let rule = ActivityClassificationRule(
            displayName: displayName,
            identifier: identifier,
            kind: kind,
            classification: subgroup.classification,
            subgroupID: subgroup.id
        )
        classificationRules.append(rule)
        return rule.id
    }

    private func normalizedIdentifier(_ input: String, kind: ActivitySourceKind) -> String? {
        if kind == .application { return input.lowercased() }
        let candidate = input.contains("://") ? input : "https://\(input)"
        guard let components = URLComponents(string: candidate),
              var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
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
    private static let defaultClassificationSubgroups = [
        ClassificationSubgroup(name: "School", classification: .flow),
        ClassificationSubgroup(name: "College apps", classification: .flow),
        ClassificationSubgroup(name: "Communication", classification: .neutral),
        ClassificationSubgroup(name: "Utilities", classification: .neutral),
        ClassificationSubgroup(name: "Social media", classification: .brainrot),
        ClassificationSubgroup(name: "Video", classification: .brainrot)
    ]
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
