@testable import SkilliCore
import XCTest

final class RecordingFolderTests: XCTestCase {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testTheFolderIsTheDateThenTheTitle() {
        let started = date("2026-10-22T12:00:00Z")
        XCTAssertEqual(RecordingFolder.name(title: "Weekly sync", started: started, calendar: paris), "2026-10-22 14.00 Weekly sync")
        XCTAssertEqual(RecordingFolder.name(title: "", started: date("2026-01-05T08:07:00Z"), calendar: paris), "2026-01-05 09.07 Meeting")
    }

    func testATitleBecomesAFolderName() {
        XCTAssertEqual(RecordingFolder.cleaned("Budget 2026/2027: review"), "Budget 2026-2027- review")
        XCTAssertEqual(RecordingFolder.cleaned("Point\tbudget\nsuite"), "Point budget suite", "a line break or a tab keeps words apart")
        XCTAssertEqual(RecordingFolder.cleaned("Bell\u{07}ring\u{0}"), "Bellring", "other control characters go")
        XCTAssertEqual(RecordingFolder.cleaned(".hidden"), "hidden", "never a hidden folder")
        XCTAssertEqual(RecordingFolder.cleaned("  ..  dots"), "dots")
        XCTAssertEqual(RecordingFolder.cleaned("Réunion   d'équipe  "), "Réunion d'équipe")
        XCTAssertEqual(RecordingFolder.cleaned(""), "Meeting")
        XCTAssertEqual(RecordingFolder.cleaned(" / "), "-")
        XCTAssertEqual(RecordingFolder.cleaned("..."), "Meeting")
    }

    func testALongTitleIsCutAtEightyCharacters() {
        let long = String(repeating: "Comité ", count: 20)
        let cut = RecordingFolder.cleaned(long)
        XCTAssertLessThanOrEqual(cut.count, 80)
        XCTAssertFalse(cut.hasSuffix(" "))
        XCTAssertTrue(long.hasPrefix(cut))
        XCTAssertEqual(RecordingFolder.cleaned(String(repeating: "é", count: 100)).count, 80, "characters, not bytes")
    }

    func testANameTakenGetsANumber() {
        var taken: Set<String> = []
        XCTAssertEqual(RecordingFolder.free("2026-10-22 14.00 Weekly sync") { taken.contains($0) }, "2026-10-22 14.00 Weekly sync")
        taken = ["2026-10-22 14.00 Weekly sync"]
        XCTAssertEqual(RecordingFolder.free("2026-10-22 14.00 Weekly sync") { taken.contains($0) }, "2026-10-22 14.00 Weekly sync 2")
        taken.insert("2026-10-22 14.00 Weekly sync 2")
        XCTAssertEqual(RecordingFolder.free("2026-10-22 14.00 Weekly sync") { taken.contains($0) }, "2026-10-22 14.00 Weekly sync 3")
    }

    func testARecordingNobodyNamedIsNamedByItsTime() {
        let title = RecordingFolder.defaultTitle(at: date("2026-10-22T12:30:00Z"), locale: Locale(identifier: "fr_FR"),
                                                 timeZone: TimeZone(identifier: "Europe/Paris")!)
        XCTAssertEqual(title, "Meeting 14:30")
    }
}

final class RecordRequestTests: XCTestCase {
    func testRecThenANameNamesTheRecording() {
        XCTAssertEqual(RecordRequest.name("rec Weekly sync"), "Weekly sync")
        XCTAssertEqual(RecordRequest.name("REC  Point budget "), "Point budget")
        XCTAssertNil(RecordRequest.name("rec"), "alone: Record Meeting found by its name")
        XCTAssertNil(RecordRequest.name("rec "))
        XCTAssertNil(RecordRequest.name("recipe"))
        XCTAssertNil(RecordRequest.name("record meeting"))
    }

    func testTheWordsAboutARecording() {
        for text in ["rec", "rec weekly", "reco", "record", "recording", "Enregistrement", "enregistrer", "stop rec"] {
            XCTAssertTrue(RecordRequest.mentions(text), text)
        }
        for text in ["re", "recipe", "recent", "rect", "music", "enr"] {
            XCTAssertFalse(RecordRequest.mentions(text), text)
        }
    }
}

final class MeetingRecordTests: XCTestCase {
    func testItIsReadBackAsWritten() throws {
        var record = MeetingRecord(title: "Weekly sync", started: Date(timeIntervalSince1970: 1_792_000_000), language: "en-US",
                                   recorder: .init(pid: 4242, launched: Date(timeIntervalSince1970: 1_791_999_000)))
        record.seconds = 1925.5
        record.pauses = [.init(at: 600, seconds: 30)]
        record.state = .done
        record.engine = "SpeechTranscriber"
        let back = try MeetingRecord.decode(try record.encoded())
        XCTAssertEqual(back, record)
        XCTAssertEqual(back.speakers, ["me": "Me", "them": "Them"])
        let json = String(decoding: try record.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"title\" : \"Weekly sync\""), json)
    }

    func testATranscribeAgainLeftAtTheQuitIsReadBack() throws {
        var record = MeetingRecord(title: "Weekly sync", started: Date(timeIntervalSince1970: 0), language: "en-US", recorder: nil)
        record.state = .done
        XCTAssertNil(try MeetingRecord.decode(try record.encoded()).madeAgain, "none asked")
        record.madeAgain = .init(language: "fr-FR", engine: "whisper")
        let back = try MeetingRecord.decode(try record.encoded())
        XCTAssertEqual(back.madeAgain, .init(language: "fr-FR", engine: "whisper"))
        XCTAssertEqual(back.language, "en-US", "the transcript there is still the one before")
        let older = String(decoding: try record.encoded(), as: UTF8.self)
            .replacingOccurrences(of: #""madeAgain" : \{[^}]*\},?"#, with: "", options: .regularExpression)
        XCTAssertNil(try MeetingRecord.decode(Data(older.utf8)).madeAgain, "a meeting.json from before reads")
    }

    func testWhyATranscriptFailedIsKept() throws {
        var record = MeetingRecord(title: "Weekly sync", started: Date(timeIntervalSince1970: 0), language: "it-IT", recorder: nil)
        record.state = .pending
        record.failed = "Italian can't be transcribed on this Mac yet."
        XCTAssertEqual(try MeetingRecord.decode(try record.encoded()).failed, "Italian can't be transcribed on this Mac yet.")
    }

    func testATranscriptKeepsTheRunsThatFinishedWhileItWasMade() {
        var made = MeetingRecord(title: "Weekly sync", started: Date(timeIntervalSince1970: 0), language: "en-US", recorder: nil)
        made.state = .done
        let ran = MeetingRecord.SkillieRun(title: "Keep the Folder", path: "/skillies/keep.sh", at: Date(timeIntervalSince1970: 60),
                                           automatic: false, status: 0, line: "Kept.")
        var onDisk = made
        onDisk.state = .transcribing
        onDisk.skillies = [ran]
        let kept = made.keepingRuns(of: onDisk)
        XCTAssertEqual(kept.skillies, [ran])
        XCTAssertEqual(kept.state, .done, "the rest is the transcript's")
        XCTAssertEqual(made.keepingRuns(of: nil), made, "nothing on disk: as made")
        made.skillies = [ran]
        onDisk.skillies = nil
        XCTAssertEqual(made.keepingRuns(of: onDisk).skillies, [ran], "none on disk: its own kept")
    }

    func testOneNeverStoppedIsUnfinishedOnceItsRecorderIsGone() {
        let owner = MeetingRecord.Owner(pid: 4242, launched: Date(timeIntervalSince1970: 100))
        var record = MeetingRecord(title: "Weekly sync", started: .now, language: "en-US", recorder: owner)
        XCTAssertFalse(record.isUnfinished { $0 == owner }, "still being recorded")
        XCTAssertTrue(record.isUnfinished { _ in false }, "skil.li quit or crashed")
        let reused = MeetingRecord.Owner(pid: 4242, launched: Date(timeIntervalSince1970: 200))
        XCTAssertTrue(record.isUnfinished { $0 == reused }, "another process got its number")
        record.state = .paused
        XCTAssertTrue(record.isUnfinished { _ in false })
        record.state = .transcribing
        XCTAssertTrue(record.isUnfinished { _ in false }, "stopped, its transcript never finished")
        record.state = .done
        XCTAssertFalse(record.isUnfinished { _ in false })
        record.state = .pending
        XCTAssertFalse(record.isUnfinished { _ in false })
        record.state = .recording
        record.recorder = nil
        XCTAssertTrue(record.isUnfinished { _ in true })
    }

    func testOneClosedAsSkilliQuitIsNotUnfinished() throws {
        // Its files whole, its transcript waits for the next launch: nothing
        // to offer (Save, Later, Discard is for a crash or a power cut).
        var record = MeetingRecord(title: "Weekly sync", started: .now, language: "en-US", recorder: nil)
        record.state = .stopped
        XCTAssertFalse(record.isUnfinished { _ in false })
        let read = try MeetingRecord.decode(record.encoded())
        XCTAssertEqual(read.state, .stopped)
        XCTAssertTrue(String(decoding: try record.encoded(), as: UTF8.self).contains(#""state" : "stopped""#))
    }
}

final class TrackTimelineTests: XCTestCase {
    /// Places buffers of `size` frames, one after another from `sampleTime`
    /// and `hostTime`, and returns what went in the file.
    private func feed(_ timeline: inout TrackTimeline, sampleTime: Double, hostTime: Double, buffers: Int, size: Int) -> [TrackTimeline.Piece] {
        (0..<buffers).flatMap { index in
            timeline.place(sampleTime: sampleTime + Double(index * size), hostTime: hostTime + Double(index * size) / timeline.rate, frames: size)
        }
    }

    private func length(_ pieces: [TrackTimeline.Piece]) -> Int {
        pieces.reduce(0) { total, piece in
            switch piece {
            case .silence(let count): total + count
            case .frames(let range): total + range.count
            }
        }
    }

    func testBuffersInARowFollowEachOther() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        let pieces = feed(&timeline, sampleTime: 5000, hostTime: 10, buffers: 3, size: 10)
        XCTAssertEqual(pieces, [.frames(0..<10), .frames(0..<10), .frames(0..<10)])
        XCTAssertEqual(timeline.written, 30)
    }

    func testAMissedCycleIsSilenceOfItsLength() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        _ = timeline.place(sampleTime: 0, hostTime: 10, frames: 10)
        // The next two cycles never came: the third is 20 frames later.
        let pieces = timeline.place(sampleTime: 30, hostTime: 10.3, frames: 10)
        XCTAssertEqual(pieces, [.silence(20), .frames(0..<10)])
        XCTAssertEqual(timeline.written, 40)
    }

    func testTheDevicesClockPlacesARunNotTheHosts() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        _ = timeline.place(sampleTime: 0, hostTime: 10, frames: 10)
        // The host says 50 ms late (a busy thread), the sample time says in a row.
        XCTAssertEqual(timeline.place(sampleTime: 10, hostTime: 10.15, frames: 10), [.frames(0..<10)])
    }

    func testFramesBeforeTheStartAreLeftOut() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        // The card was open: the source ran before ↩.
        XCTAssertEqual(timeline.place(sampleTime: 0, hostTime: 9.85, frames: 10), [])
        XCTAssertEqual(timeline.place(sampleTime: 10, hostTime: 9.95, frames: 10), [.frames(5..<10)])
        XCTAssertEqual(timeline.written, 5)
    }

    func testATrackThatStartsLateBeginsWithSilence() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        // The microphone's first buffer came 120 ms after the start.
        XCTAssertEqual(timeline.place(sampleTime: 0, hostTime: 10.12, frames: 10), [.silence(12), .frames(0..<10)])
    }

    func testAPauseIsCutFromEveryTrackAtTheSameMoment() {
        // Two tracks, other rates, other buffer sizes, other sample times.
        var mic = TrackTimeline(rate: 100, start: 10)
        var mac = TrackTimeline(rate: 160, start: 10)
        mic.pause(at: 10.505)
        mac.pause(at: 10.505)
        mic.resume(at: 12.0)
        mac.resume(at: 12.0)
        mic.finish(at: 13.0)
        mac.finish(at: 13.0)
        _ = feed(&mic, sampleTime: 777, hostTime: 9.9, buffers: 40, size: 8)
        _ = feed(&mac, sampleTime: 31, hostTime: 9.95, buffers: 40, size: 16)
        // 0.505 s before the pause, 1 s after it: 1.505 s each.
        XCTAssertEqual(Double(mic.written) / mic.rate, 1.51, accuracy: 0.011)
        XCTAssertEqual(Double(mac.written) / mac.rate, 1.505, accuracy: 0.007)
        XCTAssertEqual(mic.fileTime(of: 12.5), 1.005, accuracy: 1e-9)
        XCTAssertEqual(mac.fileTime(of: 11.0), 0.505, accuracy: 1e-9, "inside the pause: where it was cut")
    }

    func testEachResumeSaysHowFarTheRunMoved() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        timeline.pause(at: 10.2)
        timeline.resume(at: 11)
        _ = timeline.place(sampleTime: 0, hostTime: 10, frames: 10)
        // The device's clock ran fast: 12 frames by 10.1 s instead of 10.
        _ = timeline.place(sampleTime: 10, hostTime: 10.08, frames: 12)
        _ = timeline.place(sampleTime: 22, hostTime: 11, frames: 10)
        XCTAssertEqual(timeline.resumeJumps, [-2], "two frames left out to be in place again")
    }

    func testAPauseInsideABufferKeepsWhatCameBefore() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        timeline.pause(at: 10.05)
        XCTAssertEqual(timeline.place(sampleTime: 0, hostTime: 10, frames: 10), [.frames(0..<5)])
        XCTAssertTrue(timeline.isPaused)
        timeline.resume(at: 10.5)
        XCTAssertFalse(timeline.isPaused)
        // Resumed inside a buffer: from its first frame after it, placed
        // right after what was kept, not by the sample time.
        XCTAssertEqual(timeline.place(sampleTime: 47, hostTime: 10.47, frames: 10), [.frames(3..<10)])
        XCTAssertEqual(timeline.written, 12)
    }

    func testAnEngineStartedAgainIsPlacedByTheHostClock() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        _ = timeline.place(sampleTime: 4000, hostTime: 10, frames: 10)
        // The audio setup changed: the engine stopped, started again with a
        // sample time of its own, 300 ms later.
        timeline.restarted()
        XCTAssertEqual(timeline.place(sampleTime: 0, hostTime: 10.4, frames: 10), [.silence(30), .frames(0..<10)])
        XCTAssertEqual(timeline.written, 50)
    }

    func testASampleTimeThatJumpsFarIsANewTimeline() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        _ = timeline.place(sampleTime: 0, hostTime: 10, frames: 10)
        // A device that started over without a word: by the host clock.
        XCTAssertEqual(timeline.place(sampleTime: 90_000, hostTime: 10.1, frames: 10), [.frames(0..<10)])
    }

    func testNothingAfterTheStop() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        timeline.finish(at: 10.15)
        XCTAssertEqual(length(feed(&timeline, sampleTime: 0, hostTime: 10, buffers: 3, size: 10)), 15)
        XCTAssertEqual(timeline.written, 15)
        XCTAssertEqual(timeline.place(sampleTime: 30, hostTime: 10.3, frames: 10), [])
    }

    func testATrackWhoseDeviceWentAwayEndsWithTheOthers() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        XCTAssertNil(timeline.tail(), "not stopped yet")
        _ = timeline.place(sampleTime: 0, hostTime: 10, frames: 50)
        timeline.pause(at: 11)
        timeline.resume(at: 12)
        timeline.finish(at: 13)
        // The microphone was unplugged at 10.5: silence to the stop, the
        // pause left out.
        XCTAssertEqual(timeline.tail(), .silence(150))
        XCTAssertEqual(timeline.written, 200)
        XCTAssertNil(timeline.tail())
    }

    func testATrackPastTheStopIsCutThere() {
        var timeline = TrackTimeline(rate: 100, start: 10)
        // Its clock ran ahead: in a row by the sample time, 30 frames more
        // than the host's half second.
        _ = timeline.place(sampleTime: 0, hostTime: 10, frames: 40)
        _ = timeline.place(sampleTime: 40, hostTime: 10.38, frames: 40)
        timeline.finish(at: 10.5)
        XCTAssertEqual(timeline.overshoot(), 30)
        XCTAssertEqual(timeline.written, 50)
        XCTAssertNil(timeline.tail())
        XCTAssertEqual(timeline.overshoot(), 0)
    }

    /// A microphone whose clock runs fast or slow (`ppm`) against the
    /// host's, for an hour, paused 30 s every 10 minutes: how far the track
    /// gets from the host clock (frames, over buffers recorded whole), how
    /// much that moves across a pause, and where it ends.
    private func drifting(ppm: Double) -> (worst: Int, worstJump: Int, end: Int, frames: Int) {
        let rate = 48000.0, size = 512
        let pauses = stride(from: 600.0, through: 3000.0, by: 600.0).map { ($0, $0 + 30) }
        var timeline = TrackTimeline(rate: rate, start: 0)
        for (from, to) in pauses {
            timeline.pause(at: from)
            timeline.resume(at: to)
        }
        timeline.finish(at: 3600)
        func recorded(_ time: Double) -> Bool { time < 3600 && !pauses.contains { time >= $0.0 && time < $0.1 } }
        var sample = 0.0, host = 0.0
        var worst = 0.0, worstJump = 0.0
        var last: Double?
        var crossed = false
        while host < 3600 {
            _ = timeline.place(sampleTime: sample, hostTime: host, frames: size)
            let end = host + Double(size) / (rate * (1 + ppm * 1e-6))
            if recorded(host), recorded(end) {
                let deviation = Double(timeline.written) - timeline.fileTime(of: end) * rate
                worst = max(worst, abs(deviation))
                if crossed, let last { worstJump = max(worstJump, abs(deviation - last)) }
                last = deviation
                crossed = false
            } else {
                crossed = true
            }
            sample += Double(size)
            host = end
        }
        return (Int(worst.rounded()), Int(worstJump.rounded()), timeline.written, Int((timeline.fileTime(of: 3600) * rate).rounded()))
    }

    func testAFastMicrophoneStaysWithTheHostClock() {
        let run = drifting(ppm: 100)
        XCTAssertLessThanOrEqual(run.worst, 24, "never more than half a millisecond off: \(run.worst) frames")
        XCTAssertLessThanOrEqual(run.worstJump, 24, "a pause's re-placement under half a millisecond: \(run.worstJump) frames")
        XCTAssertLessThanOrEqual(abs(run.end - run.frames), 24, "the hour ends where it should")
    }

    func testASlowMicrophoneStaysWithTheHostClock() {
        let run = drifting(ppm: -100)
        XCTAssertLessThanOrEqual(run.worst, 24, "never more than half a millisecond off: \(run.worst) frames")
        XCTAssertLessThanOrEqual(run.worstJump, 24, "a pause's re-placement under half a millisecond: \(run.worstJump) frames")
        XCTAssertLessThanOrEqual(abs(run.end - run.frames), 24, "the hour ends where it should")
    }

    func testAFrameIsLeftOutOrPlayedTwiceAtMost() {
        var timeline = TrackTimeline(rate: 48000, start: 0)
        var sample = 0.0, host = 0.0
        var counts: Set<Int> = []
        // 300 ppm fast, for a minute: every buffer holds 512 frames, one
        // less at most.
        for _ in 0..<5625 {
            let pieces = timeline.place(sampleTime: sample, hostTime: host, frames: 512)
            counts.insert(pieces.reduce(0) { total, piece in if case .frames(let range) = piece { total + range.count } else { total } })
            sample += 512
            host += 512 / (48000 * 1.0003)
        }
        XCTAssertEqual(counts, [511, 512])
    }

    func testAnHourOfBuffersStaysOnTheDevicesClock() {
        // 48 kHz, 512-frame cycles, one missed every 1000.
        var timeline = TrackTimeline(rate: 48000, start: 0)
        var sample = 0.0, written = 0
        for cycle in 0..<(3600 * 48000 / 512) {
            sample += 512
            if cycle % 1000 == 999 { continue }
            written += length(timeline.place(sampleTime: sample, hostTime: sample / 48000, frames: 512))
        }
        XCTAssertEqual(Double(written) / 48000, 3600, accuracy: 0.02)
    }
}

final class MeetingTranscriptTests: XCTestCase {
    /// Words one after another, 0.3 s each from `start`.
    private func phrase(_ text: String, at start: Double) -> [TranscriptWord] {
        text.split(separator: " ").enumerated().map { index, word in
            TranscriptWord(String(word), start: start + Double(index) * 0.3, end: start + Double(index) * 0.3 + 0.25)
        }
    }

    func testTheOtherSideHeardAgainLeavesTheUsersLines() {
        let them = phrase("Forty-two, actually. We can ship on Friday.", at: 10)
        // The microphone hears it 45 ms later, then the user speaks.
        let echo = them.map { TranscriptWord($0.text, start: $0.start + 0.045, end: $0.end + 0.045) }
        let mine = phrase("Great, thanks Ingrid.", at: 13)
        let (kept, dropped) = MeetingTranscript.droppingEcho([echo, mine], heard: them)
        XCTAssertEqual(kept.map(MeetingTranscript.joined), ["Great, thanks Ingrid."])
        XCTAssertEqual(dropped, 7)
    }

    func testALoneWordTheUserSaysStays() {
        let them = phrase("Does that work for you?", at: 10)
        // "you" said by the user right after: one word, not a run.
        let mine = phrase("you know what, yes", at: 11.4)
        let (kept, dropped) = MeetingTranscript.droppingEcho([mine], heard: them)
        XCTAssertEqual(kept.map(MeetingTranscript.joined), ["you know what, yes"])
        XCTAssertEqual(dropped, 0)
    }

    func testTheSameWordsOutsideTheWindowStay() {
        let them = phrase("the budget is fine", at: 10)
        // Said again by the user five seconds later: not an echo.
        let mine = phrase("the budget is fine", at: 16)
        XCTAssertEqual(MeetingTranscript.droppingEcho([mine], heard: them).dropped, 0)
        // Heard 0.6 s before the Mac played it: not an echo either.
        let early = phrase("the budget is fine", at: 9.3)
        XCTAssertEqual(MeetingTranscript.droppingEcho([early], heard: them).dropped, 0)
        let late = phrase("the budget is fine", at: 11.9)
        XCTAssertEqual(MeetingTranscript.droppingEcho([late], heard: them).dropped, 4, "up to 2 s after")
    }

    func testCaseAccentsAndPunctuationDoNotTellWordsApart() {
        let them = [TranscriptWord("Réunion,", start: 1, end: 1.2), TranscriptWord("demain", start: 1.3, end: 1.5), TranscriptWord(".", start: 1.5, end: 1.5)]
        let mine = [TranscriptWord("reunion", start: 1.05, end: 1.25), TranscriptWord("Demain", start: 1.35, end: 1.55), TranscriptWord(".", start: 1.55, end: 1.55),
                    TranscriptWord("Oui", start: 3, end: 3.2)]
        let (kept, dropped) = MeetingTranscript.droppingEcho([mine], heard: them)
        XCTAssertEqual(dropped, 2)
        XCTAssertEqual(kept.map(MeetingTranscript.joined), ["Oui"], "the period went with its word")
    }

    func testARunGoesOnFromOnePhraseToTheNext() {
        let them = phrase("we ship on Friday", at: 10)
        let echo = them.map { TranscriptWord($0.text, start: $0.start + 0.05, end: $0.end + 0.05) }
        let (kept, dropped) = MeetingTranscript.droppingEcho([Array(echo.prefix(1)), Array(echo.dropFirst())], heard: them)
        XCTAssertEqual(dropped, 4)
        XCTAssertTrue(kept.isEmpty)
    }

    func testTheTracksMakeOneTranscriptByTime() {
        let me = [phrase("Hello everyone.", at: 1), phrase("Priyanka, go ahead.", at: 8)]
        let them = [phrase("Hi Camille.", at: 3), phrase("Sure, so the budget.", at: 10)]
        let lines = MeetingTranscript.lines(me: me, them: them)
        XCTAssertEqual(lines.map(\.speaker), [.me, .them, .me, .them])
        XCTAssertEqual(lines.map(\.text), ["Hello everyone.", "Hi Camille.", "Priyanka, go ahead.", "Sure, so the budget."])
        XCTAssertEqual(lines[1].start, 3)
        XCTAssertEqual(lines[1].end, 3.55, accuracy: 1e-9)
    }

    func testPhrasesCloseTogetherAreOneLine() {
        let me = [phrase("So this is the review.", at: 1), phrase("Priyanka sent the sheet.", at: 3.0)]
        let lines = MeetingTranscript.lines(me: me, them: [])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "So this is the review. Priyanka sent the sheet.")
        // A pause over 1.5 s starts another line.
        XCTAssertEqual(MeetingTranscript.lines(me: [phrase("One.", at: 1), phrase("Two.", at: 3)], them: []).count, 2)
    }

    func testSomeoneTalkingOverStartsTheirLineWhereTheyStart() {
        let me = [phrase("so the outage lasted forty minutes and then", at: 1), phrase("we rolled back.", at: 3.6)]
        let them = [phrase("Forty-two.", at: 2)]
        let lines = MeetingTranscript.lines(me: me, them: them)
        XCTAssertEqual(lines.map(\.speaker), [.me, .them, .me])
        XCTAssertEqual(lines[2].text, "we rolled back.")
    }

    func testALongMonologueIsCutIntoLines() {
        let me = (0..<30).map { phrase("A sentence of five words.", at: Double($0) * 2.5) }
        let lines = MeetingTranscript.lines(me: me, them: [])
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { $0.end - $0.start <= 60 })
    }

    func testTheLinePlayingIsTheLastStarted() {
        let lines = MeetingTranscript.lines(me: [phrase("One.", at: 1), phrase("Three.", at: 9)], them: [phrase("Two.", at: 5)])
        XCTAssertNil(MeetingTranscript.line(at: 0.5, in: lines))
        XCTAssertEqual(MeetingTranscript.line(at: 1, in: lines), 0)
        XCTAssertEqual(MeetingTranscript.line(at: 7, in: lines), 1)
        XCTAssertEqual(MeetingTranscript.line(at: 100, in: lines), 2)
    }

    func testTheMarkdownNamesEachSpeakerAndTime() {
        let lines = MeetingTranscript.lines(me: [phrase("Hello everyone.", at: 0.4)], them: [phrase("Loud and clear.", at: 64)])
        let text = MeetingTranscript.markdown(title: "Weekly sync", about: "Wednesday 22 October 2026, 14:00 · 32 min · English",
                                              lines: lines, names: ["me": "Camille"])
        XCTAssertEqual(text, """
            # Weekly sync

            Wednesday 22 October 2026, 14:00 · 32 min · English

            **Camille** · 0:00
            Hello everyone.

            **Them** · 1:04
            Loud and clear.

            """)
    }

    func testTimesAndWords() {
        XCTAssertEqual(MeetingTranscript.clock(4.9), "0:04")
        XCTAssertEqual(MeetingTranscript.clock(724), "12:04")
        XCTAssertEqual(MeetingTranscript.clock(3723), "1:02:03")
        XCTAssertEqual(MeetingTranscript.joined([TranscriptWord(" Hello", start: 0, end: 0), TranscriptWord(",", start: 0, end: 0),
                                                 TranscriptWord(" it's", start: 0, end: 0), TranscriptWord("me", start: 0, end: 0),
                                                 TranscriptWord("?", start: 0, end: 0)]), "Hello, it's me?")
        XCTAssertEqual(MeetingTranscript.folded("Ça,"), "ca")
        XCTAssertEqual(MeetingTranscript.folded("…"), "")
    }

    func testTheTranscriptFileIsReadBack() throws {
        let file = MeetingTranscript.File(language: "fr-FR", engine: "SpeechTranscriber",
                                          lines: MeetingTranscript.lines(me: [phrase("Bonjour à tous.", at: 1)], them: []))
        XCTAssertEqual(try MeetingTranscript.File.decode(try file.encoded()), file)
        XCTAssertTrue(String(decoding: try file.encoded(), as: UTF8.self).contains("\"w\":\"Bonjour\""))
    }
}

final class SilentTrackTests: XCTestCase {
    /// The case measured: the microphone's engine started again at 100 s
    /// without its tap; nothing came for the rest of the call.
    func testAnEngineStartedAgainThatGivesNothingIsSaidWithinSeconds() {
        var watch = SilentTrack(since: 90)
        XCTAssertNil(watch.update(now: 99, lastBuffer: 98.9, lastSound: 98.9).reason)
        watch.started(at: 100)
        XCTAssertNil(watch.update(now: 101, lastBuffer: 98.9, lastSound: 98.9).reason)
        XCTAssertNil(watch.update(now: 102.9, lastBuffer: 98.9, lastSound: 98.9).reason, "under 3 s: a restart takes a moment")
        let said = watch.update(now: 103, lastBuffer: 98.9, lastSound: 98.9)
        XCTAssertEqual(said.reason, .nothing)
        XCTAssertTrue(said.offer)
        let later = watch.update(now: 600, lastBuffer: 98.9, lastSound: 98.9)
        XCTAssertEqual(later.reason, .nothing)
        XCTAssertFalse(later.offer, "the card once for a stretch; the menu bar says it all along")
    }

    func testBuffersThatStopComingAreNothing() {
        var watch = SilentTrack(since: 0)
        XCTAssertNil(watch.update(now: 60, lastBuffer: 59.9, lastSound: 59.9).reason)
        XCTAssertNil(watch.update(now: 62.8, lastBuffer: 59.9, lastSound: 59.9).reason)
        XCTAssertEqual(watch.update(now: 63, lastBuffer: 59.9, lastSound: 59.9).reason, .nothing)
    }

    /// A microphone always gives some noise, a quiet room too: exact zeros
    /// from its start are a track that records nothing.
    func testOnlyZerosSinceTheStartAreSaid() {
        var watch = SilentTrack(since: 10)
        XCTAssertNil(watch.update(now: 14.9, lastBuffer: 14.9, lastSound: nil).reason)
        let said = watch.update(now: 15, lastBuffer: 14.95, lastSound: nil)
        XCTAssertEqual(said.reason, .zeros)
        XCTAssertTrue(said.offer)
        XCTAssertEqual(watch.update(now: 16, lastBuffer: 15.95, lastSound: 2).reason, .zeros, "sound from before the start does not count")
    }

    /// Once the track gave sound since its start, quiet is only quiet: the
    /// user muted, nobody talking.
    func testAQuietStretchAfterSoundIsNeverSaid() {
        var watch = SilentTrack(since: 0)
        XCTAssertNil(watch.update(now: 3, lastBuffer: 3, lastSound: 1).reason)
        XCTAssertNil(watch.update(now: 300, lastBuffer: 299.95, lastSound: 1).reason)
    }

    /// The engine started again by itself counts from then: zeros since are
    /// said even after sound before it.
    func testZerosAfterTheSourceStartedAgainAreSaid() {
        var watch = SilentTrack(since: 0)
        XCTAssertNil(watch.update(now: 50, lastBuffer: 50, lastSound: 49).reason)
        watch.started(at: 60)
        XCTAssertNil(watch.update(now: 64, lastBuffer: 64, lastSound: 49).reason)
        XCTAssertEqual(watch.update(now: 65, lastBuffer: 65, lastSound: 49).reason, .zeros)
        watch.started(at: 30)
        XCTAssertEqual(watch.since, 60, "never moved back")
    }

    /// The Mac's sound gives exact zeros whenever nothing plays: its zeros
    /// count only once an app has played sound for 5 s.
    func testTheMacsSoundCountsZerosOnlyWhileAnAppPlays() {
        var watch = SilentTrack(since: 0)
        var playing = false
        XCTAssertNil(watch.update(now: 30, lastBuffer: 30, lastSound: nil, playing: { playing }).reason, "nothing plays: zeros are right")
        playing = true
        XCTAssertNil(watch.update(now: 31, lastBuffer: 31, lastSound: nil, playing: { playing }).reason)
        XCTAssertNil(watch.update(now: 35.9, lastBuffer: 35.9, lastSound: nil, playing: { playing }).reason)
        let said = watch.update(now: 36, lastBuffer: 36, lastSound: nil, playing: { playing })
        XCTAssertEqual(said.reason, .zeros)
        XCTAssertTrue(said.offer)
        playing = false
        let stopped = watch.update(now: 37, lastBuffer: 37, lastSound: nil, playing: { playing })
        XCTAssertNil(stopped.reason, "the app stopped: the card withdrawn")
        playing = true
        XCTAssertNil(watch.update(now: 38, lastBuffer: 38, lastSound: nil, playing: { playing }).reason, "playing again: counted afresh")
        let again = watch.update(now: 43, lastBuffer: 43, lastSound: nil, playing: { playing })
        XCTAssertEqual(again.reason, .zeros)
        XCTAssertFalse(again.offer, "no sound came in between: the same stretch, not offered twice")
    }

    func testTheMacsSoundIsNotAskedOnceItGaveSound() {
        var watch = SilentTrack(since: 0)
        var asked = 0
        XCTAssertNil(watch.update(now: 30, lastBuffer: 30, lastSound: 2, playing: { asked += 1; return true }).reason)
        XCTAssertEqual(asked, 0, "Core Audio is asked only while it matters")
    }

    func testKeepRecordingHoldsUntilTheTrackGivesSound() {
        var watch = SilentTrack(since: 0)
        XCTAssertTrue(watch.update(now: 3, lastBuffer: nil, lastSound: nil).offer)
        watch.keep()
        watch.started(at: 10)
        let restarted = watch.update(now: 13, lastBuffer: nil, lastSound: nil)
        XCTAssertEqual(restarted.reason, .nothing)
        XCTAssertFalse(restarted.offer, "started again by itself, still nothing: Keep Recording stands")
        XCTAssertNil(watch.update(now: 14, lastBuffer: 14, lastSound: 14).reason)
        watch.started(at: 20)
        XCTAssertTrue(watch.update(now: 23, lastBuffer: 19, lastSound: 19).offer, "sound came in between: a new stretch is offered")
    }

    /// Buffers back after the stretch, but only zeros: no sound since it was
    /// said, so Keep Recording still holds through the next outage.
    func testBuffersBackWithOnlyZerosDoNotEndTheStretch() {
        var watch = SilentTrack(since: 0)
        XCTAssertNil(watch.update(now: 10, lastBuffer: 10, lastSound: 9).reason)
        let said = watch.update(now: 13, lastBuffer: 10, lastSound: 9)
        XCTAssertEqual(said.reason, .nothing)
        XCTAssertTrue(said.offer)
        watch.keep()
        XCTAssertNil(watch.update(now: 14, lastBuffer: 14, lastSound: 9).reason, "zeros since sound: quiet, not said")
        XCTAssertFalse(watch.update(now: 20, lastBuffer: 16, lastSound: 9).offer, "out again, no sound in between: Keep Recording holds")
        XCTAssertNil(watch.update(now: 21, lastBuffer: 21, lastSound: 21).reason)
        XCTAssertTrue(watch.update(now: 25, lastBuffer: 21, lastSound: 21).offer, "sound came in between: a new stretch")
    }

    func testStartAgainOffersAgainWhenItStillRecordsNothing() {
        var watch = SilentTrack(since: 0)
        XCTAssertTrue(watch.update(now: 3, lastBuffer: nil, lastSound: nil).offer)
        watch.startedAgain(at: 4)
        XCTAssertNil(watch.update(now: 6, lastBuffer: nil, lastSound: nil).reason)
        XCTAssertTrue(watch.update(now: 7, lastBuffer: nil, lastSound: nil).offer)
    }

    func testACardBusyElsewhereOffersItAtTheNextUpdate() {
        var watch = SilentTrack(since: 0)
        XCTAssertTrue(watch.update(now: 3, lastBuffer: nil, lastSound: nil).offer)
        watch.offerAgain()
        XCTAssertTrue(watch.update(now: 4, lastBuffer: nil, lastSound: nil).offer)
        XCTAssertFalse(watch.update(now: 5, lastBuffer: nil, lastSound: nil).offer)
    }

    func testTheLinesSayWhatIsNotRecorded() {
        XCTAssertEqual(SilentTrack.line(.nothing, speaker: .me, device: "AirPods Pro"), "Nothing comes from AirPods Pro: what you say isn't recorded.")
        XCTAssertEqual(SilentTrack.line(.zeros, speaker: .them, device: "", playing: "Google Chrome"),
                       "The Mac's sound gives only silence while Google Chrome plays: allow skil.li in Screen & System Audio Recording.")
        XCTAssertEqual(SilentTrack.menuLine(.nothing, device: "AirPods Pro"), "nothing comes from AirPods Pro")
        XCTAssertEqual(SilentTrack.menuLine(.zeros, device: nil), "only silence")
    }
}
