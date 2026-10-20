import AppKit
import SkilliCore

/// The Markdown an AI answers with, as the card shows it: headings in
/// semibold, bullets as •, code in SF Mono, bold, italic, inline code and
/// links styled; the markers themselves never shown. Text without Markdown
/// stays exactly as written.
enum CardMarkdown {
    /// `color` nil: no color at all (for the clipboard, where the app
    /// pasted into picks its own).
    static func render(_ text: String, font: NSFont, color: NSColor?) -> NSAttributedString {
        guard MarkdownBlocks.looksLikeMarkdown(text) else { return plain(text, font: font, color: color) }
        let result = NSMutableAttributedString()
        let lines = MarkdownBlocks.lines(text)
        let indentStep = font.pointSize
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(plain("\n", font: font, color: color)) }
            let start = result.length
            switch line.kind {
            case .blank:
                continue
            case .rule:
                result.append(plain("———", font: font, color: color == nil ? nil : .tertiaryLabelColor))
            case .code:
                result.append(plain(line.text, font: monospaced(font), color: color))
            case .heading(let level):
                let size = font.pointSize + (level <= 2 ? 1 : 0)
                result.append(inline(line.text, font: NSFont.systemFont(ofSize: size, weight: .semibold), color: color))
                let style = NSMutableParagraphStyle()
                style.paragraphSpacing = font.pointSize * 0.3
                result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: result.length - start))
            case .quote:
                result.append(plain("▎ ", font: font, color: color == nil ? nil : .tertiaryLabelColor))
                result.append(inline(line.text, font: font, color: color == nil ? nil : .secondaryLabelColor))
            case .bullet(let depth), .numbered(_, let depth):
                let marker: String
                if case .numbered(let written, _) = line.kind { marker = written + " " } else { marker = "•  " }
                result.append(plain(marker, font: font, color: color == nil ? nil : .secondaryLabelColor))
                result.append(inline(line.text, font: font, color: color))
                // Wrapped lines start under the text, not under the marker.
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = CGFloat(depth) * indentStep
                style.headIndent = CGFloat(depth) * indentStep + (marker as NSString).size(withAttributes: [.font: font]).width
                result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: result.length - start))
            case .paragraph:
                result.append(inline(line.text, font: font, color: color))
            }
        }
        return result
    }

    /// The answer for a plain-text paste: no markers.
    static func plainText(_ text: String) -> String {
        guard MarkdownBlocks.looksLikeMarkdown(text) else { return text }
        return MarkdownBlocks.plain(text) { line in
            (try? AttributedString(markdown: line, options: inlineOptions)).map { String($0.characters) } ?? line
        }
    }

    private static let inlineOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible
    )

    /// Bold, italic, strikethrough, inline code and links inside one line.
    private static func inline(_ text: String, font: NSFont, color: NSColor?) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: text, options: inlineOptions) else { return plain(text, font: font, color: color) }
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let color { attributes[.foregroundColor] = color }
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { runFont = monospaced(font) }
                var traits = runFont.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                runFont = NSFont(descriptor: runFont.fontDescriptor.withSymbolicTraits(traits), size: runFont.pointSize) ?? runFont
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if let link = run.link {
                attributes[.link] = link
                if color != nil { attributes[.foregroundColor] = NSColor.linkColor }
            }
            attributes[.font] = runFont
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }

    private static func plain(_ text: String, font: NSFont, color: NSColor?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let color { attributes[.foregroundColor] = color }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func monospaced(_ font: NSFont) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
    }
}
