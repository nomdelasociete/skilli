@testable import SkilliCore
import XCTest

final class FormProfileTests: XCTestCase {
    func testDetailsInFormOrderWithTheMobileFirst() {
        var margot = ContactRecord(id: "p")
        margot.givenName = "Margot"
        margot.familyName = "Martaing"
        margot.emails = [.init("home", "margot@example.com")]
        margot.phones = [.init("home", "01 23 45 67 89"), .init("mobile", "06 12 34 56 78")]
        margot.postal = [.init(label: "home", street: "12 rue des Lilas", postalCode: "75011", city: "Paris", country: "France")]
        margot.birthdayNumeric = "14/03/1990"
        let details = FormProfile.details(of: margot)
        XCTAssertEqual(details.map(\.key), ["givenName", "familyName", "fullName", "email", "phone", "street", "postalCode", "city", "country", "birthday"])
        XCTAssertEqual(details.first { $0.key == "phone" }?.value, "06 12 34 56 78")
        XCTAssertEqual(details.first { $0.key == "fullName" }?.value, "Margot Martaing")
        XCTAssertFalse(details.contains { $0.description.contains("Margot") || $0.description.contains("75011") }, "descriptions never hold values")
    }

    func testWhoTheRequestIsFor() {
        XCTAssertEqual(FormProfile.person(in: "remplis ça pour Margot"), ["Margot"])
        XCTAssertEqual(FormProfile.person(in: "fill this in for Paul Martin"), ["Paul", "Martin"])
        XCTAssertEqual(FormProfile.person(in: "remplis le formulaire"), [])
        XCTAssertEqual(FormProfile.person(in: "remplis-le pour la commande"), [])
        XCTAssertEqual(FormProfile.person(in: "remplis ça pour moi"), [])
    }

    func testFieldsKeptInSkilliComeAfterTheCardAndKeepTheirSensitivity() {
        var me = ContactRecord(id: "me")
        me.givenName = "Jean"
        let siret = FormExtra(label: "SIRET", isSensitive: false, value: "123 456 789 00012")
        let iban = FormExtra(label: "IBAN", isSensitive: true)
        let empty = FormExtra(label: "BIC", isSensitive: true)
        let details = FormProfile.details(of: me, extras: [siret, iban, empty]) { extra in
            extra.isSensitive ? (extra.id == iban.id ? "FR76 3000 6000 0112 3456 7890 189" : nil) : extra.value
        }
        XCTAssertEqual(details.map(\.description).suffix(2), ["SIRET (field kept in skil.li)", "IBAN (field kept in skil.li)"])
        XCTAssertEqual(details.last?.isSensitive, true)
        XCTAssertEqual(details.first { $0.description.hasPrefix("SIRET") }?.isSensitive, false)
        XCTAssertFalse(details.contains { $0.description.hasPrefix("BIC") }, "no value, no detail")
        XCTAssertFalse(details.contains { $0.description.contains("FR76") }, "descriptions never hold values")
    }

    func testPeopleKeptInSkilliByName() {
        let people = [FormPerson(name: "Margot Martin"), FormPerson(name: "Paul Durand"), FormPerson(name: "Nimbus SAS"), FormPerson(name: "Paul Martin")]
        XCTAssertEqual(FormProfile.match(["Margot"], in: people)?.name, "Margot Martin")
        XCTAssertEqual(FormProfile.match(["nimbus"], in: people)?.name, "Nimbus SAS")
        XCTAssertNil(FormProfile.match(["Paul"], in: people), "two Pauls")
        XCTAssertEqual(FormProfile.match(["Paul", "Durand"], in: people)?.name, "Paul Durand")
        XCTAssertNil(FormProfile.match(["Marie"], in: people))
    }
}
