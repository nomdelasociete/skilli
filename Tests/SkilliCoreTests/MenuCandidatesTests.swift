import XCTest
@testable import SkilliCore

final class MenuCandidatesTests: XCTestCase {
    func testPrivateMenusStayOnTheMac() {
        XCTAssertTrue(MenuCandidates.isShareable(["File", "Export as PDF…"]))
        XCTAssertFalse(MenuCandidates.isShareable(["Window", "contract-acme.pdf"]))
        XCTAssertFalse(MenuCandidates.isShareable(["Historique", "Ma banque"]))
        XCTAssertFalse(MenuCandidates.isShareable(["File", "Open Recent", "budget.xlsx"]))
        XCTAssertFalse(MenuCandidates.isShareable(["Fichier", "Ouvrir l'élément récent", "budget.xlsx"]))
        XCTAssertFalse(MenuCandidates.isShareable(["Finder", "Services", "New Terminal at Folder"]))
        XCTAssertTrue(MenuCandidates.isShareable(["View", "Recently Closed Tab Groups"]), "only submenus are checked, not the item")
    }

    func testChunks() {
        XCTAssertEqual(MenuCandidates.chunks(Array(0..<600)).map(\.count), [254, 254, 92])
        XCTAssertEqual(MenuCandidates.chunks([Int]()).count, 0)
    }

    func testDisplay() {
        XCTAssertEqual(MenuCandidates.display(["File", "Export", "PDF…"]), "File › Export › PDF…")
    }
}
