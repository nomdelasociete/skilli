import XCTest
@testable import SkilliCore

final class SpokenWhenTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Monday 12 October 2026, 14:00 in Paris.
    private var now: Date { at(12, 14) }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func read(_ text: String) -> SpokenWhen {
        SpokenWhen.parse(text, now: now, calendar: calendar)
    }

    func testDaysAndTimes() {
        XCTAssertEqual(read("appeler Paul demain à 9h"), SpokenWhen(date: at(13, 9), hasTime: true, rest: "appeler Paul"))
        XCTAssertEqual(read("call Paul tomorrow at 9am"), SpokenWhen(date: at(13, 9), hasTime: true, rest: "call Paul"))
        XCTAssertEqual(read("jeudi prochain 14h30 dentiste"), SpokenWhen(date: at(15, 14, 30), hasTime: true, rest: "dentiste"))
        XCTAssertEqual(read("dentiste jeudi"), SpokenWhen(date: at(15), hasTime: false, rest: "dentiste"))
        // Monday today: "lundi" is next Monday.
        XCTAssertEqual(read("lundi").date, at(19))
        XCTAssertEqual(read("next friday").date, at(16))
        XCTAssertEqual(read("après-demain").date, at(14))
        XCTAssertEqual(read("la semaine prochaine bilan"), SpokenWhen(date: at(19), hasTime: false, rest: "bilan"))
        XCTAssertEqual(read("le 15 oct facture"), SpokenWhen(date: at(15), hasTime: false, rest: "facture"))
        XCTAssertEqual(read("le 3").date, at(3, month: 11))
        XCTAssertEqual(read("october 20").date, at(20))
        XCTAssertEqual(read("15/10").date, at(15))
        XCTAssertEqual(read("1/1").date, at(1, month: 1, year: 2027))
        XCTAssertEqual(read("le 2 mars 2027").date, at(2, month: 3, year: 2027))
    }

    func testRelativeAndPartsOfDay() {
        XCTAssertEqual(read("dans 2 heures sortir le linge"), SpokenWhen(date: at(12, 16), hasTime: true, rest: "sortir le linge"))
        XCTAssertEqual(read("in 30 min").date, at(12, 14, 30))
        XCTAssertEqual(read("dans 10min").date, at(12, 14, 10))
        XCTAssertEqual(read("in 3 days"), SpokenWhen(date: at(15), hasTime: false, rest: ""))
        XCTAssertEqual(read("dans une semaine").date, at(19))
        XCTAssertEqual(read("ce soir").date, at(12, 19))
        XCTAssertEqual(read("ce soir à 8h").date, at(12, 20))
        XCTAssertEqual(read("demain matin").date, at(13, 9))
        XCTAssertEqual(read("tomorrow afternoon").date, at(13, 14))
        XCTAssertEqual(read("à midi").date, at(13, 12))
    }

    func testTimesAlone() {
        // Gone today: tomorrow.
        XCTAssertEqual(read("à 9h").date, at(13, 9))
        // A bare hour after "à" / "at": the afternoon when the morning is gone.
        XCTAssertEqual(read("at 5").date, at(12, 17))
        XCTAssertEqual(read("à 5").date, at(12, 17))
        XCTAssertEqual(read("à 5h").date, at(13, 5))
        XCTAssertEqual(read("vers 16h30").date, at(12, 16, 30))
        XCTAssertEqual(read("at 9:30pm").date, at(12, 21, 30))
    }

    func testSpans() {
        XCTAssertEqual(read("réunion de 14h à 15h demain"), SpokenWhen(date: at(13, 14), hasTime: true, end: at(13, 15), rest: "réunion"))
        XCTAssertEqual(read("point avec Paul pendant 30 min demain 10h"),
                       SpokenWhen(date: at(13, 10), hasTime: true, end: at(13, 10, 30), rest: "point avec Paul"))
        XCTAssertEqual(read("rendez-vous 16h-17h"), SpokenWhen(date: at(12, 16), hasTime: true, end: at(12, 17), rest: "rendez-vous"))
        XCTAssertEqual(read("standup from 9am to 9:15am tomorrow").end, at(13, 9, 15))
    }

    func testRecurrences() {
        XCTAssertEqual(read("sortir les poubelles tous les lundis"),
                       SpokenWhen(date: at(12), hasTime: false, recurrence: SpokenRecurrence(.weekly, weekdays: [2]), rest: "sortir les poubelles"))
        XCTAssertEqual(read("standup every 2 weeks on friday"),
                       SpokenWhen(date: at(16), hasTime: false, recurrence: SpokenRecurrence(.weekly, interval: 2), rest: "standup"))
        XCTAssertEqual(read("payer le loyer tous les mois le 5"),
                       SpokenWhen(date: at(5, month: 11), hasTime: false, recurrence: SpokenRecurrence(.monthly), rest: "payer le loyer"))
        XCTAssertEqual(read("méditer chaque jour à 7h"),
                       SpokenWhen(date: at(13, 7), hasTime: true, recurrence: SpokenRecurrence(.daily), rest: "méditer"))
        XCTAssertEqual(read("en semaine à 8h vitamines").recurrence, SpokenRecurrence(.weekly, weekdays: [2, 3, 4, 5, 6]))
        XCTAssertEqual(read("bilan daily").recurrence, SpokenRecurrence(.daily))
        XCTAssertEqual(SpokenRecurrence(.weekly, weekdays: [2, 3, 4, 5, 6]).spoken, "every weekday")
        XCTAssertEqual(SpokenRecurrence(.weekly, interval: 2, weekdays: [6]).spoken, "every 2 weeks on Friday")
        XCTAssertEqual(SpokenRecurrence(.monthly).spoken, "every month")
    }

    func testNothingSaid() {
        XCTAssertEqual(read("appeler mon frère"), SpokenWhen(date: nil, hasTime: false, rest: "appeler mon frère"))
        XCTAssertNil(read("buy a 2 liter bottle").date)
        XCTAssertNil(read("acheter 2 pains").date)
        XCTAssertEqual(read("appeler l'école demain").rest, "appeler l'école")
        XCTAssertEqual(read("d'appeler Paul").rest, "d'appeler Paul")
    }
}
