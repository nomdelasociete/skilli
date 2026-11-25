@testable import SkilliCore
import os
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

    func testAMeetingStartingWaitsForARelaunchUnderWay() {
        let gate = RecordingGate()
        let inside = DispatchSemaphore(value: 0)
        let order = OSAllocatedUnfairLock(initialState: [String]())
        let relaunch = Thread {
            gate.unlessRecording {
                inside.signal()
                // The watcher started, the process about to end.
                Thread.sleep(forTimeInterval: 0.2)
                order.withLock { $0.append("relaunch done") }
            }
        }
        relaunch.start()
        inside.wait()
        // The main thread back, a meeting beginning: before its first file.
        gate.isRecording = true
        order.withLock { $0.append("meeting begins") }
        XCTAssertEqual(order.withLock { $0 }, ["relaunch done", "meeting begins"])
    }

    func testNoRelaunchOnceAMeetingBegan() {
        let gate = RecordingGate()
        gate.isRecording = true
        XCTAssertFalse(gate.unlessRecording { XCTFail("a meeting records") })
        gate.isRecording = false
        let ran = OSAllocatedUnfairLock(initialState: false)
        XCTAssertTrue(gate.unlessRecording { ran.withLock { $0 = true } })
        XCTAssertTrue(ran.withLock { $0 })
    }
}
