import Foundation

/// A piece of text typed often (an address, a signature, a reply), found in
/// the launcher or expanded where its keyword is typed: ";addr" becomes the
/// address. One Markdown file each, hand-editable:
///
///     ---
///     name: Address
///     keyword: ;addr
///     ---
///     12 rue des Lilas, 75011 Paris
public struct Snippet: Equatable, Sendable, Identifiable {
    /// The file's name without `.md`.
    public var id: String
    public var name: String
    /// Typed anywhere, replaced by the text. Empty: launcher only.
    public var keyword: String
    /// With `{date}`, `{clipboard}`… and one `{cursor}` where the caret ends.
    public var text: String

    public init(id: String, name: String, keyword: String = "", text: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.text = text
    }

    public static let cursorToken = "{cursor}"

    public init(id: String, parsing file: String) {
        self.id = id
        var name = ""
        var keyword = ""
        var body = file
        let lines = file.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "name", "title": name = Self.unquoted(value)
                case "keyword": keyword = Self.unquoted(value)
                default: break
                }
            }
            body = lines[(end + 1)...].joined(separator: "\n")
        }
        // The file ends with a newline the text does not have.
        if body.hasSuffix("\n") { body.removeLast() }
        self.name = name.isEmpty ? id : name
        self.keyword = keyword
        self.text = body
    }

    /// The file: front matter, then the text as is.
    public var file: String {
        var front = "---\nname: \(Self.quotedIfNeeded(name))\n"
        if !keyword.isEmpty { front += "keyword: \(Self.quotedIfNeeded(keyword))\n" }
        return front + "---\n" + text + "\n"
    }

    /// The text as it goes in: variables filled, `{cursor}` gone, and how
    /// many characters the caret then moves back from the end.
    public func expanded(_ values: [PromptTemplate.Variable: String]) -> (text: String, cursorFromEnd: Int) {
        let parts = text.components(separatedBy: Self.cursorToken)
        let before = PromptTemplate(parts[0]).render(values)
        let after = parts.count > 1 ? PromptTemplate(parts.dropFirst().joined()).render(values) : ""
        return (before + after, after.count)
    }

    /// A file name from a name: "Mon adresse" → "mon-adresse".
    public static func fileID(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let id = folded.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return id.isEmpty ? "snippet" : String(id.prefix(48))
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func quotedIfNeeded(_ value: String) -> String {
        value.contains(":") || value.contains("#") || value.hasPrefix(" ") || value.hasSuffix(" ") || value.hasPrefix("\"")
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
            : value
    }
}

/// When a keyword typed becomes its snippet (Settings → Snippets → Expand).
public enum SnippetExpansionMode: String, CaseIterable, Sendable {
    /// A keyword with a symbol (";addr") at once; one made of letters
    /// ("addr") once its word ends, the space or mark that ended it kept.
    case immediately
    /// Only after a space or ↩, which stays after the snippet.
    case afterDelimiterKept
    /// Only after a space or ↩, which goes with the keyword.
    case afterDelimiterRemoved

    /// As the pane's picker says it.
    public var title: String {
        switch self {
        case .immediately: "As soon as it is typed"
        case .afterDelimiterKept: "After a space or ↩"
        case .afterDelimiterRemoved: "After a space or ↩, left out"
        }
    }

    /// What waits for a space or ↩.
    public var waitsForDelimiter: Bool { self != .immediately }
}

/// A keyword just completed, and what becomes of what ended it.
public struct SnippetExpansion: Equatable, Sendable {
    public let snippet: Snippet
    /// What ended the keyword: nothing (a symbol keyword typed at once), a
    /// space or a mark, or "\n" for ↩.
    public let delimiter: String
    /// The delimiter comes back after the snippet.
    public let keepsDelimiter: Bool

    /// ↩ ended it: the key is held back from the app (a chat would send
    /// the keyword), then pressed again after the snippet when it stays.
    public var holdsKey: Bool { delimiter == "\n" }

    /// What the app has to lose before the snippet goes in: the keyword,
    /// and the delimiter it already took.
    public var erase: Int { snippet.keyword.count + (holdsKey ? 0 : delimiter.count) }

    /// Typed after the snippet ("" when nothing is); ↩ is pressed instead.
    public var typedAfter: String { keepsDelimiter && !holdsKey ? delimiter : "" }

    /// ↩ pressed again after the snippet.
    public var pressesReturnAfter: Bool { keepsDelimiter && holdsKey }
}

/// The last characters typed, to see a keyword end. In memory only, a few
/// characters, cleared by anything that moves the caret elsewhere.
public struct SnippetMatcher: Sendable {
    public private(set) var buffer = ""
    private static let capacity = 48
    /// What ends a keyword when expansion waits for one.
    public static let delimiters: Set<Character> = [" ", "\n"]

    public init() {}

    public mutating func type(_ text: String) {
        buffer += text
        if buffer.count > Self.capacity { buffer = String(buffer.suffix(Self.capacity)) }
    }

    public mutating func deleteBackward() {
        if !buffer.isEmpty { buffer.removeLast() }
    }

    public mutating func reset() {
        buffer = ""
    }

    /// The snippet whose keyword was just completed, and what ended it.
    /// As soon as it is typed: a keyword made of letters ("addr") waits
    /// for its word to end (a space, a punctuation mark), one with a symbol
    /// (";addr", "!sig") expands at once, anywhere. After a space or ↩:
    /// every keyword waits for one of them. Either way a keyword starting
    /// with a letter needs a word start before it, so "address" never
    /// expands "addr"; the longest keyword wins.
    public func match(_ snippets: [Snippet], mode: SnippetExpansionMode = .immediately) -> SnippetExpansion? {
        var best: SnippetExpansion?
        for snippet in snippets where !snippet.keyword.isEmpty {
            let keyword = snippet.keyword
            var typed = Substring(buffer)
            var delimiter = ""
            if mode.waitsForDelimiter {
                guard let last = typed.last, Self.delimiters.contains(last) else { continue }
                delimiter = String(last)
                typed = typed.dropLast()
            } else if keyword.first.map(Self.isWordCharacter) == true && keyword.last.map(Self.isWordCharacter) == true {
                guard let last = typed.last, !Self.isWordCharacter(last), !last.isNewline else { continue }
                delimiter = String(last)
                typed = typed.dropLast()
            }
            guard typed.hasSuffix(keyword) else { continue }
            if keyword.first.map(Self.isWordCharacter) == true,
               let before = typed.dropLast(keyword.count).last, Self.isWordCharacter(before) { continue }
            if best.map({ keyword.count > $0.snippet.keyword.count }) ?? true {
                best = SnippetExpansion(snippet: snippet, delimiter: delimiter, keepsDelimiter: mode != .afterDelimiterRemoved)
            }
        }
        return best
    }

    /// What `typed` becomes, key by key, with `snippets` expanding as the
    /// app shows it (their text as written, placeholders left in): the
    /// Settings preview, by the same matcher as typing does.
    public static func result(of typed: String, snippets: [Snippet], mode: SnippetExpansionMode) -> String {
        var matcher = SnippetMatcher()
        var text = ""
        for character in typed {
            matcher.type(String(character))
            // ↩ without a keyword before it: the matcher starts again,
            // as typing does.
            guard let expansion = matcher.match(snippets, mode: mode) else {
                if character.isNewline { matcher.reset() }
                text.append(character)
                continue
            }
            matcher.reset()
            if !expansion.holdsKey { text.append(character) }
            text.removeLast(min(expansion.erase, text.count))
            text += expansion.snippet.text.replacingOccurrences(of: Snippet.cursorToken, with: "") + expansion.typedAfter
            if expansion.pressesReturnAfter { text += "\n" }
        }
        return text
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

/// Snippets found by what the user needs ("my iban", "adresse bureau"):
/// the decision model picks among them, each told by its name, its keyword
/// and its first words. Only on ⇥, and never a whole snippet: placeholders
/// stay as written, nothing filled (no clipboard, no date).
public enum SnippetMeaning {
    /// What the model reads of each snippet's text.
    public static let previewLength = 80
    /// One Choice question holds this many.
    public static let candidateLimit = 240

    /// "“Home address” (keyword ;addr): 12 rue des Lilas, 75011 Paris…"
    public static func describe(_ snippet: Snippet) -> String {
        let keyword = snippet.keyword.isEmpty ? "" : " (keyword \(snippet.keyword))"
        let words = ClipboardMeaning.excerpt(snippet.text, limit: previewLength)
        return "“\(snippet.name)”\(keyword)" + (words.isEmpty ? "" : ": \(words)")
    }

    /// The option's value for the snippet at `index`.
    public static func value(_ index: Int) -> String { "s\(index)" }

    /// The request as the model reads it.
    public static func input(_ request: String) -> String {
        "The user wants to type one of their saved snippets: \(request)"
    }

    public static let instructions = "Which of the user's snippets do they want to type? They say what they need in their own words, possibly in another language than the snippet's name (“my iban”, “adresse du bureau”, “polite no”): judge from each snippet's name, keyword and first words. Answer none when no snippet fits."

    /// The snippets the answer points to, best first: those at 4 % and
    /// more, eight at most; none when the model is fairly sure none fits.
    public static func picked(_ probabilities: [String: Double], choice: String, count: Int) -> [Int] {
        if choice == "none", (probabilities["none"] ?? 0) > 0.6 { return [] }
        return probabilities
            .filter { $0.key != "none" && $0.value >= 0.04 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(8)
            .compactMap { entry in entry.key.first == "s" ? Int(entry.key.dropFirst()) : nil }
            .filter { (0..<count).contains($0) }
    }

    /// "snip iban", "snippet iban" → "iban".
    public static func modeFilter(_ text: String) -> String? {
        LauncherPrefix.rest(of: text, after: LauncherPrefix.prefixes(for: .searchSnippets))
    }
}
