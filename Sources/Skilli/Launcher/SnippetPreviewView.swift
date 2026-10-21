import AppKit
import SkilliCore

/// Search Snippets' right side, made from Clipboard History's parts: the
/// snippet as it would type now (the expander's own expansion and values:
/// filled placeholders on an accent wash, `{cursor}` as a thin caret, a
/// `{clipboard}` skil.li may not read without macOS asking left as
/// written on a grey wash), then Information. Fixed frames; nothing on
/// this path reads a file or the network (docs/snippet-preview.md).
@MainActor
final class SnippetPreviewView: NSView {
    /// What the launcher knows of a snippet as the mode opens.
    struct Details {
        /// When its keyword expands now ("After a space or ↩", "Off",
        /// "Not in 1Password").
        var expands: String?
        var alias: String?
        /// Its shortcut, as keys ("⌥⇧⌘9").
        var shortcut: String?
        /// Its file's date.
        var modified: Date?
    }

    private let divider = HairlineView()
    private let tile = SoftTile()
    private let text = PreviewText()
    private let placeholder = NSImageView()
    private let information = PreviewInformation(rows: 7)
    /// Each snippet's language, guessed once by its text (`CodeLanguage`).
    private var languages: [String: (text: String, language: String?)] = [:]

    /// Self-test hooks: the snippet shown, what it would type, the values
    /// on the accent wash, the tokens left as written, the caret, the rows.
    private(set) var shownID: String?
    private(set) var shownTyped = ""
    private(set) var shownFilled: [String] = []
    private(set) var shownUnfilled: [String] = []
    private(set) var shownCaret = false
    private(set) var shownCode = false
    var shownInfo: [(String, String)] { information.shown }
    private(set) var lastShowTime: Duration = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(divider)
        addSubview(tile)
        tile.addSubview(text)
        placeholder.image = Theme.symbol("text.quote", pointSize: 34, weight: .light)
        placeholder.contentTintColor = .tertiaryLabelColor
        tile.addSubview(placeholder)
        addSubview(information)
        show(nil, preview: nil, details: Details())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    /// As Clipboard History's: Information from the bottom, the tile
    /// above it.
    override func layout() {
        super.layout()
        let inset: CGFloat = 16
        let width = bounds.width - inset - 20
        divider.frame = NSRect(x: 0, y: 12, width: 1, height: bounds.height - 24)
        var y: CGFloat = 8
        information.frame = NSRect(x: inset, y: y, width: width, height: information.height)
        if information.height > 0 { y = information.frame.maxY + 14 }
        tile.frame = NSRect(x: inset, y: y, width: width, height: max(80, bounds.height - 12 - y))
        text.frame = tile.bounds
        placeholder.frame = NSRect(x: tile.bounds.midX - 24, y: tile.bounds.midY - 24, width: 48, height: 48)
    }

    // MARK: - Showing

    /// `snippet` with `preview`, the expander's pieces and the variables
    /// it could not fill now; nil: the quiet tile, no Information.
    func show(_ snippet: Snippet?, preview: (pieces: [Snippet.Piece], unfilled: Set<PromptTemplate.Variable>)?, details: Details) {
        let start = ContinuousClock.now
        defer { lastShowTime = ContinuousClock.now - start }
        shownID = snippet?.id
        shownFilled = []
        shownUnfilled = []
        shownCaret = false
        guard let snippet, let preview else {
            shownTyped = ""
            shownCode = false
            text.isHidden = true
            placeholder.isHidden = false
            information.set([])
            needsLayout = true
            return
        }
        let language = language(of: snippet)
        shownCode = language != nil
        text.show(attributed(preview.pieces, unfilled: preview.unfilled, code: language != nil),
                  language: language.flatMap { $0.isEmpty ? nil : $0 })
        text.isHidden = false
        placeholder.isHidden = true
        shownTyped = preview.pieces.map(\.typed).joined()
        information.set(info(snippet, typed: shownTyped, details: details))
        needsLayout = true
    }

    /// The mode closed: nothing kept.
    func release() {
        show(nil, preview: nil, details: Details())
        languages = [:]
    }

    /// "" for code in no language told apart, nil for prose.
    private func language(of snippet: Snippet) -> String? {
        if let known = languages[snippet.id], known.text == snippet.text { return known.language }
        let guess = CodeLanguage.guess(String(snippet.text.prefix(4_000)))
        languages[snippet.id] = (snippet.text, guess)
        return guess
    }

    private func attributed(_ pieces: [Snippet.Piece], unfilled: Set<PromptTemplate.Variable>, code: Bool) -> NSAttributedString {
        let body = PreviewText.attributes(code: code)
        let string = NSMutableAttributedString()
        for piece in pieces {
            switch piece {
            case .written(let written):
                string.append(NSAttributedString(string: written, attributes: body))
            case .filled(let token, let variable, let value):
                if let variable, unfilled.contains(variable) {
                    // Filled only when typed: the token as written, grey.
                    var attributes = body
                    attributes[.foregroundColor] = NSColor.secondaryLabelColor
                    attributes[PreviewText.wash] = NSColor.labelColor.withAlphaComponent(0.08)
                    string.append(NSAttributedString(string: token, attributes: attributes))
                    shownUnfilled.append(token)
                } else if !value.isEmpty {
                    var attributes = body
                    attributes[PreviewText.wash] = NSColor.controlAccentColor.withAlphaComponent(0.16)
                    string.append(NSAttributedString(string: value, attributes: attributes))
                    shownFilled.append(value)
                }
            case .cursor:
                var attributes = body
                attributes[.attachment] = Self.caret(code: code)
                string.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
                shownCaret = true
            }
        }
        return string
    }

    /// Only what is known; a row that would hold nothing is left out.
    private func info(_ snippet: Snippet, typed: String, details: Details) -> [(String, String)] {
        var info: [(String, String)] = []
        if !snippet.keyword.isEmpty {
            info.append(("Keyword", snippet.keyword))
            if let expands = details.expands { info.append(("Expands", expands)) }
        }
        let placeholders = snippet.placeholders
        if !placeholders.isEmpty { info.append(("Placeholders", placeholders.joined(separator: ", "))) }
        if let alias = details.alias { info.append(("Alias", alias)) }
        if let shortcut = details.shortcut { info.append(("Shortcut", shortcut)) }
        info.append(("Size", PreviewInformation.size(of: typed).size))
        if let modified = details.modified { info.append(("Modified", ClipboardPreviewView.formatted(modified))) }
        return info
    }

    // MARK: - The caret

    private static var carets: [Bool: NSTextAttachment] = [:]

    /// A thin accent bar the height of the line, where `{cursor}` leaves
    /// the caret.
    private static func caret(code: Bool) -> NSTextAttachment {
        if let made = carets[code] { return made }
        let font = code ? PreviewText.code : PreviewText.prose
        let size = NSSize(width: 4, height: ceil(font.ascender - font.descender))
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: 0, width: 1.5, height: rect.height), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: floor(font.descender), width: size.width, height: size.height)
        carets[code] = attachment
        return attachment
    }
}
