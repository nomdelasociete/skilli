@testable import SkilliCore
import XCTest

final class EnglishInputTests: XCTestCase {
    private let french = EnglishInput.Source(id: "com.apple.keylayout.French", name: "French", languages: ["fr"], asciiCapable: true,
                                             isKeyboardLayout: true)
    private let abc = EnglishInput.Source(id: "com.apple.keylayout.ABC", name: "ABC", languages: ["en"], asciiCapable: true, isKeyboardLayout: true)
    private let us = EnglishInput.Source(id: "com.apple.keylayout.US", name: "U.S.", languages: ["en"], asciiCapable: true, isKeyboardLayout: true)
    private let british = EnglishInput.Source(id: "com.apple.keylayout.British", name: "British", languages: ["en"], asciiCapable: true,
                                              isKeyboardLayout: true)
    private let russian = EnglishInput.Source(id: "com.apple.keylayout.Russian", name: "Russian", languages: ["ru"], asciiCapable: false,
                                              isKeyboardLayout: true)
    private let kana = EnglishInput.Source(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", name: "Hiragana", languages: ["ja"],
                                           asciiCapable: false, isKeyboardLayout: false)
    private let romaji = EnglishInput.Source(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", name: "Romaji", languages: ["en"],
                                             asciiCapable: true, isKeyboardLayout: false)

    func testTheUsersOwnEnglishLayout() {
        XCTAssertEqual(EnglishInput.pick([french, us, abc])?.id, abc.id, "ABC first")
        XCTAssertEqual(EnglishInput.pick([french, us])?.id, us.id, "then U.S.")
        XCTAssertEqual(EnglishInput.pick([russian, british])?.id, british.id, "then any English layout of plain letters")
        XCTAssertNil(EnglishInput.pick([french]), "none turned on: nothing")
        XCTAssertNil(EnglishInput.pick([russian, kana, romaji]), "an input method's Latin mode is not a layout")
    }

    func testSwitchesOnlyFromAnotherLanguage() {
        XCTAssertTrue(EnglishInput.switches(from: french, to: abc))
        XCTAssertTrue(EnglishInput.switches(from: russian, to: abc))
        XCTAssertTrue(EnglishInput.switches(from: kana, to: us))
        XCTAssertFalse(EnglishInput.switches(from: abc, to: abc))
        XCTAssertFalse(EnglishInput.switches(from: british, to: abc), "English already")
        XCTAssertFalse(EnglishInput.switches(from: french, to: nil), "no English layout turned on: nothing")
    }
}
