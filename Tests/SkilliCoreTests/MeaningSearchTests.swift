import XCTest
@testable import SkilliCore

final class MeaningNarrowingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Wednesday 28 October 2026, 15:00 in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 15))!
    }

    private func day(_ day: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    /// The window read, as its first and last day (slack included).
    private func days(_ request: String) -> String? {
        guard let window = MeaningNarrowing(request, now: now, calendar: calendar).window else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "en_GB")
        return formatter.string(from: window.start) + " – " + formatter.string(from: window.end.addingTimeInterval(-1))
    }

    func testDaysNamedBecomeAWindowWithADayOfSlack() {
        XCTAssertEqual(days("the email I copied today"), "27 Oct – 29 Oct")
        XCTAssertEqual(days("le lien d'hier"), "26 Oct – 28 Oct")
        XCTAssertEqual(days("yesterday's link"), "26 Oct – 28 Oct")
        XCTAssertEqual(days("the address I copied the day before yesterday"), "25 Oct – 27 Oct")
        XCTAssertEqual(days("l'adresse mail d'avant-hier"), "25 Oct – 27 Oct")
        XCTAssertEqual(days("Avant hier, le numéro"), "25 Oct – 27 Oct")
        // Monday 19 to Sunday 25, a day each side.
        XCTAssertEqual(days("la facture de la semaine dernière"), "18 Oct – 26 Oct")
        XCTAssertEqual(days("last week's screenshot"), "18 Oct – 26 Oct")
        XCTAssertEqual(days("this week"), "25 Oct – 29 Oct")
        XCTAssertEqual(days("le mois dernier"), "31 Aug – 1 Oct")
        XCTAssertEqual(days("3 days ago"), "24 Oct – 26 Oct")
        XCTAssertEqual(days("il y a deux jours"), "25 Oct – 27 Oct")
        // The last Monday before today; today's weekday is last week's.
        XCTAssertEqual(days("the code from Monday"), "25 Oct – 27 Oct")
        XCTAssertEqual(days("lundi"), "25 Oct – 27 Oct")
        XCTAssertEqual(days("mercredi"), "20 Oct – 22 Oct")
        XCTAssertEqual(days("Thursday"), "21 Oct – 23 Oct")
        XCTAssertEqual(days("ce matin"), "27 Oct – 29 Oct")
        // Two days named: from the first to the last.
        XCTAssertEqual(days("hier ou aujourd'hui"), "26 Oct – 29 Oct")
    }

    func testNoDaysNoWindow() {
        XCTAssertNil(days("the electricity bill"))
        XCTAssertNil(days("hierarchy of needs"))
        XCTAssertNil(days("Thomas's address"))
        XCTAssertNil(days("le planning"))
    }

    func testKindsNamed() {
        func kinds(_ request: String) -> Set<MeaningNarrowing.Kind> { MeaningNarrowing(request, now: now, calendar: calendar).kinds }
        XCTAssertEqual(kinds("l'adresse mail de Camille"), [.email])
        XCTAssertEqual(kinds("the e-mail address"), [.email])
        XCTAssertEqual(kinds("email"), [.email])
        XCTAssertEqual(kinds("le lien figma"), [.link])
        XCTAssertEqual(kinds("the URL"), [.link])
        XCTAssertEqual(kinds("the screenshot where the payout failed"), [.image])
        XCTAssertEqual(kinds("la capture d'écran du billet"), [.image])
        XCTAssertEqual(kinds("son téléphone"), [.phone])
        XCTAssertEqual(kinds("phone number of the plumber"), [.phone])
        XCTAssertEqual(kinds("mon IBAN"), [.iban])
        XCTAssertEqual(kinds("le RIB"), [.iban])
        XCTAssertEqual(kinds("the file I copied in Finder"), [.file])
        XCTAssertEqual(kinds("les fichiers"), [.file])
        // "Mail" alone is the app as often as an address.
        XCTAssertEqual(kinds("the text from Mail"), [])
        XCTAssertEqual(kinds("la facture d'électricité"), [])
    }

    func testCopiesHoldTheKindsNamed() {
        func holds(_ kind: MeaningNarrowing.Kind, _ text: String, copy: ClipboardMeaning.Kind = .text, ocr: String? = nil) -> Bool {
            MeaningNarrowing.holds(kind, copy: copy, text: text, ocr: ocr)
        }
        XCTAssertTrue(holds(.email, "Écris à camille@example.com, elle répond vite"))
        XCTAssertFalse(holds(.email, "@camille on Slack"))
        XCTAssertTrue(holds(.email, "", copy: .image, ocr: "Contact: margot.martin@example.com"))
        XCTAssertTrue(holds(.link, "voir https://www.figma.com/file/abc123"))
        XCTAssertTrue(holds(.link, "www.example.com/devis"))
        XCTAssertFalse(holds(.link, "Réunion produit jeudi"))
        XCTAssertTrue(holds(.phone, "Rappelle le 06 12 34 56 78 demain"))
        XCTAssertTrue(holds(.phone, "+33 6 12 34 56 78"))
        XCTAssertTrue(holds(.phone, "(415) 555-0132"))
        XCTAssertFalse(holds(.phone, "Réunion le 2026-10-28"))
        XCTAssertFalse(holds(.phone, "82,40 € à régler"))
        XCTAssertTrue(holds(.iban, "Mon IBAN : FR76 3000 6000 0112 3456 7890 189"))
        XCTAssertFalse(holds(.iban, "FR76 et le reste"))
        XCTAssertTrue(holds(.image, "", copy: .image))
        XCTAssertTrue(holds(.image, "/Users/me/Desktop/Capture.png", copy: .files))
        XCTAssertFalse(holds(.image, "/Users/me/Devis.pdf", copy: .files))
        XCTAssertTrue(holds(.file, "/Users/me/Devis.pdf", copy: .files))
        XCTAssertFalse(holds(.file, "Devis.pdf"))
    }

    private struct Copy: Equatable {
        let name: String
        let date: Date?
        let email: Bool
    }

    private func narrowed(_ request: String, _ copies: [Copy], limit: Int = 2) -> [String] {
        MeaningNarrowing(request, now: now, calendar: calendar)
            .narrowed(copies, fitting: limit, date: \.date, holds: { copy, kind in kind == .email && copy.email })
            .map(\.name)
    }

    func testALongListIsNarrowedAShortOneKeptWhole() {
        let copies = [
            Copy(name: "today", date: day(28), email: false),
            Copy(name: "yesterday's address", date: day(27), email: true),
            Copy(name: "yesterday's note", date: day(27), email: false),
            Copy(name: "a week ago", date: day(21), email: true),
            Copy(name: "no date", date: nil, email: true)
        ]
        XCTAssertEqual(narrowed("l'adresse mail d'hier", copies), ["yesterday's address"])
        // A day's slack: today and the day before yesterday count too.
        XCTAssertEqual(narrowed("hier", copies), ["today", "yesterday's address", "yesterday's note"])
        XCTAssertEqual(narrowed("an email", copies), ["yesterday's address", "a week ago", "no date"])
        XCTAssertEqual(narrowed("the bill", copies), copies.map(\.name))
        // Under the limit: every one, as one question holds them.
        XCTAssertEqual(narrowed("l'adresse mail d'hier", copies, limit: 5), copies.map(\.name))
    }

    func testAStepThatLeavesNothingIsSkipped() {
        let copies = [
            Copy(name: "a", date: day(10), email: false),
            Copy(name: "b", date: day(11), email: true),
            Copy(name: "c", date: day(12), email: false)
        ]
        // Nothing yesterday: the email among all of them.
        XCTAssertEqual(narrowed("l'adresse mail d'hier", copies), ["b"])
        // Nothing yesterday, no email: all of them.
        XCTAssertEqual(narrowed("le lien d'hier", copies), ["a", "b", "c"])
    }
}

final class MeaningRoundsTests: XCTestCase {
    /// Answers like a model that knows which value is meant: it, and a
    /// second guess in each part.
    private actor Asked {
        var questions: [[String]] = []
        func add(_ values: [String]) { questions.append(values) }
    }

    func testFewValuesOneQuestion() async throws {
        let asked = Asked()
        let outcome = try await MeaningRounds.decide((0..<240).map { "c\($0)" }) { values in
            await asked.add(values)
            return .init(choice: "c7", probabilities: ["c7": 0.9, "none": 0.1])
        }
        XCTAssertEqual(outcome?.answer.choice, "c7")
        XCTAssertEqual(outcome?.questions, 1)
        XCTAssertEqual(outcome?.rounds, 1)
        let questions = await asked.questions
        XCTAssertEqual(questions.map(\.count), [240])
    }

    func testManyValuesInPartsThenTheirPicks() async throws {
        let asked = Asked()
        let values = (0..<1_000).map { "c\($0)" }
        let outcome = try await MeaningRounds.decide(values) { part in
            await asked.add(part)
            var probabilities = Dictionary(uniqueKeysWithValues: part.map { ($0, 0.001) })
            // Each part's first value a weak guess; c613 the one meant.
            probabilities[part[0]] = 0.05
            if part.contains("c613") { probabilities["c613"] = 0.8 }
            if part.count < 240 && part.contains("c613") { return .init(choice: "c613", probabilities: probabilities) }
            return .init(choice: part.contains("c613") ? "c613" : part[0], probabilities: probabilities)
        }
        let questions = await asked.questions
        // 240 + 240 + 240 + 240 + 40, then the five first values and c613.
        XCTAssertEqual(questions.prefix(5).map(\.count).sorted(), [40, 240, 240, 240, 240])
        XCTAssertEqual(questions.last, ["c0", "c240", "c480", "c613", "c720", "c960"], "the picks, in their first order")
        XCTAssertEqual(outcome?.answer.choice, "c613")
        XCTAssertEqual(outcome?.questions, 6)
        XCTAssertEqual(outcome?.rounds, 2)
        XCTAssertEqual(outcome?.parts, 5)
        XCTAssertEqual(outcome?.unanswered, 0)
    }

    func testAPartKeepsItsLikelyPicksOnly() {
        let probabilities = ["a": 0.5, "b": 0.03, "none": 0.3, "c": 0.04].merging((0..<12).map { ("x\($0)", 0.05) }) { $1 }
        XCTAssertEqual(MeaningRounds.kept(probabilities), ["a", "x0", "x1", "x10", "x11", "x2", "x3", "x4"])
        XCTAssertEqual(MeaningRounds.kept(["none": 0.97, "a": 0.03]), [])
    }

    func testPartsAllSayingNoneFindNothing() async throws {
        let outcome = try await MeaningRounds.decide((0..<500).map { "c\($0)" }) { _ in .nothing }
        XCTAssertEqual(outcome?.answer, .nothing)
        XCTAssertEqual(outcome?.questions, 3)
        XCTAssertEqual(outcome?.rounds, 1)
    }

    func testPartsUnansweredAreCountedAndLeftOut() async throws {
        struct Down: Error {}
        let outcome = try await MeaningRounds.decide((0..<500).map { "c\($0)" }) { part in
            if part.contains("c0") { return nil }
            if part.contains("c240") { throw Down() }
            return .init(choice: part[0], probabilities: [part[0]: 0.9])
        }
        XCTAssertEqual(outcome?.answer.choice, "c480")
        XCTAssertEqual(outcome?.parts, 3)
        XCTAssertEqual(outcome?.unanswered, 2)
    }

    func testNoPartAnsweringThrowsOrSaysNoAnswer() async {
        struct Down: Error {}
        do {
            _ = try await MeaningRounds.decide((0..<500).map { "c\($0)" }) { _ in throw Down() }
            XCTFail("every part failed")
        } catch {
            XCTAssertTrue(error is Down)
        }
        let silent = try? await MeaningRounds.decide((0..<500).map { "c\($0)" }) { _ in nil }
        XCTAssertNil(silent)
    }

    func testNoMoreThanInFlightAtOnce() async throws {
        actor Gauge {
            var now = 0, most = 0
            func enter() { now += 1; most = max(most, now) }
            func leave() { now -= 1 }
        }
        let gauge = Gauge()
        _ = try await MeaningRounds.decide((0..<(240 * 40)).map { "c\($0)" }, inFlight: 16) { part in
            await gauge.enter()
            try await Task.sleep(for: .milliseconds(5))
            await gauge.leave()
            return .init(choice: part[0], probabilities: [part[0]: 0.9])
        }
        let most = await gauge.most
        XCTAssertEqual(most, 16)
    }

    func testPicksStillTooManyAskAgainInParts() async throws {
        let asked = Asked()
        // 40 parts × 8 picks = 320 picks: two parts, then their picks.
        let outcome = try await MeaningRounds.decide((0..<(240 * 40)).map { "c\($0)" }) { part in
            await asked.add(part)
            let probabilities = Dictionary(uniqueKeysWithValues: part.prefix(8).map { ($0, 0.1) })
            return .init(choice: part[0], probabilities: probabilities)
        }
        let questions = await asked.questions
        XCTAssertEqual(questions.count, 40 + 2 + 1)
        XCTAssertEqual(outcome?.rounds, 3)
        XCTAssertEqual(outcome?.questions, 43)
    }
}
