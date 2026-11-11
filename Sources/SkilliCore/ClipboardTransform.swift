import Foundation

/// A text copy pasted another way (docs/clipboard-paste-transforms.md):
/// what ⌘K offers on it, only where it changes something. All code, on
/// this Mac.
public struct ClipboardTransform: Equatable, Sendable {
    /// As ⌘K lists it: "Paste as RGB".
    public let title: String
    /// Its SF Symbol.
    public let symbol: String
    /// What is pasted.
    public let text: String

    /// Longer copies get none: the list is made when ⌘K opens, in well
    /// under a frame.
    static let limit = 100_000
    /// Case changes are for a line or a paragraph, not a file.
    static let caseLimit = 10_000

    /// The ways `text` can be pasted that differ from it, by what it is:
    /// a color in its other forms, a link without its tracking, JSON
    /// laid out or packed, then one line, trimmed, and its case.
    public static func all(for text: String) -> [ClipboardTransform] {
        guard text.utf16.count <= limit else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var found: [ClipboardTransform] = []
        func add(_ title: String, _ symbol: String, _ result: String?) {
            guard let result, !result.isEmpty, result != text, result != trimmed || title == "Paste Trimmed",
                  !found.contains(where: { $0.text == result }) else { return }
            found.append(ClipboardTransform(title: title, symbol: symbol, text: result))
        }
        let value = CopiedValue.read(text)
        switch value {
        case .color(let color):
            for (name, form) in [("Hex", color.hex), ("RGB", color.rgb), ("HSL", color.hsl)]
            where form.caseInsensitiveCompare(trimmed) != .orderedSame {
                add("Paste as \(name)", "paintpalette", form)
            }
            return found
        case .link(let url):
            add("Paste Without Tracking", "link", withoutTracking(url))
        default:
            break
        }
        if let json = JSONLayout(trimmed) {
            add("Paste as Pretty JSON", "curlybraces", json.pretty)
            add("Paste as Minified JSON", "curlybraces", json.minified)
        }
        let lines = trimmed.split(whereSeparator: \.isNewline)
        if lines.count == 1, trimmed.contains("%"), let decoded = trimmed.removingPercentEncoding {
            add("Paste URL-Decoded", "percent", decoded)
        }
        if lines.count > 1 {
            add("Paste as One Line", "arrow.right.to.line",
                lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " "))
        }
        if trimmed != text { add("Paste Trimmed", "scissors", trimmed) }
        // Prose only: a link, an address or code in capitals is no use.
        if value == .text, trimmed.utf16.count <= caseLimit, trimmed.contains(where: \.isLetter) {
            add("Paste UPPERCASE", "textformat", trimmed.uppercased())
            add("Paste lowercase", "textformat", trimmed.lowercased())
            add("Paste Title Case", "textformat", trimmed.capitalized)
        }
        return found
    }

    // MARK: - Links

    /// Query names that only follow the reader: the campaign's (`utm_…`)
    /// and the ad networks' click ids.
    static let trackers: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid", "twclid",
        "ttclid", "li_fat_id", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "s_cid"
    ]

    /// The link without its tracking; nil when it has none.
    public static func withoutTracking(_ url: URL) -> String? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = parts.percentEncodedQueryItems else { return nil }
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackers.contains(name)
        }
        guard kept.count < items.count else { return nil }
        parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return parts.string
    }
}

/// JSON laid out again without being read into values: the keys keep
/// their order, the numbers their digits.
struct JSONLayout {
    let pretty: String
    let minified: String

    /// Nil when `text` is not a JSON object or array.
    init?(_ text: String) {
        guard let first = text.first, first == "{" || first == "[", let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        var pretty = ""
        var minified = ""
        var depth = 0
        var inString = false
        var escaped = false
        var afterOpen = false
        func line(_ depth: Int) -> String { "\n" + String(repeating: "  ", count: depth) }
        for character in text {
            if inString {
                pretty.append(character)
                minified.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character.isWhitespace { continue }
            minified.append(character)
            switch character {
            case "{", "[":
                if afterOpen { pretty += line(depth) }
                pretty.append(character)
                depth += 1
                afterOpen = true
                continue
            case "}", "]":
                depth -= 1
                // Nothing inside: "{}" stays on its line.
                if !afterOpen { pretty += line(depth) }
                pretty.append(character)
            case ",":
                pretty.append(character)
                pretty += line(depth)
            case ":":
                pretty += ": "
            default:
                if afterOpen { pretty += line(depth) }
                if character == "\"" { inString = true }
                pretty.append(character)
            }
            afterOpen = false
        }
        self.pretty = pretty
        self.minified = minified
    }
}
