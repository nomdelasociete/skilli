import Foundation

/// Whose details "do it here" types into a form, and which: the user's own
/// card ("Moi"), or the person the request is for ("remplis ça pour
/// Margot"). The decision model only ever reads what each detail is
/// ("Postal code"), never its value: values are typed on this Mac.
public enum FormProfile {
    /// One detail a form may ask for.
    public struct Detail: Equatable, Sendable {
        /// "postalCode": what the model answers with.
        public let key: String
        /// "Postal code (code postal, ZIP)": what the model reads.
        public let description: String
        /// What is typed; never sent.
        public let value: String
        /// Typed only once the user said so in the card (an IBAN).
        public var isSensitive = false

        public init(key: String, description: String, value: String, isSensitive: Bool = false) {
            self.key = key
            self.description = description
            self.value = value
            self.isSensitive = isSensitive
        }

        /// "IBAN", "postal code": its name without its translations, as a
        /// question says it.
        public var name: String {
            let label = description.components(separatedBy: " (").first ?? key
            return key.hasPrefix("extra-") ? label : label.lowercased()
        }
    }

    /// "Type your IBAN and BIC in Safari?": the sensitive details one form
    /// gets, known together, asked once. `whose`: "your", "Margot's".
    public static func typingQuestion(_ details: [Detail], whose: String, in app: String) -> String {
        let names = details.map(\.name)
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : names.first ?? ""
        return "Type \(whose) \(list)\(app.isEmpty ? "" : " in \(app)")?"
    }

    /// Fields the user keeps in skil.li beyond the Contacts card, with
    /// whether each is sensitive (its value then in the Keychain).
    public static let suggestedFields: [(label: String, sensitive: Bool)] = [
        ("SIRET", false), ("SIREN", false), ("N° TVA intracommunautaire", false), ("Code NAF / APE", false),
        ("IBAN", true), ("BIC", true), ("N° de sécurité sociale", true), ("N° de passeport", true),
        ("N° de permis de conduire", true), ("Lieu de naissance", false), ("Nationalité", false)
    ]

    /// A Contacts card's details, then the fields kept in skil.li (an
    /// extra field named like a card detail does not replace it).
    public static func details(of record: ContactRecord?, extras: [FormExtra], value: (FormExtra) -> String?) -> [Detail] {
        let card = record.map(details(of:)) ?? []
        return card + extras.compactMap { extra in
            guard let typed = value(extra), !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Detail(key: "extra-\(extra.id.uuidString)", description: "\(extra.label) (field kept in skil.li)", value: typed,
                          isSensitive: extra.isSensitive)
        }
    }

    /// The person or company kept in skil.li that `words` name ("pour
    /// Margot", "pour Nimbus"): the first word starts their name.
    public static func match(_ words: [String], in people: [FormPerson]) -> FormPerson? {
        guard let first = words.first.map(fold) else { return nil }
        let fitting = people.filter { person in
            let name = fold(person.name).split(separator: " ").map(String.init)
            guard name.first == first else { return false }
            guard let second = words.dropFirst().first.map(fold), name.count > 1 else { return true }
            return name[1].hasPrefix(second) || !people.contains { fold($0.name).split(separator: " ").dropFirst().first.map(String.init)?.hasPrefix(second) == true }
        }
        return fitting.count == 1 ? fitting[0] : nil
    }

    private static func fold(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
    }

    /// The details `record` has, the likeliest asked first: names, email,
    /// phone (the mobile), address in parts, company, birthday.
    public static func details(of record: ContactRecord) -> [Detail] {
        let phones = record.phones.sorted { isMobile($0.label) && !isMobile($1.label) }
        let address = record.postal.first
        let candidates: [(String, String, String?)] = [
            ("givenName", "First name (prénom)", record.givenName),
            ("familyName", "Last name, family name (nom, nom de famille)", record.familyName),
            ("fullName", "Full name (nom complet, nom et prénom)", [record.givenName, record.familyName].filter { !$0.isEmpty }.joined(separator: " ")),
            ("email", "Email address (e-mail, courriel, adresse électronique)", record.emails.first?.value),
            ("phone", "Phone number (téléphone, mobile, portable)", phones.first?.value),
            ("street", "Street address, number and street (adresse, rue, voie)", address?.street),
            ("postalCode", "Postal code, ZIP (code postal)", address?.postalCode),
            ("city", "City, town (ville, commune)", address?.city),
            ("country", "Country (pays)", address?.country),
            ("company", "Company, organization (entreprise, société, organisme)", record.organization),
            ("jobTitle", "Job title (fonction, poste)", record.jobTitle),
            ("birthday", "Date of birth (date de naissance)", record.birthdayNumeric),
            ("website", "Website (site web)", record.urls.first?.value)
        ]
        return candidates.compactMap { key, description, value in
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Detail(key: key, description: description, value: value)
        }
    }

    /// The name the request says it is for: "remplis ça pour Margot",
    /// "fill this in for Paul Martin": the one or two words after "pour" or
    /// "for". Nil when it says no one (then the user's own card).
    public static func person(in request: String) -> [String] {
        let words = request.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "." || $0 == "!" || $0 == "?" }).map(String.init)
        guard let index = words.lastIndex(where: { ["pour", "for"].contains($0.lowercased()) }), index + 1 < words.count else { return [] }
        let after = words[(index + 1)...].prefix(2)
        // "pour la commande", "for the order": an article is not a name.
        let articles: Set<String> = ["le", "la", "les", "l'", "un", "une", "des", "du", "ce", "cet", "cette", "mon", "ma", "mes", "the", "a", "an", "my", "this", "me", "moi"]
        guard let first = after.first, !articles.contains(first.lowercased()) else { return [] }
        return Array(after)
    }

    private static func isMobile(_ label: String) -> Bool {
        ["mobile", "iphone", "portable", "cell"].contains { label.lowercased().contains($0) }
    }
}

/// A field kept in skil.li for a form profile: "SIRET", "IBAN"… A sensitive
/// one keeps its value in the Keychain, never here.
public struct FormExtra: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var isSensitive: Bool
    /// The value when not sensitive.
    public var value: String

    public init(id: UUID = UUID(), label: String, isSensitive: Bool, value: String = "") {
        self.id = id
        self.label = label
        self.isSensitive = isSensitive
        self.value = value
    }
}

/// Someone else whose details forms may get: a person (their Contacts card
/// by name) or a company, with fields of its own.
public struct FormPerson: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// "Margot Martin", "Nimbus SAS": what "pour …" names.
    public var name: String
    public var extras: [FormExtra]

    public init(id: UUID = UUID(), name: String, extras: [FormExtra] = []) {
        self.id = id
        self.name = name
        self.extras = extras
    }
}

/// Settings → Your Details: the user's own fields beyond My Card, and the people
/// and companies kept in skil.li.
public struct FormProfiles: Codable, Equatable, Sendable {
    public var mine: [FormExtra]
    public var others: [FormPerson]

    public init(mine: [FormExtra] = [], others: [FormPerson] = []) {
        self.mine = mine
        self.others = others
    }
}
