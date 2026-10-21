import AppKit

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
    private let textView: NSTextView
    private let fade = CAGradientLayer()
    private let language = NSTextField(labelWithString: "")
    private let languageLine = HairlineView()

    override init(frame: NSRect) {
        // TextKit 1, for the washes (`WashLayoutManager`).
        let storage = NSTextStorage()
        let layout = WashLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = NSTextView(frame: frame, textContainer: container)
        super.init(frame: frame)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isVerticallyResizable = true
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

    /// Plain text, monospaced when it is code.
    func show(_ text: String, code: Bool, language: String?) {
        show(NSAttributedString(string: text, attributes: Self.attributes(code: code)), language: language)
    }

    func show(_ text: NSAttributedString, language name: String?) {
        // Past 4,000 characters nobody reads it here.
        if text.length > 4_000 {
            let end = (text.string as NSString).rangeOfComposedCharacterSequence(at: 4_000).location
            let cut = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: end)))
            cut.append(NSAttributedString(string: "…", attributes: text.attributes(at: end - 1, effectiveRange: nil)))
            textView.textStorage?.setAttributedString(cut)
        } else {
            textView.textStorage?.setAttributedString(text)
        }
        textView.scroll(.zero)
        language.stringValue = name ?? ""
        language.isHidden = name == nil
        languageLine.isHidden = name == nil
        needsLayout = true
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
                let wash = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -2.5, dy: 0)
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
