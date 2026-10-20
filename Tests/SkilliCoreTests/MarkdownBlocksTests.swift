import XCTest
@testable import SkilliCore

final class MarkdownBlocksTests: XCTestCase {
    func testBlocks() {
        let text = """
        ## Two tasks
        Deux tâches en cours :

        - **SAFR-123** « Développer le lot 3 »
          - sub point
        1. first
        12) twelfth
        > a quote
        ```swift
        let x = 1
        ```
        ---
        #hashtag stays text
        """
        let lines = MarkdownBlocks.lines(text)
        XCTAssertEqual(lines[0], .init(.heading(level: 2), "Two tasks"))
        XCTAssertEqual(lines[1], .init(.paragraph, "Deux tâches en cours :"))
        XCTAssertEqual(lines[2], .init(.blank, ""))
        XCTAssertEqual(lines[3], .init(.bullet(depth: 0), "**SAFR-123** « Développer le lot 3 »"))
        XCTAssertEqual(lines[4], .init(.bullet(depth: 1), "sub point"))
        XCTAssertEqual(lines[5], .init(.numbered(marker: "1.", depth: 0), "first"))
        XCTAssertEqual(lines[6], .init(.numbered(marker: "12)", depth: 0), "twelfth"))
        XCTAssertEqual(lines[7], .init(.quote, "a quote"))
        XCTAssertEqual(lines[8], .init(.code, "let x = 1"))
        XCTAssertEqual(lines[9], .init(.rule, ""))
        XCTAssertEqual(lines[10], .init(.paragraph, "#hashtag stays text"))
    }

    func testPlainAndDetection() {
        let strip: (String) -> String = { $0.replacingOccurrences(of: "**", with: "") }
        XCTAssertEqual(MarkdownBlocks.plain("## Title\n- **a** b\n2. c", plainInline: strip), "Title\n• a b\n2. c")
        XCTAssertTrue(MarkdownBlocks.looksLikeMarkdown("Deux tâches : **SAFR-123**"))
        XCTAssertTrue(MarkdownBlocks.looksLikeMarkdown("- one\n- two"))
        XCTAssertFalse(MarkdownBlocks.looksLikeMarkdown("C'est une salutation. Rien d'autre - vraiment."))
        XCTAssertFalse(MarkdownBlocks.looksLikeMarkdown("Il est 14 h 05."))
    }
}
