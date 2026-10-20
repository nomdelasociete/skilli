import Foundation

/// A web search or page behind a keyword: "g skilli" opens Google's
/// results for skilli. `{query}` in the URL takes what follows the
/// keyword, percent-encoded.
public struct Quicklink: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Typed first: "g", "yt". Empty: found by name only.
    public var keyword: String
    public var url: String

    public init(id: UUID = UUID(), name: String, keyword: String, url: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.url = url
    }

    public static let queryToken = "{query}"

    /// Shipped, editable in Settings → Catalog → Quicklinks.
    public static let defaults = [
        Quicklink(name: "Google", keyword: "g", url: "https://www.google.com/search?q={query}"),
        Quicklink(name: "YouTube", keyword: "yt", url: "https://www.youtube.com/results?search_query={query}"),
        Quicklink(name: "GitHub", keyword: "gh", url: "https://github.com/search?q={query}"),
        Quicklink(name: "Wikipedia", keyword: "wiki", url: "https://fr.wikipedia.org/w/index.php?search={query}"),
        Quicklink(name: "Maps", keyword: "map", url: "https://maps.apple.com/?q={query}"),
        Quicklink(name: "Translate", keyword: "tr", url: "https://translate.google.com/?sl=auto&text={query}")
    ]

    /// The address for `query`; the page itself when there is none.
    public func address(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        let text = url.replacingOccurrences(of: Self.queryToken, with: encoded)
        guard let address = URL(string: text), let scheme = address.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return address
    }

    public var takesQuery: Bool { url.contains(Self.queryToken) }

    /// The selected text as a query, when none is typed: on one line,
    /// spaces folded, 1,000 characters at most. Nil when it holds nothing.
    public static func query(fromSelection text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return line.count > 1_000 ? String(line.prefix(1_000)) : line
    }

    /// A browser tab, as listed for "Reuse an open tab": its window (the
    /// browser's own id), its place in that window, its address, whether
    /// it is the window's tab in front. Windows front first.
    public struct OpenTab: Equatable, Sendable {
        public let window: Int
        public let index: Int
        public let url: String
        public let active: Bool

        public init(window: Int, index: Int, url: String, active: Bool) {
            self.window = window
            self.index = index
            self.url = url
            self.active = active
        }
    }

    /// The tab to load `address` in: one on the same site (`www.` aside),
    /// preferably one showing the same page already (a search there
    /// before: same path), then the one in front of its window, then the
    /// first; front windows first. Nil when no tab is on that site.
    public static func tabToReuse(for address: URL, among tabs: [OpenTab]) -> OpenTab? {
        guard let host = site(address) else { return nil }
        let path = address.path()
        let onSite = tabs.filter { URL(string: $0.url).flatMap(site) == host }
        let samePage = onSite.filter { URL(string: $0.url)?.path() == path }
        for group in [samePage, onSite] where !group.isEmpty {
            return group.first(where: \.active) ?? group[0]
        }
        return nil
    }

    /// An http(s) address's host, lowercased, without `www.`.
    static func site(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), var host = url.host()?.lowercased(), !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// "g skilli launcher" → the Google link and "skilli launcher".
    public static func match(_ text: String, in links: [Quicklink]) -> (link: Quicklink, query: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return nil }
        let keyword = trimmed[..<space].lowercased()
        let query = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let link = links.first(where: { !$0.keyword.isEmpty && $0.keyword.lowercased() == keyword && $0.takesQuery }) else { return nil }
        return (link, query)
    }
}
