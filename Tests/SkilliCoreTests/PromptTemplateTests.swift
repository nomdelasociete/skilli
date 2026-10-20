import XCTest
@testable import SkilliCore

final class PromptTemplateTests: XCTestCase {
    func testRendersKnownVariablesAndKeepsUnknownOnes() {
        let template = PromptTemplate("Reply to {selection} for {app} on {date}. Keep {braces} and {unclosed.")
        let rendered = template.render([.selection: "hi", .app: "Mail", .date: "11 Oct"])
        XCTAssertEqual(rendered, "Reply to hi for Mail on 11 Oct. Keep {braces} and {unclosed.")
    }

    func testMissingValuesBecomeEmpty() {
        XCTAssertEqual(PromptTemplate("[{clipboard}]").render([:]), "[]")
    }

    func testUsesIsCaseInsensitiveAndIgnoresSpaces() {
        XCTAssertTrue(PromptTemplate("Fix this:\n{ Selection }").uses(.selection))
        XCTAssertFalse(PromptTemplate("Fix this text.").uses(.selection))
    }

    func testTokensReportUnknownNames() {
        let tokens = PromptTemplate("{date} {nope} {}").tokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens.map(\.variable), [.date, nil])
    }

    func testCompletions() {
        XCTAssertEqual(PromptTemplate.completions(for: "da"), [.date, .datetime, .day])
        XCTAssertEqual(PromptTemplate.completions(for: "").count, PromptTemplate.Variable.allCases.count)
        XCTAssertEqual(PromptTemplate.completions(for: "zz"), [])
    }
}

final class PromptFileSettingsTests: XCTestCase {
    func testProfileAndModel() {
        let file = PromptFile(parsing: "---\ntitle: Improve\nprofile: true\nmodel: Sonnet\n---\nRewrite.\n\n{selection}")
        XCTAssertEqual(file.title, "Improve")
        XCTAssertTrue(file.includeProfile)
        XCTAssertEqual(file.model, "sonnet")
        XCTAssertEqual(file.instruction, "Rewrite.\n\n{selection}")
    }

    func testDefaultsWhenAbsent() {
        let file = PromptFile(parsing: "---\nmodel: default\n---\nFix.")
        XCTAssertFalse(file.includeProfile)
        XCTAssertNil(file.model)
    }

    func testRoundTripWithSettings() {
        let file = PromptFile(title: "Reply", instruction: "Answer {selection} as me.", includeProfile: true, model: "haiku")
        XCTAssertEqual(PromptFile(parsing: file.text), file)
    }
}

final class PromptTemplateQuestionsAndModifiersTests: XCTestCase {
    func testQuestionTokensUseAnswers() {
        let template = PromptTemplate("Answer in a {ask.tone} tone, {ask.Length | lower}. {ask.} {ask.a.b}")
        XCTAssertEqual(template.questionIDs(), ["tone", "length"])
        let rendered = template.render([:], answers: ["tone": "Friendly", "length": "SHORT"])
        XCTAssertEqual(rendered, "Answer in a Friendly tone, short. {ask.} {ask.a.b}")
    }

    func testModifiersApplyInOrder() {
        let template = PromptTemplate("[{selection | trim | upper}] [{clipboard|raw}] [{selection}]")
        let rendered = template.render(
            [.selection: "  hi there \n", .clipboard: "clip"],
            quoting: [.selection, .clipboard],
            quote: { "<\($0)>" }
        )
        XCTAssertEqual(rendered, "[<HI THERE>] [clip] [<  hi there \n>]")
    }

    func testUnknownModifierLeavesTokenAsTyped() {
        let template = PromptTemplate("{selection | shout} {date | nope}")
        XCTAssertEqual(template.render([.selection: "x", .date: "d"]), "{selection | shout} {date | nope}")
        XCTAssertFalse(template.uses(.selection))
        XCTAssertEqual(template.tokens().filter(\.isKnown).count, 0)
    }

    func testJSONIsNotAToken() {
        XCTAssertEqual(PromptTemplate("Reply as {\"a\": 1} or {1}.").tokens().count, 0)
    }

    func testEmptyValuesAreNotQuoted() {
        XCTAssertEqual(PromptTemplate("[{clipboard}]").render([.clipboard: ""], quoting: [.clipboard], quote: { "<\($0)>" }), "[]")
    }
}

final class PromptFileOutputAndQuestionsTests: XCTestCase {
    private let sample = """
        ---
        title: Reply to This Email
        profile: true
        output: card
        ask:
          - id: tone
            question: Which tone?
            options: [Friendly, "Formal, polite", Short]
            default: Friendly
          - question: Anything to add?
        ---
        Answer in a {ask.tone} tone.

        {selection}
        """

    func testParsesOutputAndQuestions() {
        let file = PromptFile(parsing: sample)
        XCTAssertEqual(file.title, "Reply to This Email")
        XCTAssertTrue(file.includeProfile)
        XCTAssertEqual(file.output, .card)
        XCTAssertEqual(file.questions, [
            PromptQuestion(id: "tone", question: "Which tone?", options: ["Friendly", "Formal, polite", "Short"], defaultValue: "Friendly"),
            PromptQuestion(id: "anything-to-add", question: "Anything to add?")
        ])
        XCTAssertEqual(file.instruction, "Answer in a {ask.tone} tone.\n\n{selection}")
    }

    func testRoundTrip() {
        let file = PromptFile(parsing: sample)
        XCTAssertEqual(PromptFile(parsing: file.text), file)
        let tricky = PromptFile(
            title: "T",
            instruction: "Go.",
            output: .insert,
            questions: [PromptQuestion(id: "q", question: "Pick: one", options: ["a \"b\"", "c[d]", "e\\f"], defaultValue: "c[d]")]
        )
        XCTAssertEqual(PromptFile(parsing: tricky.text), tricky)
    }

    func testDefaultMustBeAnOptionAndUnknownOutputIsIgnored() {
        let file = PromptFile(parsing: "---\noutput: shout\nask:\n  - id: x\n    question: X?\n    options: a, b\n    default: c\n---\nGo.")
        XCTAssertNil(file.output)
        XCTAssertEqual(file.questions.first?.options, ["a", "b"])
        XCTAssertNil(file.questions.first?.defaultValue)
    }

    func testNoFrontMatterWhenEmpty() {
        XCTAssertEqual(PromptFile(title: nil, instruction: "Fix.").text, "Fix.\n")
    }
}

final class CommandLinkTests: XCTestCase {
    func testLinkCarriesWholeFiles() throws {
        let files = ["---\ntitle: A & B + C\noutput: copy\n---\nSay {selection} #1?", "Fix."]
        let link = CommandLink.importLink(for: files)
        XCTAssertFalse(link.absoluteString.contains("+"))
        XCTAssertEqual(CommandLink.parse(link), CommandLink.Request(files: files))
    }

    func testURLsMustBeHTTPS() throws {
        let link = try XCTUnwrap(URL(string: "skilli://commands/import?url=https%3A%2F%2Fskil.li%2Fc%2Freply.md&url=http%3A%2F%2Fevil.test%2Fa.md&url=file%3A%2F%2F%2Fetc%2Fpasswd"))
        XCTAssertEqual(CommandLink.parse(link)?.urls, [URL(string: "https://skil.li/c/reply.md")!])
    }

    func testRejectsOtherLinks() throws {
        XCTAssertNil(CommandLink.parse(try XCTUnwrap(URL(string: "skilli://commands/delete?command=x"))))
        XCTAssertNil(CommandLink.parse(try XCTUnwrap(URL(string: "skilli://commands/import"))))
        XCTAssertNil(CommandLink.parse(try XCTUnwrap(URL(string: "https://commands/import?command=x"))))
    }
}
