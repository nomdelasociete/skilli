import XCTest
@testable import SkilliCore

final class FileMeaningTests: XCTestCase {
    func testDescriptionAndFolder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 18, minute: 2))!
        XCTAssertEqual(FileMeaning.folder(of: "/Users/me/Documents/Admin/Contrat.pdf", home: "/Users/me"), "Documents/Admin")
        XCTAssertEqual(FileMeaning.folder(of: "/Applications/Notes.app", home: "/Users/me"), "Applications")
        XCTAssertEqual(FileMeaning.describe(name: "Contrat.pdf", kind: "PDF document", folder: "Documents/Admin", modified: yesterday,
                                            now: now, calendar: calendar),
                       "PDF document “Contrat” in Documents/Admin, modified yesterday 18:02")
        XCTAssertEqual(FileMeaning.describe(name: "x", kind: "", folder: "", modified: nil), "File “x”")
    }

    func testReadableNames() {
        XCTAssertEqual(FileMeaning.readable("Contrat-location_appartement-2026-10-01.pdf"), "Contrat location appartement 2026-10-01")
        XCTAssertEqual(FileMeaning.readable("Facture-EDF-octobre-1317.pdf"), "Facture EDF octobre 1317")
        XCTAssertEqual(FileMeaning.readable("Capture d’écran 2026-10-10 à 14.32.11.png"), "Capture d’écran 2026-10-10 à 14.32.11")
        XCTAssertEqual(FileMeaning.readable("README"), "README")
        XCTAssertEqual(FileMeaning.readable("---.txt"), "---.txt")
    }

    func testSignificantWords() {
        XCTAssertEqual(FileMeaning.significantWords("mon contrat de location"), ["contrat", "location"])
        XCTAssertEqual(FileMeaning.significantWords("la facture d'électricité du mois dernier"), ["facture", "électricité"])
        XCTAssertEqual(FileMeaning.significantWords("les photos de vacances en Bretagne"), ["photos", "vacances", "bretagne"])
    }

    func testModeFilter() {
        XCTAssertEqual(FileMeaning.modeFilter("f contrat"), "contrat")
        XCTAssertEqual(FileMeaning.modeFilter("Fichier facture edf"), "facture edf")
        XCTAssertNil(FileMeaning.modeFilter("finder"))
        XCTAssertNil(FileMeaning.modeFilter("figma"))
    }
}
