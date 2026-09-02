import SwiftUI

struct StickyNotesBoard: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var selectedNoteID: UUID?
    @State private var command: RichTextCommand?
    @State private var showingDeleteConfirmation = false

    private var selectedNote: StickyNote? {
        store.stickyNotes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        VStack(spacing: 0) {
            notesToolbar
            Divider().overlay(Palette.border)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    DotJournalBackground()
                    if store.stickyNotes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "note.text.badge.plus")
                                .font(.system(size: 34, weight: .light))
                            Text("Create your first sticky note")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Move it, resize it, change its shape, and format it like a document.")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    ForEach(store.stickyNotes) { note in
                        StickyNoteCard(
                            note: note,
                            canvasSize: proxy.size,
                            isSelected: selectedNoteID == note.id,
                            command: selectedNoteID == note.id ? command : nil,
                            onSelect: { selectedNoteID = note.id }
                        )
                    }
                }
                .clipped()
            }
        }
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .alert("Delete this sticky note?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let selectedNoteID { store.deleteStickyNote(selectedNoteID) }
                selectedNoteID = nil
            }
        } message: {
            Text("This removes the note and its formatted text from this dashboard.")
        }
    }

    private var notesToolbar: some View {
        HStack(spacing: 8) {
            Text("Sticky Notes")
                .font(.system(size: 22, weight: .bold))
                .padding(.trailing, 8)

            Button {
                let offset = Double((store.stickyNotes.count % 8) * 28)
                selectedNoteID = store.addStickyNote(x: 38 + offset, y: 38 + offset)
            } label: {
                Label("New note", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.ink)

            toolbarDivider

            formattingButton("bold", help: "Bold", action: .bold)
            formattingButton("underline", help: "Underline", action: .underline)
            formattingButton("strikethrough", help: "Strikethrough", action: .strikethrough)

            Menu {
                Button("Header") { send(.paragraph(.header)) }
                Button("Normal text") { send(.paragraph(.normal)) }
            } label: {
                Label("Text style", systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 96)
            .disabled(selectedNoteID == nil)

            Menu {
                ForEach([10, 12, 14, 16, 18, 24, 32], id: \.self) { size in
                    Button("\(size) pt") { send(.fontSize(CGFloat(size))) }
                }
            } label: {
                Label("Size", systemImage: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 74)
            .disabled(selectedNoteID == nil)

            toolbarDivider

            formattingButton("checklist", help: "Checkbox list", action: .list(.checkbox))
            formattingButton("list.number", help: "Numbered list", action: .list(.numbered))
            formattingButton("list.dash", help: "Hyphen list", action: .list(.dashed))

            toolbarDivider

            Menu {
                ForEach(StickyNoteColor.allCases) { color in
                    Button {
                        guard let selectedNoteID else { return }
                        store.setStickyNoteColor(selectedNoteID, color: color)
                    } label: {
                        Label(color.displayName, systemImage: selectedNote?.color == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(selectedNote?.color.fill ?? Palette.track).frame(width: 14, height: 14)
                    Text("Color")
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 72)
            .disabled(selectedNoteID == nil)

            Menu {
                ForEach(StickyNoteShape.allCases) { shape in
                    Button {
                        guard let selectedNoteID else { return }
                        store.setStickyNoteShape(selectedNoteID, shape: shape)
                    } label: {
                        Label(shape.displayName, systemImage: shape.symbol)
                    }
                }
            } label: {
                Label("Shape", systemImage: selectedNote?.shape.symbol ?? "square.on.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 82)
            .disabled(selectedNoteID == nil)

            Spacer()

            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.warning)
            .disabled(selectedNoteID == nil)
            .help("Delete selected note")
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
    }

    private var toolbarDivider: some View {
        Rectangle().fill(Palette.grid).frame(width: 1, height: 28).padding(.horizontal, 3)
    }

    private func formattingButton(_ symbol: String, help: String, action: RichTextAction) -> some View {
        Button { send(action) } label: {
            Image(systemName: symbol).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(selectedNoteID == nil)
        .help(help)
    }

    private func send(_ action: RichTextAction) {
        guard selectedNoteID != nil else { return }
        command = RichTextCommand(action: action)
    }
}

private struct StickyNoteCard: View {
    @EnvironmentObject private var store: DashboardStore
    let note: StickyNote
    let canvasSize: CGSize
    let isSelected: Bool
    let command: RichTextCommand?
    let onSelect: () -> Void

    @State private var dragOrigin: CGPoint?
    @State private var resizeOrigin: CGSize?

    var body: some View {
        ZStack {
            NoteShapePath(shape: note.shape)
                .fill(note.color.fill)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted.opacity(0.65))
                    Text("Drag")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.muted.opacity(0.75))
                    Spacer()
                }
                .padding(.horizontal, note.shape == .circle ? 36 : 12)
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .onTapGesture(perform: onSelect)

                RichTextEditor(
                    data: note.richTextData,
                    command: command,
                    onChange: { store.updateStickyNoteContent(note.id, data: $0) },
                    onFocus: onSelect
                )
                .padding(.horizontal, note.shape == .circle ? 24 : 2)
                .padding(.bottom, note.shape == .circle ? 24 : 4)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .gesture(resizeGesture)
                        .onTapGesture(perform: onSelect)
                }
            }
        }
        .frame(width: note.width, height: note.height)
        .clipShape(NoteShapePath(shape: note.shape))
        .overlay {
            NoteShapePath(shape: note.shape)
                .stroke(isSelected ? Palette.ink : Palette.border.opacity(0.6), lineWidth: isSelected ? 2 : 1)
        }
        .offset(x: note.positionX, y: note.positionY)
        .onTapGesture(perform: onSelect)
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                onSelect()
                let origin = dragOrigin ?? CGPoint(x: note.positionX, y: note.positionY)
                if dragOrigin == nil { dragOrigin = origin }
                let maxX = max(0, canvasSize.width - note.width)
                let maxY = max(0, canvasSize.height - note.height)
                let x = min(max(0, origin.x + value.translation.width), maxX)
                let y = min(max(0, origin.y + value.translation.height), maxY)
                store.updateStickyNoteFrame(note.id, x: x, y: y)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                onSelect()
                let origin = resizeOrigin ?? CGSize(width: note.width, height: note.height)
                if resizeOrigin == nil { resizeOrigin = origin }
                let maxWidth = max(180, canvasSize.width - note.positionX)
                let maxHeight = max(140, canvasSize.height - note.positionY)
                let width = min(max(180, origin.width + value.translation.width), maxWidth)
                let height = min(max(140, origin.height + value.translation.height), maxHeight)
                store.updateStickyNoteFrame(note.id, width: width, height: height)
            }
            .onEnded { _ in resizeOrigin = nil }
    }
}

private struct DotJournalBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            var x: CGFloat = spacing
            while x < size.width {
                var y: CGFloat = spacing
                while y < size.height {
                    let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    context.fill(dot, with: .color(Palette.muted.opacity(0.22)))
                    y += spacing
                }
                x += spacing
            }
        }
        .background(Palette.surface)
    }
}

private struct NoteShapePath: Shape {
    let shape: StickyNoteShape

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .rectangle:
            return Rectangle().path(in: rect)
        case .rounded:
            return RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
        case .circle:
            return Ellipse().path(in: rect)
        }
    }
}

extension StickyNoteColor {
    var fill: Color {
        switch self {
        case .yellow: Color(red: 0.98, green: 0.91, blue: 0.55)
        case .pink: Color(red: 0.97, green: 0.76, blue: 0.78)
        case .blue: Color(red: 0.70, green: 0.84, blue: 0.94)
        case .green: Color(red: 0.77, green: 0.87, blue: 0.66)
        case .purple: Color(red: 0.84, green: 0.75, blue: 0.91)
        case .paper: Color(red: 0.98, green: 0.97, blue: 0.92)
        }
    }
}

private extension StickyNoteShape {
    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .rounded: "square"
        case .circle: "circle"
        }
    }
}
