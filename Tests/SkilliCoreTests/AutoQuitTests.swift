import XCTest
@testable import SkilliCore

final class AutoQuitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func app(_ id: String, unusedFor minutes: Double, front: Bool = false) -> AutoQuit.App {
        AutoQuit.App(bundleID: id, name: id, pid: 1, lastUsed: now.addingTimeInterval(-minutes * 60), isFront: front)
    }

    func testOnlyAppsUnusedForTheDelay() {
        let apps = [app("com.apple.Preview", unusedFor: 90), app("com.apple.Notes", unusedFor: 20), app("com.tinyspeck.slackmacgap", unusedFor: 200)]
        let picked = AutoQuit.candidates(apps, now: now, delay: 3_600, never: [])
        XCTAssertEqual(picked.map(\.bundleID), ["com.tinyspeck.slackmacgap", "com.apple.Preview"], "the longest unused first")
    }

    func testNeverTheFrontAppTheKeptOnesOrMacOSOwn() {
        let apps = [app("com.apple.Safari", unusedFor: 300, front: true), app("com.apple.finder", unusedFor: 300),
                    app("com.nomdelasociete.Skilli", unusedFor: 300), app("com.spotify.client", unusedFor: 300),
                    app("com.apple.TextEdit", unusedFor: 300)]
        let picked = AutoQuit.candidates(apps, now: now, delay: 1_800, never: ["com.spotify.client"])
        XCTAssertEqual(picked.map(\.bundleID), ["com.apple.TextEdit"])
    }

    func testTheNextLookIsWhenTheNextAppIsDue() {
        let apps = [app("a", unusedFor: 10), app("b", unusedFor: 50), app("c", unusedFor: 500, front: true)]
        XCTAssertEqual(AutoQuit.nextCheck(apps, now: now, delay: 3_600, never: []), now.addingTimeInterval(10 * 60))
        XCTAssertEqual(AutoQuit.nextCheck([app("a", unusedFor: 120)], now: now, delay: 3_600, never: []), now.addingTimeInterval(60),
                       "a minute at least")
        XCTAssertNil(AutoQuit.nextCheck([app("c", unusedFor: 5, front: true)], now: now, delay: 3_600, never: []))
        XCTAssertNil(AutoQuit.nextCheck([app("a", unusedFor: 5)], now: now, delay: 3_600, never: ["a"]))
    }

    func testBusy() {
        XCTAssertTrue(AutoQuit.isBusy(cpuSeconds: 0.3, over: 3), "10 % of a core: an export")
        XCTAssertFalse(AutoQuit.isBusy(cpuSeconds: 0.03, over: 3), "1 %: idle")
        XCTAssertFalse(AutoQuit.isBusy(cpuSeconds: 1, over: 0))
    }

    func testWhatJevReadsIsTheNameAndTheTitles() {
        XCTAssertEqual(AutoQuit.describe(name: "Terminal", titles: ["~ — ssh deploy@box — 80×24", " "]),
                       "Terminal — windows: “~ — ssh deploy@box — 80×24”")
        XCTAssertEqual(AutoQuit.describe(name: "Preview", titles: []), "Preview — no window open")
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(AutoQuit.describe(name: "X", titles: [long]).count, "X — windows: “”".count + 120)
    }

    func testDelays() {
        XCTAssertEqual(AutoQuit.delays.map { AutoQuit.spoken(minutes: $0) }, ["30 minutes", "1 hour", "2 hours", "4 hours"])
        XCTAssertTrue(AutoQuit.delays.contains(AutoQuit.defaultDelay))
    }
}
