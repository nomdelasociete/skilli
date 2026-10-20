import CoreText
import Foundation
import Synchronization

/// One emoji or symbol with its name in the user's language and in
/// English, and other words it is found by (a symbol's: "cmd" for ⌘).
public struct Emoji: Equatable, Hashable, Sendable {
    public let character: String
    public let name: String
    public let english: String
    public let words: [String]
    public let kind: Kind

    /// macOS's emoji, `SymbolTable`'s symbols, the other characters
    /// Unicode names: equally found, shown in this order.
    public enum Kind: Int, Sendable {
        case emoji
        case symbol
        case character
    }

    public init(character: String, name: String, english: String, words: [String] = [], kind: Kind = .emoji) {
        self.character = character
        self.name = name
        self.english = english
        self.words = words
        self.kind = kind
    }

    /// As it is typed in `tone` when it comes in tones (👍 → 👍🏽); as it
    /// is otherwise.
    public func character(in tone: EmojiSkinTone) -> String {
        tone.apply(to: character)
    }
}

/// The skin tone emoji that come in tones are typed in (Settings →
/// Launcher → Emoji), as Raycast and the Character Viewer offer it.
public enum EmojiSkinTone: String, CaseIterable, Codable, Sendable {
    /// The yellow one, no tone ("none" never: `Optional.none` reads the same).
    case standard = "default"
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    /// Apple's names for them.
    public var title: String {
        switch self {
        case .standard: "Default"
        case .light: "Light Skin Tone"
        case .mediumLight: "Medium-Light Skin Tone"
        case .medium: "Medium Skin Tone"
        case .mediumDark: "Medium-Dark Skin Tone"
        case .dark: "Dark Skin Tone"
        }
    }

    /// Its Fitzpatrick modifier, U+1F3FB…U+1F3FF.
    var modifier: Unicode.Scalar? {
        switch self {
        case .standard: nil
        case .light: "\u{1F3FB}"
        case .mediumLight: "\u{1F3FC}"
        case .medium: "\u{1F3FD}"
        case .mediumDark: "\u{1F3FE}"
        case .dark: "\u{1F3FF}"
        }
    }

    private static let toned = Mutex<[String: String]>([:])

    /// `character` in this tone: the modifier after each person or hand
    /// in it (👍 → 👍🏽, 🧑‍💻 → 🧑🏽‍💻, ✌️ → ✌🏽), kept only when macOS
    /// draws the result as one emoji. A family or people holding hands
    /// (no single tone for each of them) stay as they are.
    public func apply(to character: String) -> String {
        guard let modifier else { return character }
        let key = character + String(modifier)
        if let known = Self.toned.withLock({ $0[key] }) { return known }
        var scalars = String.UnicodeScalarView()
        var toned = false
        var afterBase = false
        for scalar in character.unicodeScalars {
            // The presentation selector goes: ✌️ is ✌ + U+FE0F, ✌🏽 has none.
            if afterBase, scalar.value == 0xFE0F {
                afterBase = false
                continue
            }
            afterBase = false
            scalars.append(scalar)
            if scalar.properties.isEmojiModifierBase {
                scalars.append(modifier)
                toned = true
                afterBase = true
            }
        }
        let result = toned && Self.drawnWhole(String(scalars)) ? String(scalars) : character
        Self.toned.withLock { $0[key] = result }
        return result
    }

    /// Whether macOS's emoji font draws `text` as one emoji, not as the
    /// pieces it is made of.
    static func drawnWhole(_ text: String) -> Bool {
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 24, nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CTLineGetGlyphCount(CTLineCreateWithAttributedString(attributed)) == 1
    }
}

/// Emoji found by name ("cœur", "heart", "fire"), and the ones a feeling
/// can be said with, for the decision model ("trop content mais crevé").
public enum EmojiSearch {
    /// The picker's emoji and symbols with their names folded once into
    /// one buffer: a key then only compares bytes, nothing copied or
    /// retained. Folding ~4 500 names on every key took longer than the
    /// 2 ms a key may.
    public struct Index: Sendable {
        public let emoji: [Emoji]
        /// Every name folded, end to end; each name's bytes in it, and each
        /// entry's names.
        fileprivate let bytes: [UInt8]
        fileprivate let names: [Range<Int>]
        fileprivate let entries: [Range<Int>]
        /// What ranks equal scores: the kind, then the name's length.
        fileprivate let kinds: [Int]
        fileprivate let lengths: [Int]
        /// Where each character is, without its presentation selectors.
        fileprivate let byKey: [String: [Int]]

        public init(_ emoji: [Emoji]) {
            self.emoji = emoji
            var bytes: [UInt8] = []
            var names: [Range<Int>] = []
            var entries: [Range<Int>] = []
            var byKey: [String: [Int]] = [:]
            for (at, candidate) in emoji.enumerated() {
                let first = names.count
                for name in [candidate.name, candidate.english] + candidate.words where !name.isEmpty {
                    let start = bytes.count
                    bytes += EmojiSearch.fold(name).utf8
                    names.append(start..<bytes.count)
                }
                entries.append(first..<names.count)
                byKey[SymbolTable.key(candidate.character), default: []].append(at)
            }
            self.bytes = bytes
            self.names = names
            self.entries = entries
            kinds = emoji.map(\.kind.rawValue)
            lengths = emoji.map(\.name.count)
            self.byKey = byKey
        }
    }

    /// Best first: a name that starts with the text, then a word that
    /// does, then one that contains it; every word typed must match.
    /// `said`: what the user typed to find an emoji by meaning, by emoji,
    /// read as more names; the very same words put it first. The symbol
    /// itself typed ("→") finds it first. Equal, emoji before symbols.
    public static func search(_ text: String, in emoji: [Emoji], said: [String: [String]] = [:], limit: Int = 50) -> [Emoji] {
        search(text, in: Index(emoji), said: said, limit: limit)
    }

    /// `keep`: those it says no to are left out before the limit counts.
    public static func search(_ text: String, in index: Index, said: [String: [String]] = [:], limit: Int = 50,
                              keep: (Emoji) -> Bool = { _ in true }) -> [Emoji] {
        let folded = fold(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !folded.isEmpty else { return Array(index.emoji.prefix(limit)) }
        // The words typed end to end, as the names are.
        var wordBytes: [UInt8] = []
        var words: [Range<Int>] = []
        for word in folded.split(separator: " ") {
            let start = wordBytes.count
            wordBytes += word.utf8
            words.append(start..<wordBytes.count)
        }
        let phrase = Array(folded.utf8)
        let typed = Set(index.byKey[SymbolTable.key(text.trimmingCharacters(in: .whitespaces))] ?? [])
        // The words learned, by where their emoji is: a few, folded per search.
        var learned: [Int: [[UInt8]]] = [:]
        for (character, phrases) in said {
            for at in index.byKey[SymbolTable.key(character)] ?? [] where index.emoji[at].character == character {
                learned[at] = phrases.map { Array(fold($0).utf8) }
            }
        }
        var scored: [(at: Int, score: Int)] = []
        index.bytes.withUnsafeBufferPointer { bytes in
            wordBytes.withUnsafeBufferPointer { typedBytes in
                for at in index.entries.indices {
                    if typed.contains(at) {
                        scored.append((at, 1_000))
                        continue
                    }
                    let own = learned[at]
                    var total = 0
                    var matchedAll = true
                    for word in words {
                        let typedWord = UnsafeBufferPointer(rebasing: typedBytes[word])
                        var best = 0
                        for name in index.entries[at] where best < 4 {
                            best = max(best, score(typedWord, in: UnsafeBufferPointer(rebasing: bytes[index.names[name]])))
                        }
                        for name in own ?? [] where best < 4 {
                            best = max(best, name.withUnsafeBufferPointer { score(typedWord, in: $0) })
                        }
                        if best == 0 {
                            matchedAll = false
                            break
                        }
                        total += best
                    }
                    if own?.contains(phrase) == true { total += 100 }
                    // A name written for people (macOS's, the table's) outranks
                    // Unicode's by a step: "arrow" is → before "arrowhead…".
                    if index.kinds[at] != Emoji.Kind.character.rawValue { total += 1 }
                    if matchedAll { scored.append((at, total)) }
                }
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if index.kinds[lhs.at] != index.kinds[rhs.at] { return index.kinds[lhs.at] < index.kinds[rhs.at] }
            return index.lengths[lhs.at] < index.lengths[rhs.at]
        }
        var found: [Emoji] = []
        for entry in scored where found.count < limit {
            let candidate = index.emoji[entry.at]
            if keep(candidate) { found.append(candidate) }
        }
        return found
    }

    /// 4 the name is the word, 3 it starts with it, 2 one of its words
    /// does, 1 it holds it, 0 not at all. Bytes of folded text: a byte
    /// below 0x80 that is not a letter or digit separates words.
    private static func score(_ word: UnsafeBufferPointer<UInt8>, in name: UnsafeBufferPointer<UInt8>) -> Int {
        let length = word.count
        guard length > 0, length <= name.count else { return 0 }
        if length == name.count { return name.elementsEqual(word) ? 4 : 0 }
        let first = word[0]
        var best = 0
        var start = 0
        while start <= name.count - length {
            if name[start] == first, matches(word, in: name, at: start) {
                if start == 0 { return 3 }
                if isSeparator(name[start - 1]) { return 2 }
                best = 1
            }
            start += 1
        }
        return best
    }

    private static func matches(_ word: UnsafeBufferPointer<UInt8>, in name: UnsafeBufferPointer<UInt8>, at start: Int) -> Bool {
        var offset = 1
        while offset < word.count {
            if name[start + offset] != word[offset] { return false }
            offset += 1
        }
        return true
    }

    private static func isSeparator(_ byte: UInt8) -> Bool {
        guard byte < 0x80 else { return false }
        let isLetter = (0x61...0x7A).contains(byte) || (0x41...0x5A).contains(byte)
        return !isLetter && !(0x30...0x39).contains(byte)
    }

    static func fold(_ text: String) -> String {
        // Unicode's names are plain ASCII: lowercased is all they need.
        if text.utf8.allSatisfy({ $0 < 0x80 }) { return text.lowercased() }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "’", with: "'")
    }

    /// Emoji people use to say how they feel or react: faces, hearts,
    /// hands, celebrations, a few signs. What the decision model chooses
    /// among (one question, under its 255 options).
    public static func expressive(_ emoji: [Emoji]) -> [Emoji] {
        let words = ["face", "heart", "hand", "thumbs", "clap", "fist", "muscle", "folded", "party", "confetti", "fire",
                     "sparkles", "hundred", "skull", "ghost", "poo", "clown", "eyes", "zzz", "sleeping sign", "collision",
                     "dizzy", "rocket", "trophy", "champagne", "clinking", "balloon", "gift", "birthday", "star-struck",
                     "partying", "shrug", "facepalm", "bowing", "check mark", "cross mark", "warning", "red question",
                     "red exclamation", "victory", "crossed fingers", "call me", "waving", "kiss mark", "see-no-evil",
                     "hear-no-evil", "speak-no-evil", "sweat droplets", "anger symbol", "brain", "lightning", "rainbow", "sun with face"]
        let excluded = ["clock", "cat face", "dog face", "horse face", "cow face", "pig face", "monkey face", "tiger face",
                        "rabbit face", "dragon face", "moon face", "face with medical", "facing", "handbag", "handball",
                        "hand with index finger and thumb crossed", "heart suit", "anatomical", "mechanical", "mans shoe"]
        var seen = Set<String>()
        return emoji.filter { candidate in
            let name = candidate.english.lowercased()
            // A symbol's heart (♡) or star says no feeling.
            guard candidate.kind == .emoji,
                  !candidate.character.unicodeScalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
                  words.contains(where: name.contains), !excluded.contains(where: name.contains),
                  seen.insert(candidate.english).inserted
            else { return false }
            return true
        }
    }

    /// The question and what the model reads of each candidate.
    public static let instructions = "Which emoji best says what the user describes: a feeling, a reaction or a thing? Read it as a native speaker of its language would (in French, “trop content” means very happy). Pick the emoji a person would type to say it."

    public static func input(_ request: String) -> String {
        "What the user wants to say with an emoji: \(request)"
    }
}

/// What the picker shows: the emoji, and its headers while browsing
/// (Recently Used, then Unicode's groups, as runs of `count`); none for a
/// search, ranked instead.
public struct EmojiList: Sendable {
    public var emoji: [Emoji]
    public var sections: [Section]

    public struct Section: Equatable, Sendable {
        public let name: String
        public let count: Int

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    public init(emoji: [Emoji], sections: [Section] = []) {
        self.emoji = emoji
        self.sections = sections
    }

    /// Browsing: the recent ones first, then every emoji Unicode orders,
    /// group by group, then `SymbolTable`'s symbols in their groups. Those
    /// neither orders are left to the search.
    public static func browsing(recent: [Emoji], all: [Emoji]) -> EmojiList {
        let recentKeys = Set(recent.map { EmojiOrder.key($0.character) })
        let ordered = all.compactMap { emoji in place(of: emoji.character).map { (emoji: emoji, place: $0) } }
            .filter { !recentKeys.contains(EmojiOrder.key($0.emoji.character)) }
            .sorted { $0.place < $1.place }
        var sections = recent.isEmpty ? [] : [Section(name: "Recently Used", count: recent.count)]
        var group: Int?
        for entry in ordered {
            if entry.place.group == group, let last = sections.popLast() {
                sections.append(Section(name: last.name, count: last.count + 1))
            } else {
                sections.append(Section(name: groupNames[entry.place.group], count: 1))
                group = entry.place.group
            }
        }
        return EmojiList(emoji: recent + ordered.map(\.emoji), sections: sections)
    }

    /// Unicode's emoji groups, then the symbols'.
    public static let groupNames = EmojiOrder.groupNames + SymbolTable.groupNames

    /// Unicode's place for an emoji; past its groups, the table's for a
    /// symbol (↩︎ drawn as text is the Return key, not ↩️).
    static func place(of character: String) -> EmojiOrder.Place? {
        if let place = EmojiOrder.place(of: character) { return place }
        return SymbolTable.place(of: character).map { EmojiOrder.Place(group: EmojiOrder.groupNames.count + $0.group, index: $0.index) }
    }
}

extension EmojiOrder {
    /// An emoji's place in Unicode's order: its group, then its rank.
    public struct Place: Comparable, Sendable {
        public let group: Int
        public let index: Int

        public static func < (lhs: Place, rhs: Place) -> Bool {
            (lhs.group, lhs.index) < (rhs.group, rhs.index)
        }
    }

    /// The groups' names, in order: "Smileys & Emotion", "People & Body"…
    public static let groupNames: [String] = groups.map(\.name)

    private static let places: [String: Place] = {
        var places: [String: Place] = [:]
        var index = 0
        for (group, entry) in groups.enumerated() {
            for emoji in entry.emoji.split(separator: " ") {
                places[key(String(emoji))] = Place(group: group, index: index)
                index += 1
            }
        }
        return places
    }()

    /// Compared without U+FE0F: macOS's names write some emoji without it.
    static func key(_ character: String) -> String {
        character.replacingOccurrences(of: "\u{FE0F}", with: "")
    }

    /// Where Unicode puts it; nil for one it does not order.
    public static func place(of character: String) -> Place? {
        places[key(character)]
    }
}
