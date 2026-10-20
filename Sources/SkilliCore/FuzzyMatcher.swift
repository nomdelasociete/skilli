import Foundation

/// A string prepared once for repeated fuzzy matching: case and diacritics
/// folded, word starts precomputed. Build candidates at index time, not per
/// keystroke.
public struct FuzzyCandidate: Sendable {
    public let text: String
    let scalars: [Unicode.Scalar]
    let wordStarts: [Bool]

    public init(_ text: String) {
        self.text = text
        (scalars, wordStarts) = FuzzyMatcher.normalize(text)
    }
}

public enum FuzzyMatcher {
    public struct Query: Sendable {
        let scalars: [Unicode.Scalar]

        /// Whitespace in the query is ignored: `visual code` matches
        /// "Visual Studio Code".
        public init(_ text: String) {
            scalars = FuzzyMatcher.normalize(text).scalars.filter { !$0.properties.isWhitespace }
        }

        public var isEmpty: Bool { scalars.isEmpty }

        /// Normalized text: case and diacritics folded, whitespace removed.
        /// Two queries with the same key match the same things.
        public var key: String {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars)
            return String(view)
        }
    }

    private static let matchScore = 1
    private static let wordStartBonus = 10
    private static let consecutiveBonus = 6
    private static let firstCharacterBonus = 8
    private static let exactMatchBonus = 20
    private static let maxLeadingPenalty = 10

    /// Higher is better; `nil` when the query is not a subsequence of the
    /// candidate. An empty query scores 0 against everything.
    ///
    /// Optimal alignment by dynamic programming, O(query × candidate): each
    /// matched character earns a base score, more on a word start or right
    /// after the previous match; gaps cost one point per skipped character.
    /// A candidate the query is not a subsequence of is turned down by one
    /// linear pass first, and the rows live on the stack: the launcher
    /// scores hundreds of names per key.
    public static func score(_ query: Query, _ candidate: FuzzyCandidate) -> Int? {
        let q = query.scalars
        let c = candidate.scalars
        guard !q.isEmpty else { return 0 }
        guard q.count <= c.count, isSubsequence(q, of: c) else { return nil }
        let starts = candidate.wordStarts

        let unreachable = Int.min / 2
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: 2 * c.count) { rows -> Int? in
            var previous = UnsafeMutableBufferPointer(rebasing: rows[0..<c.count])
            var current = UnsafeMutableBufferPointer(rebasing: rows[c.count...])
            previous.initialize(repeating: unreachable)
            current.initialize(repeating: unreachable)

            // Row 0: best score with q[0] matched at j.
            for j in c.indices where c[j] == q[0] {
                previous[j] = gain(starts, at: j)
                    - min(j, maxLeadingPenalty)
                    + (j == 0 ? firstCharacterBonus : 0)
            }

            // Row i: q[i] matched at j, coming either from j-1 (consecutive) or
            // from any k ≤ j-2 with a gap penalty of (j - k - 1). Tracking
            // max(previous[k] + k) keeps the row linear.
            for i in q.indices.dropFirst() {
                var bestBeforeGap = unreachable
                for j in c.indices {
                    if j >= 2, previous[j - 2] > unreachable {
                        bestBeforeGap = max(bestBeforeGap, previous[j - 2] + (j - 2))
                    }
                    current[j] = unreachable
                    guard c[j] == q[i] else { continue }

                    var best = unreachable
                    if j >= 1, previous[j - 1] > unreachable {
                        best = previous[j - 1] + consecutiveBonus
                    }
                    if bestBeforeGap > unreachable {
                        best = max(best, bestBeforeGap - j + 1)
                    }
                    if best > unreachable {
                        current[j] = best + gain(starts, at: j)
                    }
                }
                swap(&previous, &current)
            }

            guard let best = previous.max(), best > unreachable else { return nil }
            return best + (q.count == c.count ? exactMatchBonus : 0)
        }
    }

    /// Whether `query` can match `candidate`, by `score` or, for a phrase,
    /// `matchesWordStarts`: the query's letters in order in it. A query
    /// typed further only matches what this lets through
    /// (`SearchNarrowing`).
    public static func mayMatch(_ query: Query, _ candidate: FuzzyCandidate) -> Bool {
        query.scalars.isEmpty || query.scalars.count <= candidate.scalars.count && isSubsequence(query.scalars, of: candidate.scalars)
    }

    /// `q` (not empty) in order in `c`, letters in between.
    private static func isSubsequence(_ q: [Unicode.Scalar], of c: [Unicode.Scalar]) -> Bool {
        var i = 0
        for scalar in c where scalar == q[i] {
            i += 1
            if i == q.count { return true }
        }
        return false
    }

    /// The query matches mostly in runs from word starts ("shift" in
    /// "Night Shift"), not as letters scattered over a long phrase.
    public static func isStrong(_ score: Int, for query: Query) -> Bool {
        score >= query.scalars.count * 6
    }

    /// The query is made of the starts of the candidate's words, in order
    /// ("shift", "night shift", "nightsh" in "Night Shift options"; "true
    /// tone"), not letters scattered over a long phrase. Linear: for rows
    /// indexed by many long phrases (System Settings' sections), scored
    /// only when this holds, so typing stays fast and a scattered match is
    /// not shown.
    public static func matchesWordStarts(_ query: Query, _ candidate: FuzzyCandidate) -> Bool {
        let q = query.scalars
        let c = candidate.scalars
        let starts = candidate.wordStarts
        guard !q.isEmpty else { return true }
        guard q.count <= c.count else { return false }
        // `reach[j]`: the query so far can end just before `j`. A letter
        // goes on in the same word (`j`), or starts a later word.
        guard c.indices.contains(where: { starts[$0] && c[$0] == q[0] }) else { return false }
        // Its letters in order at least (one pass), before any table.
        guard isSubsequence(q, of: c) else { return false }
        // Both tables on the stack: many long phrases per key.
        return withUnsafeTemporaryAllocation(of: Bool.self, capacity: 2 * (c.count + 1)) { tables -> Bool in
            var reach = UnsafeMutableBufferPointer(rebasing: tables[0...c.count])
            var next = UnsafeMutableBufferPointer(rebasing: tables[(c.count + 1)...])
            reach.initialize(repeating: false)
            next.initialize(repeating: false)
            for m in c.indices where starts[m] && c[m] == q[0] { reach[m + 1] = true }
            for k in q.indices.dropFirst() {
                guard let first = reach.firstIndex(of: true) else { return false }
                next.update(repeating: false)
                for j in first..<c.count where reach[j] && c[j] == q[k] { next[j + 1] = true }
                for m in first..<c.count where starts[m] && c[m] == q[k] { next[m + 1] = true }
                swap(&reach, &next)
            }
            return reach.contains(true)
        }
    }

    /// The query is the candidate typed whole: the same letters and digits
    /// in the same order, case, accents, spaces and punctuation aside
    /// ("wifi" names "Wi‑Fi", "nightshift" "Night Shift"), the candidate's
    /// final "s" left out or not after three letters ("display" names
    /// "Displays"). Not one word among others ("display" in "Move to Next
    /// Display"), not a start ("disp"). Linear, and most candidates differ
    /// at their first letter.
    public static func names(_ query: Query, _ candidate: FuzzyCandidate) -> Bool {
        let q = query.scalars
        let c = candidate.scalars
        var i = 0
        var j = 0
        var same = 0
        while i < q.count, j < c.count {
            if q[i] == c[j] {
                i += 1
                j += 1
                same += 1
            } else if !isWordScalar(q[i]) {
                i += 1
            } else if !isWordScalar(c[j]) {
                j += 1
            } else {
                return false
            }
        }
        while i < q.count, !isWordScalar(q[i]) { i += 1 }
        guard i == q.count else { return false }
        while j < c.count, !isWordScalar(c[j]) { j += 1 }
        guard j < c.count else { return true }
        // Only a plural "s" may be left, and nothing after it.
        guard same >= 3, c[j] == "s" else { return false }
        j += 1
        while j < c.count, !isWordScalar(c[j]) { j += 1 }
        return j == c.count
    }

    /// A letter or a digit; ASCII without a Unicode table lookup.
    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            let value = scalar.value
            return (value >= 0x61 && value <= 0x7A) || (value >= 0x30 && value <= 0x39) || (value >= 0x41 && value <= 0x5A)
        }
        return isAlphanumeric(scalar)
    }

    private static func gain(_ wordStarts: [Bool], at index: Int) -> Int {
        matchScore + (wordStarts[index] ? wordStartBonus : 0)
    }

    /// Folds diacritics/width, every dash to "-" and the typographic
    /// apostrophe to "'", lowercases, and marks word starts (after a
    /// non-alphanumeric, or on a lower→Upper camelCase boundary). System
    /// Settings writes "Wi‑Fi" with a non-breaking hyphen: "wi-fi" typed
    /// must find it.
    static func normalize(_ text: String) -> (scalars: [Unicode.Scalar], wordStarts: [Bool]) {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        var scalars: [Unicode.Scalar] = []
        var wordStarts: [Bool] = []
        scalars.reserveCapacity(folded.unicodeScalars.count)
        wordStarts.reserveCapacity(folded.unicodeScalars.count)

        var previous: Unicode.Scalar?
        for original in folded.unicodeScalars {
            let scalar = plain(original)
            let properties = scalar.properties
            let isWordCharacter = isAlphanumeric(scalar)
            let previousIsWordCharacter = previous.map(isAlphanumeric) ?? false
            let camelBoundary = (previous?.properties.isLowercase ?? false) && properties.isUppercase
            let isStart = isWordCharacter && (!previousIsWordCharacter || camelBoundary)

            for (offset, lower) in properties.lowercaseMapping.unicodeScalars.enumerated() {
                scalars.append(lower)
                wordStarts.append(offset == 0 && isStart)
            }
            previous = scalar
        }
        return (scalars, wordStarts)
    }

    /// "‑" "–" "—" "−" as "-", "’" as "'": typed and written the same.
    private static func plain(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.isASCII { return scalar }
        if scalar.properties.generalCategory == .dashPunctuation || scalar == "\u{2212}" { return "-" }
        if scalar == "\u{2019}" || scalar == "\u{2018}" { return "'" }
        return scalar
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
}
