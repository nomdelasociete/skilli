import XCTest
@testable import SkilliCore

final class AgendaTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Monday 12 October 2026, 14:00 in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 14, minute: 0))!
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// A time on Monday 12 October.
    private func today(_ hour: Int, _ minute: Int = 0) -> Date {
        at(12, hour, minute)
    }

    func testMeetingLinksFound() {
        let meet = MeetingLink.find(in: ["", "Salle 3", "Join with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial: +33 1 23"])
        XCTAssertEqual(meet?.service, "Google Meet")
        XCTAssertEqual(meet?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
        // The event's URL comes first.
        XCTAssertEqual(MeetingLink.find(in: ["https://acme.zoom.us/j/123456789?pwd=XyZ", "", "https://meet.google.com/aaa-bbbb-ccc"])?.service, "Zoom")
        XCTAssertEqual(MeetingLink.find(in: ["", "", "Rejoindre : https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x"])?.service,
                       "Teams")
        XCTAssertEqual(MeetingLink.find(in: ["", "https://meet.jit.si/skilli-weekly", ""])?.service, "Jitsi")
        XCTAssertEqual(MeetingLink.find(in: ["", "", "https://app.slack.com/huddle/T123/C456"])?.service, "Slack Huddle")
        XCTAssertEqual(MeetingLink.find(in: ["", "", "zoommtg://zoom.us/join?confno=1"])?.service, "Zoom")
        // Not calls: a company site, Zoom's home page, a plain Google page.
        XCTAssertNil(MeetingLink.find(in: ["https://skil.li", "https://zoom.us/pricing", "https://www.google.com/search?q=meet"]))
        XCTAssertNil(MeetingLink.find(in: ["", "Salle Everest", "Pas de lien"]))
    }

    func testAppLinks() {
        let zoom = MeetingLink.find(in: ["https://acme.zoom.us/j/123456789?pwd=XyZ"])
        XCTAssertEqual(zoom?.appURL?.absoluteString, "zoommtg://acme.zoom.us/join?action=join&confno=123456789&pwd=XyZ")
        let teams = MeetingLink.find(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x"])
        XCTAssertEqual(teams?.appURL?.absoluteString, "msteams:/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x")
        XCTAssertNil(MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.appURL)
    }

    func testNextMeeting() {
        let standup = AgendaEvent(id: "1", title: "Standup", start: today(13, 50), end: today(14, 5))
        let focus = AgendaEvent(id: "2", title: "Focus", start: today(9, 0), end: today(18, 0))
        let review = AgendaEvent(id: "3", title: "Review", start: today(14, 30), end: today(15, 0))
        let holiday = AgendaEvent(id: "4", title: "Holiday", start: today(12, 0), end: today(13, 0), isAllDay: true)
        let declined = AgendaEvent(id: "5", title: "Declined", start: today(14, 10), end: today(14, 20), declined: true)
        // Ten minutes late for the standup: still the one to join.
        XCTAssertEqual(Agenda.next([focus, review, holiday, declined, standup], now: now)?.title, "Standup")
        // Once it ended, the review; the long focus block never first.
        XCTAssertEqual(Agenda.next([focus, review, holiday, declined], now: now)?.title, "Review")
        XCTAssertEqual(Agenda.next([focus], now: now)?.title, "Focus")
        XCTAssertNil(Agenda.next([holiday, declined], now: now))
        XCTAssertTrue(Agenda.isNear(review, now: today(14, 22)))
        XCTAssertFalse(Agenda.isNear(review, now: today(14, 15)))
        XCTAssertTrue(Agenda.isNear(review, now: today(14, 38)))
        XCTAssertFalse(Agenda.isNear(review, now: today(14, 45)))
    }

    func testWhen() {
        XCTAssertEqual(Agenda.when(AgendaEvent(id: "1", title: "A", start: today(13, 50), end: today(14, 30)), now: now, calendar: calendar),
                       "Now, until 14:30")
        XCTAssertEqual(Agenda.when(AgendaEvent(id: "1", title: "A", start: today(14, 12), end: today(15, 0)), now: now, calendar: calendar), "In 12 min")
        XCTAssertEqual(Agenda.when(AgendaEvent(id: "1", title: "A", start: today(15, 5), end: today(16, 0)), now: now, calendar: calendar), "In 1 h 05")
        XCTAssertEqual(Agenda.when(AgendaEvent(id: "1", title: "A", start: today(18, 0), end: today(19, 0)), now: now, calendar: calendar), "Today 18:00")
        XCTAssertEqual(Agenda.when(AgendaEvent(id: "1", title: "A", start: at(13, 9), end: at(13, 10)), now: now, calendar: calendar), "Tomorrow 09:00")
        XCTAssertEqual(Agenda.when(AgendaEvent(id: "1", title: "A", start: at(15, 0), end: at(16, 0), isAllDay: true), now: now, calendar: calendar),
                       "Thu 15 Oct, all day")
        XCTAssertEqual(Agenda.span(AgendaEvent(id: "1", title: "A", start: at(15, 9), end: at(15, 9, 30)), calendar: calendar), "09:00–09:30")
    }

    func testSections() {
        let events = [
            AgendaEvent(id: "1", title: "Review", start: at(12, 15), end: at(12, 16)),
            AgendaEvent(id: "2", title: "Lunch", start: at(13, 12), end: at(13, 13)),
            AgendaEvent(id: "3", title: "Friday", start: at(16, 9), end: at(16, 10)),
            AgendaEvent(id: "4", title: "Next week", start: at(20, 9), end: at(20, 10)),
            AgendaEvent(id: "5", title: "Later", start: at(29, 9), end: at(29, 10)),
            AgendaEvent(id: "6", title: "November", start: calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!,
                        end: calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10))!),
            AgendaEvent(id: "7", title: "Over", start: at(12, 9), end: at(12, 10))
        ]
        let sections = Agenda.sections(events, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Today", "Tomorrow", "Fri 16 Oct", "Next Week", "Later This Month", "November 2026"])
        XCTAssertEqual(sections.flatMap(\.events).map(\.title), ["Review", "Lunch", "Friday", "Next week", "Later", "November"])
    }

    func testMarkdownAndAvailability() {
        let event = AgendaEvent(id: "1", title: "Weekly sync", start: today(14, 30), end: today(15, 0), calendar: "Work", location: "Salle 3",
                                notes: "https://meet.google.com/abc-defg-hij", attendees: [.init(name: "Paul", email: "paul@x.fr"), .init(name: "Marie", email: nil)])
        XCTAssertEqual(Agenda.details(event, now: now, calendar: calendar),
                       "**Weekly sync**\nToday, 14:30–15:00 · In 30 min\n- Google Meet\n- Salle 3\n- Calendar: Work\n- With Paul, Marie")
        let tomorrow = [AgendaEvent(id: "2", title: "Standup", start: at(13, 9), end: at(13, 9, 15), notes: "https://meet.google.com/x-y-z"),
                        AgendaEvent(id: "3", title: "Holiday", start: at(13, 0), end: at(14, 0), isAllDay: true)]
        XCTAssertEqual(Agenda.dayMarkdown(tomorrow, day: at(13, 0), now: now, calendar: calendar),
                       "**Tomorrow, Tue 13 Oct**\n- **All day** Holiday\n- **09:00–09:15** Standup · Google Meet")
        XCTAssertEqual(Agenda.dayMarkdown([], day: at(14, 0), now: now, calendar: calendar), "**Wed 14 Oct**\nNothing planned.")
        // From 14:07 today: 23 minutes before the review is too short to
        // offer; after it, the afternoon. Tomorrow after the morning.
        let busy = [AgendaEvent(id: "4", title: "Review", start: at(12, 14, 30), end: at(12, 15, 0)),
                    AgendaEvent(id: "5", title: "Morning", start: at(13, 9), end: at(13, 12))]
        let free = Agenda.availability(busy, from: at(12, 14, 7), days: 2, calendar: calendar)
        XCTAssertEqual(free, "Mon 12 Oct: 15:00–18:00\nTue 13 Oct: 12:00–18:00")
        let earlier = Agenda.availability(busy, from: at(12, 13, 50), days: 1, calendar: calendar)
        XCTAssertEqual(earlier, "Mon 12 Oct: 14:00–14:30, 15:00–18:00")
    }

    func testFreeAnswer() {
        let events = [AgendaEvent(id: "1", title: "Weekly sync", start: at(15, 15), end: at(15, 15, 30)),
                      AgendaEvent(id: "2", title: "Holiday", start: at(15, 0), end: at(16, 0), isAllDay: true)]
        XCTAssertEqual(Agenda.freeAnswer(events, from: at(15, 12), to: at(15, 18), now: now, calendar: calendar),
                       "**Busy** Thu 15 Oct, 12:00–18:00\n- **15:00–15:30** Weekly sync\nFree 12:00–15:00, 15:30–18:00")
        XCTAssertEqual(Agenda.freeAnswer(events, from: at(15, 9), to: at(15, 12), now: now, calendar: calendar), "**Free** Thu 15 Oct, 09:00–12:00")
    }

    func testRequests() {
        XCTAssertEqual(AgendaRequest.parse("c'est quand ma prochaine réunion ?", now: now, calendar: calendar), .next(join: false))
        XCTAssertEqual(AgendaRequest.parse("next meeting", now: now, calendar: calendar), .next(join: false))
        XCTAssertEqual(AgendaRequest.parse("rejoins la réunion", now: now, calendar: calendar), .next(join: true))
        XCTAssertEqual(AgendaRequest.parse("rejoins la réunion de 14h", now: now, calendar: calendar), .next(join: true))
        XCTAssertEqual(AgendaRequest.parse("join my next meeting", now: now, calendar: calendar), .next(join: true))
        XCTAssertEqual(AgendaRequest.parse("qu'est-ce que j'ai demain ?", now: now, calendar: calendar), .day(offset: 1))
        XCTAssertEqual(AgendaRequest.parse("mon agenda aujourd'hui", now: now, calendar: calendar), .day(offset: 0))
        XCTAssertEqual(AgendaRequest.parse("what do I have on thursday", now: now, calendar: calendar), .day(offset: 3))
        XCTAssertEqual(AgendaRequest.parse("mes réunions lundi", now: now, calendar: calendar), .day(offset: 0))
        XCTAssertEqual(AgendaRequest.parse("agenda après-demain", now: now, calendar: calendar), .day(offset: 2))
        XCTAssertEqual(AgendaRequest.parse("mes dispos cette semaine", now: now, calendar: calendar), .availability)
        XCTAssertEqual(AgendaRequest.parse("copy my availability", now: now, calendar: calendar), .availability)
        XCTAssertEqual(AgendaRequest.parse("quand suis-je libre ?", now: now, calendar: calendar), .availability)
        // Free then: the part of the day, a time, or the working day.
        XCTAssertEqual(AgendaRequest.parse("suis-je libre jeudi après-midi ?", now: now, calendar: calendar), .free(from: at(15, 12), to: at(15, 18)))
        XCTAssertEqual(AgendaRequest.parse("am I free tomorrow at 3pm", now: now, calendar: calendar), .free(from: at(13, 15), to: at(13, 16)))
        XCTAssertEqual(AgendaRequest.parse("ai-je quelque chose demain", now: now, calendar: calendar), .free(from: at(13, 9), to: at(13, 18)))
        XCTAssertEqual(AgendaRequest.parse("suis-je libre ?", now: now, calendar: calendar), .free(from: now, to: today(18)))
        // More is asked: a model reads it.
        XCTAssertNil(AgendaRequest.parse("prépare un résumé de ma prochaine réunion", now: now, calendar: calendar))
        XCTAssertNil(AgendaRequest.parse("ajoute à mon agenda un point avec Paul demain", now: now, calendar: calendar))
        XCTAssertNil(AgendaRequest.parse("qu'est-ce que j'ai à faire demain", now: now, calendar: calendar))
        XCTAssertNil(AgendaRequest.parse("traduis ce texte", now: now, calendar: calendar))
    }
}
