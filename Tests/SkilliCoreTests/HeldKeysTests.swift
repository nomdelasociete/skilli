@testable import SkilliCore
import XCTest

final class HeldKeysTests: XCTestCase {
    private let commandK: UInt16 = 40, returnKey: UInt16 = 36, down: UInt16 = 125, space: UInt16 = 49

    func testHeldCommandKOpensTheListOnce() {
        var keys = HeldKeys()
        XCTAssertEqual(keys.press(commandK, isRepeat: false, listShown: false, repeatsInList: false), .new)
        keys.took(commandK)
        for _ in 0..<3 {
            XCTAssertEqual(keys.press(commandK, isRepeat: true, listShown: true, repeatsInList: false), .swallowed, "never closes it again")
        }
        keys.released(commandK)
        XCTAssertEqual(keys.press(commandK, isRepeat: false, listShown: true, repeatsInList: false), .new, "pressed again: closes it")
    }

    func testHeldReturnRunsOneActionNotTheWindowsReturn() {
        var keys = HeldKeys()
        XCTAssertEqual(keys.press(returnKey, isRepeat: false, listShown: true, repeatsInList: false), .new)
        keys.took(returnKey)
        XCTAssertEqual(keys.press(returnKey, isRepeat: true, listShown: false, repeatsInList: false), .swallowed, "no line edited after it")
    }

    func testArrowsRepeatInTheListAndTheWindowsKeysAsBefore() {
        var keys = HeldKeys()
        keys.took(down)
        XCTAssertEqual(keys.press(down, isRepeat: true, listShown: true, repeatsInList: true), .toList)
        XCTAssertEqual(keys.press(down, isRepeat: true, listShown: false, repeatsInList: true), .swallowed, "the list closed under it")
        XCTAssertEqual(keys.press(space, isRepeat: true, listShown: false, repeatsInList: true), .new, "a key the list never took")
    }

    func testAFreshPressForgetsAReleaseThatNeverCame() {
        var keys = HeldKeys()
        keys.took(returnKey)
        XCTAssertEqual(keys.press(returnKey, isRepeat: false, listShown: false, repeatsInList: false), .new)
        XCTAssertEqual(keys.press(returnKey, isRepeat: true, listShown: false, repeatsInList: false), .new)
    }
}
