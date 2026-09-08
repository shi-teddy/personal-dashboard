import AppKit
import SwiftUI

struct RichTextCommand: Equatable {
    let id = UUID()
    let action: RichTextAction
}

enum RichTextAction: Equatable {
    case bold
    case underline
    case strikethrough
    case fontSize(CGFloat)
    case paragraph(RichTextParagraphKind)
    case list(RichTextListKind)
}

enum RichTextParagraphKind: Equatable {
    case header
    case normal
}

enum RichTextListKind: Equatable {
    case checkbox
    case numbered
    case dashed
}

struct RichTextEditor: NSViewRepresentable {
    let data: Data
    let command: RichTextCommand?
    let onChange: (Data) -> Void
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onFocus: onFocus)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = JournalTextView()
        textView.onFocus = context.coordinator.onFocus
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = Self.normalAttributes
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.load(data: data)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onFocus = onFocus
        context.coordinator.textView?.onFocus = onFocus
        if context.coordinator.lastLoadedData != data,
           scrollView.window?.firstResponder !== context.coordinator.textView {
            context.coordinator.load(data: data)
        }
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.action)
        }
    }

    static let normalAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor.labelColor
    ]

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: JournalTextView?
        var onChange: (Data) -> Void
        var onFocus: () -> Void
        var lastLoadedData = Data()
        var lastCommandID: UUID?

        init(onChange: @escaping (Data) -> Void, onFocus: @escaping () -> Void) {
            self.onChange = onChange
            self.onFocus = onFocus
        }

        func load(data: Data) {
            guard let textView else { return }
            let attributed: NSAttributedString
            if data.isEmpty {
                attributed = NSAttributedString(string: "", attributes: RichTextEditor.normalAttributes)
            } else {
                attributed = (try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )) ?? NSAttributedString(string: "", attributes: RichTextEditor.normalAttributes)
            }
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = RichTextEditor.normalAttributes
            lastLoadedData = data
        }

        func textDidBeginEditing(_ notification: Notification) {
            onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, let textStorage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: textStorage.length)
            guard let data = try? textStorage.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) else { return }
            lastLoadedData = data
            onChange(data)
        }

        func apply(_ action: RichTextAction) {
            guard let textView else { return }
            onFocus()
            switch action {
            case .bold:
                toggleBold(in: textView)
            case .underline:
                toggleAttribute(.underlineStyle, in: textView)
            case .strikethrough:
                toggleAttribute(.strikethroughStyle, in: textView)
            case .fontSize(let size):
                applyFontSize(size, in: textView)
            case .paragraph(let kind):
                applyParagraph(kind, in: textView)
            case .list(let kind):
                textView.insertList(kind)
            }
            textView.didChangeText()
        }

        private func toggleBold(in textView: NSTextView) {
            let range = textView.selectedRange()
            let manager = NSFontManager.shared
            if range.length == 0 {
                let font = textView.typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
                let isBold = manager.traits(of: font).contains(.boldFontMask)
                textView.typingAttributes[.font] = isBold
                    ? manager.convert(font, toNotHaveTrait: .boldFontMask)
                    : manager.convert(font, toHaveTrait: .boldFontMask)
                return
            }
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: 14)
                let isBold = manager.traits(of: font).contains(.boldFontMask)
                let updated = isBold
                    ? manager.convert(font, toNotHaveTrait: .boldFontMask)
                    : manager.convert(font, toHaveTrait: .boldFontMask)
                textView.textStorage?.addAttribute(.font, value: updated, range: subrange)
            }
        }

        private func toggleAttribute(_ key: NSAttributedString.Key, in textView: NSTextView) {
            let range = textView.selectedRange()
            if range.length == 0 {
                let enabled = (textView.typingAttributes[key] as? NSNumber)?.intValue == 1
                textView.typingAttributes[key] = enabled ? 0 : 1
                return
            }
            let enabled = (textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue == 1
            textView.textStorage?.addAttribute(key, value: enabled ? 0 : 1, range: range)
        }

        private func applyFontSize(_ size: CGFloat, in textView: NSTextView) {
            let range = textView.selectedRange()
            let manager = NSFontManager.shared
            if range.length == 0 {
                let font = textView.typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
                textView.typingAttributes[.font] = manager.convert(font, toSize: size)
                return
            }
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: 14)
                textView.textStorage?.addAttribute(.font, value: manager.convert(font, toSize: size), range: subrange)
            }
        }

        private func applyParagraph(_ kind: RichTextParagraphKind, in textView: NSTextView) {
            let selected = textView.selectedRange()
            let paragraphRange = (textView.string as NSString).paragraphRange(for: selected)
            let font: NSFont = kind == .header
                ? .systemFont(ofSize: 22, weight: .bold)
                : .systemFont(ofSize: 14, weight: .regular)
            if paragraphRange.length > 0 {
                textView.textStorage?.addAttribute(.font, value: font, range: paragraphRange)
            }
            textView.typingAttributes[.font] = font
        }
    }
}

final class JournalTextView: NSTextView {
    var onFocus: (() -> Void)?
    private let listIndent: CGFloat = 20

    override func keyDown(with event: NSEvent) {
        if event.characters == " ", handleListTrigger() { return }
        if event.keyCode == 36, handleListReturn() { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let nsString = string as NSString
        if nsString.length > 0, index <= nsString.length {
            let safeIndex = min(index, max(0, nsString.length - 1))
            let paragraph = nsString.paragraphRange(for: NSRange(location: safeIndex, length: 0))
            if paragraph.location < nsString.length,
               index <= paragraph.location + 1 {
                let marker = nsString.substring(with: NSRange(location: paragraph.location, length: 1))
                if marker == "☐" || marker == "☑" {
                    replace(range: NSRange(location: paragraph.location, length: 1), with: marker == "☐" ? "☑" : "☐")
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    func insertList(_ kind: RichTextListKind) {
        let originalSelection = selectedRange()
        let prefix: String
        switch kind {
        case .checkbox: prefix = "☐ "
        case .numbered: prefix = "1. "
        case .dashed: prefix = "- "
        }
        let paragraph = currentParagraphRange()
        let current = (string as NSString).substring(with: paragraph).trimmingCharacters(in: .newlines)
        guard !current.hasPrefix(prefix) else { return }
        replace(range: NSRange(location: paragraph.location, length: 0), with: prefix)
        setSelectedRange(NSRange(
            location: originalSelection.location + prefix.utf16.count,
            length: originalSelection.length
        ))
        applyListStyle(to: currentParagraphRange())
    }

    private func handleListTrigger() -> Bool {
        let caret = selectedRange().location
        let paragraph = currentParagraphRange()
        guard caret >= paragraph.location else { return false }
        let beforeRange = NSRange(location: paragraph.location, length: caret - paragraph.location)
        let before = (string as NSString).substring(with: beforeRange)
        let replacement: String
        switch before {
        case "-": replacement = "- "
        case "1.": replacement = "1. "
        case "[]", "[ ]": replacement = "☐ "
        default: return false
        }
        replace(range: beforeRange, with: replacement)
        setSelectedRange(NSRange(location: paragraph.location + replacement.utf16.count, length: 0))
        applyListStyle(to: currentParagraphRange())
        return true
    }

    private func handleListReturn() -> Bool {
        let paragraph = currentParagraphRange()
        let raw = (string as NSString).substring(with: paragraph).trimmingCharacters(in: .newlines)
        guard let prefix = listPrefix(in: raw) else { return false }
        let content = String(raw.dropFirst(prefix.utf16.count)).trimmingCharacters(in: .whitespaces)
        if content.isEmpty {
            replace(range: NSRange(location: paragraph.location, length: prefix.utf16.count), with: "")
            let style = NSMutableParagraphStyle()
            style.headIndent = 0
            style.firstLineHeadIndent = 0
            textStorage?.addAttribute(.paragraphStyle, value: style, range: currentParagraphRange())
            return false
        }

        let nextPrefix: String
        if prefix == "☐ " || prefix == "☑ " {
            nextPrefix = "☐ "
        } else if prefix == "- " {
            nextPrefix = "- "
        } else {
            let numberText = prefix.dropLast(2)
            nextPrefix = "\((Int(numberText) ?? 0) + 1). "
        }
        let insertion = "\n\(nextPrefix)"
        let caret = selectedRange().location
        replace(range: NSRange(location: caret, length: 0), with: insertion)
        setSelectedRange(NSRange(location: caret + insertion.utf16.count, length: 0))
        applyListStyle(to: currentParagraphRange())
        return true
    }

    private func listPrefix(in paragraph: String) -> String? {
        if paragraph.hasPrefix("☐ ") { return "☐ " }
        if paragraph.hasPrefix("☑ ") { return "☑ " }
        if paragraph.hasPrefix("- ") { return "- " }
        guard let dot = paragraph.firstIndex(of: ".") else { return nil }
        let number = String(paragraph[..<dot])
        let afterDot = paragraph.index(after: dot)
        guard Int(number) != nil, afterDot < paragraph.endIndex, paragraph[afterDot] == " " else { return nil }
        return "\(number). "
    }

    private func currentParagraphRange() -> NSRange {
        let nsString = string as NSString
        let caret = min(selectedRange().location, nsString.length)
        return nsString.paragraphRange(for: NSRange(location: caret, length: 0))
    }

    private func applyListStyle(to range: NSRange) {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        style.headIndent = listIndent
        style.tabStops = [NSTextTab(textAlignment: .left, location: listIndent)]
        textStorage?.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func replace(range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
    }
}
