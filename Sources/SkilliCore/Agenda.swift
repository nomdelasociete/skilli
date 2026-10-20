import Foundation

/// A calendar event as skil.li shows it: in the launcher, in the card and
/// to agents. Read from the Mac's calendars (any account the Calendar app
/// has), never kept anywhere else.
public struct AgendaEvent: Equatable, Sendable, Identifiable {
    public struct Attendee: Equatable, Sendable {
        public let name: String
        public let email: String?

        public init(name: String, email: String?) {
            self.name = name
            self.email = email
        }
    }

    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The calendar's name ("Work", "Famille").
    public var calendar: String
    public var location: String
    public var notes: String
    public var url: String?
    public var attendees: [Attendee]
    /// The user said no: never their next meeting.
    public var declined: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, calendar: String = "", location: String = "",
                notes: String = "", url: String? = nil, attendees: [Attendee] = [], declined: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.location = location
        self.notes = notes
        self.url = url
        self.attendees = attendees
        self.declined = declined
    }

    /// The video call it is joined by: its URL, else the first call link in
    /// its location or notes.
    public var meeting: MeetingLink? {
        MeetingLink.find(in: [url ?? "", location, notes])
    }
}

/// A video call's link, and the service it belongs to.
public struct MeetingLink: Equatable, Sendable {
    public let url: URL
    /// "Zoom", "Google Meet", "Teams"…
    public let service: String

    /// The services Raycast joins, by their links.
    private static let services: [(name: String, matches: @Sendable (_ host: String, _ path: String) -> Bool)] = [
        ("Zoom", { host, path in (host == "zoom.us" || host.hasSuffix(".zoom.us") || host.hasSuffix("zoomgov.com"))
            && ["/j/", "/my/", "/w/", "/s/", "/wc/"].contains { path.hasPrefix($0) } }),
        ("Google Meet", { host, path in host == "meet.google.com" && path.count > 1 }),
        ("Teams", { host, path in (host == "teams.microsoft.com" || host == "teams.live.com")
            && (path.contains("meetup-join") || path.hasPrefix("/meet/") || path.hasPrefix("/l/meet")) }),
        ("Slack Huddle", { host, path in host.hasSuffix("slack.com") && path.contains("huddle") }),
        ("Webex", { host, path in host.hasSuffix(".webex.com") && path.count > 1 }),
        ("FaceTime", { host, path in host == "facetime.apple.com" && path.hasPrefix("/join") }),
        ("Skype", { host, path in host == "join.skype.com" && path.count > 1 }),
        ("BlueJeans", { host, path in host.hasSuffix("bluejeans.com") && path.count > 1 }),
        ("Chime", { host, path in (host == "chime.aws" || host == "app.chime.aws") && path.count > 1 }),
        ("Whereby", { host, path in host == "whereby.com" && path.count > 1 }),
        ("Jitsi", { host, path in host == "meet.jit.si" && path.count > 1 }),
        ("Around", { host, path in (host == "around.co" || host.hasSuffix(".around.co")) && path.count > 1 }),
        ("Chorus", { host, path in host.hasSuffix("chorus.ai") && path.count > 1 }),
        ("Riverside", { host, path in host.hasSuffix("riverside.fm") && path.count > 1 }),
        ("StreamYard", { host, path in host == "streamyard.com" && path.count > 1 })
    ]

    /// The first call link in these texts, in order (the event's URL, its
    /// location, its notes).
    public static func find(in texts: [String]) -> MeetingLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts where !text.isEmpty {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url else { continue }
                if let link = link(url) { return link }
            }
        }
        return nil
    }

    static func link(_ url: URL) -> MeetingLink? {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "zoommtg" || scheme == "zoomus" { return MeetingLink(url: url, service: "Zoom") }
        if scheme == "msteams" { return MeetingLink(url: url, service: "Teams") }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return nil }
        let path = url.path
        return services.first { $0.matches(host, path) }.map { MeetingLink(url: url, service: $0.name) }
    }

    /// The service's own app link, so the call opens in Zoom or Teams
    /// rather than in a browser tab first; nil when it has none.
    public var appURL: URL? {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "https" && scheme != "http" { return nil }
        switch service {
        case "Zoom":
            // https://zoom.us/j/123456789?pwd=abc → zoommtg://zoom.us/join?action=join&confno=123456789&pwd=abc
            let parts = url.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "j", let host = url.host else { return nil }
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = host
            components.path = "/join"
            var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(parts[1]))]
            if let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
                items.append(URLQueryItem(name: "pwd", value: password))
            }
            components.queryItems = items
            return components.url
        case "Teams":
            // https://teams.microsoft.com/l/meetup-join/… → msteams:/l/meetup-join/…
            let text = url.absoluteString
            guard url.host?.lowercased() == "teams.microsoft.com", let host = text.range(of: "teams.microsoft.com") else { return nil }
            return URL(string: "msteams:" + text[host.upperBound...])
        default:
            return nil
        }
    }
}

/// What the user asks of their calendar, read without a model: their next
/// meeting, to join it, or a day's events.
public enum AgendaRequest: Equatable, Sendable {
    /// `join`: open the call at once.
    case next(join: Bool)
    /// That day's events; 0 is today.
    case day(offset: Int)
    /// Free time in the coming working days, to give someone.
    case availability
    /// Whether the user is free then: "suis-je libre jeudi après-midi ?".
    case free(from: Date, to: Date)

    private static let joinPhrases: [[String]] = [
        ["rejoins", "la", "reunion"], ["rejoindre", "la", "reunion"], ["rejoins", "ma", "reunion"], ["rejoins", "le", "call"],
        ["rejoins", "mon", "call"], ["rejoins", "la", "visio"], ["rejoindre", "la", "visio"], ["lance", "la", "reunion"],
        ["lance", "la", "visio"], ["rejoins", "le", "meeting"], ["join", "the", "meeting"], ["join", "my", "meeting"], ["join", "meeting"],
        ["join", "the", "call"], ["join", "my", "call"], ["join", "call"], ["join", "my", "next", "meeting"], ["join", "the", "next", "meeting"]
    ]
    private static let nextPhrases: [[String]] = [
        ["prochaine", "reunion"], ["prochain", "rendez", "vous"], ["prochain", "rdv"], ["prochain", "meeting"], ["prochain", "call"],
        ["prochain", "evenement"], ["prochaine", "visio"], ["next", "meeting"], ["next", "call"], ["next", "event"], ["next", "appointment"]
    ]
    private static let dayPhrases: [[String]] = [
        ["mon", "agenda"], ["my", "agenda"], ["my", "calendar"], ["my", "schedule"], ["mon", "planning"], ["mon", "programme"],
        ["mes", "reunions"], ["mes", "rendez", "vous"], ["mes", "rdv"], ["my", "meetings"], ["qu", "est", "ce", "que", "j", "ai"],
        ["what", "do", "i", "have"], ["what", "s", "on", "my", "calendar"], ["agenda"]
    ]
    private static let availabilityPhrases: [[String]] = [
        ["mes", "disponibilites"], ["mes", "dispos"], ["mes", "dispo"], ["my", "availability"], ["when", "am", "i", "free"],
        ["quand", "suis", "je", "libre"], ["quand", "je", "suis", "libre"], ["creneaux", "libres"], ["free", "slots"], ["my", "free", "time"]
    ]
    private static let freePhrases: [[String]] = [
        ["suis", "je", "libre"], ["je", "suis", "libre"], ["suis", "je", "dispo"], ["suis", "je", "disponible"], ["suis", "je", "occupe"],
        ["ai", "je", "quelque", "chose"], ["j", "ai", "quelque", "chose"], ["am", "i", "free"], ["am", "i", "available"], ["am", "i", "busy"],
        ["do", "i", "have", "anything"], ["i", "m", "free"]
    ]
    /// Words that only carry the sentence; anything else means more is asked
    /// ("prépare un résumé de ma prochaine réunion") and a model reads it.
    private static let fillers: Set<String> = [
        "c", "est", "quand", "ma", "mon", "mes", "la", "le", "les", "l", "de", "d", "du", "des", "a", "quelle", "quel", "heure", "ce", "que",
        "qu", "j", "ai", "il", "y", "t", "quoi", "et", "on", "pour", "un", "une", "s", "te", "plait", "stp", "svp", "montre", "moi", "affiche",
        "donne", "dis", "matin", "midi", "soir", "apres", "aujourd", "hui", "demain", "is", "when", "my", "the", "what", "time", "do", "i",
        "have", "please", "show", "me", "tell", "today", "tomorrow", "this", "morning", "afternoon", "evening", "at", "of", "for", "maintenant",
        "now", "an", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche", "monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday", "prevu", "prevue", "planned", "going", "with", "next", "upcoming", "cette", "semaine", "week",
        "copie", "copy", "envoie", "les", "jours", "days", "prochains", "coming"
    ]

    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> AgendaRequest? {
        let words = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        func found(_ phrases: [[String]]) -> [String]? {
            phrases.first { phrase in
                phrase.count <= words.count && (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
            }
        }
        // Times stay: "rejoins la réunion de 14h".
        func pure(besides phrase: [String]) -> Bool {
            words.allSatisfy { word in
                phrase.contains(word) || fillers.contains(word) || ["", "h", "min", "am", "pm"].contains(String(word.drop { $0.isNumber }))
                    && word.first?.isNumber == true
            }
        }
        if let phrase = found(joinPhrases), pure(besides: phrase) { return .next(join: true) }
        if let phrase = found(nextPhrases), pure(besides: phrase) { return .next(join: false) }
        if let phrase = found(availabilityPhrases), pure(besides: phrase) { return .availability }
        // "quand suis-je libre" is the free time above; "suis-je libre
        // jeudi après-midi" asks about then.
        if found(freePhrases) != nil, !words.contains("quand"), !words.contains("when") {
            let when = SpokenWhen.parse(text, now: now, calendar: calendar)
            let day = calendar.startOfDay(for: when.date ?? now)
            if let date = when.date, when.hasTime, when.partHours == nil {
                return .free(from: date, to: when.end ?? date.addingTimeInterval(3_600))
            }
            let hours = when.partHours ?? 9..<18
            guard let from = calendar.date(bySettingHour: hours.lowerBound, minute: 0, second: 0, of: day),
                  let to = calendar.date(bySettingHour: hours.upperBound, minute: 0, second: 0, of: day) else { return nil }
            return .free(from: max(from, min(now, to)), to: to)
        }
        if let phrase = found(dayPhrases), pure(besides: phrase) { return .day(offset: dayOffset(words, now: now, calendar: calendar)) }
        return nil
    }

    /// "demain" 1, "après-demain" 2, "jeudi" the next Thursday (today when
    /// it is Thursday), else today.
    static func dayOffset(_ words: [String], now: Date, calendar: Calendar) -> Int {
        let joined = " " + words.joined(separator: " ") + " "
        if joined.contains(" apres demain ") || joined.contains(" day after tomorrow ") { return 2 }
        if joined.contains(" demain ") || joined.contains(" tomorrow ") { return 1 }
        let weekdays = [["dimanche", "sunday"], ["lundi", "monday"], ["mardi", "tuesday"], ["mercredi", "wednesday"], ["jeudi", "thursday"],
                        ["vendredi", "friday"], ["samedi", "saturday"]]
        if let index = weekdays.firstIndex(where: { names in names.contains { words.contains($0) } }) {
            let today = calendar.component(.weekday, from: now) - 1
            return (index - today + 7) % 7
        }
        return 0
    }
}

/// How events are picked and told: the next meeting, "in 12 min", the
/// agenda's sections, a day as Markdown, free time.
public enum Agenda {
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// The meeting to join now or next: one that started up to 15 minutes
    /// ago (the user is late) or the first to come; all-day and declined
    /// events never. A long one under way comes after both.
    public static func next(_ events: [AgendaEvent], now: Date) -> AgendaEvent? {
        let candidates = events.filter { !$0.isAllDay && !$0.declined && $0.end > now }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }
        let lateBy = now.addingTimeInterval(-15 * 60)
        return candidates.first { $0.start >= lateBy } ?? candidates.first
    }

    /// Whether the launcher shows it on its own: from `minutes` before it
    /// starts to `minutes` after.
    public static func isNear(_ event: AgendaEvent, now: Date, minutes: Int = 10) -> Bool {
        let window = TimeInterval(minutes * 60)
        return !event.isAllDay && now >= event.start.addingTimeInterval(-window) && now <= min(event.end, event.start.addingTimeInterval(window))
    }

    /// "09:00–09:30", "All day".
    public static func span(_ event: AgendaEvent, calendar: Calendar = .current) -> String {
        if event.isAllDay { return "All day" }
        let time = formatter("HH:mm", calendar: calendar)
        return "\(time.string(from: event.start))–\(time.string(from: event.end))"
    }

    /// "Now, until 14:30", "In 12 min", "In 1 h 05", "Today 16:00",
    /// "Tomorrow 09:00", "Thu 15 Oct 09:00", "Tomorrow, all day".
    public static func when(_ event: AgendaEvent, now: Date, calendar: Calendar = .current) -> String {
        let time = formatter("HH:mm", calendar: calendar)
        if !event.isAllDay, event.start <= now, event.end > now { return "Now, until \(time.string(from: event.end))" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if !event.isAllDay, minutes > 0, minutes < 60 { return "In \(minutes) min" }
        if !event.isAllDay, minutes >= 60, minutes < 180 {
            return "In \(minutes / 60) h" + (minutes % 60 == 0 ? "" : String(format: " %02d", minutes % 60))
        }
        let day = dayName(event.start, now: now, calendar: calendar)
        return event.isAllDay ? "\(day), all day" : "\(day) \(time.string(from: event.start))"
    }

    /// "Today", "Tomorrow", "Thu 15 Oct", "Thu 15 Oct 2027".
    public static func dayName(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "EEE d MMM" : "EEE d MMM yyyy", calendar: calendar).string(from: date)
    }

    /// The agenda as Raycast's schedule shows it: this week day by day,
    /// next week, the rest of the month, then month by month.
    public static func sections(_ events: [AgendaEvent], now: Date, calendar: Calendar = .current) -> [(title: String, events: [AgendaEvent])] {
        let startOfToday = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let nextWeek = thisWeek.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0.end) }
        let thisMonth = calendar.dateInterval(of: .month, for: now)
        let month = formatter("MMMM yyyy", calendar: calendar)
        var order: [String] = []
        var grouped: [String: [AgendaEvent]] = [:]
        for event in events.filter({ $0.end > now || ($0.isAllDay && $0.end > startOfToday) })
            .sorted(by: { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }) {
            let day = max(event.start, startOfToday)
            let title: String
            if let thisWeek, thisWeek.contains(day) || calendar.isDate(day, inSameDayAs: startOfToday) {
                title = dayName(day, now: now, calendar: calendar)
            } else if let nextWeek, nextWeek.contains(day) {
                title = "Next Week"
            } else if let thisMonth, thisMonth.contains(day) {
                title = "Later This Month"
            } else {
                title = month.string(from: day)
            }
            if grouped[title] == nil { order.append(title) }
            grouped[title, default: []].append(event)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    /// The event as Markdown, for the card.
    public static func details(_ event: AgendaEvent, now: Date, calendar: Calendar = .current) -> String {
        var lines = ["**\(event.title.isEmpty ? "Untitled" : event.title)**"]
        let day = dayName(event.start, now: now, calendar: calendar)
        lines.append("\(day), \(span(event, calendar: calendar))" + (event.isAllDay ? "" : " · \(when(event, now: now, calendar: calendar))"))
        if let meeting = event.meeting { lines.append("- \(meeting.service)") }
        if !event.location.isEmpty, event.location != event.meeting?.url.absoluteString { lines.append("- \(event.location)") }
        if !event.calendar.isEmpty { lines.append("- Calendar: \(event.calendar)") }
        if !event.attendees.isEmpty {
            let names = event.attendees.map(\.name).filter { !$0.isEmpty }
            let shown = names.prefix(6).joined(separator: ", ") + (names.count > 6 ? " and \(names.count - 6) more" : "")
            if !shown.isEmpty { lines.append("- With \(shown)") }
        }
        return lines.joined(separator: "\n")
    }

    /// A day's events as Markdown: "**Tomorrow, Tue 13 Oct**" then
    /// "- **09:00–09:30** Weekly sync · Google Meet".
    public static func dayMarkdown(_ events: [AgendaEvent], day: Date, now: Date, calendar: Calendar = .current) -> String {
        let name = dayName(day, now: now, calendar: calendar)
        let full = formatter("EEE d MMM", calendar: calendar).string(from: day)
        var lines = ["**\(name == full ? name : "\(name), \(full)")**"]
        let onDay = events.filter { event in
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return event.start < dayEnd && event.end > dayStart && !event.declined
        }.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        if onDay.isEmpty { return lines[0] + "\nNothing planned." }
        for event in onDay {
            let extra = event.meeting.map { " · \($0.service)" } ?? (event.location.isEmpty ? "" : " · \(event.location)")
            lines.append("- **\(span(event, calendar: calendar))** \(event.title.isEmpty ? "Untitled" : event.title)\(extra)")
        }
        return lines.joined(separator: "\n")
    }

    /// Free time, working days only, for an email: "Tue 13 Oct: 09:00–10:00,
    /// 11:30–18:00". `hours`: the working day.
    public static func availability(_ events: [AgendaEvent], from now: Date, days: Int = 5, hours: ClosedRange<Int> = 9...18,
                                    calendar: Calendar = .current) -> String {
        let time = formatter("HH:mm", calendar: calendar)
        var lines: [String] = []
        var day = calendar.startOfDay(for: now)
        var counted = 0
        while counted < days {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400) }
            guard !calendar.isDateInWeekend(day),
                  let open = calendar.date(bySettingHour: hours.lowerBound, minute: 0, second: 0, of: day),
                  let close = calendar.date(bySettingHour: hours.upperBound, minute: 0, second: 0, of: day) else { continue }
            counted += 1
            var free: [(Date, Date)] = []
            var cursor = max(open, calendar.isDate(day, inSameDayAs: now) ? now : open)
            let busy = events.filter { !$0.isAllDay && !$0.declined && $0.end > cursor && $0.start < close }.sorted { $0.start < $1.start }
            for event in busy {
                if event.start.timeIntervalSince(cursor) >= 30 * 60 { free.append((cursor, event.start)) }
                cursor = max(cursor, event.end)
            }
            if close.timeIntervalSince(cursor) >= 30 * 60 { free.append((cursor, close)) }
            guard !free.isEmpty else { continue }
            let slots = free.map { "\(time.string(from: roundUp($0.0, calendar: calendar)))–\(time.string(from: $0.1))" }
            lines.append("\(formatter("EEE d MMM", calendar: calendar).string(from: day)): \(slots.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Whether the user is free from `start` to `end`, as Markdown:
    /// "**Free** Thursday 14:00–18:00", or what is there and the free time
    /// around it.
    public static func freeAnswer(_ events: [AgendaEvent], from start: Date, to end: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = formatter("HH:mm", calendar: calendar)
        let day = dayName(start, now: now, calendar: calendar)
        let busy = events.filter { !$0.isAllDay && !$0.declined && $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
        let window = "\(day), \(time.string(from: start))–\(time.string(from: end))"
        guard !busy.isEmpty else { return "**Free** \(window)" }
        var lines = ["**Busy** \(window)"]
        for event in busy {
            lines.append("- **\(span(event, calendar: calendar))** \(event.title.isEmpty ? "Untitled" : event.title)")
        }
        var free: [String] = []
        var cursor = start
        for event in busy {
            if event.start.timeIntervalSince(cursor) >= 15 * 60 { free.append("\(time.string(from: cursor))–\(time.string(from: event.start))") }
            cursor = max(cursor, event.end)
        }
        if end.timeIntervalSince(cursor) >= 15 * 60 { free.append("\(time.string(from: cursor))–\(time.string(from: end))") }
        lines.append(free.isEmpty ? "No free time then." : "Free \(free.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    /// To the next quarter hour: "14:07" offers "14:15".
    private static func roundUp(_ date: Date, calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let extra = (15 - minute % 15) % 15
        let rounded = calendar.date(byAdding: .minute, value: extra, to: date) ?? date
        return calendar.dateInterval(of: .minute, for: rounded)?.start ?? rounded
    }
}
