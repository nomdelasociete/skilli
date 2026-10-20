import Foundation

/// A warning before a meeting (Settings → Calendar): how long before, and how
/// it shows. The menu bar line and its countdown are the quieter ways,
/// set beside these.
public struct MeetingAlert: Codable, Hashable, Sendable, Identifiable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        /// The card where the launcher opens, the meeting in it.
        case card
        /// The same card, every screen dark around it until it closes.
        case dark

        public var title: String {
            switch self {
            case .card: "Card"
            case .dark: "Card, screens dark"
            }
        }
    }

    /// Minutes before the start; 0 on time.
    public var minutes: Int
    public var style: Style

    public init(minutes: Int, style: Style) {
        self.minutes = minutes
        self.style = style
    }

    public var id: String { "\(minutes)-\(style.rawValue)" }

    /// The choices offered, in minutes before the start.
    public static let choices = [0, 1, 2, 5, 10, 15, 30, 60]

    /// "On time", "5 min before", "1 hour before".
    public static func spoken(_ minutes: Int) -> String {
        minutes == 0 ? "On time" : minutes == 60 ? "1 hour before" : "\(minutes) min before"
    }
}

public enum MeetingAlerts {
    /// What to show at `now`: for each meeting, the alert whose moment has
    /// just come (within a minute: the Mac asleep then shows nothing late),
    /// once each; when two come at once, the closest to the start, dark
    /// before card. `keys` mark it, and any other come with it, shown.
    public static func due(_ events: [AgendaEvent], alerts: [MeetingAlert], now: Date, shown: Set<String>)
        -> [(event: AgendaEvent, alert: MeetingAlert, keys: [String])] {
        events.compactMap { event in
            let fresh = alerts.filter { alert in
                let moment = event.start.addingTimeInterval(-TimeInterval(alert.minutes * 60))
                return moment <= now && now.timeIntervalSince(moment) < 60 && !shown.contains(key(event, alert))
            }
            guard let alert = fresh.min(by: { ($0.minutes, $0.style == .dark ? 0 : 1) < ($1.minutes, $1.style == .dark ? 0 : 1) })
            else { return nil }
            return (event, alert, Array(Set(fresh.map { key(event, $0) })))
        }
    }

    /// Whether `alert`, come for `event`, shows: never for a call the user
    /// is in already (`MeetingBar.inCall` among `events`: joined from
    /// skil.li, or a call on this Mac since just before its start that did
    /// not begin during the meeting before), nor On time for a call joined
    /// at once as it starts (`joining`).
    public static func shows(_ alert: MeetingAlert, for event: AgendaEvent, among events: [AgendaEvent], joining: Bool,
                             presence: MeetingBar.Presence) -> Bool {
        guard event.meeting != nil else { return true }
        return !MeetingBar.inCall(event, presence, among: events) && !(joining && alert.minutes == 0)
    }

    /// Whether a call starting is joined at once (When a meeting starts →
    /// Join at once): not when the user is in it already, or its call
    /// would open a second time.
    public static func joinsAtOnce(_ event: AgendaEvent, among events: [AgendaEvent], presence: MeetingBar.Presence) -> Bool {
        event.meeting != nil && !MeetingBar.inCall(event, presence, among: events)
    }

    /// When the next alert comes, after `now`.
    public static func next(_ events: [AgendaEvent], alerts: [MeetingAlert], now: Date) -> Date? {
        events.flatMap { event in alerts.map { event.start.addingTimeInterval(-TimeInterval($0.minutes * 60)) } }
            .filter { $0 > now }
            .min()
    }

    static func key(_ event: AgendaEvent, _ alert: MeetingAlert) -> String {
        "\(event.id)@\(Int(event.start.timeIntervalSince1970))-\(alert.minutes)"
    }
}
