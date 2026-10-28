@testable import SkilliCore
import XCTest

final class MeetingBarTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var sync: AgendaEvent {
        AgendaEvent(id: "sync", title: "Weekly sync", start: start, end: start.addingTimeInterval(30 * 60),
                    notes: "https://meet.google.com/abc-defg-hij")
    }
    private var standup: AgendaEvent {
        AgendaEvent(id: "standup", title: "Standup", start: start.addingTimeInterval(30 * 60), end: start.addingTimeInterval(45 * 60),
                    notes: "https://meet.google.com/xyz-abcd-efg")
    }
    private let options = MeetingBar.Options(lead: 10, callsOnly: true, countdown: true, hideAfter: 10, nextDuringMeeting: true)
    private let idle = MeetingBar.Presence(microphone: .idle)

    private func at(_ minutes: Double, _ events: [AgendaEvent]? = nil, options: MeetingBar.Options? = nil,
                    presence: MeetingBar.Presence? = nil) -> (plan: MeetingBar.Plan, look: MeetingBar.Look?) {
        let now = start.addingTimeInterval(minutes * 60)
        let plan = MeetingBar.plan(events ?? [sync, standup], now: now, options: options ?? self.options, presence: presence ?? idle)
        let look = plan.shown.flatMap { shown in plan.state.map { MeetingBar.look(of: shown, state: $0, next: plan.next) } }
        return (plan, look)
    }

    // MARK: - Coming

    func testComingSaysInHowManyMinutesWithACalendar() {
        let (plan, look) = at(-12)
        XCTAssertNil(plan.shown, "10 min before by default: not yet")
        let (soon, soonLook) = at(-9.5)
        XCTAssertEqual(soon.shown?.id, "sync")
        XCTAssertEqual(soon.state, .coming(minutes: 10), "rounded up")
        XCTAssertEqual(soonLook, MeetingBar.Look(glyph: .calendar, urgent: false, title: "Weekly sync · in 10 min",
                                                 help: "Weekly sync starts at \(MeetingBar.clock(start))."))
        XCTAssertNil(look)
        XCTAssertEqual(at(-0.2).look?.title, "Weekly sync · in 1 min")
    }

    func testComingCountsDownEachMinuteThenItsStart() {
        let (plan, _) = at(-9.5)
        // The next minute boundary (9 min to go) and the start: one timer at the first.
        XCTAssertEqual(plan.changes.min(), start.addingTimeInterval(-9 * 60))
        XCTAssertTrue(plan.changes.contains(start))
    }

    func testAnHourOrMoreAwayItSaysItsTime() {
        let always = MeetingBar.Options(lead: .max, callsOnly: true, countdown: true, hideAfter: 10, nextDuringMeeting: true)
        let (plan, look) = at(-125, options: always)
        XCTAssertEqual(plan.state, .coming(minutes: nil))
        XCTAssertEqual(look?.title, "Weekly sync · at \(MeetingBar.clock(start))")
        XCTAssertEqual(plan.changes.min(), start.addingTimeInterval(-59 * 60), "then in minutes, under the hour")
        XCTAssertEqual(at(-59, options: always).plan.state, .coming(minutes: 59))
    }

    // MARK: - Started, not joined

    func testStartedAndNotJoinedIsRedWithTheMinutesSince() {
        let (plan, look) = at(3.4)
        XCTAssertEqual(plan.state, .started(minutes: 3, late: true))
        XCTAssertEqual(look?.glyph, .call)
        XCTAssertEqual(look?.urgent, true)
        XCTAssertEqual(look?.title, "Weekly sync · started 3 min ago")
        XCTAssertEqual(look?.help, "Weekly sync started at \(MeetingBar.clock(start)), and you have not joined it from this Mac.")
        XCTAssertEqual(at(0.5).look?.title, "Weekly sync · starting now")
        XCTAssertEqual(plan.changes.min(), start.addingTimeInterval(4 * 60), "each minute")
        XCTAssertTrue(plan.changes.contains(start.addingTimeInterval(MeetingBar.lateWindow)))
    }

    func testWithoutAMicrophoneItOnlySaysItStarted() {
        let (plan, look) = at(3.4, presence: MeetingBar.Presence(microphone: .unknown))
        XCTAssertEqual(plan.state, .started(minutes: 3, late: false))
        XCTAssertEqual(look?.urgent, false, "no claim of being late when this Mac cannot tell")
        XCTAssertEqual(look?.glyph, .call)
        XCTAssertEqual(look?.title, "Weekly sync · started 3 min ago")
        XCTAssertTrue(look?.help.contains("cannot tell") == true)
    }

    func testFifteenMinutesInItCountsDownLikeAnyMeeting() {
        let (plan, look) = at(15)
        XCTAssertEqual(plan.state, .on(minutesLeft: 15, remaining: 0.5))
        XCTAssertEqual(look?.urgent, false)
    }

    func testAnEventWithoutACallIsOnAtOnce() {
        let lunch = AgendaEvent(id: "lunch", title: "Lunch", start: start, end: start.addingTimeInterval(60 * 60), location: "Le Comptoir")
        let all = MeetingBar.Options(lead: 10, callsOnly: false, countdown: true, hideAfter: 10, nextDuringMeeting: true)
        XCTAssertEqual(at(2, [lunch], options: all).plan.state, .on(minutesLeft: 58, remaining: 58.0 / 60))
    }

    // MARK: - Joined

    func testJoinedFromSkilliCountsDownWithTheRing() {
        let joined = MeetingBar.Presence(joined: [MeetingBar.key(sync)], microphone: .idle)
        let (plan, look) = at(10, presence: joined)
        XCTAssertEqual(plan.state, .on(minutesLeft: 20, remaining: 20.0 / 30))
        XCTAssertEqual(look?.glyph, .ring(remaining: 20.0 / 30))
        XCTAssertEqual(look?.title, "Weekly sync · 20 min left")
        XCTAssertEqual(look?.urgent, false)
        XCTAssertEqual(plan.changes.min(), start.addingTimeInterval(11 * 60), "each minute")
    }

    func testACallBegunAroundItsStartJoinedIt() {
        let inCall = MeetingBar.Presence(microphone: .inUse(since: start.addingTimeInterval(-2 * 60)))
        XCTAssertEqual(at(3, presence: inCall).plan.state, .on(minutesLeft: 27, remaining: 27.0 / 30))
        // The meeting before running over: its call began long before.
        let overRunning = MeetingBar.Presence(microphone: .inUse(since: start.addingTimeInterval(-30 * 60)))
        XCTAssertEqual(at(3, presence: overRunning).plan.state, .started(minutes: 3, late: true))
    }

    func testOneOccurrenceJoinedIsNotTheNext() {
        let tomorrow = AgendaEvent(id: "sync", title: "Weekly sync", start: start.addingTimeInterval(86_400), end: start.addingTimeInterval(86_400 + 1800),
                                   notes: "https://meet.google.com/abc-defg-hij")
        XCTAssertNotEqual(MeetingBar.key(sync), MeetingBar.key(tomorrow))
        XCTAssertFalse(MeetingBar.joined(tomorrow, MeetingBar.Presence(joined: [MeetingBar.key(sync)]), among: [sync, tomorrow]))
    }

    // MARK: - Back to back

    /// A call 9:45–10:00 before Weekly sync at 10:00.
    private func meetingBefore(from minutes: Double, call: Bool = true) -> AgendaEvent {
        AgendaEvent(id: "before", title: "Design review", start: start.addingTimeInterval(minutes * 60), end: start,
                    location: call ? "" : "Room 4", notes: call ? "https://meet.google.com/bef-oreb-efo" : "")
    }

    private func microphone(since minutes: Double) -> MeetingBar.Presence {
        MeetingBar.Presence(microphone: .inUse(since: start.addingTimeInterval(minutes * 60)))
    }

    func testACallJoinedLateInTheMeetingBeforeIsThatOnes() {
        // Joined at 9:51 the 9:45–10:00 call: in the next one's 10 minutes,
        // but the meeting before's.
        let before = meetingBefore(from: -15)
        let late = microphone(since: -9)
        XCTAssertFalse(MeetingBar.joined(sync, late, among: [before, sync, standup]))
        XCTAssertTrue(MeetingBar.joined(before, late, among: [before, sync, standup]), "the meeting before is joined by it")
        // The menu bar says so: at 10:02 the next one started, not joined, red.
        XCTAssertEqual(at(2, [before, sync, standup], presence: late).plan.state, .started(minutes: 2, late: true))
        XCTAssertEqual(at(2, [before, sync, standup], presence: late).look?.urgent, true)
        // Without the meeting before on the calendar, the same call joins it.
        XCTAssertTrue(MeetingBar.joined(sync, late, among: [sync, standup]))
    }

    func testBackToBackTheCallOfTheMeetingBeforeJoinsNothingAfterIt() {
        let before = meetingBefore(from: -30)
        // In it from its start: too long before the next one anyway.
        XCTAssertFalse(MeetingBar.joined(sync, microphone(since: -30), among: [before, sync]))
        // Its call took the microphone again at 9:55, in the next one's 10
        // minutes: still the meeting before's.
        XCTAssertFalse(MeetingBar.joined(sync, microphone(since: -5), among: [before, sync]))
        // Even in its last minute: skil.li cannot tell leaving it early for
        // the next one from staying; skil.li's Join can.
        XCTAssertFalse(MeetingBar.joined(sync, microphone(since: -1), among: [before, sync]))
        XCTAssertTrue(MeetingBar.joined(sync, MeetingBar.Presence(joined: [MeetingBar.key(sync)], microphone: .inUse(since: start.addingTimeInterval(-60))),
                                        among: [before, sync]))
        // Begun as the meeting before ends, or after: the next one's.
        XCTAssertTrue(MeetingBar.joined(sync, microphone(since: 0), among: [before, sync]))
        XCTAssertTrue(MeetingBar.joined(sync, microphone(since: 1), among: [before, sync]))
        XCTAssertEqual(at(3, [before, sync], presence: microphone(since: 1)).plan.state, .on(minutesLeft: 27, remaining: 27.0 / 30))
    }

    func testAMicrophoneTakenWithNoCallBeforeJoinsIt() {
        // 9:58, nothing on before: joined.
        XCTAssertTrue(MeetingBar.joined(sync, microphone(since: -2), among: [sync, standup]))
        // A meeting before without a call, or one over by then: still joined.
        XCTAssertTrue(MeetingBar.joined(sync, microphone(since: -2), among: [meetingBefore(from: -15, call: false), sync]))
        let over = AgendaEvent(id: "over", title: "Earlier call", start: start.addingTimeInterval(-40 * 60), end: start.addingTimeInterval(-5 * 60),
                               notes: "https://meet.google.com/ove-rove-rov")
        XCTAssertTrue(MeetingBar.joined(sync, microphone(since: -2), among: [over, sync]))
        // Two meetings at the same time: the call joins both, neither was on before the other.
        let twin = AgendaEvent(id: "twin", title: "Other sync", start: start, end: start.addingTimeInterval(30 * 60),
                               notes: "https://meet.google.com/twi-ntwi-ntw")
        XCTAssertTrue(MeetingBar.joined(sync, microphone(since: 1), among: [twin, sync]))
        XCTAssertTrue(MeetingBar.joined(twin, microphone(since: 1), among: [twin, sync]))
    }

    // MARK: - The next one beside it

    func testTheNextOneBesideTheTimeLeftIsNotACountdownToIt() {
        let joined = MeetingBar.Presence(joined: [MeetingBar.key(sync)], microphone: .idle)
        let (plan, look) = at(24, presence: joined)
        XCTAssertEqual(plan.next?.id, "standup")
        XCTAssertEqual(look?.title, "6 min left · then Standup \(MeetingBar.clock(standup.start))")
        XCTAssertEqual(look?.glyph, .ring(remaining: 6.0 / 30))
        XCTAssertEqual(look?.help, "Weekly sync ends at \(MeetingBar.clock(sync.end)). Then Standup at \(MeetingBar.clock(standup.start)).")
        // Next off: the meeting alone.
        let alone = MeetingBar.Options(lead: 10, callsOnly: true, countdown: true, hideAfter: 10, nextDuringMeeting: false)
        XCTAssertEqual(at(24, options: alone, presence: joined).look?.title, "Weekly sync · 6 min left")
    }

    func testTheThreeMomentsLookDifferent() {
        let joined = MeetingBar.Presence(joined: [MeetingBar.key(sync)], microphone: .idle)
        let coming = at(-5).look, late = at(2).look, on = at(2, presence: joined).look
        XCTAssertEqual(coming?.glyph, .calendar)
        XCTAssertEqual(late?.glyph, .call)
        if case .ring = on?.glyph {} else { XCTFail("on: the ring, got \(String(describing: on?.glyph))") }
        XCTAssertEqual([coming?.urgent, late?.urgent, on?.urgent], [false, true, false], "only late is red")
        XCTAssertTrue(coming?.title.contains(" in 5 min") == true)
        XCTAssertTrue(late?.title.contains("started 2 min ago") == true)
        XCTAssertTrue(on?.title.contains("28 min left") == true)
    }

    // MARK: - Without the countdown

    func testWithoutTheCountdownJoinedSaysNowThenLeaves() {
        let quiet = MeetingBar.Options(lead: 10, callsOnly: true, countdown: false, hideAfter: 10, nextDuringMeeting: false)
        let joined = MeetingBar.Presence(joined: [MeetingBar.key(sync)], microphone: .idle)
        let (plan, look) = at(4, options: quiet, presence: joined)
        XCTAssertEqual(plan.state, .now)
        XCTAssertEqual(look?.glyph, .call)
        XCTAssertEqual(look?.title, "Weekly sync · now")
        XCTAssertEqual(at(4, options: quiet).plan.state, .started(minutes: 4, late: true), "not joined: still said")
        XCTAssertNil(at(11, options: quiet, presence: joined).plan.shown, "left 10 min after its start")
    }

    func testDismissedOrNeverShowsNothing() {
        var dismissed = MeetingDismissals()
        dismissed.insert(sync)
        XCTAssertNil(MeetingBar.plan([sync], now: start, options: options, presence: idle, dismissed: dismissed).shown)
        let never = MeetingBar.Options(lead: nil, callsOnly: true, countdown: true, hideAfter: 10, nextDuringMeeting: true)
        XCTAssertEqual(MeetingBar.plan([sync], now: start, options: never), MeetingBar.Plan())
    }

    func testDismissedIsThatOccurrenceOnly() {
        var dismissed = MeetingDismissals()
        dismissed.insert(sync)
        let tomorrow = AgendaEvent(id: "sync", title: "Weekly sync", start: start.addingTimeInterval(86_400),
                                   end: start.addingTimeInterval(86_400 + 30 * 60), notes: "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(MeetingBar.plan([tomorrow], now: tomorrow.start, options: options, presence: idle, dismissed: dismissed).shown?.id, "sync",
                       "the next occurrence of a repeating meeting still shows")
    }

    func testDismissedSurvivesAFullSyncByTheServersID() {
        let before = AgendaEvent(id: "local-1", externalID: "server-sync", title: "Weekly sync", start: start, end: start.addingTimeInterval(30 * 60),
                                 notes: "https://meet.google.com/abc-defg-hij")
        let after = AgendaEvent(id: "local-2", externalID: "server-sync", title: "Weekly sync", start: start, end: start.addingTimeInterval(30 * 60),
                                notes: "https://meet.google.com/abc-defg-hij")
        var dismissed = MeetingDismissals()
        dismissed.insert(before)
        XCTAssertTrue(dismissed.contains(after), "a new item id, the same server id and start")
        XCTAssertNil(MeetingBar.plan([after], now: start, options: options, presence: idle, dismissed: dismissed).shown)
        let unsynced = AgendaEvent(id: "local-3", externalID: "", title: "Draft", start: start, end: start.addingTimeInterval(60))
        XCTAssertEqual(MeetingDismissals.key(unsynced), "local-3@\(Int(start.timeIntervalSince1970))", "no server id yet: the item id")
    }

    func testDismissedIsSavedThenForgottenOnceItEnds() throws {
        let suite = "MeetingBarTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var dismissed = MeetingDismissals(defaults: defaults)
        dismissed.insert(sync)
        dismissed.save(to: defaults)
        let relaunched = MeetingDismissals(defaults: defaults)
        XCTAssertTrue(relaunched.contains(sync), "read back from the defaults: a relaunch keeps it")
        XCTAssertEqual(relaunched.refreshed(with: [sync], now: sync.end.addingTimeInterval(-1)), relaunched, "kept while it is on")
        let ended = relaunched.refreshed(with: [sync], now: sync.end)
        XCTAssertTrue(ended.until.isEmpty, "gone at its end")
        ended.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: MeetingDismissals.defaultsKey), "nothing left saved")
    }

    func testDismissedFollowsAMeetingMadeLonger() {
        var dismissed = MeetingDismissals()
        dismissed.insert(sync)
        var longer = sync
        longer.end = sync.end.addingTimeInterval(30 * 60)
        let refreshed = dismissed.refreshed(with: [longer], now: sync.end)
        XCTAssertTrue(refreshed.contains(longer), "still dismissed past its old end")
        XCTAssertNil(MeetingBar.plan([longer], now: sync.end, options: options, presence: idle, dismissed: refreshed).shown)
        XCTAssertTrue(refreshed.refreshed(with: [longer], now: longer.end).until.isEmpty, "gone at its new end")
    }

    func testDismissedBeforeItsFirstSyncStaysOnceItHasAServerID() {
        let local = AgendaEvent(id: "local-1", title: "Weekly sync", start: start, end: start.addingTimeInterval(30 * 60),
                                notes: "https://meet.google.com/abc-defg-hij")
        var synced = local
        synced.externalID = "server-sync"
        var dismissed = MeetingDismissals()
        dismissed.insert(local)
        XCTAssertTrue(dismissed.contains(synced), "the same item id and start")
        let refreshed = dismissed.refreshed(with: [synced], now: start)
        XCTAssertNotNil(refreshed.until[MeetingDismissals.key(synced)], "kept by its server id from then on")
    }

    func testTimeLeftReadsInHoursPastAnHour() {
        XCTAssertEqual(MeetingBar.spoken(minutes: 12), "12 min")
        XCTAssertEqual(MeetingBar.spoken(minutes: 65), "1 h 05")
        XCTAssertEqual(MeetingBar.short("Quarterly planning with the leads", 18), "Quarterly plannin…")
    }
}
