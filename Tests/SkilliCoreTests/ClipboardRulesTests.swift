import XCTest
@testable import SkilliCore

final class ClipboardRulesTests: XCTestCase {
    func testRetentionRoundTripAndCutoff() {
        for retention in [ClipboardRetention.day, .week, .month, .unlimited, .days(10)] {
            XCTAssertEqual(ClipboardRetention(rawValue: retention.rawValue), retention)
        }
        XCTAssertEqual(ClipboardRetention(rawValue: "days:0"), .month)
        XCTAssertEqual(ClipboardRetention(rawValue: "nonsense"), .month)
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ClipboardRetention.week.cutoff(now: now), now.addingTimeInterval(-7 * 86_400))
        XCTAssertNil(ClipboardRetention.unlimited.cutoff(now: now))
    }

    func testCustomStartsFromTheCurrentChoice() {
        XCTAssertEqual(ClipboardRetention.day.asCustom, .days(1))
        XCTAssertEqual(ClipboardRetention.week.asCustom, .days(7))
        XCTAssertEqual(ClipboardRetention.month.asCustom, .days(30))
        XCTAssertEqual(ClipboardRetention.days(12).asCustom, .days(12))
        XCTAssertEqual(ClipboardRetention.unlimited.asCustom, .days(365))
    }

    func testRemovalLineSaysWhatGoesAndWhen() {
        XCTAssertEqual(ClipboardRetention.week.removalLine(older: 812), "812 copies are older than a week: they go within the hour.")
        XCTAssertEqual(ClipboardRetention.day.removalLine(older: 1), "1 copy is older than a day: it goes within the hour.")
        XCTAssertEqual(ClipboardRetention.month.removalLine(older: 3), "3 copies are older than a month: they go within the hour.")
        XCTAssertEqual(ClipboardRetention.days(10).removalLine(older: 2), "2 copies are older than 10 days: they go within the hour.")
        XCTAssertEqual(ClipboardRetention.days(1).removalLine(older: 2), "2 copies are older than a day: they go within the hour.")
        XCTAssertNil(ClipboardRetention.week.removalLine(older: 0))
        XCTAssertNil(ClipboardRetention.unlimited.removalLine(older: 40))
    }

    func testSearchQueryIsSafe() {
        XCTAssertEqual(ClipboardSearch.ftsQuery("fact 2026"), "\"fact\"* \"2026\"*")
        XCTAssertEqual(ClipboardSearch.ftsQuery("a\" OR 1=1; --"), "\"a\"* \"OR\"* \"1\"* \"1\"*")
        XCTAssertEqual(ClipboardSearch.ftsQuery("réunion"), "\"réunion\"*")
        XCTAssertNil(ClipboardSearch.ftsQuery("  -- "))
    }

    func testModeFilterAndTitles() {
        XCTAssertEqual(ClipboardSearch.modeFilter("clipboard facture"), "facture")
        XCTAssertEqual(ClipboardSearch.modeFilter("Clipboard "), "")
        XCTAssertEqual(ClipboardSearch.modeFilter("presse-papier réunion"), "réunion")
        XCTAssertNil(ClipboardSearch.modeFilter("clip studio"))
        XCTAssertNil(ClipboardSearch.modeFilter("clipy"))
        XCTAssertEqual(ClipboardSearch.title(of: "\n  Bonjour   à tous \nligne 2"), "Bonjour à tous")
        XCTAssertEqual(ClipboardSearch.title(of: String(repeating: "a", count: 5), limit: 3), "aaa…")
        XCTAssertEqual(ClipboardSearch.extraLines(in: "a\n\nb\n c \n"), 2)
    }

    func testPolicySkipsSecretsAndExcludedApps() {
        let text = ["public.utf8-plain-text"]
        XCTAssertTrue(ClipboardPolicy.shouldRecord(types: text, app: "com.apple.Safari", excluded: []))
        XCTAssertFalse(ClipboardPolicy.shouldRecord(types: text + ["org.nspasteboard.ConcealedType"], app: nil, excluded: []))
        XCTAssertFalse(ClipboardPolicy.shouldRecord(types: text + ["org.nspasteboard.TransientType"], app: nil, excluded: []))
        XCTAssertFalse(ClipboardPolicy.shouldRecord(types: text, app: "com.1password.1password", excluded: Set(ClipboardPolicy.defaultExcludedApps)))
        XCTAssertFalse(ClipboardPolicy.shouldRecord(types: [], app: nil, excluded: []))
    }

    /// Each run the next older copy, newest first; 30 s apart or a copy
    /// of the user's own in between starts again; past the oldest, none.
    func testPasteSequenceGoesOlderThenStartsAgain() {
        var sequence = PasteSequence()
        var history: [Int64] = [30, 20, 10]
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(sequence.next(now: start, changeCount: 5, newest: { history }), 30)
        sequence.wrote(changeCount: 6)
        // The history moves (the paste is kept again): the sequence keeps
        // the order it began with.
        history = [30, 20, 10, 5]
        XCTAssertEqual(sequence.next(now: start + 3, changeCount: 6, newest: { history }), 20)
        sequence.wrote(changeCount: 7)
        XCTAssertEqual(sequence.next(now: start + 6, changeCount: 7, newest: { history }), 10)
        sequence.wrote(changeCount: 8)
        XCTAssertNil(sequence.next(now: start + 8, changeCount: 8, newest: { history }), "past the oldest")
        // Nothing was written: the next run begins again.
        XCTAssertEqual(sequence.next(now: start + 9, changeCount: 8, newest: { history }), 30)
        sequence.wrote(changeCount: 9)

        // The user copied something: from the newest again.
        history = [40, 30, 20, 10, 5]
        XCTAssertEqual(sequence.next(now: start + 10, changeCount: 10, newest: { history }), 40)
        sequence.wrote(changeCount: 11)
        XCTAssertEqual(sequence.next(now: start + 12, changeCount: 11, newest: { history }), 30)
        sequence.wrote(changeCount: 12)
        // A pause longer than 30 s: from the newest again.
        XCTAssertEqual(sequence.next(now: start + 12 + PasteSequence.pause + 1, changeCount: 12, newest: { history }), 40)

        var empty = PasteSequence()
        XCTAssertNil(empty.next(now: start, changeCount: 1, newest: { [] }))
    }

    func testScreenshotNames() {
        XCTAssertTrue(ScreenshotName.looksLikeScreenshot("Screenshot 2026-10-15 at 09.05.12.png"))
        XCTAssertTrue(ScreenshotName.looksLikeScreenshot("Capture d’écran 2026-10-15 à 09.05.12.png"))
        XCTAssertTrue(ScreenshotName.looksLikeScreenshot("CleanShot 2026-10-15 at 09.05.12@2x.png"))
        XCTAssertTrue(ScreenshotName.looksLikeScreenshot("IMG_2026_screenshot.jpg"))
        XCTAssertFalse(ScreenshotName.looksLikeScreenshot("vacances.jpg"))
        XCTAssertFalse(ScreenshotName.looksLikeScreenshot("capture.png"))
    }
}
