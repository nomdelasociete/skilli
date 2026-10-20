import Foundation

/// A reminder as skil.li shows it: in the launcher, the card and to agents.
public struct ReminderItem: Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var due: Date?
    /// A time was set (else the day alone).
    public var hasTime: Bool
    /// The list's name ("Courses", "Reminders").
    public var list: String
    /// EventKit's: 0 none, 1–4 high, 5 medium, 6–9 low.
    public var priority: Int
    public var notes: String
    public var url: String?
    public var isCompleted: Bool
    public var completedAt: Date?
    public var repeats: Bool

    public init(id: String, title: String, due: Date? = nil, hasTime: Bool = false, list: String = "Reminders", priority: Int = 0,
                notes: String = "", url: String? = nil, isCompleted: Bool = false, completedAt: Date? = nil, repeats: Bool = false) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.list = list
        self.priority = priority
        self.notes = notes
        self.url = url
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.repeats = repeats
    }

    /// "!!!", "!!", "!" as Reminders shows them.
    public var marks: String {
        switch priority {
        case 1...4: "!!!"
        case 5: "!!"
        case 6...9: "!"
        default: ""
        }
    }

    /// Its link: the URL field, else the first link in its notes.
    public var link: URL? {
        if let url, let link = URL(string: url), link.scheme != nil { return link }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes))?.url
    }
}

/// A place a reminder rings at: "en arrivant au bureau", "when I leave
/// home". `name` as said; matched to the user's saved places by the app.
public struct ReminderPlace: Equatable, Sendable {
    public var name: String
    /// Arriving (else leaving).
    public var arriving: Bool

    public init(name: String, arriving: Bool) {
        self.name = name
        self.arriving = arriving
    }

    /// "en arrivant au bureau", "quand j'arrive à la maison", "en partant
    /// du bureau", "quand je quitte le bureau", "when I get home", "when I
    /// arrive at work", "when I leave the office": the place and the words.
    static func find(in sentence: String) -> (ReminderPlace, Range<String.Index>)? {
        let patterns: [(String, Bool)] = [
            (#"(?i)\b(?:en\s+arrivant|quand\s+j['’]arrive|lorsque\s+j['’]arrive|à\s+mon\s+arrivée)\s+(?:à\s+la\s+|à\s+l['’]|au\s+|aux\s+|à\s+|chez\s+|a\s+la\s+|a\s+)?([\p{L}\p{N}'’-]+(?:\s+[\p{L}\p{N}'’-]+)?)"#, true),
            (#"(?i)\b(?:en\s+partant|quand\s+je\s+pars|en\s+quittant|quand\s+je\s+quitte|lorsque\s+je\s+pars)\s+(?:de\s+la\s+|de\s+l['’]|du\s+|des\s+|de\s+|d['’]|la\s+|le\s+|l['’]|chez\s+)?([\p{L}\p{N}'’-]+(?:\s+[\p{L}\p{N}'’-]+)?)"#, false),
            (#"(?i)\bwhen\s+i\s+(?:get|arrive|am)\s+(?:to\s+the\s+|at\s+the\s+|to\s+|at\s+)?(home|[\p{L}\p{N}'’-]+)"#, true),
            (#"(?i)\bwhen\s+i\s+leave\s+(?:the\s+)?([\p{L}\p{N}'’-]+)"#, false)
        ]
        for (pattern, arriving) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
                  let whole = Range(match.range, in: sentence), let named = Range(match.range(at: 1), in: sentence) else { continue }
            // One word is the place unless the next is a time or day word.
            var name = String(sentence[named])
            let words = name.split(separator: " ")
            var range = whole
            if words.count == 2, SpokenWhen.parse(String(words[1])).date != nil || ["pour", "to", "and", "et"].contains(words[1].lowercased()) {
                name = String(words[0])
                range = whole.lowerBound..<sentence.index(named.lowerBound, offsetBy: words[0].count)
            }
            return (ReminderPlace(name: name, arriving: arriving), range)
        }
        return nil
    }
}

/// A reminder said in one sentence, read without a model: "rappelle-moi
/// d'appeler Paul demain à 9h", "remind me to call Paul tomorrow at 9am !!",
/// "todo acheter du pain #Courses", "rappel payer le loyer tous les mois le
/// 5", "rappelle-moi de lire cet article" (the page in front goes with it).
public struct ReminderRequest: Equatable, Sendable {
    public var title: String
    public var due: Date?
    public var hasTime: Bool
    /// "#Courses": a list by (the start of) its name.
    public var list: String?
    /// EventKit's: 0 none, 1 high, 5 medium, 9 low.
    public var priority: Int
    public var recurrence: SpokenRecurrence?
    /// After a colon.
    public var notes: String
    public var url: String?
    /// "ce lien", "cet article", "this page": the page in front goes with it.
    public var withPageInFront: Bool
    /// "ce mail", "this email": the message selected in Mail goes with it.
    public var withMailInFront: Bool
    /// "en arrivant au bureau": it rings there, not at a time.
    public var place: ReminderPlace?

    public init(title: String, due: Date? = nil, hasTime: Bool = false, list: String? = nil, priority: Int = 0,
                recurrence: SpokenRecurrence? = nil, notes: String = "", url: String? = nil, withPageInFront: Bool = false,
                withMailInFront: Bool = false, place: ReminderPlace? = nil) {
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.list = list
        self.priority = priority
        self.recurrence = recurrence
        self.notes = notes
        self.url = url
        self.withPageInFront = withPageInFront
        self.withMailInFront = withMailInFront
        self.place = place
    }

    /// What the Catalog teaches to start one: "remind me to call Paul
    /// tomorrow 9am" (`starts` reads it).
    public static let word = "remind me"
    /// What starts a reminder, at the start of the sentence.
    private static let starts: [String] = [
        #"rappelle[- ]?(?:moi|nous)\s+(?:de\s+|d['’]|qu['’]|que\s+|à\s+|a\s+)?"#,
        #"(?:n['’]oublie\s+pas|pense\s+[àa])\s+(?:de\s+|d['’])?"#,
        #"(?:ajoute|crée|cree|créer|creer|nouveau|nouvel|mets|met)\s+(?:un\s+|une\s+)?(?:rappel|todo|to-do|tâche|tache)\s*(?:pour\s+|de\s+|d['’]|:\s*)?"#,
        #"(?:ajoute|mets|met)\s+(?:à|a|dans)\s+(?:mes|ma)\s+(?:rappels|todo|tâches|taches)\s*:?\s*"#,
        #"add\s+to\s+my\s+(?:reminders|todos|tasks)\s*:?\s*"#,
        #"(?:rappel|todo|to-do|tâche|tache|à\s+faire|a\s+faire)\s*:?\s+"#,
        #"remind\s+(?:me|us)\s+(?:to\s+|that\s+|about\s+|of\s+)?"#,
        #"(?:add|create|new|set)\s+(?:a\s+)?(?:reminder|todo|to-do|task)\s*(?:to\s+|for\s+|:\s*)?"#,
        #"(?:reminder|task)\s*:?\s+"#
    ]
    private static let pagePhrases = ["ce lien", "cet article", "cette page", "cet onglet", "this link", "this article", "this page", "this tab"]
    private static let mailPhrases = ["ce mail", "cet email", "cet e-mail", "ce message", "ce courriel", "this email", "this mail", "this e-mail", "this message"]

    /// Nil when the sentence does not ask for a reminder. `lists`: the
    /// user's lists, for "#courses".
    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current, lists: [String] = []) -> ReminderRequest? {
        var sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = starts.lazy.compactMap({ sentence.range(of: "^" + $0, options: [.regularExpression, .caseInsensitive]) }).first else {
            return nil
        }
        sentence.removeSubrange(start)

        var notes = ""
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
        var list: String?
        if let tag = sentence.range(of: #"#[^\s#]+"#, options: .regularExpression) {
            let named = String(sentence[tag].dropFirst())
            let folded = { (text: String) in text.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
            list = lists.first { folded($0) == folded(named) } ?? lists.first { folded($0).hasPrefix(folded(named)) } ?? named
            sentence.removeSubrange(tag)
        }
        var priority = 0
        if let marks = sentence.range(of: #"(?:^|\s)(!{1,3})(?=\s|$)"#, options: .regularExpression) {
            let count = sentence[marks].filter { $0 == "!" }.count
            priority = count == 3 ? 1 : count == 2 ? 5 : 9
            sentence.removeSubrange(marks)
        } else if let word = sentence.range(of: #"\b(?:urgent|important|high priority|priorité haute|priorite haute)\b"#,
                                            options: [.regularExpression, .caseInsensitive]) {
            priority = 1
            sentence.removeSubrange(word)
        } else if let word = sentence.range(of: #"\b(?:low priority|priorité basse|priorite basse)\b"#, options: [.regularExpression, .caseInsensitive]) {
            priority = 9
            sentence.removeSubrange(word)
        }
        var place: ReminderPlace?
        if let (found, range) = ReminderPlace.find(in: sentence) {
            place = found
            sentence.removeSubrange(range)
        }
        let lower = sentence.lowercased()
        let withMail = mailPhrases.contains { lower.contains($0) }
        let withPage = url == nil && !withMail && pagePhrases.contains { lower.contains($0) }

        let when = SpokenWhen.parse(sentence, now: now, calendar: calendar)
        let title = EventRequest.clean(when.rest)
        guard !title.isEmpty else { return nil }
        return ReminderRequest(title: title, due: when.date, hasTime: when.hasTime, list: list, priority: priority, recurrence: when.recurrence,
                               notes: notes, url: url, withPageInFront: withPage, withMailInFront: withMail, place: place)
    }
}

/// What is asked of the reminders, read without a model: "mes rappels",
/// "qu'est-ce que j'ai à faire aujourd'hui", "my reminders", "en retard".
public enum RemindersRequest: Equatable, Sendable {
    /// Overdue and due today.
    case today
    /// Overdue only.
    case overdue
    /// Everything not done.
    case all

    private static let todayPhrases: [[String]] = [
        ["a", "faire", "aujourd", "hui"], ["mes", "rappels"], ["mes", "taches"], ["mes", "todos"], ["ma", "todo"], ["my", "reminders"],
        ["my", "todos"], ["my", "tasks"], ["to", "do", "today"], ["todo", "today"], ["what", "do", "i", "have", "to", "do"],
        ["qu", "est", "ce", "que", "j", "ai", "a", "faire"]
    ]
    private static let overduePhrases: [[String]] = [["en", "retard"], ["overdue"], ["late"]]
    private static let allWords: Set<String> = ["tous", "toutes", "all", "every"]
    private static let fillers: Set<String> = [
        "c", "est", "quoi", "quels", "quelles", "sont", "qu", "ce", "que", "j", "ai", "a", "faire", "aujourd", "hui", "mes", "ma", "rappels",
        "taches", "todos", "todo", "my", "reminders", "tasks", "what", "do", "i", "have", "to", "today", "are", "show", "me", "montre", "moi",
        "les", "le", "la", "en", "retard", "overdue", "late", "s", "il", "y", "t", "please", "stp", "affiche", "liste", "list", "qui", "is",
        "what's", "which", "of"
    ]

    public static func parse(_ text: String) -> RemindersRequest? {
        let words = text.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        func has(_ phrase: [String]) -> Bool {
            phrase.count <= words.count && (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
        }
        guard todayPhrases.contains(where: has) || overduePhrases.contains(where: has) else { return nil }
        // Nothing else asked ("ajoute à mes rappels…" is a reminder to add).
        guard words.allSatisfy({ fillers.contains($0) || allWords.contains($0) }) else { return nil }
        if overduePhrases.contains(where: has) { return .overdue }
        if words.contains(where: allWords.contains) { return .all }
        return .today
    }
}

/// How reminders are grouped and told.
public enum Reminders {
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// ⌘K's Tomorrow and Next Week (its Monday): the day it goes to, at
    /// the time it had; one without a time goes to the day itself.
    public static func moved(_ item: ReminderItem, nextWeek: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let day = nextWeek
            ? calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? today
            : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        guard item.hasTime, let due = item.due else { return day }
        let time = calendar.dateComponents([.hour, .minute], from: due)
        return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    /// Raycast's order: overdue, today by morning, afternoon and tonight,
    /// tomorrow, later (by day), then without a date; the done ones last.
    public static func sections(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [(title: String, items: [ReminderItem])] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let after = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        func order(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.priority != b.priority ? (a.priority == 0 ? 10 : a.priority) < (b.priority == 0 ? 10 : b.priority) : a.title < b.title
            }
        }
        var order_: [String] = []
        var grouped: [String: [ReminderItem]] = [:]
        func add(_ title: String, _ item: ReminderItem) {
            if grouped[title] == nil { order_.append(title) }
            grouped[title, default: []].append(item)
        }
        let open = items.filter { !$0.isCompleted }.sorted(by: order)
        for item in open {
            guard let due = item.due else { continue }
            let dayOfDue = calendar.startOfDay(for: due)
            if item.hasTime ? due < now : dayOfDue < today {
                add("Overdue", item)
            } else if dayOfDue == today {
                let hour = item.hasTime ? calendar.component(.hour, from: due) : -1
                add(hour < 0 ? "Today" : hour < 12 ? "This Morning" : hour < 18 ? "This Afternoon" : "Tonight", item)
            } else if due < after, due >= tomorrow {
                add("Tomorrow", item)
            } else {
                add(dayTitle(due, now: now, calendar: calendar), item)
            }
        }
        // Today's groups in the day's order, whatever came first.
        let todayOrder = ["Overdue", "Today", "This Morning", "This Afternoon", "Tonight", "Tomorrow"]
        order_ = order_.enumerated().sorted { a, b in
            (todayOrder.firstIndex(of: a.element) ?? 50 + a.offset) < (todayOrder.firstIndex(of: b.element) ?? 50 + b.offset)
        }.map(\.element)
        for item in open where item.due == nil { add("No Date", item) }
        for item in items.filter(\.isCompleted).sorted(by: { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) {
            add("Completed", item)
        }
        return order_.map { ($0, grouped[$0] ?? []) }
    }

    /// "Thu 15 Oct", "Thu 15 Oct 2027".
    static func dayTitle(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "EEE d MMM" : "EEE d MMM yyyy", calendar: calendar).string(from: date)
    }

    /// "Today 09:00", "Tomorrow", "Overdue · Mon 12 Oct", "Thu 15 Oct 14:00".
    public static func when(_ item: ReminderItem, now: Date, calendar: Calendar = .current) -> String {
        guard let due = item.due else { return "" }
        let time = item.hasTime ? " " + formatter("HH:mm", calendar: calendar).string(from: due) : ""
        let today = calendar.startOfDay(for: now)
        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(due, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(due, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            day = dayTitle(due, now: now, calendar: calendar)
        }
        return day + time
    }

    /// What the menu bar counts: open, due today or overdue.
    public static func dueToday(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [ReminderItem] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return items.filter { !$0.isCompleted && ($0.due ?? .distantFuture) < tomorrow }
            .sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
    }

    /// The link back to a message in Mail, from its Message-ID.
    public static func mailLink(messageID: String) -> URL? {
        let id = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<> \n"))
        guard !id.isEmpty, let encoded = ("<" + id + ">").addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "@.-_"))) else {
            return nil
        }
        return URL(string: "message://" + encoded)
    }

    /// The card's list: "**Today**" then "- !! Appeler Paul · 09:00 · Perso".
    public static func markdown(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> String {
        let sections = self.sections(items, now: now, calendar: calendar).filter { $0.title != "Completed" }
        guard !sections.isEmpty else { return "Nothing to do." }
        return sections.map { section in
            (["**\(section.title)**"] + section.items.map { item in
                let marks = item.marks.isEmpty ? "" : "\(item.marks) "
                let due = when(item, now: now, calendar: calendar)
                return "- \(marks)\(item.title)" + (due.isEmpty ? "" : " · \(due)") + " · \(item.list)"
            }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

/// A place saved in Settings → Reminders, for "en arrivant au bureau".
public struct SavedPlace: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    /// Meters around it.
    public var radius: Double

    public init(id: UUID = UUID(), name: String, address: String, latitude: Double, longitude: Double, radius: Double = 150) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }

    /// Words that name the same place in French and English.
    private static let same: [Set<String>] = [["maison", "home", "chez moi"], ["bureau", "travail", "boulot", "work", "office"]]

    private static func folded(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
    }

    /// An address on the user's card in Contacts.
    public enum CardAddress: String, Sendable {
        case home, work
    }

    /// The card's address a said name means when no place is saved under
    /// it, as Apple's Reminders reads "when I get home": "maison", "home",
    /// "chez moi" its Home address; "bureau", "travail", "work" its Work one.
    public static func cardAddress(for said: String) -> CardAddress? {
        let name = folded(said)
        if same[0].contains(name) { return .home }
        if same[1].contains(name) { return .work }
        return nil
    }

    /// The saved place a said name means: the same name (accents and case
    /// aside), its other language ("home" for "Maison"), or its start.
    public static func match(_ said: String, in places: [SavedPlace]) -> SavedPlace? {
        let name = folded(said)
        if let exact = places.first(where: { folded($0.name) == name }) { return exact }
        if let group = same.first(where: { $0.contains(name) }), let other = places.first(where: { group.contains(folded($0.name)) }) { return other }
        return places.first { folded($0.name).hasPrefix(name) && name.count >= 3 }
    }
}
