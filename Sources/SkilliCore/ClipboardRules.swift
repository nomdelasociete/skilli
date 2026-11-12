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
/// the newest. Begun on copies selected in the history (`begin`), it
/// goes through those instead, in the order given (the order copied),
/// under the same two rules.
public struct PasteSequence: Sendable {
    /// How long a sequence waits for the next run.
    public static let pause: TimeInterval = 30
    /// How many copies one sequence goes through.
    public static let length = 50

    /// The copies in the order they paste, as the sequence began: newest
    /// first, or the selected ones as given.
    public private(set) var ids: [Int64] = []
    /// The sequence under way goes through copies the user selected.
    public private(set) var chosen = false
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
            chosen = false
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

    /// A sequence on the copies selected in the history, in the order
    /// they paste: the first one now, each `next` the one after. Nil for
    /// none.
    public mutating func begin(with ids: [Int64], now: Date) -> Int64? {
        self.ids = Array(ids.prefix(Self.length))
        position = 0
        chosen = true
        last = now
        changeCount = nil
        return self.ids.first
    }

    /// Said past the last copy of the sequence.
    public var end: String {
        guard chosen else { return "That was the oldest copy. Again starts from the newest." }
        return ids.count == 1 ? "That was the only copy selected." : "That was the last of the \(ids.count) selected."
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

    /// A longer copy that holds such a word among others (a whole `.env`,
    /// a `curl` line with its header, a sentence giving a token), or a
    /// sign-in header with its value: what it holds, to say so. Nil for
    /// anything else, and for a text that only names a key's start.
    /// One pass over the text for every shape: 100,000 characters with no
    /// key take 4 ms in a debug build (`ClipboardRulesTests`, 2026-11-12);
    /// a longer copy is read off the main thread.
    public static func held(in text: String) -> String? {
        let all = NSRange(location: 0, length: text.utf16.count)
        guard all.length >= 20, let match = inside.firstMatch(in: text, range: all), let found = Range(match.range, in: text) else { return nil }
        // A header's value may itself be a key with a name: said by it.
        let word = text[found].split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let range = NSRange(location: 0, length: word.utf16.count)
        return shapes.first { $0.pattern.firstMatch(in: word, range: range) != nil }?.name ?? "a sign-in header"
    }

    private struct Shape: Sendable {
        let name: String
        let pattern: NSRegularExpression
        let source: String
    }

    /// What a key is made of: a shape inside a text starts and ends where
    /// none of these is.
    private static let wordCharacters = "A-Za-z0-9_-"

    /// Every shape at once, each a whole word of the text. `sk-` alone
    /// starts many words that are no key (a class name, a slug): inside
    /// a text it counts with a digit and a capital in it, or ending in
    /// 32 or more hexadecimal characters ("sk-or-v1-" and 64). A header's
    /// value counts with a digit in it: "Bearer YOUR_TOKEN_GOES_HERE" is
    /// kept.
    private static let inside: NSRegularExpression = {
        let named = shapes.map { $0.name == "an API key" ? #"sk-(?=[A-Za-z0-9_-]*[0-9])(?=[A-Za-z0-9_-]*[A-Z])[A-Za-z0-9_-]{20,}|sk-(?:[a-z0-9]+-)*(?=[a-f0-9]*[0-9])[a-f0-9]{32,}"# : $0.source }
        let words = "(?<![.\(wordCharacters)])(?:\(named.joined(separator: "|")))(?![\(wordCharacters)])"
        return try! NSRegularExpression(pattern: words + "|" + header)
    }()

    private static let header = #"(?i:Authorization)["']?\s*[:=]\s*["']?(?i:Bearer|Basic|Token)\s+(?=[A-Za-z0-9._~+/=-]*[0-9])[A-Za-z0-9._~+/=-]{20,}"#

    private static func shape(_ name: String, _ pattern: String) -> Shape {
        Shape(name: name, pattern: try! NSRegularExpression(pattern: "^(?:\(pattern))$"), source: pattern)
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
        /// A longer text that holds one (`ClipboardSecret.held`).
        case holdsSecret(String)
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
        case .holdsSecret(let name):
            return "Not kept: it holds \(name) (\(from)). To keep them: Settings → Clipboard → Advanced."
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

/// Files copied a while ago and moved or deleted since: what is said
/// when one is pasted (docs/clipboard-missing-files.md). The history
/// keeps their paths, not the files.
public enum ClipboardFiles {
    /// `gone`: the names no longer where they were copied, of `total`
    /// in the copy. Nil when all are there. `done`: "pasted" or "copied",
    /// what was done with the others.
    public static func line(gone: [String], of total: Int, done: String) -> String? {
        guard let first = gone.first else { return nil }
        let others = total - gone.count
        if others <= 0 {
            return gone.count == 1
                ? "“\(first)” is no longer where it was copied: ⇧↩ pastes its path."
                : "These \(gone.count) files are no longer where they were copied: ⇧↩ pastes their paths."
        }
        let rest = others == 1 ? "the other was \(done)" : "the \(others) others were \(done)"
        return gone.count == 1 ? "“\(first)” is no longer there: \(rest)." : "\(gone.count) of \(total) files are no longer there: \(rest)."
    }

    /// The several-files preview's first line: "5 Files", "5 Files · 2 no
    /// longer there".
    public static func count(_ total: Int, gone: Int) -> String {
        gone == 0 ? "\(total) Files" : gone == total ? "\(total) Files · no longer there" : "\(total) Files · \(gone) no longer there"
    }
}

/// Several copies selected in the history and used as one
/// (docs/clipboard-select-several.md): the order they go in, and what
/// one paste can be made of.
public enum ClipboardSelection {
    /// At most this many copies selected: a sequence's length.
    public static let limit = PasteSequence.length

    /// What a selected copy is, for joining.
    public enum Family: Equatable, Sendable {
        case text, files, image
    }

    /// One selected copy: its id, when it was copied, what it is, its
    /// text (a files copy's paths, one a line).
    public struct Copy: Equatable, Sendable {
        public let id: Int64
        public let copied: Date
        public let family: Family
        public let text: String

        public init(id: Int64, copied: Date, family: Family, text: String) {
            self.id = id
            self.copied = copied
            self.family = family
            self.text = text
        }
    }

    /// What the selection puts on the clipboard.
    public enum Paste: Equatable, Sendable {
        /// Texts: one text, a line each.
        case text(String)
        /// Files: all their paths.
        case files([String])
        /// Texts and files together, or an image: no single paste.
        case none
    }

    /// The order copied, oldest first, whatever the order selected; two
    /// copied at the same instant by their ids.
    public static func ordered(_ copies: [Copy]) -> [Copy] {
        copies.sorted { ($0.copied, $0.id) < ($1.copied, $1.id) }
    }

    /// The selection as one paste, in the order copied.
    public static func paste(_ copies: [Copy]) -> Paste {
        let copies = ordered(copies)
        guard let first = copies.first, copies.allSatisfy({ $0.family == first.family }) else { return .none }
        switch first.family {
        case .text: return .text(copies.map(\.text).joined(separator: "\n"))
        case .files: return .files(copies.flatMap { $0.text.split(separator: "\n").map(String.init) })
        case .image: return .none
        }
    }

    /// Said when the selection makes no single paste.
    public static let noSinglePaste = "These copies do not make one paste: only texts together, or files together. ⌘K → Paste in Sequence pastes them one key each."

    /// The chip beside the search field: "Clipboard · 3 selected", after
    /// the filter when there is one ("Clipboard · Links · 3 selected").
    public static func chip(filter: String?, selected: Int) -> String {
        (["Clipboard"] + [filter].compactMap { $0 } + (selected > 0 ? ["\(selected) selected"] : [])).joined(separator: " · ")
    }
}

/// What a copy is kept with beside its text or its picture: every format
/// the app put there (cells, a slide's object, a web archive), so it
/// pastes back as it was copied. Bounded in size; what the copy already
/// is (its plain text, its picture) and what only marks the clipboard
/// are left out.
public enum ClipboardFormats {
    /// One format as the app gave it.
    public struct Format: Sendable, Equatable {
        public var type: String
        public var data: Data

        public init(type: String, data: Data) {
            self.type = type
            self.data = data
        }
    }

    /// All of a copy's formats together stay under this: one that does
    /// not fit is left out, the next smaller ones kept.
    public static let limit = 4_000_000

    /// Reading asks the app copied from for each format: past this long
    /// in all, the rest is left out (the main thread is the one waiting).
    public static let readBudget: Duration = .milliseconds(50)

    /// The copy's text under its other names: kept once, as the text.
    static let plainText: Set<String> = [
        "public.utf8-plain-text", "public.utf16-external-plain-text", "public.utf16-plain-text",
        "public.plain-text", "public.text", "NSStringPboardType", "com.apple.traditional-mac-plain-text"
    ]

    /// A picture of the copy: kept once, as a PNG, when the copy is a
    /// picture; beside a text (the cells drawn), not kept, as before.
    static let pictures: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "public.heic", "NeXT TIFF v4.0 pasteboard type", "com.apple.icns"
    ]

    /// Marks an app leaves for itself or for macOS, and files promised
    /// (written only when dropped somewhere): nothing to paste back.
    static let markers: [String] = [
        "org.nspasteboard.", "com.apple.is-remote-clipboard", "org.chromium.internal.", "com.apple.pasteboard.promised",
        "com.apple.NSFilePromise", "NSPromiseContentsPboardType", "Apple files promise pasteboard type"
    ]

    /// Whether a format is kept beside the copy.
    public static func keeps(_ type: String) -> Bool {
        !plainText.contains(type) && !pictures.contains(type) && !markers.contains { type.hasPrefix($0) }
    }

    /// The formats as one value to store, in their order; nil for none.
    public static func encoded(_ formats: [Format]) -> Data? {
        guard !formats.isEmpty else { return nil }
        let list: [Any] = formats.flatMap { [$0.type, $0.data] as [Any] }
        return try? PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0)
    }

    /// What `encoded` stored. A copy of before (RTF, RTFD and HTML by
    /// name, no order kept) reads in that order.
    public static func decoded(_ data: Data) -> [Format] {
        guard let list = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [] }
        if let before = list as? [String: Data] {
            let order = ["public.rtf", "com.apple.flat-rtfd", "public.html"]
            return before.sorted { (order.firstIndex(of: $0.key) ?? order.count, $0.key) < (order.firstIndex(of: $1.key) ?? order.count, $1.key) }
                .map { Format(type: $0.key, data: $0.value) }
        }
        guard let pairs = list as? [Any], pairs.count.isMultiple(of: 2) else { return [] }
        return stride(from: 0, to: pairs.count, by: 2).compactMap { index in
            guard let type = pairs[index] as? String, let data = pairs[index + 1] as? Data else { return nil }
            return Format(type: type, data: data)
        }
    }
}

/// What a copy gives when dragged out of the history into another app.
public enum ClipboardDrag: Equatable, Sendable {
    /// A text copy: its text.
    case text(String)
    /// A picture copy: its file.
    case picture
    /// A files copy of one file: that file, at this path.
    case file(String)
    /// Nothing to drag: several files copied together.
    case none

    /// `kind`: "text", "image" or "files", as the history keeps it;
    /// `text`: the copy's text, or its paths one per line.
    public static func of(kind: String, text: String) -> ClipboardDrag {
        switch kind {
        case "text":
            return text.isEmpty ? .none : .text(text)
        case "image":
            return .picture
        case "files":
            let paths = text.split(separator: "\n", omittingEmptySubsequences: true)
            return paths.count == 1 ? .file(String(paths[0])) : .none
        default:
            return .none
        }
    }

    /// The name of a dragged picture's file: "Copied Image 2026-11-12 at
    /// 09.41.05 (1280×720).png". No ":" or "/" (a file's name).
    public static func pictureName(size: String?, copied: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: copied)
        let stamp = String(format: "%04d-%02d-%02d at %02d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                           parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let pixels = size.flatMap { $0.isEmpty ? nil : " (\($0.replacingOccurrences(of: "/", with: "×").replacingOccurrences(of: ":", with: "×")))" } ?? ""
        return "Copied Image \(stamp)\(pixels).png"
    }
}
