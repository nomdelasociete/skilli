import CoreGraphics
import SkilliCore
import XCTest

final class CardAnchorTests: XCTestCase {
    func testAFieldIsAPlaceADocumentIsNot() {
        XCTAssertTrue(CardAnchor.isAPlace(field: CGRect(x: 1082, y: -874, width: 435, height: 20)), "a one-line field")
        XCTAssertTrue(CardAnchor.isAPlace(field: CGRect(x: 1082, y: -1034, width: 435, height: 180)), "a compose box")
        XCTAssertFalse(CardAnchor.isAPlace(field: CGRect(x: -68, y: -1550, width: 1285, height: 1034)), "Codex's web area")
        XCTAssertFalse(CardAnchor.isAPlace(field: .zero))
    }
}
