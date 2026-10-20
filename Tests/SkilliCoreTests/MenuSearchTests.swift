@testable import SkilliCore
import XCTest

final class MenuSearchTests: XCTestCase {
    private let candidates = [
        (["File"], "New Document", "⌘N"),
        (["File"], "Export as PDF…", nil),
        (["File", "Share"], "Mail", nil),
        (["Edit"], "Select All", "⌘A"),
        (["Edit", "Transformations"], "Make Upper Case", nil),
        (["Edit", "Transformations"], "Make Lower Case", nil),
        (["Format", "Font"], "Show Fonts", "⌘T"),
        (["Format", "Text"], "Align Left", "⌘{")
    ].enumerated().map { index, item in
        MenuSearch.Candidate(.init(index: index, title: item.1, parents: item.0, shortcut: item.2))
    }

    private func titles(_ text: String) -> [String] {
        MenuSearch.search(text, in: candidates).map(\.title)
    }

    /// An item named so first; its menus' names find it too, after.
    func testByItsNameThenItsMenus() {
        XCTAssertEqual(titles("upper").first, "Make Upper Case")
        XCTAssertEqual(titles("export pdf").first, "Export as PDF…")
        XCTAssertEqual(titles("select all"), ["Select All"])
        XCTAssertEqual(Set(titles("transformations")), ["Make Upper Case", "Make Lower Case"], "by the menu it is in")
        XCTAssertEqual(titles("font").first, "Show Fonts", "its own name before Format › Font's other items")
        XCTAssertTrue(titles("zzzz").isEmpty)
    }

    func testNothingTypedListsTheMenusInOrder() {
        XCTAssertEqual(titles(""), candidates.map(\.entry.title))
    }

    func testCaseAndAccentsIgnored() {
        let french = [MenuSearch.Candidate(.init(index: 0, title: "Mettre en majuscules", parents: ["Édition", "Transformations"], shortcut: nil))]
        XCTAssertEqual(MenuSearch.search("MAJUSCULES", in: french).count, 1)
        XCTAssertEqual(MenuSearch.search("edition", in: french).count, 1)
    }

    func testPlaceAndPrefix() {
        XCTAssertEqual(candidates[4].entry.place, "Edit › Transformations")
        XCTAssertEqual(LauncherPrefix.mode(of: "m upper")?.0, .searchMenus)
        XCTAssertEqual(LauncherPrefix.mode(of: "m upper")?.1, "upper")
        XCTAssertNil(LauncherPrefix.mode(of: "menu bar"), "“menu bar” still finds apps")
    }
}
