import AppKit
import SkilliCore
import SwiftUI

/// Lets SwiftUI buttons insert into the editor at the cursor.
@MainActor
final class PromptEditorController {
    /// A grouped Form is a table view: SwiftUI can make a second copy of the
    /// editor to measure the row. The one in a window is the real one.
    private let views = NSHashTable<PromptTextView>.weakObjects()

    fileprivate func attach(_ textView: PromptTextView) {
        views.add(textView)
    }

    fileprivate var textView: PromptTextView? {
        views.allObjects.first { $0.window != nil } ?? views.allObjects.last
    }

    func insert(_ text: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    /// Self-test hooks.
    var text: String { textView?.string ?? "" }
    var instances: (total: Int, inWindow: Int) {
        (views.allObjects.count, views.allObjects.filter { $0.window != nil }.count)
    }
    var completionItems: [PromptTemplate.Variable] { textView?.completion.isVisible == true ? textView?.completion.items ?? [] : [] }
    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }
}

/// A command's prompt: plain text, `{variables}` drawn in the accent color,
/// and a list of matching variables as soon as `{` is typed.
struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: PromptEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // `init(frame:)` builds the whole text system; a nil text container
        // would show nothing.
        let textView = PromptTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = PromptTextView.font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.highlightVariables()
        controller.attach(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptTextView, textView.string != text else { return }
        textView.string = text
        textView.highlightVariables()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PromptTextView else { return }
            text.wrappedValue = textView.string
            textView.highlightVariables()
            textView.updateCompletion()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? PromptTextView)?.updateCompletion()
        }
    }
}

final class PromptTextView: NSTextView {
    static let font = NSFont.systemFont(ofSize: 13)
    /// Lazy: overriding an initializer would hide AppKit's `init(frame:)`.
    lazy var completion: VariableCompletionList = {
        let list = VariableCompletionList()
        list.onPick = { [weak self] variable in self?.accept(variable) }
        return list
    }()

    /// Letters typed after an unclosed `{` on the current line, or nil.
    var variablePrefix: String? {
        guard let range = openBraceRange else { return nil }
        return String((string as NSString).substring(with: range).dropFirst())
    }

    /// From the unclosed `{` to the cursor.
    private var openBraceRange: NSRange? {
        let text = string as NSString
        let cursor = selectedRange().location
        guard selectedRange().length == 0, cursor <= text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: cursor, length: 0))
        let before = NSRange(location: line.location, length: cursor - line.location)
        let brace = text.range(of: "{", options: .backwards, range: before)
        guard brace.location != NSNotFound else { return nil }
        let typed = text.substring(with: NSRange(location: brace.location + 1, length: cursor - brace.location - 1))
        guard typed.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
        return NSRange(location: brace.location, length: cursor - brace.location)
    }

    func updateCompletion() {
        guard let window, let range = openBraceRange, let prefix = variablePrefix else {
            completion.hide()
            return
        }
        let items = PromptTemplate.completions(for: prefix)
        guard !items.isEmpty else {
            completion.hide()
            return
        }
        let caret = firstRect(forCharacterRange: NSRange(location: range.location, length: 0), actualRange: nil)
        completion.show(items, below: caret, in: window)
    }

    private func accept(_ variable: PromptTemplate.Variable) {
        guard let range = openBraceRange else { return }
        completion.hide()
        insertText(variable.token, replacementRange: range)
    }

    override func keyDown(with event: NSEvent) {
        guard completion.isVisible else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case 125: completion.move(by: 1) // ↓
        case 126: completion.move(by: -1) // ↑
        case 36, 76, 48: // Return, Enter, Tab
            if let variable = completion.current { accept(variable) }
        case 53: completion.hide() // Esc closes the list, not the sheet.
        default: super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        completion.hide()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { completion.hide() }
        super.viewWillMove(toWindow: newWindow)
    }

    func highlightVariables() {
        guard let storage = textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: Self.font, .foregroundColor: NSColor.labelColor], range: whole)
        for token in PromptTemplate(string).tokens() {
            let range = NSRange(token.range, in: string)
            if token.isKnown {
                storage.addAttributes([
                    .foregroundColor: NSColor.controlAccentColor,
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
                ], range: range)
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
        }
        storage.endEditing()
    }
}

/// The variables matching what follows `{`, under the cursor: name and what
/// it holds. Never takes focus; the editor drives it with ↑ ↓ Return Tab Esc.
@MainActor
final class VariableCompletionList {
    private static let rowHeight: CGFloat = 26
    private static let width: CGFloat = 300
    private static let inset: CGFloat = 5

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.animationBehavior = .none
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.addSubview(rows)
        panel.contentView = background
        return panel
    }()
    private let rows = NSView()

    private(set) var items: [PromptTemplate.Variable] = []
    private(set) var selected = 0
    var onPick: ((PromptTemplate.Variable) -> Void)?

    var isVisible: Bool { panel.isVisible }
    var current: PromptTemplate.Variable? { items.indices.contains(selected) ? items[selected] : nil }

    func show(_ items: [PromptTemplate.Variable], below caret: NSRect, in window: NSWindow) {
        if items != self.items { selected = 0 }
        self.items = items
        render()
        let height = CGFloat(items.count) * Self.rowHeight + 2 * Self.inset
        let frame = NSRect(x: caret.minX - 8, y: caret.minY - height - 4, width: Self.width, height: height)
        panel.setFrame(frame, display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func move(by offset: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + offset + items.count) % items.count
        render()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        items = []
    }

    private func render() {
        rows.subviews.forEach { $0.removeFromSuperview() }
        let height = CGFloat(items.count) * Self.rowHeight
        rows.frame = NSRect(x: Self.inset, y: Self.inset, width: Self.width - 2 * Self.inset, height: height)
        for (index, variable) in items.enumerated() {
            let row = CompletionRow(variable: variable, isSelected: index == selected)
            row.frame = NSRect(x: 0, y: height - CGFloat(index + 1) * Self.rowHeight, width: rows.frame.width, height: Self.rowHeight)
            row.onClick = { [weak self] in self?.onPick?(variable) }
            rows.addSubview(row)
        }
    }

    private final class CompletionRow: NSView {
        var onClick: (() -> Void)?
        private let isSelected: Bool

        init(variable: PromptTemplate.Variable, isSelected: Bool) {
            self.isSelected = isSelected
            super.init(frame: .zero)
            let token = NSTextField(labelWithString: variable.token)
            token.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            token.textColor = isSelected ? .white : .controlAccentColor
            let summary = NSTextField(labelWithString: variable.summary)
            summary.font = NSFont.systemFont(ofSize: 12)
            summary.textColor = isSelected ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
            summary.lineBreakMode = .byTruncatingTail
            token.sizeToFit()
            summary.sizeToFit()
            token.frame.origin = NSPoint(x: 8, y: 5)
            summary.frame = NSRect(x: 112, y: 6, width: 170, height: summary.frame.height)
            addSubview(token)
            addSubview(summary)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func draw(_ dirtyRect: NSRect) {
            guard isSelected else { return }
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }
    }
}
