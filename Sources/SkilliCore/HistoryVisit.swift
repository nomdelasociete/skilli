import Foundation

/// A page a browser visited, from its own history: Chrome and its family
/// (Arc, Brave, Edge, Vivaldi…), Firefox and Zen.
public struct HistoryVisit: Hashable, Sendable {
    public let url: String
    public let title: String
    /// "Chrome".
    public let browser: String
    public let bundleID: String
    public let visited: Date?
    public let visits: Int

    public init(url: String, title: String, browser: String, bundleID: String, visited: Date?, visits: Int) {
        self.url = url
        self.title = title
        self.browser = browser
        self.bundleID = bundleID
        self.visited = visited
        self.visits = visits
    }

    /// "impots.gouv.fr": the host without "www.".
    public var domain: String {
        let host = URL(string: url)?.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Its title, else its address.
    public var shownTitle: String { title.isEmpty ? url : title }
}

/// Pages searched the way a person remembers them: "la page sur les impôts
/// d'hier". The decision model picks among the visits kept, one line each.
public enum HistoryMeaning {
    /// Chrome counts microseconds since 1601.
    public static func chromeDate(_ microseconds: Int64) -> Date? {
        microseconds > 0 ? Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - 11_644_473_600) : nil
    }

    /// Safari counts seconds since 2001.
    public static func safariDate(_ seconds: Double) -> Date? {
        seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil
    }

    /// Firefox counts microseconds since 1970.
    public static func firefoxDate(_ microseconds: Int64) -> Date? {
        microseconds > 0 ? Date(timeIntervalSince1970: Double(microseconds) / 1_000_000) : nil
    }

    /// "“Impôts 2026 : déclaration” on impots.gouv.fr, yesterday 18:02": the
    /// title masked as clipboard excerpts are, before its cut.
    public static func describe(_ visit: HistoryVisit, now: Date = .now, calendar: Calendar = .current) -> String {
        var line = "“\(ClipboardMeaning.excerpt(visit.shownTitle, limit: 160))”"
        if !visit.domain.isEmpty { line += " on \(visit.domain)" }
        if let visited = visit.visited { line += ", \(ClipboardMeaning.when(visited, now: now, calendar: calendar))" }
        return line
    }

    /// For a row: "21:08" today, "yesterday", "Mon" this week, "12 Oct".
    public static func shortWhen(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        } else if now.timeIntervalSince(date) < 6 * 86_400 {
            formatter.dateFormat = "EEE"
        } else {
            formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "d MMM" : "d MMM yyyy"
        }
        return formatter.string(from: date)
    }

    public static func input(_ request: String, now: Date = .now, calendar: Calendar = .current) -> String {
        ClipboardMeaning.input(request, now: now, calendar: calendar).replacingOccurrences(of: "copied earlier", with: "visited in their browser")
    }

    public static let instructions = "Which of these web pages is the user looking for? They describe it as a person remembers it: what it was about, the site, roughly when, possibly in another language than its title. Answer none when no page fits."

    /// "history impôts", "historique impôts" → "impôts".
    public static func modeFilter(_ text: String) -> String? {
        LauncherPrefix.rest(of: text, after: LauncherPrefix.prefixes(for: .searchHistory))
    }

    /// The same page seen in several browsers or profiles once, its most
    /// recent visit; newest first.
    public static func merged(_ lists: [[HistoryVisit]], limit: Int) -> [HistoryVisit] {
        var best: [String: HistoryVisit] = [:]
        for visit in lists.joined() {
            if let known = best[visit.url], (known.visited ?? .distantPast) >= (visit.visited ?? .distantPast) { continue }
            best[visit.url] = visit
        }
        return Array(best.values.sorted { ($0.visited ?? .distantPast) > ($1.visited ?? .distantPast) }.prefix(limit))
    }

    /// Words for SQL's LIKE: each must appear in the title or the address;
    /// `%`, `_` and `\` taken as letters.
    public static func likePatterns(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).prefix(6).map { word in
            "%" + word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
        }
    }
}
