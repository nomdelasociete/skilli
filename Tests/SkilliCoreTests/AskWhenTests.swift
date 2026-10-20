import SkilliCore
import XCTest

final class AskWhenTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    /// Friday 16 October 2026, 14:00.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 14))! }

    private func answers(_ pairs: [String: String], sure: Double = 0.95) -> [String: AskValues.Answer] {
        pairs.mapValues { AskValues.Answer(choice: $0, confidence: sure) }
    }

    private func date(_ day: Int, _ month: Int = 10, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func when(_ pairs: [String: String]) -> (date: Date?, hasTime: Bool, confidence: Double)? {
        AskValues.when(answers(pairs), now: now, calendar: calendar)
    }

    func testWords() {
        XCTAssertEqual(AskValues.words(of: "rappelle-moi d'appeler Paul demain à 9h."),
                       ["rappelle-moi", "d'", "appeler", "Paul", "demain", "à", "9h"])
        XCTAssertEqual(AskValues.words(of: "qu'est-ce que j’ai aujourd'hui ?"), ["qu'", "est-ce", "que", "j’", "ai", "aujourd'hui"])
        XCTAssertEqual(AskValues.words(of: "jusqu'à 18h #Courses"), ["jusqu'à", "18h", "#Courses"])
    }

    /// What it says: the words between the first and the last picked.
    func testTitleFromItsFirstAndLastWords() {
        let words = AskValues.words(of: "rappelle-moi d'appeler Paul demain à 9h")
        XCTAssertEqual(AskValues.title(answers(["title_start": "word 2", "title_end": "word 3"]), words: words)?.title, "Appeler Paul")
        let elided = AskValues.words(of: "rappelle-moi de vérifier l'agenda demain")
        XCTAssertEqual(AskValues.title(answers(["title_start": "word 2", "title_end": "word 4"]), words: elided)?.title, "Vérifier l'agenda")
        XCTAssertNil(AskValues.title(answers(["title_start": "word 3", "title_end": "word 2"]), words: words), "backwards")
        // The words saying when, inside it, are left out.
        let meeting = AskValues.words(of: "crée un rdv demain à 14h avec Paul")
        XCTAssertEqual(AskValues.title(answers(["title_start": "word 2", "title_end": "word 7", "when_words_start": "word 3", "when_words_end": "word 5"]),
                                       words: meeting)?.title, "Rdv avec Paul")
        XCTAssertEqual(AskValues.title(answers(["title_start": "word 2", "title_end": "word 7", "when_words_start": "none", "when_words_end": "none"]),
                                       words: meeting)?.title, "Rdv demain à 14h avec Paul")
        XCTAssertNil(AskValues.title(answers(["title_start": "none", "title_end": "word 2"]), words: words))
        let questions = AskValues.titleQuestions(words: words, thing: "the reminder", examples: "")
        XCTAssertEqual(questions[0].options.count, words.count + 1)
        XCTAssertTrue(questions[0].options[2].description.contains("[appeler]"))
    }

    func testADayAndATime() {
        XCTAssertEqual(when(["when": "at", "day": "tomorrow", "hour": "9", "minute": "0"])?.date, date(17, 10, 9))
        XCTAssertEqual(when(["when": "at", "day": "tomorrow", "hour": "9", "minute": "none"])?.date, date(17, 10, 9))
        XCTAssertEqual(when(["when": "at", "day": "tomorrow", "hour": "none", "part_of_day": "morning"])?.date, date(17, 10, 9))
        let dayOnly = when(["when": "at", "day": "tomorrow", "hour": "none", "part_of_day": "none"])
        XCTAssertEqual(dayOnly?.date, date(17))
        XCTAssertEqual(dayOnly?.hasTime, false)
        XCTAssertEqual(when(["when": "at", "day": "today", "hour": "20", "minute": "30"])?.date, date(16, 10, 20, 30))
        XCTAssertEqual(when(["when": "at", "day": "after tomorrow", "hour": "none"])?.date, date(18))
    }

    /// A time alone: today, or tomorrow once it has passed.
    func testATimeAlone() {
        XCTAssertEqual(when(["when": "at", "day": "none", "hour": "18", "minute": "0"])?.date, date(16, 10, 18))
        XCTAssertEqual(when(["when": "at", "day": "none", "hour": "9", "minute": "0"])?.date, date(17, 10, 9))
        XCTAssertNil(when(["when": "at", "day": "none", "hour": "none", "part_of_day": "none"]), "nothing to place it")
    }

    /// Weekdays from Friday 16 October: the coming one, or next week's.
    func testWeekdays() {
        XCTAssertEqual(when(["when": "at", "day": "weekday", "weekday": "thursday", "week": "coming", "hour": "none"])?.date, date(22))
        XCTAssertEqual(when(["when": "at", "day": "weekday", "weekday": "monday", "week": "none", "hour": "10", "minute": "0"])?.date, date(19, 10, 10))
        XCTAssertEqual(when(["when": "at", "day": "weekday", "weekday": "saturday", "week": "coming", "hour": "none"])?.date, date(17))
        XCTAssertEqual(when(["when": "at", "day": "weekday", "weekday": "saturday", "week": "following week", "hour": "none"])?.date, date(24))
        XCTAssertEqual(when(["when": "at", "day": "weekday", "weekday": "thursday", "week": "following week", "hour": "none"])?.date, date(22))
        // Friday said on a Friday: today while its time is ahead, else next week.
        XCTAssertEqual(when(["when": "at", "day": "weekday", "weekday": "friday", "week": "coming", "hour": "18", "minute": "0"])?.date, date(16, 10, 18))
        XCTAssertEqual(when(["when": "at", "day": "weekday", "weekday": "friday", "week": "coming", "hour": "9", "minute": "0"])?.date, date(23, 10, 9))
    }

    func testDates() {
        XCTAssertEqual(when(["when": "at", "day": "date", "day_of_month": "12", "month": "march", "hour": "none"])?.date, date(12, 3, year: 2027))
        XCTAssertEqual(when(["when": "at", "day": "date", "day_of_month": "20", "month": "none", "hour": "none"])?.date, date(20))
        XCTAssertEqual(when(["when": "at", "day": "date", "day_of_month": "5", "month": "none", "hour": "none"])?.date, date(5, 11), "past this month: next month")
        XCTAssertNil(when(["when": "at", "day": "date", "day_of_month": "30", "month": "february", "hour": "none"]), "no such day")
    }

    /// "dans une heure trente": one of the lengths, from now.
    func testADelay() {
        let read = when(["when": "in", "delay": "1 h 30"])
        XCTAssertEqual(read?.date, now.addingTimeInterval(5_400))
        XCTAssertEqual(read?.hasTime, true)
        XCTAssertNil(when(["when": "in", "delay": "none"]))
        let nothing = when(["when": "none"])
        XCTAssertNotNil(nothing)
        XCTAssertNil(nothing?.date)
    }

    func testTheLeastSurePartUsed() {
        var parts = answers(["when": "at", "day": "tomorrow", "hour": "9", "minute": "0", "weekday": "monday"])
        parts["minute"] = AskValues.Answer(choice: "0", confidence: 0.4)
        parts["weekday"] = AskValues.Answer(choice: "monday", confidence: 0.1)
        XCTAssertEqual(when(["when": "at"]) == nil, true)
        XCTAssertEqual(AskValues.when(parts, now: now, calendar: calendar)?.confidence, 0.4, "the unused weekday does not count")
    }

    func testHowOften() {
        XCTAssertEqual(AskValues.recurrence(answers(["repeat": "every weekday"]), weekdayOf: nil).recurrence?.spoken, "every weekday")
        XCTAssertEqual(AskValues.recurrence(answers(["repeat": "every week"]), weekdayOf: date(19), calendar: calendar).recurrence?.spoken, "every Monday")
        XCTAssertNil(AskValues.recurrence(answers(["repeat": "none"]), weekdayOf: nil).recurrence)
    }

    func testEventEnds() {
        let start = date(17, 10, 14)
        XCTAssertEqual(AskValues.eventEnd(answers(["ends": "time", "end_hour": "15", "end_minute": "30"]), start: start, calendar: calendar).end, date(17, 10, 15, 30))
        XCTAssertEqual(AskValues.eventEnd(answers(["ends": "length", "lasts": "2 h"]), start: start, calendar: calendar).end, date(17, 10, 16))
        let unsaid = AskValues.eventEnd(answers(["ends": "none"]), start: start, calendar: calendar)
        XCTAssertEqual(unsaid.end, date(17, 10, 15))
        XCTAssertNil(unsaid.confidence)
        XCTAssertEqual(AskValues.alertMinutes(answers(["alert": "15"])), 15)
        XCTAssertNil(AskValues.alertMinutes(answers(["alert": "none"])))
    }

    func testTheirNames() {
        let question = AskValues.namedQuestion(name: "list", instructions: "", names: ["Courses", "Travail"])
        XCTAssertEqual(question.options.map(\.value), ["list 0", "list 1", "none"])
        XCTAssertEqual(AskValues.named(answers(["list": "list 1"]), "list", names: ["Courses", "Travail"])?.name, "Travail")
        XCTAssertNil(AskValues.named(answers(["list": "none"]), "list", names: ["Courses"]))
        XCTAssertEqual(AskValues.priority(answers(["priority": "high"])), 1)
    }

    /// Every question within a Choice's 255 options, every name once.
    func testQuestionsFit() {
        let words = AskValues.words(of: String(repeating: "mot ", count: 80))
        let questions = AskValues.reminderQuestions(words: words, lists: ["A"])
            + AskValues.eventQuestions(words: words, calendars: ["B"])
        for question in questions {
            XCTAssertLessThanOrEqual(question.options.count, 255, question.name)
        }
        XCTAssertEqual(Set(AskValues.reminderQuestions(words: words, lists: []).map(\.name)).count,
                       AskValues.reminderQuestions(words: words, lists: []).count)
    }
}
