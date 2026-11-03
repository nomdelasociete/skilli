import XCTest
@testable import SkilliCore

final class AutoQuitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func app(_ id: String, unusedFor minutes: Double, front: Bool = false) -> AutoQuit.App {
        AutoQuit.App(bundleID: id, name: id, pid: 1, lastUsed: now.addingTimeInterval(-minutes * 60), isFront: front)
    }

    func testOnlyListedAppsUnusedForTheirOwnDelay() {
        let apps = [app("com.apple.Preview", unusedFor: 90), app("com.apple.Notes", unusedFor: 20), app("com.tinyspeck.slackmacgap", unusedFor: 200),
                    app("com.example.vpn", unusedFor: 600)]
        let rules = ["com.apple.Preview": 60, "com.apple.Notes": 15, "com.tinyspeck.slackmacgap": 240]
        let picked = AutoQuit.candidates(apps, now: now, rules: rules)
        // Preview at 90 of its 60 min, Notes at 20 of its 15; Slack at 200
        // of its 240 not yet; the VPN, not listed, never. Longest unused first.
        XCTAssertEqual(picked.map(\.bundleID), ["com.apple.Preview", "com.apple.Notes"])
    }

    func testAnAppNotListedIsNeverQuit() {
        let apps = [app("com.example.vpn", unusedFor: 10_000), app("com.docker.docker", unusedFor: 10_000)]
        XCTAssertEqual(AutoQuit.candidates(apps, now: now, rules: [:]), [])
        XCTAssertNil(AutoQuit.nextCheck(apps, now: now, rules: [:]), "nothing listed: no timer")
    }

    func testNeverTheFrontAppOrMacOSOwnEvenListed() {
        let apps = [app("com.apple.Safari", unusedFor: 300, front: true), app("com.apple.finder", unusedFor: 300),
                    app("com.nomdelasociete.Skilli", unusedFor: 300), app("com.apple.TextEdit", unusedFor: 300)]
        let rules = ["com.apple.Safari": 30, "com.apple.finder": 30, "com.nomdelasociete.Skilli": 30, "com.apple.TextEdit": 30]
        XCTAssertEqual(AutoQuit.candidates(apps, now: now, rules: rules).map(\.bundleID), ["com.apple.TextEdit"])
    }

    func testTheNextLookIsWhenTheNextListedAppIsDue() {
        let apps = [app("a", unusedFor: 10), app("b", unusedFor: 50), app("c", unusedFor: 500, front: true)]
        XCTAssertEqual(AutoQuit.nextCheck(apps, now: now, rules: ["a": 60, "b": 60, "c": 60]), now.addingTimeInterval(10 * 60))
        XCTAssertEqual(AutoQuit.nextCheck(apps, now: now, rules: ["a": 30, "b": 240]), now.addingTimeInterval(20 * 60), "each its own delay")
        XCTAssertEqual(AutoQuit.nextCheck([app("a", unusedFor: 120)], now: now, rules: ["a": 60]), now.addingTimeInterval(60), "a minute at least")
        XCTAssertNil(AutoQuit.nextCheck([app("c", unusedFor: 5, front: true)], now: now, rules: ["c": 60]))
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

    func testDelaysSpoken() {
        XCTAssertEqual(AutoQuit.delays.map { AutoQuit.spoken(minutes: $0) },
                       ["15 minutes", "30 minutes", "1 hour", "2 hours", "4 hours", "8 hours", "1 day"])
        XCTAssertTrue(AutoQuit.delays.contains(AutoQuit.defaultDelay))
        XCTAssertEqual(AutoQuit.spoken(minutes: 90), "1 hour 30 minutes")
        XCTAssertEqual(AutoQuit.spoken(minutes: 2_880), "2 days")
        XCTAssertEqual(AutoQuit.spoken(minutes: 1_500), "25 hours")
    }

    func testDelaysTyped() {
        XCTAssertEqual(AutoQuit.minutes(from: "90"), 90, "a bare number is minutes")
        XCTAssertEqual(AutoQuit.minutes(from: "45 min"), 45)
        XCTAssertEqual(AutoQuit.minutes(from: "3 h"), 180)
        XCTAssertEqual(AutoQuit.minutes(from: "1h30"), 90)
        XCTAssertEqual(AutoQuit.minutes(from: "1 hour 30 minutes"), 90)
        XCTAssertEqual(AutoQuit.minutes(from: "1.5 hours"), 90)
        XCTAssertEqual(AutoQuit.minutes(from: "1,5 h"), 90)
        XCTAssertEqual(AutoQuit.minutes(from: "2 jours"), 2_880)
        XCTAssertEqual(AutoQuit.minutes(from: "2 days"), 2_880)
        XCTAssertNil(AutoQuit.minutes(from: "2 min"), "under 5 minutes")
        XCTAssertNil(AutoQuit.minutes(from: "8 days"), "over a week")
        XCTAssertNil(AutoQuit.minutes(from: "soon"))
        XCTAssertEqual(AutoQuit.Rule(bundleID: "a", minutes: 1).minutes, 5, "kept in range")
    }

    func testToolItems() {
        XCTAssertEqual(AutoQuit.item(name: "Arc", minutes: 120), "Arc: 2 hours")
        XCTAssertEqual(AutoQuit.parseItem("Arc: 2 hours").app, "Arc")
        XCTAssertEqual(AutoQuit.parseItem("Arc: 2 hours").minutes, 120)
        XCTAssertEqual(AutoQuit.parseItem("Docker Desktop, 90 min").minutes, 90)
        XCTAssertEqual(AutoQuit.parseItem("Docker Desktop after 3h").app, "Docker Desktop")
        XCTAssertEqual(AutoQuit.parseItem("Preview").minutes, AutoQuit.defaultDelay, "no delay said: one hour")
        XCTAssertEqual(AutoQuit.parseItem("Preview").app, "Preview")
        XCTAssertNil(AutoQuit.parseItem("Preview: 1 min").minutes, "a delay out of range is refused, not changed")
        XCTAssertEqual(AutoQuit.parseItem("Final Cut Pro: 1 day").app, "Final Cut Pro")
    }
}
