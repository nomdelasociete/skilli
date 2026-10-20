import XCTest
@testable import SkilliCore

final class ClipboardMeaningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    /// Monday 12 October 2026, 01:30 in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 1, minute: 30))!
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testWhenSpeaksLikeAPerson() {
        XCTAssertEqual(ClipboardMeaning.when(now.addingTimeInterval(-30), now: now, calendar: calendar), "just now")
        XCTAssertEqual(ClipboardMeaning.when(date(12, 0, 15), now: now, calendar: calendar), "today 00:15")
        XCTAssertEqual(ClipboardMeaning.when(date(11, 18, 2), now: now, calendar: calendar), "yesterday 18:02")
        XCTAssertEqual(ClipboardMeaning.when(date(8, 9, 5), now: now, calendar: calendar), "Thursday 09:05")
        XCTAssertEqual(ClipboardMeaning.when(date(3, 9, 5), now: now, calendar: calendar), "3 October")
        XCTAssertEqual(ClipboardMeaning.when(date(3, 9, 5, year: 2025), now: now, calendar: calendar), "3 October 2025")
    }

    func testDescriptionsSayWhatWhereWhenThenTheWords() {
        let text = ClipboardMeaning.describe(kind: .text, text: "Facture EDF\n  octobre :   82,40 €", ocr: nil, appName: "Mail",
                                             copiedAt: date(11, 18, 2), now: now, calendar: calendar)
        XCTAssertEqual(text, "Text from Mail, yesterday 18:02: Facture EDF octobre : 82,40 €")
        let image = ClipboardMeaning.describe(kind: .image, text: "", ocr: "Billet Paris Lyon 14h05", appName: "CleanShot X",
                                              copiedAt: date(11, 9, 0), now: now, calendar: calendar)
        XCTAssertEqual(image, "Image from CleanShot X, yesterday 09:00. Text in it: Billet Paris Lyon 14h05")
        let blank = ClipboardMeaning.describe(kind: .image, text: "", ocr: nil, appName: nil, copiedAt: date(12, 0, 15), now: now, calendar: calendar)
        XCTAssertEqual(blank, "Image, today 00:15. No text in it.")
        let files = ClipboardMeaning.describe(kind: .files, text: "/Users/me/Devis.pdf\n/Users/me/Plan.png", ocr: nil, appName: "Finder",
                                              copiedAt: date(12, 0, 15), now: now, calendar: calendar)
        XCTAssertEqual(files, "Files from Finder, today 00:15: Devis.pdf, Plan.png")
    }

    func testExcerptIsShort() {
        let long = String(repeating: "mot ", count: 200)
        let excerpt = ClipboardMeaning.excerpt(long)
        XCTAssertEqual(excerpt.count, ClipboardMeaning.excerptLength + 1)
        XCTAssertTrue(excerpt.hasSuffix("…"))
    }

    func testInputCarriesTheRequestAndNow() {
        let input = ClipboardMeaning.input("ma facture d'électricité", now: now, calendar: calendar)
        XCTAssertTrue(input.hasPrefix("Looking for something copied earlier: ma facture d'électricité"))
        XCTAssertTrue(input.contains("Now: Monday 12 October 2026, 01:30"), input)
    }
}
