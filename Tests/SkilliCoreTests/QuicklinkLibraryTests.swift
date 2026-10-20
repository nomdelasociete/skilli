@testable import SkilliCore
import XCTest

final class QuicklinkLibraryTests: XCTestCase {
    func testASmallLibraryOfWorkingLinks() {
        let items = QuicklinkLibrary.items
        XCTAssertTrue((15...25).contains(items.count), "\(items.count)")
        XCTAssertEqual(Set(items.map(\.name)).count, items.count, "names are unique")
        XCTAssertEqual(Set(items.map { $0.keyword.lowercased() }).count, items.count, "keywords are unique")
        XCTAssertEqual(Set(items.map(\.url)).count, items.count)
        for item in items {
            let link = Quicklink(name: item.name, keyword: item.keyword, url: item.url)
            XCTAssertTrue(link.takesQuery, item.name)
            XCTAssertNotNil(link.address(for: "tour eiffel & co / é #1"), item.name)
            XCTAssertEqual(link.address(for: "x")?.scheme, "https", item.name)
            XCTAssertFalse(item.keyword.isEmpty || item.keyword.contains(" "), item.name)
            XCTAssertEqual(Quicklink.match("\(item.keyword) tour eiffel", in: [link])?.query, "tour eiffel", item.name)
        }
        XCTAssertEqual(QuicklinkLibrary.groups.map(\.group), QuicklinkLibrary.Group.allCases)
        XCTAssertTrue(QuicklinkLibrary.groups.allSatisfy { !$0.items.isEmpty })
    }

    /// A library keyword typed then a space must never take what the
    /// launcher already reads: a shipped quicklink, a mode's prefix, a
    /// parser's word.
    func testKeywordsClashWithNothing() {
        let shipped = Set(Quicklink.defaults.map { $0.keyword.lowercased() })
        let prefixes = Set(LauncherPrefix.modes.flatMap(\.prefixes).map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let words: Set<String> = [TimerRequest.word, AwakeRequest.word, EventRequest.word, "remind", "minuteur", "chrono", "join", "save", "layout"]
        for item in QuicklinkLibrary.items {
            let keyword = item.keyword.lowercased()
            XCTAssertFalse(shipped.contains(keyword), item.keyword)
            XCTAssertFalse(prefixes.contains(keyword), item.keyword)
            XCTAssertFalse(words.contains(keyword), item.keyword)
            XCTAssertNil(LauncherPrefix.mode(of: "\(keyword) something"), item.keyword)
        }
    }

    func testAddedOnceKeywordKeptWhenFree() throws {
        let french = try XCTUnwrap(QuicklinkLibrary.items.first { $0.name == "Wikipedia (French)" })
        XCTAssertTrue(QuicklinkLibrary.isAdded(french, in: Quicklink.defaults), "the shipped “wiki” is the same address")
        let maps = try XCTUnwrap(QuicklinkLibrary.items.first { $0.keyword == "gm" })
        XCTAssertFalse(QuicklinkLibrary.isAdded(maps, in: Quicklink.defaults))
        XCTAssertEqual(QuicklinkLibrary.quicklink(for: maps, among: Quicklink.defaults).keyword, "gm")
        let mine = Quicklink(name: "Gmail", keyword: "GM", url: "https://mail.google.com/mail/u/0/#search/{query}")
        let added = QuicklinkLibrary.quicklink(for: maps, among: Quicklink.defaults + [mine])
        XCTAssertEqual(added.keyword, "", "its keyword is the user's: found by name")
        XCTAssertEqual(added.name, "Google Maps")
        XCTAssertEqual(added.url, maps.url)
    }
}
