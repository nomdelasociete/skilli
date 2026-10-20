import Foundation

/// Raycast's snippet and quicklink exports (the JSON files its Snippets and
/// Quicklinks commands export) turned into skil.li's own.
public enum RaycastImport {
    public struct SnippetItem: Equatable, Sendable {
        public let name: String
        public let keyword: String
        public let text: String
        /// Raycast placeholders skil.li does not fill (yet): kept as typed.
        public let unknown: [String]
    }

    public struct QuicklinkItem: Equatable, Sendable {
        public let name: String
        public let url: String
    }

    /// The placeholders skil.li fills in snippets, as Raycast writes them.
    static let snippetPlaceholders: Set<String> = ["{clipboard}", "{cursor}", "{date}", "{time}", "{datetime}", "{day}", "{selection}"]

    /// A snippets export: `[{"name", "text", "keyword"}]`. Nil when the file
    /// is something else.
    public static func snippets(_ data: Data) -> [SnippetItem]? {
        guard let items = list(data, key: "snippets"), items.contains(where: { $0["text"] is String }) else { return nil }
        return items.compactMap { item in
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            // Name and keyword on one line: they go in the file's front matter.
            let name = oneLine((item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(text.prefix(40)))
            let unknown = placeholders(in: text).filter { !snippetPlaceholders.contains($0) }
            return SnippetItem(name: name, keyword: oneLine(item["keyword"] as? String ?? "").replacingOccurrences(of: " ", with: ""),
                               text: text, unknown: unknown)
        }
    }

    /// A quicklinks export: `[{"name", "link"}]`. Raycast's one argument
    /// (`{Query}`, `{argument name="…"}`) becomes `{query}`; a link that
    /// needs anything else (two arguments, `{clipboard}`…) is left out, by
    /// name. Nil when the file is something else.
    public static func quicklinks(_ data: Data) -> (links: [QuicklinkItem], skipped: [String])? {
        guard let items = list(data, key: "quicklinks"), items.contains(where: { $0["link"] is String || $0["url"] is String }) else { return nil }
        var links: [QuicklinkItem] = []
        var skipped: [String] = []
        for item in items {
            guard let link = (item["link"] as? String) ?? (item["url"] as? String) else { continue }
            let name = oneLine((item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? link)
            if let url = quicklinkURL(link) { links.append(QuicklinkItem(name: name, url: url)) } else { skipped.append(name) }
        }
        return (links, skipped)
    }

    /// `https://x.com/search?q={Query}` → `…{query}`; nil when it takes
    /// more than one argument or another placeholder, or is not http(s).
    static func quicklinkURL(_ link: String) -> String? {
        guard link.hasPrefix("http://") || link.hasPrefix("https://") else { return nil }
        let found = placeholders(in: link)
        let arguments = Set(found.filter { $0.lowercased() == "{query}" || $0.hasPrefix("{argument") })
        guard found.count == found.filter({ arguments.contains($0) }).count, arguments.count <= 1 else { return nil }
        var url = link
        for argument in arguments { url = url.replacingOccurrences(of: argument, with: "{query}") }
        return url
    }

    /// `{date format="yyyy"}`, `{Query}`: every `{…}` in the text.
    static func placeholders(in text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"\{[^{}\n]{1,80}\}"#)
        let string = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func list(_ data: Data, key: String) -> [[String: Any]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = root as? [[String: Any]] { return array }
        return (root as? [String: Any])?[key] as? [[String: Any]]
    }
}
