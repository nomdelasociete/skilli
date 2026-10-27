@testable import SkilliCore
import XCTest

final class MeetingFollowUpTests: XCTestCase {
    private func line(_ speaker: Voice, _ start: Double, _ text: String) -> TranscriptLine {
        let words = text.split(separator: " ").enumerated().map { index, word in
            TranscriptWord(String(word), start: start + Double(index) * 0.4, end: start + Double(index) * 0.4 + 0.3)
        }
        return TranscriptLine(speaker: speaker, words: words)
    }

    private var lines: [TranscriptLine] {
        [line(.me, 0.5, "Hello everyone."), line(.them, 4.2, "Loud and clear."), line(Voice.them(2), 240.7, "On the budget, we are short."),
         line(.me, 610, "Paul, send the screens by Friday.")]
    }

    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func testTheTranscriptNamesTheUserAndShowsTheSlidesAtTheirTime() {
        let text = MeetingFollowUp.transcript(title: "Weekly sync", date: "Wednesday 22 October 2026, 14:00", lines: lines,
                                              names: ["me": "Camille", "them": "Paul", "them2": "Anna"],
                                              slides: [SlideLog.Slide(start: 240.7, lines: ["Budget", "Q3: −12 %"])])
        XCTAssertEqual(text, """
            Meeting: Weekly sync
            Date: Wednesday 22 October 2026, 14:00

            [0:00] Camille (the user): Hello everyone.
            [0:04] Paul: Loud and clear.
            [4:00] On screen: Budget · Q3: −12 %
            [4:00] Anna: On the budget, we are short.
            [10:10] Camille (the user): Paul, send the screens by Friday.
            """)
    }

    func testEachRequestSaysTheLanguageAndQuotesTheTranscript() {
        let summary = MeetingFollowUp.summaryRequest("Meeting: X", language: "fr-FR")
        XCTAssertTrue(summary.contains("in French"))
        XCTAssertTrue(summary.hasSuffix("\"\"\"\nMeeting: X\n\"\"\""))
        XCTAssertTrue(MeetingFollowUp.chaptersRequest("Meeting: X", language: "en-US").contains("in English"))
        XCTAssertTrue(MeetingFollowUp.actionItemsRequest("Meeting: X", language: "en-US", date: "2026-10-22").contains("on 2026-10-22"))
        XCTAssertTrue(MeetingFollowUp.askRequest("  What about the budget? ", transcript: "Meeting: X")
            .contains("Question: What about the budget?\n"))
    }

    func testChaptersLandOnTheLinesThatStartThere() {
        let answer = """
            ```json
            [{"start": "0:03", "title": "Hello"}, {"start": "4:00", "title": "The budget"}, {"start": "4:00", "title": "Twice"},
             {"start": 600, "title": "Next\\nsteps"}, {"start": "59:00", "title": "Past the end"}, {"start": "x", "title": "No time"}]
            ```
            """
        let chapters = MeetingFollowUp.chapters(from: answer, lines: lines)
        XCTAssertEqual(chapters, [.init(title: "Hello", start: 0.5), .init(title: "The budget", start: 240.7),
                                  .init(title: "Next steps", start: 610)])
        XCTAssertNil(MeetingFollowUp.chapters(from: "Sorry, I can't.", lines: lines))
        XCTAssertNil(MeetingFollowUp.chapters(from: "[]", lines: lines))
        XCTAssertNil(MeetingFollowUp.chapters(from: "[{\"start\": \"1:00\", \"title\": \"A\"}]", lines: []))
    }

    func testTheChaptersAreHeadingsInTheMarkdown() {
        let markdown = MeetingTranscript.markdown(title: "Weekly sync", about: "Wed", lines: lines, names: ["me": "Camille"],
                                                  chapters: [.init(title: "Hello", start: 0.5), .init(title: "The budget", start: 240.7)])
        XCTAssertTrue(markdown.contains("Wed\n\n## Hello\n\n**Camille** · 0:00\nHello everyone.\n"))
        XCTAssertTrue(markdown.contains("Loud and clear.\n\n## The budget\n\n**them2**".replacingOccurrences(of: "them2", with: "Them 2")))
        XCTAssertEqual(MeetingTranscript.chapterLines([.init(title: "Late", start: 9999)], in: lines), [:])
    }

    func testActionItemsKnowWhoseAndWhen() throws {
        let answer = """
            [{"task": "Send the final screens", "owner": "Paul", "due": "2026-10-24", "at": "10:10"},
             {"task": "Book the room", "owner": "me", "due": null, "at": "4:00"},
             {"task": "Write to Anna", "owner": "camille", "due": "soon"},
             {"task": "", "owner": "Paul"}, {"owner": "Paul"}]
            """
        let items = try XCTUnwrap(MeetingFollowUp.actionItems(from: answer, ownNames: ["Camille"], calendar: paris))
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].owner, "Paul")
        XCTAssertEqual(items[0].due, paris.date(from: DateComponents(year: 2026, month: 10, day: 24)))
        XCTAssertEqual(items[0].at, 610)
        XCTAssertNil(items[1].owner, "the user's own")
        XCTAssertNil(items[2].owner, "the user by name")
        XCTAssertNil(items[2].due, "not a day")
        XCTAssertEqual(MeetingFollowUp.actionItems(from: "[]"), [])
        XCTAssertNil(MeetingFollowUp.actionItems(from: "None."))
    }

    func testAReminderSaysWhoseItIsWhenNotTheUsers() {
        XCTAssertEqual(MeetingFollowUp.reminderTitle(.init(task: "Send the final screens", owner: "Paul", due: nil, at: nil)),
                       "Paul: send the final screens")
        XCTAssertEqual(MeetingFollowUp.reminderTitle(.init(task: "PDF export", owner: "Anna", due: nil, at: nil)), "Anna: PDF export")
        XCTAssertEqual(MeetingFollowUp.reminderTitle(.init(task: "Book the room", owner: nil, due: nil, at: nil)), "Book the room")
    }

    func testTheSummaryFileKeepsTheSummary() {
        let file = MeetingFollowUp.summaryFile(title: "Weekly sync", summary: "\nIt went well.\n\n### Decided\n- Ship it\n")
        XCTAssertEqual(file, "# Summary of Weekly sync\n\nIt went well.\n\n### Decided\n- Ship it\n")
        XCTAssertEqual(MeetingFollowUp.summary(inFile: file), "It went well.\n\n### Decided\n- Ship it")
        let recap = MeetingFollowUp.recap(title: "Weekly sync", day: "Wed 22 Oct", plain: "It went well.")
        XCTAssertEqual(recap.subject, "Recap: Weekly sync")
        XCTAssertEqual(recap.body, "Here is the recap of Weekly sync, Wed 22 Oct.\n\nIt went well.\n")
    }

    func testTimesAreReadAsTheTranscriptWritesThem() {
        XCTAssertEqual(MeetingFollowUp.seconds("12:04"), 724)
        XCTAssertEqual(MeetingFollowUp.seconds("[1:02:03]"), 3723)
        XCTAssertEqual(MeetingFollowUp.seconds(90), 90)
        XCTAssertNil(MeetingFollowUp.seconds("soon"))
        XCTAssertNil(MeetingFollowUp.seconds("1:2:3:4"))
        XCTAssertEqual(MeetingFollowUp.languageName("fr-FR"), "French")
    }

    func testARecordWithoutPhaseFiveFieldsStillReads() throws {
        var record = MeetingRecord(title: "Weekly sync", started: Date(timeIntervalSince1970: 0), language: "en-US", recorder: nil)
        let before = try MeetingRecord.decode(record.encoded())
        XCTAssertNil(before.summarized)
        record.summarized = .init(at: Date(timeIntervalSince1970: 60), by: "Claude · Haiku")
        record.addresses = ["paul@example.com"]
        record.chapters = [.init(title: "Hello", start: 0.5)]
        XCTAssertEqual(try MeetingRecord.decode(record.encoded()), record)
    }
}
