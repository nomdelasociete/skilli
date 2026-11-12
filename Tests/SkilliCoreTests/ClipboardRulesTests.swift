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

    func testSubstringQueryTakesWordsOfThreeLettersOrMore() {
        XCTAssertEqual(ClipboardSearch.substringQuery("board"), "\"board\"")
        XCTAssertEqual(ClipboardSearch.substringQuery("  ithub.com/acme  voice "), "\"ithub.com/acme\" \"voice\"")
        XCTAssertEqual(ClipboardSearch.substringQuery("say \"hi\"!"), "\"say\" \"\"\"hi\"\"!\"")
        XCTAssertNil(ClipboardSearch.substringQuery("id 4521"))
        XCTAssertNil(ClipboardSearch.substringQuery("ab"))
        XCTAssertNil(ClipboardSearch.substringQuery("   "))
    }

    func testFoundLineIsTheTitleWhenTheFirstLineDoesNotHoldTheWord() {
        let text = "Meeting notes\n\nPlease send the signed invoice for October before Friday.\nThanks"
        XCTAssertEqual(ClipboardSearch.found("voice", in: text), "…send the signed invoice for October before Friday.")
        XCTAssertNil(ClipboardSearch.found("meet", in: text))
        XCTAssertNil(ClipboardSearch.found("absent", in: text))
        XCTAssertEqual(ClipboardSearch.found("THANKS", in: text), "Thanks")
        XCTAssertEqual(ClipboardSearch.found("reunion", in: "Agenda\nRéunion à 14 h"), "Réunion à 14 h")
        XCTAssertEqual(ClipboardSearch.ranges(of: "o no", in: "No, not now").map { String("No, not now"[$0]) }, ["No", "o", "no", "o", "no", "o"])
    }

    func testRowsSayWhenAndTheHeaderSaysTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let locale = Locale(identifier: "en_GB")
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        let now = date(2026, 11, 10, 18, 30)   // a Tuesday
        func short(_ date: Date) -> String { ClipboardDay.short(date, now: now, calendar: calendar, locale: locale) }
        func header(_ date: Date) -> String { ClipboardDay.header(date, now: now, calendar: calendar, locale: locale) }
        XCTAssertEqual(short(date(2026, 11, 10, 9, 23)), "09:23")
        XCTAssertEqual(short(date(2026, 11, 9, 23, 59)), "Mon")
        XCTAssertEqual(short(date(2026, 11, 4)), "Wed")
        XCTAssertEqual(short(date(2026, 11, 3)), "3 Nov")
        XCTAssertEqual(short(date(2025, 11, 3)), "3 Nov 2025")
        XCTAssertEqual(header(date(2026, 11, 10, 0, 1)), "Copied today")
        XCTAssertEqual(header(date(2026, 11, 9, 23, 59)), "Copied yesterday")
        XCTAssertEqual(header(date(2026, 11, 6)), "Copied Friday")
        XCTAssertEqual(header(date(2026, 11, 3)), "Copied 3 November")
        XCTAssertEqual(header(date(2025, 11, 3)), "Copied 3 November 2025")
        XCTAssertEqual(header(date(2026, 11, 11)), "Copied today")
    }

    func testWhatACopyIs() {
        XCTAssertEqual(ClipboardKind.of(stored: "image", text: ""), .image)
        XCTAssertEqual(ClipboardKind.of(stored: "files", text: "/tmp/Scan.png"), .image)
        XCTAssertEqual(ClipboardKind.of(stored: "files", text: "/tmp/notes.txt"), .file)
        XCTAssertEqual(ClipboardKind.of(stored: "files", text: "/tmp/a.png\n/tmp/b.png"), .file)
        XCTAssertEqual(ClipboardKind.of(stored: "text", text: "https://example.com/page"), .link)
        XCTAssertEqual(ClipboardKind.of(stored: "text", text: "someone@example.com"), .email)
        XCTAssertEqual(ClipboardKind.of(stored: "text", text: "#3E8E7E"), .color)
        XCTAssertEqual(ClipboardKind.of(stored: "text", text: "Lunch on Thursday?"), .text)
        // Every kind has a name, and is kept under its own word.
        for kind in ClipboardKind.allCases {
            XCTAssertFalse(kind.plural.isEmpty)
            XCTAssertEqual(ClipboardKind(rawValue: kind.rawValue), kind)
        }
    }

    func testOneCopiedPictureFileIsAPicture() {
        XCTAssertEqual(CopiedPicture.path(in: "/tmp/CleanShot 2026-11-10 at 18.16.45@2x.jpg"), "/tmp/CleanShot 2026-11-10 at 18.16.45@2x.jpg")
        XCTAssertEqual(CopiedPicture.path(in: "/tmp/Scan.HEIC"), "/tmp/Scan.HEIC")
        XCTAssertNil(CopiedPicture.path(in: "/tmp/a.png\n/tmp/b.png"))
        XCTAssertNil(CopiedPicture.path(in: "/tmp/notes.txt"))
        XCTAssertNil(CopiedPicture.path(in: "/tmp/.png"))
        XCTAssertNil(CopiedPicture.path(in: "/tmp/folder.png/readme"))
        XCTAssertNil(CopiedPicture.path(in: ""))
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

    /// Made here, never real: the shapes only.
    func testKeysAndTokensAreKnownByTheirShape() {
        let letters = String(repeating: "aB3dE6gH", count: 8)
        XCTAssertEqual(ClipboardSecret.name(of: "ghp_" + letters.prefix(36)), "a GitHub token")
        XCTAssertEqual(ClipboardSecret.name(of: "  github_pat_" + letters + "\n"), "a GitHub token")
        XCTAssertEqual(ClipboardSecret.name(of: "sk-proj-" + letters), "an API key")
        XCTAssertEqual(ClipboardSecret.name(of: "sk_test_" + letters.prefix(24)), "a Stripe key")
        XCTAssertEqual(ClipboardSecret.name(of: "AKIA" + "ABCDEFGH12345678"), "an AWS access key")
        XCTAssertEqual(ClipboardSecret.name(of: "xoxb-" + "1234567890-" + letters.prefix(24)), "a Slack token")
        XCTAssertEqual(ClipboardSecret.name(of: "eyJ" + letters.prefix(20) + ".eyJ" + letters.prefix(30) + "." + letters.prefix(43)), "a sign-in token")
        // In two pieces: the repo's hygiene check refuses the header whole.
        let header = "-----BEGIN OPENSSH " + "PRIVATE KEY-----"
        XCTAssertEqual(ClipboardSecret.name(of: header + "\n" + letters + "\n-----END OPENSSH " + "PRIVATE KEY-----\n"), "a private key")
        // Whatever is around it: a long copy, a word lost in spaces.
        let long = String(repeating: "a line of a long file\n", count: 6_000)
        XCTAssertEqual(ClipboardSecret.name(of: long + header + "\n" + letters), "a private key")
        XCTAssertEqual(ClipboardSecret.name(of: String(repeating: " ", count: 120_000) + "ghp_" + letters.prefix(36)), "a GitHub token")
        XCTAssertNil(ClipboardSecret.name(of: long))
    }

    /// What the user wants back from the history is kept: a hash, a UUID,
    /// a sentence that names a key, a link, a short word.
    func testWhatOnlyLooksRandomIsKept() {
        let letters = String(repeating: "aB3dE6gH", count: 8)
        for kept in ["9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                     "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
                     "set GITHUB_TOKEN to ghp_" + letters.prefix(36) + " in the file",
                     "https://example.com/a/very/long/path/with-many-words-in-it",
                     "sk-short", "ghp_", "skilli", "",
                     "-----BEGIN CERTIFICATE-----\n" + letters + "\n-----END CERTIFICATE-----"] {
            XCTAssertNil(ClipboardSecret.name(of: kept), kept)
        }
    }

    func testACopyNotKeptSaysWhatFromWhereAndWhen() {
        let date = Date(timeIntervalSince1970: 1_000)
        let secret = ClipboardNotKept(reason: .secret("a GitHub token"), appName: "Terminal", date: date)
        XCTAssertEqual(secret.line(time: "14:02"), "Not kept: looks like a GitHub token (Terminal, 14:02). To keep them: Settings → Clipboard → Advanced.")
        XCTAssertEqual(ClipboardNotKept(reason: .longText, appName: nil, date: date).line(time: "14:02"), "Not kept: a text over 5 MB (14:02).")
        XCTAssertEqual(ClipboardNotKept(reason: .bigPicture, appName: "Preview", date: date).line(time: "9:41"),
                       "Not kept: a picture over 40 MB (Preview, 9:41).")
        XCTAssertTrue(secret.isRecent(now: date.addingTimeInterval(3_600)))
        XCTAssertFalse(secret.isRecent(now: date.addingTimeInterval(90_000)))
    }

    func testACopySavedAsASnippetStartsFromItsFirstLine() {
        let draft = Snippet.draft(from: "\n  Bien cordialement,\nCamille Martin\n")
        XCTAssertEqual(draft.id, "")
        XCTAssertEqual(draft.name, "Bien cordialement,")
        XCTAssertEqual(draft.keyword, "")
        XCTAssertEqual(draft.text, "\n  Bien cordialement,\nCamille Martin\n")
        XCTAssertEqual(Snippet.draft(from: String(repeating: "word ", count: 30)).name.count, 39)
        XCTAssertEqual(Snippet.draft(from: "   ").name, "")
    }

    func testSeveralCopiesGoInTheOrderCopied() {
        let start = Date(timeIntervalSince1970: 1_000)
        func copy(_ id: Int64, _ after: TimeInterval, _ family: ClipboardSelection.Family, _ text: String) -> ClipboardSelection.Copy {
            .init(id: id, copied: start.addingTimeInterval(after), family: family, text: text)
        }
        let a = copy(1, 0, .text, "A"), b = copy(2, 10, .text, "B\nb"), c = copy(3, 20, .text, "C")
        // Selected C, A, B: pasted A, B, C.
        XCTAssertEqual(ClipboardSelection.ordered([c, a, b]).map(\.id), [1, 2, 3])
        XCTAssertEqual(ClipboardSelection.paste([c, a, b]), .text("A\nB\nb\nC"))
        // The same instant: by id.
        XCTAssertEqual(ClipboardSelection.ordered([copy(9, 0, .text, "z"), copy(4, 0, .text, "y")]).map(\.id), [4, 9])
        XCTAssertEqual(ClipboardSelection.paste([copy(2, 5, .files, "/Users/me/b.txt\n/Users/me/c.txt"), copy(1, 0, .files, "/Users/me/a.txt")]),
                       .files(["/Users/me/a.txt", "/Users/me/b.txt", "/Users/me/c.txt"]))
        XCTAssertEqual(ClipboardSelection.paste([a, copy(5, 30, .files, "/Users/me/a.txt")]), ClipboardSelection.Paste.none)
        XCTAssertEqual(ClipboardSelection.paste([copy(6, 0, .image, ""), copy(7, 1, .image, "")]), ClipboardSelection.Paste.none)
        XCTAssertEqual(ClipboardSelection.paste([]), ClipboardSelection.Paste.none)
        XCTAssertEqual(ClipboardSelection.paste([a]), .text("A"))
        XCTAssertEqual(ClipboardSelection.chip(filter: nil, selected: 0), "Clipboard")
        XCTAssertEqual(ClipboardSelection.chip(filter: nil, selected: 3), "Clipboard · 3 selected")
        XCTAssertEqual(ClipboardSelection.chip(filter: "Links", selected: 2), "Clipboard · Links · 2 selected")
        XCTAssertEqual(ClipboardSelection.chip(filter: "Links", selected: 0), "Clipboard · Links")
    }

    func testFilesGoneSinceAreSaid() {
        XCTAssertNil(ClipboardFiles.line(gone: [], of: 3, done: "pasted"))
        XCTAssertEqual(ClipboardFiles.line(gone: ["report.pdf"], of: 1, done: "pasted"),
                       "“report.pdf” is no longer where it was copied: ⇧↩ pastes its path.")
        XCTAssertEqual(ClipboardFiles.line(gone: ["a", "b", "c"], of: 3, done: "pasted"),
                       "These 3 files are no longer where they were copied: ⇧↩ pastes their paths.")
        XCTAssertEqual(ClipboardFiles.line(gone: ["a.png"], of: 2, done: "pasted"), "“a.png” is no longer there: the other was pasted.")
        XCTAssertEqual(ClipboardFiles.line(gone: ["a.png"], of: 4, done: "copied"), "“a.png” is no longer there: the 3 others were copied.")
        XCTAssertEqual(ClipboardFiles.line(gone: ["a", "b"], of: 5, done: "pasted"), "2 of 5 files are no longer there: the 3 others were pasted.")
        XCTAssertEqual(ClipboardFiles.count(5, gone: 0), "5 Files")
        XCTAssertEqual(ClipboardFiles.count(5, gone: 2), "5 Files · 2 no longer there")
        XCTAssertEqual(ClipboardFiles.count(2, gone: 2), "2 Files · no longer there")
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

    /// Begun on selected copies: those, in the order given, under the
    /// same rules; past the last it says how many; then today's again.
    func testPasteSequenceOnSelectedCopies() {
        var sequence = PasteSequence()
        let history: [Int64] = [40, 30, 20, 10]
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(sequence.begin(with: [10, 30, 40], now: start), 10)
        XCTAssertTrue(sequence.chosen)
        sequence.wrote(changeCount: 6)
        XCTAssertEqual(sequence.next(now: start + 3, changeCount: 6, newest: { history }), 30)
        sequence.wrote(changeCount: 7)
        XCTAssertEqual(sequence.next(now: start + 6, changeCount: 7, newest: { history }), 40)
        sequence.wrote(changeCount: 8)
        XCTAssertNil(sequence.next(now: start + 8, changeCount: 8, newest: { history }), "past the last selected")
        XCTAssertEqual(sequence.end, "That was the last of the 3 selected.")
        // The next run is today's: the newest copy, then older.
        XCTAssertEqual(sequence.next(now: start + 9, changeCount: 8, newest: { history }), 40)
        XCTAssertFalse(sequence.chosen)
        XCTAssertEqual(sequence.end, "That was the oldest copy. Again starts from the newest.")

        // A copy of the user's own in between: the selection is over.
        XCTAssertEqual(sequence.begin(with: [10, 20], now: start + 20), 10)
        sequence.wrote(changeCount: 9)
        XCTAssertEqual(sequence.next(now: start + 22, changeCount: 10, newest: { history }), 40)
        XCTAssertFalse(sequence.chosen)
        // 30 s without a key: over too.
        XCTAssertEqual(sequence.begin(with: [10, 20], now: start + 30), 10)
        sequence.wrote(changeCount: 11)
        XCTAssertEqual(sequence.next(now: start + 31 + PasteSequence.pause, changeCount: 11, newest: { history }), 40)

        // One selected; none; more than a sequence holds.
        XCTAssertEqual(sequence.begin(with: [20], now: start), 20)
        XCTAssertEqual(sequence.end, "That was the only copy selected.")
        XCTAssertNil(sequence.begin(with: [], now: start))
        XCTAssertEqual(sequence.begin(with: Array(1...80), now: start), 1)
        XCTAssertEqual(sequence.ids.count, PasteSequence.length)
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
