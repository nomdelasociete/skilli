import Foundation

/// Dictate (✦D): what the user says is typed where the caret is, from this
/// Mac's own speech model. The pure parts: the words the recognizer is told
/// to expect (the user's contacts' names and companies, never sent off the
/// Mac) and how the words heard join the text already there.
public struct DictationVocabulary: Equatable, Sendable {
    /// Apple's advice for `AnalysisContext.contextualStrings`: no more than
    /// 100 phrases across all tags, short ones (one or two words).
    public static let limit = 100

    /// For the recognizer, the likeliest first.
    public let phrases: [String]
    /// Every word of every contact's name and company, folded: such a word
    /// keeps its capital mid-sentence ("Bonjour, Margot").
    public let names: Set<String>

    public static let empty = DictationVocabulary(phrases: [], names: [])

    public init(phrases: [String], names: Set<String>) {
        self.phrases = phrases
        self.names = names
    }

    /// `me`: the user's own card; `picks`: how often each contact (by id)
    /// was picked in the launcher. First the user's company and name, then
    /// the contacts picked (most first), then the companies several
    /// contacts share (most shared first), then everyone else, those with
    /// a phone or an email first, in the address book's order: each name,
    /// then its company. Each phrase once, case and accents aside.
    public init(contacts: [ContactRecord], me: ContactRecord? = nil, picks: [String: Double] = [:], limit: Int = Self.limit) {
        var phrases: [String] = []
        var seen: Set<String> = []
        func add(_ phrase: String?) {
            guard let phrase, phrases.count < limit else { return }
            let key = Self.fold(phrase)
            guard seen.insert(key).inserted else { return }
            phrases.append(phrase)
        }
        func addPerson(_ contact: ContactRecord) {
            add(Self.name(of: contact))
            add(Self.company(contact.organization))
        }

        if let me {
            add(Self.company(me.organization))
            add(Self.name(of: me))
        }
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, _) in picks.filter({ $0.value > 0 }).sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
            if let contact = byID[id] { addPerson(contact) }
        }
        var companies: [String: (name: String, count: Int, first: Int)] = [:]
        for (index, contact) in contacts.enumerated() {
            guard let company = Self.company(contact.organization) else { continue }
            let key = Self.fold(company)
            let current = companies[key]
            companies[key] = (current?.name ?? company, (current?.count ?? 0) + 1, current?.first ?? index)
        }
        for company in companies.values.filter({ $0.count > 1 }).sorted(by: { $0.count != $1.count ? $0.count > $1.count : $0.first < $1.first }) {
            add(company.name)
        }
        let reachable = contacts.filter { !$0.phones.isEmpty || !$0.emails.isEmpty }
        let others = contacts.filter { $0.phones.isEmpty && $0.emails.isEmpty }
        for contact in reachable + others where phrases.count < limit {
            addPerson(contact)
        }

        var names: Set<String> = []
        for contact in contacts + [me].compactMap({ $0 }) {
            for part in [contact.givenName, contact.middleName, contact.familyName, contact.nickname, contact.organization] {
                for word in part.split(whereSeparator: { $0.isWhitespace }) {
                    let folded = Self.fold(String(word).trimmingCharacters(in: .punctuationCharacters))
                    guard folded.count > 1 else { continue }
                    names.insert(folded)
                    // "Jean-François": "jean" and "françois" too.
                    for piece in folded.split(separator: "-") where piece.count > 1 { names.insert(String(piece)) }
                }
            }
        }
        self.init(phrases: phrases, names: names)
    }

    /// Whether `word` is one of the contacts' names or companies.
    public func isName(_ word: String) -> Bool {
        names.contains(Self.fold(word))
    }

    /// "Margot Martin": first and last names, as people say them (the
    /// middle name and the nickname left out). Nil when nothing fits.
    static func name(of contact: ContactRecord) -> String? {
        phrase([contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// The company as people say it: "Nimbus SAS" → "Nimbus", "Apple, Inc." →
    /// "Apple".
    static func company(_ organization: String) -> String? {
        var words = organization.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while words.count > 1, let last = words.last,
              legalForms.contains(last.lowercased().replacingOccurrences(of: ".", with: "")) {
            words.removeLast()
        }
        if let last = words.last, last.hasSuffix(",") { words[words.count - 1] = String(last.dropLast()) }
        return phrase(words.joined(separator: " "))
    }

    /// The legal forms a company's name ends with, dots left out.
    static let legalForms: Set<String> = [
        "inc", "llc", "ltd", "limited", "corp", "corporation", "co", "plc", "gmbh", "ag", "kg", "sa", "sas", "sasu", "sarl", "eurl",
        "bv", "nv", "spa", "srl", "sl", "oy", "ab", "pty"
    ]

    /// A phrase the recognizer can use: spaces collapsed, at least two
    /// characters and a letter, four words and 40 characters at most.
    static func phrase(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        let phrase = words.joined(separator: " ")
        guard phrase.count >= 2, phrase.count <= 40, words.count <= 4, phrase.contains(where: \.isLetter) else { return nil }
        return phrase
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// How dictated words join the text: the transcriber's pieces with each
/// other, then the whole with what is before the caret.
public enum DictationText {
    /// A settled piece after the ones before it, a space between them
    /// unless one is there already or the piece starts with punctuation.
    public static func joined(_ settled: String, _ next: String) -> String {
        guard let last = settled.last, let first = next.first else { return settled + next }
        if last.isWhitespace || first.isWhitespace || closing.contains(first) { return settled + next }
        return settled + " " + next
    }

    /// What is typed for `heard` at a caret with `before` behind it (the
    /// field's text up to the caret; nil when the app does not say):
    /// - spaces trimmed and collapsed (line breaks kept);
    /// - a space first when the caret is right after a word or punctuation,
    ///   not after an opening bracket or quote;
    /// - a capital at the start of a sentence (empty field, after . ! ? or
    ///   a line break);
    /// - mid-sentence (after a letter, a digit, a comma, ; or :), the first
    ///   word in lowercase unless it is a name (`isName`), "I" or has other
    ///   capitals ("NASA", "iPhone").
    /// Unknown `before`: the words as heard.
    public static func insertion(_ heard: String, after before: String?, isName: (String) -> Bool = { _ in false }) -> String {
        var text = collapsed(heard)
        guard !text.isEmpty, let before else { return text }
        let tail = before.reversed().prefix { $0.isWhitespace }
        let lastWritten = before.dropLast(tail.count).last
        let startsSentence = lastWritten.map { sentenceEnds.contains($0) } ?? true || tail.contains(where: \.isNewline)
        if startsSentence {
            text = capitalizingFirstLetter(text)
        } else if let lastWritten, lastWritten.isLetter || lastWritten.isNumber || midSentence.contains(lastWritten) {
            text = lowercasingFirstWord(text, isName: isName)
        }
        if let last = before.last, !last.isWhitespace, !opening.contains(last), let first = text.first, !closing.contains(first) {
            text = " " + text
        }
        return text
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]
    private static let midSentence: Set<Character> = [",", ";", ":", "-", "–", "—"]
    private static let opening: Set<Character> = ["(", "[", "{", "«", "“", "‘", "\"", "'", "/", "@", "#", "-"]
    private static let closing: Set<Character> = [",", ".", ";", ":", "!", "?", "…", ")", "]", "}", "»", "”", "’", "%"]
    /// The English "I", alone or with its contractions.
    private static let pronounI: Set<String> = ["I", "I'm", "I’m", "I'll", "I’ll", "I've", "I’ve", "I'd", "I’d"]

    /// Spaces and tabs collapsed to one, line breaks kept, the ends trimmed.
    static func collapsed(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isWhitespace, !character.isNewline {
                pendingSpace = true
                continue
            }
            if character.isNewline {
                pendingSpace = false
                while result.last == " " { result.removeLast() }
            } else if pendingSpace, result.last?.isNewline == false {
                result.append(" ")
            }
            pendingSpace = false
            result.append(character)
        }
        return result
    }

    private static func capitalizingFirstLetter(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter), text[index].isLowercase else { return text }
        return text.replacingCharacters(in: index...index, with: text[index].uppercased())
    }

    private static func lowercasingFirstWord(_ text: String, isName: (String) -> Bool) -> String {
        let word = text.prefix { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }
        // "Margot's": the name before the apostrophe.
        let stem = word.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? String(word)
        guard let first = word.first, first.isUppercase, word.dropFirst().allSatisfy({ !$0.isUppercase }),
              !pronounI.contains(String(word)), !isName(String(word)), !isName(stem) else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
