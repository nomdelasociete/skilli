@testable import SkilliCore
import XCTest

final class LauncherShorthandTests: XCTestCase {
    private let aliases = [LauncherAlias(id: "system:keepAwake", alias: "a", title: "Keep Awake"),
                           LauncherAlias(id: "cmd:recordMeeting", alias: "r", title: "Record Meeting"),
                           LauncherAlias(id: "cmd:emoji", alias: "e", title: "Emoji")]

    func testAWordCutShortThenItsValue() {
        XCTAssertEqual(LauncherShorthand.expand("awa 2h", aliases: []), "awake 2h")
        XCTAssertEqual(LauncherShorthand.expand("Aw 2", aliases: []), "awake 2")
        XCTAssertEqual(LauncherShorthand.expand("tim 10 tea", aliases: []), "timer 10 tea")
        XCTAssertEqual(LauncherShorthand.expand("vo 30", aliases: []), "volume 30")
        // The command's own parser reads what comes back.
        XCTAssertEqual(LauncherShorthand.expand("awa 2h", aliases: []).flatMap { AwakeRequest.parse($0) }, .awake(seconds: 7_200))
        XCTAssertEqual(LauncherShorthand.expand("ti 1:30", aliases: []).flatMap(TimerRequest.parse)?.seconds, 90)
        XCTAssertEqual(LauncherShorthand.expand("volu 30", aliases: []).flatMap(VolumeRequest.parse), 30)
    }

    func testNothingToReadYet() {
        XCTAssertNil(LauncherShorthand.expand("awa", aliases: []), "no space: still a search")
        XCTAssertNil(LauncherShorthand.expand("awa ", aliases: []), "nothing after the space yet")
        XCTAssertNil(LauncherShorthand.expand("a 2h", aliases: []), "one letter says too little")
        XCTAssertNil(LauncherShorthand.expand("awake 2h", aliases: []), "whole already: read as typed")
        XCTAssertNil(LauncherShorthand.expand("visual st", aliases: []))
        XCTAssertNil(LauncherShorthand.expand("re Weekly sync", aliases: []), "free text only after the word or an alias")
        XCTAssertNil(LauncherShorthand.expand("ev demain 14h", aliases: []))
        XCTAssertNil(LauncherShorthand.expand("t2 5", aliases: []))
        // A search that is not a value stays a search for the parser too.
        XCTAssertNil(LauncherShorthand.expand("vo studio", aliases: []).flatMap(VolumeRequest.parse))
        XCTAssertNil(LauncherShorthand.expand("awa soon", aliases: []).flatMap { AwakeRequest.parse($0) })
    }

    func testAnAliasCarriesTheValueOfItsRow() {
        XCTAssertEqual(LauncherShorthand.expand("a 2h", aliases: aliases), "awake 2h")
        XCTAssertEqual(LauncherShorthand.expand("A until 6pm", aliases: aliases), "awake until 6pm")
        XCTAssertEqual(LauncherShorthand.expand("r Weekly sync", aliases: aliases), "rec Weekly sync")
        XCTAssertEqual(LauncherShorthand.expand("r Weekly sync", aliases: aliases).flatMap(RecordRequest.name), "Weekly sync")
        XCTAssertNil(LauncherShorthand.expand("e smile", aliases: aliases), "a mode's alias opens the mode, as before")
        XCTAssertNil(LauncherShorthand.expand("a ", aliases: aliases))
    }

    func testEveryShortenedWordIsTaught() {
        // Two letters always tell them apart: a new word must too.
        let starts = LauncherShorthand.shortened.map { $0.prefix(LauncherShorthand.minimum) }
        XCTAssertEqual(Set(starts).count, starts.count)
    }
}
