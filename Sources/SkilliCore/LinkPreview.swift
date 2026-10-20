import Foundation

/// A page's social preview, as its own head says it: the Open Graph and
/// Twitter card tags (`og:title`, `twitter:image`…), else its `<title>`
/// and description, and its icons. Read by the clipboard history when a
/// copied link is shown (`LinkPreviews`), kept with the copy
/// (`LinkPreviewCache`).
public struct LinkPreview: Codable, Equatable, Sendable {
    public var title: String?
    /// The page's description.
    public var summary: String?
    public var siteName: String?
    public var imageURL: URL?
    /// Icons to try, best first; the site's /favicon.ico last.
    public var iconURLs: [URL]
    /// The link is a picture itself: the picture is the preview.
    public var isImage: Bool

    public init(title: String? = nil, summary: String? = nil, siteName: String? = nil, imageURL: URL? = nil,
                iconURLs: [URL] = [], isImage: Bool = false) {
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imageURL = imageURL
        self.iconURLs = iconURLs
        self.isImage = isImage
    }

    /// Nothing worth showing beyond the link itself.
    public var isEmpty: Bool {
        title == nil && summary == nil && imageURL == nil && !isImage
    }
}

/// The rules of a link preview: what is a link, what may be fetched, how
/// much is read, and the head's tags.
public enum LinkPreviews {
    /// Read of a page at most: its head is near the top.
    public static let headLimit = 512 * 1024
    /// A picture's bytes at most (the preview's image, a link to one).
    public static let imageLimit = 8 * 1024 * 1024
    /// An icon's bytes at most.
    public static let iconLimit = 512 * 1024
    /// Seconds for one request.
    public static let timeout: TimeInterval = 6
    /// Redirects followed at most, each to http(s) only.
    public static let redirectLimit = 5

    /// The URL when the whole copy is one web link: "https://…",
    /// "http://…" or "www.…" (read as https), one word; nil for anything
    /// else ("skil.li", a sentence holding a link, "mailto:", "file:").
    public static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 4_096, !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let lower = trimmed.lowercased()
        let candidate: String
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            candidate = trimmed
        } else if lower.hasPrefix("www."), trimmed.dropFirst(4).contains(".") {
            candidate = "https://" + trimmed
        } else {
            return nil
        }
        guard let url = URL(string: candidate) ?? URL(string: candidate.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(.urlQueryAllowed).union(CharacterSet(charactersIn: "#%"))) ?? ""),
              isFetchable(url) else { return nil }
        return url
    }

    /// http or https with a host, and no name or password in it (they
    /// would be sent).
    public static func isFetchable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return false }
        return url.user == nil && url.password == nil
    }

    /// "github.com" for "https://www.github.com/…".
    public static func domain(of url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The page's text: the charset its header or head names, else UTF-8
    /// (bad bytes replaced, never a failure).
    public static func decode(_ data: Data, contentType: String?) -> String {
        let named = charset(in: contentType) ?? charset(in: String(decoding: data.prefix(2_048), as: UTF8.self))
        if let named, named != "utf-8", named != "utf8" {
            let cf = CFStringConvertIANACharSetNameToEncoding(named as CFString)
            if cf != kCFStringEncodingInvalidId,
               let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) {
                return text
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// "charset=iso-8859-1" in a header or a meta tag, lowercased.
    static func charset(in text: String?) -> String? {
        guard let text, let range = text.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let rest = text[range.upperBound...].drop { $0 == "\"" || $0 == "'" }
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return name.isEmpty ? nil : name.lowercased()
    }

    /// Whether `data` already holds the end of the head: no need to read on.
    public static func headEnded(_ data: Data) -> Bool {
        let tail = data.suffix(8_192)
        let text = String(decoding: tail, as: UTF8.self).lowercased()
        return text.contains("</head") || text.contains("<body")
    }

    // MARK: - The head

    /// The preview a page's head gives, its addresses resolved against
    /// `base` (the page's address after redirects, or its `<base>`).
    public static func parse(html: String, base: URL) -> LinkPreview {
        var meta: [String: String] = [:]
        var title: String?
        var baseURL = base
        var icons: [(url: URL, rank: Int)] = []
        var imageSource: String?

        var scanner = HeadScanner(html)
        while let tag = scanner.next() {
            switch tag.name {
            case "meta":
                guard let content = tag.attributes["content"].map(clean), !content.isEmpty else { continue }
                for key in ["property", "name", "itemprop"] {
                    if let name = tag.attributes[key]?.lowercased(), meta[name] == nil { meta[name] = content }
                }
            case "title":
                if title == nil, let text = tag.text.map(clean), !text.isEmpty { title = text }
            case "base":
                if let href = tag.attributes["href"], let url = resolve(href, base) { baseURL = url }
            case "link":
                guard let href = tag.attributes["href"] else { continue }
                let rel = Set((tag.attributes["rel"] ?? "").lowercased().split(separator: " ").map(String.init))
                if rel.contains("image_src") { imageSource = imageSource ?? href }
                guard let rank = iconRank(rel: rel, href: href, type: tag.attributes["type"], sizes: tag.attributes["sizes"]),
                      let url = resolve(href, baseURL) else { continue }
                icons.append((url, rank))
            default:
                break
            }
        }

        func first(_ keys: [String]) -> String? {
            keys.lazy.compactMap { meta[$0] }.first { !$0.isEmpty }
        }
        let image = first(["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src", "image"]) ?? imageSource
        var iconURLs = icons.sorted { $0.rank > $1.rank }.map(\.url)
        if let scheme = baseURL.scheme, let host = baseURL.host(),
           let fallback = URL(string: "\(scheme)://\(host)\(baseURL.port.map { ":\($0)" } ?? "")/favicon.ico"),
           !iconURLs.contains(fallback) {
            iconURLs.append(fallback)
        }
        return LinkPreview(
            title: (first(["og:title", "twitter:title"]) ?? title ?? first(["title"])).map { cap($0, 300) },
            summary: first(["og:description", "twitter:description", "description"]).map { cap($0, 600) },
            siteName: first(["og:site_name", "application-name", "apple-mobile-web-app-title"]).map { cap($0, 80) },
            imageURL: image.flatMap { resolve($0, baseURL) },
            iconURLs: Array(iconURLs.prefix(4)))
    }

    /// How good an icon is to show at 16–32 pt: Apple's touch icon (180
    /// px), then a large PNG, then any; SVG last (not every Mac draws it).
    static func iconRank(rel: Set<String>, href: String, type: String?, sizes: String?) -> Int? {
        let touch = rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed")
        guard touch || rel.contains("icon") else { return nil }
        if type?.lowercased().contains("svg") == true || href.lowercased().hasSuffix(".svg") { return 1 }
        let side = sizes?.lowercased().split(separator: "x").first.flatMap { Int($0) } ?? 0
        if touch { return 300 + min(side, 256) }
        return 100 + min(side, 256)
    }

    /// `href` against `base`; http(s) only.
    static func resolve(_ href: String, _ base: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("data:") else { return nil }
        let url = URL(string: trimmed, relativeTo: base) ?? URL(string: trimmed.replacingOccurrences(of: " ", with: "%20"), relativeTo: base)
        guard let absolute = url?.absoluteURL, isFetchable(absolute) else { return nil }
        return absolute
    }

    /// Entities decoded, runs of spaces made one.
    static func clean(_ text: String) -> String {
        HTMLEntities.decode(text).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func cap(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}

/// A pass over an HTML document's head, tag by tag, on its UTF-8 bytes
/// (tags are ASCII): comments, scripts and styles skipped, attributes in
/// any quoting, stopped at `</head>` or `<body>`.
struct HeadScanner {
    struct Tag {
        let name: String
        let attributes: [String: String]
        /// For `<title>`: what is between it and `</title>`.
        let text: String?
    }

    private let bytes: [UInt8]
    private var index = 0

    init(_ html: String) {
        bytes = Array(html.utf8.prefix(LinkPreviews.headLimit))
    }

    private static let lt = UInt8(ascii: "<"), gt = UInt8(ascii: ">"), slash = UInt8(ascii: "/")
    private static let equal = UInt8(ascii: "="), quote = UInt8(ascii: "\""), apostrophe = UInt8(ascii: "'")

    mutating func next() -> Tag? {
        while index < bytes.count {
            guard bytes[index] == Self.lt else {
                index += 1
                continue
            }
            if starts(with: "<!--") {
                skip(past: "-->")
                continue
            }
            index += 1
            let closing = index < bytes.count && bytes[index] == Self.slash
            if closing { index += 1 }
            let name = readName()
            guard !name.isEmpty else { continue }
            if closing {
                if name == "head" { index = bytes.count }
                skip(past: ">")
                continue
            }
            let attributes = readAttributes()
            switch name {
            case "body":
                index = bytes.count
                return nil
            case "script", "style", "noscript", "template":
                skip(past: "</\(name)")
                skip(past: ">")
            case "title":
                let start = index
                let end = find("</title") ?? bytes.count
                index = end
                skip(past: ">")
                return Tag(name: name, attributes: attributes, text: String(decoding: bytes[start..<end], as: UTF8.self))
            default:
                return Tag(name: name, attributes: attributes, text: nil)
            }
        }
        return nil
    }

    private static func lower(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte + 32 : byte
    }

    private func starts(with text: String, at position: Int? = nil) -> Bool {
        var position = position ?? index
        for byte in text.utf8 {
            guard position < bytes.count, Self.lower(bytes[position]) == Self.lower(byte) else { return false }
            position += 1
        }
        return true
    }

    /// Where `text` (case ignored) starts next, from here.
    private func find(_ text: String) -> Int? {
        guard let first = text.utf8.first.map(Self.lower) else { return nil }
        var position = index
        while position < bytes.count {
            if Self.lower(bytes[position]) == first, starts(with: text, at: position) { return position }
            position += 1
        }
        return nil
    }

    /// Moves past the next `text` (case ignored), or to the end.
    private mutating func skip(past text: String) {
        index = find(text).map { $0 + text.utf8.count } ?? bytes.count
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) || (byte >= 48 && byte <= 57)
            || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "!")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12
    }

    private mutating func readName() -> String {
        let start = index
        while index < bytes.count, Self.isNameByte(bytes[index]) { index += 1 }
        return String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
    }

    /// Up to the tag's ">", names lowercased.
    private mutating func readAttributes() -> [String: String] {
        var attributes: [String: String] = [:]
        while index < bytes.count {
            while index < bytes.count, Self.isSpace(bytes[index]) || bytes[index] == Self.slash { index += 1 }
            guard index < bytes.count, bytes[index] != Self.gt else {
                index += 1
                break
            }
            let nameStart = index
            while index < bytes.count, !Self.isSpace(bytes[index]), bytes[index] != Self.equal, bytes[index] != Self.gt,
                  bytes[index] != Self.slash {
                index += 1
            }
            let name = String(decoding: bytes[nameStart..<index], as: UTF8.self).lowercased()
            while index < bytes.count, Self.isSpace(bytes[index]) { index += 1 }
            var value = ""
            if index < bytes.count, bytes[index] == Self.equal {
                index += 1
                while index < bytes.count, Self.isSpace(bytes[index]) { index += 1 }
                if index < bytes.count, bytes[index] == Self.quote || bytes[index] == Self.apostrophe {
                    let mark = bytes[index]
                    index += 1
                    let start = index
                    while index < bytes.count, bytes[index] != mark { index += 1 }
                    value = String(decoding: bytes[start..<min(index, bytes.count)], as: UTF8.self)
                    index += 1
                } else {
                    let start = index
                    while index < bytes.count, !Self.isSpace(bytes[index]), bytes[index] != Self.gt { index += 1 }
                    value = String(decoding: bytes[start..<index], as: UTF8.self)
                }
            }
            if name.isEmpty {
                index += 1
            } else if attributes[name] == nil {
                attributes[name] = value
            }
        }
        return attributes
    }
}

/// HTML's entities in titles and descriptions: numeric ones, and the
/// named ones pages use in text.
enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "laquo": "«", "raquo": "»", "middot": "·", "bull": "•", "copy": "©", "reg": "®", "trade": "™",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "agrave": "à", "acirc": "â", "ccedil": "ç", "ocirc": "ô",
        "ucirc": "û", "ugrave": "ù", "icirc": "î", "iuml": "ï", "euml": "ë", "ouml": "ö", "uuml": "ü", "auml": "ä",
        "szlig": "ß", "ntilde": "ñ", "aacute": "á", "iacute": "í", "oacute": "ó", "uacute": "ú", "euro": "€"
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            guard let semicolon = after.prefix(12).firstIndex(of: ";") else {
                result += "&"
                rest = after
                continue
            }
            let name = String(after[..<semicolon])
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = named[name] ?? named[name.lowercased()]
            }
            if let decoded {
                result += decoded
                rest = after[after.index(after: semicolon)...]
            } else {
                result += "&"
                rest = after
            }
        }
        return result + rest
    }
}

// MARK: - Kept with the copy

/// A link's preview as kept on disk beside its copy: what was fetched,
/// when, and the picture and icon saved with it.
public struct LinkPreviewRecord: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// The page answered: `preview` holds what it said (maybe nothing).
        case found
        /// No answer (offline, a timeout, an error): tried again soon.
        case failed
    }

    /// The link as copied.
    public var url: URL
    public var fetched: Date
    public var outcome: Outcome
    public var preview: LinkPreview?
    /// File names in the cache folder.
    public var image: String?
    public var icon: String?

    public init(url: URL, fetched: Date, outcome: Outcome, preview: LinkPreview? = nil, image: String? = nil, icon: String? = nil) {
        self.url = url
        self.fetched = fetched
        self.outcome = outcome
        self.preview = preview
        self.image = image
        self.icon = icon
    }
}

/// Where previews are kept and when one is read again: files named by the
/// copy's id in the history's own folder (removed with the copy), a page
/// read again after a week, a failure tried again after ten minutes, and
/// only while it is shown.
public enum LinkPreviewCache {
    public static let refreshAfter: TimeInterval = 7 * 86_400
    public static let retryAfter: TimeInterval = 10 * 60

    /// Whether to read the page now, shown with `record` kept.
    public static func needsFetch(_ record: LinkPreviewRecord?, for url: URL, now: Date) -> Bool {
        guard let record, record.url == url else { return true }
        let age = now.timeIntervalSince(record.fetched)
        // A clock put back: read again.
        guard age >= 0 else { return true }
        switch record.outcome {
        case .found: return age >= refreshAfter
        case .failed: return age >= retryAfter
        }
    }

    public static func recordName(_ id: Int64) -> String { "\(id).json" }
    public static func imageName(_ id: Int64) -> String { "\(id).image.jpg" }
    public static func iconName(_ id: Int64) -> String { "\(id).icon.png" }

    /// Every file a copy's preview may have.
    public static func files(of id: Int64) -> [String] {
        [recordName(id), imageName(id), iconName(id)]
    }

    /// The copy a file belongs to; nil for any other file.
    public static func id(ofFile name: String) -> Int64? {
        let parts = name.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let id = Int64(parts[0]), id > 0, files(of: id).contains(name) else { return nil }
        return id
    }

    /// The files of copies the history no longer holds; others' files
    /// are left alone.
    public static func orphans(among names: [String], kept ids: Set<Int64>) -> [String] {
        names.filter { name in id(ofFile: name).map { !ids.contains($0) } ?? false }
    }
}
