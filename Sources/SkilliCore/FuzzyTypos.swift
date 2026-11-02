import Foundation

/// One slip of the fingers in what was typed, undone: two letters swapped
/// ("wahtsapp"), a key's neighbour hit ("whqtsapp", on a QWERTY or an
/// AZERTY keyboard), a letter too many ("safaari"). A letter left out or a
/// space needs nothing: the query only has to be in order in the name
/// (`FuzzyMatcher.score`).
///
/// Asked only when the query as typed finds nothing: built once for that
/// key, then each name is looked at through the variants that start with
/// one of its words' first letters.
public struct FuzzyTypos: Sendable {
    /// From four letters: shorter, one slip leads to too many names.
    public static let minLength = 4
    /// Past it the words are a sentence, not a name mistyped.
    public static let maxLength = 12
    /// Under any row the query finds as typed.
    public static let penalty = 12
    /// A letter dropped is a looser guess than one swapped or a neighbour.
    static let droppedPenalty = 4

    struct Variant: Sendable {
        let query: FuzzyMatcher.Query
        let dropped: Bool
    }

    /// The variants by their first letter.
    let variants: [Unicode.Scalar: [Variant]]

    public init(_ query: FuzzyMatcher.Query) {
        let q = query.scalars
        guard (Self.minLength...Self.maxLength).contains(q.count) else {
            variants = [:]
            return
        }
        var seen: Set<[Unicode.Scalar]> = [q]
        var byFirst: [Unicode.Scalar: [Variant]] = [:]
        func add(_ scalars: [Unicode.Scalar], dropped: Bool) {
            guard let first = scalars.first, seen.insert(scalars).inserted else { return }
            byFirst[first, default: []].append(Variant(query: FuzzyMatcher.Query(scalars: scalars), dropped: dropped))
        }
        for i in q.indices.dropLast() where q[i] != q[i + 1] {
            var swapped = q
            swapped.swapAt(i, i + 1)
            add(swapped, dropped: false)
        }
        for i in q.indices {
            for neighbour in Self.neighbours[q[i]] ?? [] {
                var replaced = q
                replaced[i] = neighbour
                add(replaced, dropped: false)
            }
        }
        for i in q.indices {
            var shorter = q
            shorter.remove(at: i)
            add(shorter, dropped: true)
        }
        variants = byFirst
    }

    public var isEmpty: Bool { variants.isEmpty }

    /// The best score of a variant the name's word starts carry in runs
    /// ("whatsapp" in "WhatsApp", not letters scattered over it) and that
    /// fits strongly, less `penalty`; nil when none does.
    public func score(_ candidate: FuzzyCandidate) -> Int? {
        var best: Int?
        var tried: Set<Unicode.Scalar> = []
        for (index, scalar) in candidate.scalars.enumerated() where candidate.wordStarts[index] && tried.insert(scalar).inserted {
            for variant in variants[scalar] ?? [] where FuzzyMatcher.matchesWordStarts(variant.query, candidate) {
                guard let score = FuzzyMatcher.score(variant.query, candidate), FuzzyMatcher.isStrong(score, for: variant.query) else { continue }
                let kept = score - Self.penalty - (variant.dropped ? Self.droppedPenalty : 0)
                best = max(best ?? kept, kept)
            }
        }
        return best
    }

    /// Letters next to each other on a QWERTY or an AZERTY keyboard: on
    /// the same row, and the two touching it on the rows above and below.
    static let neighbours: [Unicode.Scalar: [Unicode.Scalar]] = {
        let layouts = [
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
            ["azertyuiop", "qsdfghjklm", "wxcvbn"],
        ]
        var table: [Unicode.Scalar: Set<Unicode.Scalar>] = [:]
        for rows in layouts {
            let grid = rows.map { Array($0.unicodeScalars) }
            for (r, row) in grid.enumerated() {
                for (i, key) in row.enumerated() {
                    var near: [Unicode.Scalar] = []
                    if i > 0 { near.append(row[i - 1]) }
                    if i + 1 < row.count { near.append(row[i + 1]) }
                    // Each row starts half a key to the right of the one above.
                    if r > 0 { near += [i, i + 1].filter { grid[r - 1].indices.contains($0) }.map { grid[r - 1][$0] } }
                    if r + 1 < grid.count { near += [i - 1, i].filter { grid[r + 1].indices.contains($0) }.map { grid[r + 1][$0] } }
                    table[key, default: []].formUnion(near)
                }
            }
        }
        return table.mapValues { $0.sorted { $0.value < $1.value } }
    }()
}

extension FuzzyMatcher.Query {
    /// Already normalized (a typo's variant).
    init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }
}

extension LauncherRank {
    /// A row's score for a query mistyped once (`FuzzyTypos`): its best
    /// over its names and keywords; nil when no variant fits.
    public static func typoScore(_ typos: FuzzyTypos, names: ArraySlice<FuzzyCandidate>,
                                 keywords: ArraySlice<FuzzyCandidate> = []) -> Int? {
        var best: Int?
        for candidate in names {
            if let score = typos.score(candidate) { best = max(best ?? score, score) }
        }
        for candidate in keywords {
            if let score = typos.score(candidate) { best = max(best ?? score, score) }
        }
        return best
    }
}
