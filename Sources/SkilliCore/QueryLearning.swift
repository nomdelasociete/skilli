import Foundation

/// Learns which result the user picks for what they type, Tuna-style.
///
/// Picking Safari after typing "saf" makes Safari rank first for "saf" and,
/// a little less, for "s" and "sa", so the same habit needs fewer keystrokes
/// each time. A learned pick wins even when the query does not fuzzy-match
/// the name. Picks fade with a half-life, so habits can change.
public struct QueryLearning: Codable, Sendable, Equatable {
    public struct Hit: Codable, Sendable, Equatable {
        public var weight: Double
        public var updated: Date
    }

    /// Weight of a pick for the shorter prefixes of what was typed.
    public static let prefixWeight = 0.5
    /// Bonus per unit of (log) weight; fuzzy scores are in the tens.
    public static let pointsPerBit = 30.0
    public static let maxQueries = 4_000

    public var halfLife: TimeInterval
    /// Query key → item id → hit.
    public private(set) var hits: [String: [String: Hit]] = [:]

    public init(halfLife: TimeInterval = 30 * 24 * 3_600) {
        self.halfLife = halfLife
    }

    public mutating func record(query text: String, item: String, at now: Date) {
        let key = Self.key(text)
        guard !key.isEmpty else { return }
        for length in 1...key.count {
            let prefix = String(key.prefix(length))
            let weight = length == key.count ? 1.0 : Self.prefixWeight
            var bucket = hits[prefix, default: [:]]
            let current = bucket[item].map { decayed($0, at: now) } ?? 0
            bucket[item] = Hit(weight: current + weight, updated: now)
            hits[prefix] = bucket
        }
        prune()
    }

    /// Ranking bonus for `item` under `query`; 0 when never picked.
    public func boost(query text: String, item: String, at now: Date) -> Int {
        guard let hit = hits[Self.key(text)]?[item] else { return 0 }
        return Self.points(decayed(hit, at: now))
    }

    /// Everything learned for this query, best first.
    public func learnedItems(query text: String, at now: Date) -> [(item: String, boost: Int)] {
        (hits[Self.key(text)] ?? [:])
            .map { (item: $0.key, boost: Self.points(decayed($0.value, at: now))) }
            .filter { $0.boost > 0 }
            .sorted { $0.boost != $1.boost ? $0.boost > $1.boost : $0.item < $1.item }
    }

    /// How much each item whose id starts with `prefix` was picked (its
    /// strongest query, faded), keyed by the rest of its id: "contact:42"
    /// → "42". Dictate tells the recognizer those contacts' names first.
    public func picks(prefix: String, at now: Date) -> [String: Double] {
        var picks: [String: Double] = [:]
        for bucket in hits.values {
            for (item, hit) in bucket where item.hasPrefix(prefix) {
                let id = String(item.dropFirst(prefix.count))
                picks[id] = max(picks[id] ?? 0, decayed(hit, at: now))
            }
        }
        return picks
    }

    public mutating func forget(item: String) {
        for key in hits.keys {
            hits[key]?[item] = nil
            if hits[key]?.isEmpty == true { hits[key] = nil }
        }
    }

    static func points(_ weight: Double) -> Int {
        Int((log2(1 + weight) * pointsPerBit).rounded())
    }

    static func key(_ text: String) -> String {
        FuzzyMatcher.Query(text).key
    }

    private func decayed(_ hit: Hit, at now: Date) -> Double {
        let age = max(0, now.timeIntervalSince(hit.updated))
        return hit.weight * pow(0.5, age / halfLife)
    }

    /// Keeps the table bounded by dropping the least recently used queries.
    private mutating func prune() {
        guard hits.count > Self.maxQueries else { return }
        let byRecency = hits.map { (key: $0.key, last: $0.value.values.map(\.updated).max() ?? .distantPast) }
            .sorted { $0.last < $1.last }
        for entry in byRecency.prefix(hits.count - Self.maxQueries) {
            hits[entry.key] = nil
        }
    }
}
