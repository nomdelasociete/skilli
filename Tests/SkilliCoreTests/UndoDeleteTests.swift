@testable import SkilliCore
import XCTest

final class UndoDeleteTests: XCTestCase {
    func testTheCardNamesWhatWentInBold() {
        XCTAssertEqual(UndoDelete.details("Home address", " (;addr)"), "**Home address** (;addr)")
        XCTAssertEqual(UndoDelete.details("Work", ": its windows stay where they are."), "**Work**: its windows stay where they are.")
        XCTAssertEqual(UndoDelete.details("Claude API key"), "**Claude API key**")
    }

    func testANameNeverStylesTheCard() {
        XCTAssertEqual(UndoDelete.details("my_server"), #"**my\_server**"#)
        XCTAssertEqual(UndoDelete.details("**bold** `code` [link](x)"), #"**\*\*bold\*\* \`code\` \[link\](x)**"#)
        XCTAssertEqual(UndoDelete.escaped("C# <tag> ~x~ a\\b"), ##"C\# \<tag\> \~x\~ a\\b"##)
    }

    func testANameIsOneShortLine() {
        XCTAssertEqual(UndoDelete.shortened("Réunion budget\nsecond line"), "Réunion budget")
        XCTAssertEqual(UndoDelete.shortened("  spaced   out  "), "spaced out")
        let long = String(repeating: "word ", count: 30)
        let cut = UndoDelete.shortened(long)
        XCTAssertLessThanOrEqual(cut.count, 60)
        XCTAssertTrue(cut.hasSuffix("word…"), cut)
        let unbroken = String(repeating: "x", count: 100)
        XCTAssertEqual(UndoDelete.shortened(unbroken).count, 60)
        XCTAssertEqual(UndoDelete.shortened(""), "")
    }

    func testAFilePutBackNeverTakesAnotherOnesName() {
        var taken: Set<String> = []
        XCTAssertEqual(UndoDelete.freeName(for: "report.pdf") { taken.contains($0) }, "report.pdf")
        taken = ["report.pdf", "report 2.pdf"]
        XCTAssertEqual(UndoDelete.freeName(for: "report.pdf") { taken.contains($0) }, "report 3.pdf")
        taken = ["Notes"]
        XCTAssertEqual(UndoDelete.freeName(for: "Notes") { taken.contains($0) }, "Notes 2")
        taken = [".zshrc"]
        XCTAssertEqual(UndoDelete.freeName(for: ".zshrc") { taken.contains($0) }, ".zshrc 2")
        taken = ["archive.tar.gz"]
        XCTAssertEqual(UndoDelete.freeName(for: "archive.tar.gz") { taken.contains($0) }, "archive.tar 2.gz")
        taken = ["Version 1.0 final"]
        XCTAssertEqual(UndoDelete.freeName(for: "Version 1.0 final") { taken.contains($0) }, "Version 1.0 final 2")
    }

    func testTheCardGoesUnderTheOpenLauncher() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let glass = CGRect(x: 610, y: 300, width: 700, height: 480)
        let spot = UndoDelete.spot(under: glass, in: visible)
        XCTAssertEqual(spot.minX, glass.minX)
        XCTAssertEqual(spot.width, glass.width)
        XCTAssertEqual(spot.maxY, 290, "its top just under the glass: it grows down from there")
        XCTAssertLessThan(spot.maxY, glass.minY)
    }

    func testDraggedLowTheCardGoesAbove() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let glass = CGRect(x: 610, y: 60, width: 700, height: 480)
        let spot = UndoDelete.spot(under: glass, in: visible)
        XCTAssertEqual(spot.maxY, glass.maxY + 10 + UndoDelete.cardRoom)
        XCTAssertGreaterThan(spot.maxY - UndoDelete.cardRoom, glass.maxY, "a card of its room stays clear of the glass")
        // No room above either: kept on the screen.
        let tall = CGRect(x: 610, y: 60, width: 700, height: 960)
        XCTAssertEqual(UndoDelete.spot(under: tall, in: visible).maxY, visible.maxY)
    }

    private struct Item: Identifiable, Equatable {
        let id: Int
        let name: String
    }

    func testAnElementGoesBackWhereItWas() {
        var list = [Item(id: 1, name: "a"), Item(id: 2, name: "b"), Item(id: 3, name: "c")]
        let removed = RemovedElement.take(2, from: &list)
        XCTAssertEqual(removed?.index, 1)
        XCTAssertEqual(list.map(\.id), [1, 3])
        XCTAssertTrue(removed?.putBack(into: &list) == true)
        XCTAssertEqual(list.map(\.id), [1, 2, 3])
        // Once: there already, it does not come twice.
        XCTAssertFalse(removed?.putBack(into: &list) == true)
        XCTAssertEqual(list.map(\.id), [1, 2, 3])
        XCTAssertNil(RemovedElement.take(9, from: &list))
    }

    func testAShorterListTakesItAtTheEnd() {
        var list = [Item(id: 1, name: "a"), Item(id: 2, name: "b"), Item(id: 3, name: "c")]
        guard let removed = RemovedElement.take(3, from: &list) else { return XCTFail("not taken") }
        list.removeAll { $0.id == 1 }
        removed.putBack(into: &list)
        XCTAssertEqual(list.map(\.id), [2, 3])
    }

    func testAnythingMatchedCanBeTaken() {
        var aliases = ["e", "cl", "k"]
        let removed = RemovedElement.take(from: &aliases) { $0 == "cl" }
        XCTAssertEqual(aliases, ["e", "k"])
        removed?.putBack(into: &aliases) { $0 == "cl" }
        XCTAssertEqual(aliases, ["e", "cl", "k"])
    }
}
