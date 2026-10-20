@testable import SkilliCore
import XCTest

final class MeetingAlertTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var review: AgendaEvent { AgendaEvent(id: "r", title: "Review", start: start, end: start.addingTimeInterval(1800)) }

    func testAnAlertComesItsMinutesBeforeOnce() {
        let alerts = [MeetingAlert(minutes: 5, style: .card)]
        XCTAssertTrue(MeetingAlerts.due([review], alerts: alerts, now: start.addingTimeInterval(-301), shown: []).isEmpty)
        let due = MeetingAlerts.due([review], alerts: alerts, now: start.addingTimeInterval(-300), shown: [])
        XCTAssertEqual(due.map(\.alert), alerts)
        XCTAssertTrue(MeetingAlerts.due([review], alerts: alerts, now: start.addingTimeInterval(-290), shown: Set(due[0].keys)).isEmpty,
                      "shown once")
        XCTAssertTrue(MeetingAlerts.due([review], alerts: alerts, now: start.addingTimeInterval(-200), shown: []).isEmpty,
                      "the Mac asleep at its moment: nothing late")
    }

    func testTwoAtOnceTheClosestAndDarkWin() {
        let alerts = [MeetingAlert(minutes: 10, style: .card), MeetingAlert(minutes: 10, style: .dark)]
        let due = MeetingAlerts.due([review], alerts: alerts, now: start.addingTimeInterval(-600), shown: [])
        XCTAssertEqual(due.first?.alert.style, .dark)
        XCTAssertEqual(due.first?.keys.count, 1, "same minute, one key")
    }

    func testTheNextMomentIsTheEarliestToCome() {
        let alerts = [MeetingAlert(minutes: 10, style: .card), MeetingAlert(minutes: 2, style: .dark)]
        XCTAssertEqual(MeetingAlerts.next([review], alerts: alerts, now: start.addingTimeInterval(-3600)), start.addingTimeInterval(-600))
        XCTAssertEqual(MeetingAlerts.next([review], alerts: alerts, now: start.addingTimeInterval(-500)), start.addingTimeInterval(-120))
        XCTAssertNil(MeetingAlerts.next([review], alerts: alerts, now: start.addingTimeInterval(-60)))
    }

    // MARK: - In the call already

    private var sync: AgendaEvent {
        AgendaEvent(id: "sync", title: "Weekly sync", start: start, end: start.addingTimeInterval(1800), notes: "https://meet.google.com/abc-defg-hij")
    }
    private let onTime = MeetingAlert(minutes: 0, style: .card)
    private let fiveDark = MeetingAlert(minutes: 5, style: .dark)

    private func presence(joined: Bool = false, microphone: MeetingBar.Presence.Microphone = .idle) -> MeetingBar.Presence {
        MeetingBar.Presence(joined: joined ? [MeetingBar.key(sync)] : [], microphone: microphone)
    }

    func testNoAlertForACallJoinedFromSkilli() {
        for alert in [onTime, fiveDark] {
            XCTAssertTrue(MeetingAlerts.shows(alert, for: sync, among: [sync], joining: false, presence: presence()), "not joined: \(alert.id) shows")
            XCTAssertFalse(MeetingAlerts.shows(alert, for: sync, among: [sync], joining: false, presence: presence(joined: true)), "joined: no \(alert.id)")
        }
        // Another occurrence of the same meeting is not joined.
        let tomorrow = AgendaEvent(id: "sync", title: "Weekly sync", start: start.addingTimeInterval(86_400), end: start.addingTimeInterval(86_400 + 1800),
                                   notes: "https://meet.google.com/abc-defg-hij")
        XCTAssertTrue(MeetingAlerts.shows(onTime, for: tomorrow, among: [sync, tomorrow], joining: false, presence: presence(joined: true)))
    }

    func testNoAlertForACallOnTheMicrophoneSinceJustBeforeIt() {
        let justBefore = presence(microphone: .inUse(since: start.addingTimeInterval(-2 * 60)))
        XCTAssertFalse(MeetingAlerts.shows(onTime, for: sync, among: [sync], joining: false, presence: justBefore))
        XCTAssertFalse(MeetingAlerts.shows(fiveDark, for: sync, among: [sync], joining: false, presence: justBefore), "no screens dark either")
        // The meeting before running over: its call began long before.
        let before = presence(microphone: .inUse(since: start.addingTimeInterval(-30 * 60)))
        XCTAssertTrue(MeetingAlerts.shows(onTime, for: sync, among: [sync], joining: false, presence: before))
        XCTAssertTrue(MeetingAlerts.shows(onTime, for: sync, among: [sync], joining: false, presence: presence(microphone: .unknown)), "a Mac that cannot tell alerts")
    }

    func testAnEventWithoutACallAlertsWhateverTheMicrophone() {
        let lunch = AgendaEvent(id: "lunch", title: "Lunch", start: start, end: start.addingTimeInterval(3600), location: "Le Comptoir")
        let inCall = MeetingBar.Presence(joined: [MeetingBar.key(lunch)], microphone: .inUse(since: start.addingTimeInterval(-60)))
        XCTAssertTrue(MeetingAlerts.shows(onTime, for: lunch, among: [lunch], joining: true, presence: inCall))
        XCTAssertFalse(MeetingBar.inCall(lunch, inCall, among: [lunch]), "only a call can be joined")
    }

    func testJoinAtOnceLeavesOnTimeToItself() {
        XCTAssertFalse(MeetingAlerts.shows(onTime, for: sync, among: [sync], joining: true, presence: presence()))
        XCTAssertTrue(MeetingAlerts.shows(fiveDark, for: sync, among: [sync], joining: true, presence: presence()))
        XCTAssertFalse(MeetingAlerts.shows(fiveDark, for: sync, among: [sync], joining: true, presence: presence(joined: true)))
    }

    func testJoinAtOnceSkipsACallJoinedAlready() {
        XCTAssertTrue(MeetingAlerts.joinsAtOnce(sync, among: [sync], presence: presence()))
        XCTAssertTrue(MeetingAlerts.joinsAtOnce(sync, among: [sync], presence: presence(microphone: .unknown)))
        XCTAssertFalse(MeetingAlerts.joinsAtOnce(sync, among: [sync], presence: presence(joined: true)), "joined from skil.li: not opened again")
        XCTAssertFalse(MeetingAlerts.joinsAtOnce(sync, among: [sync], presence: presence(microphone: .inUse(since: start.addingTimeInterval(-60)))),
                       "on the microphone since just before")
        XCTAssertTrue(MeetingAlerts.joinsAtOnce(sync, among: [sync], presence: presence(microphone: .inUse(since: start.addingTimeInterval(-40 * 60)))),
                      "a call from before is another one")
        XCTAssertFalse(MeetingAlerts.joinsAtOnce(review, among: [review], presence: presence()), "nothing to join without a call")
    }

    func testTheCallOfTheMeetingBeforeSilencesNothingAfterIt() {
        // A 9:45–10:00 call joined late, at 9:51: the 10:00 one still alerts
        // and is still joined at once.
        let before = AgendaEvent(id: "before", title: "Design review", start: start.addingTimeInterval(-15 * 60), end: start,
                                 notes: "https://meet.google.com/bef-oreb-efo")
        let late = presence(microphone: .inUse(since: start.addingTimeInterval(-9 * 60)))
        XCTAssertTrue(MeetingAlerts.shows(onTime, for: sync, among: [before, sync], joining: false, presence: late))
        XCTAssertTrue(MeetingAlerts.shows(fiveDark, for: sync, among: [before, sync], joining: false, presence: late))
        XCTAssertTrue(MeetingAlerts.joinsAtOnce(sync, among: [before, sync], presence: late))
        XCTAssertFalse(MeetingBar.inCall(sync, late, among: [before, sync]), "a card up for it stays")
        // 9:58 with nothing before: in it, no alert, not joined again.
        let plain = presence(microphone: .inUse(since: start.addingTimeInterval(-2 * 60)))
        XCTAssertFalse(MeetingAlerts.shows(onTime, for: sync, among: [sync], joining: false, presence: plain))
        XCTAssertFalse(MeetingAlerts.joinsAtOnce(sync, among: [sync], presence: plain))
        // skil.li's own Join for it counts whatever was on before.
        XCTAssertFalse(MeetingAlerts.shows(onTime, for: sync, among: [before, sync], joining: false,
                                           presence: presence(joined: true, microphone: .inUse(since: start.addingTimeInterval(-9 * 60)))))
    }

    func testAnAlertUpGoesOnceTheUserIsInTheCall() {
        // A card up 5 min before: not in the call yet, then the microphone
        // taken before the start or after it, or Join.
        XCTAssertFalse(MeetingBar.inCall(sync, presence(), among: [sync]))
        XCTAssertTrue(MeetingBar.inCall(sync, presence(microphone: .inUse(since: start.addingTimeInterval(-3 * 60))), among: [sync]))
        XCTAssertTrue(MeetingBar.inCall(sync, presence(microphone: .inUse(since: start.addingTimeInterval(2 * 60))), among: [sync]))
        XCTAssertTrue(MeetingBar.inCall(sync, presence(joined: true), among: [sync]))
    }

    func testTheChoicesSaid() {
        XCTAssertEqual(MeetingAlert.spoken(60), "1 hour before")
        XCTAssertEqual(MeetingAlert.spoken(2), "2 min before")
        XCTAssertEqual(MeetingAlert.spoken(0), "On time")
    }
}
