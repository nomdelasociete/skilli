import XCTest
@testable import SkilliCore

final class QuicklinkTests: XCTestCase {
    func testKeywordAndQuery() throws {
        let match = try XCTUnwrap(Quicklink.match("g skilli launcher", in: Quicklink.defaults))
        XCTAssertEqual(match.link.name, "Google")
        XCTAssertEqual(match.query, "skilli launcher")
        XCTAssertEqual(match.link.address(for: match.query)?.absoluteString, "https://www.google.com/search?q=skilli%20launcher")
        XCTAssertNil(Quicklink.match("google", in: Quicklink.defaults), "no query yet")
        XCTAssertNil(Quicklink.match("safari tabs", in: Quicklink.defaults))
        XCTAssertEqual(Quicklink.match("YT lofi", in: Quicklink.defaults)?.link.name, "YouTube")
    }

    func testEncodingKeepsTheQueryWhole() {
        let google = Quicklink.defaults[0]
        XCTAssertEqual(google.address(for: "a&b=c #d/é")?.absoluteString, "https://www.google.com/search?q=a%26b%3Dc%20%23d%2F%C3%A9")
        XCTAssertEqual(google.address(for: "")?.absoluteString, "https://www.google.com/search?q=")
    }

    func testOnlyWebAddresses() {
        XCTAssertNil(Quicklink(name: "Bad", keyword: "x", url: "file:///etc/{query}").address(for: "passwd"))
        XCTAssertNil(Quicklink(name: "Bad", keyword: "x", url: "javascript:alert({query})").address(for: "1"))
        XCTAssertNotNil(Quicklink(name: "Page", keyword: "", url: "https://example.com").address(for: ""))
    }

    func testTheSelectionAsAQuery() {
        XCTAssertEqual(Quicklink.query(fromSelection: "  Tour\n Eiffel\t "), "Tour Eiffel")
        XCTAssertNil(Quicklink.query(fromSelection: " \n "))
        XCTAssertNil(Quicklink.query(fromSelection: nil))
        XCTAssertEqual(Quicklink.query(fromSelection: String(repeating: "a", count: 3_000))?.count, 1_000)
    }

    /// "Reuse an open tab": a tab on the same site, the same page first,
    /// then the one in front of its window; front windows first.
    func testTheTabToReuse() throws {
        let address = try XCTUnwrap(Quicklink.defaults[0].address(for: "skilli"))
        let tabs = [
            Quicklink.OpenTab(window: 7, index: 1, url: "https://github.com/x", active: true),
            Quicklink.OpenTab(window: 7, index: 2, url: "https://google.com/maps", active: false),
            Quicklink.OpenTab(window: 9, index: 1, url: "https://www.google.com/search?q=old", active: false),
            Quicklink.OpenTab(window: 9, index: 2, url: "https://www.google.com/search?q=older", active: true)
        ]
        XCTAssertEqual(Quicklink.tabToReuse(for: address, among: tabs), tabs[3], "a search there before, the one in front")
        XCTAssertEqual(Quicklink.tabToReuse(for: address, among: Array(tabs.prefix(2))), tabs[1], "else any page of the site (www. aside)")
        XCTAssertNil(Quicklink.tabToReuse(for: address, among: [tabs[0]]))
        XCTAssertNil(Quicklink.tabToReuse(for: address, among: [Quicklink.OpenTab(window: 1, index: 1, url: "file:///google.com/search", active: true)]))
        let maps = try XCTUnwrap(URL(string: "https://maps.apple.com/?q=x"))
        XCTAssertNil(Quicklink.tabToReuse(for: maps, among: tabs), "another host of the same company is another site")
    }
}
