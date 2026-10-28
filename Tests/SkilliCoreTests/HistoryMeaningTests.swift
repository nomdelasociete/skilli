import XCTest
@testable import SkilliCore

final class HistoryMeaningTests: XCTestCase {
    func testDatesAndLines() {
        // 2026-10-11 16:02:00 UTC in Chrome's, Safari's and Firefox's clocks.
        let unix = 1_791_734_520.0
        XCTAssertEqual(HistoryMeaning.chromeDate(Int64((unix + 11_644_473_600) * 1_000_000))?.timeIntervalSince1970, unix)
        XCTAssertEqual(HistoryMeaning.safariDate(unix - 978_307_200)?.timeIntervalSince1970, unix)
        XCTAssertEqual(HistoryMeaning.firefoxDate(Int64(unix * 1_000_000))?.timeIntervalSince1970, unix)
        XCTAssertNil(HistoryMeaning.chromeDate(0))
        XCTAssertNil(HistoryMeaning.safariDate(0))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!
        let visit = HistoryVisit(url: "https://www.impots.gouv.fr/declarer", title: "Impôts 2026 : déclaration", browser: "Chrome",
                                 bundleID: "com.google.Chrome", visited: Date(timeIntervalSince1970: unix), visits: 3)
        XCTAssertEqual(visit.domain, "impots.gouv.fr")
        XCTAssertEqual(HistoryMeaning.describe(visit, now: now, calendar: calendar), "“Impôts 2026 : déclaration” on impots.gouv.fr, yesterday 18:02")
        let rib = HistoryVisit(url: "https://banque.example.com/rib", title: "Votre RIB : 12345 67890 12345678901 04 – Banque", browser: "Safari",
                               bundleID: "com.apple.Safari", visited: nil, visits: 1)
        XCTAssertEqual(HistoryMeaning.describe(rib), "“Votre RIB : (a bank account number) – Banque” on banque.example.com", "masked")
        let long = HistoryVisit(url: "https://example.com", title: String(repeating: "a ", count: 74) + "12345 67890 12345678901 04", browser: "Safari",
                                bundleID: "com.apple.Safari", visited: nil, visits: 1)
        XCTAssertFalse(HistoryMeaning.describe(long).contains("12345"), "masked before the cut")
        // Masking shortens what comes before: a number past the old cut still goes masked.
        let ibans = String(repeating: "FR76 3000 6000 0112 3456 7890 189 ", count: 4) + String(repeating: "x", count: 82)
        let shifted = HistoryVisit(url: "https://example.com", title: ibans + " 12345 67890 12345678901 04", browser: "Safari",
                                   bundleID: "com.apple.Safari", visited: nil, visits: 1)
        XCTAssertEqual(HistoryMeaning.describe(shifted), "“" + String(repeating: "(an IBAN) ", count: 4) + String(repeating: "x", count: 82)
                       + " (a bank account number)” on example.com")
        let untitled = HistoryVisit(url: "https://example.com/reset?token=abc123#x", title: "", browser: "Safari",
                                    bundleID: "com.apple.Safari", visited: nil, visits: 1)
        XCTAssertEqual(HistoryMeaning.describe(untitled), "“https://example.com/reset?…” on example.com", "no query")
        XCTAssertEqual(HistoryMeaning.shortWhen(visit.visited!, now: now, calendar: calendar), "yesterday")
        XCTAssertEqual(HistoryMeaning.shortWhen(now.addingTimeInterval(-3_600), now: now, calendar: calendar), "08:00")
        XCTAssertEqual(HistoryMeaning.shortWhen(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar), "Fri")
        XCTAssertEqual(HistoryMeaning.shortWhen(now.addingTimeInterval(-40 * 86_400), now: now, calendar: calendar), "2 Sep")
    }

    func testMergingFiltersAndPatterns() {
        let old = HistoryVisit(url: "https://a.com", title: "A", browser: "Chrome", bundleID: "c", visited: Date(timeIntervalSince1970: 10), visits: 1)
        let new = HistoryVisit(url: "https://a.com", title: "A", browser: "Arc", bundleID: "a", visited: Date(timeIntervalSince1970: 20), visits: 1)
        let other = HistoryVisit(url: "https://b.com", title: "B", browser: "Zen", bundleID: "z", visited: Date(timeIntervalSince1970: 15), visits: 1)
        XCTAssertEqual(HistoryMeaning.merged([[old, other], [new]], limit: 10).map(\.browser), ["Arc", "Zen"])
        XCTAssertEqual(HistoryMeaning.modeFilter("historique impôts"), "impôts")
        XCTAssertNil(HistoryMeaning.modeFilter("histoire"))
        XCTAssertEqual(HistoryMeaning.likePatterns("100% tarte_aux"), ["%100\\%%", "%tarte\\_aux%"])
    }
}
