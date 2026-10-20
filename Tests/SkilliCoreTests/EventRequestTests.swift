import XCTest
@testable import SkilliCore

final class EventRequestTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Monday 12 October 2026, 14:00 in Paris.
    private var now: Date { at(12, 14) }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func read(_ text: String, nounFirst: Bool = false) -> EventRequest? {
        EventRequest.parse(text, now: now, calendar: calendar, calendars: ["Work", "Perso", "Famille"], nounFirst: nounFirst)
    }

    func testEvents() {
        XCTAssertEqual(read("rdv demain 14h point budget avec Paul"),
                       EventRequest(title: "Point budget avec Paul", start: at(13, 14), end: at(13, 15)))
        XCTAssertEqual(read("ajoute à mon agenda dentiste jeudi 9h30 #perso"),
                       EventRequest(title: "Dentiste", start: at(15, 9, 30), end: at(15, 10, 30), calendar: "Perso"))
        XCTAssertEqual(read("crée un rendez-vous avec Paul vendredi de 14h à 15h30"),
                       EventRequest(title: "Avec Paul", start: at(16, 14), end: at(16, 15, 30)))
        XCTAssertEqual(read("schedule a call with Marie tomorrow at 3pm for 30 min"),
                       EventRequest(title: "Call with Marie", start: at(13, 15), end: at(13, 15, 30)))
        // A day alone: all day.
        XCTAssertEqual(read("rdv anniversaire de Léa le 20 oct"),
                       EventRequest(title: "Anniversaire de Léa", start: at(20), end: at(21), isAllDay: true))
        // Notes after a colon, a link, an alert.
        XCTAssertEqual(read("rdv vendredi 10h revue : préparer les chiffres https://meet.google.com/abc-defg-hij rappel 10 min avant"),
                       EventRequest(title: "Revue", start: at(16, 10), end: at(16, 11), notes: "préparer les chiffres https://meet.google.com/abc-defg-hij rappel 10 min avant"))
        XCTAssertEqual(read("rdv vendredi 10h revue https://meet.google.com/abc-defg-hij alerte 1h avant"),
                       EventRequest(title: "Revue", start: at(16, 10), end: at(16, 11), url: "https://meet.google.com/abc-defg-hij", alertMinutes: 60))
        // "14:30" is a time, not notes.
        XCTAssertEqual(read("rdv demain 14:30 banque")?.start, at(13, 14, 30))
        XCTAssertEqual(read("rdv demain 14:30 banque")?.notes, "")
        // Recurring.
        XCTAssertEqual(read("schedule standup every weekday at 9:30 for 15 min")?.recurrence, SpokenRecurrence(.weekly, weekdays: [2, 3, 4, 5, 6]))
        XCTAssertEqual(read("schedule standup every weekday at 9:30 for 15 min")?.end, at(13, 9, 45))
    }

    func testBlocks() {
        XCTAssertEqual(read("bloque 2h demain matin pour écrire"), EventRequest(title: "Écrire", start: at(13, 9), end: at(13, 11)))
        XCTAssertEqual(read("block 1 hour tomorrow at 4pm"), EventRequest(title: "Busy", start: at(13, 16), end: at(13, 17)))
        XCTAssertEqual(read("bloque jeudi après-midi")?.isAllDay, false)
    }

    func testNotEvents() {
        XCTAssertNil(read("appeler Paul demain"))
        XCTAssertNil(read("rdv avec Paul"))
        XCTAssertNil(read("réunion budget demain 14h"))
        XCTAssertEqual(read("réunion budget demain 14h", nounFirst: true), EventRequest(title: "Réunion budget", start: at(13, 14), end: at(13, 15)))
    }
}
