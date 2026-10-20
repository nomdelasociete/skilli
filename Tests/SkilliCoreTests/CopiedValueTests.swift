@testable import SkilliCore
import XCTest

final class CopiedColorTests: XCTestCase {
    private func hex(_ text: String) -> String? {
        CopiedColor.parse(text)?.hex
    }

    func testHexInEveryLength() {
        XCTAssertEqual(hex("#3E8E7E"), "#3E8E7E")
        XCTAssertEqual(hex("#3e8e7e"), "#3E8E7E")
        XCTAssertEqual(hex("  #3E8E7E\n"), "#3E8E7E", "spaces around")
        XCTAssertEqual(hex("#3E8E7E;"), "#3E8E7E", "as CSS ends it")
        XCTAssertEqual(hex("#fff"), "#FFFFFF")
        XCTAssertEqual(hex("#0f08"), "#00FF0088")
        XCTAssertEqual(hex("#3E8E7E80"), "#3E8E7E80")
        XCTAssertEqual(hex("0x3E8E7E"), "#3E8E7E")
        // As design tools copy it: six digits, figures and letters.
        XCTAssertEqual(hex("3E8E7E"), "#3E8E7E")
    }

    func testWhatIsNotAColor() {
        for text in ["123456", "decade", "facade", "#12345", "#ggg", "#", "a4af3f8e", "fff", "1e5", "#hashtag",
                     "The color is #3E8E7E", "#3E8E7E and #FFFFFF", "rgb(300, 0, 0)", "rgb(1, 2)", "hsl(10, 200%, 50%)",
                     "Color(red: 62, green: 142, blue: 126)", "Color(.displayP3, red: 0.2, green: 0.5, blue: 0.4)",
                     "Color.red", "red", "NSColor(named: \"Accent\")", ""] {
            XCTAssertNil(CopiedColor.parse(text), text)
        }
    }

    func testCSSFunctions() {
        XCTAssertEqual(hex("rgb(62, 142, 126)"), "#3E8E7E")
        XCTAssertEqual(hex("rgb(62 142 126)"), "#3E8E7E")
        XCTAssertEqual(hex("RGB(62,142,126)"), "#3E8E7E")
        XCTAssertEqual(hex("rgba(62, 142, 126, 0.5)"), "#3E8E7E80")
        XCTAssertEqual(hex("rgb(62 142 126 / 50%)"), "#3E8E7E80")
        XCTAssertEqual(hex("rgb(100%, 0%, 0%)"), "#FF0000")
        XCTAssertEqual(hex("hsl(0, 100%, 50%)"), "#FF0000")
        XCTAssertEqual(hex("hsl(120deg 100% 25%)"), "#008000")
        XCTAssertEqual(hex("hsla(240, 100%, 50%, 0.25)"), "#0000FF40")
        XCTAssertEqual(hex("hsl(168, 39%, 40%)"), "#3E8E7E")
    }

    func testCodeLiterals() {
        XCTAssertEqual(hex("Color(red: 1, green: 0.5, blue: 0)"), "#FF8000")
        XCTAssertEqual(hex("Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.5)"), "#FF800080")
        XCTAssertEqual(hex("NSColor(srgbRed: 62 / 255, green: 142 / 255, blue: 126 / 255, alpha: 1)"), "#3E8E7E")
        XCTAssertEqual(hex("UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)"), "#0000FF")
        XCTAssertEqual(hex("NSColor(calibratedWhite: 0.5, alpha: 1)"), "#808080")
        XCTAssertEqual(hex("Color(white: 1)"), "#FFFFFF")
        XCTAssertEqual(hex("Color(hue: 0, saturation: 1, brightness: 1)"), "#FF0000")
    }

    func testItsValuesInEveryFormat() throws {
        let mint = try XCTUnwrap(CopiedColor.parse("#3E8E7E"))
        XCTAssertEqual(mint.rgb, "rgb(62, 142, 126)")
        XCTAssertEqual(mint.hsl, "hsl(168, 39%, 40%)")
        XCTAssertEqual(mint.opacity, "100%")
        let glass = try XCTUnwrap(CopiedColor.parse("rgba(255, 255, 255, 0.25)"))
        XCTAssertEqual(glass.rgb, "rgba(255, 255, 255, 0.25)")
        XCTAssertEqual(glass.hsl, "hsla(0, 0%, 100%, 0.25)")
        XCTAssertEqual(glass.opacity, "25%")
        // Round trips through each format.
        for text in [mint.hex, mint.rgb, mint.hsl] {
            XCTAssertEqual(CopiedColor.parse(text)?.hex, "#3E8E7E", text)
        }
    }

    func testTextOnItReadsBetterDarkOrWhite() throws {
        XCTAssertTrue(try XCTUnwrap(CopiedColor.parse("#FFFFFF")).prefersDarkText)
        XCTAssertTrue(try XCTUnwrap(CopiedColor.parse("#F5D90A")).prefersDarkText, "yellow")
        XCTAssertFalse(try XCTUnwrap(CopiedColor.parse("#000000")).prefersDarkText)
        XCTAssertFalse(try XCTUnwrap(CopiedColor.parse("#1D4ED8")).prefersDarkText, "blue")
    }
}

final class CopiedValueTests: XCTestCase {
    func testALinkIsTheWholeCopy() {
        XCTAssertEqual(CopiedValue.read("https://skil.li/docs?a=1#top"), .link(URL(string: "https://skil.li/docs?a=1#top")!))
        XCTAssertEqual(CopiedValue.read("  http://example.com\n"), .link(URL(string: "http://example.com")!))
        XCTAssertEqual(CopiedValue.read("www.apple.com/fr/"), .link(URL(string: "https://www.apple.com/fr/")!))
        for text in ["skil.li", "Look at https://skil.li", "https://skil.li and https://apple.com", "mailto:jb@example.com",
                     "file:///Users/me/notes.txt", "ftp://example.com/file", "https://", "https://jb:secret@example.com/"] {
            if case .link = CopiedValue.read(text) { XCTFail("not a link: \(text)") }
        }
    }

    func testAColorIsTheWholeCopy() {
        XCTAssertEqual(CopiedValue.read("#3E8E7E"), .color(CopiedColor(red: 62 / 255, green: 142 / 255, blue: 126 / 255)))
        if case .color = CopiedValue.read("My favourite is #3E8E7E") { XCTFail("a color inside a sentence") }
    }

    func testEmailPhoneAndAddress() {
        XCTAssertEqual(CopiedValue.read("jb@example.com"), .email("jb@example.com"))
        XCTAssertEqual(CopiedValue.read("mailto:jb@example.com"), .email("jb@example.com"))
        XCTAssertEqual(CopiedValue.read("+33 6 12 34 56 78"), .phone("+33 6 12 34 56 78"))
        XCTAssertEqual(CopiedValue.read("(415) 555-0132"), .phone("(415) 555-0132"))
        guard case .address(let address) = CopiedValue.read("1 Infinite Loop, Cupertino, CA 95014") else {
            return XCTFail("an address")
        }
        XCTAssertEqual(address.lines, ["1 Infinite Loop", "Cupertino", "CA 95014"])
        XCTAssertEqual(address.city, "Cupertino")
        // Inside a sentence, none of them.
        for text in ["Write to jb@example.com tomorrow", "Call me at +33 6 12 34 56 78 tonight", "2026", "12345",
                     "We met at 1 Infinite Loop, Cupertino, CA 95014 and talked for hours about everything"] {
            switch CopiedValue.read(text) {
            case .email, .phone, .address: XCTFail("not a value: \(text)")
            default: break
            }
        }
    }

    func testCodeAndItsLanguage() {
        let swift = """
        import SwiftUI

        struct ContentView: View {
            let name = "skil.li"
            var body: some View {
                Text(name)
            }
        }
        """
        XCTAssertEqual(CopiedValue.read(swift), .code("Swift"))
        let python = """
        def greet(name):
            if not name:
                return None
            print(f"Hello {name}")
        """
        XCTAssertEqual(CopiedValue.read(python), .code("Python"))
        XCTAssertEqual(CopiedValue.read(#"{"name": "skil.li", "fast": true}"#), .code("JSON"))
        XCTAssertEqual(CopiedValue.read("#!/bin/zsh\nset -e\nbrew install xcodegen"), .code("Shell"))
        XCTAssertEqual(CopiedValue.read("SELECT id, title FROM items WHERE copied > 0 ORDER BY copied DESC"), .code("SQL"))
        XCTAssertEqual(CopiedValue.read("const add = (a, b) => {\n  return a + b;\n};\nconsole.log(add(1, 2));"), .code("JavaScript"))
        XCTAssertEqual(CopiedValue.read("<div class=\"card\">\n  <p>Hello</p>\n</div>"), .code("HTML"))
        XCTAssertEqual(CopiedValue.read("#include <stdio.h>\nint main(void) {\n  return 0;\n}"), .code("C"))
    }

    func testProseIsText() {
        for text in ["Hello Paul, the meeting is at 10:00; see you then.",
                     "Note: let me know if you can come.",
                     "Select one from the list, then press Return.",
                     "Réunion demain à 9h avec l'équipe produit",
                     "def", "{}", "Billet SNCF Paris Gare de Lyon → Lyon Part-Dieu, départ 14:05"] {
            XCTAssertEqual(CopiedValue.read(text), .text, text)
        }
    }
}

final class CopiedValueSpeedTests: XCTestCase {
    /// The preview reads what a copy is on the main thread as a row is
    /// selected: well under a millisecond, prose and long code included.
    func testReadingACopyIsFast() {
        let prose = String(repeating: "Réunion demain à 9h avec l'équipe produit (salle 3), puis déjeuner. ", count: 60)
        let code = (0..<120).map { "    let value\($0) = compute(\($0)) { $0 * 2 };" }.joined(separator: "\n")
        let texts = ["#3E8E7E", "https://skil.li/docs", "jb@example.com", "+33 6 12 34 56 78", "1 Infinite Loop, Cupertino, CA 95014",
                     prose, code, "Billet SNCF Paris Gare de Lyon → Lyon Part-Dieu, départ 14:05, voiture 12 place 47", "ok"]
        _ = texts.map(CopiedValue.read)
        let start = ContinuousClock.now
        let rounds = 20
        for _ in 0..<rounds {
            for text in texts { _ = CopiedValue.read(text) }
        }
        let each = (ContinuousClock.now - start) / (rounds * texts.count)
        XCTAssertLessThan(each, .microseconds(700), "\(each) a copy")
    }
}
