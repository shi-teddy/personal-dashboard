import AppKit
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
                        HStack {
                            Circle()
                                .fill(color.fill)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Palette.muted.opacity(0.35), lineWidth: 0.5))
                            Text(color.displayName)
                            if selectedNote?.color == color {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
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

    @GestureState private var dragTranslation = CGSize.zero
    @GestureState private var resizeTranslation = CGSize.zero
    @State private var isInteracting = false
    @State private var previewText = ""

    private var renderedPosition: CGPoint {
        constrainedPosition(for: dragTranslation)
    }

    private var renderedSize: CGSize {
        constrainedSize(for: resizeTranslation)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            noteSurface(isPreview: false)
                .frame(width: note.width, height: note.height)
                .clipShape(NoteShapePath(shape: note.shape))
                .overlay {
                    NoteShapePath(shape: note.shape)
                        .stroke(isSelected ? Palette.ink : Palette.border.opacity(0.6), lineWidth: 0.75)
                }
                .position(
                    x: note.positionX + note.width / 2,
                    y: note.positionY + note.height / 2
                )
                .opacity(isInteracting ? 0.001 : 1)
                .onTapGesture(perform: onSelect)

            if isInteracting {
                noteSurface(isPreview: true)
                    .frame(width: renderedSize.width, height: renderedSize.height)
                    .clipShape(NoteShapePath(shape: note.shape))
                    .overlay {
                        NoteShapePath(shape: note.shape)
                            .stroke(Palette.ink, lineWidth: 0.75)
                    }
                    .drawingGroup(opaque: false, colorMode: .nonLinear)
                    .offset(x: renderedPosition.x, y: renderedPosition.y)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private func noteSurface(isPreview: Bool) -> some View {
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

                if isPreview {
                    Text(previewText)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, note.shape == .circle ? 36 : 16)
                        .padding(.top, 12)
                        .padding(.bottom, note.shape == .circle ? 24 : 8)
                        .allowsHitTesting(false)
                } else {
                    RichTextEditor(
                        data: note.richTextData,
                        command: command,
                        onChange: { store.updateStickyNoteContent(note.id, data: $0) },
                        onFocus: onSelect
                    )
                    .padding(.horizontal, note.shape == .circle ? 24 : 2)
                    .padding(.bottom, note.shape == .circle ? 24 : 4)
                }
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
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onChanged { _ in
                if !isInteracting {
                    previewText = note.dragPreviewText
                    isInteracting = true
                    onSelect()
                }
            }
            .onEnded { value in
                let position = constrainedPosition(for: value.translation)
                store.updateStickyNoteFrame(note.id, x: position.x, y: position.y)
                isInteracting = false
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .updating($resizeTranslation) { value, state, _ in
                state = value.translation
            }
            .onChanged { _ in
                if !isInteracting {
                    previewText = note.dragPreviewText
                    isInteracting = true
                    onSelect()
                }
            }
            .onEnded { value in
                let size = constrainedSize(for: value.translation)
                store.updateStickyNoteFrame(note.id, width: size.width, height: size.height)
                isInteracting = false
            }
    }

    private func constrainedPosition(for translation: CGSize) -> CGPoint {
        let size = renderedSize
        let maxX = max(0, canvasSize.width - size.width)
        let maxY = max(0, canvasSize.height - size.height)
        return CGPoint(
            x: min(max(0, note.positionX + translation.width), maxX),
            y: min(max(0, note.positionY + translation.height), maxY)
        )
    }

    private func constrainedSize(for translation: CGSize) -> CGSize {
        let maxWidth = max(180, canvasSize.width - note.positionX)
        let maxHeight = max(140, canvasSize.height - note.positionY)
        return CGSize(
            width: min(max(180, note.width + translation.width), maxWidth),
            height: min(max(140, note.height + translation.height), maxHeight)
        )
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
            return RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect)
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

private extension StickyNote {
    var dragPreviewText: String {
        guard !richTextData.isEmpty,
              let attributed = try? NSAttributedString(
                data: richTextData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else { return "" }
        return attributed.string
    }
}
