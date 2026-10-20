import Foundation

/// What a search typed further can still find. A row no name of which
/// holds "saf" in order cannot match "safa": while the user types on, a key
/// looks only at the rows the key before let through
/// (`FuzzyMatcher.mayMatch`, `FuzzyMatcher.matchesWordStarts`), not at
/// every row again. Anything else typed (a letter erased, a word pasted
/// over) looks at every row.
public struct SearchNarrowing: Sendable {
    private var typed: [Unicode.Scalar]?
    private var possible: [Int] = []

    public init() {}

    /// The rows, among `count`, that `query` may match: those the last
    /// query let through when `query` goes on from it, else all of them.
    public func rows(for query: FuzzyMatcher.Query, count: Int) -> [Int] {
        guard let typed, !typed.isEmpty, query.scalars.starts(with: typed) else { return Array(0..<count) }
        return possible
    }

    /// The rows `query` let through (`rows` ascending, each one that may
    /// match it): all the next key looks at, if it goes on from `query`.
    public mutating func keep(_ rows: [Int], for query: FuzzyMatcher.Query) {
        typed = query.scalars
        possible = rows
    }

    /// The rows changed: the next key looks at all of them.
    public mutating func reset() {
        typed = nil
        possible = []
    }
}
