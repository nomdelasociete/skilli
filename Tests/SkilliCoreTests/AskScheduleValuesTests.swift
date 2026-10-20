import SkilliCore
import XCTest

final class AskScheduleValuesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func read(_ request: String, _ pairs: [String: String]) -> AskValues.ScheduleAsk {
        AskValues.schedule(pairs.mapValues { AskValues.Answer(choice: $0, confidence: 0.9) }, words: AskValues.words(of: request), now: now)
    }


    /// The option of `text` among the request's phrases.
    private func phrase(_ request: String, _ text: String, longest: Int = 8) -> String {
        "phrase \(AskValues.phrases(of: AskValues.words(of: request), longest: longest).firstIndex(of: text) ?? -1)"
    }

    func testEveryMondayAtNine() {
        let said = "tous les lundis à 9h résume mes PR"
        XCTAssertEqual(read(said, ["schedule_repeat": "some days", "day_1": "monday", "day_2": "none", "hour": "9", "minute": "0",
                                   "ask": phrase(said, "résume mes PR"), "is_reminder": "no"]),
                       .schedule(AskSchedule(.weekly, weekdays: [2], hour: 9, start: now), ask: "résume mes PR"))
    }

    /// What to do is the phrase picked, the words saying when left out.
    func testWhatToDoIsAPhrase() {
        let said = "résume mes PR chaque lundi à 9h"
        guard case .schedule(_, let ask) = read(said, ["schedule_repeat": "some days", "day_1": "monday", "hour": "9", "ask": phrase(said, "résume mes PR")]) else {
            return XCTFail("no schedule")
        }
        XCTAssertEqual(ask, "résume mes PR")
    }

    func testWeekdaysMonthsAndTheMorning() {
        guard case .schedule(let weekdays, _) = read("every weekday at 8:30 tell me my day",
                                                     ["schedule_repeat": "every weekday", "hour": "8", "minute": "30", "ask": phrase("every weekday at 8:30 tell me my day", "tell me my day")]) else {
            return XCTFail("no schedule")
        }
        XCTAssertEqual(weekdays, AskSchedule(.weekly, weekdays: [2, 3, 4, 5, 6], hour: 8, minute: 30, start: now))
        guard case .schedule(let monthly, _) = read("le 1er de chaque mois envoie-moi le point",
                                                    ["schedule_repeat": "every month", "day_of_month": "1", "hour": "none", "part_of_day": "none",
                                                     "ask": phrase("le 1er de chaque mois envoie-moi le point", "envoie-moi le point")]) else {
            return XCTFail("no schedule")
        }
        XCTAssertEqual(monthly, AskSchedule(.monthly, day: 1, hour: 9, start: now), "no time said: 9:00")
        guard case .schedule(let evenings, _) = read("chaque soir résume mes mails",
                                                     ["schedule_repeat": "every day", "hour": "none", "part_of_day": "evening", "ask": phrase("chaque soir résume mes mails", "résume mes mails")]) else {
            return XCTFail("no schedule")
        }
        XCTAssertEqual(evenings.hour, 19)
    }

    func testARepeatingReminderIsNotASchedule() {
        XCTAssertEqual(read("rappelle-moi tous les lundis de sortir les poubelles", ["is_reminder": "yes"]), .plans)
    }

    func testMissingParts() {
        guard case .missing = read("tous les lundis résume mes PR", ["schedule_repeat": "some days", "ask": phrase("tous les lundis résume mes PR", "résume mes PR")]) else {
            return XCTFail("which days")
        }
        guard case .missing = read("tous les lundis", ["schedule_repeat": "some days", "day_1": "monday", "ask": "none"]) else {
            return XCTFail("what to do")
        }
    }

    func testTheAppNamed() {
        let said = "kill creative cloud"
        XCTAssertEqual(AskValues.target(["target": .init(choice: phrase(said, "creative cloud", longest: 4), confidence: 0.9)],
                                        words: AskValues.words(of: said)), "creative cloud")
    }

    func testQuestionsFit() {
        let words = AskValues.words(of: String(repeating: "mot ", count: 80))
        for question in AskValues.scheduleQuestions(words: words) + AskValues.targetQuestions(words: words) {
            XCTAssertLessThanOrEqual(question.options.count, 255, question.name)
        }
        XCTAssertEqual(Set(AskValues.scheduleQuestions(words: words).map(\.name)).count, AskValues.scheduleQuestions(words: words).count)
    }
}
