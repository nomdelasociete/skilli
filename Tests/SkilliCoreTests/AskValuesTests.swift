import SkilliCore
import XCTest

final class AskValuesTests: XCTestCase {
    private func answers(_ pairs: [String: String], sure: Double = 0.95) -> [String: AskValues.Answer] {
        pairs.mapValues { AskValues.Answer(choice: $0, confidence: sure) }
    }

    /// One option per length, however it is said: "une heure trente" is
    /// 1h30, never "one hour" with the rest dropped, never 90 hours.
    func testALengthIsOneOption() {
        XCTAssertEqual(AskValues.duration(answers(["length": "1 h 30"]))?.seconds, 5_400)
        XCTAssertEqual(AskValues.duration(answers(["length": "1 h 15"]))?.seconds, 4_500)
        XCTAssertEqual(AskValues.duration(answers(["length": "1 h"]))?.seconds, 3_600)
        XCTAssertEqual(AskValues.duration(answers(["length": "20 min"]))?.seconds, 1_200)
        XCTAssertEqual(AskValues.duration(answers(["length": "30 s"]))?.seconds, 30)
        XCTAssertEqual(AskValues.duration(answers(["length": "1 min 30 s"]))?.seconds, 90)
        XCTAssertEqual(AskValues.duration(answers(["length": "48 h"]))?.seconds, 172_800)
        XCTAssertNil(AskValues.duration(answers(["length": "none"])))
        XCTAssertNil(AskValues.duration(answers(["length": "until"])), "until without its hour: nothing")
        let options = AskValues.durationQuestions[0].options
        XCTAssertEqual(Set(options.map(\.value)).count, options.count, "every length once")
        XCTAssertTrue(options.contains { $0.value == "1 h 30" && $0.description.contains("90 minutes") && $0.description.contains("an hour and a half") })
        XCTAssertTrue(options.contains { $0.value == "4 h 15" }, "every 15 minutes past 4 h")
        XCTAssertTrue(options.contains { $0.value == "15 min" && $0.description.contains("un quart d'heure") })
        XCTAssertTrue(options.contains { $0.value == "1 h 30" && $0.description.contains("une heure et demie") })
        XCTAssertTrue(options.contains { $0.value == "2 h 05" }, "every 5 minutes to 4 h")
    }

    /// Until a time of day: today when still ahead, else tomorrow.
    func testUntilATimeOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 14, minute: 0))!
        let tonight = answers(["length": "until", "until_hour": "18", "until_minute": "30"])
        XCTAssertEqual(AskValues.duration(tonight, now: now, calendar: calendar)?.seconds, 4 * 3_600 + 1_800)
        let morning = answers(["length": "until", "until_hour": "9", "until_minute": "none"])
        XCTAssertEqual(AskValues.duration(morning, now: now, calendar: calendar)?.seconds, 19 * 3_600)
    }

    /// The least sure part used says how sure the whole is.
    func testTheLeastSurePartDecides() {
        var parts = answers(["length": "until", "until_hour": "18", "until_minute": "30"])
        parts["until_minute"] = AskValues.Answer(choice: "30", confidence: 0.41)
        XCTAssertEqual(AskValues.duration(parts)?.confidence, 0.41)
        // A part not used (no end time) does not lower it.
        parts["length"] = AskValues.Answer(choice: "1 h 30", confidence: 0.9)
        XCTAssertEqual(AskValues.duration(parts)?.confidence, 0.9)
    }

    func testALevel() {
        XCTAssertEqual(AskValues.level(answers(["level": "30"]))?.level, 30)
        XCTAssertNil(AskValues.level(answers(["level": "none"])))
    }

    /// What for: picked among the request's own words, never written.
    func testWhatForIsTheRequestsOwnWords() {
        let request = "mets un minuteur de dix minutes pour les pâtes."
        let spans = AskValues.spans(of: request)
        XCTAssertTrue(spans.contains("les pâtes"))
        XCTAssertTrue(spans.contains("pâtes"), "the last word without its period")
        XCTAssertLessThanOrEqual(spans.count, 254)
        let index = spans.firstIndex(of: "les pâtes")!
        XCTAssertEqual(AskValues.label(answers(["label": "phrase \(index)"]), spans: spans), "les pâtes")
        XCTAssertNil(AskValues.label(answers(["label": "none"]), spans: spans))
        XCTAssertEqual(AskValues.labelQuestion(spans: spans).options.count, spans.count + 1)
        // A long request stays within a question's options.
        XCTAssertLessThanOrEqual(AskValues.spans(of: String(repeating: "mot ", count: 200)).count, 254)
    }

    /// Every question within a Choice's 255 options.
    func testQuestionsFitAChoice() {
        for question in AskValues.durationQuestions + AskValues.levelQuestions {
            XCTAssertLessThanOrEqual(question.options.count, 255, question.name)
        }
    }
}
