import Foundation

/// Meetings dismissed from the menu bar (its menu's Dismiss): each
/// occurrence until it ends, then forgotten. Kept across relaunches
/// (`MeetingWatch` saves `until`) and through a full sync of the calendar,
/// which gives events new item ids: an occurrence is its server id
/// (`AgendaEvent.externalID`, else `id`) and its start, so dismissing
/// today's standup leaves tomorrow's.
public struct MeetingDismissals: Equatable, Sendable {
    /// Each dismissed occurrence (`key`), and when it ends.
    public private(set) var until: [String: Date]

    public init(_ until: [String: Date] = [:]) {
        self.until = until
    }

    /// One occurrence, the same after a full sync.
    public static func key(_ event: AgendaEvent) -> String {
        let id = event.externalID.flatMap { $0.isEmpty ? nil : $0 } ?? event.id
        return "\(id)@\(Int(event.start.timeIntervalSince1970))"
    }

    public func contains(_ event: AgendaEvent) -> Bool {
        until[Self.key(event)] != nil
    }

    public mutating func insert(_ event: AgendaEvent) {
        until[Self.key(event)] = event.end
    }

    /// Without the occurrences ended at `now`.
    public func pruned(now: Date) -> MeetingDismissals {
        MeetingDismissals(until.filter { $0.value > now })
    }
}
