import AppKit

/// What macOS's key bindings make of a key: the command a Mac text field
/// runs for it (⌥← `moveWordLeft:`, ⇧⌘→ `moveToRightEndOfLineAndModifySelection:`,
/// ⌘⌫ `deleteToBeginningOfLine:`…), from Cocoa's standard bindings and the
/// user's own DefaultKeyBinding.dict. Nothing listed here by hand.
@MainActor
enum KeyBindings {
    /// A responder without an input context: `interpretKeyEvents` goes
    /// straight to the key bindings, no input method in between, and the
    /// command found lands here.
    private final class Reader: NSResponder {
        var commands: [Selector] = []

        override func doCommand(by selector: Selector) {
            commands.append(selector)
        }

        override func insertText(_ insertString: Any) {}
    }

    private static let reader = Reader()
    private static let noop = NSSelectorFromString("noop:")

    /// The commands `event` names, in order (a user's DefaultKeyBinding.dict
    /// can bind one key to several); none when it types text or names
    /// nothing (⌘K is `noop:`).
    static func commands(for event: NSEvent) -> [Selector] {
        reader.commands = []
        reader.interpretKeyEvents([event])
        defer { reader.commands = [] }
        return reader.commands.filter { $0 != noop }
    }
}

/// One line edited as a Mac text field edits it, for a line skil.li draws
/// itself (the card's answer): the command a key names (`KeyBindings`)
/// runs on a text view that is never shown, so word, line and selection
/// moves are AppKit's own.
@MainActor
enum LineEditor {
    /// The line's text and its selection (a caret when empty).
    struct Line: Equatable {
        var text: String
        var selection: NSRange
    }

    private static let view: NSTextView = {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 100_000, height: 40))
        view.isRichText = false
        view.isFieldEditor = true
        view.allowsUndo = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        // One line, however long.
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return view
    }()

    /// Moves, selections and deletes; the rest (↩, ⇥, esc, completion…)
    /// is the card's.
    static func edits(_ command: Selector) -> Bool {
        let name = NSStringFromSelector(command)
        return ["move", "delete", "select", "transpose"].contains { name.hasPrefix($0) }
    }

    /// `line` after `command`, as a text field would leave it.
    static func run(_ command: Selector, on line: Line) -> Line {
        view.string = line.text
        view.setSelectedRange(clamped(line.selection, in: line.text))
        view.doCommand(by: command)
        return Line(text: view.string, selection: view.selectedRange())
    }

    /// `text` typed or pasted over the selection, the caret after it.
    static func insert(_ text: String, into line: Line) -> Line {
        let selection = clamped(line.selection, in: line.text)
        let result = (line.text as NSString).replacingCharacters(in: selection, with: text)
        return Line(text: result, selection: NSRange(location: selection.location + (text as NSString).length, length: 0))
    }

    private static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }
}
