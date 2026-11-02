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

    /// Where: three runs from Figma make a habit there, not elsewhere.
    func testPlaceItemsNeedAHabitInThatApp() {
        var learning = QueryLearning()
        let figma = "com.figma.Desktop"
        let day = 86_400.0
        // A week apart: the earlier ones have faded a little.
        learning.record(item: "layout:design", in: figma, at: start)
        learning.record(item: "layout:design", in: figma, at: start + 7 * day)
        XCTAssertEqual(learning.placeItems(in: figma, at: start + 7 * day), [])
        learning.record(item: "layout:design", in: figma, at: start + 14 * day)
        for hour in 0..<4 { learning.record(item: "cmd:searchMenus", in: figma, at: start + 14 * day + Double(hour) * 3_600) }
        let now = start + 14 * day + 4 * 3_600
        XCTAssertEqual(learning.placeItems(in: figma, at: now), ["cmd:searchMenus", "layout:design"])
        XCTAssertEqual(learning.placeItems(in: "com.apple.Safari", at: now), [])
        // Typed picks are not touched.
        XCTAssertTrue(learning.hits.isEmpty)
    }

    func testPlaceItemsFade() {
        var learning = QueryLearning(halfLife: 100)
        for second in 0..<3 { learning.record(item: "cmd:quit", in: "com.example.App", at: start + Double(second)) }
        XCTAssertEqual(learning.placeItems(in: "com.example.App", at: start + 2), ["cmd:quit"])
        XCTAssertEqual(learning.placeItems(in: "com.example.App", at: start + 102), [])
    }

    /// Less than a name typed whole or one pick for the text.
    func testPlaceBoostStaysUnderTypedLearning() {
        var learning = QueryLearning()
        for _ in 0..<20 { learning.record(item: "app:/Applications/Simulator.app", in: "com.apple.dt.Xcode", at: start) }
        let boost = learning.placeBoost(item: "app:/Applications/Simulator.app", in: "com.apple.dt.Xcode", at: start)
        XCTAssertGreaterThan(boost, 0)
        XCTAssertLessThan(boost, LauncherPins.boost)
        XCTAssertLessThan(boost, LauncherRank.namedBoost)
        XCTAssertLessThan(boost, Int(QueryLearning.pointsPerBit))
        XCTAssertEqual(learning.placeBoost(item: "app:/Applications/Simulator.app", in: "com.apple.Safari", at: start), 0)
    }

    func testPlacesStayBounded() {
        var learning = QueryLearning()
        for i in 0..<(QueryLearning.maxPerPlace + 5) {
            learning.record(item: "item\(i)", in: "com.example.App", at: start + Double(i))
        }
        XCTAssertEqual(learning.places["com.example.App"]?.count, QueryLearning.maxPerPlace)
        for i in 0..<(QueryLearning.maxPlaces + 3) {
            learning.record(item: "cmd:quit", in: "com.example.App\(i)", at: start + 100 + Double(i))
        }
        XCTAssertEqual(learning.places.count, QueryLearning.maxPlaces)
    }

    func testForgetRemovesItemFromPlaces() {
        var learning = QueryLearning()
        learning.record(item: "safari", in: "com.example.App", at: start)
        learning.forget(item: "safari")
        XCTAssertTrue(learning.places.isEmpty)
    }

    func testPlacesRoundTripAndOldFilesStillRead() throws {
        var learning = QueryLearning()
        learning.record(query: "saf", item: "safari", at: start)
        learning.record(item: "safari", in: "com.example.App", at: start)
        let decoded = try JSONDecoder().decode(QueryLearning.self, from: JSONEncoder().encode(learning))
        XCTAssertEqual(decoded, learning)
        // learning.json from before places: no "places" key.
        let old = #"{"halfLife":2592000,"hits":{"saf":{"safari":{"weight":1,"updated":800000000}}}}"#
        let read = try JSONDecoder().decode(QueryLearning.self, from: Data(old.utf8))
        XCTAssertTrue(read.places.isEmpty)
        XCTAssertGreaterThan(read.boost(query: "saf", item: "safari", at: start), 0)
    }
}
