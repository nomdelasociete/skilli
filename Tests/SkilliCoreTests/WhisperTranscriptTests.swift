@testable import SkilliCore
import XCTest

final class WhisperTranscriptTests: XCTestCase {
    private func token(_ text: String, _ start: Double, _ end: Double) -> WhisperTranscript.Token {
        WhisperTranscript.Token(text, start: start, end: end)
    }

    func testTokensMakeWordsFromTheirFirstStartToTheirLastEnd() {
        let segment = WhisperTranscript.Segment(tokens: [token(" Hello", 0.0, 0.4), token(",", 0.4, 0.45), token(" Ker", 0.5, 0.7),
                                                         token("jean", 0.7, 1.0), token(".", 1.0, 1.05)])
        let words = WhisperTranscript.words(of: segment)
        XCTAssertEqual(words.map(\.text), ["Hello,", "Kerjean."])
        XCTAssertEqual(words[1].start, 0.5)
        XCTAssertEqual(words[1].end, 1.05)
    }

    func testACharacterCutBetweenTwoTokensIsWholeAgain() {
        // "é" is C3 A9: whisper may give each byte its own token.
        let segment = WhisperTranscript.Segment(tokens: [WhisperTranscript.Token([0x20, 0x4D, 0x61, 0xC3], start: 0, end: 0.2),
                                                         WhisperTranscript.Token([0xA9, 0x6C, 0x79, 0x73], start: 0.2, end: 0.5)])
        XCTAssertEqual(WhisperTranscript.words(of: segment).map(\.text), ["Maélys"])
    }

    func testASegmentRepeatedRightAfterItselfGoes() {
        let line = WhisperTranscript.Segment(tokens: [token(" Thank", 0, 0.3), token(" you.", 0.3, 0.6)])
        var again = line
        again.tokens = again.tokens.map { WhisperTranscript.Token($0.bytes, start: $0.start + 5, end: $0.end + 5) }
        let other = WhisperTranscript.Segment(tokens: [token(" Bye.", 20, 20.4)])
        let phrases = WhisperTranscript.phrases(of: WhisperTranscript.Run(segments: [line, again, again, other, line]), attendees: [])
        XCTAssertEqual(phrases.map(MeetingTranscript.joined), ["Thank you.", "Bye.", "Thank you."])
    }

    func testASegmentIsCutWhereItsTimesJump() {
        // One segment over words said 15 s apart (the other side spoke
        // between them): two phrases, so the lines interleave by time.
        let segment = WhisperTranscript.Segment(tokens: [token(" Hello", 1, 1.4), token(" everyone.", 1.4, 2), token(" That's", 16, 16.3),
                                                         token(" fine.", 16.3, 16.8), token(" Thanks", 17.2, 17.6)])
        let phrases = WhisperTranscript.phrases(of: WhisperTranscript.Run(segments: [segment]), attendees: [])
        XCTAssertEqual(phrases.map(MeetingTranscript.joined), ["Hello everyone.", "That's fine. Thanks"])
        let lines = MeetingTranscript.lines(me: phrases, them: [[TranscriptWord("Hi", start: 4, end: 4.5)]])
        XCTAssertEqual(lines.map(\.speaker), [.me, .them, .me])
    }

    func testAnAttendeesNameWrittenAsASpeakerLabelGoes() {
        let attendees = ["Camille Kerjean", "Paul Arnaud"]
        let segment = WhisperTranscript.Segment(tokens: [token(" Camille", 0, 0.3), token(" Ker", 0.3, 0.5), token("jean", 0.5, 0.6),
                                                         token(" :", 0.6, 0.7), token(" On", 0.8, 0.9), token(" y", 0.9, 1),
                                                         token(" va.", 1, 1.2), token(" Paul", 2, 2.2), token(" Arnaud:", 2.2, 2.6),
                                                         token(" Oui.", 2.7, 3)])
        let kept = WhisperTranscript.phrases(of: WhisperTranscript.Run(segments: [segment]), attendees: attendees)
        // The label's words gone; the pause where it was (1.5 s) cuts the phrase.
        XCTAssertEqual(kept.map(MeetingTranscript.joined), ["On y va.", "Oui."])
        // A name said, not a label, stays.
        let said = WhisperTranscript.withoutLabels(WhisperTranscript.words(of: .init(tokens: [token(" Merci", 0, 1), token(" Camille", 1, 2),
                                                                                                token(" Kerjean.", 2, 3)])), attendees: attendees)
        XCTAssertEqual(MeetingTranscript.joined(said), "Merci Camille Kerjean.")
    }

    func testThePromptHoldsTheAttendeesThenTheContactsWithin450Characters() {
        let contacts = (1...60).map { "Contact Number\($0) Lastname" } + ["Paul Arnaud"]
        let prompt = WhisperTranscript.prompt(attendees: ["Paul Arnaud", "Anna Lindqvist"], contacts: ["paul arnaud"] + contacts, language: "en-US")
        XCTAssertTrue(prompt.hasPrefix("Attendees: Paul Arnaud, Anna Lindqvist. Also: Contact Number1 Lastname, "), prompt)
        XCTAssertLessThanOrEqual(prompt.count, 450)
        XCTAssertTrue(prompt.hasSuffix("."))
        XCTAssertEqual(prompt.components(separatedBy: "Paul Arnaud").count, 2, "an attendee once")
        let french = WhisperTranscript.prompt(attendees: ["Maëlys Le Guennec"], contacts: ["Tancrède Abgrall"], language: "fr-FR")
        XCTAssertEqual(french, "Participants : Maëlys Le Guennec. Aussi : Tancrède Abgrall.")
        XCTAssertEqual(WhisperTranscript.prompt(attendees: [], contacts: ["Margot Martin"], language: "en"), "Also: Margot Martin.")
        XCTAssertEqual(WhisperTranscript.prompt(attendees: [], contacts: [], language: "en"), "")
    }

    func testWhispersLanguages() {
        XCTAssertEqual(WhisperTranscript.code(for: "en-US"), "en")
        XCTAssertEqual(WhisperTranscript.code(for: "fr-CA"), "fr")
        XCTAssertEqual(WhisperTranscript.code(for: "nb-NO"), "no")
        XCTAssertEqual(WhisperTranscript.code(for: "it"), "it")
        XCTAssertNil(WhisperTranscript.code(for: "chr"))
        XCTAssertEqual(WhisperTranscript.languages.count, 100)
    }

    func testTheDownloadsRowSaysSizesAndTime() {
        XCTAssertEqual(ModelDownload.size(1_624_555_275), "1.6 GB")
        XCTAssertEqual(ModelDownload.size(412_300_000), "412 MB")
        XCTAssertEqual(ModelDownload.progress(received: 412_000_000, total: 1_624_555_275, bytesPerSecond: nil), "412 MB of 1.6 GB")
        XCTAssertEqual(ModelDownload.progress(received: 412_000_000, total: 1_624_555_275, bytesPerSecond: 6_000_000), "412 MB of 1.6 GB · about 3 min left")
        XCTAssertEqual(ModelDownload.progress(received: 1_600_000_000, total: 1_624_555_275, bytesPerSecond: 6_000_000),
                       "1.6 GB of 1.6 GB · less than a minute left")
        XCTAssertEqual(ModelDownload.roomLine(needed: 1_625_440_373, available: 900_000_000), "1.7 GB free needed on this Mac: 900 MB left.")
        XCTAssertNil(ModelDownload.roomLine(needed: 1_625_440_373, available: 5_000_000_000))
    }
}
