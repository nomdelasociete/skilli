@testable import SkilliCore
import XCTest

final class DictationTests: XCTestCase {
    private func contact(_ id: String, _ given: String, _ family: String = "", company: String = "", phone: Bool = true) -> ContactRecord {
        var record = ContactRecord(id: id)
        record.givenName = given
        record.familyName = family
        record.organization = company
        if phone { record.phones = [.init("mobile", "+33 6 12 34 56 78")] }
        return record
    }

    // MARK: - Vocabulary

    func testNamesAndCompaniesAsPeopleSayThem() {
        XCTAssertEqual(DictationVocabulary.name(of: contact("1", "Margot", "Martin")), "Margot Martin")
        XCTAssertEqual(DictationVocabulary.name(of: contact("2", "Jean-François", "Martaing")), "Jean-François Martaing")
        XCTAssertEqual(DictationVocabulary.name(of: contact("3", "Maman")), "Maman")
        XCTAssertNil(DictationVocabulary.name(of: contact("4", "")), "a card with no name gives none")
        XCTAssertNil(DictationVocabulary.name(of: contact("5", "😀")), "a name needs a letter")
        XCTAssertEqual(DictationVocabulary.company("Nimbus SAS"), "Nimbus")
        XCTAssertEqual(DictationVocabulary.company("Apple, Inc."), "Apple")
        XCTAssertEqual(DictationVocabulary.company("Nom de la Société S.A.S."), "Nom de la Société")
        XCTAssertEqual(DictationVocabulary.company("SA"), "SA", "a name that is only a legal form stays")
        XCTAssertNil(DictationVocabulary.company("   "))
        XCTAssertNil(DictationVocabulary.company("The International Federation of Things"), "longer than four words: too long to say at once")
    }

    func testOrderMeThenPickedThenSharedCompaniesThenTheRest() {
        let contacts = [
            contact("a", "Alice", "Durand", company: "Acme"),
            contact("b", "Bruno", "Petit", company: "Lumière"),
            contact("c", "Chloé", "Roux", company: "Lumière"),
            contact("d", "David", "Noir", phone: false),
            contact("e", "Emma", "Blanc")
        ]
        let me = contact("me", "Jean-François", "Martaing", company: "Nimbus SAS")
        let vocabulary = DictationVocabulary(contacts: contacts, me: me, picks: ["e": 3, "c": 1, "zz": 9])
        XCTAssertEqual(vocabulary.phrases, [
            "Nimbus", "Jean-François Martaing",
            "Emma Blanc", "Chloé Roux", "Lumière",
            "Alice Durand", "Acme", "Bruno Petit",
            "David Noir"
        ])
    }

    func testEachPhraseOnceAndAtMostTheLimit() {
        let contacts = [contact("x", "PERSON0", "name")]
            + (0..<300).map { contact("\($0)", "Person\($0)", "Name", company: "Company") }
        let vocabulary = DictationVocabulary(contacts: contacts)
        XCTAssertEqual(vocabulary.phrases.count, DictationVocabulary.limit)
        XCTAssertEqual(vocabulary.phrases.first, "Company", "shared by everyone: first")
        XCTAssertEqual(vocabulary.phrases.filter { $0.lowercased() == "person0 name" }.count, 1, "case aside, once")
        XCTAssertEqual(DictationVocabulary(contacts: []).phrases, [])
    }

    func testNamesKeepTheirCapital() {
        let vocabulary = DictationVocabulary(contacts: [contact("1", "Jean-François", "Martaing", company: "Lumière")])
        XCTAssertTrue(vocabulary.isName("Martaing"))
        XCTAssertTrue(vocabulary.isName("lumiere"), "accents and case aside")
        XCTAssertTrue(vocabulary.isName("Jean-François"))
        XCTAssertTrue(vocabulary.isName("François"))
        XCTAssertFalse(vocabulary.isName("Je"))
    }

    // MARK: - Text

    func testPiecesJoinWithOneSpace() {
        XCTAssertEqual(DictationText.joined("", "Bonjour."), "Bonjour.")
        XCTAssertEqual(DictationText.joined("Bonjour.", "Comment ça va ?"), "Bonjour. Comment ça va ?")
        XCTAssertEqual(DictationText.joined("Bonjour.", " Comment"), "Bonjour. Comment")
        XCTAssertEqual(DictationText.joined("Bonjour ", "Paul"), "Bonjour Paul")
        XCTAssertEqual(DictationText.joined("Bonjour", ", Paul"), "Bonjour, Paul")
        XCTAssertEqual(DictationText.joined("Done", ""), "Done")
    }

    func testSpacesTrimmedAndCollapsedLineBreaksKept() {
        XCTAssertEqual(DictationText.collapsed("  Bonjour   Paul \n\n  à demain  "), "Bonjour Paul\n\nà demain")
        XCTAssertEqual(DictationText.insertion("   ", after: "Text"), "")
        XCTAssertEqual(DictationText.insertion("Hello  there.", after: nil), "Hello there.", "unknown caret: as heard")
    }

    func testStartOfASentenceGetsItsCapitalNoSpace() {
        XCTAssertEqual(DictationText.insertion("bonjour Paul.", after: ""), "Bonjour Paul.")
        XCTAssertEqual(DictationText.insertion("à demain.", after: "Merci. "), "À demain.")
        XCTAssertEqual(DictationText.insertion("next point", after: "Done!"), " Next point")
        XCTAssertEqual(DictationText.insertion("second line", after: "First line\n"), "Second line")
        XCTAssertEqual(DictationText.insertion("Je t'envoie le devis.", after: "   "), "Je t'envoie le devis.")
    }

    func testMidSentenceTheFirstWordGoesLowercaseUnlessAName() {
        let names = DictationVocabulary(contacts: [contact("1", "Margot", "Martin")])
        XCTAssertEqual(DictationText.insertion("Je t'envoie le devis.", after: "Bonjour Paul,", isName: names.isName), " je t'envoie le devis.")
        XCTAssertEqual(DictationText.insertion("Ça marche.", after: "Bonjour, ", isName: names.isName), "ça marche.")
        XCTAssertEqual(DictationText.insertion("J'ai vu le devis", after: "Hier", isName: names.isName), " j'ai vu le devis")
        XCTAssertEqual(DictationText.insertion("Margot viendra.", after: "Demain,", isName: names.isName), " Margot viendra.")
        XCTAssertEqual(DictationText.insertion("Margot's file", after: "Here is", isName: names.isName), " Margot's file")
        XCTAssertEqual(DictationText.insertion("I think so.", after: "Well,"), " I think so.")
        XCTAssertEqual(DictationText.insertion("I'm in.", after: "Yes,"), " I'm in.")
        XCTAssertEqual(DictationText.insertion("NASA called", after: "Then"), " NASA called")
        XCTAssertEqual(DictationText.insertion("Voici la liste", after: "Note :"), " voici la liste")
    }

    func testNoSpaceAfterAnOpeningOrBeforePunctuation() {
        XCTAssertEqual(DictationText.insertion("Le devis", after: "Voir ("), "Le devis", "after a bracket: as heard, no space")
        XCTAssertEqual(DictationText.insertion(", et puis", after: "Bonjour"), ", et puis")
        XCTAssertEqual(DictationText.insertion("devis", after: "« "), "devis")
        XCTAssertEqual(DictationText.insertion("Devis", after: "“"), "Devis", "after a quote: as heard")
    }
}
