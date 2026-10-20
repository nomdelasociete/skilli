import Foundation

/// The block level of the Markdown an AI answers with, line by line, for the
/// card: headings, bullets, numbered items, quotes, code blocks, paragraphs.
/// Inline styles (bold, italic, code, links) are read inside each line by
/// the app.
public enum MarkdownBlocks {
    public enum Kind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        /// `depth`: 0 at the margin, 1 for two to four spaces in…
        case bullet(depth: Int)
        /// "1." kept as written.
        case numbered(marker: String, depth: Int)
        case quote
        case code
        /// A blank line between blocks.
        case blank
        /// "---", "***".
        case rule
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        /// The text without its marker ("- ", "## ", "> ").
        public let text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    public static func lines(_ markdown: String) -> [Line] {
        var lines: [Line] = []
        var inCode = false
        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCode.toggle()
                continue
            }
            if inCode {
                lines.append(Line(.code, raw))
                continue
            }
            if trimmed.isEmpty {
                lines.append(Line(.blank, ""))
                continue
            }
            if trimmed.count >= 3, Set(trimmed.replacingOccurrences(of: " ", with: "")).count == 1, ["-", "*", "_"].contains(trimmed.first) {
                lines.append(Line(.rule, ""))
                continue
            }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let depth = min(indent / 2, 4)
            if let hashes = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#") {
                let level = trimmed.distance(from: trimmed.startIndex, to: hashes)
                if level <= 6, trimmed[hashes] == " " {
                    lines.append(Line(.heading(level: level), String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                lines.append(Line(.quote, String(trimmed.dropFirst(trimmed == ">" ? 1 : 2))))
                continue
            }
            if let marker = ["- ", "* ", "+ ", "• "].first(where: trimmed.hasPrefix) {
                lines.append(Line(.bullet(depth: depth), String(trimmed.dropFirst(marker.count))))
                continue
            }
            if let dot = trimmed.firstIndex(where: { !$0.isNumber }), dot != trimmed.startIndex,
               [".", ")"].contains(trimmed[dot]), trimmed.index(after: dot) < trimmed.endIndex, trimmed[trimmed.index(after: dot)] == " " {
                let marker = String(trimmed[...dot])
                lines.append(Line(.numbered(marker: marker, depth: depth), String(trimmed[trimmed.index(dot, offsetBy: 2)...])))
                continue
            }
            lines.append(Line(.paragraph, trimmed))
        }
        return lines
    }

    /// The answer as plain text, for a paste where styles do not go: the
    /// markers gone ("**SAFR-123**" → "SAFR-123", "## Title" → "Title",
    /// "- item" → "• item"). Inline markers are removed by `plainInline`.
    public static func plain(_ markdown: String, plainInline: (String) -> String) -> String {
        lines(markdown).map { line in
            switch line.kind {
            case .blank, .rule: return ""
            case .code: return line.text
            case .bullet(let depth): return String(repeating: "  ", count: depth) + "• " + plainInline(line.text)
            case .numbered(let marker, let depth): return String(repeating: "  ", count: depth) + marker + " " + plainInline(line.text)
            case .heading, .quote, .paragraph: return plainInline(line.text)
            }
        }
        .joined(separator: "\n")
        .replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    /// Whether the text uses Markdown at all (so plain text stays as is).
    public static func looksLikeMarkdown(_ text: String) -> Bool {
        if text.contains("**") || text.contains("`") || text.contains("](") || text.contains("__") { return true }
        return lines(text).contains { line in
            switch line.kind {
            case .heading, .bullet, .numbered, .quote, .code, .rule: return true
            case .paragraph, .blank: return false
            }
        }
    }
}
