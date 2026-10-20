import Foundation

/// How often something comes back: "tous les lundis", "every 2 weeks",
/// "en semaine".
public struct SpokenRecurrence: Equatable, Sendable {
    public enum Frequency: String, Sendable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    /// Calendar weekdays (1 Sunday … 7 Saturday) for a weekly one.
    public var weekdays: [Int]

    public init(_ frequency: Frequency, interval: Int = 1, weekdays: [Int] = []) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
    }

    /// "every day", "every 2 weeks on Monday", "every weekday".
    public var spoken: String {
        if frequency == .weekly, weekdays == [2, 3, 4, 5, 6] { return "every weekday" }
        let unit = switch frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let days = weekdays.compactMap { names.indices.contains($0 - 1) ? names[$0 - 1] : nil }
        let every = interval == 1 ? "every \(unit)" : "every \(interval) \(unit)s"
        if frequency == .weekly, !days.isEmpty {
            return interval == 1 ? "every " + days.joined(separator: ", ") : "\(every) on " + days.joined(separator: ", ")
        }
        return every
    }
}

/// When a sentence says something happens, read without a model, in French
/// and English: "demain à 9h", "jeudi prochain 14h30", "le 15 oct",
/// "15/10", "dans 2 heures", "ce soir", "tomorrow at 9am", "next monday",
/// "de 14h à 15h", "pendant 30 min", "tous les lundis", "every 2 weeks".
/// What is left is the rest of the sentence, as typed.
public struct SpokenWhen: Equatable, Sendable {
    /// When; nil when the sentence says no date or time.
    public var date: Date?
    /// A time was said (else the day alone).
    public var hasTime: Bool
    /// The end, when said: "de 14h à 15h", "pendant 30 min".
    public var end: Date?
    public var recurrence: SpokenRecurrence?
    /// The sentence without the words that said when, as typed.
    public var rest: String
    /// The hours a part of the day spans, when one was said and no time:
    /// "matin" 8–12, "après-midi" 12–18, "soir" 18–23.
    public var partHours: Range<Int>?

    public init(date: Date?, hasTime: Bool, end: Date? = nil, recurrence: SpokenRecurrence? = nil, rest: String, partHours: Range<Int>? = nil) {
        self.date = date
        self.hasTime = hasTime
        self.end = end
        self.recurrence = recurrence
        self.rest = rest
        self.partHours = partHours
    }

    // MARK: - Words

    private static let weekdayNames: [[String]] = [
        // Full names only: "mon" is also French ("mon frère").
        ["dimanche", "sunday"], ["lundi", "monday"], ["mardi", "tuesday"], ["mercredi", "wednesday"], ["jeudi", "thursday"],
        ["vendredi", "friday"], ["samedi", "saturday"]
    ]
    private static let monthNames: [[String]] = [
        ["janvier", "janv", "january", "jan"], ["fevrier", "fevr", "fev", "february", "feb"], ["mars", "march", "mar"],
        ["avril", "avr", "april", "apr"], ["mai", "may"], ["juin", "june", "jun"], ["juillet", "juil", "july", "jul"],
        ["aout", "august", "aug"], ["septembre", "sept", "september", "sep"], ["octobre", "oct", "october"],
        ["novembre", "nov", "november"], ["decembre", "dec", "december"]
    ]
    private static let units: [(names: Set<String>, component: Calendar.Component, seconds: Int)] = [
        (["min", "mins", "minute", "minutes", "mn", "m"], .minute, 60),
        (["h", "heure", "heures", "hour", "hours", "hr", "hrs"], .hour, 3_600),
        (["jour", "jours", "day", "days", "j"], .day, 86_400),
        (["semaine", "semaines", "week", "weeks"], .weekOfYear, 7 * 86_400),
        (["mois", "month", "months"], .month, 30 * 86_400)
    ]
    private static let parts: [(words: [String], hour: Int)] = [
        (["matin"], 9), (["morning"], 9), (["midi"], 12), (["noon"], 12), (["apres", "midi"], 14), (["apres-midi"], 14),
        (["aprem"], 14), (["afternoon"], 14), (["soir"], 19), (["soiree"], 19), (["evening"], 19), (["tonight"], 19), (["minuit"], 0),
        (["midnight"], 0)
    ]
    private static let numbers: [String: Int] = [
        "un": 1, "une": 1, "a": 1, "an": 1, "one": 1, "deux": 2, "two": 2, "trois": 3, "three": 3, "quatre": 4, "four": 4,
        "cinq": 5, "five": 5, "six": 6, "dix": 10, "ten": 10, "quinze": 15, "fifteen": 15, "vingt": 20, "twenty": 20, "trente": 30, "thirty": 30
    ]

    private struct Token {
        let original: String
        let folded: String
        var used = false
        /// "d'", "l'": the next word follows without a space.
        var glued = false
    }

    private struct Time: Equatable {
        var hour: Int
        var minute: Int
        /// "at 5" (no h, no am/pm): 17:00 when 5:00 is gone.
        var loose = false
    }

    // MARK: - Reading

    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> SpokenWhen {
        var tokens = tokenize(text)
        var day: Date?
        var time: Time?
        var endTime: Time?
        var relative: (component: Calendar.Component, value: Int)?
        var duration: Int?
        var recurrence: SpokenRecurrence?
        var partHour: Int?
        let today = calendar.startOfDay(for: now)

        func word(_ index: Int) -> String { tokens.indices.contains(index) && !tokens[index].used ? tokens[index].folded : "" }
        func use(_ range: Range<Int>) { for index in range where tokens.indices.contains(index) { tokens[index].used = true } }
        func matches(_ phrase: [String], at index: Int) -> Bool {
            phrase.enumerated().allSatisfy { word(index + $0.offset) == $0.element }
        }
        func weekday(_ text: String) -> Int? { weekdayNames.firstIndex { $0.contains(text) }.map { $0 + 1 } }
        func month(_ text: String) -> Int? { monthNames.firstIndex { $0.contains(text) }.map { $0 + 1 } }
        func number(_ text: String) -> Int? { Int(text) ?? numbers[text] }
        func unit(_ text: String) -> (component: Calendar.Component, seconds: Int)? {
            units.first { $0.names.contains(text) }.map { ($0.component, $0.seconds) }
        }
        func dayOffset(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        /// The next such weekday, tomorrow at the earliest.
        func next(_ weekday: Int, allowToday: Bool = false) -> Date {
            let current = calendar.component(.weekday, from: today)
            var ahead = (weekday - current + 7) % 7
            if ahead == 0, !allowToday { ahead = 7 }
            return dayOffset(ahead)
        }
        /// "9h", "9h30", "14:15", "9am", "9:30pm": a time in one token.
        func clock(_ text: String) -> Time? {
            let patterns = [#"^(\d{1,2})h(\d{2})?$"#, #"^(\d{1,2}):(\d{2})$"#, #"^(\d{1,2})(?::(\d{2}))?(am|pm)$"#]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
                func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
                guard var hour = group(1).flatMap(Int.init) else { continue }
                let minute = group(2).flatMap(Int.init) ?? 0
                if let meridiem = match.numberOfRanges > 3 ? group(3) : nil {
                    if meridiem == "pm", hour < 12 { hour += 12 }
                    if meridiem == "am", hour == 12 { hour = 0 }
                }
                guard hour < 24, minute < 60 else { continue }
                return Time(hour: hour, minute: minute)
            }
            return nil
        }
        /// A time over one to three tokens at `index`: "9h30", "9 h 30",
        /// "9 am", "14:00"; how many tokens it took.
        func timeAt(_ index: Int, loose: Bool) -> (Time, Int)? {
            let first = word(index)
            if let time = clock(first) { return (time, 1) }
            guard let hour = Int(first), hour < 24 else { return nil }
            if word(index + 1) == "h" {
                if let minute = Int(word(index + 2)), minute < 60 { return (Time(hour: hour, minute: minute), 3) }
                return (Time(hour: hour, minute: 0), 2)
            }
            if word(index + 1) == "am" || word(index + 1) == "pm", hour <= 12 {
                let shifted = word(index + 1) == "pm" ? (hour == 12 ? 12 : hour + 12) : (hour == 12 ? 0 : hour)
                return (Time(hour: shifted, minute: 0), 2)
            }
            return loose ? (Time(hour: hour, minute: 0, loose: true), 1) : nil
        }

        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            let current = word(index)
            guard !current.isEmpty else { continue }

            // Recurrence: "tous les lundis", "toutes les 2 semaines", "chaque mois",
            // "every day", "every 2 weeks", "daily", "en semaine", "weekdays".
            if recurrence == nil {
                var length = 0
                if ["tous", "toutes"].contains(current), word(index + 1) == "les" { length = 2 }
                if current == "chaque" || current == "every" { length = 1 }
                if length > 0 {
                    var cursor = index + length
                    var interval = 1
                    if let count = Int(word(cursor)) {
                        interval = count
                        cursor += 1
                    }
                    let what = word(cursor)
                    var found: SpokenRecurrence?
                    if let unit = unit(what), unit.component != .minute, unit.component != .hour {
                        found = SpokenRecurrence(unit.component == .day ? .daily : unit.component == .weekOfYear ? .weekly : .monthly, interval: interval)
                    } else if ["an", "ans", "annee", "annees", "year", "years"].contains(what) {
                        found = SpokenRecurrence(.yearly, interval: interval)
                    } else if what == "weekday" || what == "weekdays" {
                        found = SpokenRecurrence(.weekly, weekdays: [2, 3, 4, 5, 6])
                    } else if let named = weekday(what.hasSuffix("s") && weekday(what) == nil ? String(what.dropLast()) : what) {
                        found = SpokenRecurrence(.weekly, interval: interval, weekdays: [named])
                        if day == nil { day = next(named, allowToday: true) }
                    }
                    if let found {
                        recurrence = found
                        use(index..<(cursor + 1))
                        index = cursor
                        continue
                    }
                }
                let single: [String: SpokenRecurrence] = [
                    "daily": .init(.daily), "quotidien": .init(.daily), "quotidiennement": .init(.daily), "weekly": .init(.weekly),
                    "hebdo": .init(.weekly), "hebdomadaire": .init(.weekly), "monthly": .init(.monthly), "mensuel": .init(.monthly),
                    "mensuellement": .init(.monthly), "yearly": .init(.yearly), "annually": .init(.yearly), "annuel": .init(.yearly),
                    "weekdays": .init(.weekly, weekdays: [2, 3, 4, 5, 6])
                ]
                if let found = single[current] {
                    recurrence = found
                    use(index..<(index + 1))
                    continue
                }
                if current == "en", word(index + 1) == "semaine" {
                    recurrence = SpokenRecurrence(.weekly, weekdays: [2, 3, 4, 5, 6])
                    use(index..<(index + 2))
                    continue
                }
            }

            // In a while: "dans 10 min", "dans 2 heures", "in 3 days", "in an hour".
            if relative == nil, current == "dans" || current == "in", let amount = number(word(index + 1)), let found = unit(word(index + 2)) {
                relative = (found.component, amount)
                use(index..<(index + 3))
                continue
            }
            if relative == nil, current == "dans" || current == "in",
               let match = word(index + 1).range(of: #"^(\d+)(min|mn|h|j)$"#, options: .regularExpression).map({ _ in word(index + 1) }) {
                let digits = Int(match.prefix { $0.isNumber }) ?? 0
                let suffix = String(match.drop { $0.isNumber })
                if let found = unit(suffix) {
                    relative = (found.component, digits)
                    use(index..<(index + 2))
                    continue
                }
            }

            // How long: "pendant 30 min", "for 1 hour", "durant 2 heures".
            if duration == nil, ["pendant", "for", "durant"].contains(current), let amount = number(word(index + 1)),
               let found = unit(word(index + 2)), found.component == .minute || found.component == .hour {
                duration = amount * found.seconds
                use(index..<(index + 3))
                continue
            }

            // From… to…: "de 14h à 15h", "from 2pm to 3pm", "14h-15h".
            if time == nil, current == "de" || current == "from" || current == "entre" || current == "between",
               let (start, length) = timeAt(index + 1, loose: false) ?? timeAt(index + 1, loose: true) {
                let link = word(index + 1 + length)
                if ["a", "to", "et", "and", "-"].contains(link), let (finish, finishLength) = timeAt(index + 2 + length, loose: true) {
                    time = start
                    endTime = finish
                    use(index..<(index + 2 + length + finishLength))
                    continue
                }
            }
            if time == nil, let match = current.range(of: #"^(\d{1,2}(?:h\d{0,2}|:\d{2})?)-(\d{1,2}(?:h\d{0,2}|:\d{2})?)$"#, options: .regularExpression) {
                let pieces = current[match].split(separator: "-").map(String.init)
                func read(_ piece: String) -> Time? { clock(piece) ?? Int(piece).flatMap { $0 < 24 ? Time(hour: $0, minute: 0) : nil } }
                if pieces.count == 2, let start = read(pieces[0]), let finish = read(pieces[1]) {
                    time = start
                    endTime = finish
                    use(index..<(index + 1))
                    continue
                }
            }

            // Days.
            if day == nil {
                if current == "aujourd'hui" || current == "today" {
                    day = today
                    use(index..<(index + 1))
                    continue
                }
                if current == "apres-demain" || matches(["apres", "demain"], at: index) {
                    day = dayOffset(2)
                    use(index..<(index + (current == "apres-demain" ? 1 : 2)))
                    continue
                }
                if matches(["day", "after", "tomorrow"], at: index) {
                    day = dayOffset(2)
                    use(index..<(index + 3))
                    continue
                }
                if current == "demain" || current == "tomorrow" {
                    day = dayOffset(1)
                    use(index..<(index + 1))
                    continue
                }
                if matches(["la", "semaine", "prochaine"], at: index) || matches(["semaine", "prochaine"], at: index) || matches(["next", "week"], at: index) {
                    day = next(2)
                    let length = current == "la" ? 3 : 2
                    use(index..<(index + length))
                    continue
                }
                // "lundi", "lundi prochain", "next monday", "on monday", "ce lundi".
                let lead = ["next", "on", "ce", "this"].contains(current) ? 1 : 0
                if let named = weekday(word(index + lead)), lead == 0 || weekday(current) == nil {
                    day = next(named)
                    var length = lead + 1
                    if ["prochain", "prochaine"].contains(word(index + length)) { length += 1 }
                    use(index..<(index + length))
                    continue
                }
                // "le 15", "le 15 octobre", "15 oct", "15 octobre 2027", "october 15", "the 15th".
                let dayLead = ["le", "the", "on"].contains(current) ? 1 : 0
                let dayText = word(index + dayLead).replacingOccurrences(of: #"(st|nd|rd|th|er)$"#, with: "", options: .regularExpression)
                if let number = Int(dayText), (1...31).contains(number) {
                    let monthIndex = month(word(index + dayLead + 1))
                    if monthIndex != nil || dayLead == 1, word(index + dayLead + 1) != "h", clock(word(index + dayLead)) == nil {
                        var length = dayLead + 1 + (monthIndex == nil ? 0 : 1)
                        var year: Int?
                        if monthIndex != nil, let written = Int(word(index + length)), written >= 2000, written < 2100 {
                            year = written
                            length += 1
                        }
                        if let date = Self.date(day: number, month: monthIndex, year: year, today: today, calendar: calendar) {
                            day = date
                            use(index..<(index + length))
                            continue
                        }
                    }
                }
                if let monthIndex = month(current), current.count >= 3,
                   let number = Int(word(index + 1).replacingOccurrences(of: #"(st|nd|rd|th)$"#, with: "", options: .regularExpression)),
                   (1...31).contains(number), let date = Self.date(day: number, month: monthIndex, year: nil, today: today, calendar: calendar) {
                    day = date
                    use(index..<(index + 2))
                    continue
                }
                // "15/10", "15/10/2027".
                if let match = current.range(of: #"^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$"#, options: .regularExpression) {
                    let pieces = current[match].split(separator: "/").compactMap { Int($0) }
                    let year = pieces.count == 3 ? (pieces[2] < 100 ? 2000 + pieces[2] : pieces[2]) : nil
                    if pieces.count >= 2, let date = Self.date(day: pieces[0], month: pieces[1], year: year, today: today, calendar: calendar) {
                        day = date
                        use(index..<(index + 1))
                        continue
                    }
                }
            }

            // Parts of the day: "ce soir", "demain matin", "this afternoon", "à midi".
            if partHour == nil {
                let lead = ["ce", "cet", "cette", "this", "le", "la", "l'", "in", "the", "a"].contains(current) ? 1 : 0
                if let part = parts.first(where: { matches($0.words, at: index + lead) }) {
                    // "a" alone before a part ("à midi") only with midi/minuit.
                    if lead == 0 || current != "a" || part.hour == 12 || part.hour == 0 {
                        partHour = part.hour
                        if current == "ce" || current == "cet" || current == "cette" || current == "this" || part.words == ["tonight"] {
                            if day == nil { day = today }
                        }
                        use(index..<(index + lead + part.words.count))
                        continue
                    }
                }
            }

            // A time: "à 9h", "9h30", "at 9am", "vers 14h", "at 5".
            if time == nil {
                let lead = ["a", "at", "vers", "around", "des", "by", "pour"].contains(current) ? 1 : 0
                // A bare hour only after "à", "at", "vers", "around" (not
                // the article "a": "buy a 2 liter bottle").
                let loose = lead == 1 && ["à", "at", "vers", "around"].contains(tokens[index].original.lowercased())
                if let (found, length) = timeAt(index + lead, loose: loose) {
                    time = found
                    use(index..<(index + lead + length))
                    continue
                }
            }
        }

        // Together.
        var date: Date?
        var hasTime = false
        if let relative {
            date = calendar.date(byAdding: relative.component, value: relative.value, to: now)
            hasTime = relative.component == .minute || relative.component == .hour
            if !hasTime, let base = date {
                date = calendar.startOfDay(for: base)
                if let time { date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base); hasTime = true }
            }
        } else if let hour = time.map({ ($0.hour, $0.minute, $0.loose) }) ?? partHour.map({ ($0, 0, false) }) {
            var (hourValue, minute, loose) = hour
            // "ce soir à 8h": evening hours.
            if let partHour, partHour >= 14, hourValue < 12, time != nil { hourValue += 12 }
            let base = day ?? today
            date = calendar.date(bySettingHour: hourValue, minute: minute, second: 0, of: base)
            hasTime = true
            if day == nil, let candidate = date, candidate <= now {
                // "à 5" at 16:00 is 17:00; an exact time gone is tomorrow.
                if loose, hourValue < 12, let later = calendar.date(byAdding: .hour, value: 12, to: candidate), later > now {
                    date = later
                } else {
                    date = calendar.date(byAdding: .day, value: 1, to: candidate)
                }
            }
        } else if let day {
            date = day
        } else if recurrence != nil {
            date = today
        }
        var end: Date?
        if let start = date, hasTime {
            if let endTime, let finish = calendar.date(bySettingHour: endTime.hour, minute: endTime.minute, second: 0, of: start) {
                end = finish > start ? finish : calendar.date(byAdding: .day, value: 1, to: finish)
            } else if let duration {
                end = start.addingTimeInterval(TimeInterval(duration))
            }
        }
        var rest = ""
        var glue = false
        for token in tokens where !token.used {
            rest += (rest.isEmpty || glue ? "" : " ") + token.original
            glue = token.glued
        }
        var partHours: Range<Int>?
        if time == nil, relative == nil, let partHour {
            partHours = switch partHour {
            case 9: 8..<12
            case 12: 12..<14
            case 14: 12..<18
            case 19: 18..<23
            default: partHour..<(partHour + 1)
            }
        }
        return SpokenWhen(date: date, hasTime: hasTime, end: end, recurrence: recurrence, rest: rest, partHours: partHours)
    }

    /// That day this year (next year when it is gone), or that month's
    /// next such day.
    private static func date(day: Int, month: Int?, year: Int?, today: Date, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month], from: today)
        parts.day = day
        if let month { parts.month = month }
        if let year { parts.year = year }
        guard let date = calendar.date(from: parts), calendar.component(.day, from: date) == day else { return nil }
        if year == nil, date < today {
            return calendar.date(byAdding: month == nil ? .month : .year, value: 1, to: date)
        }
        return date
    }

    /// Words split as they are said: "d'appeler" is "d'" and "appeler",
    /// "aujourd'hui" stays one; punctuation around a word goes.
    private static func tokenize(_ text: String) -> [Token] {
        let normalized = text.replacingOccurrences(of: "’", with: "'")
        var tokens: [Token] = []
        for piece in normalized.split(whereSeparator: \.isWhitespace) {
            var word = String(piece).trimmingCharacters(in: CharacterSet(charactersIn: ",.;!?()\"“”«»"))
            if word.isEmpty { continue }
            let folded = word.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            if folded != "aujourd'hui", let apostrophe = word.firstIndex(of: "'"), word.distance(from: word.startIndex, to: apostrophe) <= 2,
               word.index(after: apostrophe) < word.endIndex {
                let head = String(word[...apostrophe])
                tokens.append(Token(original: head, folded: head.lowercased(), glued: true))
                word = String(word[word.index(after: apostrophe)...])
            }
            tokens.append(Token(original: word, folded: word.lowercased().folding(options: .diacriticInsensitive, locale: nil)))
        }
        return tokens
    }
}
