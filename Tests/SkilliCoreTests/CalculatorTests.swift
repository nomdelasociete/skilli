import XCTest
@testable import SkilliCore

final class CalculatorTests: XCTestCase {
    private let french = Locale(identifier: "fr_FR")
    private let english = Locale(identifier: "en_US")

    private func value(_ text: String, _ locale: Locale = Locale(identifier: "en_US")) -> String? {
        Calculator.evaluate(text, locale: locale)?.copy
    }

    func testArithmeticAsTyped() {
        XCTAssertEqual(value("2 + 3 * 4"), "14")
        XCTAssertEqual(value("(2 + 3) * 4"), "20")
        XCTAssertEqual(value("2^10"), "1024")
        XCTAssertEqual(value("10 / 4"), "2.5")
        XCTAssertEqual(value("0.1 + 0.2"), "0.3")
        XCTAssertEqual(value("3 x 4"), "12")
        XCTAssertEqual(value("12 × 3 ÷ 4"), "9")
        XCTAssertEqual(value("-5 + 2"), "-3")
        XCTAssertEqual(value("sqrt(16) + 1"), "5")
        XCTAssertEqual(value("√9 * 2"), "6")
        XCTAssertEqual(value("2 * pi"), "6.28318531")
    }

    func testFrenchNumbersAndThousands() {
        XCTAssertEqual(value("12,5 × 4", french), "50")
        XCTAssertEqual(value("1 234,5 + 0,5", french), "1235")
        XCTAssertEqual(value("10 / 4", french), "2,5")
        XCTAssertEqual(Calculator.evaluate("1234,5 * 2", locale: french)?.display, 2469.formatted(.number.locale(french)))
        // In English a comma groups thousands.
        XCTAssertEqual(value("1,234 + 1", english), "1235")
        XCTAssertEqual(value("1,234.5 * 2", english), "2469")
    }

    func testPercentagesAsSaid() {
        XCTAssertEqual(value("20% of 85"), "17")
        XCTAssertEqual(value("20 % de 85", french), "17")
        XCTAssertEqual(value("85 + 20%"), "102")
        XCTAssertEqual(value("85 - 15%"), "72.25")
        XCTAssertEqual(value("50 * 10%"), "5")
    }

    func testNotACalculation() {
        XCTAssertNil(Calculator.evaluate("42", locale: english))
        XCTAssertNil(Calculator.evaluate("safari", locale: english))
        XCTAssertNil(Calculator.evaluate("max 3", locale: english))
        XCTAssertNil(Calculator.evaluate("2 +", locale: english))
        XCTAssertNil(Calculator.evaluate("rendez-vous en ville", locale: french))
        XCTAssertNil(Calculator.evaluate("e", locale: english))
    }

    func testUnits() {
        XCTAssertEqual(Calculator.evaluate("10 km in miles", locale: english)?.display, "6.21371192 mi")
        XCTAssertEqual(value("10 mi to km"), "16.09344")
        XCTAssertEqual(value("32 °F to °C"), "0")
        XCTAssertEqual(value("100 c in f"), "212")
        XCTAssertEqual(value("1,5 go en mo", french), "1500")
        XCTAssertEqual(value("100 km/h en mph", french), "62,13711922")
        XCTAssertEqual(value("10 in to cm"), "25.4")
        XCTAssertEqual(value("5 fl oz in ml"), "147.86764781")
        XCTAssertEqual(value("2 h en min", french), "120")
        XCTAssertEqual(value("3 jours en heures", french), "72")
        XCTAssertEqual(value("1 lb in kg"), "0.45359237")
        XCTAssertEqual(value("10km in m"), "10000")
        XCTAssertNil(Calculator.evaluate("10 km in kg", locale: english), "length is not mass")
        XCTAssertEqual(Calculator.evaluate("10 mi to km", locale: english)?.detail, "10 mi → km")
    }

    func testTimeElsewhere() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let tokyo = try XCTUnwrap(Calculator.evaluate("heure à Tokyo", locale: english, now: noon))
        XCTAssertTrue(tokyo.display.contains("21:00") || tokyo.display.contains("9:00"), tokyo.display)
        XCTAssertTrue(tokyo.display.hasSuffix("in Tokyo"))
        XCTAssertNotNil(Calculator.evaluate("time in new york", locale: english, now: noon))
        XCTAssertNotNil(Calculator.evaluate("San Francisco time", locale: english, now: noon))
        XCTAssertNil(Calculator.evaluate("time in narnia", locale: english, now: noon))
    }
}
