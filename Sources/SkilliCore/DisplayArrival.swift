import Foundation

extension DisplayFingerprint {
    /// The same display as far as plugging goes: macOS's own id for it, or
    /// its own serial.
    public func isSameDisplay(as other: DisplayFingerprint) -> Bool {
        uuid == other.uuid || same(as: other) == .unit
    }
}

/// Which displays were plugged in, as opposed to coming back after sleep:
/// a display that was there before the Mac or its screens slept and comes
/// back while asleep or in the first 30 s after waking is not plugged in.
public struct DisplayArrival: Sendable {
    /// The displays at the last change.
    public private(set) var present: [DisplayFingerprint]
    private var beforeSleep: [DisplayFingerprint] = []
    private var asleep = false
    private var wokeAt: Date?

    /// How long after waking a display coming back is a reconnection.
    public static let wakeGrace: TimeInterval = 30

    public init(present: [DisplayFingerprint]) {
        self.present = present
    }

    /// The Mac or its screens go to sleep: the displays there now are the
    /// ones that may come back.
    public mutating func sleep() {
        guard !asleep else { return }
        beforeSleep = present
        asleep = true
    }

    public mutating func wake(at date: Date) {
        asleep = false
        wokeAt = date
    }

    /// The displays now; returns the ones plugged in since the last change
    /// (the built-in display aside: a lid opened is not a display plugged).
    public mutating func update(_ now: [DisplayFingerprint], at date: Date) -> [DisplayFingerprint] {
        let reconnecting = asleep || wokeAt.map { date.timeIntervalSince($0) < Self.wakeGrace } ?? false
        let plugged = now.filter { display in
            !display.builtIn
                && !present.contains { $0.isSameDisplay(as: display) }
                && !(reconnecting && beforeSleep.contains { $0.isSameDisplay(as: display) })
        }
        present = now
        return plugged
    }
}

/// The layouts to offer when displays are plugged in, best first, and the
/// one to put back without asking.
public enum LayoutTrigger {
    public struct Candidate: Equatable, Sendable {
        public var layoutID: String
        /// How surely a display plugged in is one the layout was saved on.
        public var certainty: DisplayFingerprint.Certainty
        /// Every display of the layout is connected, and no other.
        public var exact: Bool
    }

    /// Layouts saved on one of the displays just plugged in (by serial, or
    /// by model when it has none), not set to never; monitors ignored offer
    /// nothing. The layout made for exactly the displays there now first,
    /// then the surest, then the one using most of them, then by name.
    public static func candidates(for plugged: [DisplayFingerprint], connected: [DisplayFingerprint], layouts: [SavedWindowLayout],
                                  ignoredMonitors: [DisplayFingerprint]) -> [Candidate] {
        let arrived = plugged.filter { display in !display.builtIn && !ignoredMonitors.contains { $0.isSameDisplay(as: display) } }
        guard !arrived.isEmpty else { return [] }
        var found: [(candidate: Candidate, used: Int, name: String)] = []
        for layout in layouts where layout.automatic != .never {
            let saved = layout.displays.map(\.fingerprint)
            let matches = arrived.flatMap { display in saved.compactMap { $0.same(as: display) } }
            guard !matches.isEmpty else { continue }
            let certainty: DisplayFingerprint.Certainty = matches.contains(.unit) ? .unit : .model
            let used = saved.filter { display in connected.contains { display.same(as: $0) != nil } }.count
            let exact = used == saved.count && saved.count == connected.count
            found.append((Candidate(layoutID: layout.id, certainty: certainty, exact: exact), used, layout.name))
        }
        return found.sorted { a, b in
            if a.candidate.exact != b.candidate.exact { return a.candidate.exact }
            if a.candidate.certainty != b.candidate.certainty { return a.candidate.certainty == .unit }
            if a.used != b.used { return a.used > b.used }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }.map(\.candidate)
    }

    /// The layout to put back without asking: the only one offered that is
    /// set to always, on a display surely the one saved (its serial).
    public static func automatic(_ candidates: [Candidate], layouts: [SavedWindowLayout]) -> String? {
        let always = candidates.filter { candidate in
            candidate.certainty == .unit && layouts.first { $0.id == candidate.layoutID }?.automatic == .always
        }
        return always.count == 1 ? always[0].layoutID : nil
    }
}
