import XCTest
@testable import SkilliCore

final class QueryLearningTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testPickBoostsExactQueryMostAndPrefixesLess() {
        var learning = QueryLearning()
        learning.record(query: "saf", item: "safari", at: start)
        let exact = learning.boost(query: "saf", item: "safari", at: start)
        let prefix = learning.boost(query: "s", item: "safari", at: start)
        XCTAssertEqual(exact, 30)
        XCTAssertEqual(prefix, 18)
        XCTAssertEqual(learning.boost(query: "sa", item: "safari", at: start), 18)
        XCTAssertEqual(learning.boost(query: "safa", item: "safari", at: start), 0)
        XCTAssertEqual(learning.boost(query: "saf", item: "siri", at: start), 0)
    }

    func testRepeatedPicksGrowLogarithmically() {
        var learning = QueryLearning()
        for _ in 0..<3 {
            learning.record(query: "sfi", item: "safari", at: start)
        }
        XCTAssertEqual(learning.boost(query: "sfi", item: "safari", at: start), 60)
    }

    func testQueriesAreNormalized() {
        var learning = QueryLearning()
        learning.record(query: "Préf", item: "settings", at: start)
        XCTAssertGreaterThan(learning.boost(query: "pref", item: "settings", at: start), 0)
        learning.record(query: "visual code", item: "vscode", at: start)
        XCTAssertGreaterThan(learning.boost(query: "visualcode", item: "vscode", at: start), 0)
    }

    /// Dictate's order: the contacts picked most, by id, faded like the rest.
    func testPicksOfAKindByTheirStrongestQuery() {
        var learning = QueryLearning(halfLife: 100)
        learning.record(query: "paul", item: "contact:42", at: start)
        learning.record(query: "paul", item: "contact:42", at: start)
        learning.record(query: "mar", item: "contact:7", at: start)
        learning.record(query: "saf", item: "app:/Applications/Safari.app", at: start)
        let picks = learning.picks(prefix: "contact:", at: start)
        XCTAssertEqual(Set(picks.keys), ["42", "7"])
        XCTAssertEqual(picks["42"] ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(picks["7"] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(learning.picks(prefix: "contact:", at: start + 100)["42"] ?? 0, 1, accuracy: 0.001)
    }

    func testPicksFadeWithHalfLife() {
        var learning = QueryLearning(halfLife: 100)
        learning.record(query: "saf", item: "safari", at: start)
        XCTAssertEqual(learning.boost(query: "saf", item: "safari", at: start + 100), QueryLearning.points(0.5))
    }

    func testLearnedItemsListsPicksForNonMatchingQueries() {
        var learning = QueryLearning()
        learning.record(query: "smid", item: "transmit", at: start)
        learning.record(query: "smid", item: "transmit", at: start)
        learning.record(query: "smid", item: "smithers", at: start)
        let learned = learning.learnedItems(query: "SMID", at: start)
        XCTAssertEqual(learned.map(\.item), ["transmit", "smithers"])
    }

    func testEmptyQueryLearnsNothing() {
        var learning = QueryLearning()
        learning.record(query: "  ", item: "safari", at: start)
        XCTAssertTrue(learning.hits.isEmpty)
    }

    func testForgetRemovesItemEverywhere() {
        var learning = QueryLearning()
        learning.record(query: "saf", item: "safari", at: start)
        learning.forget(item: "safari")
        XCTAssertTrue(learning.hits.isEmpty)
    }

    func testRoundTripsThroughJSON() throws {
        var learning = QueryLearning()
        learning.record(query: "saf", item: "safari", at: start)
        let decoded = try JSONDecoder().decode(QueryLearning.self, from: JSONEncoder().encode(learning))
        XCTAssertEqual(decoded, learning)
    }
}
