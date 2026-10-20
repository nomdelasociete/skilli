import XCTest
@testable import SkilliCore

final class ReminderDateTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!

    func testLocalTimeWithoutOffset() throws {
        let due = try XCTUnwrap(ReminderDate.parse("2026-10-11T21:00", timeZone: paris))
        XCTAssertTrue(due.hasTime)
        XCTAssertEqual(due.date, ISO8601DateFormatter().date(from: "2026-10-11T19:00:00Z"))
        XCTAssertEqual(ReminderDate.parse("2026-10-11 21:00:00".replacingOccurrences(of: " ", with: "T"), timeZone: paris)?.date, due.date)
    }

    func testOffsetAndZulu() {
        XCTAssertEqual(ReminderDate.parse("2026-10-11T21:00:00+02:00", timeZone: .gmt)?.date, ISO8601DateFormatter().date(from: "2026-10-11T19:00:00Z"))
        XCTAssertEqual(ReminderDate.parse("2026-10-11T19:00:00Z")?.hasTime, true)
    }

    func testDayAloneAndGarbage() {
        XCTAssertEqual(ReminderDate.parse("2026-10-12", timeZone: paris)?.hasTime, false)
        XCTAssertNil(ReminderDate.parse("tonight"))
        XCTAssertNil(ReminderDate.parse(""))
    }
}
