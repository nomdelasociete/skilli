@testable import SkilliCore
import XCTest

final class HangWatchTests: XCTestCase {
    func testAMainThreadThatAnswersIsAskedAgain() {
        var watch = HangWatch()
        XCTAssertEqual(watch.tick(now: 0, recording: false, sinceRelaunch: nil), .ask)
        watch.answered()
        XCTAssertEqual(watch.tick(now: 5, recording: false, sinceRelaunch: nil), .ask)
    }

    func testHeldIsCapturedOnceThenRelaunched() {
        var watch = HangWatch()
        XCTAssertEqual(watch.tick(now: 0, recording: false, sinceRelaunch: nil), .ask)
        XCTAssertEqual(watch.tick(now: 25, recording: false, sinceRelaunch: nil), .wait, "slow is not held")
        XCTAssertEqual(watch.tick(now: 30, recording: false, sinceRelaunch: nil), .capture)
        XCTAssertEqual(watch.tick(now: 35, recording: false, sinceRelaunch: nil), .relaunch)
    }

    func testAnAnswerAfterTheCaptureKeepsSkilliRunning() {
        var watch = HangWatch()
        _ = watch.tick(now: 0, recording: false, sinceRelaunch: nil)
        XCTAssertEqual(watch.tick(now: 31, recording: false, sinceRelaunch: nil), .capture)
        watch.answered()
        XCTAssertEqual(watch.tick(now: 36, recording: false, sinceRelaunch: nil), .ask)
        XCTAssertEqual(watch.tick(now: 70, recording: false, sinceRelaunch: nil), .capture, "held again: captured again")
    }

    func testARecordingIsNotCutShort() {
        var watch = HangWatch()
        _ = watch.tick(now: 0, recording: true, sinceRelaunch: nil)
        XCTAssertEqual(watch.tick(now: 30, recording: true, sinceRelaunch: nil), .capture)
        XCTAssertEqual(watch.tick(now: 35, recording: true, sinceRelaunch: nil), .wait)
        XCTAssertEqual(watch.tick(now: 40, recording: true, sinceRelaunch: nil), .wait, "captured once")
        XCTAssertEqual(watch.tick(now: 45, recording: false, sinceRelaunch: nil), .relaunch)
    }

    func testNoRelaunchRightAfterAnother() {
        var watch = HangWatch()
        _ = watch.tick(now: 0, recording: false, sinceRelaunch: 40)
        XCTAssertEqual(watch.tick(now: 30, recording: false, sinceRelaunch: 70), .capture)
        XCTAssertEqual(watch.tick(now: 35, recording: false, sinceRelaunch: 75), .wait)
        XCTAssertEqual(watch.tick(now: 600, recording: false, sinceRelaunch: 640), .relaunch, "still held ten minutes on")
        var other = HangWatch()
        _ = other.tick(now: 0, recording: false, sinceRelaunch: -5)
        _ = other.tick(now: 30, recording: false, sinceRelaunch: -5)
        XCTAssertEqual(other.tick(now: 35, recording: false, sinceRelaunch: -5), .relaunch, "a clock set back does not hold it")
    }
}
