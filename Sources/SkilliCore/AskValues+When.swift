import Foundation

/// When a reminder or an event is, what it says, and the rest Ask adds it
/// with, read by the decision model, never by a regex ("rappelle-moi dans
/// une heure trente…" read as one hour). TypeSafe's date-extraction
/// pattern: a date is asked as parts whose split is unique (the day, a
/// weekday and which week, a month and a day of the month, an hour and its
/// minutes, a part of the day), a delay as one of the lengths; code puts
/// them together and the least sure part used says how sure the date is.
extension AskValues {
    // MARK: - Words of the request

    /// The request's words as said, for picking what a reminder or an event
    /// says among them: split at spaces, an elided word ("d'", "l'", "qu'")
    /// a word of its own, punctuation around a word left out.
    public static func words(of request: String, limit: Int = 40) -> [String] {
        let around = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’-#@"))
        var words: [String] = []
        for raw in request.split(whereSeparator: \.isWhitespace) {
            var word = raw.trimmingCharacters(in: around)
            while let apostrophe = word.firstIndex(where: { $0 == "'" || $0 == "’" }),
                  word.distance(from: word.startIndex, to: apostrophe) <= 2,
                  word.index(after: apostrophe) < word.endIndex {
                words.append(String(word[...apostrophe]))
                word = String(word[word.index(after: apostrophe)...])
            }
            if !word.isEmpty { words.append(word) }
            if words.count >= limit { break }
        }
        return Array(words.prefix(limit))
    }

    /// Words put back together, an elided one stuck to the next ("l'agenda").
    static func joined(_ words: ArraySlice<String>) -> String {
        var text = ""
        for word in words {
            if !text.isEmpty, !(text.hasSuffix("'") || text.hasSuffix("’")) { text += " " }
            text += word
        }
        return text
    }

    /// Every run of 1 to `longest` of the request's words, as said, once
    /// each, shortest first, 254 at most: a name or a short phrase picked
    /// whole ("Paul Durand", "résume mes PR"). Asked as a first and a last
    /// word, both models often stopped at the first ("Paul").
    public static func phrases(of words: [String], longest: Int = 6) -> [String] {
        var phrases: [String] = []
        var seen = Set<String>()
        for length in 1...max(1, longest) {
            for start in words.indices where start + length <= words.count {
                let phrase = joined(words[start..<start + length])
                if seen.insert(phrase.lowercased()).inserted { phrases.append(phrase) }
                if phrases.count == 254 { return phrases }
            }
        }
        return phrases
    }

    /// A phrase of the request picked whole, or none.
    static func phraseQuestion(name: String, instructions: String, phrases: [String], none: String) -> Question {
        Question(name: name, instructions: instructions,
                 options: phrases.enumerated().map { Option("phrase \($0.offset)", $0.element) } + [Option("none", none)])
    }

    /// The phrase picked (or said in the card), and how sure; nil for none.
    static func phrase(_ answers: [String: Answer], _ name: String, phrases: [String]) -> (text: String, confidence: Double)? {
        if let answer = answers[name], let said = answer.said { return (said, answer.confidence) }
        guard let answer = answers[name], answer.choice.hasPrefix("phrase "), let index = Int(answer.choice.dropFirst(7)),
              phrases.indices.contains(index) else { return nil }
        return (phrases[index], answer.confidence)
    }

    /// The request's words as options, each shown in its place.
    static func wordOptions(_ words: [String], none: String) -> [Option] {
        words.indices.map { index in
            let before = joined(words[max(0, index - 3)..<index])
            let after = joined(words[(index + 1)..<min(words.count, index + 4)])
            return Option("word \(index)", "“\(words[index])”, in “\(before) [\(words[index])] \(after)”")
        } + [Option("none", none)]
    }

    /// Where the first and the last word picked are (`<prefix>_start`,
    /// `<prefix>_end`), and how sure.
    static func span(_ answers: [String: Answer], _ prefix: String, words: [String]) -> (range: ClosedRange<Int>, confidence: Double)? {
        guard let start = answers[prefix + "_start"], let end = answers[prefix + "_end"],
              start.choice.hasPrefix("word "), end.choice.hasPrefix("word "),
              let first = Int(start.choice.dropFirst(5)), let last = Int(end.choice.dropFirst(5)),
              words.indices.contains(first), words.indices.contains(last), first <= last else { return nil }
        return (first...last, min(start.confidence, end.confidence))
    }

    /// The words between the first and the last picked, and how sure.
    static func picked(_ answers: [String: Answer], _ prefix: String, words: [String]) -> (text: String, confidence: Double)? {
        span(answers, prefix, words: words).map { (joined(words[$0.range]), $0.confidence) }
    }

    /// What a reminder or an event says, picked as its first and its last
    /// word among the request's: selected, never written by the model.
    /// The words saying when are picked too, and left out of it when they
    /// fall inside ("rdv demain à 14h avec Paul" says "Rdv avec Paul").
    /// `thing`: "the reminder", "the event".
    public static func titleQuestions(words: [String], thing: String, examples: String) -> [Question] {
        let options = wordOptions(words, none: "It says nothing \(thing) is about")
        let whenExamples = "rappelle-moi d'appeler Paul demain à 9h → “demain” to “9h”; crée un rdv demain à 14h avec Paul → “demain” to “14h”; réunion jeudi de 14h à 15h30 → “jeudi” to “15h30”; dans une heure trente → “dans” to “trente”."
        return [
            Question(name: "title_start", instructions: "What should \(thing) say, in the request's own words? Its first word: the verb right after “rappelle-moi de”, “remind me to”, “n'oublie pas de” when there is one (remind me to buy bread → “buy”, never “bread”), the kind of event when it names one; never the words asking to add it (crée, ajoute, add, schedule, rappelle-moi). \(examples) Words saying where, how often, which list or calendar, or how important are not part of it.",
                     options: options),
            Question(name: "title_end", instructions: "What should \(thing) say, in the request's own words? Its last word. \(examples) Words saying where, how often, which list or calendar, or how important are not part of it.",
                     options: options),
            Question(name: "when_words_start", instructions: "Which words of the request say when (the day, the time, the delay)? The first of them. \(whenExamples) None when nothing says when.",
                     options: wordOptions(words, none: "Nothing says when")),
            Question(name: "when_words_end", instructions: "Which words of the request say when (the day, the time, the delay)? The last of them. \(whenExamples) None when nothing says when.",
                     options: wordOptions(words, none: "Nothing says when"))
        ]
    }

    /// The words picked, without those saying when, its little words at
    /// the ends dropped and its first letter up; how sure.
    public static func title(_ answers: [String: Answer], words: [String]) -> (title: String, confidence: Double)? {
        // Said in the card: already read from the answer's own words.
        if let start = answers["title_start"], let said = start.said { return (said, start.confidence) }
        guard let title = span(answers, "title", words: words) else { return nil }
        var kept = Array(title.range)
        var sure = title.confidence
        if let when = span(answers, "when_words", words: words), kept.contains(where: when.range.contains) {
            kept.removeAll(where: when.range.contains)
            sure = min(sure, when.confidence)
        }
        let text = EventRequest.clean(joined(ArraySlice(kept.map { words[$0] })))
        return text.isEmpty ? nil : (text, sure)
    }

    // MARK: - When

    static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    static let whenMode = Question(
        name: "when",
        instructions: "Does the request say when: a day or a time (demain, jeudi à 9h, le 12 mars, ce soir, à 18h, tomorrow at 9am), or a delay from now (dans 20 minutes, dans une heure trente, in 2 hours, dans 3 jours)?",
        options: [
            Option("at", "A day or a time: demain, jeudi à 9h, le 12 mars, ce soir, à 18h"),
            Option("in", "A delay from now: dans 20 minutes, dans une heure trente, in 2 hours"),
            Option("none", "Neither: no day, no time, no delay")
        ])

    static let day = Question(
        name: "day",
        instructions: "Which day does the request say? aujourd'hui, ce soir, today → today; demain, tomorrow → tomorrow; après-demain → after tomorrow; jeudi, next Friday, lundi prochain → a weekday; le 12 mars, le 3, March 12th → a date. Only a time (à 18h) → none.",
        options: [
            Option("today", "Today: aujourd'hui, ce soir, ce matin, today, tonight"),
            Option("tomorrow", "Tomorrow: demain, tomorrow"),
            Option("after tomorrow", "The day after tomorrow: après-demain"),
            Option("weekday", "A day of the week: jeudi, lundi prochain, next Friday"),
            Option("date", "A date: le 12 mars, le 3, March 12th, 15/10"),
            none
        ])

    static let weekday = Question(
        name: "weekday",
        instructions: "The day of the week the request says: jeudi, jeudi prochain → thursday; next Monday → monday; none when it names none.",
        options: weekdayNames.map { Option($0, $0.capitalized) } + [none])

    static let week = Question(
        name: "week",
        instructions: "Which week that day of the week is in: the coming one (jeudi, jeudi prochain, this Thursday, next Thursday: the first Thursday from today), or the following week (jeudi de la semaine prochaine, Thursday next week, jeudi en huit).",
        options: [
            Option("coming", "The first such day from today: jeudi, jeudi prochain, this Thursday, next Thursday"),
            Option("following week", "That day of next week: la semaine prochaine, next week, en huit"),
            none
        ])

    static let month = Question(
        name: "month",
        instructions: "The month of the date the request says: le 12 mars → march; 15/10 → october; none when it says no month (le 3).",
        options: monthNames.map { Option($0, $0.capitalized) } + [none])

    static let dayOfMonth = Question(
        name: "day_of_month",
        instructions: "The day of the month of the date the request says: le 12 mars → 12; le 1er → 1; 15/10 → 15; none when it says no date.",
        options: (1...31).map { Option("\($0)", "the \($0)") } + [none])

    static let hour = Question(
        name: "hour",
        instructions: "The hour it starts or is due, on a 24-hour clock, as meant: à 9h, 9am → 9; à 14h30, 2:30pm → 14; de 14h à 15h30 → 14; ce soir à 8h, 8pm → 20; à midi → 12; à minuit → 0. None when it says no time (demain, ce soir alone).",
        options: (0...23).map { Option("\($0)", "\($0) h") } + [none])

    static let minute = Question(
        name: "minute",
        instructions: "The minutes of the time it starts or is due: à 14h30 → 30; 9h15, a quarter past nine → 15; à 9h, 9am → 0; de 14h à 15h30 → 0 (it starts at 14:00); none when it says no time.",
        options: (0...59).map { Option("\($0)", ":\(String(format: "%02d", $0))") } + [none])

    static let partOfDay = Question(
        name: "part_of_day",
        instructions: "A part of the day the request says without a time: demain matin → morning; à midi → noon; cet après-midi → afternoon; ce soir, tonight → evening; none when it says a time or no part of the day.",
        options: [
            Option("morning", "The morning: matin, morning"),
            Option("noon", "Noon: midi, noon"),
            Option("afternoon", "The afternoon: après-midi, afternoon"),
            Option("evening", "The evening: ce soir, soirée, tonight, evening"),
            none
        ])

    static let delay = lengthQuestion(
        name: "delay",
        instructions: "In how long from now? Read the whole delay, hours and minutes together: dans une heure trente, in an hour and a half → 1 h 30; dans 20 minutes → 20 min; dans un quart d'heure → 15 min; dans 2 jours → 48 h. None when it says no delay.")

    /// The questions that read when.
    public static let whenQuestions = [whenMode, day, weekday, week, month, dayOfMonth, hour, minute, partOfDay, delay]

    /// What the answers say: a date, whether a time was said, how sure;
    /// `date` nil when the request says no day, time or delay. Nil when a
    /// part needed is missing.
    public static func when(_ answers: [String: Answer], now: Date = .now, calendar: Calendar = .current)
        -> (date: Date?, hasTime: Bool, confidence: Double)? {
        guard let mode = answers[whenMode.name] else { return nil }
        var parts = [mode.confidence]
        switch mode.choice {
        case "none":
            return (nil, false, mode.confidence)
        case "in":
            guard let length = answers[delay.name], let seconds = secondsByLength[length.choice] else { return nil }
            return (now.addingTimeInterval(TimeInterval(seconds)), true, min(mode.confidence, length.confidence))
        case "at":
            break
        default:
            return nil
        }

        // The time: an hour (and its minutes), else a part of the day.
        var time: (hour: Int, minute: Int)?
        if let hourAnswer = answers[hour.name], let hourValue = Int(hourAnswer.choice) {
            parts.append(hourAnswer.confidence)
            var minuteValue = 0
            if let minuteAnswer = answers[minute.name], let value = Int(minuteAnswer.choice) {
                minuteValue = value
                parts.append(minuteAnswer.confidence)
            }
            time = (hourValue, minuteValue)
        } else if let part = answers[partOfDay.name], let hourValue = ["morning": 9, "noon": 12, "afternoon": 14, "evening": 19][part.choice] {
            parts.append(part.confidence)
            time = (hourValue, 0)
        }

        let today = calendar.startOfDay(for: now)
        func at(_ day: Date) -> Date {
            guard let time else { return day }
            return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
        }
        let dayAnswer = answers[day.name]
        var date: Date
        switch dayAnswer?.choice ?? "none" {
        case "today":
            date = at(today)
        case "tomorrow":
            date = at(calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        case "after tomorrow":
            date = at(calendar.date(byAdding: .day, value: 2, to: today) ?? today)
        case "weekday":
            guard let named = answers[weekday.name], let index = weekdayNames.firstIndex(of: named.choice) else { return nil }
            parts.append(named.confidence)
            let following = answers[week.name]?.choice == "following week"
            if let weekAnswer = answers[week.name], weekAnswer.choice != "none" { parts.append(weekAnswer.confidence) }
            if following {
                // That day of next week, weeks starting on Monday.
                var monday = calendar
                monday.firstWeekday = 2
                guard let thisWeek = monday.dateInterval(of: .weekOfYear, for: now)?.start,
                      let nextWeek = monday.date(byAdding: .day, value: 7, to: thisWeek) else { return nil }
                let offset = (index + 1 - 2 + 7) % 7
                date = at(monday.date(byAdding: .day, value: offset, to: nextWeek) ?? nextWeek)
            } else {
                // The first such day from today; today's when its time is
                // still ahead.
                let ahead = (index + 1 - calendar.component(.weekday, from: today) + 7) % 7
                date = at(calendar.date(byAdding: .day, value: ahead, to: today) ?? today)
                if ahead == 0, time == nil || date <= now { date = at(calendar.date(byAdding: .day, value: 7, to: today) ?? today) }
            }
        case "date":
            guard let dayNumber = answers[dayOfMonth.name], let number = Int(dayNumber.choice) else { return nil }
            parts.append(dayNumber.confidence)
            var components = calendar.dateComponents([.year, .month], from: today)
            let monthAnswer = answers[month.name]
            let namedMonth = monthAnswer.flatMap { monthNames.firstIndex(of: $0.choice) }
            if let namedMonth, let monthAnswer {
                components.month = namedMonth + 1
                parts.append(monthAnswer.confidence)
            }
            components.day = number
            guard var found = calendar.date(from: components), calendar.component(.day, from: found) == number else { return nil }
            // Already past: the next one (next month when no month was
            // said, else next year).
            if found < today {
                found = calendar.date(byAdding: namedMonth == nil ? .month : .year, value: 1, to: found) ?? found
            }
            date = at(found)
        default:
            // A time alone: today, or tomorrow once it has passed.
            guard time != nil else { return nil }
            date = at(today)
            if date <= now { date = at(calendar.date(byAdding: .day, value: 1, to: today) ?? today) }
        }
        if let dayAnswer, dayAnswer.choice != "none" { parts.append(dayAnswer.confidence) }
        return (date, time != nil, parts.min() ?? 0)
    }

    // MARK: - How often

    static let repeats = Question(
        name: "repeat",
        instructions: "Does the request say it comes back? tous les jours, every day → every day; en semaine, every weekday → every weekday; tous les lundis, chaque semaine → every week; toutes les deux semaines → every 2 weeks; tous les mois, le 5 de chaque mois → every month; tous les ans → every year; none when it happens once.",
        options: [
            Option("every day", "Every day: tous les jours, chaque jour, every day"),
            Option("every weekday", "Monday to Friday: en semaine, every weekday"),
            Option("every week", "Every week: tous les lundis, chaque semaine, every Monday"),
            Option("every 2 weeks", "Every other week: toutes les deux semaines, every 2 weeks"),
            Option("every month", "Every month: tous les mois, le 5 de chaque mois, monthly"),
            Option("every year", "Every year: tous les ans, every year"),
            Option("none", "Once")
        ])

    /// How often, and how sure; nil recurrence for once.
    public static func recurrence(_ answers: [String: Answer], weekdayOf date: Date?, calendar: Calendar = .current)
        -> (recurrence: SpokenRecurrence?, confidence: Double) {
        guard let answer = answers[repeats.name] else { return (nil, 1) }
        let weekday = date.map { calendar.component(.weekday, from: $0) }
        let recurrence: SpokenRecurrence? = switch answer.choice {
        case "every day": SpokenRecurrence(.daily)
        case "every weekday": SpokenRecurrence(.weekly, weekdays: [2, 3, 4, 5, 6])
        case "every week": SpokenRecurrence(.weekly, weekdays: weekday.map { [$0] } ?? [])
        case "every 2 weeks": SpokenRecurrence(.weekly, interval: 2, weekdays: weekday.map { [$0] } ?? [])
        case "every month": SpokenRecurrence(.monthly)
        case "every year": SpokenRecurrence(.yearly)
        default: nil
        }
        return (recurrence, answer.confidence)
    }

    // MARK: - Which one of theirs

    /// One of the user's lists, calendars or places by name, or none.
    public static func namedQuestion(name: String, instructions: String, names: [String]) -> Question {
        Question(name: name, instructions: instructions,
                 options: names.prefix(200).enumerated().map { Option("\(name) \($0.offset)", $0.element) } + [none])
    }

    /// The name picked, and how sure; nil for none.
    public static func named(_ answers: [String: Answer], _ name: String, names: [String]) -> (name: String, confidence: Double)? {
        guard let answer = answers[name], answer.choice.hasPrefix(name + " "),
              let index = Int(answer.choice.dropFirst(name.count + 1)), names.indices.contains(index) else { return nil }
        return (names[index], answer.confidence)
    }

    // MARK: - A reminder's own

    static let priority = Question(
        name: "priority",
        instructions: "How important does the request say it is? urgent, important, !!! → high; !! → medium; pas urgent, low priority, ! → low; none when it does not say.",
        options: [Option("high", "High: urgent, important, !!!"), Option("medium", "Medium: !!"), Option("low", "Low: pas urgent, low priority, !"), none])

    /// EventKit's priority: 1 high, 5 medium, 9 low, 0 none.
    public static func priority(_ answers: [String: Answer]) -> Int {
        ["high": 1, "medium": 5, "low": 9][answers[priority.name]?.choice ?? ""] ?? 0
    }

    static let placeWhen = Question(
        name: "place_when",
        instructions: "Should it ring at a place rather than at a time: when they arrive somewhere (en arrivant au bureau, quand j'arrive à la maison, when I get home) or when they leave (en partant du bureau, when I leave work)?",
        options: [Option("arriving", "When they arrive there"), Option("leaving", "When they leave there"), Option("none", "Not at a place")])

    /// The place's name as said ("bureau", "la maison", "salle de
    /// sport"): the reminders resolve it (a saved place, Home or Work on
    /// the user's card) or say it is unknown.
    static func placeQuestion(words: [String]) -> Question {
        phraseQuestion(name: "place",
                       instructions: "Which place should it ring at, in the request's own words? en arrivant au bureau → “bureau”; quand j'arrive à la maison → “maison”; when I get home → “home”; en partant de la salle de sport → “salle de sport”. None when it names no place.",
                       phrases: phrases(of: words, longest: 4), none: "It names no place")
    }

    static let attached = Question(
        name: "with",
        instructions: "Does it point at something on the screen to go with it: the page in front (cet article, ce lien, cette page, this page) or the mail in front (ce mail, this email)?",
        options: [Option("page", "The page in front: cet article, ce lien, cette page"), Option("mail", "The mail in front: ce mail, this email"), Option("none", "Neither")])

    /// The questions of a reminder: what it says, when, how often, how
    /// important, where, with what, on which list.
    public static func reminderQuestions(words: [String], lists: [String]) -> [Question] {
        reminderTitleQuestions(words: words)
            + whenQuestions + [repeats, priority, placeWhen, attached, placeQuestion(words: words)]
            + [namedQuestion(name: "list", instructions: "Which of their lists does the request name (#Courses, dans ma liste courses, on my Work list)? None when it names none.", names: lists)]
    }

    /// What a reminder says, as its first and its last word.
    static func reminderTitleQuestions(words: [String]) -> [Question] {
        titleQuestions(words: words, thing: "the reminder",
                       examples: "rappelle-moi d'appeler Paul demain à 9h → “appeler” to “Paul”; rappelle-moi d'acheter du pain en partant du bureau → “acheter” to “pain”; remind me to buy bread tomorrow → “buy” to “bread”; n'oublie pas de payer le loyer le 5 → “payer” to “loyer”.")
    }

    // MARK: - An event's own

    static let ends = Question(
        name: "ends",
        instructions: "Does the request say how long the event lasts (pendant 1h, for 30 minutes, bloque 2h) or when it ends (de 14h à 15h, until 6pm, jusqu'à 16h)?",
        options: [Option("length", "How long: pendant 1h, for 30 minutes, bloque 2h"), Option("time", "An end time: de 14h à 15h, jusqu'à 16h"), Option("none", "Neither")])

    static let lasts = lengthQuestion(
        name: "lasts",
        instructions: "How long does the event last? pendant une heure trente, for an hour and a half → 1 h 30; bloque 2h → 2 h; 30 minutes → 30 min. None when it does not say.")

    static let endHour = Question(
        name: "end_hour",
        instructions: "The hour the event ends, on a 24-hour clock: de 14h à 15h → 15; until 6pm → 18; jusqu'à midi → 12. None when it says no end time.",
        options: (0...23).map { Option("\($0)", "\($0) h") } + [none])

    static let endMinute = Question(
        name: "end_minute",
        instructions: "The minutes of the time the event ends: de 14h à 15h30 → 30; until 6pm → 0. None when it says no end time.",
        options: (0...59).map { Option("\($0)", ":\(String(format: "%02d", $0))") } + [none])

    static let alert = Question(
        name: "alert",
        instructions: "Does the request ask for an alert before the event? rappel 10 min avant, alert me 15 minutes before → 15 min; préviens-moi une heure avant → 1 h; la veille → 1 day; none when it does not.",
        options: [Option("0", "At the time it starts"), Option("5", "5 minutes before"), Option("10", "10 minutes before"), Option("15", "15 minutes before"),
                  Option("30", "30 minutes before"), Option("60", "1 hour before"), Option("120", "2 hours before"), Option("1440", "1 day before"), none])

    /// The questions of an event: what it is, when, how long, how often,
    /// an alert, in which calendar.
    public static func eventQuestions(words: [String], calendars: [String]) -> [Question] {
        titleQuestions(words: words, thing: "the event",
                       examples: "déjeuner avec Anna vendredi à 13h → “déjeuner” to “Anna”; réunion budget jeudi à 14h → “réunion” to “budget”; crée un rdv demain à 14h avec Paul → “rdv” to “Paul”; bloque 2h demain matin pour écrire → “écrire”; schedule lunch with Anna on Friday → “lunch” to “Anna”.")
            + whenQuestions + [ends, lasts, endHour, endMinute, repeats, alert]
            + [namedQuestion(name: "calendar", instructions: "Which of their calendars does the request name (#Perso, dans mon calendrier travail, on my Work calendar)? None when it names none.", names: calendars)]
    }

    /// When the event ends after `start`, and how sure: the length or the
    /// end time said, else an hour. Nil confidence when nothing was said.
    public static func eventEnd(_ answers: [String: Answer], start: Date, calendar: Calendar = .current) -> (end: Date, confidence: Double?) {
        switch answers[ends.name]?.choice {
        case "length":
            if let length = answers[lasts.name], let seconds = secondsByLength[length.choice], let mode = answers[ends.name] {
                return (start.addingTimeInterval(TimeInterval(seconds)), min(mode.confidence, length.confidence))
            }
        case "time":
            if let hourAnswer = answers[endHour.name], let hourValue = Int(hourAnswer.choice), let mode = answers[ends.name] {
                let minuteAnswer = answers[endMinute.name]
                let minuteValue = minuteAnswer.flatMap { Int($0.choice) } ?? 0
                if var end = calendar.date(bySettingHour: hourValue, minute: minuteValue, second: 0, of: start) {
                    if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
                    var parts = [mode.confidence, hourAnswer.confidence]
                    if let minuteAnswer, Int(minuteAnswer.choice) != nil { parts.append(minuteAnswer.confidence) }
                    return (end, parts.min())
                }
            }
        default:
            break
        }
        return (start.addingTimeInterval(3_600), nil)
    }

    /// Minutes before the event for its alert, nil for none.
    public static func alertMinutes(_ answers: [String: Answer]) -> Int? {
        answers[alert.name].flatMap { Int($0.choice) }
    }
}
