@testable import SkilliCore
import CoreGraphics
import XCTest

final class PictureTimelineTests: XCTestCase {
    func testPicturesTakeTheSoundsCuts() {
        var timeline = PictureTimeline(start: 100)
        XCTAssertNil(timeline.place(99.9), "before the start")
        XCTAssertEqual(timeline.placeHeld(at: 100), 0, "the picture on screen at the start goes at 0")
        XCTAssertEqual(timeline.place(100.5)!, 0.5, accuracy: 1e-9)
        timeline.pause(at: 101)
        XCTAssertNil(timeline.place(103), "paused: nothing written")
        timeline.resume(at: 105)
        XCTAssertEqual(timeline.placeHeld(at: 105)!, 1, accuracy: 1e-9, "the picture held over the pause goes where recording goes on")
        XCTAssertEqual(timeline.place(105.25)!, 1.25, accuracy: 1e-9, "the pause cut out, as from the sound")
        XCTAssertEqual(timeline.finish(at: 106), 2, accuracy: 1e-9, "the file ends at the stop")
        XCTAssertNil(timeline.place(106.1), "after the stop")
        XCTAssertNil(timeline.place(105.99 - 0.0001 + 0.02), "after the stop's file time")
    }

    func testTimesAlwaysRise() {
        var timeline = PictureTimeline(start: 0)
        XCTAssertEqual(timeline.place(1), 1)
        let next = timeline.place(1)!
        XCTAssertGreaterThan(next, 1, "two pictures at one moment: the later just after")
        XCTAssertNil(timeline.placeHeld(at: 0.5), "a held picture never goes back in time")
    }

    func testAPauseAtTheStopEndsTheFileWhereItBegan() {
        var timeline = PictureTimeline(start: 10)
        timeline.pause(at: 12)
        XCTAssertEqual(timeline.finish(at: 20), 2, accuracy: 1e-9)
        XCTAssertNil(timeline.placeHeld(at: 20))
    }

    func testThePicturesAndTheSoundCutAtTheSameMoments() {
        // The sound's timeline and the pictures' agree on every moment.
        var sound = TrackTimeline(rate: 48000, start: 50)
        var pictures = PictureTimeline(start: 50)
        for (pause, resume) in [(60.0, 75.0), (90.0, 90.5)] {
            sound.pause(at: pause)
            pictures.pause(at: pause)
            sound.resume(at: resume)
            pictures.resume(at: resume)
        }
        for moment in [55.0, 61.0, 80.0, 95.0] {
            XCTAssertEqual(sound.fileTime(of: moment), pictures.fileTime(of: moment), accuracy: 1e-9)
        }
    }
}

final class WindowCoverTests: XCTestCase {
    private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

    func testNothingInFrontLeavesItAllInSight() {
        XCTAssertEqual(WindowCover.visibleFraction(of: window, under: []), 1)
        XCTAssertEqual(WindowCover.visibleFraction(of: window, under: [CGRect(x: 0, y: 0, width: 50, height: 50)]), 1, "elsewhere on screen")
    }

    func testHalfCovered() {
        let half = CGRect(x: 100, y: 100, width: 200, height: 300)
        XCTAssertEqual(WindowCover.visibleFraction(of: window, under: [half]), 0.5, accuracy: 1e-9)
    }

    func testCoveredWholeBySeveralWindows() {
        let left = CGRect(x: 50, y: 50, width: 260, height: 400)
        let right = CGRect(x: 300, y: 80, width: 300, height: 340)
        XCTAssertEqual(WindowCover.visibleFraction(of: window, under: [left, right]), 0)
    }

    func testOverlappingWindowsAreCountedOnce() {
        let one = CGRect(x: 100, y: 100, width: 200, height: 150)
        let same = one.insetBy(dx: 20, dy: 20)
        XCTAssertEqual(WindowCover.visibleFraction(of: window, under: [one, same]), 0.75, accuracy: 1e-9)
    }

    func testAStripLeftInSight() {
        let almost = CGRect(x: 100, y: 100, width: 396, height: 300)
        XCTAssertEqual(WindowCover.visibleFraction(of: window, under: [almost]), 0.01, accuracy: 1e-9)
    }
}

final class PictureWatchTests: XCTestCase {
    func testAWindowInSightIsFineEvenStill() {
        var watch = PictureWatch()
        XCTAssertNil(watch.update(.init(), lastPicture: 0, now: 0))
        XCTAssertNil(watch.update(.init(), lastPicture: 0, now: 60), "a still slide in sight is no failure")
    }

    func testMinimizedHiddenAndOffScreenAreSaidAfterASecond() {
        var watch = PictureWatch()
        XCTAssertNil(watch.update(.init(onScreen: false, minimized: true), lastPicture: 0, now: 10))
        XCTAssertEqual(watch.update(.init(onScreen: false, minimized: true), lastPicture: 0, now: 11), .minimized)
        XCTAssertNil(watch.update(.init(), lastPicture: 12, now: 12), "back on screen: said no more")
        _ = watch.update(.init(onScreen: false, appHidden: true), lastPicture: 12, now: 13)
        XCTAssertEqual(watch.update(.init(onScreen: false, appHidden: true), lastPicture: 12, now: 14.2), .hidden)
        var other = PictureWatch()
        _ = other.update(.init(onScreen: false), lastPicture: 0, now: 0)
        XCTAssertEqual(other.update(.init(onScreen: false), lastPicture: 0, now: 1), .offScreen)
    }

    func testCoveredWholeIsAProblemOnlyWithoutNewPictures() {
        var watch = PictureWatch()
        // Arc keeps painting under another window.
        for second in 0...10 {
            XCTAssertNil(watch.update(.init(coveredWhole: true), lastPicture: Double(second), now: Double(second)))
        }
        // Chrome stops: the same picture, five seconds after it was covered.
        var chrome = PictureWatch()
        XCTAssertNil(chrome.update(.init(coveredWhole: true), lastPicture: -30, now: 0), "the last picture came long before it was covered")
        XCTAssertNil(chrome.update(.init(coveredWhole: true), lastPicture: -30, now: 4.9))
        XCTAssertEqual(chrome.update(.init(coveredWhole: true), lastPicture: -30, now: 5), .stoppedPainting)
        chrome.pictured()
        XCTAssertNil(chrome.problem, "a new picture: painting again")
        XCTAssertEqual(chrome.update(.init(coveredWhole: true), lastPicture: 5.5, now: 11), .stoppedPainting)
        XCTAssertNil(chrome.update(.init(), lastPicture: 5.5, now: 12), "uncovered: in sight again, even with the same picture")
    }

    func testAWindowWhoseStreamStoppedIsClosedAtOnce() {
        var watch = PictureWatch()
        watch.closed()
        XCTAssertEqual(watch.problem, .closed)
    }

    func testAWindowGoneIsClosed() {
        var watch = PictureWatch()
        _ = watch.update(.init(exists: false), lastPicture: 0, now: 0)
        XCTAssertEqual(watch.update(.init(exists: false), lastPicture: 0, now: 1), .closed)
        XCTAssertEqual(PictureWatch.line(.closed, app: "Google Chrome"), "the window closed: pick another")
        XCTAssertEqual(PictureWatch.line(.minimized, app: "Google Chrome"), "Google Chrome is minimized: nothing recorded until it's back")
    }
}

final class SlideScheduleTests: XCTestCase {
    private func grid(_ value: UInt8, changing share: Double = 1, from base: UInt8 = 0) -> [UInt8] {
        let count = SlideSchedule.columns * SlideSchedule.rows
        let changed = Int(Double(count) * share)
        return (0..<count).map { $0 < changed ? value : base }
    }

    func testTheFirstPictureIsReadAtOnce() {
        var schedule = SlideSchedule()
        XCTAssertEqual(schedule.sample(grid(0), at: 0), 0)
    }

    func testASlideIsReadWithinASecondAndTimedAtItsChange() {
        var schedule = SlideSchedule()
        _ = schedule.sample(grid(0), at: 0)
        schedule.read(grid(0), at: 0, foundNew: true)
        XCTAssertNil(schedule.sample(grid(0), at: 0.25), "nothing changed")
        XCTAssertNil(schedule.sample(grid(200), at: 0.5), "changed, but read a moment ago")
        XCTAssertNil(schedule.sample(grid(200), at: 0.75))
        XCTAssertEqual(schedule.sample(grid(200), at: 1.0), 0.5, "read once a second at most, timed when the picture changed")
    }

    func testOnlyTheTextChangingIsAChange() {
        var schedule = SlideSchedule()
        _ = schedule.sample(grid(0), at: 0)
        schedule.read(grid(0), at: 0, foundNew: true)
        // A line of text: 3 % of the grid's cells.
        XCTAssertEqual(schedule.sample(grid(60, changing: 0.03), at: 1.25), 1.25)
        // A corner's clock: a few cells.
        var still = SlideSchedule()
        _ = still.sample(grid(0), at: 0)
        still.read(grid(0), at: 0, foundNew: true)
        XCTAssertNil(still.sample(grid(60, changing: 0.004), at: 1.25))
    }

    func testAMovingVideoIsReadEveryTwoSeconds() {
        var schedule = SlideSchedule()
        var time = 0.0
        var readings: [Double] = []
        var value: UInt8 = 0
        while time < 30 {
            value = value == 0 ? 100 : 0
            let picture = grid(value, changing: 0.1)
            if schedule.sample(picture, at: time) != nil {
                readings.append(time)
                schedule.read(picture, at: time, foundNew: false)
            }
            time += SlideSchedule.sampleEvery
        }
        let gaps = zip(readings.dropFirst(), readings).map { $0 - $1 }
        XCTAssertEqual(gaps.max() ?? 0, SlideSchedule.latest, accuracy: 0.26, "never more than two seconds apart")
    }

    func testAChangeSeenWhileAReadingRanIsKept() {
        var schedule = SlideSchedule()
        _ = schedule.sample(grid(0), at: 0)
        schedule.read(grid(0), at: 0, foundNew: true)
        // Read at 1.0; the slide changes at 1.25 while it is being read.
        _ = schedule.sample(grid(50, changing: 0.05), at: 1.0)
        _ = schedule.sample(grid(200, changing: 0.05), at: 1.25)
        schedule.read(grid(50, changing: 0.05), at: 1.0, foundNew: false)
        XCTAssertEqual(schedule.sample(grid(200, changing: 0.05), at: 3.0), 1.25, "timed at its change, not at the next reading")
    }

    func testASlideAfterAFlashIsTimedWithinTheReadingsInterval() {
        var schedule = SlideSchedule()
        _ = schedule.sample(grid(0), at: 0)
        schedule.read(grid(0), at: 0, foundNew: true)
        // A white flash at 0.25, gone at 0.5; the slide at 0.75.
        _ = schedule.sample(grid(255), at: 0.25)
        _ = schedule.sample(grid(0), at: 0.5)
        _ = schedule.sample(grid(90, changing: 0.05), at: 0.75)
        XCTAssertEqual(schedule.sample(grid(90, changing: 0.05), at: 1.0), 0.75, "the last change, not the flash")
    }
}

final class SlideLogTests: XCTestCase {
    func testNewLinesAreASlide() {
        var log = SlideLog()
        XCTAssertEqual(log.read(["Meet", "Q3 review", "Lumière"], at: 2)?.lines, ["Meet", "Q3 review", "Lumière"])
        XCTAssertNil(log.read(["Meet", "Q3 review", "Lumière"], at: 3), "nothing new")
        let next = log.read(["Meet", "Budget 2027", "Revenue up 12 %"], at: 10)
        XCTAssertEqual(next, SlideLog.Slide(start: 10, lines: ["Budget 2027", "Revenue up 12 %"]))
    }

    func testALineReadAgainIsNotNew() {
        var log = SlideLog()
        log.read(["Q3 review", "Revenue up 12 %"], at: 0)
        XCTAssertNil(log.read(["Q3 review"], at: 1), "a line missed once")
        XCTAssertNil(log.read(["Q3 review", "Revenue up 12%"], at: 2), "read again, a space aside")
        XCTAssertNil(log.read(["Q3  REVIEW", "revenue up 12 %"], at: 3))
    }

    func testTheWindowsOwnLinesAreTakenOut() {
        var log = SlideLog()
        log.read(["Meet - abc-defg-hij", "Leave call", "Welcome"], at: 0)
        for second in 1...20 { log.read(["Meet - abc-defg-hij", "Leave call", second < 10 ? "Welcome" : "Agenda"], at: Double(second)) }
        let kept = log.kept()
        XCTAssertEqual(kept.map(\.lines), [["Welcome"], ["Agenda"]], "the tab's and the call's buttons are not a slide")
        XCTAssertEqual(kept.map(\.start), [0, 10])
    }

    func testLinesWithoutWordsAreNoText() {
        var log = SlideLog()
        XCTAssertEqual(log.read(["•", "|", "A", "OK", "12:04", "28", "Revenue up 12 %"], at: 0)?.lines, ["OK", "Revenue up 12 %"])
    }

    func testSlidesRoundTripAsJSON() throws {
        let slides = [SlideLog.Slide(start: 75.4, lines: ["Q3 review", "Revenue up 12 %"])]
        XCTAssertEqual(try SlideLog.decode(SlideLog.encoded(slides)), slides)
        let text = String(data: try SlideLog.encoded(slides), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"start\" : 75.4"), text)
    }
}

final class MeetingTabTests: XCTestCase {
    private func tab(_ url: String, window: Int = 1, index: Int = 1, active: Bool = false) -> Quicklink.OpenTab {
        Quicklink.OpenTab(window: window, index: index, url: url, active: active)
    }

    func testMeetIsToldByItsCode() {
        let link = URL(string: "https://meet.google.com/abc-defg-hij")!
        let tabs = [tab("https://meet.google.com/xyz-abcd-efg", index: 1), tab("https://meet.google.com/abc-defg-hij?authuser=0", index: 2),
                    tab("https://mail.google.com/mail/u/0/", index: 3)]
        XCTAssertEqual(MeetingTab.find(link, among: tabs)?.index, 2)
        XCTAssertNil(MeetingTab.find(link, among: [tabs[0]]), "another meeting on the same site is not this one")
    }

    func testZoomInTheBrowserIsToldByItsNumber() {
        let link = URL(string: "https://us02web.zoom.us/j/81234567890?pwd=abc")!
        let joined = tab("https://app.zoom.us/wc/81234567890/join?fromPWA=1", index: 4)
        XCTAssertEqual(MeetingTab.find(link, among: [tab("https://zoom.us/", index: 1), joined])?.index, 4)
    }

    func testTeamsIsToldByItsThread() {
        let link = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZTk5NjQ%40thread.v2/0?context=%7b%7d")!
        let joined = tab("https://teams.microsoft.com/v2/?meetingjoin=true#/l/meetup-join/19:meeting_ZTk5NjQ@thread.v2/0", index: 2)
        XCTAssertEqual(MeetingTab.find(link, among: [tab("https://teams.microsoft.com/v2/", index: 1), joined])?.index, 2)
    }

    func testElsewhereThePageItself() {
        let link = URL(string: "https://whereby.com/lumiere-weekly")!
        XCTAssertEqual(MeetingTab.find(link, among: [tab("https://whereby.com/lumiere-weekly/", index: 3)])?.index, 3)
        XCTAssertNil(MeetingTab.find(link, among: [tab("https://whereby.com/other-room")]))
        XCTAssertNil(MeetingTab.room(URL(string: "https://whereby.com/")!), "a site's home is no meeting")
    }

    func testTheTabInFrontFirst() {
        let link = URL(string: "https://meet.google.com/abc-defg-hij")!
        let tabs = [tab("https://meet.google.com/abc-defg-hij", window: 1, index: 3), tab("https://meet.google.com/abc-defg-hij", window: 2, index: 1, active: true)]
        XCTAssertEqual(MeetingTab.find(link, among: tabs)?.window, 2)
    }
}

final class MeetingMomentPicturesTests: XCTestCase {
    func testTheWebcamAndTheScreenFollowTheSettingsNeverTheCase() {
        let call = MicrophoneApp(bundleID: "us.zoom.xos", name: "zoom.us", pid: 12)
        let defaults = MeetingMoment.Sources(microphone: true, macSound: true, webcam: true, screen: true)
        let reading = MeetingMoment.read(event: nil, microphone: MicrophoneHolders(apps: [call]), defaults: defaults)
        XCTAssertEqual(reading.sources, defaults, "a call: both sounds, the pictures as set")
        let off = MeetingMoment.read(event: nil, microphone: MicrophoneHolders(apps: [call]))
        XCTAssertEqual(off.sources, .both, "off by default")
        XCTAssertFalse(off.sources.webcam || off.sources.screen)
    }

    func testInPersonTheScreenStaysOff() {
        let now = Date(timeIntervalSince1970: 1_792_670_400)
        let room = AgendaEvent(id: "e2", title: "Budget review", start: now, end: now.addingTimeInterval(1800), isAllDay: false,
                               location: "Salle Horizon, 3e étage", notes: "", url: nil, attendees: [], declined: false)
        let defaults = MeetingMoment.Sources(microphone: true, macSound: true, webcam: true, screen: true)
        let reading = MeetingMoment.read(event: room, microphone: .none, defaults: defaults)
        XCTAssertEqual(reading.kind, .inPerson)
        XCTAssertEqual(reading.sources, MeetingMoment.Sources(microphone: true, macSound: false, webcam: true, screen: false),
                       "no call's window to record; the webcam as set")
    }
}
