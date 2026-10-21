import CoreGraphics
import Foundation
import XCTest
@testable import SkilliCore

final class RecentSearchesTests: XCTestCase {
    func testNewestFirstAndTheSameWordsMoveToTheFront() {
        var recent = RecentSearches()
        recent.record("saf")
        recent.record("  2 + 2 ")
        recent.record("Saf")
        XCTAssertEqual(recent.entries, ["Saf", "2 + 2"])
    }

    func testNothingTypedIsNotKept() {
        var recent = RecentSearches()
        recent.record("")
        recent.record("   ")
        recent.record("two\nlines")
        XCTAssertEqual(recent.entries, [])
    }

    func testKeepsTheLastTwenty() {
        var recent = RecentSearches()
        for number in 1...25 { recent.record("search \(number)") }
        XCTAssertEqual(recent.entries.count, RecentSearches.limit)
        XCTAssertEqual(recent.entries.first, "search 25")
        XCTAssertEqual(recent.entries.last, "search 6")
    }

    func testALongSearchIsKeptCut() {
        var recent = RecentSearches()
        recent.record(String(repeating: "a", count: 2_000))
        XCTAssertEqual(recent.entries.first?.count, RecentSearches.maxLength)
    }

    /// ↑ ↑ walks back, ↓ forward, ↓ past the newest is the empty field again.
    func testUpGoesBackDownComesForwardLikeAShell() {
        let recent = RecentSearches(entries: ["third", "second", "first"])
        XCTAssertEqual(recent.older(than: nil), 0)
        XCTAssertEqual(recent.older(than: 0), 1)
        XCTAssertEqual(recent.older(than: 1), 2)
        XCTAssertNil(recent.older(than: 2), "nothing older than the oldest")
        XCTAssertEqual(recent.newer(than: 2), 1)
        XCTAssertEqual(recent.newer(than: 1), 0)
        XCTAssertNil(recent.newer(than: 0), "past the newest: the empty field")
        XCTAssertNil(RecentSearches().older(than: nil))
    }

    func testReadBackAsSaved() throws {
        var recent = RecentSearches()
        recent.record("calc")
        recent.record("g rust")
        let data = try JSONEncoder().encode(recent)
        XCTAssertEqual(try JSONDecoder().decode(RecentSearches.self, from: data), recent)
    }

    /// A file edited by hand: duplicates and blanks go, the limit holds.
    func testAFileEditedByHandIsCleanedOnRead() throws {
        let json = #"{"entries":["a","A","","b"]}"#
        let read = try JSONDecoder().decode(RecentSearches.self, from: Data(json.utf8))
        XCTAssertEqual(read.entries, ["a", "b"])
    }
}

final class LauncherPinsTests: XCTestCase {
    func testPinnedInTheOrderPinnedAndOnce() {
        var pins: [String] = []
        pins = LauncherPins.pinning("app:/Applications/Safari.app", in: pins)
        pins = LauncherPins.pinning("cmd:emoji", in: pins)
        pins = LauncherPins.pinning("app:/Applications/Safari.app", in: pins)
        XCTAssertEqual(pins, ["app:/Applications/Safari.app", "cmd:emoji"])
        XCTAssertEqual(LauncherPins.unpinning("app:/Applications/Safari.app", in: pins), ["cmd:emoji"])
        XCTAssertEqual(LauncherPins.unpinning("cmd:nothing", in: pins), pins)
    }

    func testPinnedFirstThenTheRestWithoutThem() {
        let suggestions = ["app:Mail", "app:Safari", "app:Notes", "app:Xcode"]
        let pinned = ["cmd:emoji", "app:Notes"]
        XCTAssertEqual(LauncherPins.first(pinned, then: suggestions) { $0 }, ["cmd:emoji", "app:Notes", "app:Mail", "app:Safari", "app:Xcode"])
        XCTAssertEqual(LauncherPins.first([], then: suggestions) { $0 }, suggestions)
    }

    func testPinsOfItemsGoneAreDropped() {
        let pins = ["app:/Applications/Gone.app", "cmd:emoji", "cmd:emoji", "quicklink:old"]
        let kept = LauncherPins.kept(pins) { $0 == "app:/Applications/Gone.app" || $0 == "quicklink:old" }
        XCTAssertEqual(kept, ["cmd:emoji"])
    }

    /// The boost lifts a pinned item over an even match, not over a
    /// learned pick.
    func testTheBoostIsLessThanALearnedPick() {
        var learning = QueryLearning()
        learning.record(query: "cal", item: "app:Calendar", at: .now)
        XCTAssertGreaterThan(learning.boost(query: "cal", item: "app:Calendar", at: .now), LauncherPins.boost)
        XCTAssertGreaterThan(LauncherPins.boost, 0)
    }
}

final class LauncherOpeningTests: XCTestCase {
    /// The main display, and a second one to its right, higher.
    private let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let right = CGRect(x: 1512, y: -200, width: 2560, height: 1440)

    func testThePointersScreenByDefault() {
        XCTAssertEqual(LauncherScreen.pointer.pick(screens: [main, right], pointerScreen: 1, frontWindow: main), 1)
        XCTAssertNil(LauncherScreen.pointer.pick(screens: [main, right], pointerScreen: nil, frontWindow: nil))
    }

    func testTheMainDisplay() {
        XCTAssertEqual(LauncherScreen.main.pick(screens: [main, right], pointerScreen: 1, frontWindow: nil), 0)
        XCTAssertNil(LauncherScreen.main.pick(screens: [], pointerScreen: nil, frontWindow: nil))
    }

    func testTheScreenThatShowsMostOfTheWindowInFront() {
        // Mostly on the right display, a little on the main one.
        let window = CGRect(x: 1400, y: 100, width: 900, height: 600)
        XCTAssertEqual(LauncherScreen.frontWindow.pick(screens: [main, right], pointerScreen: 0, frontWindow: window), 1)
        // No window in front, or one off every screen: the pointer's.
        XCTAssertEqual(LauncherScreen.frontWindow.pick(screens: [main, right], pointerScreen: 0, frontWindow: nil), 0)
        let off = CGRect(x: -5000, y: 0, width: 200, height: 200)
        XCTAssertEqual(LauncherScreen.frontWindow.pick(screens: [main, right], pointerScreen: 1, frontWindow: off), 1)
    }

    func testWindowServerFramesTurnIntoAppKitOnes() {
        // 100 pt from the top of a 982 pt main display, 300 tall.
        let frame = LauncherScreen.appKitFrame(fromTopLeft: CGRect(x: 40, y: 100, width: 500, height: 300), mainHeight: 982)
        XCTAssertEqual(frame, CGRect(x: 40, y: 582, width: 500, height: 300))
    }

    func testStartsAgainEmptyAfterItsTime() {
        XCTAssertFalse(LauncherReset.immediately.keepsSearch(closedFor: .zero))
        XCTAssertTrue(LauncherReset.afterOneMinute.keepsSearch(closedFor: .seconds(59)))
        XCTAssertFalse(LauncherReset.afterOneMinute.keepsSearch(closedFor: .seconds(60)))
        XCTAssertTrue(LauncherReset.afterFiveMinutes.keepsSearch(closedFor: .seconds(299)))
        XCTAssertFalse(LauncherReset.afterFiveMinutes.keepsSearch(closedFor: .seconds(301)))
        XCTAssertTrue(LauncherReset.never.keepsSearch(closedFor: .seconds(86_400)))
    }

    /// Settings shows them in this order; tools will name them by value.
    func testChoicesAndTheirNames() {
        XCTAssertEqual(LauncherScreen.allCases.map(\.rawValue), ["pointer", "frontWindow", "main"])
        XCTAssertEqual(LauncherReset.allCases.map(\.title), ["Right away", "After 1 minute", "After 5 minutes", "Never"])
    }
}

/// Rows built as the launcher builds them: names first (a title; a pane's
/// name in each language), then keywords; even scores, the shorter title.
final class LauncherRankTests: XCTestCase {
    private struct Row {
        let title: String
        let names: [FuzzyCandidate]
        let keywords: [FuzzyCandidate]

        init(_ title: String, names: [String]? = nil, keywords: [String]) {
            self.title = title
            self.names = (names ?? [title]).map(FuzzyCandidate.init)
            self.keywords = keywords.map(FuzzyCandidate.init)
        }

        func score(_ text: String) -> Int? {
            LauncherRank.score(FuzzyMatcher.Query(text), names: names[...], keywords: keywords[...])
        }
    }

    private static func window(_ layout: WindowLayout) -> Row { Row(layout.title, keywords: layout.keywords) }
    private static func mac(_ command: SystemCommand) -> Row { Row(command.title, keywords: command.keywords) }
    /// A System Settings pane as `MacAction` lists it: its names, then
    /// "… settings".
    private static func pane(_ name: String, _ otherNames: String...) -> Row {
        Row(name, names: [name] + otherNames, keywords: ([name] + otherNames).map { "\($0) settings" })
    }

    private func ranked(_ text: String, _ rows: [Row]) -> [String] {
        rows.compactMap { row in row.score(text).map { (row.title, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.count < $1.0.count }
            .map(\.0)
    }

    private let displayRows = [window(.nextDisplay), window(.previousDisplay), mac(.sleepDisplays), pane("Moniteurs", "Displays")]

    /// Asked: "display" finds System Settings' Displays first, before
    /// the window moves whose keyword it is; on a French Mac and an English one.
    func testANameTypedWholeComesBeforeAKeyword() {
        for text in ["display", "displays", "Displays", "moniteur", "moniteurs"] {
            XCTAssertEqual(ranked(text, displayRows).first, "Moniteurs", text)
        }
        let english = [Self.window(.nextDisplay), Self.window(.previousDisplay), Self.mac(.sleepDisplays), Self.pane("Displays")]
        XCTAssertEqual(ranked("display", english).first, "Displays")
        // A keyword still finds its row, after the name.
        XCTAssertEqual(Array(ranked("display", displayRows).prefix(3)), ["Moniteurs", "Move to Next Display", "Move to Previous Display"])
        XCTAssertEqual(ranked("screen", displayRows).first, "Move to Next Display", "no row is named “screen”")
    }

    /// Punctuation aside: System Settings writes "Wi‑Fi" with a
    /// non-breaking hyphen, the switch has "wifi" as a keyword.
    func testWiFiItsPaneByName() {
        let rows = [Self.mac(.wifiOff), Self.mac(.speedTest), Self.pane("Wi‑Fi")]
        XCTAssertEqual(ranked("wifi", rows).first, "Wi‑Fi")
        XCTAssertEqual(ranked("couper le wifi", rows).first, "Turn Wi-Fi Off", "the switch's own words")
    }

    /// The same for every row: an app named so comes before a command whose
    /// keyword it is ("contact": Contacts, then Search Contacts).
    func testTheSameForAppsAndCommands() throws {
        let contacts = LauncherCommand.all.first { $0.id == .searchContacts }
        let command = try XCTUnwrap(contacts?.score(FuzzyMatcher.Query("contact")))
        let app = try XCTUnwrap(LauncherRank.score(FuzzyMatcher.Query("contact"), names: [FuzzyCandidate("Contacts")][...]))
        XCTAssertGreaterThan(app, command)
        // A command named so gains it too; two rows named so stay as even as before.
        let calendar = LauncherCommand.all.first { $0.id == .agenda }
        XCTAssertEqual(calendar?.score(FuzzyMatcher.Query("calendar")),
                       LauncherRank.score(FuzzyMatcher.Query("calendar"), names: [FuzzyCandidate("Calendar")][...]))
    }

    /// The boost sits between a pin and one pick learned: the user's habit
    /// for those words still comes first.
    func testOneLearnedPickStillComesFirst() throws {
        XCTAssertGreaterThan(LauncherRank.namedBoost, LauncherPins.boost)
        XCTAssertLessThan(Double(LauncherRank.namedBoost), QueryLearning.pointsPerBit)
        var learning = QueryLearning()
        let now = Date()
        learning.record(query: "display", item: "system:window.nextDisplay", at: now)
        let picked = try XCTUnwrap(Self.window(.nextDisplay).score("display")) + learning.boost(query: "display", item: "system:window.nextDisplay", at: now)
        let pane = try XCTUnwrap(Self.pane("Moniteurs", "Displays").score("display"))
        XCTAssertGreaterThan(picked, pane)
    }

    /// "réglages bluetooth" asks for the pane: it stays first and Allow
    /// Bluetooth comes next; "bluetooth" alone or "connecte mes AirPods":
    /// Allow Bluetooth first, as before.
    func testAnOfferGoesAfterThePaneAskedFor() throws {
        let bluetooth = Self.pane("Bluetooth")
        let asked = try XCTUnwrap(SystemSettingsPane.asked("réglages bluetooth"))
        XCTAssertTrue(LauncherRank.names(FuzzyMatcher.Query(asked), bluetooth.names[...]))
        XCTAssertTrue(LauncherRank.names(FuzzyMatcher.Query(try XCTUnwrap(SystemSettingsPane.asked("Bluetooth settings"))), bluetooth.names[...]))
        XCTAssertEqual(LauncherRank.offerPlace(asksForSettings: true, named: [true, false, false]), 1)
        XCTAssertEqual(LauncherRank.offerPlace(asksForSettings: true, named: [false, true, false]), 2)
        XCTAssertEqual(LauncherRank.offerPlace(asksForSettings: false, named: [true, false]), 0)
        XCTAssertEqual(LauncherRank.offerPlace(asksForSettings: true, named: [false, false]), 0, "no pane by that name")
        XCTAssertEqual(LauncherRank.offerPlace(asksForSettings: false, named: []), 0)
    }
}

final class RootSearchSettingsTests: XCTestCase {
    /// Tools set the two settings by the values the pane offers; pins stay
    /// the user's own, out of get_settings.
    func testTheTwoSettingsHaveTheirToolAndPinsStayOut() throws {
        let screen = try SettingsTable.entry(pane: "Launcher", setting: "Opens on") { $0 }
        XCTAssertEqual(screen.key, "launcherScreen")
        XCTAssertEqual(SettingsTable.options(of: screen).map(\.value), LauncherScreen.allCases.map(\.rawValue))
        XCTAssertTrue(screen.usesSetSetting)
        let reset = try SettingsTable.entry(pane: "launcher", setting: "starts again empty") { $0 }
        XCTAssertEqual(try SettingsTable.parse("never", for: reset, paneTitle: "Launcher"), .text("never"))
        XCTAssertEqual(try SettingsTable.parse("After 5 minutes", for: reset, paneTitle: "Launcher"), .text("afterFiveMinutes"))
        XCTAssertNotNil(SettingsTable.notInPanes["launcherPins"])
        XCTAssertFalse(SettingsTable.preferences.contains("launcherPins"))
    }
}
