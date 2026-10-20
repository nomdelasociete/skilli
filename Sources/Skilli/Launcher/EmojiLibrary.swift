import Foundation
import SkilliCore

/// Every emoji with its name in the user's language and in English, from
/// macOS's own emoji data (the names the Character Viewer shows), the
/// symbols skil.li names (`SymbolTable`: ⌘, →, the Apple logo…) and the
/// others Unicode names, and the ones used lately first.
final class EmojiLibrary: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded: [Emoji]?
    private var index: EmojiSearch.Index?
    /// Browsing as last built, with the recent ones it was built for.
    private var browsed: (recents: [String], list: EmojiList)?
    /// How many a search shows: twelve rows of the picker's grid.
    static let searchLimit = 96
    private let defaults: UserDefaults
    private static let recentsKey = "EmojiLibrary.recents"
    private static let saidKey = "EmojiLibrary.said"
    private static let folder = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Read once, by code point: ~1 900 emoji, ~190 symbols written for
    /// skil.li, ~2 500 others Unicode names (~14 ms the first time).
    var all: [Emoji] {
        lock.lock()
        defer { lock.unlock() }
        return loadedLocked()
    }

    private func loadedLocked() -> [Emoji] {
        if let loaded { return loaded }
        let english = Self.names(language: "en")
        let language = Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? "en" } ?? "en"
        let local = language == "en" ? english : Self.names(language: language)
        // "🇭🇰@CH-SKU": a variant for China's Macs, never typed as is.
        var emoji = english.keys.filter { !$0.contains("@") }.map { character in
            Emoji(character: character, name: local[character] ?? english[character] ?? character, english: english[character] ?? "")
        }
        // An emoji macOS names keeps its name; the table names it only
        // drawn as text (↩︎), or while macOS leaves it unnamed (♀️).
        var keys = Set(emoji.map { SymbolTable.key($0.character) })
        for symbol in SymbolTable.written(language: language) {
            let asText = symbol.character.unicodeScalars.last?.value == 0xFE0E
            guard asText || !keys.contains(SymbolTable.key(symbol.character)) else { continue }
            emoji.append(symbol)
            keys.insert(SymbolTable.key(symbol.character))
        }
        emoji += SymbolTable.unicode(excluding: keys)
        emoji.sort { ($0.character.unicodeScalars.first?.value ?? 0, $0.character) < ($1.character.unicodeScalars.first?.value ?? 0, $1.character) }
        loaded = emoji
        return emoji
    }

    /// The names folded once, made with `all`.
    private var searchIndex: EmojiSearch.Index {
        lock.lock()
        defer { lock.unlock() }
        if let index { return index }
        let made = EmojiSearch.Index(loadedLocked())
        index = made
        return made
    }

    private static func names(language: String) -> [String: String] {
        let url = folder.appendingPathComponent("\(language).lproj/AppleName.strings")
        return (NSDictionary(contentsOf: url) as? [String: String]) ?? [:]
    }

    /// The text typed, ranked by name; nothing typed, every emoji to
    /// browse: the recent ones, then Unicode's groups in its order, then
    /// the symbols' groups. A character no font of this Mac draws is left
    /// out (Unicode names some).
    func search(_ text: String) -> EmojiList {
        guard text.trimmingCharacters(in: .whitespaces).isEmpty else {
            let found = EmojiSearch.search(text, in: searchIndex, said: said, limit: Self.searchLimit) { candidate in
                candidate.kind != .character || SymbolTable.isDrawn(candidate.character)
            }
            return EmojiList(emoji: found)
        }
        let everything = all
        let recentCharacters = recentCharacters
        lock.lock()
        defer { lock.unlock() }
        if let browsed, browsed.recents == recentCharacters { return browsed.list }
        let recents = recentCharacters.compactMap { character in everything.first { $0.character == character } }
        let list = EmojiList.browsing(recent: recents, all: everything)
        browsed = (recentCharacters, list)
        return list
    }

    /// What the user typed to find an emoji by meaning and then picked it,
    /// by emoji (its plain character): found by name next time, without
    /// SI, as Raycast keeps its custom keywords. Kept on this Mac only.
    var said: [String: [String]] {
        (defaults.dictionary(forKey: Self.saidKey) as? [String: [String]]) ?? [:]
    }

    /// How many words are kept, all emoji together (Settings → Emoji).
    var saidCount: Int {
        said.values.reduce(0) { $0 + $1.count }
    }

    /// Settings → Emoji → Forget: none kept any more. Returns them, for
    /// ⌘Z (`restoreSaid`).
    @discardableResult
    func forgetSaid() -> [String: [String]] {
        let forgotten = said
        defaults.removeObject(forKey: Self.saidKey)
        return forgotten
    }

    /// ⌘Z: the words back, after any learned since (eight each at most).
    func restoreSaid(_ forgotten: [String: [String]]) {
        var all = said
        for (emoji, phrases) in forgotten {
            let now = all[emoji] ?? []
            all[emoji] = Array((now + phrases.filter { phrase in !now.contains { $0.caseInsensitiveCompare(phrase) == .orderedSame } }).prefix(8))
        }
        defaults.set(all, forKey: Self.saidKey)
    }

    /// `words` found `emoji` by meaning and it was picked: the newest
    /// first, eight at most for each emoji.
    func learn(_ words: String, for emoji: Emoji) {
        let phrase = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !phrase.isEmpty else { return }
        var all = said
        let kept = (all[emoji.character] ?? []).filter { $0.caseInsensitiveCompare(phrase) != .orderedSame }
        all[emoji.character] = Array(([phrase] + kept).prefix(8))
        defaults.set(all, forKey: Self.saidKey)
    }

    var recentCharacters: [String] {
        defaults.stringArray(forKey: Self.recentsKey) ?? []
    }

    func used(_ emoji: Emoji) {
        var recents = recentCharacters.filter { $0 != emoji.character }
        recents.insert(emoji.character, at: 0)
        defaults.set(Array(recents.prefix(24)), forKey: Self.recentsKey)
    }

    /// "trop content mais crevé": the decision model picks among the
    /// expressive emoji. Only what was typed is sent, and emoji names.
    func searchByMeaning(_ request: String, keys: [DecisionProvider: String]) async -> (emoji: [Emoji], label: String)? {
        let candidates = Array(EmojiSearch.expressive(all).prefix(254))
        guard !candidates.isEmpty else { return nil }
        let question = DecisionQuestion(
            name: "emoji", instructions: EmojiSearch.instructions,
            // Both names: "trop content" reads better against "visage
            // souriant" than against "grinning face" alone.
            options: candidates.enumerated().map { index, emoji in
                .init(value: "e\(index)", description: "\(emoji.character) \(emoji.english)" + (emoji.name == emoji.english ? "" : " — \(emoji.name)"))
            }
        )
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let start = ContinuousClock.now
            do {
                let answers = try await DecisionClient.decide([question], input: EmojiSearch.input(request), provider: provider, key: key)
                guard let answer = answers[question.name] else { continue }
                let ranked = answer.probabilities
                    .filter { $0.value >= 0.03 }
                    .sorted { $0.value > $1.value }
                    .prefix(8)
                    .compactMap { entry in Int(entry.key.dropFirst()).flatMap { candidates.indices.contains($0) ? candidates[$0] : nil } }
                let elapsed = ContinuousClock.now - start
                let name = provider == .typeSafe ? "Jev" : "Decisions"
                Log.trace("Emoji by meaning “\(request)”: \(ranked.prefix(3).map(\.character).joined()) by \(name) in \(elapsed.compact)")
                return (ranked, "\(name) · \(String(format: "%.2f s", elapsed.milliseconds / 1_000))")
            } catch {
                Log.actions.error("Emoji by meaning with \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}
