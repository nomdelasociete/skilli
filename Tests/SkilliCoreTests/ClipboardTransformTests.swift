@testable import SkilliCore
import XCTest

final class ClipboardTransformTests: XCTestCase {
    private func titles(_ text: String) -> [String] { ClipboardTransform.all(for: text).map(\.title) }
    private func result(_ title: String, _ text: String) -> String? { ClipboardTransform.all(for: text).first { $0.title == title }?.text }

    func testAColorPastesInItsOtherForms() {
        XCTAssertEqual(titles("#3E8E7E"), ["Paste as RGB", "Paste as HSL"])
        XCTAssertEqual(result("Paste as RGB", "#3e8e7e"), "rgb(62, 142, 126)")
        XCTAssertEqual(result("Paste as Hex", "rgb(62, 142, 126)"), "#3E8E7E")
        XCTAssertEqual(titles("rgb(62, 142, 126)"), ["Paste as Hex", "Paste as HSL"])
    }

    func testALinkPastesWithoutItsTracking() {
        XCTAssertEqual(result("Paste Without Tracking", "https://example.com/a?id=7&utm_source=mail&utm_medium=x&fbclid=abc#top"),
                       "https://example.com/a?id=7#top")
        XCTAssertEqual(result("Paste Without Tracking", "https://example.com/a?utm_campaign=x"), "https://example.com/a")
        // Nothing to remove: not offered.
        XCTAssertEqual(titles("https://example.com/a?id=7"), [])
    }

    func testJSONIsLaidOutOrPackedKeysInTheirOrder() {
        let packed = #"{"b":1,"a":[1,2,{"c":"x, y: {z}"}],"e":{},"n":1.50}"#
        let pretty = """
        {
          "b": 1,
          "a": [
            1,
            2,
            {
              "c": "x, y: {z}"
            }
          ],
          "e": {},
          "n": 1.50
        }
        """
        XCTAssertEqual(result("Paste as Pretty JSON", packed), pretty)
        XCTAssertEqual(result("Paste as Minified JSON", pretty), packed)
        // Already so: not offered again.
        XCTAssertFalse(titles(packed).contains("Paste as Minified JSON"))
        XCTAssertFalse(titles(pretty).contains("Paste as Pretty JSON"))
        // Not JSON: neither.
        XCTAssertFalse(titles("{not json}").contains("Paste as Pretty JSON"))
        XCTAssertEqual(result("Paste as Minified JSON", #"[ "a \" b" , 2 ]"#), #"["a \" b",2]"#)
    }

    func testLinesSpacesAndCase() {
        XCTAssertEqual(result("Paste as One Line", "  first line \n\n second\tline\n"), "first line second\tline")
        XCTAssertEqual(result("Paste Trimmed", "  hello you \n"), "hello you")
        XCTAssertEqual(result("Paste UPPERCASE", "hello you"), "HELLO YOU")
        XCTAssertEqual(result("Paste lowercase", "Hello YOU"), "hello you")
        XCTAssertEqual(result("Paste Title Case", "hello you"), "Hello You")
        XCTAssertEqual(titles("hello you"), ["Paste UPPERCASE", "Paste Title Case"])
        XCTAssertEqual(result("Paste URL-Decoded", "caf%C3%A9%20au%20lait"), "café au lait")
    }

    func testNothingWhereNothingChangesOrTheCopyIsLong() {
        XCTAssertEqual(titles(""), [])
        XCTAssertEqual(titles("   "), [])
        XCTAssertEqual(titles("12345"), [])
        XCTAssertEqual(titles(String(repeating: "a long copy ", count: 10_000)), [])
        // An address or a mail is not shouted.
        XCTAssertFalse(titles("camille@example.com").contains("Paste UPPERCASE"))
    }
}
