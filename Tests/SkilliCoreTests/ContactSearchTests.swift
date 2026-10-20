import XCTest
@testable import SkilliCore

final class ContactSearchTests: XCTestCase {
    private func contact(_ id: String, _ given: String, _ family: String, company: String = "", job: String = "", email: String? = nil,
                         phone: String? = nil, related: ContactRecord.Item? = nil, city: String? = nil) -> ContactRecord {
        var record = ContactRecord(id: id)
        record.givenName = given
        record.familyName = family
        record.organization = company
        record.jobTitle = job
        if let email { record.emails = [.init("work", email)] }
        if let phone { record.phones = [.init("mobile", phone)] }
        if let related { record.relations = [related] }
        if let city { record.addresses = [.init("work", "12 rue Haute, \(city)")] }
        return record
    }

    private var book: [ContactRecord] {
        [
            contact("1", "Jean-François", "Martin", company: "Lumière", job: "Directeur technique", email: "jf.martin@lumiere.example", phone: "+33 6 12 34 56 78"),
            contact("2", "Jean", "Dupont", company: "Lumière", email: "jean.dupont@lumiere.example"),
            contact("3", "François", "Leroy", company: "Horizon", email: "francois.leroy@horizon.example", city: "Villeneuve-d'Ascq"),
            contact("4", "François", "Bernard", company: "Michelin"),
            contact("5", "Marie", "Martin", related: .init("spouse", "Jean-François Martin")),
            contact("6", "Paul", "Durand", company: "Nimbus", job: "CTO", city: "Lyon")
        ]
    }

    func testJBsQuestions() {
        let who = ContactSearch.search("qui est le contact Jean-François qui travaille chez lumière ?", in: book)
        XCTAssertEqual(who.first?.record.id, "1")
        XCTAssertEqual(who.dropFirst().first?.record.id, "2", "the other one at Lumière, behind")
        let mail = ContactSearch.search("créé un mail à françois de chez horizon", in: book)
        XCTAssertEqual(mail.first?.record.id, "3")
        XCTAssertGreaterThan(mail[0].score, mail[1].score * 1.5)
    }

    func testAnyField() {
        XCTAssertEqual(ContactSearch.search("horizon", in: book).first?.record.id, "3")
        XCTAssertEqual(ContactSearch.search("06 12 34", in: book).first?.record.id, "1", "phone digits")
        XCTAssertEqual(ContactSearch.search("cto", in: book).first?.record.id, "6")
        XCTAssertEqual(ContactSearch.search("lyon", in: book).first?.record.id, "6", "the city of an address")
        XCTAssertEqual(ContactSearch.search("jf.martin", in: book).first?.record.id, "1", "an email")
        let related = ContactSearch.search("femme de jean-françois martin", in: book)
        XCTAssertTrue(related.contains { $0.record.id == "5" && $0.field == "Related" } || related.first?.record.id == "1")
        XCTAssertEqual(ContactSearch.search("lumire", in: book).first?.record.organization, "Lumière", "a letter missing")
        let start = ContactSearch.search("fran", in: book)
        XCTAssertEqual(Set(start.prefix(3).map(\.record.id)), ["1", "3", "4"], "the start of a name, names first")
        XCTAssertEqual(start.last?.record.id, "5", "then a related name")
        XCTAssertTrue(ContactSearch.search("qui est le", in: book).isEmpty)
    }

    func testCardText() {
        let text = book[0].details
        XCTAssertTrue(text.hasPrefix("**Jean-François Martin**\nDirecteur technique · Lumière"))
        XCTAssertTrue(text.contains("- jf.martin@lumiere.example (work)"))
        XCTAssertEqual(book[3].subtitle, "Michelin")
        var company = ContactRecord(id: "9")
        company.organization = "Horizon"
        XCTAssertEqual(company.name, "Horizon")
    }

    func testThousandsSearchQuickly() {
        let companies = ["Lumière", "Horizon", "Michelin", "Nimbus", "Renault", "Airbus", "Schneider", "Danone"]
        let given = ["Jean", "Marie", "Paul", "François", "Lucie", "Hugo", "Emma", "Louis"]
        var records: [ContactRecord] = []
        for index in 0..<3_200 {
            var record = ContactRecord(id: "\(index)")
            record.givenName = given[index % given.count]
            record.familyName = "Nom\(index)"
            record.organization = companies[index % companies.count]
            record.jobTitle = index % 3 == 0 ? "Directeur technique" : "Acheteur"
            record.emails = [.init("work", "contact\(index)@example\(index % 50).com")]
            record.phones = [.init("mobile", "+33 6 \(10 + index % 89) \(10 + index % 77) 56 78")]
            record.addresses = [.init("work", "\(index) rue Haute, Lyon")]
            records.append(record)
        }
        let index = ContactSearch.Index(records)
        let sentence = "met la chanson suivante et dis moi quelle heure il est a tokyo"
        // The fastest of several runs: what the search costs, not what else
        // the Mac was doing then (a build beside it made one run 30 × slower).
        func fastest(_ runs: Int, _ body: () -> Void) -> Duration {
            (0..<runs).map { _ in
                let start = ContinuousClock.now
                body()
                return ContinuousClock.now - start
            }.min() ?? .zero
        }
        let each = fastest(5) {
            _ = ContactSearch.search(sentence, in: index, limit: 2)
            _ = ContactSearch.search("françois horizon", in: index, limit: 2)
        } / 2
        print("Contact search over 3200: \(each)")
        let quickEach = fastest(50) { _ = ContactSearch.quickSearch(sentence, in: index, limit: 2) }
        print("Quick contact search over 3200: \(quickEach)")
        XCTAssertLessThan(quickEach, .milliseconds(3))
        // As typed, letter by letter: "ma" alone fits 400 contacts. Each
        // letter's fastest of three.
        var typed = ""
        var slowest = Duration.zero
        for character in "marie horizon" {
            typed.append(character)
            slowest = max(slowest, fastest(3) { _ = ContactSearch.quickSearch(typed, in: index, limit: 2) })
        }
        print("Slowest quick contact search while typing: \(slowest)")
        XCTAssertLessThan(slowest, .milliseconds(3))
        XCTAssertEqual(ContactSearch.quickSearch("marie decath", in: index, limit: 1).first?.record.organization, "Horizon")
        XCTAssertEqual(ContactSearch.quickSearch("nom42", in: index, limit: 1).first?.record.id, "42")
        // Unoptimized test build, on a Mac often building beside it (68 ms
        // seen with three builds running): room for that, still far under
        // what a slower way to search would take. The app's own build is
        // faster still; the launcher's typing speed is measured on the mini.
        XCTAssertLessThan(each, .milliseconds(150))
        XCTAssertEqual(ContactSearch.search("marie horizon", in: index, limit: 1).first?.record.organization, "Horizon")
    }

    func testClearMatch() {
        func match(_ id: String, _ score: Double) -> ContactSearch.Match {
            ContactSearch.Match(record: ContactRecord(id: id), score: score, field: "Name")
        }
        XCTAssertEqual(ContactSearch.clearMatch([match("a", 26), match("b", 9)])?.record.id, "a")
        XCTAssertNil(ContactSearch.clearMatch([match("a", 18), match("b", 17)]), "two close: the user picks")
        XCTAssertNil(ContactSearch.clearMatch([match("a", 4)]), "too weak")
        XCTAssertEqual(ContactSearch.clearMatch([match("a", 10)])?.record.id, "a")
    }
}
