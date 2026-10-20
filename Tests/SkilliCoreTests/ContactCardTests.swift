import SkilliCore
import XCTest

final class ContactCardTests: XCTestCase {
    private func person() -> ContactRecord {
        var record = ContactRecord(id: "1")
        record.givenName = "Jean-François"
        record.familyName = "Martin"
        record.organization = "Lumière"
        record.phones = [.init("work", "+33 1 23 45 67 89"), .init("Mobile", "+33 6 12 34 56 78")]
        record.emails = [.init("", "jf.martin@lumiere.example")]
        record.addresses = [.init("home", "12 rue des Lilas, 75011 Paris, France")]
        record.postal = [.init(label: "home", street: "12 rue des Lilas", postalCode: "75011", city: "Paris", country: "France")]
        record.birthday = "12 March"
        return record
    }

    func testInitials() {
        XCTAssertEqual(person().initials, "JM")
        var company = ContactRecord(id: "2")
        company.organization = "Lumière"
        XCTAssertEqual(company.initials, "L")
    }

    /// Contacts' order and labels: the mobile first, a label said for each,
    /// the address on its lines.
    func testRowsInContactsOrder() {
        XCTAssertEqual(person().cardRows, [
            .init("mobile", "+33 6 12 34 56 78"),
            .init("work", "+33 1 23 45 67 89"),
            .init("email", "jf.martin@lumiere.example"),
            .init("home", "12 rue des Lilas\n75011 Paris\nFrance"),
            .init("birthday", "12 March")
        ])
    }
}
