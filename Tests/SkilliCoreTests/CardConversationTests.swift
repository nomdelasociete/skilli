import XCTest
@testable import SkilliCore

final class CardConversationTests: XCTestCase {
    func testFollowUpCarriesTheConversation() {
        var conversation = CardConversation()
        conversation.add(request: "explique ce mot\n\n\"\"\"\nBonjour\n\"\"\"", answer: "C'est une salutation.")
        conversation.add(request: "et en anglais ?", answer: "Hello.", steps: ["Read the selection"])
        let message = conversation.message(followUp: "  et en espagnol ?  ")
        XCTAssertTrue(message.hasPrefix("This continues a conversation the user started in skil.li"))
        let first = message.range(of: "User:\nexplique ce mot")
        let second = message.range(of: "User:\net en anglais ?\n\nWhat you did on their Mac:\n- Read the selection\n\nYou answered:\nHello.")
        let now = message.range(of: "The user now asks:\net en espagnol ?\n\n")
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(now)
        XCTAssertTrue(first!.upperBound < second!.lowerBound && second!.upperBound < now!.lowerBound)
        XCTAssertTrue(message.hasSuffix("with the conversation in mind."))
    }

    func testLongConversationsDropTheOldestTurns() {
        var conversation = CardConversation()
        for index in 1...6 { conversation.add(request: "question \(index) " + String(repeating: "x", count: 20_000), answer: "answer \(index)") }
        let message = conversation.message(followUp: "last")
        XCTAssertFalse(message.contains("question 1 "))
        XCTAssertTrue(message.contains("question 6 "))
        XCTAssertLessThan(message.count, 90_000)
    }

    func testRefiningAskForTheTextAlone() {
        var conversation = CardConversation()
        conversation.add(request: "Fix the spelling:\n\nbonjour a tous", answer: "Bonjour à tous.")
        let message = conversation.message(refining: "  plus formel ")
        XCTAssertTrue(message.contains("User:\nFix the spelling:\n\nbonjour a tous"))
        XCTAssertTrue(message.contains("You answered:\nBonjour à tous."))
        XCTAssertTrue(message.contains("They want it changed again:\nplus formel\n"))
        XCTAssertTrue(message.hasSuffix("no quotes, no comment, nothing before or after it."))
    }

    func testHandoffKeepsEarlierTurns() {
        var conversation = CardConversation()
        conversation.add(request: "first", answer: "one")
        let text = Handoff.conversation(request: "second", answer: "two", earlier: conversation.turns, for: .claude)
        XCTAssertTrue(text.contains("User:\nfirst\n\nYou answered:\none\n\nUser:\nsecond"))
        XCTAssertTrue(text.contains("You answered:\ntwo"))
    }
}
