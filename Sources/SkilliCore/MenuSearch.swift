import Foundation

/// Search Menu Items ("m " in the launcher, JB 2026-10-16: "like Raycast",
/// "sometimes it's not useful to use AI"): the menu items of the app in
/// front found by their names as typed, without a model. Ask still finds
/// one by meaning (`MenuCandidates`).
public enum MenuSearch {
    /// One menu item: its name, the menus it is under, its keys.
    public struct Entry: Equatable, Sendable {
        /// Its place in what was read, to find the item again.
        public let index: Int
        public let title: String
        /// "Edit", "Transformations": the menus above it, top first.
        public let parents: [String]
        /// "⇧⌘E", as the menu shows it.
        public let shortcut: String?

        public init(index: Int, title: String, parents: [String], shortcut: String?) {
            self.index = index
            self.title = title
            self.parents = parents
            self.shortcut = shortcut
        }

        /// "Edit › Transformations".
        public var place: String { parents.joined(separator: " › ") }
    }

    /// An entry prepared once for every key: its name, and its menus' too.
    public struct Candidate: Sendable {
        public let entry: Entry
        let title: FuzzyCandidate
        let path: FuzzyCandidate

        public init(_ entry: Entry) {
            self.entry = entry
            title = FuzzyCandidate(entry.title)
            path = FuzzyCandidate((entry.parents + [entry.title]).joined(separator: " "))
        }
    }

    /// Best first: an item named so before one whose menus are (“export
    /// pdf” finds File › Export as PDF…, “format” the items of Format).
    /// Nothing typed: every item, in the menus' order.
    public static func search(_ text: String, in candidates: [Candidate], limit: Int = 60) -> [Entry] {
        let query = FuzzyMatcher.Query(text)
        guard !query.isEmpty else { return Array(candidates.prefix(limit).map(\.entry)) }
        let scored: [(entry: Entry, score: Int)] = candidates.compactMap { candidate in
            if let own = FuzzyMatcher.score(query, candidate.title) { return (candidate.entry, own + 1_000) }
            return FuzzyMatcher.score(query, candidate.path).map { (candidate.entry, $0) }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.index < $1.entry.index }
            .prefix(limit)
            .map(\.entry)
    }
}
