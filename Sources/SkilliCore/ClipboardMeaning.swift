import Foundation

/// The clipboard history searched the way a person remembers it: "the
/// electricity bill I copied yesterday", "Thomas's address", "that train
/// ticket screenshot". A decision model (Jev, OpenAI Decisions) picks among
/// the recent copies, each described in one line; only on ⇥, and only short
/// excerpts leave the Mac.
public enum ClipboardMeaning {
    /// What the model reads of each copy.
    public static let excerptLength = 200
    /// How many recent copies one search looks through.
    public static let candidateLimit = 240

    public enum Kind: String, Sendable {
        case text
        case image
        case files
    }

    /// One line per copy: what it is, where from, when, then its words.
    /// "Image from CleanShot X, yesterday 18:02. Text in it: Billet Paris → Lyon…"
    public static func describe(kind: Kind, text: String, ocr: String?, appName: String?, copiedAt: Date, tags: String? = nil,
                                now: Date = .now, calendar: Calendar = .current) -> String {
        let source = appName.map { " from \($0)" } ?? ""
        let when = Self.when(copiedAt, now: now, calendar: calendar)
        switch kind {
        case .text:
            return "Text\(source), \(when): \(excerpt(text))"
        case .image:
            let words = excerpt(ocr ?? "")
            let address = text.isEmpty ? "" : " Address: \(excerpt(text, limit: 80))."
            // What Jev saw in it, when tagged: "A chart, with a person in it."
            let seen = tags.flatMap(ImageTags.init(words:)).map { tags in
                (tags.kind == .other ? "" : " \(tags.kind.criteria).") + (tags.person ? " A person in it." : "")
            } ?? ""
            return "Image\(source), \(when).\(seen)\(address)" + (words.isEmpty ? " No text in it." : " Text in it: \(words)")
        case .files:
            let names = text.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }
            return "File\(names.count > 1 ? "s" : "")\(source), \(when): \(excerpt(names.joined(separator: ", ")))"
        }
    }

    /// "just now", "today 14:32", "yesterday 18:02", "Monday 14:10" (this
    /// week), "3 October", "3 October 2025".
    public static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = format(date, "HH:mm", calendar)
        if now.timeIntervalSince(date) < 120 { return "just now" }
        if calendar.isDate(date, inSameDayAs: now) { return "today \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday \(time)"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day, days < 7 {
            return format(date, "EEEE HH:mm", calendar)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(date, sameYear ? "d MMMM" : "d MMMM yyyy", calendar)
    }

    /// English names, 24-hour time: what the model reads, whatever the
    /// Mac's own settings.
    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// The words, spaces collapsed, cut at `limit` characters; a bank or
    /// card number or a key in them goes as what it is ("(an IBAN)"), never
    /// itself (`ToolCallSummary.maskingSecrets`).
    public static func excerpt(_ text: String, limit: Int = excerptLength) -> String {
        // A little past the cut, so a number cut in two is still seen whole.
        let collapsed = ToolCallSummary.maskingSecrets(String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit + 80)))
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    /// What the model is given besides the candidates: the request, and now
    /// (so "yesterday" means something).
    public static func input(_ request: String, now: Date = .now, calendar: Calendar = .current) -> String {
        let today = format(now, "EEEE d MMMM yyyy, HH:mm", calendar)
        return "Looking for something copied earlier: \(request)\nNow: \(today)"
    }

    /// The question asked about the candidates.
    public static let instructions = "Which of these copies is the user looking for? They describe it as a person remembers it: what it was about, roughly when, where it came from, text or image, possibly in another language than the copy. Answer none when no copy fits."
}
