import XCTest
@testable import SkilliCore

final class SnippetTests: XCTestCase {
    func testFileRoundTrip() {
        let snippet = Snippet(id: "adresse", name: "Adresse: maison", keyword: ";addr", text: "12 rue des Lilas\n75011 Paris")
        let parsed = Snippet(id: "adresse", parsing: snippet.file)
        XCTAssertEqual(parsed, snippet)
        XCTAssertTrue(snippet.file.contains("name: \"Adresse: maison\""))
    }

    func testHandWrittenFile() {
        let parsed = Snippet(id: "sig", parsing: "---\ntitle: Signature\nkeyword: !sig\n---\nCamille\n— skil.li\n")
        XCTAssertEqual(parsed.name, "Signature")
        XCTAssertEqual(parsed.keyword, "!sig")
        XCTAssertEqual(parsed.text, "Camille\n— skil.li")
        let bare = Snippet(id: "plain", parsing: "Just text\n")
        XCTAssertEqual(bare.name, "plain")
        XCTAssertEqual(bare.keyword, "")
        XCTAssertEqual(bare.text, "Just text")
    }

    func testExpansionFillsVariablesAndPlacesTheCursor() {
        let snippet = Snippet(id: "r", name: "Reply", text: "Bonjour {cursor},\n\nÀ {day} !")
        let expanded = snippet.expanded([.day: "lundi"])
        XCTAssertEqual(expanded.text, "Bonjour ,\n\nÀ lundi !")
        XCTAssertEqual(expanded.cursorFromEnd, ",\n\nÀ lundi !".count)
        let plain = Snippet(id: "d", name: "Date", text: "{date}").expanded([.date: "12 octobre 2026"])
        XCTAssertEqual(plain.text, "12 octobre 2026")
        XCTAssertEqual(plain.cursorFromEnd, 0)
    }

    func testMatcherSymbolKeywordsAtOnceLetterKeywordsAtTheWordsEnd() {
        let snippets = [
            Snippet(id: "a", name: "Address", keyword: ";addr", text: "x"),
            Snippet(id: "b", name: "Thanks", keyword: "ty", text: "Thank you"),
            Snippet(id: "c", name: "Address long", keyword: ";addr2", text: "y")
        ]
        var matcher = SnippetMatcher()
        matcher.type("voici ;addr")
        XCTAssertEqual(matcher.match(snippets)?.snippet.id, "a")
        XCTAssertEqual(matcher.match(snippets)?.delimiter, "")
        matcher.type("2")
        XCTAssertEqual(matcher.match(snippets)?.snippet.id, "c")
        matcher.reset()
        matcher.type("ok ty")
        XCTAssertNil(matcher.match(snippets), "a letter keyword waits for its word to end")
        matcher.type(",")
        XCTAssertEqual(matcher.match(snippets)?.snippet.id, "b")
        XCTAssertEqual(matcher.match(snippets)?.delimiter, ",")
        matcher.reset()
        matcher.type("pretty ")
        XCTAssertNil(matcher.match(snippets), "“ty” ending a word does not expand")
        matcher.reset()
        matcher.type("ty")
        matcher.type("pe ")
        XCTAssertNil(matcher.match(snippets), "“type” is not “ty”")
        matcher.reset()
        matcher.type(" ty ")
        matcher.deleteBackward()
        XCTAssertNil(matcher.match(snippets))
    }

    func testFileIDs() {
        XCTAssertEqual(Snippet.fileID(for: "Mon adresse perso"), "mon-adresse-perso")
        XCTAssertEqual(Snippet.fileID(for: "Réponse « merci »"), "reponse-merci")
        XCTAssertEqual(Snippet.fileID(for: "!!!"), "snippet")
    }

    private let address = Snippet(id: "a", name: "Address", keyword: "addr", text: "12 rue des Lilas")
    private let signature = Snippet(id: "s", name: "Signature", keyword: ";sig", text: "Camille{cursor}")

    /// Today's behavior stays the default: a symbol keyword at once, a
    /// letter keyword at its word's end with the space kept.
    func testAsSoonAsTypedIsTodaysBehavior() {
        let snippets = [address, signature]
        XCTAssertEqual(SnippetMatcher.result(of: "voici ;sig", snippets: snippets, mode: .immediately), "voici Camille")
        XCTAssertEqual(SnippetMatcher.result(of: "chez addr ", snippets: snippets, mode: .immediately), "chez 12 rue des Lilas ")
        XCTAssertEqual(SnippetMatcher.result(of: "chez addr, merci", snippets: snippets, mode: .immediately), "chez 12 rue des Lilas, merci")
        XCTAssertEqual(SnippetMatcher.result(of: "address ", snippets: snippets, mode: .immediately), "address ")
        // ↩ after a letter keyword: no word ended for it.
        XCTAssertEqual(SnippetMatcher.result(of: "addr\n", snippets: snippets, mode: .immediately), "addr\n")
    }

    func testAfterASpaceOrReturnKeepsIt() {
        let snippets = [address, signature]
        XCTAssertEqual(SnippetMatcher.result(of: "voici ;sig", snippets: snippets, mode: .afterDelimiterKept), "voici ;sig",
                       "a symbol keyword waits too")
        XCTAssertEqual(SnippetMatcher.result(of: "voici ;sig ", snippets: snippets, mode: .afterDelimiterKept), "voici Camille ")
        XCTAssertEqual(SnippetMatcher.result(of: "chez addr ", snippets: snippets, mode: .afterDelimiterKept), "chez 12 rue des Lilas ")
        XCTAssertEqual(SnippetMatcher.result(of: "chez addr, ", snippets: snippets, mode: .afterDelimiterKept), "chez addr, ",
                       "a mark is not a space or ↩")
        XCTAssertEqual(SnippetMatcher.result(of: "addr\nok", snippets: snippets, mode: .afterDelimiterKept), "12 rue des Lilas\nok")
        XCTAssertEqual(SnippetMatcher.result(of: "address ", snippets: snippets, mode: .afterDelimiterKept), "address ")
        XCTAssertEqual(SnippetMatcher.result(of: "myaddr ", snippets: snippets, mode: .afterDelimiterKept), "myaddr ",
                       "a letter keyword needs a word start")
    }

    func testAfterASpaceOrReturnLeavesItOut() {
        let snippets = [address, signature]
        XCTAssertEqual(SnippetMatcher.result(of: "chez addr ", snippets: snippets, mode: .afterDelimiterRemoved), "chez 12 rue des Lilas")
        XCTAssertEqual(SnippetMatcher.result(of: ";sig\n", snippets: snippets, mode: .afterDelimiterRemoved), "Camille")
        XCTAssertEqual(SnippetMatcher.result(of: "addr  x", snippets: snippets, mode: .afterDelimiterRemoved), "12 rue des Lilas x")
    }

    /// What the expander does: how much it erases, what it types after,
    /// whether ↩ is held back and pressed again.
    func testExpansionErasesAndRetypes() throws {
        var matcher = SnippetMatcher()
        matcher.type("chez addr ")
        let kept = try XCTUnwrap(matcher.match([address], mode: .afterDelimiterKept))
        XCTAssertEqual(kept.erase, 5)
        XCTAssertEqual(kept.typedAfter, " ")
        XCTAssertFalse(kept.holdsKey)
        let left = try XCTUnwrap(matcher.match([address], mode: .afterDelimiterRemoved))
        XCTAssertEqual(left.erase, 5)
        XCTAssertEqual(left.typedAfter, "")

        matcher.reset()
        matcher.type("addr\n")
        let enter = try XCTUnwrap(matcher.match([address], mode: .afterDelimiterKept))
        XCTAssertTrue(enter.holdsKey, "↩ never reaches the app with the keyword")
        XCTAssertEqual(enter.erase, 4)
        XCTAssertEqual(enter.typedAfter, "")
        XCTAssertTrue(enter.pressesReturnAfter)
        XCTAssertFalse(try XCTUnwrap(matcher.match([address], mode: .afterDelimiterRemoved)).pressesReturnAfter)
        XCTAssertNil(matcher.match([address], mode: .immediately))

        matcher.reset()
        matcher.type(";sig")
        let atOnce = try XCTUnwrap(matcher.match([signature]))
        XCTAssertEqual(atOnce.delimiter, "")
        XCTAssertEqual(atOnce.erase, 4)
        XCTAssertFalse(atOnce.holdsKey)
    }

    func testModesHaveTitlesAndTodayFirst() {
        XCTAssertEqual(SnippetExpansionMode.allCases.first, .immediately)
        XCTAssertEqual(Set(SnippetExpansionMode.allCases.map(\.title)).count, SnippetExpansionMode.allCases.count)
        XCTAssertFalse(SnippetExpansionMode.immediately.waitsForDelimiter)
        XCTAssertTrue(SnippetExpansionMode.afterDelimiterRemoved.waitsForDelimiter)
    }

    /// What goes to the decision model: the name, the keyword and the
    /// first 80 characters as written, never filled in, a bank number as
    /// what it is.
    func testMeaningSendsNameKeywordAndFirstWordsOnly() {
        let iban = Snippet(id: "iban", name: "IBAN perso", keyword: ";iban",
                           text: "FR76 3000 6000 0112 3456 7890 189\nBIC AGRIFRPP882\n{clipboard}\n" + String(repeating: "x", count: 200))
        let line = SnippetMeaning.describe(iban)
        XCTAssertTrue(line.hasPrefix("“IBAN perso” (keyword ;iban): (an IBAN) BIC AGRIFRPP882"), line)
        XCTAssertFalse(line.contains("3000"), "the number itself never goes")
        XCTAssertTrue(line.contains("{clipboard}"), "placeholders stay as written")
        XCTAssertLessThanOrEqual(line.count, "“IBAN perso” (keyword ;iban): ".count + SnippetMeaning.previewLength + 1)
        XCTAssertFalse(line.contains(String(repeating: "x", count: 100)))
        XCTAssertEqual(SnippetMeaning.describe(Snippet(id: "n", name: "Note", text: "")), "“Note”")
        XCTAssertTrue(SnippetMeaning.input("mon iban").hasSuffix("mon iban"))
        XCTAssertEqual(SnippetMeaning.value(3), "s3")
    }

    /// Bank and card numbers and keys in free text go as what they are; the
    /// words around them stay.
    func testSecretsInTextGoAsWhatTheyAre() {
        XCTAssertEqual(ToolCallSummary.maskingSecrets("Mon IBAN : FR76 3000 6000 0112 3456 7890 189, merci"), "Mon IBAN : (an IBAN) merci")
        XCTAssertEqual(ToolCallSummary.maskingSecrets("FR7630006000011234567890189"), "(an IBAN)")
        XCTAssertEqual(ToolCallSummary.maskingSecrets("Carte 4111 1111 1111 1111 exp 12/28"), "Carte (a card number) exp 12/28")
        XCTAssertEqual(ToolCallSummary.maskingSecrets("token sk-proj-abcdefghijklmnop1234 ici"), "token (a key) ici")
        XCTAssertEqual(ToolCallSummary.maskingSecrets("12 rue des Lilas, 75011 Paris"), "12 rue des Lilas, 75011 Paris")
        XCTAssertEqual(ToolCallSummary.maskingSecrets("Rendez-vous à 14h05 le 3 novembre"), "Rendez-vous à 14h05 le 3 novembre")
        XCTAssertTrue(ToolCallSummary.hasIBANCheckDigits("GB82 WEST 1234 5698 7654 32"))
        XCTAssertFalse(ToolCallSummary.hasIBANCheckDigits("GB83 WEST 1234 5698 7654 32"))
        XCTAssertEqual(ClipboardMeaning.excerpt("Virement sur FR76 3000 6000 0112 3456 7890 189"), "Virement sur (an IBAN)")
    }

    func testMeaningPicksTheLikelyOnesBestFirst() {
        let picked = SnippetMeaning.picked(["s2": 0.7, "s0": 0.2, "s5": 0.03, "none": 0.05, "s9": 0.5], choice: "s2", count: 6)
        XCTAssertEqual(picked, [2, 0], "under 4 % and unknown indexes left out")
        XCTAssertEqual(SnippetMeaning.picked(["none": 0.8, "s1": 0.15], choice: "none", count: 3), [])
        XCTAssertEqual(SnippetMeaning.picked(["none": 0.5, "s1": 0.4], choice: "none", count: 3), [1])
        let many = Dictionary(uniqueKeysWithValues: (0..<12).map { ("s\($0)", 0.08) })
        XCTAssertEqual(SnippetMeaning.picked(many, choice: "s0", count: 12).count, 8)
    }
}
