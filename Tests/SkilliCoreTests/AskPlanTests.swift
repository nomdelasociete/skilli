import SkilliCore
import XCTest

final class AskPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    /// Friday 16 October 2026, 14:00.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 14))! }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func plan(_ request: String, _ pairs: [String: String], sure: Double = 0.95, lists: [String] = ["Courses", "Travail"],
                      calendars: [String] = ["Perso", "Pro"]) -> AskValues.Plan {
        AskValues.plan(pairs.mapValues { AskValues.Answer(choice: $0, confidence: sure) }, words: AskValues.words(of: request),
                       lists: lists, calendars: calendars, now: now, calendar: calendar)
    }

    /// "rappelle-moi d'appeler Paul demain à 9h": its words, its day and time.
    func testAReminder() {
        let read = plan("rappelle-moi d'appeler Paul demain à 9h",
                        ["plan": "remind", "title_start": "word 2", "title_end": "word 3", "when": "at", "day": "tomorrow", "hour": "9", "minute": "0",
                         "repeat": "none", "priority": "none", "place_when": "none", "with": "none", "list": "none"])
        XCTAssertEqual(read, .reminder(ReminderRequest(title: "Appeler Paul", due: date(17, 9), hasTime: true), sure: 0.95))
    }

    /// "dans une heure trente": one of the lengths from now, never an hour.
    func testAReminderInALength() {
        guard case .reminder(let request, _) = plan("rappelle-moi dans une heure trente de sortir le linge",
                                                    ["plan": "remind", "title_start": "word 6", "title_end": "word 8", "when": "in", "delay": "1 h 30"]) else {
            return XCTFail("not a reminder")
        }
        XCTAssertEqual(request.title, "Sortir le linge")
        XCTAssertEqual(request.due, now.addingTimeInterval(5_400))
    }

    func testAReminderOnAListAtAPlaceEveryMonth() {
        guard case .reminder(let request, _) = plan("n'oublie pas de payer le loyer le 5 tous les mois #Travail",
                                                    ["plan": "remind", "title_start": "word 4", "title_end": "word 6", "when": "at", "day": "date",
                                                     "day_of_month": "5", "month": "none", "hour": "none", "repeat": "every month", "list": "list 1",
                                                     "priority": "high"]) else {
            return XCTFail("not a reminder")
        }
        XCTAssertEqual(request.title, "Payer le loyer")
        XCTAssertEqual(request.due, calendar.date(from: DateComponents(year: 2026, month: 11, day: 5)))
        XCTAssertEqual(request.recurrence, SpokenRecurrence(.monthly))
        XCTAssertEqual(request.list, "Travail")
        XCTAssertEqual(request.priority, 1)
        guard case .reminder(let there, _) = plan("rappelle-moi d'appeler Paul en arrivant au bureau",
                                                  ["plan": "remind", "title_start": "word 2", "title_end": "word 3", "when": "none",
                                                   "place_when": "arriving", "place": "phrase \(AskValues.phrases(of: AskValues.words(of: "rappelle-moi d'appeler Paul en arrivant au bureau"), longest: 4).firstIndex(of: "bureau") ?? -1)"]) else {
            return XCTFail("not a reminder")
        }
        XCTAssertEqual(there.place, ReminderPlace(name: "bureau", arriving: true))
        XCTAssertNil(there.due)
    }

    func testAReminderNeedsWhatItSays() {
        guard case .missing = plan("rappelle-moi demain", ["plan": "remind", "title_start": "none", "title_end": "none", "when": "at", "day": "tomorrow"]) else {
            return XCTFail("a reminder without words")
        }
    }

    /// "bloque 2h demain matin pour écrire": from 9:00 for two hours.
    func testAnEvent() {
        let read = plan("bloque 2h demain matin pour écrire",
                        ["plan": "event", "title_start": "word 5", "title_end": "word 5", "when": "at", "day": "tomorrow", "hour": "none",
                         "part_of_day": "morning", "ends": "length", "lasts": "2 h", "repeat": "none", "alert": "none", "calendar": "none"])
        XCTAssertEqual(read, .event(EventRequest(title: "Écrire", start: date(17, 9), end: date(17, 11)), sure: 0.95))
        guard case .event(let meeting, _) = plan("réunion de 14h à 15h30 vendredi #Pro",
                                                 ["plan": "event", "title_start": "word 0", "title_end": "word 0", "when": "at", "day": "weekday",
                                                  "weekday": "friday", "week": "coming", "hour": "14", "minute": "0", "ends": "time", "end_hour": "15",
                                                  "end_minute": "30", "calendar": "calendar 1", "alert": "10"]) else {
            return XCTFail("not an event")
        }
        XCTAssertEqual(meeting.start, date(23, 14))
        XCTAssertEqual(meeting.end, date(23, 15, 30))
        XCTAssertEqual(meeting.calendar, "Pro")
        XCTAssertEqual(meeting.alertMinutes, 10)
        guard case .event(let allDay, _) = plan("ajoute anniversaire de Léa le 20", ["plan": "event", "title_start": "word 1", "title_end": "word 3",
                                                                                     "when": "at", "day": "date", "day_of_month": "20", "hour": "none"]) else {
            return XCTFail("not an event")
        }
        XCTAssertTrue(allDay.isAllDay)
        XCTAssertEqual(allDay.title, "Anniversaire de Léa")
        guard case .missing = plan("crée un rdv avec Paul", ["plan": "event", "when": "none"]) else { return XCTFail("an event needs a day") }
    }

    func testReadingTheCalendarAndTheReminders() {
        XCTAssertEqual(plan("qu'est-ce que j'ai demain", ["plan": "day", "when": "at", "day": "tomorrow", "hour": "none"]), .agenda(.day(offset: 1)))
        XCTAssertEqual(plan("mon agenda", ["plan": "day", "when": "none"]), .agenda(.day(offset: 0)))
        XCTAssertEqual(plan("rejoins la réunion", ["plan": "join"]), .agenda(.next(join: true)))
        XCTAssertEqual(plan("suis-je libre jeudi après-midi", ["plan": "free", "when": "at", "day": "weekday", "weekday": "thursday", "week": "coming",
                                                               "hour": "none", "part_of_day": "afternoon"]),
                       .agenda(.free(from: date(22, 12), to: date(22, 18))))
        XCTAssertEqual(plan("am I free tomorrow at 3pm", ["plan": "free", "when": "at", "day": "tomorrow", "hour": "15", "minute": "0"]),
                       .agenda(.free(from: date(17, 15), to: date(17, 16))))
        XCTAssertEqual(plan("mes rappels", ["plan": "todo"]), .reminders(.today))
        XCTAssertEqual(plan("mes rappels en retard", ["plan": "overdue"]), .reminders(.overdue))
    }

    func testTheLeastSurePartUsed() {
        var answers = ["plan": "remind", "title_start": "word 2", "title_end": "word 3", "when": "at", "day": "tomorrow", "hour": "9", "minute": "0"]
            .mapValues { AskValues.Answer(choice: $0, confidence: 0.9) }
        answers["hour"] = AskValues.Answer(choice: "9", confidence: 0.3)
        answers["list"] = AskValues.Answer(choice: "none", confidence: 0.1)
        guard case .reminder(_, let sure) = AskValues.plan(answers, words: AskValues.words(of: "rappelle-moi d'appeler Paul demain à 9h"),
                                                          lists: [], calendars: [], now: now, calendar: calendar) else {
            return XCTFail("not a reminder")
        }
        XCTAssertEqual(sure, 0.3, "the hour, not the list none")
        // What it says does not count; an unsure extra is left out.
        answers["hour"] = AskValues.Answer(choice: "9", confidence: 0.9)
        answers["title_end"] = AskValues.Answer(choice: "word 3", confidence: 0.2)
        answers["list"] = AskValues.Answer(choice: "list 0", confidence: 0.3)
        guard case .reminder(let request, let sureNow) = AskValues.plan(answers, words: AskValues.words(of: "rappelle-moi d'appeler Paul demain à 9h"),
                                                                        lists: ["Courses"], calendars: [], now: now, calendar: calendar) else {
            return XCTFail("not a reminder")
        }
        XCTAssertEqual(sureNow, 0.9)
        XCTAssertNil(request.list, "a list the model is unsure was named")
    }

    func testEveryQuestionOnceAndWithinAChoice() {
        let questions = AskValues.planQuestions(words: AskValues.words(of: String(repeating: "mot ", count: 60)), lists: ["A"], calendars: ["B"])
        XCTAssertEqual(Set(questions.map(\.name)).count, questions.count)
        XCTAssertTrue(questions.allSatisfy { $0.options.count <= 255 })
    }
}
