import XCTest
@testable import SkilliCore

final class InputScopeTests: XCTestCase {
    func testShortFieldIsTakenWholeWithoutOuterBlanks() {
        let text = "  les enfant on manger\ndes pome \n"
        let range = InputScope.range(in: text, cursor: 3)
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "les enfant on manger\ndes pome")
    }

    func testLongDocumentTakesTheParagraphAtTheCursor() {
        let first = String(repeating: "Intro sentence. ", count: 20)
        let text = first + "\nSecond paragraph here.\n" + "Third one."
        let cursor = (first as NSString).length + 5
        let range = InputScope.range(in: text, cursor: cursor, wholeFieldLimit: 100)
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "Second paragraph here.")
    }

    func testBlankFieldOrBlankLineGivesNothing() {
        XCTAssertNil(InputScope.range(in: "   \n ", cursor: 0))
        let text = String(repeating: "x", count: 50) + "\n\n" + String(repeating: "y", count: 50)
        XCTAssertNil(InputScope.range(in: text, cursor: 51, wholeFieldLimit: 10))
    }

    /// Arc gave a lone no-break space as the selection through
    /// Accessibility: it is no text to fix.
    func testBlanksAloneAreNoText() {
        XCTAssertTrue(InputScope.isBlank(""))
        XCTAssertTrue(InputScope.isBlank("\u{00A0}"))
        XCTAssertTrue(InputScope.isBlank(" \u{202F}\n\t\r\n"))
        XCTAssertFalse(InputScope.isBlank("\u{00A0}a"))
        XCTAssertFalse(InputScope.isBlank("les enfant on manger des pome"))
    }

    func testCountsInUTF16LikeAccessibility() {
        let text = "👋 salut"
        XCTAssertEqual(InputScope.range(in: text, cursor: 0), NSRange(location: 0, length: 8))
    }
}
