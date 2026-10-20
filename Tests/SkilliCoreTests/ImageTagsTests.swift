@testable import SkilliCore
import XCTest

final class ImageTagsTests: XCTestCase {
    func testJevsAnswersBecomeTags() {
        XCTAssertEqual(ImageTags(kind: "invoice", kindProbability: 0.92, personProbability: 0.1), ImageTags(kind: .invoice, person: false))
        XCTAssertEqual(ImageTags(kind: "chart", kindProbability: 0.4, personProbability: nil).kind, .other, "unsure: other")
        XCTAssertEqual(ImageTags(kind: "nonsense", kindProbability: 0.9, personProbability: 0.8), ImageTags(kind: .other, person: true))
    }

    func testTheWordsFindItInEitherLanguage() {
        let words = ImageTags(kind: .invoice, person: false).words
        XCTAssertTrue(words.hasPrefix("invoice "))
        XCTAssertTrue(words.contains("facture"))
        XCTAssertTrue(ImageTags(kind: .chart, person: true).words.contains("graphique"))
        XCTAssertTrue(ImageTags(kind: .chart, person: true).words.contains("personne"))
        XCTAssertEqual(ImageTags(kind: .other, person: false).words, "other")
    }

    /// The preview says what SI saw in one sentence; nothing when it
    /// could not tell.
    func testWhatSISawInOneSentence() {
        XCTAssertEqual(ImageTags(kind: .invoice, person: false).sentence, "SI sees an invoice, a receipt or a bill.")
        XCTAssertEqual(ImageTags(kind: .photo, person: true).sentence, "SI sees a photo, with a person in it.")
        XCTAssertEqual(ImageTags(kind: .other, person: true).sentence, "SI sees a person in it.")
        XCTAssertNil(ImageTags(kind: .other, person: false).sentence)
        for kind in ImageTags.Kind.allCases where kind != .other {
            let sentence = ImageTags(kind: kind, person: false).sentence ?? ""
            XCTAssertTrue(sentence.hasPrefix("SI sees ") && sentence.hasSuffix("."), sentence)
            XCTAssertNil(sentence.range(of: #"\bAI\b"#, options: .regularExpression), "the brand says SI")
        }
    }

    func testStoredWordsReadBack() {
        for kind in ImageTags.Kind.allCases {
            for person in [false, true] {
                let tags = ImageTags(kind: kind, person: person)
                XCTAssertEqual(ImageTags(words: tags.words), tags)
            }
        }
        XCTAssertNil(ImageTags(words: ""))
        XCTAssertNil(ImageTags(words: "hello world"))
    }
}
