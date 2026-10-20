import XCTest
@testable import SkilliCore

final class AskScheduleTests: XCTestCase {
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

    private func read(_ text: String, anywhere: Bool = false) -> (schedule: AskSchedule, ask: String)? {
        AskSchedule.read(text, now: now, calendar: calendar, anywhere: anywhere)
    }

    private func assertRead(_ text: String, _ spoken: String, _ ask: String, anywhere: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        guard let found = read(text, anywhere: anywhere) else {
            return XCTFail("“\(text)” read no schedule", file: file, line: line)
        }
        XCTAssertEqual(found.schedule.spoken, spoken, text, file: file, line: line)
        XCTAssertEqual(found.ask, ask, text, file: file, line: line)
    }

    // MARK: - Said in French and English

    func testFrench() {
        assertRead("tous les lundis à 9h résume mes PR", "Every Monday at 9:00", "résume mes PR")
        assertRead("tous les jours à 18h fais le point sur mes mails", "Every day at 18:00", "fais le point sur mes mails")
        assertRead("chaque lundi à 9h30, résume mes PR", "Every Monday at 9:30", "résume mes PR")
        assertRead("en semaine à 8h30 dis-moi ma journée", "Every weekday at 8:30", "dis-moi ma journée")
        assertRead("du lundi au vendredi à 8h30 fais-moi un point", "Every weekday at 8:30", "fais-moi un point")
        assertRead("tous les jours ouvrés à 8h dis-moi ma journée", "Every weekday at 8:00", "dis-moi ma journée")
        assertRead("tous les soirs à 22h active le mode sombre", "Every day at 22:00", "active le mode sombre")
        assertRead("tous les matins donne-moi la météo", "Every day at 9:00", "donne-moi la météo")
        assertRead("le 1er de chaque mois à 9h envoie-moi le bilan", "Every month on the 1st at 9:00", "envoie-moi le bilan")
        assertRead("tous les mois le 15 à 10h relance les factures", "Every month on the 15th at 10:00", "relance les factures")
        assertRead("tous les lundis et jeudis à 9h regarde les déploiements", "Every Monday and Thursday at 9:00", "regarde les déploiements")
        assertRead("toutes les 2 semaines le lundi à 9h relis la roadmap", "Every 2 weeks on Monday at 9:00", "relis la roadmap")
        // A day of the week is enough: 9:00 then.
        assertRead("tous les lundis résume mes PR", "Every Monday at 9:00", "résume mes PR")
        // Said at the end.
        assertRead("résume mes PR chaque lundi à 9h", "Every Monday at 9:00", "résume mes PR")
    }

    func testEnglish() {
        assertRead("every weekday at 8:30 tell me my day", "Every weekday at 8:30", "tell me my day")
        assertRead("every Monday at 9: sum up my pull requests", "Every Monday at 9:00", "sum up my pull requests")
        assertRead("every day at 6pm summarize my unread mail", "Every day at 18:00", "summarize my unread mail")
        assertRead("each morning give me the weather in Paris", "Every day at 9:00", "give me the weather in Paris")
        assertRead("every month on the 1st at 9am send me the invoices", "Every month on the 1st at 9:00", "send me the invoices")
        assertRead("on the first of every month at 9am list my subscriptions", "Every month on the 1st at 9:00", "list my subscriptions")
        assertRead("every monday and thursday at 9 check the deploys", "Every Monday and Thursday at 9:00", "check the deploys")
        assertRead("every weekend at 10 plan the week", "Every Saturday and Sunday at 10:00", "plan the week")
        assertRead("every 2 weeks on monday at 9 review the roadmap", "Every 2 weeks on Monday at 9:00", "review the roadmap")
        assertRead("on fridays at 17:00 list what I merged this week", "Every Friday at 17:00", "list what I merged this week")
        assertRead("check my PRs every weekday at 8:30", "Every weekday at 8:30", "check my PRs")
        // Its little words stay with what is asked.
        assertRead("every Monday at 9 the report on my pull requests", "Every Monday at 9:00", "the report on my pull requests")
    }

    func testNotASchedule() {
        for text in ["every day I wonder why the sky is blue", "tous les jours je bois trop de café, c'est grave ?",
                     "what's the weather every monday at 9 in Paris", "rappelle-moi demain à 9h d'appeler Paul",
                     "explique ce passage", "every monday at 9", "tous les jours à 9h", "chaque", "every year on 1 January at 9 wish me luck"] {
            XCTAssertNil(read(text).map { "\($0.schedule.spoken): \($0.ask)" }, text)
        }
    }

    /// Ask's decision chose a schedule: the words saying when may be
    /// anywhere and say less.
    func testAnywhereOnceAskChoseASchedule() {
        assertRead("est-ce que tu peux chaque lundi à 9h me résumer mes PR", "Every Monday at 9:00", "est-ce que tu peux me résumer mes PR",
                   anywhere: true)
        assertRead("chaque mois envoie-moi le bilan", "Every month on the 12th at 9:00", "envoie-moi le bilan", anywhere: true)
        XCTAssertNil(read("est-ce que tu peux chaque lundi à 9h me résumer mes PR"), "not a block at either end")
        XCTAssertNil(read("résume mes PR", anywhere: true))
    }

    func testMentionsRepeat() {
        for text in ["est-ce que tu pourrais me faire un résumé de mes mails chaque soir", "every Monday", "TOUS LES JOURS", "en semaine",
                     "du lundi au vendredi", "daily standup notes", "on fridays"] {
            XCTAssertTrue(AskSchedule.mentionsRepeat(text), text)
        }
        for text in ["ouvre les réglages bluetooth", "rappelle-moi demain à 9h", "everyone is here", "tous", "chaquement"] {
            XCTAssertFalse(AskSchedule.mentionsRepeat(text), text)
        }
    }

    /// As tools give it: when alone.
    func testWhenAlone() {
        XCTAssertEqual(AskSchedule.when("every Monday at 9:00", now: now, calendar: calendar)?.spoken, "Every Monday at 9:00")
        XCTAssertEqual(AskSchedule.when("tous les jours à 8h30", now: now, calendar: calendar)?.spoken, "Every day at 8:30")
        XCTAssertEqual(AskSchedule.when("weekdays at 7am", now: now, calendar: calendar)?.spoken, "Every weekday at 7:00")
        XCTAssertEqual(AskSchedule.when("le 1er de chaque mois", now: now, calendar: calendar)?.spoken, "Every month on the 1st at 9:00")
        XCTAssertNil(AskSchedule.when("Monday at 9:00", now: now, calendar: calendar), "not again and again")
        XCTAssertNil(AskSchedule.when("every Monday at 9:00 sum up my PRs", now: now, calendar: calendar), "more than when")
    }

    func testSpokenAndKept() throws {
        XCTAssertEqual(AskSchedule.ordinal(1), "1st")
        XCTAssertEqual(AskSchedule.ordinal(2), "2nd")
        XCTAssertEqual(AskSchedule.ordinal(3), "3rd")
        XCTAssertEqual(AskSchedule.ordinal(11), "11th")
        XCTAssertEqual(AskSchedule.ordinal(22), "22nd")
        XCTAssertEqual(AskSchedule.time(hour: 9, minute: 5), "9:05")
        XCTAssertEqual(AskSchedule(.weekly, weekdays: [6, 2, 4], hour: 9, start: now).spoken, "Every Monday, Wednesday and Friday at 9:00")
        XCTAssertEqual(AskSchedule(.daily, hour: 7, minute: 15, interval: 3, start: now).spoken, "Every 3 days at 7:15")
        XCTAssertEqual(AskSchedule(.monthly, day: 31, hour: 9, interval: 2, start: now).spoken, "Every 2 months on the 31st at 9:00")
        let schedule = AskSchedule(.weekly, weekdays: [2], hour: 9, start: now)
        let data = try JSONEncoder().encode(schedule)
        XCTAssertEqual(try JSONDecoder().decode(AskSchedule.self, from: data), schedule)
    }

    // MARK: - Its next time

    func testNextTime() {
        let monday = AskSchedule(.weekly, weekdays: [2], hour: 9, start: at(12))
        XCTAssertEqual(monday.next(after: now, calendar: calendar), at(19, 9))
        XCTAssertEqual(monday.next(after: at(12, 8), calendar: calendar), at(12, 9))
        XCTAssertEqual(monday.next(after: at(12, 9), calendar: calendar), at(19, 9), "strictly after")
        let weekdays = AskSchedule(.weekly, weekdays: [2, 3, 4, 5, 6], hour: 8, minute: 30, start: at(12))
        XCTAssertEqual(weekdays.next(after: at(16, 9), calendar: calendar), at(19, 8, 30), "Friday after its time: Monday")
        XCTAssertEqual(weekdays.next(after: at(13, 7), calendar: calendar), at(13, 8, 30))
        let daily = AskSchedule(.daily, hour: 9, start: at(12))
        XCTAssertEqual(daily.next(after: now, calendar: calendar), at(13, 9))
        let everyOther = AskSchedule(.daily, hour: 9, interval: 2, start: at(12))
        XCTAssertEqual(everyOther.next(after: at(12, 10), calendar: calendar), at(14, 9))
        let fortnight = AskSchedule(.weekly, weekdays: [2], hour: 9, interval: 2, start: at(12))
        XCTAssertEqual(fortnight.next(after: at(12, 10), calendar: calendar), at(26, 9))
        XCTAssertEqual(fortnight.next(after: at(26, 10), calendar: calendar), at(9, 9, month: 11))
    }

    func testMonthsAndTheirLastDay() {
        let first = AskSchedule(.monthly, day: 1, hour: 9, start: at(12))
        XCTAssertEqual(first.next(after: now, calendar: calendar), at(1, 9, month: 11))
        let last = AskSchedule(.monthly, day: 31, hour: 9, start: at(12))
        XCTAssertEqual(last.next(after: now, calendar: calendar), at(31, 9))
        XCTAssertEqual(last.next(after: at(31, 10), calendar: calendar), at(30, 9, month: 11), "November has 30 days")
        XCTAssertEqual(last.next(after: at(1, 0, month: 2, year: 2027), calendar: calendar), at(28, 9, month: 2, year: 2027))
        let quarterly = AskSchedule(.monthly, day: 15, hour: 9, interval: 3, start: at(12))
        XCTAssertEqual(quarterly.next(after: at(16), calendar: calendar), at(15, 9, month: 1, year: 2027))
    }

    func testClocksChanging() {
        // Paris: clocks back on 25 October 2026, forward on 28 March 2027.
        let early = AskSchedule(.daily, hour: 2, minute: 30, start: at(12))
        let back = early.next(after: at(25, 0), calendar: calendar)
        XCTAssertEqual(back.map { calendar.component(.day, from: $0) }, 25)
        let forward = early.next(after: at(27, 12, month: 3, year: 2027), calendar: calendar)
        XCTAssertEqual(forward.map { calendar.component(.day, from: $0) }, 28, "a time the clocks skip runs that day, just after")
    }

    // MARK: - Due, missed, caught up once

    func testDueOnTimeThenNextWeek() {
        var ask = ScheduledAsk(ask: "sum up my pull requests", schedule: AskSchedule(.weekly, weekdays: [2], hour: 9, start: at(12)),
                               created: at(12, 8))
        XCTAssertEqual(ScheduledAsks.next([ask], now: at(12, 8, 30), calendar: calendar), at(12, 9))
        XCTAssertTrue(ScheduledAsks.due([ask], now: at(12, 8, 59), calendar: calendar).isEmpty)
        XCTAssertEqual(ScheduledAsks.due([ask], now: at(12, 9), calendar: calendar).map(\.id), [ask.id])
        ask.lastRun = at(12, 9)
        XCTAssertTrue(ScheduledAsks.due([ask], now: at(12, 9, 1), calendar: calendar).isEmpty)
        XCTAssertEqual(ask.due(calendar: calendar), at(19, 9))
    }

    func testMissedRunsRunOnceAtWake() {
        var ask = ScheduledAsk(ask: "tell me my day", schedule: AskSchedule(.weekly, weekdays: [2, 3, 4, 5, 6], hour: 8, minute: 30, start: at(5)),
                               created: at(5, 7))
        ask.lastRun = at(9, 8, 30)
        // Asleep from Friday to Wednesday 10:00: Monday, Tuesday and Wednesday missed.
        let wake = at(14, 10)
        XCTAssertEqual(ScheduledAsks.due([ask], now: wake, calendar: calendar).count, 1, "due once, not three times")
        ask.lastRun = wake
        XCTAssertTrue(ScheduledAsks.due([ask], now: wake.addingTimeInterval(60), calendar: calendar).isEmpty)
        XCTAssertEqual(ask.due(calendar: calendar), at(15, 8, 30))
    }

    func testOffThenOnCatchesNothingUp() {
        var ask = ScheduledAsk(ask: "météo", schedule: AskSchedule(.daily, hour: 9, start: at(1)), created: at(1, 8))
        ask.turn(on: false)
        XCTAssertNil(ask.due(calendar: calendar))
        XCTAssertNil(ScheduledAsks.next([ask], now: now, calendar: calendar))
        ask.turn(on: true, now: now)
        XCTAssertTrue(ScheduledAsks.due([ask], now: now, calendar: calendar).isEmpty, "the days it was off are not caught up")
        XCTAssertEqual(ask.due(calendar: calendar), at(13, 9))
    }

    func testSoonestFirstAndKept() throws {
        let a = ScheduledAsk(ask: "a", schedule: AskSchedule(.daily, hour: 9, start: at(1)), created: at(1))
        let b = ScheduledAsk(ask: "b", schedule: AskSchedule(.daily, hour: 7, start: at(1)), created: at(1))
        XCTAssertEqual(ScheduledAsks.due([a, b], now: at(1, 10), calendar: calendar).map(\.ask), ["b", "a"])
        XCTAssertEqual(ScheduledAsks.next([a, b], now: at(1, 8), calendar: calendar), at(1, 9))
        let data = try JSONEncoder().encode([a, b])
        XCTAssertEqual(try JSONDecoder().decode([ScheduledAsk].self, from: data), [a, b])
        XCTAssertEqual(a.spoken, "Every day at 9:00: a")
    }

    func testMomentsAsSaid() {
        XCTAssertEqual(ScheduledAsks.moment(at(12, 9), now: now, calendar: calendar), "Today 9:00")
        XCTAssertEqual(ScheduledAsks.moment(at(13, 8, 30), now: now, calendar: calendar), "Tomorrow 8:30")
        XCTAssertEqual(ScheduledAsks.moment(at(11, 9), now: now, calendar: calendar), "Yesterday 9:00")
        XCTAssertEqual(ScheduledAsks.moment(at(19, 9), now: now, calendar: calendar), "Mon 19 Oct 9:00")
        XCTAssertEqual(ScheduledAsks.moment(at(4, 9, month: 1, year: 2027), now: now, calendar: calendar), "Mon 4 Jan 2027 9:00")
    }

    func testTheRowsLine() {
        XCTAssertEqual(ScheduledAsks.line(of: "## Pull requests\n- **#12** ready to merge"), "Pull requests")
        XCTAssertEqual(ScheduledAsks.line(of: "\n\n- **3** ready, 1 blocked\nmore"), "3 ready, 1 blocked")
        let long = String(repeating: "word ", count: 40)
        let cut = ScheduledAsks.line(of: long, limit: 30)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertLessThanOrEqual(cut.count, 31)
        XCTAssertEqual(ScheduledAsks.line(of: "  "), "")
    }
}
