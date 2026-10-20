import Foundation

/// When an ask comes back: every day, on some days of the week, or on a day
/// of the month, at a time ("every Monday at 9:00", "tous les jours ouvrés à
/// 8h30", "le 1er de chaque mois à 9h"). Read on this Mac from what the
/// user says in Ask (`read`), without a model.
public struct AskSchedule: Codable, Hashable, Sendable {
    public enum Repeat: String, Codable, Sendable {
        case daily, weekly, monthly
    }

    public var repeats: Repeat
    /// Weekly: calendar weekdays, 1 Sunday … 7 Saturday.
    public var weekdays: [Int]
    /// Monthly: 1…31; a shorter month runs on its last day.
    public var day: Int
    public var hour: Int
    public var minute: Int
    /// Every `interval` days, weeks or months, counted from `start`'s.
    public var interval: Int
    /// The day it counts from (its day, week or month is the first).
    public var start: Date

    public init(_ repeats: Repeat, weekdays: [Int] = [], day: Int = 1, hour: Int, minute: Int = 0, interval: Int = 1, start: Date) {
        self.repeats = repeats
        self.weekdays = weekdays.sorted { Self.mondayFirst($0) < Self.mondayFirst($1) }
        self.day = min(max(day, 1), 31)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.interval = max(interval, 1)
        self.start = start
    }

    // MARK: - When it runs

    /// Its first time after `date` (strictly). A time that does not exist
    /// that day (the clocks go forward) is the next one that does.
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        let every = max(interval, 1)
        let today = calendar.startOfDay(for: date)
        func at(_ day: Date) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime,
                          repeatedTimePolicy: .first, direction: .forward)
        }
        switch repeats {
        case .daily, .weekly:
            let days = Set(weekdays.isEmpty ? [calendar.component(.weekday, from: start)] : weekdays)
            for offset in 0...(7 * every + 7) {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if repeats == .weekly {
                    guard days.contains(calendar.component(.weekday, from: day)),
                          Self.count(.weekOfYear, from: start, to: day, calendar).isMultiple(of: every) else { continue }
                } else {
                    guard Self.count(.day, from: start, to: day, calendar).isMultiple(of: every) else { continue }
                }
                if let candidate = at(day), candidate > date { return candidate }
            }
        case .monthly:
            guard let month = calendar.dateInterval(of: .month, for: today)?.start else { return nil }
            for offset in 0...(12 * every + 1) {
                guard let first = calendar.date(byAdding: .month, value: offset, to: month),
                      Self.count(.month, from: start, to: first, calendar).isMultiple(of: every),
                      let length = calendar.range(of: .day, in: .month, for: first)?.count,
                      let day = calendar.date(byAdding: .day, value: min(self.day, length) - 1, to: first),
                      let candidate = at(day), candidate > date else { continue }
                return candidate
            }
        }
        return nil
    }

    /// Whole days, weeks or months from `start`'s to `end`'s.
    private static func count(_ unit: Calendar.Component, from start: Date, to end: Date, _ calendar: Calendar) -> Int {
        switch unit {
        case .weekOfYear:
            guard let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
                  let last = calendar.dateInterval(of: .weekOfYear, for: end)?.start else { return 0 }
            let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
            return Int((Double(days) / 7).rounded())
        case .month:
            guard let first = calendar.dateInterval(of: .month, for: start)?.start,
                  let last = calendar.dateInterval(of: .month, for: end)?.start else { return 0 }
            return calendar.dateComponents([.month], from: first, to: last).month ?? 0
        default:
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        }
    }

    // MARK: - Said

    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Monday first, Sunday last.
    private static func mondayFirst(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    /// "9:00", "18:30".
    public static func time(hour: Int, minute: Int) -> String {
        "\(hour):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }

    /// "1st", "2nd", "3rd", "11th", "22nd".
    public static func ordinal(_ number: Int) -> String {
        let suffix = switch (number % 10, number % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(number)\(suffix)"
    }

    /// "Monday", "Monday and Thursday", "Monday, Wednesday and Friday".
    private static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    /// "Every Monday at 9:00", "Every weekday at 8:30", "Every month on the
    /// 1st at 9:00", "Every 2 weeks on Monday at 9:00".
    public var spoken: String {
        let at = " at " + Self.time(hour: hour, minute: minute)
        switch repeats {
        case .daily:
            return (interval > 1 ? "Every \(interval) days" : "Every day") + at
        case .weekly:
            let days = weekdays.isEmpty ? [Calendar.current.component(.weekday, from: start)] : weekdays
            let names = Self.list(days.map { Self.dayNames[($0 - 1 + 7) % 7] })
            if interval > 1 { return "Every \(interval) weeks on \(names)" + at }
            switch Set(days) {
            case [2, 3, 4, 5, 6]: return "Every weekday" + at
            case [1, 2, 3, 4, 5, 6, 7]: return "Every day" + at
            default: return "Every \(names)" + at
            }
        case .monthly:
            return (interval > 1 ? "Every \(interval) months" : "Every month") + " on the \(Self.ordinal(day))" + at
        }
    }

    // MARK: - Read from a sentence

    /// What brings a schedule in a sentence; nothing of it: not one.
    private static let triggers = ["every", "each", "tous les", "toutes les", "chaque", "daily", "weekly", "monthly", "weekdays",
                                   "quotidien", "quotidiennement", "hebdo", "hebdomadaire", "mensuel", "mensuellement", "en semaine",
                                   "ouvres", "ouvrables", "du lundi au vendredi", "week-end", "weekend",
                                   "on mondays", "on tuesdays", "on wednesdays", "on thursdays", "on fridays", "on saturdays", "on sundays"]

    /// Ways of saying it that `SpokenWhen` reads once said its way.
    private static let rewrites: [(pattern: String, with: String)] = [
        (#"\beach\b"#, "every"),
        (#"\bevery\s+(?:working|business|work)\s+day\b"#, "every weekday"),
        (#"\bon\s+weekdays\b"#, "every weekday"),
        (#"\b(?:tous\s+les|chaque)\s+jours?\s+(?:ouvr[ée]s?|ouvrables?|de\s+(?:la\s+)?semaine)(?=\s|$|[,.;:])"#, "en semaine"),
        (#"\bles\s+jours\s+(?:ouvr[ée]s|ouvrables|de\s+semaine)(?=\s|$|[,.;:])"#, "en semaine"),
        (#"\bdu\s+lundi\s+au\s+vendredi\b"#, "en semaine"),
        (#"\b(?:tous\s+les\s+week-?ends?|chaque\s+week-?end|le\s+week-?end)\b"#, "tous les samedis et dimanches"),
        (#"\bevery\s+weekend\b"#, "every saturday and sunday"),
        (#"\b(?:tous\s+les\s+matins|chaque\s+matin)\b"#, "tous les jours matin"),
        (#"\b(?:tous\s+les\s+soirs|chaque\s+soir)\b"#, "tous les jours soir"),
        (#"\bevery\s+morning\b"#, "every day morning"),
        (#"\bevery\s+(?:evening|night)\b"#, "every day evening"),
        (#"\bevery\s+afternoon\b"#, "every day afternoon"),
        (#"\bon\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s\b"#, "every $1"),
        (#"\ble\s+premier\b"#, "le 1er"),
        (#"\bthe\s+first\b"#, "the 1st"),
        (#"\b(?:du|de\s+chaque|de\s+tous\s+les)\s+mois\b"#, "chaque mois"),
        (#"\bof\s+(?:the|each|every)\s+month\b"#, "every month")
    ]

    /// Words that only carry the sentence between those that say when.
    private static let fillers: Set<String> = ["on", "at", "the", "le", "la", "les", "l'", "a", "de", "du", "d'", "en", "in", "et", "and",
                                               "of", "every", "each", "chaque", "tous", "toutes", "-", ":", ",", "&", "+", "vers", "around"]

    private static let weekdayWords: [[String]] = [
        ["dimanche", "sunday"], ["lundi", "monday"], ["mardi", "tuesday"], ["mercredi", "wednesday"], ["jeudi", "thursday"],
        ["vendredi", "friday"], ["samedi", "saturday"]
    ]

    private static func fold(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "’", with: "'")
    }

    /// A weekday named, alone or plural: "lundis", "mondays".
    private static func weekday(_ word: String) -> Int? {
        let plain = word.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
        for (index, names) in weekdayWords.enumerated() where names.contains(plain) || plain.hasSuffix("s") && names.contains(String(plain.dropLast())) {
            return index + 1
        }
        return nil
    }

    /// The schedule a sentence starts or ends with, and what to ask then:
    /// "tous les lundis à 9h résume mes PR", "every weekday at 8:30 tell
    /// me my day", "résume mes PR chaque lundi à 9h", "le 1er de chaque
    /// mois à 9h envoie-moi le point". The words saying when are one block
    /// at the start or the end, and say a time, a day of the week or a day
    /// of the month (plain "every day I wonder…" is not a schedule).
    /// `anywhere`: those words may be anywhere and say less (Ask's decision
    /// already chose a schedule). Nil when it says no schedule, or nothing
    /// to ask. Yearly ones are not offered.
    public static func read(_ text: String, now: Date = .now, calendar: Calendar = .current,
                            anywhere: Bool = false) -> (schedule: AskSchedule, ask: String)? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let folded = words.map { fold($0) }
        guard words.count >= 2, hasTrigger(folded[...]) else { return nil }
        func found(_ range: Range<Int>, whole: Bool) -> (schedule: AskSchedule, ask: String)? {
            guard hasTrigger(folded[range]),
                  let schedule = schedule(in: words[range].joined(separator: " "), now: now, calendar: calendar, needsWhen: whole) else { return nil }
            return askText((words[..<range.lowerBound] + words[range.upperBound...]).joined(separator: " ")).map { (schedule, $0) }
        }
        if anywhere {
            // The longest run of words that says when, anywhere.
            for length in stride(from: words.count - 1, through: 1, by: -1) {
                for start in 0...(words.count - length) {
                    if let result = found(start..<(start + length), whole: false) { return result }
                }
            }
            return nil
        }
        // The longest block at the start, its little words at its end
        // given back ("every Monday at 9 the report": "the report").
        for count in stride(from: words.count - 1, through: 1, by: -1) where found(0..<count, whole: true) != nil {
            var end = count
            while end > 1, fillers.contains(folded[end - 1]), found(0..<(end - 1), whole: true) != nil { end -= 1 }
            return found(0..<end, whole: true)
        }
        // Then at the end.
        for first in 1..<words.count where found(first..<words.count, whole: true) != nil {
            var start = first
            while start < words.count - 1, fillers.contains(folded[start]), found((start + 1)..<words.count, whole: true) != nil { start += 1 }
            return found(start..<words.count, whole: true)
        }
        return nil
    }

    /// A schedule said alone ("every Monday at 9:00", "tous les jours à
    /// 8h30", "daily at 7am"), as tools give it; nil when it says none, or
    /// says more than when.
    public static func when(_ text: String, now: Date = .now, calendar: Calendar = .current) -> AskSchedule? {
        schedule(in: text.trimmingCharacters(in: .whitespacesAndNewlines), now: now, calendar: calendar, needsWhen: false)
    }

    /// Whether the sentence says again and again ("every", "chaque", "tous
    /// les", "daily", "en semaine"…): only then is a schedule worth asking
    /// about.
    public static func mentionsRepeat(_ text: String) -> Bool {
        hasTrigger(text.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }[...])
    }

    private static func hasTrigger(_ words: ArraySlice<String>) -> Bool {
        let joined = " " + words.joined(separator: " ") + " "
        return triggers.contains { joined.contains(" " + $0 + " ") || joined.contains(" " + $0 + "s ") }
    }

    /// What to ask, without the marks around it; nil when no word is left.
    private static func askText(_ text: String) -> String? {
        let marks = CharacterSet(charactersIn: ",:;-–—→").union(.whitespacesAndNewlines)
        let trimmed = text.trimmingCharacters(in: marks)
        let words = trimmed.split(whereSeparator: \.isWhitespace).map { fold(String($0)).trimmingCharacters(in: .punctuationCharacters) }
        guard words.contains(where: { !$0.isEmpty && !fillers.contains($0) && $0.contains(where: \.isLetter) }) else { return nil }
        return trimmed
    }

    /// The schedule `phrase` says: every word of it says when, or only
    /// carries the sentence. `needsWhen`: it names a time or a day ("every
    /// day" alone is not enough).
    private static func schedule(in phrase: String, now: Date, calendar: Calendar, needsWhen: Bool) -> AskSchedule? {
        // Lowercased, accents kept: `SpokenWhen` reads "à 9" as a time, "a 9" not.
        var said = phrase.lowercased().replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"(\d)\s*:(?=\s|$)"#, with: "$1", options: .regularExpression)
        for rewrite in rewrites {
            said = said.replacingOccurrences(of: rewrite.pattern, with: rewrite.with, options: [.regularExpression, .caseInsensitive])
        }
        let when = SpokenWhen.parse(said, now: now, calendar: calendar)
        guard let recurrence = when.recurrence, recurrence.frequency != .yearly else { return nil }
        let tokens = said.split(whereSeparator: \.isWhitespace).map(String.init)
        let named = tokens.compactMap(weekday)
        for word in when.rest.split(whereSeparator: \.isWhitespace) {
            let plain = fold(String(word)).trimmingCharacters(in: CharacterSet(charactersIn: ",.;!?()\"“”«»"))
            guard plain.isEmpty || fillers.contains(plain) || weekday(plain) != nil else { return nil }
        }
        // "le 15", "the 1st", "on the 15th": a day of the month.
        var monthDay: Int?
        if let match = said.range(of: #"(?:^|\s)(?:le|the|on)\s+(\d{1,2})(?:er|st|nd|rd|th|e)?(?=\s|$)|(?:^|\s)(\d{1,2})(?:er|st|nd|rd|th)(?=\s|$)"#,
                                  options: .regularExpression) {
            let digits = said[match].filter(\.isNumber)
            if let number = Int(digits), (1...31).contains(number) { monthDay = number }
        }
        var hour = 9
        var minute = 0
        if when.hasTime, let date = when.date {
            hour = calendar.component(.hour, from: date)
            minute = calendar.component(.minute, from: date)
        }
        let start = calendar.startOfDay(for: now)
        let schedule: AskSchedule
        switch recurrence.frequency {
        case .daily:
            schedule = AskSchedule(.daily, hour: hour, minute: minute, interval: recurrence.interval, start: start)
        case .weekly:
            var days = recurrence.weekdays == [2, 3, 4, 5, 6] ? recurrence.weekdays : Array(Set(recurrence.weekdays + named))
            if days.isEmpty { days = [calendar.component(.weekday, from: now)] }
            schedule = days.count == 7 && recurrence.interval == 1
                ? AskSchedule(.daily, hour: hour, minute: minute, start: start)
                : AskSchedule(.weekly, weekdays: days, hour: hour, minute: minute, interval: recurrence.interval, start: start)
        case .monthly:
            schedule = AskSchedule(.monthly, day: monthDay ?? calendar.component(.day, from: now), hour: hour, minute: minute,
                                   interval: recurrence.interval, start: start)
        case .yearly:
            return nil
        }
        // "every day I wonder…": a schedule says when in the day or which day.
        if needsWhen, !when.hasTime, named.isEmpty, monthDay == nil, recurrence.weekdays.isEmpty { return nil }
        return schedule
    }
}
