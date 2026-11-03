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

    func testNumbersInHexBinaryAndOctal() {
        XCTAssertEqual(value("0xff"), "255", "alone, an answer")
        XCTAssertEqual(value("0xFF + 1"), "256")
        XCTAssertEqual(value("0b1010 * 2"), "20")
        XCTAssertEqual(value("0o17"), "15")
        XCTAssertEqual(value("0x10", french), "16", "not 0 × 10")
        XCTAssertEqual(value("0 x 10"), "0", "spaced, still multiplies")
        XCTAssertEqual(value("0.5 * 2"), "1")
        XCTAssertNil(value("0xg"))
        XCTAssertNil(value("0b2"))
    }

    func testBigNumbersInABaseAreExactOrNothing() {
        XCTAssertEqual(value("0x1FFFFFFFFFFFFF"), "9007199254740991", "every digit, not 9.0071993E15")
        XCTAssertEqual(value("0x20000000000000"), "9007199254740992")
        XCTAssertNil(value("0x20000000000001"), "past 2^53: not exact")
        XCTAssertNil(value("0x99999999999999999999"), "past Int64: never 0 × 999…")
        XCTAssertEqual(value("9007199254740992 in hex"), "0x20000000000000")
        XCTAssertNil(value("9007199254740993 in hex"), "rounded by a Double before the check")
        XCTAssertNil(value("123456789012345678901 in hex"))
        // Grouped as typed, read whole.
        XCTAssertNil(value("9 007 199 254 740 993 in hex"))
        XCTAssertEqual(value("9 007 199 254 740 992 in hex"), "0x20000000000000")
        // A fraction a Double rounds to a whole number.
        XCTAssertNil(value("1.0000000000000001 in hex"))
        XCTAssertEqual(value("2.5 * 2 in hex"), "0x5")
    }

    /// Past 2^53 on the way, the answer was rounded: no exact digits, no
    /// hex, even when what follows brings it back under.
    func testRoundedOnTheWayIsNotExact() {
        let past = Calculator.answers("0x20000000000000 + 1", locale: english)
        XCTAssertEqual(past.count, 1)
        XCTAssertNotEqual(past.first?.copy, "9007199254740992")
        XCTAssertEqual(Calculator.answers("(0x20000000000000 + 1) - 1", locale: english).count, 1)
        XCTAssertNotEqual(value("(0x20000000000000 + 1) - 1"), "9007199254740991")
        XCTAssertEqual(Calculator.answers("0x1FFFFFFFFFFFFF + 1", locale: english).map(\.copy), ["9007199254740992", "0x20000000000000"])
    }

    func testWrittenWithHexAnswersInHexToo() {
        let answers = Calculator.answers("0xff + 1", locale: english)
        XCTAssertEqual(answers.map(\.copy), ["256", "0x100"])
        XCTAssertEqual(Calculator.answers("0xff", locale: english).map(\.copy), ["255"], "no echo of what was typed")
        XCTAssertEqual(Calculator.answers("0xff / 2", locale: english).map(\.copy), ["127.5"], "a fraction has no hex")
        XCTAssertEqual(Calculator.answers("12 + 1", locale: english).map(\.copy), ["13"])
    }

    func testIntoABase() {
        XCTAssertEqual(value("255 in hex"), "0xFF")
        XCTAssertEqual(value("4096 en binaire", french), "0b1000000000000")
        XCTAssertEqual(value("0xff to dec"), "255")
        XCTAssertEqual(value("0b1010 → hexa"), "0xA")
        XCTAssertEqual(value("8 * 8 in octal"), "0o100")
        XCTAssertEqual(value("-255 in hex"), "-0xFF")
        XCTAssertNil(value("2.5 in hex"))
        XCTAssertNil(value("1e300 in hex"))
        XCTAssertEqual(Calculator.evaluate("255 in hex", locale: english)?.detail, "255 → hex")
        // Units still convert.
        XCTAssertNotNil(value("10 km in miles"))
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
