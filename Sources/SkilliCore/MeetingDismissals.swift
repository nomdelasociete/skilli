import Foundation

/// Meetings dismissed from the menu bar (its menu's Dismiss): each
/// occurrence until it ends, then forgotten. Kept across relaunches
/// (saved in the app's defaults) and through a full sync of the calendar,
/// which gives events new item ids: an occurrence is its server id
/// (`AgendaEvent.externalID`) and its start, so dismissing today's standup
/// leaves tomorrow's. Its item id and start too, for an event dismissed
/// before its first sync gave it a server id.
public struct MeetingDismissals: Equatable, Sendable {
    /// Each dismissed occurrence (`key`), and when it ends.
    public private(set) var until: [String: Date]

    /// Where `MeetingWatch` saves them: outside `Preferences.*`, so never
    /// in a backup.
    public static let defaultsKey = "MeetingWatch.dismissed"

    public init(_ until: [String: Date] = [:]) {
        self.until = until
    }

    /// As saved in `defaults`.
    public init(defaults: UserDefaults) {
        self.init(defaults.dictionary(forKey: Self.defaultsKey) as? [String: Date] ?? [:])
    }

    public func save(to defaults: UserDefaults) {
        if until.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(until, forKey: Self.defaultsKey)
        }
    }

    /// One occurrence, the same after a full sync.
    public static func key(_ event: AgendaEvent) -> String {
        let id = event.externalID.flatMap { $0.isEmpty ? nil : $0 } ?? event.id
        return "\(id)@\(Int(event.start.timeIntervalSince1970))"
    }

    /// `key`, and the key by its item id while that is still the one it had
    /// before its first sync.
    private static func keys(_ event: AgendaEvent) -> Set<String> {
        [key(event), "\(event.id)@\(Int(event.start.timeIntervalSince1970))"]
    }

    public func contains(_ event: AgendaEvent) -> Bool {
        Self.keys(event).contains { until[$0] != nil }
    }

    public mutating func insert(_ event: AgendaEvent) {
        for key in Self.keys(event) { until[key] = event.end }
    }

    /// Each one among `events` until its end as the calendar says it now
    /// (a meeting made longer stays dismissed), then without those ended at
    /// `now`.
    public func refreshed(with events: [AgendaEvent], now: Date) -> MeetingDismissals {
        var kept = self
        for event in events where contains(event) { kept.insert(event) }
        return MeetingDismissals(kept.until.filter { $0.value > now })
    }
}
