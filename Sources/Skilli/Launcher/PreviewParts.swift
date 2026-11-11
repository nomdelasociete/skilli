import AppKit
import SkilliCore

// The parts the launcher's previews are made of (Clipboard History's,
// Search Snippets'): a soft tile, a text that fades at the bottom, and
// Information's label/value rows. Fixed frames, laid out by hand.

/// A soft rounded fill that follows the appearance, drawn at draw time.
final class SoftTile: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }
}

/// A preview's text in its tile: a long one fades out at the bottom
/// instead of being cut through a line; code under its language's name.
/// Parts marked `PreviewText.wash` sit on a rounded wash of that color.
final class PreviewText: NSView {
    /// An `NSColor`: the rounded wash under these characters.
    static let wash = NSAttributedString.Key("SkilliPreviewWash")
    static let prose = NSFont.systemFont(ofSize: 13)
    static let code = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

    private let scroll = NSScrollView()
    private let textView: PreviewTextView
    private let fade = CAGradientLayer()
    private let language = NSTextField(labelWithString: "")
    private let languageLine = HairlineView()

    override init(frame: NSRect) {
        // TextKit 1, for the washes (`WashLayoutManager`).
        let storage = NSTextStorage()
        let layout = WashLayoutManager()
        // A long text is laid out where it is looked at, not from its
        // first line down to there.
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = PreviewTextView(frame: frame, textContainer: container)
        super.init(frame: frame)
        textView.isEditable = false
        textView.isSelectable = false
        textView.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28)]
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isVerticallyResizable = true
        // As tall as its text: without this it stays as tall as it was
        // made, and a place far down a long text cannot be scrolled to.
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.wantsLayer = true
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        scroll.layer?.mask = fade
        addSubview(scroll)
        language.font = Theme.Font.sectionHeader
        language.textColor = .secondaryLabelColor
        addSubview(language)
        addSubview(languageLine)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The text as shown (attachments as U+FFFC).
    var string: String { textView.string }

    /// A part of the text can be picked with the pointer (the clipboard
    /// history's copies: docs/clipboard-text-selection.md).
    var isSelectable: Bool {
        get { textView.isSelectable }
        set { textView.isSelectable = newValue }
    }

    /// The part picked, when there is one.
    var selectedText: String? {
        let range = textView.selectedRange()
        guard textView.isSelectable, !isHidden, range.length > 0 else { return nil }
        return (textView.string as NSString).substring(with: range)
    }

    /// Nothing picked any more. `true` when a part was.
    @discardableResult
    func clearSelection() -> Bool {
        let had = textView.selectedRange().length > 0
        if had { textView.setSelectedRange(NSRange(location: 0, length: 0)) }
        return had
    }

    /// Picks `range` of the text shown (self-test hook).
    func select(_ range: NSRange) {
        textView.setSelectedRange(range)
    }

    /// Where `range` of the text is on screen (self-test hook: a real drag
    /// over it).
    func screenRect(of range: NSRange) -> NSRect {
        textView.firstRect(forCharacterRange: range, actualRange: nil)
    }

    /// How many places `mark` marked.
    private(set) var markedCount = 0
    private var firstMarked: NSRange?

    /// Self-test hook: the first place marked is in the part of the text
    /// in view.
    var firstMarkInView: Bool {
        guard let firstMarked, let layout = textView.layoutManager, let container = textView.textContainer else { return false }
        let glyphs = layout.glyphRange(forCharacterRange: firstMarked, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        return textView.visibleRect.intersects(rect)
    }

    /// Self-test hook: where the first mark and the part in view are.
    var markPlace: String {
        guard let firstMarked, let layout = textView.layoutManager, let container = textView.textContainer else { return "no mark" }
        let glyphs = layout.glyphRange(forCharacterRange: firstMarked, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        return "mark y \(Int(rect.minY)), in view \(Int(textView.visibleRect.minY))–\(Int(textView.visibleRect.maxY)), text \(Int(textView.frame.height)) pt high, max \(Int(min(textView.maxSize.height, 99_999)))"
    }

    /// Marks every place a word of `words` is in the text shown (the
    /// history's search), and with `moving` scrolls the first into view.
    /// Temporary attributes: the text itself, and what is picked in it,
    /// stay as they are.
    func mark(_ words: String, moving: Bool) {
        guard let layout = textView.layoutManager else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        let string = textView.string
        let found = words.isEmpty ? [] : ClipboardSearch.ranges(of: words, in: string).map { NSRange($0, in: string) }
        markedCount = found.count
        firstMarked = found.first
        markedWords = words
        for range in found {
            layout.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), forCharacterRange: range)
        }
        if moving, let first = found.first { textView.scrollRangeToVisible(first) }
    }

    /// A long copy shows whole up to this many characters: its start at
    /// once, the rest right after (`show`, `whole`).
    static let wholeLimit = 200_000

    /// The words marked last, to mark them in the rest of a long text.
    private var markedWords = ""
    /// The text asked for last, as given: the same again keeps its place.
    private var source: NSAttributedString?
    /// One more for each text shown: a rest that comes for another is dropped.
    private var shows = 0
    /// Self-test hooks: the rest of a long text is still to come; the
    /// longest one piece of the last one held the main thread; how many
    /// pieces in how long.
    private(set) var restPending = false
    private(set) var restTook: Duration = .zero
    private(set) var restLaps = ""

    /// Plain text, monospaced when it is code. `keeping`: the same copy
    /// shown again keeps its place and what is picked in it.
    func show(_ text: String, code: Bool, language: String?, limit: Int = 4_000, whole: Int = 0, keeping: Bool = false) {
        show(NSAttributedString(string: text, attributes: Self.attributes(code: code)), language: language, limit: limit, whole: whole,
             keeping: keeping)
    }

    /// `limit` characters at once (the preview shows in well under a
    /// frame whatever the copy). With `whole` over `limit`, the rest up
    /// to `whole` joins them piece by piece on the main thread's next
    /// turns, in place: nothing in view moves, what is picked stays
    /// picked, and the words marked are marked in it too (the first
    /// scrolled to when nothing before it held one).
    func show(_ text: NSAttributedString, language name: String?, limit: Int = 4_000, whole: Int = 0, keeping: Bool = false) {
        language.stringValue = name ?? ""
        language.isHidden = name == nil
        languageLine.isHidden = name == nil
        needsLayout = true
        if keeping, let source, source.isEqual(to: text) { return }
        source = text
        shows += 1
        restPending = false
        let head = Self.cut(text, at: limit)
        textView.textStorage?.setAttributedString(head)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(.zero)
        // `head !== text`: it was cut, and ends with "…".
        guard whole > limit, head !== text else { return }
        restPending = true
        restTook = .zero
        join(Self.cut(text, at: whole), from: head.length - 1, show: shows, began: .now, pieces: 0)
    }

    /// Another preview takes the text's place (a picture, a card, no
    /// row): the pieces still to come are dropped, and the same text
    /// asked for again is shown anew.
    func stop() {
        shows += 1
        restPending = false
        source = nil
    }

    /// A piece of the rest joins the text on each turn of the main
    /// thread: all at once held it 36 ms for 140,000 characters (measured
    /// 2026-11-11), a key not drawn meanwhile.
    /// Each piece is laid out as it comes: left for later, the whole
    /// layout fell on the turn that scrolled to a word far down (31 ms).
    private static let piece = 8_000

    /// `from`: where the text shown ends ("…", which gives way to what
    /// follows). Stops when another text is shown.
    private func join(_ all: NSAttributedString, from: Int, show: Int, began: ContinuousClock.Instant, pieces: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shows == show, let storage = self.textView.textStorage, storage.length == from + 1 else { return }
            let start = ContinuousClock.now
            var end = min(all.length, from + Self.piece)
            if end < all.length { end = Self.edge(in: all, near: end, after: from) }
            let part = NSMutableAttributedString(attributedString: all.attributedSubstring(from: NSRange(location: from, length: end - from)))
            let last = end == all.length
            if !last { part.append(NSAttributedString(string: "…", attributes: all.attributes(at: end - 1, effectiveRange: nil))) }
            storage.replaceCharacters(in: NSRange(location: from, length: 1), with: part)
            self.textView.layoutManager?.ensureLayout(forCharacterRange: NSRange(location: from, length: part.length))
            // The words marked, in what just came too; the first scrolled
            // to when nothing before held one.
            let hadMark = self.firstMarked != nil
            if !self.markedWords.isEmpty, !hadMark || last { self.mark(self.markedWords, moving: !hadMark) }
            self.needsLayout = true
            self.restTook = max(self.restTook, ContinuousClock.now - start)
            guard !last else {
                self.restPending = false
                self.restLaps = "\(pieces + 1) pieces in \((ContinuousClock.now - began).compact)"
                return
            }
            self.join(all, from: end, show: show, began: began, pieces: pieces + 1)
        }
    }

    /// Past `limit` characters the start, then "…".
    private static func cut(_ text: NSAttributedString, at limit: Int) -> NSAttributedString {
        guard text.length > limit else { return text }
        let end = edge(in: text, near: limit, after: 0)
        guard end < text.length else { return text }
        let cut = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: end)))
        cut.append(NSAttributedString(string: "…", attributes: text.attributes(at: end - 1, effectiveRange: nil)))
        return cut
    }

    /// Where to cut `text` near `place` without splitting a character
    /// made of several (a letter and its marks, an emoji): before it,
    /// or after it when that would not go past `start` (a letter with
    /// thousands of marks: a cut before it would never advance).
    static func edge(in text: NSAttributedString, near place: Int, after start: Int) -> Int {
        let whole = (text.string as NSString).rangeOfComposedCharacterSequence(at: place)
        return whole.location > start ? whole.location : min(text.length, NSMaxRange(whole))
    }

    static func attributes(code: Bool) -> [NSAttributedString.Key: Any] {
        [.font: code ? Self.code : Self.prose, .foregroundColor: NSColor.labelColor]
    }

    override func layout() {
        super.layout()
        let inner = bounds
        // Code in a language: its name on a line of its own atop the code.
        let header: CGFloat = language.isHidden ? 0 : 30
        language.frame = NSRect(x: 14, y: inner.maxY - 22, width: inner.width - 28, height: 14)
        languageLine.frame = NSRect(x: 0, y: inner.maxY - header, width: inner.width, height: 1)
        scroll.frame = NSRect(x: 0, y: 0, width: inner.width, height: inner.height - header)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = scroll.bounds
        // From the top down: solid, then clear over the last 30 pt. The
        // scroll view is flipped: its layer's top is y 0.
        let length = min(0.5, 30 / max(scroll.bounds.height, 1))
        let top: CGFloat = scroll.isFlipped ? 0 : 1
        fade.locations = [0, NSNumber(value: 1 - length), 1]
        fade.startPoint = CGPoint(x: 0.5, y: top)
        fade.endPoint = CGPoint(x: 0.5, y: 1 - top)
        CATransaction.commit()
        textView.frame = NSRect(origin: .zero, size: NSSize(width: inner.width, height: max(scroll.frame.height, textView.frame.height)))
        textView.textContainer?.containerSize = NSSize(width: inner.width - 16, height: .greatestFiniteMagnitude)
    }
}

/// The preview's text: a part of it picked with the pointer copies as
/// plain text (never the preview's font and color), and a right click
/// offers Copy alone: Look Up or Services would take the keys from the
/// launcher, which closes when it loses them.
private final class PreviewTextView: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? {
        guard isSelectable, selectedRange().length > 0 else { return nil }
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        return menu
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((string as NSString).substring(with: range), forType: .string)
    }
}

/// Draws `PreviewText.wash` as a rounded fill behind its characters, line
/// by line.
private final class WashLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(PreviewText.wash, in: characters) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            color.setFill()
            enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                    in: container) { rect, _ in
                let wash = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -2.5, dy: 0.5)
                NSBezierPath(roundedRect: wash, xRadius: 4, yRadius: 4).fill()
            }
        }
    }
}

/// "Information", a hairline, then label/value rows, from the bottom of
/// the preview up. Rows hidden while empty; one changed in place when a
/// value comes late ("File size", "…").
final class PreviewInformation: NSView {
    static let rowHeight: CGFloat = 21
    private let header = NSTextField(labelWithString: "Information")
    private let line = HairlineView()
    private var rows: [(label: NSTextField, value: NSTextField)] = []
    private let capacity: Int
    /// What the rows say (self-test hook).
    private(set) var shown: [(String, String)] = []

    init(rows capacity: Int) {
        self.capacity = capacity
        super.init(frame: .zero)
        header.font = Theme.Font.sectionHeader
        header.textColor = .secondaryLabelColor
        addSubview(header)
        addSubview(line)
        for _ in 0..<capacity {
            let label = NSTextField(labelWithString: "")
            label.font = Theme.Font.rowAccessory
            label.textColor = .secondaryLabelColor
            let value = NSTextField(labelWithString: "")
            value.font = Theme.Font.rowAccessory
            value.textColor = .labelColor
            value.alignment = .right
            value.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            addSubview(value)
            rows.append((label, value))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// "1 word", "12 characters".
    static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted()) \(noun)\(value == 1 ? "" : "s")"
    }

    /// A text's Size row: "12 words · 64 characters" (· "3 lines" past
    /// one), and its words.
    static func size(of text: String) -> (size: String, words: Int) {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lines = text.split(whereSeparator: \.isNewline).count
        var size = "\(count(words, "word")) · \(count(text.count, "character"))"
        if lines > 1 { size += " · \(count(lines, "line"))" }
        return (size, words)
    }

    /// Its height for what it shows: nothing when there is nothing.
    var height: CGFloat { shown.isEmpty ? 0 : CGFloat(shown.count) * Self.rowHeight + 22 }

    func set(_ info: [(String, String)]) {
        let info = Array(info.prefix(capacity))
        shown = info
        header.isHidden = info.isEmpty
        line.isHidden = info.isEmpty
        for (index, row) in rows.enumerated() {
            let pair = index < info.count ? info[index] : nil
            row.label.stringValue = pair?.0 ?? ""
            row.value.stringValue = pair?.1 ?? ""
        }
        needsLayout = true
    }

    /// One row filled in after it was shown.
    func update(_ label: String, _ value: String) {
        if let index = shown.firstIndex(where: { $0.0 == label }) {
            shown[index].1 = value
            rows[index].value.stringValue = value
        }
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for (index, row) in rows.enumerated().reversed() {
            guard index < shown.count else {
                row.label.frame = .zero
                row.value.frame = .zero
                continue
            }
            row.label.frame = NSRect(x: 0, y: y, width: 120, height: 16)
            row.value.frame = NSRect(x: 112, y: y, width: bounds.width - 112, height: 16)
            y += Self.rowHeight
        }
        line.frame = NSRect(x: 0, y: y + 1, width: bounds.width, height: 1)
        header.frame = NSRect(x: 0, y: y + 8, width: bounds.width, height: 14)
    }
}
