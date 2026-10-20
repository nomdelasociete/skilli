import XCTest
@testable import SkilliCore

/// The launcher looks at fewer rows as the user types on: what it skips
/// must be what could not match, and the matcher's scores must not move.
final class SearchNarrowingTests: XCTestCase {
    private let phrases = [
        "Safari", "Night Shift", "Displays", "Moniteurs", "Wi‑Fi", "Bluetooth", "Touch ID & Password", "Lock Screen",
        "Move to Next Display", "Keep Awake", "Son", "Sound", "Contrôle de la mission", "Réglages de l'écran verrouillé",
        "Allow Bluetooth", "Visual Studio Code", "Xcode Code", "met la chanson suivante", "Marie Horizon",
        "True Tone", "Show percentage in menu bar", "Accessibility Keyboard", "qui est jean-françois de chez lumière",
        "Background items", "Screen Time", "Siri", "Spotlight", "Battery", "Énergie", "Économiseur d'écran", "a", ""
    ]

    private let queries = [
        "s", "sa", "saf", "safari", "n", "ni", "nsh", "night sh", "disp", "display", "wifi", "wi-fi", "lock screen", "mets",
        "met la chanson suivante", "marie horizon", "12,5 * 4", "awake 1 hour", "qui est jean-françois", "tt", "xc",
        "code", "écran", "ecran verr", "zzz", "é", "bat", "spot", "true tone", "keyb"
    ]

    /// The original matcher (arrays per call), kept as the reference the
    /// faster one must equal.
    private func referenceScore(_ query: FuzzyMatcher.Query, _ candidate: FuzzyCandidate) -> Int? {
        let q = query.scalars
        let c = candidate.scalars
        guard !q.isEmpty else { return 0 }
        guard q.count <= c.count else { return nil }
        func gain(_ j: Int) -> Int { 1 + (candidate.wordStarts[j] ? 10 : 0) }
        let unreachable = Int.min / 2
        var previous = [Int](repeating: unreachable, count: c.count)
        var current = [Int](repeating: unreachable, count: c.count)
        for j in c.indices where c[j] == q[0] {
            previous[j] = gain(j) - min(j, 10) + (j == 0 ? 8 : 0)
        }
        for i in q.indices.dropFirst() {
            var bestBeforeGap = unreachable
            for j in c.indices {
                if j >= 2, previous[j - 2] > unreachable { bestBeforeGap = max(bestBeforeGap, previous[j - 2] + (j - 2)) }
                current[j] = unreachable
                guard c[j] == q[i] else { continue }
                var best = unreachable
                if j >= 1, previous[j - 1] > unreachable { best = previous[j - 1] + 6 }
                if bestBeforeGap > unreachable { best = max(best, bestBeforeGap - j + 1) }
                if best > unreachable { current[j] = best + gain(j) }
            }
            swap(&previous, &current)
        }
        guard let best = previous.max(), best > unreachable else { return nil }
        return best + (q.count == c.count ? 20 : 0)
    }

    private func referenceWordStarts(_ query: FuzzyMatcher.Query, _ candidate: FuzzyCandidate) -> Bool {
        let q = query.scalars
        let c = candidate.scalars
        let starts = candidate.wordStarts
        guard !q.isEmpty else { return true }
        guard q.count <= c.count else { return false }
        guard c.indices.contains(where: { starts[$0] && c[$0] == q[0] }) else { return false }
        var reach = [Bool](repeating: false, count: c.count + 1)
        for m in c.indices where starts[m] && c[m] == q[0] { reach[m + 1] = true }
        for k in q.indices.dropFirst() {
            guard let first = reach.firstIndex(of: true) else { return false }
            var next = [Bool](repeating: false, count: c.count + 1)
            for j in first..<c.count where reach[j] && c[j] == q[k] { next[j + 1] = true }
            for m in first..<c.count where starts[m] && c[m] == q[k] { next[m + 1] = true }
            reach = next
        }
        return reach.contains(true)
    }

    func testScoresAndWordStartsAreUnchanged() {
        var random = SystemRandomNumberGenerator()
        let letters = Array("abcdeilnorstué ")
        let made = (0..<300).map { _ in String((0..<Int.random(in: 1...6, using: &random)).map { _ in letters.randomElement(using: &random)! }) }
        for phrase in phrases {
            let candidate = FuzzyCandidate(phrase)
            for text in queries + made {
                let query = FuzzyMatcher.Query(text)
                XCTAssertEqual(FuzzyMatcher.score(query, candidate), referenceScore(query, candidate), "“\(text)” in “\(phrase)”")
                XCTAssertEqual(FuzzyMatcher.matchesWordStarts(query, candidate), referenceWordStarts(query, candidate),
                               "“\(text)” in “\(phrase)”")
                XCTAssertEqual(FuzzyMatcher.mayMatch(query, candidate), referenceScore(query, candidate) != nil, "“\(text)” in “\(phrase)”")
            }
        }
    }

    /// What a query lets through holds everything its longer forms match:
    /// a score, or the word starts of a phrase.
    func testTypingOnOnlyLosesWhatCouldNotMatch() {
        let candidates = phrases.map(FuzzyCandidate.init)
        for text in queries {
            let typed = Array(text)
            for end in typed.indices.dropFirst() {
                let shorter = FuzzyMatcher.Query(String(typed[..<end]))
                let longer = FuzzyMatcher.Query(String(typed[...end]))
                for candidate in candidates {
                    if FuzzyMatcher.score(longer, candidate) != nil {
                        XCTAssertTrue(FuzzyMatcher.mayMatch(shorter, candidate), "“\(String(typed[...end]))” in “\(candidate.text)”")
                    }
                    if FuzzyMatcher.matchesWordStarts(longer, candidate) {
                        XCTAssertTrue(FuzzyMatcher.matchesWordStarts(shorter, candidate), "“\(String(typed[...end]))” in “\(candidate.text)”")
                    }
                }
            }
        }
    }

    func testNarrowsOnlyWhileTypingOn() {
        var narrowing = SearchNarrowing()
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("sa"), count: 4), [0, 1, 2, 3], "nothing kept yet: every row")
        narrowing.keep([1, 3], for: FuzzyMatcher.Query("sa"))
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("saf"), count: 4), [1, 3], "typed on")
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("Sa f"), count: 4), [1, 3], "case and spaces aside, still typed on")
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("sa"), count: 4), [1, 3], "the same words again")
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("s"), count: 4), [0, 1, 2, 3], "a letter erased: every row")
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("so"), count: 4), [0, 1, 2, 3], "other words: every row")
        narrowing.reset()
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("saf"), count: 4), [0, 1, 2, 3], "the rows changed: every row")
        narrowing.keep([], for: FuzzyMatcher.Query(""))
        XCTAssertEqual(narrowing.rows(for: FuzzyMatcher.Query("x"), count: 2), [0, 1], "an empty query narrows nothing")
    }
}
