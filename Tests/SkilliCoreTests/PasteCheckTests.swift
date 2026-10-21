import SkilliCore
import XCTest

final class PasteCheckTests: XCTestCase {
    func testTheProbeIsTheFirstWordsShown() {
        XCTAssertEqual(PasteCheck.probe("FR12345678901"), "FR12345678901")
        XCTAssertEqual(PasteCheck.probe("\n  Bien à toi,\nCamille"), "Bien à toi,")
        XCTAssertEqual(PasteCheck.probe("12 rue des Lilas, 75011 Paris, France, Europe"), "12 rue des Lilas, 75011 ")
        XCTAssertEqual(PasteCheck.probe("  \n "), "")
    }

    /// The keyword's deletes land after ⌘V is sent: the field changes, the
    /// paste has not landed; the clipboard must wait.
    func testOnlyThePastedWordsSayItLanded() {
        let probe = PasteCheck.probe("FR12345678901")
        XCTAssertFalse(PasteCheck.landed(before: "TVA: !!ytva", now: "TVA: !!yt", probe: probe), "a delete, not the paste")
        XCTAssertFalse(PasteCheck.landed(before: "TVA: !!ytva", now: "TVA: !!ytva", probe: probe))
        XCTAssertTrue(PasteCheck.landed(before: "TVA: !!ytva", now: "TVA: FR12345678901", probe: probe))
        // The same snippet already in the field: one more of it.
        XCTAssertFalse(PasteCheck.landed(before: "FR12345678901 et !!ytva", now: "FR12345678901 et ", probe: probe))
        XCTAssertTrue(PasteCheck.landed(before: "FR12345678901 et ", now: "FR12345678901 et FR12345678901", probe: probe))
        // Nothing to look for: any change.
        XCTAssertTrue(PasteCheck.landed(before: "a", now: "a ", probe: ""))
    }
}
