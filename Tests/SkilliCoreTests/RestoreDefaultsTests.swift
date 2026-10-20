import SkilliCore
import XCTest

final class RestoreDefaultsTests: XCTestCase {
    func testSaysWhatGoes() {
        XCTAssertEqual(RestoreDefaults.message(custom: 3, changed: 2), "Your 3 custom shortcuts and 2 changed keys are removed.")
        XCTAssertEqual(RestoreDefaults.message(custom: 1, changed: 1), "Your 1 custom shortcut and 1 changed key are removed.")
        XCTAssertEqual(RestoreDefaults.message(custom: 4, changed: 0), "Your 4 custom shortcuts are removed.")
        XCTAssertEqual(RestoreDefaults.message(custom: 1, changed: 0), "Your 1 custom shortcut is removed.")
        XCTAssertEqual(RestoreDefaults.message(custom: 0, changed: 2), "Your 2 changed keys are removed.")
        XCTAssertEqual(RestoreDefaults.message(custom: 0, changed: 1), "Your 1 changed key is removed.")
    }

    func testNothingToRestore() {
        XCTAssertNil(RestoreDefaults.message(custom: 0, changed: 0))
    }
}
