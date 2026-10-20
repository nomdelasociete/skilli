import XCTest
@testable import SkilliCore

final class TextTransformTests: XCTestCase {
    private let french = Locale(identifier: "fr_FR")

    func testUppercaseKeepsAccents() {
        XCTAssertEqual(TextTransform.uppercase.apply("élève à l'école", locale: french), "ÉLÈVE À L'ÉCOLE")
    }

    func testLowercase() {
        XCTAssertEqual(TextTransform.lowercase.apply("ÇA VA", locale: french), "ça va")
    }

    func testCapitalized() {
        XCTAssertEqual(TextTransform.capitalized.apply("hello wide world", locale: french), "Hello Wide World")
    }
}
