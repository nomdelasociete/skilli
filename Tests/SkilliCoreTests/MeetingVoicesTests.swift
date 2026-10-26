@testable import SkilliCore
import XCTest

final class MeetingVoicesTests: XCTestCase {
    private func word(_ text: String, _ start: Double, _ end: Double? = nil) -> TranscriptWord {
        TranscriptWord(text, start: start, end: end ?? start + 0.3)
    }

    private func line(_ voice: Voice, _ text: String, at start: Double) -> TranscriptLine {
        let pieces = text.split(separator: " ")
        return TranscriptLine(speaker: voice, words: pieces.enumerated().map { word(String($0.element), start + Double($0.offset) * 0.4) })
    }

    // MARK: - Voice

    func testVoiceKeepsItsIDInJSONAndReadsVersionOne() throws {
        let file = MeetingTranscript.File(language: "en-US", engine: "macOS", lines: [line(.them(2), "Hello there", at: 1)])
        let json = String(decoding: try file.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""speaker":"them2""#), json)
        XCTAssertTrue(json.contains(#""version":2"#), json)
        let old = #"{"version":1,"language":"en-US","engine":"SpeechTranscriber","lines":[{"speaker":"me","start":0,"end":1,"words":[{"w":"Hi","s":0,"e":1}]}]}"#
        let read = try MeetingTranscript.File.decode(Data(old.utf8))
        XCTAssertEqual(read.lines.first?.speaker, .me)
        XCTAssertEqual(TranscriptEngine(stored: read.engine), .macOS)
    }

    func testVoicesTitlesAndTracks() {
        XCTAssertEqual(Voice.me.title, "Me")
        XCTAssertEqual(Voice.them.title, "Them")
        XCTAssertEqual(Voice.them(1), .them)
        XCTAssertEqual(Voice.them(3).title, "Them 3")
        XCTAssertEqual(Voice.single(2).title, "Speaker 2")
        XCTAssertEqual(Voice.them(2).track, .them)
        XCTAssertEqual(Voice.single(1).track, .me)
        XCTAssertEqual(Voice.me.track, .me)
    }

    // MARK: - Words to voices

    func testWordsGoToTheVoiceHeardAtTheirTimeAndPhrasesAreCutThere() {
        let phrases = [[word("Hello", 0), word("Paul.", 0.4), word("Hi", 1.2), word("Anna.", 1.6)]]
        let stretches = [MeetingVoices.Stretch(voice: 7, start: 0, end: 0.9), .init(voice: 3, start: 1.1, end: 2.2)]
        let (split, voices) = MeetingVoices.split(phrases, stretches: stretches, id: Voice.them)
        XCTAssertEqual(voices, [.them, .them(2)])
        XCTAssertEqual(split.map(\.0), [.them, .them(2)])
        XCTAssertEqual(split.map { MeetingTranscript.joined($0.1) }, ["Hello Paul.", "Hi Anna."])
    }

    func testVoicesAreNumberedByTheirFirstWordNotByTheSeparationsOrder() {
        // The separation calls the second speaker 0 and the first 1.
        let phrases = [[word("One", 0)], [word("Two", 2)], [word("Three", 4)]]
        let stretches = [MeetingVoices.Stretch(voice: 1, start: 0, end: 1), .init(voice: 0, start: 1.9, end: 3), .init(voice: 1, start: 3.9, end: 5)]
        let (split, voices) = MeetingVoices.split(phrases, stretches: stretches, id: Voice.single)
        XCTAssertEqual(voices, [.single(1), .single(2)])
        XCTAssertEqual(split.map(\.0), [.single(1), .single(2), .single(1)])
    }

    func testAWordNoStretchHoldsGoesToTheNearestWithinReachElseToItsNeighbours() {
        let phrases = [[word("Near", 1.5)], [word("Far", 10), word("away", 10.4)], [word("Then", 20)]]
        let stretches = [MeetingVoices.Stretch(voice: 0, start: 0, end: 1.2), .init(voice: 1, start: 19.8, end: 21)]
        let (split, _) = MeetingVoices.split(phrases, stretches: stretches, id: Voice.them)
        // "Near" is 0.45 s from the first stretch; "Far away" is out of
        // reach of both: the word before's voice.
        XCTAssertEqual(split.map(\.0), [.them, .them, .them(2)])
    }

    func testALoneWordBetweenTwoOfAnotherVoiceStaysWithThem() {
        let phrases = [[word("We", 0), word("agree", 0.4), word("then", 0.8)]]
        let stretches = [MeetingVoices.Stretch(voice: 0, start: 0, end: 0.6), .init(voice: 1, start: 0.6, end: 0.85), .init(voice: 0, start: 0.85, end: 2)]
        let (split, voices) = MeetingVoices.split(phrases, stretches: stretches, id: Voice.them)
        XCTAssertEqual(voices, [.them])
        XCTAssertEqual(split.count, 1)
    }

    func testOverlappingStretchesGiveTheWordToTheOneHoldingMoreOfIt() {
        let phrases = [[word("Overlap", 1.0, 1.6)]]
        let stretches = [MeetingVoices.Stretch(voice: 0, start: 0, end: 1.35), .init(voice: 1, start: 1.1, end: 3)]
        XCTAssertEqual(MeetingVoices.split(phrases, stretches: stretches, id: Voice.them).phrases.map(\.0), [.them])
    }

    func testNoStretchIsOneVoice() {
        let (split, voices) = MeetingVoices.split([[word("Alone", 0)]], stretches: [], id: Voice.them)
        XCTAssertEqual(voices, [.them])
        XCTAssertEqual(split.map(\.0), [.them])
    }

    func testLinesOfManyVoicesStayInTimeAndTheUserFirstOnATie() {
        let lines = MeetingTranscript.lines([(.them(2), [word("b", 1)]), (.me, [word("a", 1)]), (.them, [word("c", 0.5)])])
        XCTAssertEqual(lines.map(\.speaker), [.them, .me, .them(2)])
    }

    // MARK: - Names

    func testNamesStartAsThemAloneOrNumbered() {
        XCTAssertEqual(MeetingVoices.names(of: [.me, .them]), ["them": "Them"])
        XCTAssertEqual(MeetingVoices.names(of: [.them, .them(2), .them(3)]), ["them": "Them 1", "them2": "Them 2", "them3": "Them 3"])
        XCTAssertEqual(MeetingVoices.names(of: [.single(1), .single(2)]), ["s1": "Speaker 1", "s2": "Speaker 2"])
    }

    func testOrderIsMeFirstThenAsTheyFirstSpeak() {
        let lines = [line(.them(2), "a", at: 0), line(.them, "b", at: 1), line(.me, "c", at: 2), line(.them(2), "d", at: 3)]
        XCTAssertEqual(MeetingVoices.order(of: lines), [.me, .them(2), .them])
        XCTAssertEqual(MeetingVoices.next(after: .them, in: [.me, .them(2), .them]), .me)
        XCTAssertEqual(MeetingVoices.next(after: .me, in: [.me, .them(2), .them], step: -1), .them)
        XCTAssertEqual(MeetingVoices.next(after: .me, in: [.me]), .me)
    }

    func testARenameRenamesEveryLineOfThatSpeaker() {
        var lines = [line(.me, "a", at: 0), line(.them(2), "b", at: 1), line(.them(2), "c", at: 2)]
        var names = ["them2": "Them 2"]
        let renamed = MeetingVoices.rename(.them(2), to: "  Paul   Arnaud ", lines: &lines, names: &names)
        XCTAssertEqual(names["them2"], "Paul Arnaud")
        XCTAssertEqual(renamed?.moved, [:])
        XCTAssertNil(MeetingVoices.rename(.them(2), to: "Paul Arnaud", lines: &lines, names: &names))
        XCTAssertNil(MeetingVoices.rename(.them(2), to: "  ", lines: &lines, names: &names))
    }

    func testTwoSpeakersGivenTheSameNameBecomeOne() {
        var lines = [line(.them, "a", at: 0), line(.them(2), "b", at: 1), line(.them(3), "c", at: 2)]
        var names = ["them": "Paul", "them2": "Them 2", "them3": "Them 3"]
        let renamed = MeetingVoices.rename(.them(3), to: "paul", lines: &lines, names: &names)
        XCTAssertEqual(lines.map(\.speaker), [.them, .them(2), .them])
        XCTAssertEqual(names, ["them": "Paul", "them2": "Them 2"])
        XCTAssertEqual(renamed?.joined, .them)
        XCTAssertEqual(renamed?.moved, [2: .them(3)])
    }

    func testMeIsKeptWhenMergedAndTheOwnNameJoinsMe() {
        var lines = [line(.me, "a", at: 0), line(.them(2), "b", at: 1)]
        var names = ["me": "Me", "them2": "Them 2"]
        // Given the user's own name: joins Me, Me keeps its name.
        let joined = MeetingVoices.rename(.them(2), to: "Jean-François Martaing", lines: &lines, names: &names, ownName: "Jean-Francois Martaing")
        XCTAssertEqual(joined?.joined, .me)
        XCTAssertEqual(lines.map(\.speaker), [.me, .me])
        XCTAssertEqual(names, ["me": "Me"])

        // Me renamed to another's name: that one's lines join Me.
        lines = [line(.me, "a", at: 0), line(.them, "b", at: 1)]
        names = ["me": "Me", "them": "Margot"]
        _ = MeetingVoices.rename(.me, to: "Margot", lines: &lines, names: &names)
        XCTAssertEqual(lines.map(\.speaker), [.me, .me])
        XCTAssertEqual(names, ["me": "Margot"])
    }

    func testTheOwnNameJoinsNobodyWhenMeHasNoLines() {
        var lines = [line(.single(1), "a", at: 0), line(.single(2), "b", at: 1)]
        var names = ["me": "Room", "s1": "Speaker 1", "s2": "Speaker 2"]
        let renamed = MeetingVoices.rename(.single(2), to: "Camille", lines: &lines, names: &names, ownName: "Camille")
        XCTAssertNil(renamed?.joined)
        XCTAssertEqual(names["s2"], "Camille")
    }

    func testOfferedNamesPutTheUsersFirstForMeThenTheAttendeesNotGivenThenTheGiven() {
        let lines = [line(.me, "a", at: 0), line(.them, "b", at: 1), line(.them(2), "c", at: 2)]
        let names = ["me": "Me", "them": "Paul Arnaud", "them2": "Them 2"]
        let forThem = MeetingVoices.offered(for: .them(2), lines: lines, names: names, attendees: ["Paul Arnaud", "Anna Lindqvist"], ownName: "Camille")
        XCTAssertEqual(forThem.fresh, ["Anna Lindqvist"])
        XCTAssertEqual(forThem.given.map(\.name), ["Me", "Paul Arnaud"])
        let forMe = MeetingVoices.offered(for: .me, lines: lines, names: names, attendees: ["Anna Lindqvist"], ownName: "Camille")
        XCTAssertEqual(forMe.fresh, ["Camille", "Anna Lindqvist"])
    }

    // MARK: - Edits

    func testRetimedKeepsTheWordsKeptAndSharesTheReplacedOnesTime() {
        let words = [word("We", 0, 0.4), word("meat", 0.5, 0.9), word("at", 1.0, 1.2), word("noon.", 1.3, 1.8)]
        let retimed = TranscriptDraft.retimed(words, to: "We meet up at noon.", start: 0, end: 1.8)
        XCTAssertEqual(retimed.map(\.text), ["We", "meet", "up", "at", "noon."])
        XCTAssertEqual(retimed[0].start, 0)
        XCTAssertEqual(retimed[1].start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(retimed[2].end, 0.9, accuracy: 1e-9)
        XCTAssertEqual(retimed[3].start, 1.0)
        XCTAssertEqual(retimed[4].end, 1.8)
        // A word added between two kept ones: the gap between them.
        let added = TranscriptDraft.retimed([word("Hello", 0, 0.5), word("Paul", 1.0, 1.4)], to: "Hello dear Paul", start: 0, end: 1.4)
        XCTAssertEqual(added[1].start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(added[1].end, 1.0, accuracy: 1e-9)
        XCTAssertTrue(TranscriptDraft.retimed(words, to: "   ", start: 0, end: 1).isEmpty)
    }

    func testEditsUndoAndRedo() {
        var draft = TranscriptDraft(lines: [line(.me, "Hello all", at: 0), line(.them, "Hi there", at: 2), line(.them(2), "Good morning", at: 4)],
                                    names: ["them": "Them 1", "them2": "Them 2"])
        let original = draft
        var history = TranscriptHistory()
        history.record(draft.setText("Hello everyone", at: 0)!)
        history.record(draft.moveSpeaker(at: 1)!)
        XCTAssertEqual(draft.lines[1].speaker, .them(2))
        history.record(draft.rename(.them(2), to: "Anna")!)
        history.record(draft.delete(at: 2)!)
        XCTAssertEqual(draft.lines.map(\.text), ["Hello everyone", "Hi there"])
        XCTAssertNil(draft.setText("Hi there", at: 1))
        while history.canUndo { history.undo(&draft) }
        XCTAssertEqual(draft, original)
        while history.canRedo { history.redo(&draft) }
        XCTAssertEqual(draft.lines.map(\.text), ["Hello everyone", "Hi there"])
        XCTAssertEqual(draft.names["them2"], "Anna")
    }

    func testEmptiedTextIsADelete() {
        var draft = TranscriptDraft(lines: [line(.me, "Hello", at: 0)], names: [:])
        guard case .delete? = draft.setText("", at: 0) else { return XCTFail("not a delete") }
        XCTAssertTrue(draft.lines.isEmpty)
    }

    func testADeletesUndoCardBringsItBackAfterLaterChanges() {
        var draft = TranscriptDraft(lines: [line(.me, "a", at: 0), line(.them, "b", at: 1), line(.me, "c", at: 2), line(.them, "d", at: 3)], names: [:])
        var history = TranscriptHistory()
        let deleted = history.record(draft.delete(at: 1)!)
        // Then "d" (now line 2) is edited and "c" (line 1) deleted.
        history.record(draft.setText("dd", at: 2)!)
        history.record(draft.delete(at: 1)!)
        XCTAssertEqual(draft.lines.map(\.text), ["a", "dd"])
        XCTAssertTrue(history.revert(id: deleted, in: &draft))
        XCTAssertEqual(draft.lines.map(\.text), ["a", "b", "dd"])
        XCTAssertFalse(history.revert(id: deleted, in: &draft))
        // The later changes still undo in place.
        history.undo(&draft)
        XCTAssertEqual(draft.lines.map(\.text), ["a", "b", "c", "dd"])
        history.undo(&draft)
        XCTAssertEqual(draft.lines.map(\.text), ["a", "b", "c", "d"])
    }

    // MARK: - Engines

    func testTheEngineIsBetterTranscriptionOnceDownloadedUnlessMacOSIsPicked() {
        XCTAssertEqual(TranscriptEngine.standard(preferred: nil, whisperReady: false), .macOS)
        XCTAssertEqual(TranscriptEngine.standard(preferred: .whisper, whisperReady: false), .macOS)
        XCTAssertEqual(TranscriptEngine.standard(preferred: nil, whisperReady: true), .whisper)
        XCTAssertEqual(TranscriptEngine.standard(preferred: .macOS, whisperReady: true), .macOS)
        XCTAssertEqual(TranscriptEngine.order(standard: .whisper, whisperReady: true), [.whisper, .macOS])
        XCTAssertEqual(TranscriptEngine.order(standard: .macOS, whisperReady: false), [.macOS])
        XCTAssertEqual(TranscriptEngine(stored: "whisper-large-v3-turbo"), .whisper)
        XCTAssertNil(TranscriptEngine(stored: "other"))
    }
}
