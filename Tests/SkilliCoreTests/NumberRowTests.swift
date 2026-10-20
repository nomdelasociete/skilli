import XCTest
@testable import SkilliCore

final class NumberRowTests: XCTestCase {
    func testAZERTYNumberRowNamesDigits() {
        // French AZERTY: & é " ' ( - è _ ç à, digits with Shift.
        XCTAssertEqual(NumberRow.shortcutDigit("1", unshifted: "&", shifted: "1"), "1")
        XCTAssertEqual(NumberRow.shortcutDigit("2", unshifted: "é", shifted: "2"), "2")
        XCTAssertEqual(NumberRow.shortcutDigit("0", unshifted: "à", shifted: "0"), "0")
        // QWERTY: the key already types the digit.
        XCTAssertNil(NumberRow.shortcutDigit("1", unshifted: "1", shifted: "!"))
        // A layout whose Shift gives something else: left alone.
        XCTAssertNil(NumberRow.shortcutDigit("1", unshifted: "+", shifted: "°"))
    }
}
