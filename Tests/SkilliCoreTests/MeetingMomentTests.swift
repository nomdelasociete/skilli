@testable import SkilliCore
import XCTest

final class MeetingMomentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_670_400)
    private let chrome = MicrophoneApp(bundleID: "com.google.Chrome", name: "Google Chrome", pid: 401)
    private let discord = MicrophoneApp(bundleID: "com.hnc.Discord", name: "Discord", pid: 402)
    private let zoom = MicrophoneApp(bundleID: "us.zoom.xos", name: "zoom.us", pid: 403)
    private let quickTime = MicrophoneApp(bundleID: "com.apple.QuickTimePlayerX", name: "QuickTime Player", pid: 404)

    private func event(title: String = "Weekly sync", location: String = "", notes: String = "", url: String? = nil,
                       startsIn minutes: Double = 0, allDay: Bool = false, declined: Bool = false) -> AgendaEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return AgendaEvent(id: "e1", title: title, start: start, end: start.addingTimeInterval(30 * 60), isAllDay: allDay, location: location,
                           notes: notes, url: url, attendees: [.init(name: "Margot Martin", email: nil), .init(name: "Camille", email: nil)],
                           declined: declined)
    }

    // MARK: - The five cases

    func testACallLinkRecordsBothSidesNamedByTheEvent() {
        let meet = event(url: "https://meet.google.com/abc-defg-hij")
        let reading = MeetingMoment.read(event: meet, microphone: .none, linkOpensIn: chrome)
        XCTAssertEqual(reading.kind, .callLink)
        XCTAssertEqual(reading.sources, .both)
        XCTAssertEqual(reading.title, "Weekly sync")
        XCTAssertEqual(reading.app, chrome, "not joined yet: the app the link opens in")
        XCTAssertEqual(reading.attendees, ["Margot Martin", "Camille"])
        XCTAssertEqual(reading.recordLabel, "Record")
    }

    func testACallLinkWatchesTheAppTheUserJoinedIn() {
        let meet = event(url: "https://meet.google.com/abc-defg-hij")
        let arc = MicrophoneApp(bundleID: "company.thebrowser.Browser", name: "Arc", pid: 405)
        XCTAssertEqual(MeetingMoment.read(event: meet, microphone: MicrophoneHolders(apps: [arc]), linkOpensIn: chrome).app, arc)
        XCTAssertEqual(MeetingMoment.read(event: meet, microphone: MicrophoneHolders(apps: [arc, chrome]), linkOpensIn: chrome).app, chrome,
                       "the link's own app first, when it is on the microphone")
    }

    func testNoLinkAndAnAppOnTheMicrophoneIsInThatApp() {
        let reading = MeetingMoment.read(event: event(location: "Salle Lumière"), microphone: MicrophoneHolders(apps: [chrome]))
        XCTAssertEqual(reading.kind, .inApp, "an app on the microphone wins over a place: the call is on")
        XCTAssertEqual(reading.app, chrome)
        XCTAssertEqual(reading.sources, .both)
    }

    func testTheLocationNamesWhichAppIsTheCall() {
        let reading = MeetingMoment.read(event: event(location: "Discord · Lumière server"), microphone: MicrophoneHolders(apps: [chrome, discord]))
        XCTAssertEqual(reading.app, discord)
        let callFirst = MeetingMoment.read(event: event(), microphone: MicrophoneHolders(apps: [quickTime, discord]))
        XCTAssertEqual(callFirst.app, discord, "else a known call app first")
        let first = MeetingMoment.read(event: event(), microphone: MicrophoneHolders(apps: [quickTime, chrome]))
        XCTAssertEqual(first.app, quickTime, "else the first")
    }

    func testAPlaceAndNobodyOnTheMicrophoneIsInPerson() {
        let reading = MeetingMoment.read(event: event(location: "Salle Lumière, 3e étage"), microphone: .none)
        XCTAssertEqual(reading.kind, .inPerson)
        XCTAssertEqual(reading.sources, MeetingMoment.Sources(microphone: true, macSound: false))
        XCTAssertNil(reading.app)
        XCTAssertEqual(reading.place, "Salle Lumière, 3e étage")
        XCTAssertEqual(reading.recordLabel, "Record (in person)")
    }

    func testAKnownCallAppWithNoEventIsACall() {
        let reading = MeetingMoment.read(event: nil, microphone: MicrophoneHolders(apps: [discord]))
        XCTAssertEqual(reading.kind, .callWithoutEvent)
        XCTAssertEqual(reading.app, discord)
        XCTAssertNil(reading.title, "named by the app and the time")
        let zoomCall = MeetingMoment.read(event: nil, microphone: MicrophoneHolders(apps: [chrome, zoom]))
        XCTAssertEqual(zoomCall.app, zoom)
    }

    func testABrowserWithNoEventIsNothingToGoOn() {
        let reading = MeetingMoment.read(event: nil, microphone: MicrophoneHolders(apps: [chrome]),
                                         defaults: MeetingMoment.Sources(microphone: true, macSound: false))
        XCTAssertEqual(reading.kind, .nothing)
        XCTAssertEqual(reading.sources, MeetingMoment.Sources(microphone: true, macSound: false), "the default sources")
        XCTAssertNil(reading.app)
    }

    func testOnlyAnAppSkilliCannotNameIsNothingToGoOn() {
        // Safari's call: WebKit's service runs the microphone, no app among its parents.
        let reading = MeetingMoment.read(event: event(location: "Salle Lumière"), microphone: MicrophoneHolders(apps: [], unnamed: 1))
        XCTAssertEqual(reading.kind, .nothing, "not in person: something runs the microphone")
        XCTAssertEqual(reading.title, "Weekly sync")
        XCTAssertEqual(MeetingMoment.read(event: nil, microphone: MicrophoneHolders(unnamed: 2)).kind, .nothing)
    }

    func testAnEventWithNothingToSayIsNothingToGoOn() {
        let reading = MeetingMoment.read(event: event(location: "Online"), microphone: .none)
        XCTAssertEqual(reading.kind, .nothing)
        XCTAssertEqual(reading.title, "Weekly sync")
        XCTAssertEqual(MeetingMoment.read(event: event(title: "  "), microphone: .none).title, nil, "an untitled event: the default name")
    }

    func testAllDayAndDeclinedEventsAreNotMeetings() {
        XCTAssertNil(MeetingMoment.read(event: event(allDay: true), microphone: .none).event)
        XCTAssertNil(MeetingMoment.read(event: event(declined: true), microphone: .none).event)
        XCTAssertFalse(MeetingMoment.isRecordable(event(allDay: true), now: now))
        XCTAssertFalse(MeetingMoment.isRecordable(event(declined: true), now: now))
    }

    func testRecordableFromTenMinutesBeforeToItsEnd() {
        XCTAssertTrue(MeetingMoment.isRecordable(event(startsIn: 10), now: now))
        XCTAssertFalse(MeetingMoment.isRecordable(event(startsIn: 11), now: now))
        XCTAssertTrue(MeetingMoment.isRecordable(event(startsIn: -29), now: now))
        XCTAssertFalse(MeetingMoment.isRecordable(event(startsIn: -30), now: now), "over at its end")
    }

    // MARK: - A place

    func testPlacesAreWrittenPlaces() {
        XCTAssertEqual(MeetingMoment.place("Salle Lumière"), "Salle Lumière")
        XCTAssertEqual(MeetingMoment.place("12 rue de la Paix, Paris"), "12 rue de la Paix, Paris")
        XCTAssertEqual(MeetingMoment.place("Bât. B, salle 2.1"), "Bât. B, salle 2.1")
        XCTAssertEqual(MeetingMoment.place("  Horizon HQ  "), "Horizon HQ")
    }

    func testOnlineWordsAddressesAndPhonesAreNotPlaces() {
        for location in ["", "Online", "En ligne", "visio", "Remote", "TBD", "à définir", "Phone call", "https://example.com/room",
                         "lumiere.example.com/salon", "+33 6 12 34 56 78", "Gather", "Slack huddle", "Google Meet", "Discord · Lumière server",
                         "app.gather.town/app/abc"] {
            XCTAssertNil(MeetingMoment.place(location), location)
        }
    }

    func testCallAppsByBundleOrName() {
        XCTAssertTrue(MeetingMoment.isCallApp(discord))
        XCTAssertTrue(MeetingMoment.isCallApp(zoom))
        XCTAssertTrue(MeetingMoment.isCallApp(MicrophoneApp(bundleID: "", name: "Tuple", pid: 1)))
        XCTAssertFalse(MeetingMoment.isCallApp(chrome), "a browser is not a call app")
        XCTAssertFalse(MeetingMoment.isCallApp(quickTime))
    }

    func testACallWithNoEventIsNamedByItsApp() {
        let title = MeetingMoment.callTitle(discord, at: Date(timeIntervalSince1970: 1_792_678_200), locale: Locale(identifier: "fr_FR"),
                                            timeZone: TimeZone(identifier: "Europe/Paris")!)
        XCTAssertEqual(title, "Discord call 16:10")
    }

    // MARK: - The call ends

    func testTheCallEndsWhenItsAppLeavesForFiveSeconds() {
        var watch = CallEndWatch()
        let app = "Google Chrome"
        XCTAssertNil(watch.update(now: now, app: (app, false), quiet: false, eventEnd: nil), "never seen on the microphone: joining")
        XCTAssertNil(watch.update(now: now.addingTimeInterval(10), app: (app, true), quiet: false, eventEnd: nil))
        XCTAssertNil(watch.update(now: now.addingTimeInterval(11), app: (app, false), quiet: false, eventEnd: nil))
        XCTAssertNil(watch.update(now: now.addingTimeInterval(13), app: (app, true), quiet: false, eventEnd: nil), "a reconnect is not an end")
        XCTAssertNil(watch.update(now: now.addingTimeInterval(14), app: (app, false), quiet: false, eventEnd: nil))
        XCTAssertNil(watch.update(now: now.addingTimeInterval(18), app: (app, false), quiet: false, eventEnd: nil))
        XCTAssertEqual(watch.update(now: now.addingTimeInterval(19), app: (app, false), quiet: false, eventEnd: nil), .appLeft(app))
        XCTAssertTrue(watch.stillTrue(.appLeft(app)))
        XCTAssertNil(watch.update(now: now.addingTimeInterval(40), app: (app, false), quiet: false, eventEnd: nil), "once")
        _ = watch.update(now: now.addingTimeInterval(41), app: (app, true), quiet: false, eventEnd: nil)
        XCTAssertFalse(watch.stillTrue(.appLeft(app)), "back on the microphone: the offer goes")
    }

    func testTheMeetingEndsWhenItIsOverAndQuietForAMinute() {
        var watch = CallEndWatch()
        let end = now.addingTimeInterval(60)
        XCTAssertNil(watch.update(now: now, app: nil, quiet: true, eventEnd: end), "quiet before the end counts from the end")
        XCTAssertNil(watch.update(now: end.addingTimeInterval(59), app: nil, quiet: true, eventEnd: end))
        XCTAssertEqual(watch.update(now: end.addingTimeInterval(60), app: nil, quiet: true, eventEnd: end), .quietAfterEnd(end))
        XCTAssertNil(watch.update(now: end.addingTimeInterval(200), app: nil, quiet: true, eventEnd: end), "once")
    }

    func testSoundAfterTheEndStartsTheMinuteAgain() {
        var watch = CallEndWatch()
        let end = now
        _ = watch.update(now: end.addingTimeInterval(10), app: nil, quiet: true, eventEnd: end)
        _ = watch.update(now: end.addingTimeInterval(50), app: nil, quiet: false, eventEnd: end)
        XCTAssertNil(watch.update(now: end.addingTimeInterval(80), app: nil, quiet: true, eventEnd: end))
        XCTAssertNil(watch.update(now: end.addingTimeInterval(139), app: nil, quiet: true, eventEnd: end))
        XCTAssertEqual(watch.update(now: end.addingTimeInterval(140), app: nil, quiet: true, eventEnd: end), .quietAfterEnd(end))
        var noMeeting = CallEndWatch()
        XCTAssertNil(noMeeting.update(now: end.addingTimeInterval(500), app: nil, quiet: true, eventEnd: nil), "no meeting: never by quiet")
    }

    func testAnotherAppPickedMustBeSeenFirst() {
        var watch = CallEndWatch()
        _ = watch.update(now: now, app: ("Discord", true), quiet: false, eventEnd: nil)
        watch.appChanged()
        XCTAssertNil(watch.update(now: now.addingTimeInterval(1), app: ("Google Chrome", false), quiet: false, eventEnd: nil))
        XCTAssertNil(watch.update(now: now.addingTimeInterval(30), app: ("Google Chrome", false), quiet: false, eventEnd: nil))
    }

    func testTheCardSaysWhy() {
        XCTAssertEqual(CallEndWatch.line(.appLeft("Google Chrome")), "Google Chrome left the call.")
        XCTAssertEqual(CallEndWatch.line(.quietAfterEnd(now)) { _ in "14:30" }, "The meeting ended at 14:30, and it has been quiet for a minute.")
    }

    // MARK: - People

    func testPeopleAreSaidByFirstName() {
        XCTAssertEqual(MeetingPeople.sentence([]), "")
        XCTAssertEqual(MeetingPeople.sentence(["Margot Martin"]), "Margot")
        XCTAssertEqual(MeetingPeople.sentence(["Margot Martin", "Camille"]), "Margot and Camille")
        XCTAssertEqual(MeetingPeople.sentence(["Margot Martin", "Camille", "Jean-François Martaing"]), "Margot, Camille and 1 other")
        XCTAssertEqual(MeetingPeople.sentence(["A", "B", "C", "D"]), "A, B and 2 others")
    }
}

final class RecordingRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_670_400)

    func testItsChoicesRoundTrip() {
        for retention in [RecordingRetention.never, .week, .month, .quarter, .year, .days(10)] {
            XCTAssertEqual(RecordingRetention(rawValue: retention.rawValue), retention)
        }
        XCTAssertEqual(RecordingRetention(rawValue: "days:0"), .never)
        XCTAssertEqual(RecordingRetention(rawValue: "nonsense"), .never)
        XCTAssertEqual(RecordingRetention.week.asCustom, .days(7))
        XCTAssertEqual(RecordingRetention.never.asCustom, .days(365))
    }

    func testTheLineSaysWhatTheNextPassRemoves() {
        XCTAssertEqual(RecordingRetention.month.removalLine(older: 2), "2 recordings are older than a month: they go to the Trash within the hour.")
        XCTAssertEqual(RecordingRetention.quarter.removalLine(older: 1), "1 recording is older than 3 months: it goes to the Trash within the hour.")
        XCTAssertEqual(RecordingRetention.days(10).removalLine(older: 3), "3 recordings are older than 10 days: they go to the Trash within the hour.")
        XCTAssertNil(RecordingRetention.month.removalLine(older: 0))
        XCTAssertNil(RecordingRetention.never.removalLine(older: 5))
    }

    func testOnlyDoneRecordingsPastTheCutoffGo() {
        func record(_ daysAgo: Double, _ state: MeetingRecord.State) -> MeetingRecord {
            var record = MeetingRecord(title: "Weekly sync", started: now.addingTimeInterval(-daysAgo * 86_400), language: "en-US", recorder: nil)
            record.state = state
            return record
        }
        let recordings: [(folder: String, record: MeetingRecord)] = [
            ("old done", record(40, .done)), ("old pending", record(40, .pending)), ("old never stopped", record(40, .recording)),
            ("old transcribing", record(40, .transcribing)), ("new done", record(10, .done))
        ]
        XCTAssertEqual(RecordingRetention.month.expired(recordings, now: now), ["old done", "old pending"])
        XCTAssertEqual(RecordingRetention.never.expired(recordings, now: now), [])
        XCTAssertEqual(RecordingRetention.week.expired(recordings, now: now), ["old done", "old pending", "new done"])
    }
}

final class RecordingSearchTests: XCTestCase {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func summary(_ title: String, attendees: [String] = [], daysAgo: Double = 0) -> RecordingSummary {
        RecordingSummary(folder: title, title: title, started: Date(timeIntervalSince1970: 1_792_670_400 - daysAgo * 86_400), seconds: 1920,
                         attendees: attendees, state: .done)
    }

    func testEveryWordTypedStartsAWordOfItsTitleAttendeesOrDate() {
        let english = Locale(identifier: "en_US")
        let weekly = summary("Weekly design review", attendees: ["Margot Martin", "Camille"])
        XCTAssertNotNil(RecordingSearch.score("design", weekly, locale: english, calendar: paris))
        XCTAssertNotNil(RecordingSearch.score("wee rev", weekly, locale: english, calendar: paris))
        XCTAssertNotNil(RecordingSearch.score("margot", weekly, locale: english, calendar: paris))
        XCTAssertNotNil(RecordingSearch.score("review octo", weekly, locale: english, calendar: paris), "its month")
        XCTAssertNil(RecordingSearch.score("budget", weekly, locale: english, calendar: paris))
        XCTAssertNil(RecordingSearch.score("design budget", weekly, locale: english, calendar: paris), "every word")
        XCTAssertGreaterThan(RecordingSearch.score("design", weekly, locale: english, calendar: paris)!,
                             RecordingSearch.score("margot", weekly, locale: english, calendar: paris)!, "the title first")
    }

    func testAccentsAndCaseAside() {
        let comite = summary("Comité de pilotage", attendees: ["Maëlys Le Guennec"])
        XCTAssertNotNil(RecordingSearch.score("COMITE", comite))
        XCTAssertNotNil(RecordingSearch.score("maelys", comite))
    }

    func testTheRowSaysWhenHowLongAndWho() {
        let line = RecordingSearch.detail(summary("Weekly sync", attendees: ["Margot Martin", "Camille", "Jean-François Martaing"]), length: "32 min")
        XCTAssertTrue(line.hasSuffix(" · 32 min · Margot, Camille and 1 other"), line)
    }
}
