import XCTest
@testable import SkilliCore

final class SymbolicHotKeyTests: XCTestCase {
    private func entry(enabled: Int, _ parameters: [Int]) -> [String: Any] {
        ["enabled": NSNumber(value: enabled), "value": ["parameters": parameters.map { NSNumber(value: $0) }, "type": "standard"]]
    }

    func testShowDesktopAsTheUserSetIt() {
        let standard = SymbolicHotKey.showDesktopDefault
        XCTAssertEqual(SymbolicHotKey.read("36", in: ["36": entry(enabled: 1, [65535, 103, 0])], standard: standard),
                       SymbolicHotKey(keyCode: 103, modifiers: 0), "F11, as on the Mac mini")
        XCTAssertEqual(SymbolicHotKey.read("36", in: ["36": entry(enabled: 1, [65535, 103, 8_388_608])], standard: standard)?.modifiers, 8_388_608)
        XCTAssertEqual(SymbolicHotKey.read("36", in: ["36": entry(enabled: 1, [100, 2, 1_048_576])], standard: standard),
                       SymbolicHotKey(keyCode: 2, modifiers: 1_048_576), "changed to ⌘D")
        XCTAssertEqual(SymbolicHotKey.read("36", in: [:], standard: standard), standard, "never changed: no entry")
        XCTAssertEqual(SymbolicHotKey.read("36", in: nil, standard: standard), standard)
        XCTAssertNil(SymbolicHotKey.read("36", in: ["36": entry(enabled: 0, [65535, 103, 0])], standard: standard), "turned off")
        XCTAssertNil(SymbolicHotKey.read("36", in: ["36": entry(enabled: 1, [65535, 65535, 0])], standard: standard), "no key")
        XCTAssertTrue(standard.isFunctionKey)
        XCTAssertFalse(SymbolicHotKey(keyCode: 2, modifiers: 0).isFunctionKey)
    }
}
