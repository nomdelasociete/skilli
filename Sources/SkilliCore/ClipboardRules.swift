import Foundation

/// How long the clipboard history keeps what was copied (pinned items stay).
public enum ClipboardRetention: Equatable, Hashable, Sendable {
    case day
    case week
    case month
    case unlimited
    case days(Int)

    /// What Settings stores: "day", "week", "month", "unlimited", "days:10".
    public var rawValue: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .unlimited: "unlimited"
        case .days(let days): "days:\(days)"
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "day": self = .day
        case "week": self = .week
        case "month": self = .month
        case "unlimited": self = .unlimited
        default:
            if rawValue.hasPrefix("days:"), let days = Int(rawValue.dropFirst(5)), days > 0 {
                self = .days(days)
            } else {
                self = .month
            }
        }
    }

    public var days: Int? {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .unlimited: nil
        case .days(let days): days
        }
    }

    /// Items copied before this date go; nil keeps everything.
    public func cutoff(now: Date = .now) -> Date? {
        days.map { now.addingTimeInterval(-Double($0) * 86_400) }
    }

    /// Custom, from this choice's days (a week: 7 days), so picking Custom
    /// keeps what was kept; from Unlimited, a year.
    public var asCustom: ClipboardRetention {
        .days(days ?? 365)
    }

    /// How long, in a sentence: "a week", "10 days"; nil for Unlimited.
    public var spoken: String? {
        switch self {
        case .day, .days(1): "a day"
        case .week: "a week"
        case .month: "a month"
        case .unlimited: nil
        case .days(let days): "\(days) days"
        }
    }

    /// Under Keep copies for, before the hourly pass removes them: "812
    /// copies are older than a week: they go within the hour." Nil when
    /// none would go.
    public func removalLine(older count: Int) -> String? {
        guard count > 0, let spoken else { return nil }
        return count == 1
            ? "1 copy is older than \(spoken): it goes within the hour."
            : "\(count) copies are older than \(spoken): they go within the hour."
    }
}

/// Turns what the user types into an SQLite FTS5 query: every word as a
/// prefix, all of them required; quotes and operators cannot break it.
public enum ClipboardSearch {
    /// What follows "cb " / "clipboard " / "presse-papier " in the
    /// launcher (`LauncherPrefix`), or nil when the text does not ask for
    /// the history.
    public static func modeFilter(_ text: String) -> String? {
        LauncherPrefix.rest(of: text, after: LauncherPrefix.prefixes(for: .clipboardHistory))?.trimmingCharacters(in: .whitespaces)
    }

    /// A row's title: the first line with text, spaces collapsed.
    public static func title(of text: String, limit: Int = 200) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    /// Lines of text after the first, for "+12 lines".
    public static func extraLines(in text: String) -> Int {
        max(0, text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }.count - 1)
    }

    /// The query for the trigram index (`items_sub`): every word as it is
    /// typed, found inside words too, all of them required. Nil when a
    /// word is under 3 characters (a trigram cannot find it): the search
    /// is then `ftsQuery`'s.
    public static func substringQuery(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(8)
        guard !words.isEmpty, words.allSatisfy({ $0.unicodeScalars.count >= 3 }) else { return nil }
        return words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " ")
    }

    /// Where each word typed is in `text`, accents and case ignored, in
    /// the order found, `limit` at most: what the preview marks.
    public static func ranges(of words: String, in text: String, limit: Int = 200) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for word in words.split(whereSeparator: \.isWhitespace).prefix(8) {
            var from = text.startIndex
            while found.count < limit, let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
                found.append(range)
                from = range.upperBound
            }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// A found copy's title when its first line does not hold the first
    /// word typed: the line that does, from a few words before it
    /// ("…the invoice for October"). Nil when the first line holds it, or
    /// nothing does in the first 100,000 characters.
    public static func found(_ words: String, in text: String, limit: Int = 200) -> String? {
        guard let word = words.split(whereSeparator: \.isWhitespace).first else { return nil }
        let head = text.prefix(100_000)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let match = head.range(of: word, options: options) else { return nil }
        if title(of: text, limit: limit).range(of: word, options: options) != nil { return nil }
        let lineStart = head[..<match.lowerBound].lastIndex(where: \.isNewline).map { head.index(after: $0) } ?? head.startIndex
        let lineEnd = head[match.upperBound...].firstIndex(where: \.isNewline) ?? head.endIndex
        // At most 24 characters before the word, from a word's start.
        var start = lineStart
        let before = head[lineStart..<match.lowerBound]
        if before.count > 24 {
            let near = before.index(before.endIndex, offsetBy: -24)
            start = before[near...].firstIndex(where: \.isWhitespace).map { before.index(after: $0) } ?? near
        }
        let line = head[start..<lineEnd].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let cut = line.count > limit ? String(line.prefix(limit)) + "…" : line
        return start == lineStart ? cut : "…" + cut
    }

    public static func ftsQuery(_ text: String) -> String? {
        let words = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}

/// When a copy was made, as the history's list says it
/// (docs/clipboard-rows-and-search.md).
public enum ClipboardDay {
    /// At a row's right edge: "14:32" today, "Mon" the six days before,
    /// "3 Nov" before that, "3 Nov 2025" in another year.
    public static func short(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let days = daysAgo(date, now: now, calendar: calendar)
        if days <= 0 {
            style = style.hour().minute()
        } else if days < 7 {
            style = style.weekday(.abbreviated)
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            style = style.day().month(.abbreviated)
        } else {
            style = style.day().month(.abbreviated).year()
        }
        return date.formatted(style)
    }

    /// Over the list, for the row at its top: "Copied today", "Copied
    /// yesterday", "Copied Monday", "Copied 3 November", "Copied 3
    /// November 2025".
    public static func header(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let days = daysAgo(date, now: now, calendar: calendar)
        if days <= 0 { return "Copied today" }
        if days == 1 { return "Copied yesterday" }
        if days < 7 {
            style = style.weekday(.wide)
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            style = style.day().month(.wide)
        } else {
            style = style.day().month(.wide).year()
        }
        return "Copied " + date.formatted(style)
    }

    /// Whole days between the two dates' days; 0 for today (and for a
    /// date after now).
    static func daysAgo(_ date: Date, now: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)
    }
}

/// What a copy is, to show one kind at a time in the history (⌘K →
/// Show Only Links: docs/clipboard-pins-filter-actions.md). The same
/// reading as the preview's (`CopiedValue`), kept with the copy.
public enum ClipboardKind: String, CaseIterable, Sendable {
    case image, file, link, color, email, phone, address, code, text

    /// "Show Only Links", "Clipboard · Links".
    public var plural: String {
        switch self {
        case .image: "Images"
        case .file: "Files"
        case .link: "Links"
        case .color: "Colors"
        case .email: "Email Addresses"
        case .phone: "Phone Numbers"
        case .address: "Addresses"
        case .code: "Code"
        case .text: "Text"
        }
    }

    /// `stored`: how the history keeps it ("text", "image", "files": the
    /// files' paths in `text`, one a line). A picture copied as its file
    /// is an image, as everywhere else in the history.
    public static func of(stored: String, text: String) -> ClipboardKind {
        switch stored {
        case "image": return .image
        case "files": return CopiedPicture.path(in: text) != nil ? .image : .file
        default:
            switch CopiedValue.read(text) {
            case .text: return .text
            case .link: return .link
            case .color: return .color
            case .email: return .email
            case .phone: return .phone
            case .address: return .address
            case .code: return .code
            }
        }
    }
}

/// A copy that is one file, and that file a picture (a screenshot copied
/// in Finder or by a capture app): read and offered as an image copied as
/// an image is (docs/clipboard-text-selection.md).
public enum CopiedPicture {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp"]

    /// The file's path when `files` (a files copy's text: paths, one a
    /// line) is one picture; nil for several files or another kind.
    public static func path(in files: String) -> String? {
        let paths = files.split(whereSeparator: \.isNewline)
        guard paths.count == 1, let path = paths.first.map(String.init) else { return nil }
        let name = path.split(separator: "/").last.map(String.init) ?? ""
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        return extensions.contains(name[name.index(after: dot)...].lowercased()) ? path : nil
    }
}

/// What the clipboard history never keeps.
public enum ClipboardPolicy {
    /// nspasteboard.org markers: secrets from password managers, and
    /// writes an app makes for itself (skil.li's own paste included).
    public static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword"
    ]

    /// Password managers and Keychain Access, ignored out of the box.
    public static let defaultExcludedApps = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass"
    ]

    /// The password managers' names, for the lists where they are not
    /// installed (no app to read the name from).
    public static let knownNames: [String: String] = [
        "com.apple.Passwords": "Passwords",
        "com.apple.keychainaccess": "Keychain Access",
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "com.dashlane.dashlanephonefinal": "Dashlane",
        "com.lastpass.LastPass": "LastPass"
    ]

    /// Whether a copy is kept: not marked secret or transient, not from an
    /// excluded app.
    public static func shouldRecord(types: [String], app: String?, excluded: Set<String>) -> Bool {
        guard !types.isEmpty, types.allSatisfy({ !ignoredTypes.contains($0) }) else { return false }
        if let app, excluded.contains(app) { return false }
        return true
    }
}

/// Paste in Sequence: each run pastes the next older copy, the newest
/// first, from the history as it was when the sequence began. A pause of
/// 30 s, or anything copied after skil.li's own paste, starts again from
/// the newest.
public struct PasteSequence: Sendable {
    /// How long a sequence waits for the next run.
    public static let pause: TimeInterval = 30
    /// How many copies one sequence goes through.
    public static let length = 50

    /// The copies in order, newest first, as the sequence began.
    public private(set) var ids: [Int64] = []
    /// The one pasted last; -1 before the first.
    public private(set) var position = -1
    private var last: Date?
    private var changeCount: Int?

    public init() {}

    /// The copy to paste now: the newest when a sequence begins (`newest`
    /// gives the history's ids, newest first), else the next older. Nil
    /// past the oldest one.
    public mutating func next(now: Date, changeCount: Int, newest: () -> [Int64]) -> Int64? {
        let goesOn = last.map { now.timeIntervalSince($0) <= Self.pause } == true && self.changeCount == changeCount
        if goesOn {
            position = min(position + 1, ids.count)
        } else {
            ids = Array(newest().prefix(Self.length))
            position = 0
            self.changeCount = nil
        }
        last = now
        guard ids.indices.contains(position) else {
            // Past the oldest: the next run begins again.
            self.changeCount = nil
            return nil
        }
        return ids[position]
    }

    /// The clipboard's change count once skil.li put the copy on it: a
    /// change after that is the user's own copy.
    public mutating func wrote(changeCount: Int) {
        self.changeCount = changeCount
    }
}

/// What makes an image a screenshot when macOS did not mark it so
/// (`kMDItemIsScreenCapture`): its name, as macOS and CleanShot X write it.
public enum ScreenshotName {
    static let starts = ["screenshot", "screen shot", "capture d’écran", "capture d'écran", "cleanshot", "bildschirmfoto",
                         "captura de pantalla", "schermafbeelding", "istantanea"]

    public static func looksLikeScreenshot(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return starts.contains { lower.hasPrefix($0) } || lower.contains("_screenshot")
    }
}

/// A copy that is a key or a token by its shape: never kept while
/// Settings → Clipboard → Never keep keys and tokens is on. Only shapes
/// that say what they are (a prefix its issuer documents, a JWT's three
/// parts, a private key's header): a hash, a UUID or a long random word
/// is kept, since nothing tells it from what the user wants back.
public enum ClipboardSecret {
    /// The whole copy is one such word (spaces around it aside), or holds
    /// a private key. What it looks like, to say so ("a GitHub token");
    /// nil for anything else.
    public static func name(of text: String) -> String? {
        // A private key is several lines, often with a certificate:
        // anywhere in the copy, whatever its length (a long copy is read
        // off the main thread, `ClipboardHistory.look`).
        // Literal: Foundation's search. On 1.6 MB of text the whole check
        // adds 21 ms off the main thread (33 with `contains`), measured
        // 2026-11-11.
        if text.range(of: "PRIVATE KEY-----", options: .literal) != nil, text.range(of: "-----BEGIN ", options: .literal) != nil {
            return "a private key"
        }
        // The word between the spaces around it, without copying a long
        // text to trim it.
        let spaces = CharacterSet.whitespacesAndNewlines
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !spaces.contains($0) }),
              let last = scalars.lastIndex(where: { !spaces.contains($0) }) else { return nil }
        let inner = scalars[first...last]
        // At most 8,192 characters looked at: longer is no key.
        guard inner.prefix(8_193).count <= 8_192, !inner.contains(where: { spaces.contains($0) }) else { return nil }
        let word = String(inner)
        let length = word.utf16.count
        guard length >= 20 else { return nil }
        let range = NSRange(location: 0, length: length)
        return shapes.first { $0.pattern.firstMatch(in: word, range: range) != nil }?.name
    }

    private struct Shape: Sendable {
        let name: String
        let pattern: NSRegularExpression
    }

    private static func shape(_ name: String, _ pattern: String) -> Shape {
        Shape(name: name, pattern: try! NSRegularExpression(pattern: "^(?:\(pattern))$"))
    }

    // Built once; NSRegularExpression is immutable and Sendable.
    private static let shapes: [Shape] = [
        shape("a GitHub token", #"gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,}"#),
        shape("a GitLab token", #"glpat-[A-Za-z0-9_-]{20,}"#),
        shape("a Stripe key", #"[sr]k_(?:live|test)_[A-Za-z0-9]{16,}"#),
        shape("an API key", #"sk-[A-Za-z0-9_-]{20,}"#),
        shape("an AWS access key", #"(?:AKIA|ASIA)[A-Z0-9]{16}"#),
        shape("a Slack token", #"xox[abeprs]-[A-Za-z0-9-]{16,}"#),
        shape("a Google API key", #"AIza[A-Za-z0-9_-]{35}"#),
        shape("an npm token", #"npm_[A-Za-z0-9]{36}"#),
        shape("a sign-in token", #"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#)
    ]
}

/// A copy the history did not keep, and why: said once when the history
/// opens next, so a copy looked for and not there is never a riddle.
/// Never what was copied: its kind, the app, when.
public struct ClipboardNotKept: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// A key or a token by its shape (`ClipboardSecret.name`).
        case secret(String)
        /// A text over `ClipboardPolicy.textLimit` bytes.
        case longText
        /// A picture over `ClipboardPolicy.pictureLimit` bytes.
        case bigPicture
    }

    public let reason: Reason
    public let appName: String?
    public let date: Date

    public init(reason: Reason, appName: String?, date: Date) {
        self.reason = reason
        self.appName = appName
        self.date = date
    }

    /// Said for a day: after it, "at 14:02" names no day.
    public func isRecent(now: Date) -> Bool { now.timeIntervalSince(date) < 86_400 }

    /// One line for the launcher's footer: what, from where, when, and
    /// what to do about it where something can be done.
    public func line(time: String) -> String {
        let from = appName.map { "\($0), \(time)" } ?? time
        switch reason {
        case .secret(let name):
            return "Not kept: looks like \(name) (\(from)). To keep them: Settings → Clipboard → Advanced."
        case .longText:
            return "Not kept: a text over \(ClipboardPolicy.textLimit / 1_000_000) MB (\(from))."
        case .bigPicture:
            return "Not kept: a picture over \(ClipboardPolicy.pictureLimit / 1_000_000) MB (\(from))."
        }
    }
}

extension ClipboardPolicy {
    /// A text copy is kept up to this many bytes (UTF-8).
    public static let textLimit = 5_000_000
    /// A picture copy is kept up to this many bytes, as copied.
    public static let pictureLimit = 40_000_000
}
