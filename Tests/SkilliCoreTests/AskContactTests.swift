import SkilliCore
import XCTest

final class AskContactTests: XCTestCase {
    private func read(_ request: String, _ pairs: [String: String]) -> AskValues.ContactAsk {
        AskValues.contact(pairs.mapValues { AskValues.Answer(choice: $0, confidence: 0.9) }, words: AskValues.words(of: request))
    }


    /// The option of `text` among the request's phrases.
    private func phrase(_ request: String, _ text: String, longest: Int = 6) -> String {
        "phrase \(AskValues.phrases(of: AskValues.words(of: request), longest: longest).firstIndex(of: text) ?? -1)"
    }

    func testWhoTheyAre() {
        XCTAssertEqual(read("qui est Jean-François de chez Lumière ?", ["contact": "who", "person": phrase("qui est Jean-François de chez Lumière ?", "Jean-François de chez Lumière")]),
                       .who(person: "Jean-François de chez Lumière"))
    }

    func testAMail() {
        let request = "écris à François de chez Horizon pour lui dire que la commande arrive lundi"
        XCTAssertEqual(read(request, ["contact": "mail", "person": phrase(request, "François de chez Horizon"), "says": "yes"]),
                       .mail(person: "François de chez Horizon", says: true))
        XCTAssertEqual(read("crée un mail à Marie", ["contact": "mail", "person": phrase("crée un mail à Marie", "Marie"), "says": "no"]),
                       .mail(person: "Marie", says: false))
    }

    func testNoOneNamed() {
        guard case .missing = read("écris un mail", ["contact": "mail", "person": "none"]) else {
            return XCTFail("a mail to no one")
        }
    }

    func testQuestionsFit() {
        let questions = AskValues.contactQuestions(words: AskValues.words(of: String(repeating: "mot ", count: 80)))
        XCTAssertTrue(questions.allSatisfy { $0.options.count <= 255 })
        XCTAssertEqual(Set(questions.map(\.name)).count, questions.count)
    }
}
