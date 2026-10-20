import Foundation

/// An ask kept with its schedule ("every Monday at 9:00: sum up my pull
/// requests"): run at its time like Ask would, its last answer kept.
public struct ScheduledAsk: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What to ask, as said, without the words that say when.
    public var ask: String
    public var schedule: AskSchedule
    public var created: Date
    public var isOn: Bool
    /// Its times count from here: made, turned back on, or changed; a time
    /// before it is never caught up.
    public var countsFrom: Date
    /// When it last ran (its run starts it: one run per time, never two).
    public var lastRun: Date?
    /// The last answer, whole (the user's own: agents only learn whether
    /// there is one).
    public var lastAnswer: String?
    /// The last run failed: `lastAnswer` says why.
    public var lastFailed: Bool

    public init(id: UUID = UUID(), ask: String, schedule: AskSchedule, created: Date = .now, isOn: Bool = true,
                lastRun: Date? = nil, lastAnswer: String? = nil, lastFailed: Bool = false) {
        self.id = id
        self.ask = ask
        self.schedule = schedule
        self.created = created
        self.isOn = isOn
        countsFrom = created
        self.lastRun = lastRun
        self.lastAnswer = lastAnswer
        self.lastFailed = lastFailed
    }

    /// "Every Monday at 9:00: sum up my pull requests".
    public var spoken: String { schedule.spoken + ": " + ask }

    /// Its next time: the first after its last run (or since it counts).
    /// One already gone was missed (the Mac asleep or off): it is due now,
    /// once, however many were missed.
    public func due(calendar: Calendar = .current) -> Date? {
        guard isOn else { return nil }
        let after = max(lastRun ?? countsFrom, countsFrom)
        return schedule.next(after: after, calendar: calendar)
    }

    /// Turned on again: the times while it was off are not caught up.
    public mutating func turn(on: Bool, now: Date = .now) {
        guard on != isOn else { return }
        isOn = on
        if on { countsFrom = now }
    }
}

/// The scheduled asks together: which are due, when to look again, what a
/// row says of the last run.
public enum ScheduledAsks {
    /// Those due at `now`, soonest first: each once, missed or on time.
    public static func due(_ asks: [ScheduledAsk], now: Date, calendar: Calendar = .current) -> [ScheduledAsk] {
        asks.compactMap { ask in ask.due(calendar: calendar).flatMap { $0 <= now ? (ask, $0) : nil } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// The first time still to come, to wait for; nil when none is on.
    public static func next(_ asks: [ScheduledAsk], now: Date, calendar: Calendar = .current) -> Date? {
        asks.compactMap { $0.due(calendar: calendar) }.filter { $0 > now }.min()
    }

    /// When a missed one runs: a minute after skil.li starts or the Mac
    /// wakes (the network back, the user settled), never in the past.
    public static let catchUpDelay: TimeInterval = 60

    /// "Today 9:00", "Tomorrow 8:30", "Yesterday 9:00", "Mon 19 Oct 9:00",
    /// "Mon 4 Jan 2027 9:00".
    public static func moment(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = AskSchedule.time(hour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date))
        let today = calendar.startOfDay(for: now)
        let day = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 99
        switch day {
        case 0: return "Today " + time
        case 1: return "Tomorrow " + time
        case -1: return "Yesterday " + time
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.timeZone = calendar.timeZone
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            formatter.dateFormat = sameYear ? "EEE d MMM" : "EEE d MMM yyyy"
            return formatter.string(from: date) + " " + time
        }
    }

    /// The one line a row shows of an answer: its first line with words,
    /// Markdown's marks out, cut at `limit` characters.
    public static func line(of answer: String, limit: Int = 90) -> String {
        let first = answer.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^(?:#+\s*|[-*+]\s+|\d+[.)]\s+|>\s*)"#, with: "", options: .regularExpression) }
            .map { $0.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression) }
            .first { $0.contains(where: \.isLetter) || $0.contains(where: \.isNumber) } ?? ""
        guard first.count > limit else { return first }
        let cut = first.prefix(limit)
        let end = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return end.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.—-")) + "…"
    }
}
