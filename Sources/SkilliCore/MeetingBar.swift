import Foundation

/// The meeting in the menu bar (Settings → Calendar), its three moments
/// told apart at a glance (2026-10-16: "i don't know if i'm very late
/// or just still have time"):
/// - coming: a calendar, "Weekly sync · in 12 min" ("at 14:30" an hour or
///   more away);
/// - started and not joined: a call, red, "Weekly sync · started 3 min ago"
///   (without the red when this Mac cannot tell who joined);
/// - on: the ring that empties, "Weekly sync · 20 min left", the next one
///   beside it "12 min left · then Standup 14:30".
/// Which meeting, in which state, said how, and when that next changes.
/// The app draws it (`MeetingWatch`); Settings previews it from the same
/// code.
public enum MeetingBar {
    /// A call not joined is "started" this long after its start, as the
    /// agenda's next meeting is one that started up to 15 min ago; then it
    /// counts down like any meeting on now.
    public static let lateWindow: TimeInterval = 15 * 60
    /// A call on this Mac that began from this long before a meeting's
    /// start joined it, unless it began during another meeting with a call
    /// (`joined`); an older one is another call (the meeting before,
    /// running over).
    public static let joinLead: TimeInterval = 10 * 60

    /// The settings that shape it (Settings → Calendar).
    public struct Options: Equatable, Sendable {
        /// Minutes before a meeting it shows; nil never, Int.max always.
        public var lead: Int?
        public var callsOnly: Bool
        public var countdown: Bool
        /// Minutes after its start it leaves; -1 at its end.
        public var hideAfter: Int
        public var nextDuringMeeting: Bool

        public init(lead: Int?, callsOnly: Bool, countdown: Bool, hideAfter: Int, nextDuringMeeting: Bool) {
            self.lead = lead
            self.callsOnly = callsOnly
            self.countdown = countdown
            self.hideAfter = hideAfter
            self.nextDuringMeeting = nextDuringMeeting
        }
    }

    /// What skil.li can read of the calls on this Mac: never a guess.
    public struct Presence: Equatable, Sendable {
        public enum Microphone: Equatable, Sendable {
            /// No app records from a microphone: no call on this Mac.
            case idle
            /// Another app records from one (macOS's orange dot), since
            /// skil.li saw it begin.
            case inUse(since: Date)
            /// This Mac has no microphone, or CoreAudio cannot say: who
            /// joined cannot be told.
            case unknown
        }

        /// Occurrences joined (`key`): from skil.li (its Join), or seen in a
        /// call once.
        public var joined: Set<String>
        public var microphone: Microphone

        public init(joined: Set<String> = [], microphone: Microphone = .unknown) {
            self.joined = joined
            self.microphone = microphone
        }
    }

    public enum State: Equatable, Sendable {
        /// Before it: the minutes to its start, rounded up; nil an hour or
        /// more away (said as its time).
        case coming(minutes: Int?)
        /// A call that started and was not joined: the minutes since its
        /// start; `late` when skil.li can tell no one joined from this Mac.
        case started(minutes: Int, late: Bool)
        /// On: the minutes left, rounded up, and the part of it left (1 at
        /// its start, 0 at its end).
        case on(minutesLeft: Int, remaining: Double)
        /// On, without the countdown (Settings: Count down to its end off).
        case now
    }

    /// What the menu bar draws before the words.
    public enum Glyph: Equatable, Sendable {
        /// A calendar page: something is coming.
        case calendar
        /// The ring, emptying: the part of the meeting left.
        case ring(remaining: Double)
        /// A camera: the call is on.
        case call
    }

    public struct Plan: Equatable, Sendable {
        /// The meeting shown (on now until it leaves, else the next one
        /// once that close), and how.
        public var shown: AgendaEvent?
        public var state: State?
        /// The next one beside it, during a meeting.
        public var next: AgendaEvent?
        /// The moments that can change it.
        public var changes: [Date]

        public init(shown: AgendaEvent? = nil, state: State? = nil, next: AgendaEvent? = nil, changes: [Date] = []) {
            self.shown = shown
            self.state = state
            self.next = next
            self.changes = changes
        }
    }

    /// One occurrence of an event: a repeating meeting keeps its id.
    public static func key(_ event: AgendaEvent) -> String {
        "\(event.id)@\(Int(event.start.timeIntervalSince1970))"
    }

    /// Joined, as far as this Mac can tell: from skil.li (its Join for this
    /// occurrence), or a call that began on it from `joinLead` before the
    /// start while no other meeting with a call, begun before this one, was
    /// still on among `events`. A call begun during the meeting before is
    /// that one's (back to back, or joined late): it joins nothing after it,
    /// even when it began in this one's lead.
    public static func joined(_ event: AgendaEvent, _ presence: Presence, among events: [AgendaEvent]) -> Bool {
        if presence.joined.contains(key(event)) { return true }
        guard case .inUse(let since) = presence.microphone, since >= event.start.addingTimeInterval(-joinLead) else { return false }
        return !events.contains { $0.meeting != nil && $0.start < event.start && $0.start <= since && since < $0.end }
    }

    /// In the call already, as the menu bar tells it (`joined`); only a call
    /// can be joined. No alert comes for it, it is not joined at once again
    /// as it starts, and its alert, still up, goes.
    public static func inCall(_ event: AgendaEvent, _ presence: Presence, among events: [AgendaEvent]) -> Bool {
        event.meeting != nil && joined(event, presence, among: events)
    }

    /// At `now`: the meeting shown and its state, the next one beside it
    /// during a meeting, and the moments that can change them (each minute
    /// while a number is said: one timer, never a poll).
    public static func plan(_ events: [AgendaEvent], now: Date, options: Options, presence: Presence = Presence(),
                            dismissed: Set<String> = []) -> Plan {
        guard let lead = options.lead else { return Plan() }
        func leaves(_ event: AgendaEvent) -> Date {
            options.countdown || options.hideAfter < 0 ? event.end
                : min(event.end, event.start.addingTimeInterval(TimeInterval(options.hideAfter * 60)))
        }
        func showsAt(_ event: AgendaEvent) -> Date {
            lead == Int.max ? .distantPast : event.start.addingTimeInterval(-TimeInterval(lead * 60))
        }
        let candidates = events.filter { (!options.callsOnly || $0.meeting != nil) && !dismissed.contains($0.id) }
        let current = candidates.filter { $0.start <= now && leaves($0) > now }.max { $0.start < $1.start }
        let upcoming = candidates.filter { $0.start > now }.min { $0.start < $1.start }
        let due = upcoming.flatMap { now >= showsAt($0) ? $0 : nil }
        var changes: [Date] = []
        if let current {
            changes.append(leaves(current))
            let state: State
            let lateEnds = current.start.addingTimeInterval(lateWindow)
            if current.meeting != nil, now < lateEnds, !joined(current, presence, among: events) {
                let minutes = max(0, Int(now.timeIntervalSince(current.start) / 60))
                state = .started(minutes: minutes, late: presence.microphone != .unknown)
                changes.append(min(lateEnds, current.start.addingTimeInterval(TimeInterval((minutes + 1) * 60))))
                changes.append(lateEnds)
            } else if options.countdown {
                let total = max(current.end.timeIntervalSince(current.start), 1)
                state = .on(minutesLeft: minutesLeft(until: current.end, now: now),
                            remaining: min(max(current.end.timeIntervalSince(now) / total, 0), 1))
                // The time left changes each minute.
                changes.append(nextMinuteChange(until: current.end, now: now))
            } else {
                state = .now
            }
            if let upcoming {
                if options.nextDuringMeeting, due == nil { changes.append(showsAt(upcoming)) }
                changes.append(upcoming.start)
            }
            return Plan(shown: current, state: state, next: options.nextDuringMeeting ? due : nil, changes: changes)
        }
        if let due {
            let minutes = minutesLeft(until: due.start, now: now)
            changes.append(due.start)
            // "in 12 min" each minute; "at 14:30" until it is under an hour.
            if minutes >= 60 {
                changes.append(due.start.addingTimeInterval(-59 * 60))
            } else if minutes > 1 {
                changes.append(nextMinuteChange(until: due.start, now: now))
            }
            return Plan(shown: due, state: .coming(minutes: minutes < 60 ? minutes : nil), changes: changes)
        }
        return Plan(changes: upcoming.map { [showsAt($0)] } ?? [])
    }

    /// What the menu bar shows: the glyph, red or not, the words, and its
    /// help (the item's tooltip), which says how skil.li knows.
    public struct Look: Equatable, Sendable {
        public var glyph: Glyph
        /// Red (`systemRed`, as the meeting card says "STARTED … AGO"): a
        /// call started and no one joined from this Mac.
        public var urgent: Bool
        public var title: String
        public var help: String

        public init(glyph: Glyph, urgent: Bool, title: String, help: String) {
            self.glyph = glyph
            self.urgent = urgent
            self.title = title
            self.help = help
        }
    }

    public static func look(of event: AgendaEvent, state: State, next: AgendaEvent?, clock: (Date) -> String = clock) -> Look {
        let name = event.title.isEmpty ? "Untitled" : event.title
        let then = next.map { " · then \(short($0.title, 18)) \(clock($0.start))" } ?? ""
        let thenHelp = next.map { " Then \($0.title.isEmpty ? "Untitled" : $0.title) at \(clock($0.start))." } ?? ""
        switch state {
        case .coming(let minutes):
            return Look(glyph: .calendar, urgent: false,
                        title: "\(short(event.title, 24)) · \(minutes.map { "in \($0) min" } ?? "at \(clock(event.start))")",
                        help: "\(name) starts at \(clock(event.start)).")
        case .started(let minutes, let late):
            return Look(glyph: .call, urgent: late,
                        title: "\(short(event.title, 24)) · \(minutes == 0 ? "starting now" : "started \(minutes) min ago")",
                        help: late ? "\(name) started at \(clock(event.start)), and you have not joined it from this Mac."
                            : "\(name) started at \(clock(event.start)). This Mac has no microphone: skil.li cannot tell whether you joined.")
        case .on(let minutesLeft, let remaining):
            let left = "\(spoken(minutes: minutesLeft)) left"
            // Beside the next one, only the time: the meeting on now is known.
            return Look(glyph: .ring(remaining: remaining), urgent: false,
                        title: next == nil ? "\(short(event.title, 24)) · \(left)" : "\(left)\(then)",
                        help: "\(name) ends at \(clock(event.end)).\(thenHelp)")
        case .now:
            return Look(glyph: event.meeting == nil ? .calendar : .call, urgent: false,
                        title: "\(short(event.title, next == nil ? 24 : 16)) · now\(then)",
                        help: "\(name) started at \(clock(event.start)).\(thenHelp)")
        }
    }

    public static func short(_ title: String, _ length: Int) -> String {
        let name = title.isEmpty ? "Untitled" : title
        return name.count > length ? String(name.prefix(length - 1)) + "…" : name
    }

    public static func clock(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    /// "12 min", "1 h 05".
    public static func spoken(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// The minutes to `end`, rounded up, so it reads 1 min to the end.
    public static func minutesLeft(until end: Date, now: Date) -> Int {
        max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// When the minutes to `end` (rounded up) next go down.
    public static func nextMinuteChange(until end: Date, now: Date) -> Date {
        let minutes = (end.timeIntervalSince(now) / 60).rounded(.up)
        return end.addingTimeInterval(-(minutes - 1) * 60)
    }
}
