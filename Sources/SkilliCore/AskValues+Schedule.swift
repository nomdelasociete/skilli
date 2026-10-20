import Foundation

/// An ask on a schedule ("tous les lundis à 9h résume mes PR"), and the app
/// or process a request names ("kill creative cloud", "désinstalle
/// Slack"), read by the decision model, never by a regex.
extension AskValues {
    // MARK: - On a schedule

    /// What a scheduled request asks and when it comes back.
    public enum ScheduleAsk: Equatable, Sendable {
        /// Kept once the user says so: the card always asks first.
        case schedule(AskSchedule, ask: String)
        /// A reminder or an event for themselves, repeating: Calendar and
        /// Reminders take it, not the scheduler.
        case plans
        /// A part it needs was not read: asked in the card.
        case missing(Missing)
    }

    static let repeatKind = Question(
        name: "schedule_repeat",
        instructions: "How often should skil.li do it? tous les jours, every morning → every day; en semaine, every weekday, du lundi au vendredi → every weekday; le week-end → every weekend; tous les lundis, every Monday and Thursday → some days of the week; le 1er de chaque mois, every month on the 15th → every month.",
        options: [
            Option("every day", "Every day: tous les jours, chaque matin, every evening"),
            Option("every weekday", "Monday to Friday: en semaine, jours ouvrés, every weekday"),
            Option("every weekend", "Saturday and Sunday: le week-end, every weekend"),
            Option("some days", "Some days of the week: tous les lundis, every Monday and Thursday"),
            Option("every month", "A day of each month: le 1er de chaque mois, every month on the 15th"),
            Option("none", "It says no repeat")
        ])

    static let everyN = Question(
        name: "every_n",
        instructions: "Every how many days, weeks or months? tous les lundis → 1; toutes les deux semaines, every other week → 2; tous les trois jours → 3.",
        options: (1...4).map { Option("\($0)", $0 == 1 ? "Each time" : "Every \($0)") } + [none])

    /// The days of the week named, in the order said: three questions of
    /// one day each (or none). Asked as a yes or no per day, OpenAI
    /// Decisions added a day never said ("tous les lundis": Monday and
    /// Thursday).
    static func namedDay(_ index: Int) -> Question {
        let which = ["first", "second", "third"][index]
        return Question(name: "day_\(index + 1)",
                        instructions: "The \(which) day of the week the request names for it to come back on, none when it names fewer: tous les lundis → first monday, second none; every Monday and Thursday → first monday, second thursday; lundi, mercredi et vendredi → monday, wednesday, friday.",
                        options: weekdayNames.map { Option($0, $0.capitalized) } + [none])
    }

    static let runHour = Question(
        name: "hour",
        instructions: "At what hour should it run, on a 24-hour clock? à 9h → 9; at 8:30 → 8; à 18h30, 6:30pm → 18; none when it says no time (chaque soir, tous les lundis).",
        options: (0...23).map { Option("\($0)", "\($0) h") } + [none])

    static let runMinute = Question(
        name: "minute",
        instructions: "The minutes of the time it should run: at 8:30 → 30; à 9h → 0; none when it says no time.",
        options: (0...59).map { Option("\($0)", ":\(String(format: "%02d", $0))") } + [none])

    static let isReminder = Question(
        name: "is_reminder",
        instructions: "Is it a reminder or an event for themselves, something they will do (rappelle-moi de sortir les poubelles tous les lundis, n'oublie pas de payer le loyer, remind me every Monday to…, a meeting every Tuesday), rather than something skil.li should do, write, send or tell them each time (résume mes PR, envoie-moi le point, tell me my day, check my mail)?",
        options: [Option("yes", "A reminder or an event for themselves: they do it"), Option("no", "skil.li does, writes, sends or tells it each time")])

    /// The questions of a request on a schedule.
    public static func scheduleQuestions(words: [String]) -> [Question] {
        [repeatKind, everyN, dayOfMonth, runHour, runMinute, partOfDay, isReminder] + (0..<3).map(namedDay) + [scheduledAskQuestion(words: words)]
    }

    /// What skil.li does each time, as a phrase of `words` (the request's,
    /// or the answer's in the card).
    static func scheduledAskQuestion(words: [String]) -> Question {
        phraseQuestion(name: "ask",
                       instructions: "What should skil.li do each time, in the request's own words, without the words saying when? tous les lundis à 9h résume mes PR → “résume mes PR”; every weekday at 8:30 tell me my day → “tell me my day”; le 1er de chaque mois envoie-moi le point → “envoie-moi le point” (the whole action, with what it is about); est-ce que tu pourrais me faire un résumé de mes mails chaque soir → “me faire un résumé de mes mails”.",
                       phrases: phrases(of: words, longest: 8), none: "It says nothing to do")
    }

    /// What the answers say; `now` starts its count.
    public static func schedule(_ answers: [String: Answer], words: [String], now: Date = .now) -> ScheduleAsk {
        // Only when sure: unsure, the card says the schedule and waits for ↩.
        if let reminder = answers[isReminder.name], reminder.choice == "yes", reminder.confidence >= sureFrom { return .plans }
        guard let text = phrase(answers, "ask", phrases: phrases(of: words, longest: 8))?.text else { return .missing(.scheduledAsk) }

        var hourValue = 9, minuteValue = 0
        if let said = answers[runHour.name].flatMap({ Int($0.choice) }) {
            hourValue = said
            minuteValue = answers[runMinute.name].flatMap { Int($0.choice) } ?? 0
        } else if let part = answers[partOfDay.name].flatMap({ ["morning": 9, "noon": 12, "afternoon": 14, "evening": 19][$0.choice] }) {
            hourValue = part
        }
        let interval = answers[everyN.name].flatMap { Int($0.choice) } ?? 1
        let schedule: AskSchedule
        switch answers[repeatKind.name]?.choice {
        case "every day":
            schedule = AskSchedule(.daily, hour: hourValue, minute: minuteValue, interval: interval, start: now)
        case "every weekday":
            schedule = AskSchedule(.weekly, weekdays: [2, 3, 4, 5, 6], hour: hourValue, minute: minuteValue, start: now)
        case "every weekend":
            schedule = AskSchedule(.weekly, weekdays: [7, 1], hour: hourValue, minute: minuteValue, start: now)
        case "some days":
            let days = Array(Set((1...3).compactMap { answers["day_\($0)"].flatMap { weekdayNames.firstIndex(of: $0.choice) }.map { $0 + 1 } }))
            guard !days.isEmpty else { return .missing(.weekdays) }
            schedule = AskSchedule(.weekly, weekdays: days, hour: hourValue, minute: minuteValue, interval: interval, start: now)
        case "every month":
            guard let day = answers[dayOfMonth.name].flatMap({ Int($0.choice) }) else {
                return .missing(.dayOfMonth)
            }
            schedule = AskSchedule(.monthly, day: day, hour: hourValue, minute: minuteValue, interval: interval, start: now)
        default:
            return .missing(.repeats)
        }
        return .schedule(schedule, ask: text)
    }

    // MARK: - An app or a process

    /// The app or the process a request names ("kill creative cloud",
    /// "désinstalle Slack"), as a span of its own words.
    public static func targetQuestions(words: [String]) -> [Question] {
        [phraseQuestion(name: "target",
                        instructions: "Which app or program does the request name, in its own words: its whole name? kill creative cloud → “creative cloud”; quitte de force Teams → “Teams”; désinstalle Slack → “Slack”; uninstall the Figma app → “Figma”.",
                        phrases: phrases(of: words, longest: 4), none: "It names no app")]
    }

    /// The name picked, as said.
    public static func target(_ answers: [String: Answer], words: [String]) -> String? {
        phrase(answers, "target", phrases: phrases(of: words, longest: 4))?.text
    }
}
