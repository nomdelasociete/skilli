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
