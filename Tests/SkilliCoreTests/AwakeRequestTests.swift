import XCTest
@testable import SkilliCore

final class AwakeRequestTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    /// 2026-10-12 13:00 in Paris.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 13))! }

    func testDurations() {
        XCTAssertEqual(AwakeRequest.parse("awake 1 hour"), .awake(seconds: 3_600))
        XCTAssertEqual(AwakeRequest.parse("do not sleep 1"), .awake(seconds: 3_600))
        XCTAssertEqual(AwakeRequest.parse("don't sleep 2h"), .awake(seconds: 7_200))
        XCTAssertEqual(AwakeRequest.parse("keep awake 30 min"), .awake(seconds: 1_800))
        XCTAssertEqual(AwakeRequest.parse("garde le mac éveillé 1h30"), .awake(seconds: 5_400))
        XCTAssertEqual(AwakeRequest.parse("pas de veille pendant 3 heures"), .awake(seconds: 10_800))
        XCTAssertEqual(AwakeRequest.parse("caffeinate 90"), .awake(seconds: 5_400), "above 24, a bare number is minutes")
        XCTAssertEqual(AwakeRequest.parse("Amphetamine 4"), .awake(seconds: 14_400))
    }

    func testUntilATime() {
        XCTAssertEqual(AwakeRequest.parse("awake until 6pm", now: now, calendar: calendar), .awake(seconds: 5 * 3_600))
        XCTAssertEqual(AwakeRequest.parse("garde le mac éveillé jusqu'à 18h30", now: now, calendar: calendar), .awake(seconds: 5 * 3_600 + 1_800))
        XCTAssertEqual(AwakeRequest.parse("no sleep till 9:00", now: now, calendar: calendar), .awake(seconds: 20 * 3_600), "past today: tomorrow")
    }

    func testOffAndNotAwake() {
        XCTAssertEqual(AwakeRequest.parse("allow sleep"), .allowSleep)
        XCTAssertEqual(AwakeRequest.parse("laisse le mac dormir"), .allowSleep)
        XCTAssertNil(AwakeRequest.parse("keep awake"), "no duration: the Keep Awake command")
        XCTAssertNil(AwakeRequest.parse("réveille-moi dans 10 minutes"), "a wake-up, not staying awake")
        XCTAssertNil(AwakeRequest.parse("timer 10 min"))
        XCTAssertNil(AwakeRequest.parse("awake 0"))
        XCTAssertEqual(AwakeRequest.spoken(5_400), "1 h 30")
    }

}

final class AwakeStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func time(_ date: Date) -> String { "T+\(Int(date.timeIntervalSince(now)))" }

    func testMentionsTheWordsWithOrWithoutALength() {
        XCTAssertTrue(AwakeRequest.mentions("awake"))
        XCTAssertTrue(AwakeRequest.mentions("keep awake"))
        XCTAssertTrue(AwakeRequest.mentions("Awake 2h"))
        XCTAssertTrue(AwakeRequest.mentions("caffeinate"))
        XCTAssertTrue(AwakeRequest.mentions("allow sleep"))
        XCTAssertTrue(AwakeRequest.mentions("éveillé"))
        XCTAssertFalse(AwakeRequest.mentions("awa"), "whole words only: a few letters open an app")
        XCTAssertFalse(AwakeRequest.mentions("sleep"), "the Sleep command")
        XCTAssertFalse(AwakeRequest.mentions("timer 10 min"))
        XCTAssertFalse(AwakeRequest.mentions(""))
    }

    func testTimeLeft() {
        XCTAssertEqual(AwakeStatus.left(until: now.addingTimeInterval(42 * 60), now: now), "42 min")
        XCTAssertEqual(AwakeStatus.left(until: now.addingTimeInterval(41 * 60 + 1), now: now), "42 min", "rounded up")
        XCTAssertEqual(AwakeStatus.left(until: now.addingTimeInterval(80 * 60), now: now), "1 h 20")
        XCTAssertEqual(AwakeStatus.left(until: now.addingTimeInterval(65 * 60), now: now), "1 h 05")
        XCTAssertEqual(AwakeStatus.left(until: now.addingTimeInterval(3 * 3_600), now: now), "3 h")
        XCTAssertEqual(AwakeStatus.left(until: now.addingTimeInterval(-5), now: now), "1 min", "never 0")
    }

    func testRunningTitle() {
        XCTAssertEqual(AwakeStatus.title(until: now.addingTimeInterval(42 * 60), now: now, time: time),
                       "Keeping Awake · 42 min left (until T+2520)")
        XCTAssertEqual(AwakeStatus.title(until: nil, now: now, time: time), "Keeping Awake · until you allow sleep")
    }

    func testOneHourLonger() {
        XCTAssertEqual(AwakeStatus.secondsLonger(until: now.addingTimeInterval(42 * 60), now: now), 42 * 60 + 3_600)
        XCTAssertEqual(AwakeStatus.secondsLonger(until: now.addingTimeInterval(-30), now: now), 3_600, "ended: an hour from now")
    }
}
