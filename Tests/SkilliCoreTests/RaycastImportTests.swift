import XCTest
@testable import SkilliCore

final class RaycastImportTests: XCTestCase {
    func testSnippets() throws {
        let json = """
        [{"name": "Signature", "text": "Best,\\n{clipboard}{cursor}", "keyword": ";sig"},
         {"name": "", "text": "Order {uuid} on {date format=\\"yyyy-MM-dd\\"}", "keyword": ""},
         {"name": "Empty", "text": ""}]
        """
        let snippets = try XCTUnwrap(RaycastImport.snippets(Data(json.utf8)))
        XCTAssertEqual(snippets.map(\.name), ["Signature", "Order {uuid} on {date format=\"yyyy-MM-dd"], "no name: its first 40 characters")
        XCTAssertEqual(snippets[0].keyword, ";sig")
        XCTAssertTrue(snippets[0].unknown.isEmpty)
        XCTAssertEqual(snippets[1].unknown, ["{uuid}", "{date format=\"yyyy-MM-dd\"}"])
        XCTAssertNotNil(RaycastImport.snippets(Data(#"{"snippets": [{"name": "A", "text": "a"}]}"#.utf8)))
        let sneaky = try XCTUnwrap(RaycastImport.snippets(Data(#"[{"name": "A\nkeyword: ;x", "text": "t", "keyword": ";k k\n"}]"#.utf8)))
        XCTAssertEqual(sneaky[0].name, "A keyword: ;x", "one line: nothing reaches the front matter")
        XCTAssertEqual(sneaky[0].keyword, ";kk")
        XCTAssertNil(RaycastImport.snippets(Data(#"[{"name": "x", "link": "https://x.com"}]"#.utf8)), "a quicklinks file")
        XCTAssertNil(RaycastImport.snippets(Data("not json".utf8)))
    }

    func testQuicklinks() throws {
        let json = """
        [{"name": "GitHub Search", "link": "https://github.com/search?q={Query}"},
         {"name": "Docs", "link": "https://developer.apple.com/search/?q={argument name=\\"Term\\"}"},
         {"name": "Home", "link": "https://skil.li"},
         {"name": "Two", "link": "https://x.com/{argument name=\\"a\\"}/{argument name=\\"b\\"}"},
         {"name": "Clip", "link": "https://translate.google.com/?text={clipboard}"},
         {"name": "Local", "link": "file:///Users/me/notes"}]
        """
        let (links, skipped) = try XCTUnwrap(RaycastImport.quicklinks(Data(json.utf8)))
        XCTAssertEqual(links.map(\.url), ["https://github.com/search?q={query}", "https://developer.apple.com/search/?q={query}", "https://skil.li"])
        XCTAssertEqual(skipped, ["Two", "Clip", "Local"])
        XCTAssertNil(RaycastImport.quicklinks(Data(#"[{"name": "S", "text": "t"}]"#.utf8)), "a snippets file")
    }
}
