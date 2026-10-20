import Foundation

/// A GIF as the GIF mode shows it: one of Klipy's, or a file on this Mac.
public enum GIF: Equatable, Sendable {
    case klipy(KlipyGIF)
    case file(URL)

    /// Its name: Klipy's title, the file's name without ".gif".
    public var title: String {
        switch self {
        case .klipy(let gif): gif.title.isEmpty ? gif.slug : gif.title
        case .file(let url): url.deletingPathExtension().lastPathComponent
        }
    }

    /// Kept in Recently Used: Klipy's slug (never the GIF: Klipy's rule),
    /// the file's path.
    public var recent: GIFRecents.Entry {
        switch self {
        case .klipy(let gif): .klipy(gif.plainSlug)
        case .file(let url): .file(url.path)
        }
    }

    /// What the tile shows still: a small picture loaded first.
    public var stillURL: URL {
        switch self {
        case .klipy(let gif): gif.still
        case .file(let url): url
        }
    }

    /// What the selected tile plays.
    public var playURL: URL {
        switch self {
        case .klipy(let gif): gif.preview
        case .file(let url): url
        }
    }
}

/// One of Klipy's GIFs, as its API returns it (`file` → `sm`, `hd`…).
/// Its URLs are kept as given: Klipy's rule.
public struct KlipyGIF: Equatable, Sendable {
    public let slug: String
    public let title: String
    /// `md.jpg` (else `sm`): the tile's still picture, sharp at 2× (about
    /// 20 KB).
    public let still: URL
    /// `md.webp` (else `sm.webp`, else `sm.gif`): the selected tile plays
    /// it, a fifth of the GIF's weight.
    public let preview: URL
    /// `hd.gif` (else `md`, else `sm`): what is pasted and copied.
    public let full: URL
    public let width: Int
    public let height: Int
    /// The full GIF's size in bytes, as Klipy says it (0 when not said).
    public let size: Int

    public init(slug: String, title: String, still: URL, preview: URL, full: URL, width: Int, height: Int, size: Int) {
        self.slug = slug
        self.title = title
        self.still = still
        self.preview = preview
        self.full = full
        self.width = width
        self.height = height
        self.size = size
    }

    /// Its slug without the search's mark: a search gives
    /// "hello-3--kULSAXj24" (every result of one search ends the same),
    /// `gifs/items` answers "hello-3". Recently Used keeps this one; a
    /// share sends `slug` as given (Klipy's rule: its tracking kept).
    public var plainSlug: String { Self.plain(slug) }

    /// `plainSlug` of any slug (Recently Used kept before it was plain):
    /// the last "--" and the letters and digits after it left out.
    public static func plain(_ slug: String) -> String {
        guard let mark = slug.range(of: "--", options: .backwards), mark.lowerBound > slug.startIndex else { return slug }
        let tail = slug[mark.upperBound...]
        guard !tail.isEmpty, tail.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return slug }
        return String(slug[..<mark.lowerBound])
    }

    /// `![Hello](https://static.klipy.com/…gif)`: where a file cannot go.
    public var markdown: String {
        let name = title.isEmpty ? slug : title
        let escaped = name.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        return "![\(escaped)](\(full.absoluteString))"
    }
}

/// Klipy's API (docs.klipy.com, read 2026-10-19): the key in the path of
/// every request, made from the user's Mac (its rule: no server of ours in
/// between), results shown in its order.
public enum Klipy {
    public static let base = URL(string: "https://api.klipy.com")!
    /// The most a page holds (Klipy allows 8 to 50 for a search).
    public static let pageSize = 48
    /// Klipy's filter: "off", "low", "medium", "high".
    public static let contentFilter = "medium"

    /// One page of a search or of Trending, in Klipy's order.
    public struct Page: Equatable, Sendable {
        public let gifs: [KlipyGIF]
        public let hasNext: Bool

        public init(gifs: [KlipyGIF], hasNext: Bool) {
            self.gifs = gifs
            self.hasNext = hasNext
        }
    }

    public enum Failure: Error, Equatable {
        /// Not Klipy's shape, or `result: false`.
        case unreadable
    }

    /// `/api/v1/{key}/gifs/search?q=…`.
    public static func searchURL(_ query: String, key: String, page: Int = 1, customerID: String, locale: String?,
                                 base: URL = base) -> URL? {
        url(base, key: key, path: "gifs/search", query: [("q", query)] + paging(page) + who(customerID, locale))
    }

    /// `/api/v1/{key}/gifs/trending`.
    public static func trendingURL(key: String, page: Int = 1, customerID: String, locale: String?, base: URL = base) -> URL? {
        url(base, key: key, path: "gifs/trending", query: paging(page) + who(customerID, locale))
    }

    /// `/api/v1/{key}/gifs/items?slugs=a,b`: Recently Used read back.
    public static func itemsURL(_ slugs: [String], key: String, base: URL = base) -> URL? {
        url(base, key: key, path: "gifs/items", query: [("slugs", slugs.joined(separator: ","))])
    }

    /// `POST /api/v1/{key}/gifs/share/{slug}`: a GIF pasted or copied.
    public static func shareURL(_ slug: String, key: String, base: URL = base) -> URL? {
        guard let slug = slug.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) else { return nil }
        return url(base, key: key, path: "gifs/share/\(slug)", query: [])
    }

    /// The share's body: who (skil.li's random id) and the words that led
    /// to it (empty from Trending or Recently Used).
    public static func shareBody(customerID: String, query: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["customer_id": customerID, "q": query], options: [.sortedKeys])) ?? Data()
    }

    /// The country Klipy asks for (ISO 3166 alpha-2, lowercased): "fr".
    public static func locale(region: String?) -> String? {
        guard let region, region.count == 2, region.allSatisfy(\.isLetter) else { return nil }
        return region.lowercased()
    }

    /// `{ "result": true, "data": { "data": [ … ], "has_next": true } }`.
    /// Items without a GIF (an ad, another kind) are not GIFs to show.
    public static func parse(_ data: Data) throws -> Page {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["result"] as? Bool == true,
              let body = root["data"] as? [String: Any], let items = body["data"] as? [[String: Any]] else {
            throw Failure.unreadable
        }
        return Page(gifs: items.compactMap(gif), hasNext: body["has_next"] as? Bool ?? false)
    }

    static func gif(_ item: [String: Any]) -> KlipyGIF? {
        guard (item["type"] as? String ?? "gif") == "gif", let slug = item["slug"] as? String, !slug.isEmpty,
              let files = item["file"] as? [String: Any] else { return nil }
        func format(_ size: String, _ kind: String) -> (url: URL, width: Int, height: Int, size: Int)? {
            guard let sized = files[size] as? [String: Any], let entry = sized[kind] as? [String: Any],
                  let text = entry["url"] as? String, let url = URL(string: text), url.scheme == "https" || url.scheme == "http" else { return nil }
            return (url, entry["width"] as? Int ?? 0, entry["height"] as? Int ?? 0, entry["size"] as? Int ?? 0)
        }
        guard let full = format("hd", "gif") ?? format("md", "gif") ?? format("sm", "gif"),
              let preview = format("md", "webp") ?? format("sm", "webp") ?? format("sm", "gif") ?? format("md", "gif") else { return nil }
        let still = format("md", "jpg") ?? format("sm", "jpg") ?? format("hd", "jpg")
        return KlipyGIF(slug: slug, title: (item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        still: still?.url ?? preview.url, preview: preview.url, full: full.url,
                        width: full.width, height: full.height, size: full.size)
    }

    private static let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))

    private static func paging(_ page: Int) -> [(String, String)] {
        [("page", String(max(page, 1))), ("per_page", String(pageSize)), ("content_filter", contentFilter)]
    }

    private static func who(_ customerID: String, _ locale: String?) -> [(String, String)] {
        [("customer_id", customerID)] + (locale.map { [("locale", $0)] } ?? [])
    }

    private static func url(_ base: URL, key: String, path: String, query: [(String, String)]) -> URL? {
        // Klipy's keys are letters and digits: anything else could change the path.
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let root = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.percentEncodedPath = root + "/api/v1/\(key)/" + path
        // "+" left raw reads as a space on most servers: "c++" would search "c  ".
        components.percentEncodedQueryItems = query.isEmpty ? nil : query.map { name, value in
            URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: queryAllowed))
        }
        return components.url
    }
}

/// Recently Used in the GIF mode, newest first: Klipy's slugs and files'
/// paths only (Klipy's rule: no copy of its GIFs kept).
public struct GIFRecents: Codable, Equatable, Sendable {
    public enum Entry: Codable, Equatable, Hashable, Sendable {
        case klipy(String)
        case file(String)
    }

    public static let limit = 24
    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = Array(entries.prefix(Self.limit))
    }

    /// Used again: first, once.
    public mutating func used(_ entry: Entry) {
        entries.removeAll { $0 == entry }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    public mutating func remove(_ entry: Entry) {
        entries.removeAll { $0 == entry }
    }

    /// Klipy's slugs, in Recently Used's order.
    public var slugs: [String] {
        entries.compactMap { if case .klipy(let slug) = $0 { slug } else { nil } }
    }

    /// The rows in Recently Used's order: Klipy's read back by slug, the
    /// files still on disk. One Klipy no longer gives is left out.
    public func resolve(klipy: [KlipyGIF], fileExists: (String) -> Bool) -> [GIF] {
        let bySlug = Dictionary(klipy.map { ($0.plainSlug, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            switch entry {
            case .klipy(let slug): bySlug[KlipyGIF.plain(slug)].map(GIF.klipy)
            case .file(let path): fileExists(path) ? .file(URL(fileURLWithPath: path)) : nil
            }
        }
    }
}

/// How ↩ puts a GIF in the app in front.
public enum GIFPaste: Equatable, Sendable {
    /// The file and its GIF data on the clipboard, then ⌘V: chat apps,
    /// mail, notes take it animated.
    case file
    /// `![title](link)` typed: a terminal or a code editor, where a file
    /// would land as a path or not at all.
    case markdown

    /// Terminals skil.li knows; editors come from `EditorProjects`.
    public static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "dev.warp.Warp",
        "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "com.raphaelamorim.rio"
    ]

    /// Markdown for a Klipy GIF in a terminal or an editor; a file
    /// everywhere else (a file on this Mac is always pasted as a file).
    public static func style(for gif: GIF, frontApp bundleID: String?, editors: Set<String>) -> GIFPaste {
        guard case .klipy = gif, let bundleID, terminals.contains(bundleID) || editors.contains(bundleID) else { return .file }
        return .markdown
    }
}
