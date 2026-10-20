import Foundation

/// A contact as its card shows it, as Apple's Contacts does: a monogram
/// when there is no photo, then each field with its label on the left.
public extension ContactRecord {
    /// One line of the card: "mobile  +33 6 12 34 56 78".
    struct CardRow: Equatable, Sendable {
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    /// "JM" for Jean-François Martin, "T" for Lumière alone: the monogram
    /// Contacts draws without a photo.
    var initials: String {
        let person = [givenName, familyName].filter { !$0.isEmpty }
        let source = person.isEmpty ? [name] : person
        return source.compactMap { $0.first.map { String($0).uppercased() } }.prefix(2).joined()
    }

    /// The fields in Contacts' order: phones (the mobile first), emails,
    /// addresses (each on its lines), websites, profiles, related people,
    /// birthday, note. Labels lowercase as Contacts writes them; none said,
    /// what the field is.
    var cardRows: [CardRow] {
        func rows(_ items: [Item], _ kind: String) -> [CardRow] {
            items.map { CardRow($0.label.isEmpty ? kind : $0.label.lowercased(), $0.value) }
        }
        let mobileFirst = phones.enumerated().sorted { a, b in
            let mobile = { (label: String) in ["mobile", "iphone", "portable", "cell"].contains { label.lowercased().contains($0) } }
            return mobile(a.element.label) != mobile(b.element.label) ? mobile(a.element.label) : a.offset < b.offset
        }.map(\.element)
        var list = rows(mobileFirst, "phone") + rows(emails, "email")
        if postal.count == addresses.count, !postal.isEmpty {
            list += postal.map { address in
                let city = [address.postalCode, address.city].filter { !$0.isEmpty }.joined(separator: " ")
                let lines = [address.street, city, address.country].filter { !$0.isEmpty }.joined(separator: "\n")
                return CardRow(address.label.isEmpty ? "address" : address.label.lowercased(), lines)
            }
        } else {
            list += rows(addresses, "address")
        }
        list += rows(urls, "website") + rows(social, "profile") + rows(relations, "related")
        if let birthday, !birthday.isEmpty { list.append(CardRow("birthday", birthday)) }
        if let note, !note.isEmpty { list.append(CardRow("note", note)) }
        return list
    }
}
