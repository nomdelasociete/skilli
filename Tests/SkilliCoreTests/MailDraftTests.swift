import XCTest
@testable import SkilliCore

final class MailDraftTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(MailDraft.parse("Objet : Commande\n\nBonjour François,\nLa commande arrive lundi."),
                       MailDraft(subject: "Commande", body: "Bonjour François,\nLa commande arrive lundi."))
        XCTAssertEqual(MailDraft.parse("Subject: Order\n\nHi"), MailDraft(subject: "Order", body: "Hi"))
        XCTAssertEqual(MailDraft.parse("**Objet :** Réunion\nBonjour"), MailDraft(subject: "Réunion", body: "Bonjour"))
        // French typography: a no-break space (or a narrow one) before the colon.
        XCTAssertEqual(MailDraft.parse("Objet\u{00A0}: Nouveau contrat\n\nBonjour François"), MailDraft(subject: "Nouveau contrat", body: "Bonjour François"))
        XCTAssertEqual(MailDraft.parse("Objet\u{202F}: Nouveau contrat\nBonjour"), MailDraft(subject: "Nouveau contrat", body: "Bonjour"))
        XCTAssertEqual(MailDraft.parse("**Subject:** Q4 budget\nHi"), MailDraft(subject: "Q4 budget", body: "Hi"))
        XCTAssertEqual(MailDraft.parse("Sujet : Facture\nBonjour"), MailDraft(subject: "Facture", body: "Bonjour"))
        XCTAssertEqual(MailDraft.parse("Bonjour,\nPas d'objet ici"), MailDraft(subject: "", body: "Bonjour,\nPas d'objet ici"))
        XCTAssertEqual(MailDraft.parse("Bonjour Paul"), MailDraft(subject: "", body: "Bonjour Paul"))
    }
}
