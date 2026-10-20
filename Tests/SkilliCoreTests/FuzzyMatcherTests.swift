import XCTest
@testable import SkilliCore

final class FuzzyMatcherTests: XCTestCase {
    private func score(_ query: String, _ text: String) -> Int? {
        FuzzyMatcher.score(FuzzyMatcher.Query(query), FuzzyCandidate(text))
    }

    func testNonSubsequenceDoesNotMatch() {
        XCTAssertNil(score("xyz", "Safari"))
        XCTAssertNil(score("safarii", "Safari"))
    }

    func testEmptyQueryMatchesEverythingNeutrally() {
        XCTAssertEqual(score("", "Safari"), 0)
        XCTAssertEqual(score("   ", "Safari"), 0)
    }

    func testPrefixBeatsMiddleOfWord() throws {
        let prefix = try XCTUnwrap(score("term", "Terminal"))
        let middle = try XCTUnwrap(score("term", "Determined"))
        XCTAssertGreaterThan(prefix, middle)
    }

    func testWordStartsBeatScatteredLetters() throws {
        let initials = try XCTUnwrap(score("vsc", "Visual Studio Code"))
        let scattered = try XCTUnwrap(score("vsc", "Movies Scanner"))
        XCTAssertGreaterThan(initials, scattered)
    }

    func testExactMatchBeatsLongerCandidate() throws {
        let exact = try XCTUnwrap(score("notes", "Notes"))
        let longer = try XCTUnwrap(score("notes", "Notes Helper"))
        XCTAssertGreaterThan(exact, longer)
    }

    func testFoldsCaseAndDiacritics() {
        XCTAssertNotNil(score("prefe", "Préférences Système"))
        XCTAssertNotNil(score("PRÉF", "preferences"))
    }

    /// System Settings writes "Wi\u{2011}Fi" (a non-breaking hyphen):
    /// "wi-fi" typed finds it; "’" and "'" are the same.
    func testDashesAndApostrophesFold() {
        XCTAssertNotNil(score("wi-fi", "Wi\u{2011}Fi"))
        XCTAssertNotNil(score("wi\u{2011}fi", "Wi-Fi"))
        XCTAssertNotNil(score("jusqu'a", "Jusqu\u{2019}à"))
        XCTAssertNotNil(score("a-b", "A\u{2013}B"))
    }

    func testQueryWhitespaceIsIgnored() {
        XCTAssertNotNil(score("visual code", "Visual Studio Code"))
    }

    func testMarksCamelCaseAndSeparatorWordStarts() {
        let normalized = FuzzyMatcher.normalize("GitIsland my-app")
        let starts = zip(normalized.scalars, normalized.wordStarts)
            .filter(\.1)
            .map { String($0.0) }
        XCTAssertEqual(starts, ["g", "i", "m", "a"])
    }

    /// A name typed whole: case, accents, spaces, punctuation and its
    /// plural "s" aside; never one word among others, nor a start.
    func testNamesANameTypedWholeOnly() {
        func names(_ query: String, _ text: String) -> Bool {
            FuzzyMatcher.names(FuzzyMatcher.Query(query), FuzzyCandidate(text))
        }
        XCTAssertTrue(names("displays", "Displays"))
        XCTAssertTrue(names("display", "Displays"), "the plural left out")
        XCTAssertTrue(names("moniteur", "Moniteurs"))
        XCTAssertTrue(names("ECRAN VERROUILLE", "Écran verrouillé"))
        XCTAssertTrue(names("wifi", "Wi‑Fi"), "a non-breaking hyphen, as System Settings writes it")
        XCTAssertTrue(names("wi-fi", "Wi‑Fi"))
        XCTAssertTrue(names("nightshift", "Night Shift"))
        XCTAssertTrue(names("touch id password", "Touch ID & Password"))
        XCTAssertFalse(names("display", "Move to Next Display"), "one word among others")
        XCTAssertFalse(names("disp", "Displays"), "a start")
        XCTAssertFalse(names("bluetooth", "Allow Bluetooth"))
        XCTAssertFalse(names("displayx", "Displays"))
        XCTAssertFalse(names("as", "Ass"), "the plural only after three letters")
        XCTAssertFalse(names("note", "Notes Helper"))
        XCTAssertFalse(names("", "Safari"))
    }

    func testLaterAnchorCanWin() throws {
        // First "c" is mid-word; the word-start "c" later must be found.
        let best = try XCTUnwrap(score("code", "Xcode Code"))
        let midWordOnly = try XCTUnwrap(score("code", "Xcode"))
        XCTAssertGreaterThan(best, midWordOnly)
    }
}
