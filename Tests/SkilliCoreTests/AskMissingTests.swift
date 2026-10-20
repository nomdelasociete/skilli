import SkilliCore
import XCTest

/// A value the request did not give, asked in the card: the answer read
/// alone and joined to what the request gave, nothing said again.
final class AskMissingTests: XCTestCase {
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

    private func answers(_ pairs: [String: String], sure: Double = 0.95) -> [String: AskValues.Answer] {
        pairs.mapValues { AskValues.Answer(choice: $0, confidence: sure) }
    }

    /// The model's reading of `reply` for `missing`, joined to `request`'s.
    private func joined(_ request: [String: String], _ missing: AskValues.Missing, reply: String, read: [String: String],
                        sure: Double = 0.95) -> [String: AskValues.Answer] {
        answers(request).merging(missing.answers(answers(read, sure: sure), reply: reply)) { $1 }
    }

    private func phrase(_ text: String, in sentence: String, longest: Int = 6) -> String {
        "phrase \(AskValues.phrases(of: AskValues.words(of: sentence), longest: longest).firstIndex(of: text) ?? -1)"
    }

    private func plan(_ request: String, _ answers: [String: AskValues.Answer]) -> AskValues.Plan {
        AskValues.plan(answers, words: AskValues.words(of: request), lists: [], calendars: [], now: now, calendar: calendar)
    }

    /// "mets un minuteur pour les pâtes": how long asked, "10 minutes"
    /// read alone; what it is for kept.
    func testATimersLength() {
        let request = "mets un minuteur pour les pâtes"
        let spans = AskValues.spans(of: request)
        let first = ["length": "none", "until_hour": "none", "until_minute": "none", "label": phrase("les pâtes", in: request)]
        XCTAssertNil(AskValues.duration(answers(first)))
        XCTAssertEqual(AskValues.Missing.length.questions(reply: "10 minutes").map(\.name), ["length", "until_hour", "until_minute"])
        let all = joined(first, .length, reply: "10 minutes", read: ["length": "10 min", "until_hour": "none", "until_minute": "none"])
        XCTAssertEqual(AskValues.duration(all)?.seconds, 600)
        XCTAssertEqual(AskValues.label(all, spans: spans), "les pâtes")
    }

    /// Only the missing value's own questions join: an answer can never
    /// change what the request said of the rest.
    func testOnlyItsOwnQuestionsJoin() {
        let read = AskValues.Missing.level.answers(answers(["level": "30", "length": "1 h"]), reply: "30")
        XCTAssertEqual(read.keys.sorted(), ["level"])
        XCTAssertEqual(AskValues.level(answers(["level": "none"]).merging(read) { $1 })?.level, 30)
    }

    /// "désinstalle": the app's name typed in the card, picked among the
    /// answer's own words.
    func testAnAppsName() {
        let reply = "Creative Cloud"
        let read = AskValues.Missing.app.answers(answers(["target": phrase("Creative Cloud", in: reply, longest: 4)]), reply: reply)
        XCTAssertEqual(read["target"]?.said, "Creative Cloud")
        let words = AskValues.words(of: "désinstalle")
        XCTAssertNil(AskValues.target(answers(["target": "none"]), words: words))
        XCTAssertEqual(AskValues.target(answers(["target": "none"]).merging(read) { $1 }, words: words), "Creative Cloud")
        // Nothing the model found: nothing joins, the question stays.
        XCTAssertTrue(AskValues.Missing.app.answers(answers(["target": "none"]), reply: "euh").isEmpty)
    }

    /// "écris un mail": who, typed; "Paul Durand": what about them, keycaps.
    func testAContact() {
        let request = "écris un mail"
        let words = AskValues.words(of: request)
        guard case .missing(let who) = AskValues.contact(answers(["contact": "mail", "person": "none", "says": "no"]), words: words) else {
            return XCTFail("who is missing")
        }
        XCTAssertEqual(who.value, .person)
        XCTAssertTrue(who.options.isEmpty, "a name is typed")
        let named = joined(["contact": "mail", "person": "none", "says": "no"], who, reply: "Paul Durand",
                           read: ["person": phrase("Paul Durand", in: "Paul Durand")])
        XCTAssertEqual(AskValues.contact(named, words: words), .mail(person: "Paul Durand", says: false))

        let said = "Paul Durand"
        let unsure = ["contact": "none", "person": phrase("Paul Durand", in: said)]
        guard case .missing(let kind) = AskValues.contact(answers(unsure), words: AskValues.words(of: said)) else {
            return XCTFail("what about them is missing")
        }
        XCTAssertEqual(kind.options.map(\.description), ["Who they are", "Write them a mail"])
        let picked = answers(unsure).merging(kind.answers(picking: "who")) { $1 }
        XCTAssertEqual(picked["contact"]?.confidence, 1, "the user's own pick is sure")
        XCTAssertEqual(AskValues.contact(picked, words: AskValues.words(of: said)), .who(person: "Paul Durand"))
        XCTAssertTrue(kind.answers(picking: "call").isEmpty, "only its own options")
    }

    /// "rappelle-moi d'appeler Paul": when, typed ("demain 9h"); what it
    /// says kept from the request.
    func testAReminderWhen() {
        let request = "rappelle-moi d'appeler Paul"
        let first = ["plan": "remind", "title_start": "word 2", "title_end": "word 3", "when": "at", "day": "none", "hour": "none"]
        guard case .missing(let missing) = plan(request, answers(first)) else { return XCTFail("when is missing") }
        XCTAssertEqual(missing, .reminderWhen)
        let all = joined(first, missing, reply: "demain 9h",
                         read: ["when": "at", "day": "tomorrow", "hour": "9", "minute": "0", "part_of_day": "none", "delay": "none"])
        XCTAssertEqual(plan(request, all), .reminder(ReminderRequest(title: "Appeler Paul", due: date(17, 9), hasTime: true), sure: 0.95))
    }

    /// "rappelle-moi demain à 9h": what it says, typed; the words saying
    /// when in the answer left out, the request's when kept.
    func testAReminderTitle() {
        let request = "rappelle-moi demain à 9h"
        let first = ["plan": "remind", "title_start": "none", "title_end": "none", "when": "at", "day": "tomorrow", "hour": "9", "minute": "0"]
        guard case .missing(let missing) = plan(request, answers(first)) else { return XCTFail("what it says is missing") }
        XCTAssertEqual(missing.value, .reminderTitle)
        let reply = "appeler Paul ce soir"
        let all = joined(first, missing, reply: reply,
                         read: ["title_start": "word 0", "title_end": "word 3", "when_words_start": "word 2", "when_words_end": "word 3"])
        XCTAssertEqual(plan(request, all), .reminder(ReminderRequest(title: "Appeler Paul", due: date(17, 9), hasTime: true), sure: 0.95))
    }

    /// "crée un rdv avec Paul": which day, typed; an unsure reading of it
    /// makes the event unsure (the card then waits for ↩).
    func testAnEventsDay() {
        let request = "crée un rdv avec Paul"
        let first = ["plan": "event", "title_start": "word 2", "title_end": "word 4", "when": "none", "ends": "none"]
        guard case .missing(let missing) = plan(request, answers(first)) else { return XCTFail("which day is missing") }
        XCTAssertEqual(missing, .eventDay)
        let all = joined(first, missing, reply: "vendredi 14h",
                         read: ["when": "at", "day": "weekday", "weekday": "friday", "week": "coming", "hour": "14", "minute": "0"], sure: 0.4)
        guard case .event(let event, let sure) = plan(request, all) else { return XCTFail("no event") }
        XCTAssertEqual(event.title, "Rdv avec Paul")
        XCTAssertEqual(event.start, date(23, 14))
        XCTAssertEqual(event.end, date(23, 15))
        XCTAssertEqual(sure, 0.4)
    }

    /// "résume mes PR à 9h": how often, keycaps; "some days" then asks
    /// which days, typed; the hour kept.
    func testAScheduleHowOftenThenWhichDays() {
        let request = "résume mes PR à 9h"
        let words = AskValues.words(of: request)
        let first = ["schedule_repeat": "none", "hour": "9", "minute": "0", "is_reminder": "no", "ask": phrase("résume mes PR", in: request, longest: 8)]
        guard case .missing(let often) = AskValues.schedule(answers(first), words: words, now: now) else { return XCTFail("how often is missing") }
        XCTAssertEqual(often.value, .repeats)
        XCTAssertEqual(often.options.count, 5)
        let some = answers(first).merging(often.answers(picking: "some days")) { $1 }
        guard case .missing(let days) = AskValues.schedule(some, words: words, now: now) else { return XCTFail("which days is missing") }
        XCTAssertEqual(days, .weekdays)
        let all = some.merging(days.answers(answers(["day_1": "monday", "day_2": "thursday", "day_3": "none"]), reply: "lundi et jeudi")) { $1 }
        guard case .schedule(let schedule, let ask) = AskValues.schedule(all, words: words, now: now) else { return XCTFail("no schedule") }
        XCTAssertEqual(Set(schedule.weekdays), [2, 5])
        XCTAssertEqual(schedule.hour, 9)
        XCTAssertEqual(ask, "résume mes PR")
    }

    /// "tous les jours à 9h": what to do each time, typed, picked whole.
    func testAScheduleWhatToDo() {
        let request = "tous les jours à 9h"
        let first = ["schedule_repeat": "every day", "hour": "9", "minute": "0", "is_reminder": "no", "ask": "none"]
        let words = AskValues.words(of: request)
        guard case .missing(let missing) = AskValues.schedule(answers(first), words: words, now: now) else { return XCTFail("what to do is missing") }
        let reply = "résume mes mails"
        let all = joined(first, missing, reply: reply, read: ["ask": phrase("résume mes mails", in: reply, longest: 8)])
        guard case .schedule(_, let ask) = AskValues.schedule(all, words: words, now: now) else { return XCTFail("no schedule") }
        XCTAssertEqual(ask, "résume mes mails")
    }

    func testNotedQuestions() {
        let noted = AskValues.Missing.app.noting("No app named “Slak” on this Mac.")
        XCTAssertEqual(noted.note, "No app named “Slak” on this Mac.")
        XCTAssertEqual(noted.question, AskValues.Missing.app.question)
        XCTAssertNotEqual(noted, .app)
    }

    // MARK: - Menu items Ask chooses at once

    func testDestructiveMenuItems() {
        for path in [["Safari", "Quit Safari"], ["Finder", "Empty Trash…"], ["File", "Close Window"], ["Fichier", "Fermer la fenêtre"],
                     ["Mail", "Sign Out"], ["Message", "Send"], ["Edit", "Delete"], ["File", "Share", "Mail"], ["File", "Revert To", "Last Saved"],
                     ["History", "Clear History…"], ["Fichier", "Supprimer"], ["Compte", "Se déconnecter"], ["Apple", "Restart…"]] {
            XCTAssertTrue(MenuCandidates.isDestructive(path), "\(path)")
        }
        for path in [["File", "Export as PDF…"], ["View", "Show Sidebar"], ["File", "New Window"], ["View", "Zoom In"], ["File", "Print…"],
                     ["Format", "Font", "Bold"], ["Présentation", "Afficher la barre latérale"], ["Safari", "Check for Updates…"]] {
            XCTAssertFalse(MenuCandidates.isDestructive(path), "\(path)")
        }
    }

    // MARK: - Do it here: sensitive details asked together

    func testSensitiveDetailsAskedTogether() {
        let iban = FormProfile.Detail(key: "extra-1", description: "IBAN (field kept in skil.li)", value: "FR76", isSensitive: true)
        let bic = FormProfile.Detail(key: "extra-2", description: "BIC (field kept in skil.li)", value: "AGRI", isSensitive: true)
        let passport = FormProfile.Detail(key: "extra-3", description: "N° de passeport (field kept in skil.li)", value: "12", isSensitive: true)
        let email = FormProfile.Detail(key: "email", description: "Email address (e-mail, courriel)", value: "a@b.c")
        XCTAssertEqual(email.name, "email address")
        XCTAssertEqual(FormProfile.typingQuestion([iban], whose: "your", in: "Safari"), "Type your IBAN in Safari?")
        XCTAssertEqual(FormProfile.typingQuestion([iban, bic], whose: "Margot's", in: "Safari"), "Type Margot's IBAN and BIC in Safari?")
        XCTAssertEqual(FormProfile.typingQuestion([iban, bic, passport], whose: "your", in: ""), "Type your IBAN, BIC and N° de passeport?")
    }
}
