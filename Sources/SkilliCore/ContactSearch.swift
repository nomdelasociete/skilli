import Foundation

/// A contact as skil.li searches it: every field the Contacts app has that
/// a Mac app may read (the note only with Apple's permission).
public struct ContactRecord: Equatable, Sendable, Identifiable {
    /// "work: jf.martin@lumiere.example", "spouse: Marie Martin".
    public struct Item: Equatable, Sendable {
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public let id: String
    public var givenName = ""
    public var middleName = ""
    public var familyName = ""
    public var nickname = ""
    public var organization = ""
    public var department = ""
    public var jobTitle = ""
    public var emails: [Item] = []
    public var phones: [Item] = []
    public var addresses: [Item] = []
    public var urls: [Item] = []
    public var social: [Item] = []
    /// Related people: "spouse: Marie Martin", "assistant: Paul".
    public var relations: [Item] = []
    public var birthday: String?
    public var note: String?
    /// The addresses in parts, for forms (same order as `addresses`).
    public var postal: [PostalAddress] = []
    /// "14/03/1985" as this Mac writes dates: what forms ask.
    public var birthdayNumeric: String?

    public struct PostalAddress: Equatable, Sendable {
        public let label: String
        public let street: String
        public let postalCode: String
        public let city: String
        public let country: String

        public init(label: String, street: String, postalCode: String, city: String, country: String) {
            self.label = label
            self.street = street
            self.postalCode = postalCode
            self.city = city
            self.country = country
        }
    }

    public init(id: String) {
        self.id = id
    }

    /// "Jean-François Martin", else the company.
    public var name: String {
        let person = [givenName, middleName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !person.isEmpty { return person }
        return organization.isEmpty ? (emails.first?.value ?? "No Name") : organization
    }

    /// "Directeur technique · Lumière", else the first address or number.
    public var subtitle: String {
        let work = [jobTitle, organization].filter { !$0.isEmpty }
        if !work.isEmpty, name != organization { return work.joined(separator: " · ") }
        return emails.first?.value ?? phones.first?.value ?? ""
    }

    /// The contact as Markdown, for the card.
    public var details: String {
        var lines = ["**\(name)**"]
        if !subtitle.isEmpty, subtitle != emails.first?.value { lines.append(subtitle) }
        if !nickname.isEmpty { lines.append("“\(nickname)”") }
        func items(_ list: [Item]) -> [String] { list.map { $0.label.isEmpty ? "- \($0.value)" : "- \($0.value) (\($0.label))" } }
        lines += items(emails) + items(phones) + items(addresses) + items(urls) + items(social)
        if !relations.isEmpty { lines.append("- Related: " + relations.map { $0.label.isEmpty ? $0.value : "\($0.value) (\($0.label))" }.joined(separator: ", ")) }
        if let birthday { lines.append("- Birthday: \(birthday)") }
        if let note, !note.isEmpty { lines.append("\n" + note) }
        return lines.joined(separator: "\n")
    }
}

/// Contacts by any of their fields, best first, without a model: "jean
/// françois lumiere", "horizon", "06 12", "marie" (a related name).
public enum ContactSearch {
    public struct Match: Equatable, Sendable {
        public let record: ContactRecord
        public let score: Double
        /// Where the strongest word matched: "Organization", "Email"…
        public let field: String
    }

    /// Words that only carry the sentence ("qui est le contact … qui
    /// travaille chez …").
    static let fillers: Set<String> = [
        "qui", "est", "le", "la", "les", "l", "de", "du", "des", "d", "chez", "a", "au", "aux", "en", "et", "un", "une", "mon", "ma", "mes",
        "ce", "cette", "son", "sa", "ses", "il", "elle", "c", "quel", "quelle", "quels", "travaille", "bosse", "contact", "contacts",
        "cherche", "trouve", "trouver", "affiche", "montre", "donne", "moi", "numero", "telephone", "tel", "mail", "email", "e", "adresse",
        "cree", "creer", "ecris", "ecrire", "envoie", "envoyer", "redige", "pour", "lui", "dire", "que",
        "the", "at", "of", "in", "from", "my", "who", "is", "works", "work", "working", "find", "show", "search", "number", "phone", "address",
        "write", "send", "create", "draft", "an", "to", "for", "and", "with"
    ]

    /// Lowercased words without accents; phone numbers keep their digits.
    public static func words(_ text: String) -> [String] {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// The words that may name someone.
    public static func queryWords(_ query: String) -> [String] {
        words(query).filter { !fillers.contains($0) }
    }

    public static func search(_ query: String, in records: [ContactRecord], limit: Int = 20) -> [Match] {
        search(query, in: Index(records), limit: limit)
    }

    /// Every contact's words, read once (accents and case gone, as bytes):
    /// a search then only compares, a few milliseconds for thousands.
    public struct Index: Sendable {
        struct Field: Sendable {
            let name: String
            let weight: Double
            let tokens: [[UInt8]]
        }

        struct Entry: Sendable {
            let record: ContactRecord
            /// `record.name`, built once: ties are ordered by it.
            let name: String
            let fields: [Field]
            let phoneDigits: [String]
        }

        let entries: [Entry]
        /// Names, nicknames and companies, sorted: a search as the user types
        /// looks words up here (by their start) instead of going through
        /// every contact.
        let quick: [(token: [UInt8], entry: Int, weight: Double, field: String)]
        public var count: Int { entries.count }

        public init(_ records: [ContactRecord]) {
            self.entries = Self.entries(records)
            var quick: [(token: [UInt8], entry: Int, weight: Double, field: String)] = []
            for (position, entry) in entries.enumerated() {
                for field in entry.fields where field.weight >= 8 {
                    for token in field.tokens { quick.append((token, position, field.weight, field.name)) }
                }
            }
            self.quick = quick.sorted { $0.token.lexicographicallyPrecedes($1.token) }
        }

        private static func entries(_ records: [ContactRecord]) -> [Entry] {
            return records.map { record in
                func tokens(_ values: [String]) -> [[UInt8]] { values.flatMap(ContactSearch.words).map { Array($0.utf8) } }
                let fields = [
                    Field(name: "Name", weight: 10, tokens: tokens([record.givenName, record.middleName, record.familyName])),
                    Field(name: "Nickname", weight: 9, tokens: tokens([record.nickname])),
                    Field(name: "Organization", weight: 8, tokens: tokens([record.organization])),
                    Field(name: "Job", weight: 5, tokens: tokens([record.jobTitle])),
                    Field(name: "Department", weight: 4, tokens: tokens([record.department])),
                    Field(name: "Email", weight: 6, tokens: tokens(record.emails.map(\.value))),
                    Field(name: "Related", weight: 3, tokens: tokens(record.relations.map(\.value))),
                    Field(name: "Address", weight: 2, tokens: tokens(record.addresses.map(\.value))),
                    Field(name: "Web", weight: 2, tokens: tokens(record.urls.map(\.value) + record.social.map(\.value))),
                    Field(name: "Note", weight: 2, tokens: tokens([record.note ?? ""]))
                ].filter { !$0.tokens.isEmpty }
                return Entry(record: record, name: record.name, fields: fields, phoneDigits: record.phones.map { $0.value.filter(\.isNumber) })
            }
        }
    }

    /// As the user types in the launcher: only names, nicknames and
    /// companies, by a whole word or its start, through the sorted words
    /// (well under a millisecond for thousands).
    public static func quickSearch(_ query: String, in index: Index, limit: Int) -> [Match] {
        let asked = queryWords(query).map { Array($0.utf8) }.filter { $0.count >= 2 }
        guard !asked.isEmpty, limit > 0 else { return [] }
        // Per contact: the sum of each word's best, how many words fit, the
        // strongest one and its field. Only the contacts touched are read.
        var total = [Double](repeating: 0, count: index.entries.count)
        var matched = [Int](repeating: 0, count: index.entries.count)
        var strongest = [(value: Double, field: String)](repeating: (0, ""), count: index.entries.count)
        var touched: [Int] = []
        var wordBest = [Double](repeating: 0, count: index.entries.count)
        var wordField = [String](repeating: "", count: index.entries.count)
        for word in asked {
            // The first word not before `word`: every word it starts follows.
            var low = 0, high = index.quick.count
            while low < high {
                let middle = (low + high) / 2
                if index.quick[middle].token.lexicographicallyPrecedes(word) { low = middle + 1 } else { high = middle }
            }
            var hits: [Int] = []
            var position = low
            while position < index.quick.count, index.quick[position].token.starts(with: word) {
                let item = index.quick[position]
                let value = (item.token.count == word.count ? 1 : 0.75) * item.weight
                if wordBest[item.entry] == 0 { hits.append(item.entry) }
                if value > wordBest[item.entry] {
                    wordBest[item.entry] = value
                    wordField[item.entry] = item.field
                }
                position += 1
            }
            for entry in hits {
                if matched[entry] == 0 { touched.append(entry) }
                total[entry] += wordBest[entry]
                matched[entry] += 1
                if wordBest[entry] > strongest[entry].value { strongest[entry] = (wordBest[entry], wordField[entry]) }
                wordBest[entry] = 0
            }
        }
        // The best `limit`, kept in order as they come: no full sort.
        var best: [(score: Double, entry: Int)] = []
        func before(_ a: (score: Double, entry: Int), _ b: (score: Double, entry: Int)) -> Bool {
            a.score != b.score ? a.score > b.score : index.entries[a.entry].name < index.entries[b.entry].name
        }
        for entry in touched {
            let coverage = Double(matched[entry]) / Double(asked.count)
            let candidate = (score: total[entry] * (0.4 + 0.6 * coverage * coverage), entry: entry)
            if best.count == limit, let last = best.last, !before(candidate, last) { continue }
            let place = best.firstIndex { before(candidate, $0) } ?? best.endIndex
            best.insert(candidate, at: place)
            if best.count > limit { best.removeLast() }
        }
        return best.map { Match(record: index.entries[$0.entry].record, score: $0.score, field: strongest[$0.entry].field) }
    }

    public static func search(_ query: String, in index: Index, limit: Int = 20) -> [Match] {
        let asked = queryWords(query).map { Array($0.utf8) }
        guard !asked.isEmpty else { return [] }
        // A number typed: the phones' digits. "06 12…" is "+33 6 12…": the
        // leading 0 stands for the country code.
        let national = String(query.filter(\.isNumber).drop { $0 == "0" })
        var found: [(match: Match, name: String)] = []
        for entry in index.entries {
            var total = 0.0
            var matched = 0
            var bestField = ""
            var bestScore = 0.0
            for word in asked {
                var best = 0.0
                var place = ""
                for field in entry.fields where field.weight > best {
                    var strongest = 0.0
                    for token in field.tokens {
                        let value = strength(of: word, in: token)
                        if value > strongest {
                            strongest = value
                            if value == 1 { break }
                        }
                    }
                    if strongest * field.weight > best {
                        best = strongest * field.weight
                        place = field.name
                    }
                }
                if best > 0 {
                    total += best
                    matched += 1
                    if best > bestScore {
                        bestScore = best
                        bestField = place
                    }
                }
            }
            if national.count >= 4, entry.phoneDigits.contains(where: { $0.contains(national) }) {
                total += 20
                matched = asked.count
                bestField = "Phone"
            }
            guard total > 0 else { continue }
            let coverage = Double(matched) / Double(asked.count)
            found.append((Match(record: entry.record, score: total * (0.4 + 0.6 * coverage * coverage), field: bestField), entry.name))
        }
        found.sort { $0.match.score != $1.match.score ? $0.match.score > $1.match.score : $0.name < $1.name }
        return found.prefix(limit).map(\.match)
    }

    /// 1 for the same word, less for its start, one typo or a part of it.
    static func strength(of word: String, in token: String) -> Double {
        strength(of: Array(word.utf8), in: Array(token.utf8))
    }

    static func strength(of word: [UInt8], in token: [UInt8]) -> Double {
        if word == token { return 1 }
        let w = word.count, t = token.count
        if w >= 2, t > w, token.starts(with: word) { return 0.75 }
        if w >= 5, t >= 5, abs(w - t) <= 1, word[0] == token[0] || word[w - 1] == token[t - 1], oneEdit(word, token) { return 0.6 }
        if w >= 4, t > w, contains(token, word) { return 0.4 }
        return 0
    }

    /// One letter added, removed or changed.
    private static func oneEdit(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        var i = 0, j = 0, edits = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count { i += 1 } else if b.count > a.count { j += 1 } else {
                i += 1
                j += 1
            }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count, let first = needle.first else { return false }
        var start = 0
        while start + needle.count <= haystack.count {
            if haystack[start] == first {
                var k = 1
                while k < needle.count, haystack[start + k] == needle[k] { k += 1 }
                if k == needle.count { return true }
            }
            start += 1
        }
        return false
    }
}

extension ContactSearch {
    /// The clear match, when one contact stands out: every word that may
    /// name someone found in it, and well ahead of the next one. Nil when
    /// two are close (the user picks) or none fits well.
    public static func clearMatch(_ matches: [Match]) -> Match? {
        guard let first = matches.first, first.score >= 7.5 else { return nil }
        guard let second = matches.dropFirst().first else { return first }
        return first.score >= second.score * 1.3 ? first : nil
    }
}
