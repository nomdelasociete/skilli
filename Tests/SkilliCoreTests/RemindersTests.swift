import XCTest
@testable import SkilliCore

final class RemindersTests: XCTestCase {
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

    private func read(_ text: String) -> ReminderRequest? {
        ReminderRequest.parse(text, now: now, calendar: calendar, lists: ["Reminders", "Courses", "Perso"])
    }

    func testQuickAdd() {
        XCTAssertEqual(read("rappelle-moi d'appeler Paul demain à 9h"), ReminderRequest(title: "Appeler Paul", due: at(13, 9), hasTime: true))
        XCTAssertEqual(read("remind me to call Paul tomorrow at 9am !!"), ReminderRequest(title: "Call Paul", due: at(13, 9), hasTime: true, priority: 5))
        XCTAssertEqual(read("todo acheter du pain #courses"), ReminderRequest(title: "Acheter du pain", list: "Courses"))
        XCTAssertEqual(read("rappel payer le loyer tous les mois le 5 !!!"),
                       ReminderRequest(title: "Payer le loyer", due: calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!, priority: 1,
                                       recurrence: SpokenRecurrence(.monthly)))
        XCTAssertEqual(read("rappelle-moi de lire cet article ce soir")?.withPageInFront, true)
        XCTAssertEqual(read("rappelle-moi de lire cet article ce soir")?.title, "Lire cet article")
        XCTAssertEqual(read("ajoute à mes rappels : rendre les clés")?.title, "Rendre les clés")
        XCTAssertEqual(read("ajoute à mes rappels rendre les clés vendredi"), ReminderRequest(title: "Rendre les clés", due: at(16)))
        XCTAssertEqual(read("add a reminder to renew the passport urgent"), ReminderRequest(title: "Renew the passport", priority: 1))
        XCTAssertEqual(read("rappel facture https://example.com/f/12 demain")?.url, "https://example.com/f/12")
        XCTAssertEqual(read("n'oublie pas d'arroser les plantes")?.title, "Arroser les plantes")
        XCTAssertNil(read("appeler Paul demain"))
        XCTAssertNil(read("rappelle-moi"))
    }

    func testPlacesAndMail() {
        XCTAssertEqual(read("rappelle-moi d'acheter du pain en partant du bureau"),
                       ReminderRequest(title: "Acheter du pain", place: ReminderPlace(name: "bureau", arriving: false)))
        XCTAssertEqual(read("rappelle-moi de sortir le chien en arrivant à la maison")?.place, ReminderPlace(name: "maison", arriving: true))
        XCTAssertEqual(read("rappelle-moi de sortir le chien en arrivant à la maison")?.title, "Sortir le chien")
        XCTAssertEqual(read("remind me to call mom when I get home"), ReminderRequest(title: "Call mom", place: ReminderPlace(name: "home", arriving: true)))
        XCTAssertEqual(read("remind me to buy milk when I leave the office")?.place, ReminderPlace(name: "office", arriving: false))
        XCTAssertEqual(read("rappelle-moi de répondre à ce mail demain")?.withMailInFront, true)
        XCTAssertEqual(read("rappelle-moi de répondre à ce mail demain")?.withPageInFront, false)
        XCTAssertEqual(read("rappelle-moi de répondre à ce mail demain")?.due, at(13))
        XCTAssertEqual(Reminders.mailLink(messageID: "<CA+abc123@mail.gmail.com>")?.absoluteString, "message://%3CCA%2Babc123@mail.gmail.com%3E")
        let items = [ReminderItem(id: "1", title: "Late", due: at(11)), ReminderItem(id: "2", title: "Today", due: at(12, 18), hasTime: true),
                     ReminderItem(id: "3", title: "Tomorrow", due: at(13)), ReminderItem(id: "4", title: "Done", due: at(12), isCompleted: true)]
        XCTAssertEqual(Reminders.dueToday(items, now: now, calendar: calendar).map(\.title), ["Late", "Today"])
    }

    func testSavedPlaces() {
        let places = [SavedPlace(name: "Maison", address: "1 rue A", latitude: 48.8, longitude: 2.3),
                      SavedPlace(name: "Bureau Nimbus", address: "2 rue B", latitude: 48.9, longitude: 2.4)]
        XCTAssertEqual(SavedPlace.match("maison", in: places)?.name, "Maison")
        XCTAssertEqual(SavedPlace.match("home", in: places)?.name, "Maison")
        XCTAssertEqual(SavedPlace.match("bureau", in: places)?.name, "Bureau Nimbus")
        XCTAssertNil(SavedPlace.match("gym", in: places))
    }

    func testListRequests() {
        XCTAssertEqual(RemindersRequest.parse("mes rappels"), .today)
        XCTAssertEqual(RemindersRequest.parse("qu'est-ce que j'ai à faire aujourd'hui ?"), .today)
        XCTAssertEqual(RemindersRequest.parse("my reminders"), .today)
        XCTAssertEqual(RemindersRequest.parse("tous mes rappels"), .all)
        XCTAssertEqual(RemindersRequest.parse("qu'est-ce qui est en retard"), .overdue)
        XCTAssertNil(RemindersRequest.parse("ajoute à mes rappels acheter du pain"))
        XCTAssertNil(RemindersRequest.parse("traduis mes rappels en anglais"))
    }

    func testMovedKeepsItsTime() {
        // Friday the 16th, 15:00.
        let friday = at(16, 15)
        let timed = ReminderItem(id: "1", title: "Call", due: at(14, 9, 30), hasTime: true)
        let day = ReminderItem(id: "2", title: "Pay", due: at(14), hasTime: false)
        let none = ReminderItem(id: "3", title: "Read")
        XCTAssertEqual(Reminders.moved(timed, nextWeek: false, now: friday, calendar: calendar), at(17, 9, 30))
        XCTAssertEqual(Reminders.moved(day, nextWeek: false, now: friday, calendar: calendar), at(17))
        XCTAssertEqual(Reminders.moved(none, nextWeek: false, now: friday, calendar: calendar), at(17))
        // Next Week: its Monday, the 19th; from a Monday, the one after.
        XCTAssertEqual(Reminders.moved(timed, nextWeek: true, now: friday, calendar: calendar), at(19, 9, 30))
        XCTAssertEqual(Reminders.moved(day, nextWeek: true, now: at(19, 8), calendar: calendar), at(26))
    }

    func testSections() {
        let items = [
            ReminderItem(id: "1", title: "Late", due: at(11), hasTime: false),
            ReminderItem(id: "2", title: "Lunch", due: at(12, 12), hasTime: true),
            ReminderItem(id: "3", title: "Call", due: at(12, 16), hasTime: true, priority: 1),
            ReminderItem(id: "4", title: "Dinner", due: at(12, 20), hasTime: true),
            ReminderItem(id: "5", title: "Today", due: at(12), hasTime: false),
            ReminderItem(id: "6", title: "Tomorrow", due: at(13, 9), hasTime: true),
            ReminderItem(id: "7", title: "Friday", due: at(16), hasTime: false),
            ReminderItem(id: "8", title: "Thursday", due: at(15), hasTime: false),
            ReminderItem(id: "9", title: "Someday", priority: 5),
            ReminderItem(id: "10", title: "Done", isCompleted: true, completedAt: at(12, 10))
        ]
        let sections = Reminders.sections(items, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Overdue", "Today", "This Afternoon", "Tonight", "Tomorrow", "Thu 15 Oct", "Fri 16 Oct", "No Date", "Completed"])
        XCTAssertEqual(sections[0].items.map(\.title), ["Late", "Lunch"])
        XCTAssertEqual(Reminders.when(items[5], now: now, calendar: calendar), "Tomorrow 09:00")
        XCTAssertEqual(Reminders.when(items[0], now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(items[2].marks, "!!!")
        XCTAssertEqual(Reminders.markdown([items[2], items[8]], now: now, calendar: calendar),
                       "**This Afternoon**\n- !!! Call · Today 16:00 · Reminders\n\n**No Date**\n- !! Someday · Reminders")
    }

    /// No place saved under "maison": the card's Home address, as Apple's
    /// Reminders reads it; "bureau" its Work one; another name, none.
    func testHomeAndWorkFallBackToTheCard() {
        XCTAssertEqual(SavedPlace.cardAddress(for: "maison"), .home)
        XCTAssertEqual(SavedPlace.cardAddress(for: "Chez moi"), .home)
        XCTAssertEqual(SavedPlace.cardAddress(for: "home"), .home)
        XCTAssertEqual(SavedPlace.cardAddress(for: "bureau"), .work)
        XCTAssertEqual(SavedPlace.cardAddress(for: "Travail"), .work)
        XCTAssertEqual(SavedPlace.cardAddress(for: "office"), .work)
        XCTAssertNil(SavedPlace.cardAddress(for: "gymnase"))
    }
}
