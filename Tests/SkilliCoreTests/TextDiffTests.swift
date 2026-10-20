import XCTest
@testable import SkilliCore

final class TextDiffTests: XCTestCase {

    func testCloseWordsShowOnlyTheLettersThatChanged() throws {
        XCTAssertEqual(TextDiff.segments(from: "enfant", to: "enfants"), [
            TextDiff.Segment(.same, "enfant"), TextDiff.Segment(.inserted, "s")
        ])
        XCTAssertEqual(TextDiff.segments(from: "manger", to: "mangé"), [
            TextDiff.Segment(.same, "mang"), TextDiff.Segment(.deleted, "er"), TextDiff.Segment(.inserted, "é")
        ])
        XCTAssertEqual(TextDiff.segments(from: "les", to: "Les"), [
            TextDiff.Segment(.deleted, "l"), TextDiff.Segment(.inserted, "L"), TextDiff.Segment(.same, "es")
        ])
        XCTAssertEqual(TextDiff.segments(from: "pome", to: "pommes"), [
            TextDiff.Segment(.same, "pom"), TextDiff.Segment(.inserted, "m"), TextDiff.Segment(.same, "e"), TextDiff.Segment(.inserted, "s")
        ])
    }

    func testDifferentWordsAreReplacedWhole() throws {
        XCTAssertEqual(TextDiff.segments(from: "the cat", to: "the dog"), [
            TextDiff.Segment(.same, "the "), TextDiff.Segment(.deleted, "cat"), TextDiff.Segment(.inserted, "dog")
        ])
    }

    func testFullCorrectionMarksFewCharacters() throws {
        let segments = try XCTUnwrap(TextDiff.segments(from: "les enfant on manger des pome", to: "Les enfants ont mangé des pommes."))
        let inserted = segments.filter { $0.kind == .inserted }.map(\.text).joined()
        let deleted = segments.filter { $0.kind == .deleted }.map(\.text).joined()
        XCTAssertEqual(inserted, "Lstéms.")
        XCTAssertEqual(deleted, "ler")
    }

    func testDeletionComesBeforeItsReplacement() throws {
        let segments = try XCTUnwrap(TextDiff.segments(from: "a cat sat", to: "a dog sat"))
        XCTAssertEqual(segments, [
            TextDiff.Segment(.same, "a "), TextDiff.Segment(.deleted, "cat"), TextDiff.Segment(.inserted, "dog"), TextDiff.Segment(.same, " sat")
        ])
    }

    func testRebuildsBothTexts() throws {
        let old = "Hello, wide world! It's fine."
        let new = "Hello wide world. It is fine!"
        let segments = try XCTUnwrap(TextDiff.segments(from: old, to: new))
        XCTAssertEqual(segments.filter { $0.kind != .inserted }.map(\.text).joined(), old)
        XCTAssertEqual(segments.filter { $0.kind != .deleted }.map(\.text).joined(), new)
    }

    func testIdenticalTextIsOneSameSegment() throws {
        XCTAssertEqual(TextDiff.segments(from: "Déjà vu.", to: "Déjà vu."), [TextDiff.Segment(.same, "Déjà vu.")])
    }

    func testSimilarityIsLowForATranslation() throws {
        let fix = try XCTUnwrap(TextDiff.segments(from: "the cat sat on teh mat", to: "the cat sat on the mat"))
        let translation = try XCTUnwrap(TextDiff.segments(from: "le chat est sur le tapis", to: "the cat is on the mat"))
        XCTAssertGreaterThan(TextDiff.similarity(fix), 0.8)
        XCTAssertLessThan(TextDiff.similarity(translation), 0.4)
    }

    func testCharacterSimilaritySeparatesFixesFromTranslations() throws {
        let fixes = [
            ("les enfant on manger des pome", "Les enfants ont mangé des pommes."),
            ("je sui allé au marcher hier", "Je suis allé au marché hier."),
            ("Their going too the store tomorow, isnt it?", "They're going to the store tomorrow, aren't they?")
        ]
        let translations = [
            ("le chat est sur le tapis", "the cat is on the mat"),
            ("Je vous remercie pour votre retour rapide.", "Thank you for your quick reply."),
            ("Can we move the meeting to Thursday afternoon?", "Peut-on déplacer la réunion à jeudi après-midi ?")
        ]
        for (old, new) in fixes {
            XCTAssertGreaterThan(try XCTUnwrap(TextDiff.characterSimilarity(old, new)), 0.75, "\(old) → \(new)")
        }
        for (old, new) in translations {
            XCTAssertLessThan(try XCTUnwrap(TextDiff.characterSimilarity(old, new)), 0.75, "\(old) → \(new)")
        }
    }

    func testTooLongIsSkipped() {
        let long = String(repeating: "word ", count: 3_000)
        XCTAssertNil(TextDiff.segments(from: long, to: long + "more"))
    }

    func testTokensSplitPunctuationAndKeepApostrophes() {
        XCTAssertEqual(TextDiff.tokens("l'école, ok"), ["l'école", ",", " ", "ok"])
    }
}

final class PromptFileTests: XCTestCase {
    func testFrontMatterAndBody() {
        let file = PromptFile(parsing: "---\ntitle: Fix Spelling & Grammar\n---\nFix spelling.\nKeep the tone.\n")
        XCTAssertEqual(file.title, "Fix Spelling & Grammar")
        XCTAssertEqual(file.instruction, "Fix spelling.\nKeep the tone.")
    }

    func testBodyOnly() {
        let file = PromptFile(parsing: "\nTranslate into natural English.\n")
        XCTAssertNil(file.title)
        XCTAssertEqual(file.instruction, "Translate into natural English.")
    }

    func testQuotedTitleAndUnknownKeys() {
        let file = PromptFile(parsing: "---\r\ntitle: \"Shorter\"\r\nshortcut: hyper+k s\r\n---\r\nMake it shorter.")
        XCTAssertEqual(file.title, "Shorter")
        XCTAssertEqual(file.instruction, "Make it shorter.")
    }

    func testRoundTrip() {
        let file = PromptFile(title: "Improve Writing", instruction: "Rewrite to be clearer.")
        XCTAssertEqual(PromptFile(parsing: file.text), file)
    }
}
