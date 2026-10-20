import Foundation

/// A calendar event said in one sentence, read without a model: "rdv
/// demain 14h point budget avec Paul", "ajoute à mon agenda dentiste jeudi
/// 9h30 #Perso", "bloque 2h demain matin pour écrire", "schedule standup
/// every weekday at 9:30 for 15 min", "réunion de 14h à 15h vendredi :
/// préparer les chiffres", "… rappel 10 min avant".
public struct EventRequest: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// "#Perso": a calendar by (the start of) its name.
    public var calendar: String?
    /// After a colon.
    public var notes: String
    public var url: String?
    /// An alert that many minutes before.
    public var alertMinutes: Int?
    public var recurrence: SpokenRecurrence?

    /// The words that say an event is to be made, at the start.
    private static let starts: [[String]] = [
        ["cree", "un", "rendez-vous"], ["cree", "un", "rdv"], ["cree", "un", "evenement"], ["cree", "une", "reunion"], ["cree", "un", "meeting"],
        ["creer", "un", "rendez-vous"], ["creer", "un", "evenement"], ["ajoute", "a", "mon", "agenda"], ["ajoute", "a", "l'agenda"],
        ["ajoute", "au", "calendrier"], ["ajoute", "un", "rendez-vous"], ["ajoute", "un", "rdv"], ["ajoute", "un", "evenement"],
        ["ajoute", "une", "reunion"], ["planifie", "un", "rdv"], ["planifie", "une", "reunion"], ["planifie"], ["programme", "un", "rdv"],
        ["nouvel", "evenement"], ["nouveau", "rdv"], ["nouveau", "rendez-vous"], ["rendez-vous"], ["rendez", "vous"], ["rdv"], ["evenement"],
        ["add", "an", "event"], ["add", "event"], ["add", "to", "my", "calendar"], ["create", "an", "event"], ["create", "event"],
        ["new", "event"], ["schedule", "a", "meeting"], ["schedule", "a"], ["schedule"], [word], ["book", "a"]
    ]
    /// The word the Catalog teaches: "event lunch with Paul tomorrow 1pm".
    public static let word = "event"
    /// What the event is, said first: kept in its title ("Réunion budget"),
    /// and only where the user typed an event on purpose (the launcher).
    private static let nouns: [[String]] = [
        ["reunion"], ["meeting"], ["call"], ["dejeuner"], ["lunch"], ["diner"], ["dinner"], ["point"], ["visio"]
    ]
    /// Time kept for oneself: "bloque 2h demain matin", "block 1 hour".
    private static let blocks: [[String]] = [
        ["bloque"], ["bloquer"], ["reserve", "du", "temps"], ["reserve"], ["block", "time"], ["block"]
    ]
    private static let connectors: Set<String> = ["pour", "for", "de", "d'", "un", "une", "a", "an", "the", "le", "la", "les", "l'",
                                                  "to", "on", "au", "aux", "du", "-", ":", "et", "and"]
    private static let alertPattern = #"(?i)\b(?:rappel|alerte|alert|reminder|notif(?:ication)?)\s+(\d+)\s*(min|mins|minutes?|mn|h|heures?|hours?)\s+(?:avant|before)\b"#

    /// Nil when the sentence does not ask for an event, or says no day.
    /// `calendars`: the user's calendar names, for "#perso". `nounFirst`:
    /// "réunion budget demain 14h" counts too (typed in the launcher, where
    /// it is offered, not done).
    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current, calendars: [String] = [],
                             nounFirst: Bool = false) -> EventRequest? {
        var sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = sentence.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).map(String.init)
        func startsWith(_ phrase: [String]) -> Bool { phrase.count <= words.count && Array(words.prefix(phrase.count)) == phrase }
        var isBlock = false
        if let phrase = blocks.first(where: startsWith) {
            isBlock = true
            sentence = drop(phrase.count, from: sentence)
        } else if let phrase = starts.first(where: startsWith) {
            sentence = drop(phrase.count, from: sentence)
        } else if !(nounFirst && nouns.contains(where: startsWith)) {
            return nil
        }

        // Notes after a colon, a link anywhere, an alert, a calendar.
        var notes = ""
        // A colon then a space ("… vendredi : préparer"), not "14:30" or a link.
        if let colon = sentence.range(of: #":\s"#, options: .regularExpression) {
            notes = sentence[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            sentence = String(sentence[..<colon.lowerBound])
        }
        var url: String?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
           let range = Range(match.range, in: sentence), match.url?.scheme?.hasPrefix("http") == true {
            url = match.url?.absoluteString
            sentence.removeSubrange(range)
        }
        var alertMinutes: Int?
        if let regex = try? NSRegularExpression(pattern: alertPattern),
           let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
           let amount = Range(match.range(at: 1), in: sentence).flatMap({ Int(sentence[$0]) }),
           let unit = Range(match.range(at: 2), in: sentence).map({ sentence[$0].lowercased() }), let whole = Range(match.range, in: sentence) {
            alertMinutes = unit.hasPrefix("h") ? amount * 60 : amount
            sentence.removeSubrange(whole)
        }
        var calendarName: String?
        if let tag = sentence.range(of: #"#[^\s#]+"#, options: .regularExpression) {
            let named = String(sentence[tag].dropFirst())
            let folded = { (text: String) in text.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
            calendarName = calendars.first { folded($0) == folded(named) } ?? calendars.first { folded($0).hasPrefix(folded(named)) } ?? named
            sentence.removeSubrange(tag)
        }

        // "bloque 2h demain matin": how long, before the day and time.
        var blockSeconds: Int?
        if isBlock, let (seconds, range) = leadingDuration(in: sentence) {
            blockSeconds = seconds
            sentence.removeSubrange(range)
        }

        let when = SpokenWhen.parse(sentence, now: now, calendar: calendar)
        guard let date = when.date else { return nil }
        var title = clean(when.rest)
        if title.isEmpty { title = isBlock ? "Busy" : "Event" }

        let start: Date
        let end: Date
        var isAllDay = false
        if when.hasTime {
            start = date
            if let blockSeconds {
                end = start.addingTimeInterval(TimeInterval(blockSeconds))
            } else {
                end = when.end ?? start.addingTimeInterval(3_600)
            }
        } else if let blockSeconds {
            // A block with a day and no time: from the start of the working
            // day, or of the part of the day said.
            let hour = when.partHours?.lowerBound ?? 9
            start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            end = start.addingTimeInterval(TimeInterval(blockSeconds))
        } else {
            isAllDay = true
            start = calendar.startOfDay(for: date)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        return EventRequest(title: title, start: start, end: end, isAllDay: isAllDay, calendar: calendarName, notes: notes, url: url,
                            alertMinutes: alertMinutes, recurrence: when.recurrence)
    }

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false, calendar: String? = nil, notes: String = "", url: String? = nil,
                alertMinutes: Int? = nil, recurrence: SpokenRecurrence? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.notes = notes
        self.url = url
        self.alertMinutes = alertMinutes
        self.recurrence = recurrence
    }

    /// The sentence without its first `count` words.
    private static func drop(_ count: Int, from sentence: String) -> String {
        sentence.split(whereSeparator: \.isWhitespace).dropFirst(count).joined(separator: " ")
    }

    /// "2h", "2 h", "90 min", "1h30", "2 heures" at the start.
    private static func leadingDuration(in sentence: String) -> (Int, Range<String.Index>)? {
        let trimmed = sentence.drop { $0.isWhitespace }
        guard trimmed.first?.isNumber == true, let (seconds, range) = TimerRequest.duration(in: sentence),
              sentence[..<range.lowerBound].allSatisfy(\.isWhitespace), seconds >= 5 * 60, seconds <= 12 * 3_600 else { return nil }
        return (seconds, range)
    }

    /// Without the little words left at its ends, its first letter up.
    static func clean(_ text: String) -> String {
        var words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        func folded(_ word: String) -> String { word.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        while let first = words.first, connectors.contains(folded(first)) { words.removeFirst() }
        while let last = words.last, connectors.contains(folded(last)) { words.removeLast() }
        var title = words.joined(separator: " ")
        // "d'appeler" alone at the start: "Appeler".
        if let apostrophe = title.firstIndex(of: "'"), title.distance(from: title.startIndex, to: apostrophe) == 1,
           connectors.contains(folded(String(title[...apostrophe]))) {
            title = String(title[title.index(after: apostrophe)...])
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}
