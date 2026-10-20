import Foundation

/// Ask's calendar and reminders, read by the decision model: what is
/// asked of them (add a reminder or an event, the day's agenda, the next
/// meeting, free time, the to-dos) and every value it takes, in one
/// request; code makes the same requests the launcher's typed words make
/// (`ReminderRequest`, `EventRequest`, `AgendaRequest`, `RemindersRequest`).
extension AskValues {
    /// What a request asks of the calendar and the reminders.
    public enum Plan: Equatable, Sendable {
        /// `sure`: the least sure of the parts that make it ring or happen
        /// at the wrong time or place (what is asked, when, how often,
        /// where). What it says is not among them: the card shows it once
        /// added, ⌘Z takes it back. Extras (a list, a calendar, an alert,
        /// how important) are only kept when sure: one the model is unsure
        /// of was likely never said.
        case reminder(ReminderRequest, sure: Double)
        case event(EventRequest, sure: Double)
        case agenda(AgendaRequest)
        case reminders(RemindersRequest)
        /// A part it needs was not read: asked in the card.
        case missing(Missing)
    }

    static let planKind = Question(
        name: "plan",
        instructions: "What does the request ask of their Calendar and Reminders?",
        options: [
            Option("remind", "Add a reminder or a to-do: rappelle-moi d'appeler Paul demain, remind me to buy bread, n'oublie pas de payer le loyer, ajoute du lait à mes courses"),
            Option("event", "Add an event to their calendar: rdv demain 14h avec Paul, bloque 2h demain matin, réunion de 14h à 15h vendredi, schedule lunch with Anna on Friday"),
            Option("day", "What is on their calendar on a day: qu'est-ce que j'ai demain, mon agenda, my meetings today"),
            Option("next", "Their next meeting: ma prochaine réunion, c'est quand mon prochain rdv, my next meeting"),
            Option("join", "Join their meeting now: rejoins la réunion, lance la visio, join the call"),
            Option("availability", "When they are free in the coming days, to give someone: mes dispos, quand suis-je libre cette semaine, my availability"),
            Option("free", "Whether they are free at a given time: suis-je libre jeudi après-midi, am I free tomorrow at 3"),
            Option("todo", "Their reminders for today and the late ones: mes rappels, qu'est-ce que j'ai à faire aujourd'hui, my reminders, my to-dos"),
            Option("all todos", "Every one of their reminders, whatever the day, only when they say all: tous mes rappels, all my reminders"),
            Option("overdue", "Their late reminders: mes rappels en retard, what is overdue")
        ])

    /// Every question of a calendar or reminders request, once each.
    public static func planQuestions(words: [String], lists: [String], calendars: [String]) -> [Question] {
        var seen = Set<String>()
        return ([planKind] + reminderQuestions(words: words, lists: lists) + eventQuestions(words: words, calendars: calendars))
            .filter { seen.insert($0.name).inserted }
    }

    /// What the answers ask for. `url`: a link found in the request (a
    /// data detector, not a reading of it).
    public static func plan(_ answers: [String: Answer], words: [String], lists: [String], calendars: [String],
                            url: String? = nil, now: Date = .now, calendar: Calendar = .current) -> Plan {
        guard let kind = answers[planKind.name] else { return .missing(.planKind) }
        let when = self.when(answers, now: now, calendar: calendar)
        switch kind.choice {
        case "remind":
            guard let (title, _) = title(answers, words: words) else { return .missing(.reminderTitle) }
            guard let when else { return .missing(.reminderWhen) }
            var sure = [kind.confidence, when.confidence]
            let (recurrence, repeatSure) = recurrence(answers, weekdayOf: when.date, calendar: calendar)
            if recurrence != nil { sure.append(repeatSure) }
            var place: ReminderPlace?
            if let mode = answers[placeWhen.name], mode.choice != "none", let said = phrase(answers, "place", phrases: phrases(of: words, longest: 4)) {
                place = ReminderPlace(name: said.text, arriving: mode.choice == "arriving")
                sure += [mode.confidence, said.confidence]
            }
            let list = named(answers, "list", names: lists).flatMap { $0.confidence >= sureFrom ? $0.name : nil }
            let with = answers[attached.name].flatMap { $0.confidence >= sureFrom ? $0.choice : nil }
            let important = answers[priority.name].map { $0.confidence >= sureFrom } == true ? priority(answers) : 0
            let request = ReminderRequest(title: title, due: place == nil ? when.date : nil, hasTime: place == nil && when.hasTime,
                                          list: list, priority: important, recurrence: recurrence, url: url,
                                          withPageInFront: url == nil && with == "page", withMailInFront: url == nil && with == "mail", place: place)
            return .reminder(request, sure: sure.min() ?? 0)
        case "event":
            guard let when, let date = when.date else { return .missing(.eventDay) }
            var sure = [kind.confidence, when.confidence]
            let titled = title(answers, words: words)
            let start: Date
            let end: Date
            if when.hasTime {
                start = date
                let ending = eventEnd(answers, start: start, calendar: calendar)
                end = ending.end
                if let endSure = ending.confidence { sure.append(endSure) }
            } else {
                start = calendar.startOfDay(for: date)
                end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            }
            let (recurrence, repeatSure) = recurrence(answers, weekdayOf: start, calendar: calendar)
            if recurrence != nil { sure.append(repeatSure) }
            let inCalendar = named(answers, "calendar", names: calendars).flatMap { $0.confidence >= sureFrom ? $0.name : nil }
            let alerted = answers[alert.name].map { $0.confidence >= sureFrom } == true ? alertMinutes(answers) : nil
            let request = EventRequest(title: titled?.title ?? "Event", start: start, end: end, isAllDay: !when.hasTime, calendar: inCalendar,
                                       url: url, alertMinutes: alerted, recurrence: recurrence)
            return .event(request, sure: sure.min() ?? 0)
        case "day":
            let day = when?.date.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
            return .agenda(.day(offset: max(0, offset)))
        case "next":
            return .agenda(.next(join: false))
        case "join":
            return .agenda(.next(join: true))
        case "availability":
            return .agenda(.availability)
        case "free":
            let date = when?.date ?? now
            if when?.hasTime == true, answers[hour.name].flatMap({ Int($0.choice) }) != nil {
                return .agenda(.free(from: date, to: date.addingTimeInterval(3_600)))
            }
            let hours = ["morning": 8..<12, "noon": 12..<14, "afternoon": 12..<18, "evening": 18..<23][answers[partOfDay.name]?.choice ?? ""] ?? 9..<18
            let day = calendar.startOfDay(for: date)
            guard let from = calendar.date(bySettingHour: hours.lowerBound, minute: 0, second: 0, of: day),
                  let to = calendar.date(bySettingHour: hours.upperBound, minute: 0, second: 0, of: day) else {
                return .missing(.freeWhen)
            }
            return .agenda(.free(from: max(from, min(now, to)), to: to))
        case "todo":
            return .reminders(.today)
        case "all todos":
            return .reminders(.all)
        case "overdue":
            return .reminders(.overdue)
        default:
            return .missing(.planKind)
        }
    }
}
