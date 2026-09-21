import SwiftUI

struct ClassificationSettingsView: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var tracker: ScreenTimeTracker
    @EnvironmentObject private var focusCat: FocusCatController
    @EnvironmentObject private var deepFocus: DeepFocusController

    @State private var selection: ClassificationSelection = .unclassified
    @State private var newSubgroupClassification: ProductivityClassification?
    @State private var subgroupToRename: ClassificationSubgroup?
    @State private var subgroupToDelete: ClassificationSubgroup?
    @State private var showingDeleteConfirmation = false
    @State private var ruleInput = ""
    @State private var ruleKind: ActivitySourceKind = .website

    private var unclassifiedSources: [TrackedActivitySource] {
        tracker.knownSources.filter { store.classificationRule(for: $0) == nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            classificationSidebar
                .frame(width: 274)
            Divider().overlay(Palette.border)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .sheet(item: $newSubgroupClassification) { classification in
            NewClassificationSubgroupSheet(classification: classification) { name in
                if let id = store.addClassificationSubgroup(name: name, classification: classification) {
                    selection = .subgroup(id)
                }
            }
        }
        .sheet(item: $subgroupToRename) { subgroup in
            RenameClassificationSubgroupSheet(subgroup: subgroup) { name in
                store.renameClassificationSubgroup(subgroup.id, name: name)
            }
        }
        .alert("Delete \(subgroupToDelete?.name ?? "subgroup")?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { subgroupToDelete = nil }
            Button("Delete", role: .destructive) {
                if let subgroupToDelete {
                    store.deleteClassificationSubgroup(subgroupToDelete.id)
                }
                selection = .unclassified
                subgroupToDelete = nil
            }
        } message: {
            Text("Its apps and websites will return to Unclassified. Tracking history will not be deleted.")
        }
    }

    private var classificationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Classification")
                .font(.system(size: 22, weight: .bold))
            Text("Decide how tracked apps and websites affect your focus score.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            focusCatControl
                .padding(.top, 16)

            deepFocusControl
                .padding(.top, 10)

            Button { selection = .unclassified } label: {
                HStack {
                    Label("Unclassified", systemImage: "tray")
                    Spacer()
                    Text("\(unclassifiedSources.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .frame(minHeight: 20)
                        .background(Palette.track)
                        .clipShape(Capsule())
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 42)
                .background(selection == .unclassified ? Palette.selected.opacity(0.75) : Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ProductivityClassification.allCases) { classification in
                        classificationGroup(classification)
                    }
                }
                .padding(.vertical, 18)
            }
        }
        .padding(22)
        .background(Palette.surface.opacity(0.5))
    }

    private var focusCatControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                WhiteFocusCat(pose: .sleeping, facingRight: true, phase: 0)
                    .frame(width: 120, height: 86)
                    .scaleEffect(0.25)
                    .frame(width: 31, height: 24)
                Text("Focus Cat")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { focusCat.isEnabled },
                    set: { focusCat.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Text(focusCat.isEnabled
                 ? "Watches the active Chrome tab for Shorts and Instagram."
                 : "The desktop pet and tab detection are off.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(focusCat.statusText.isEmpty ? "Runs locally" : focusCat.statusText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(focusCat.isEnabled ? Palette.focus : Palette.muted)
                Spacer()
                Button("Preview") {
                    focusCat.previewIntervention()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold))
                .disabled(!focusCat.isEnabled)
            }
        }
        .padding(11)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.border, lineWidth: 1))
    }

    private var deepFocusControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(deepFocus.isActive ? Palette.focus : Palette.muted)
                    .frame(width: 24)
                Text("Deep Focus")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if deepFocus.isActive {
                    Text(deepFocusRemainingTime)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.focus)
                }
            }

            Text(deepFocus.isActive
                 ? deepFocus.statusText
                 : "Hard-block everything outside your Flow category.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if deepFocus.isActive {
                Button("End Deep Focus") { deepFocus.endSession() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(spacing: 8) {
                    Picker("Duration", selection: $deepFocus.selectedDuration) {
                        ForEach(DeepFocusDuration.allCases) { duration in
                            Text(duration.displayName).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                    Button("Start") { deepFocus.beginSelectedSession() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(11)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.border, lineWidth: 1))
    }

    private var deepFocusRemainingTime: String {
        let total = max(0, Int(deepFocus.remainingSeconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func classificationGroup(_ classification: ProductivityClassification) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(classification.color).frame(width: 8, height: 8)
                Text(classification.displayName)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(store.classificationRules.filter { $0.classification == classification }.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
            }

            ForEach(store.subgroups(for: classification)) { subgroup in
                Button { selection = .subgroup(subgroup.id) } label: {
                    HStack {
                        Text(subgroup.name).lineLimit(1)
                        Spacer()
                        Text("\(store.rules(in: subgroup.id).count)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                    .font(.system(size: 13, weight: selection == .subgroup(subgroup.id) ? .semibold : .regular))
                    .padding(.leading, 16)
                    .padding(.trailing, 9)
                    .frame(height: 34)
                    .background(selection == .subgroup(subgroup.id) ? classification.color.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button { newSubgroupClassification = classification } label: {
                Label("New subgroup", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(classification.color)
                    .padding(.leading, 14)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection {
        case .unclassified:
            unclassifiedDetail
        case .subgroup(let id):
            if let subgroup = store.classificationSubgroups.first(where: { $0.id == id }) {
                subgroupDetail(subgroup)
            } else {
                unclassifiedDetail
            }
        }
    }

    private var unclassifiedDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                detailHeader(
                    kicker: "Needs review",
                    title: "Unclassified",
                    detail: "Assign detected apps and websites to a subgroup. Until then, their time counts as Neutral."
                )
                Spacer()
                if !unclassifiedSources.isEmpty {
                    Button {
                        tracker.clearUnclassifiedSources(unclassifiedSources)
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear the current unclassified list without deleting screen-time history")
                }
            }

            if unclassifiedSources.isEmpty {
                settingsEmptyState(
                    symbol: "checkmark.circle",
                    title: "Everything is classified",
                    detail: "New apps and websites will appear here automatically as they are tracked."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(unclassifiedSources) { source in
                            unclassifiedRow(source)
                            if source.id != unclassifiedSources.last?.id {
                                Divider().overlay(Palette.grid)
                            }
                        }
                    }
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
                }
                .padding(.top, 22)
            }
        }
        .padding(28)
    }

    private func unclassifiedRow(_ source: TrackedActivitySource) -> some View {
        HStack(spacing: 12) {
            sourceIcon(source.kind, name: source.displayName)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.displayName).font(.system(size: 13, weight: .semibold))
                Text(source.identifier).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer()
            classificationDestinationMenu(title: "Classify") { subgroup in
                store.classifyTrackedSource(source, subgroupID: subgroup.id)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
    }

    private func subgroupDetail(_ subgroup: ClassificationSubgroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                detailHeader(
                    kicker: "\(subgroup.classification.displayName) subgroup",
                    title: subgroup.name,
                    detail: "Time in these apps and websites counts toward \(subgroup.classification.displayName)."
                )
                Spacer()
                HStack(spacing: 8) {
                    Button("Rename") { subgroupToRename = subgroup }
                        .buttonStyle(.bordered)
                    Button {
                        subgroupToDelete = subgroup
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Palette.warning)
                    .help("Delete subgroup")
                }
            }

            HStack(spacing: 9) {
                TextField(ruleKind == .website ? "Website domain, such as docs.google.com" : "App name or bundle identifier", text: $ruleInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addRule(to: subgroup.id) }
                Picker("Type", selection: $ruleKind) {
                    ForEach(ActivitySourceKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 122)
                Button("Add") { addRule(to: subgroup.id) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .disabled(ruleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 24)

            let rules = store.rules(in: subgroup.id)
            if rules.isEmpty {
                settingsEmptyState(
                    symbol: "square.stack.3d.up",
                    title: "This subgroup is empty",
                    detail: "Add an app or website above, or classify one from the Unclassified inbox."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rules) { rule in
                            classificationRuleRow(rule)
                            if rule.id != rules.last?.id {
                                Divider().overlay(Palette.grid)
                            }
                        }
                    }
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
                }
                .padding(.top, 16)
            }

            HStack {
                Text("\(rules.count) classification rule\(rules.count == 1 ? "" : "s")")
                Spacer()
                Text("Each app or domain can belong to one subgroup.")
            }
            .font(.system(size: 10))
            .foregroundStyle(Palette.muted)
            .padding(.top, 12)
        }
        .padding(28)
    }

    private func classificationRuleRow(_ rule: ActivityClassificationRule) -> some View {
        HStack(spacing: 12) {
            sourceIcon(rule.kind, name: rule.displayName)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayName).font(.system(size: 13, weight: .semibold))
                Text("\(rule.identifier) · \(rule.kind.displayName)")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Menu {
                ForEach(ProductivityClassification.allCases) { classification in
                    Menu(classification.displayName) {
                        ForEach(store.subgroups(for: classification)) { subgroup in
                            Button(subgroup.name) { store.moveClassificationRule(rule.id, to: subgroup.id) }
                        }
                    }
                }
                Divider()
                Button("Remove classification", role: .destructive) {
                    store.deleteClassificationRule(rule.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("Move or remove classification")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
    }

    private func detailHeader(kicker: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Palette.focus)
            Text(title).font(.system(size: 25, weight: .bold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private func settingsEmptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light))
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourceIcon(_ kind: ActivitySourceKind, name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.selected.opacity(0.55))
            if kind == .website {
                Image(systemName: "globe")
            } else {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold))
            }
        }
        .foregroundStyle(Palette.focus)
        .frame(width: 34, height: 34)
    }

    private func classificationDestinationMenu(
        title: String,
        action: @escaping (ClassificationSubgroup) -> Void
    ) -> some View {
        Menu {
            ForEach(ProductivityClassification.allCases) { classification in
                Menu(classification.displayName) {
                    let subgroups = store.subgroups(for: classification)
                    if subgroups.isEmpty {
                        Text("No subgroups")
                    } else {
                        ForEach(subgroups) { subgroup in
                            Button(subgroup.name) { action(subgroup) }
                        }
                    }
                }
            }
        } label: {
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 78)
    }

    private func addRule(to subgroupID: UUID) {
        guard store.addClassificationRule(input: ruleInput, kind: ruleKind, subgroupID: subgroupID) != nil else { return }
        ruleInput = ""
    }
}

private enum ClassificationSelection: Equatable {
    case unclassified
    case subgroup(UUID)
}

private struct NewClassificationSubgroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let classification: ProductivityClassification
    let onSave: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(classification.displayName) subgroup")
                .font(.system(size: 20, weight: .bold))
            Text(classification.detail)
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
            TextField("Subgroup name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
        .onAppear { focused = true }
    }

    private func save() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        onSave(cleaned)
        dismiss()
    }
}

private struct RenameClassificationSubgroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let subgroup: ClassificationSubgroup
    let onSave: (String) -> Void
    @State private var name: String
    @FocusState private var focused: Bool

    init(subgroup: ClassificationSubgroup, onSave: @escaping (String) -> Void) {
        self.subgroup = subgroup
        self.onSave = onSave
        _name = State(initialValue: subgroup.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename subgroup").font(.system(size: 20, weight: .bold))
            TextField("Subgroup name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { focused = true }
    }

    private func save() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        onSave(cleaned)
        dismiss()
    }
}

private extension ProductivityClassification {
    var color: Color {
        switch self {
        case .flow: Palette.focus
        case .neutral: Palette.neutral
        case .brainrot: Palette.warning
        }
    }
}
