import XCTest
@testable import SkilliCore

final class SymbolTableTests: XCTestCase {
    /// macOS's emoji as the picker reads them, a few: names in French.
    private let emoji = [
        Emoji(character: "🍎", name: "pomme rouge", english: "red apple"),
        Emoji(character: "🍏", name: "pomme verte", english: "green apple"),
        Emoji(character: "🍍", name: "ananas", english: "pineapple"),
        Emoji(character: "⭐", name: "étoile", english: "star"),
        Emoji(character: "↩️", name: "flèche courbe vers la gauche", english: "right arrow curving left"),
        Emoji(character: "😂", name: "visage riant aux larmes", english: "face with tears of joy")
    ]

    private var all: [Emoji] {
        let written = SymbolTable.written(language: "fr")
        let keys = Set((emoji + written).map { SymbolTable.key($0.character) })
        return emoji + written + SymbolTable.unicode(excluding: keys)
    }

    /// Every symbol written has both names and is written once; one that
    /// is also an emoji says how it is drawn, as text or as the emoji.
    func testEverySymbolIsWrittenOnceWithBothNames() {
        let entries = SymbolTable.entries
        XCTAssertGreaterThan(entries.count, 180)
        XCTAssertEqual(Set(entries.map { SymbolTable.key($0.character) }).count, entries.count, "a symbol twice")
        for entry in entries {
            XCTAssertFalse(entry.english.isEmpty, entry.character)
            XCTAssertFalse(entry.french.isEmpty, entry.character)
            XCTAssertEqual(entry.character.count, 1, "one character: \(entry.character)")
            let selector = entry.character.unicodeScalars.last.map { $0.value == 0xFE0E || $0.value == 0xFE0F } ?? false
            if EmojiOrder.place(of: SymbolTable.key(entry.character)) != nil {
                XCTAssertTrue(selector, "\(entry.character) is also an emoji: U+FE0E (text) or U+FE0F (the emoji)")
            }
        }
        XCTAssertEqual(SymbolTable.groupNames, ["Mac Keys", "Typography", "Arrows", "Math", "Currencies", "Signs & Shapes"])
    }

    /// The Apple logo by what people call it, in both languages; the Mac's
    /// keys by their names and the short ones.
    func testMacKeysAndTheAppleLogo() {
        let all = all
        XCTAssertEqual(EmojiSearch.search("apple", in: all).first?.character, "\u{F8FF}")
        XCTAssertEqual(EmojiSearch.search("apple logo", in: all).map(\.character), ["\u{F8FF}"])
        XCTAssertEqual(EmojiSearch.search("logo pomme", in: all).first?.character, "\u{F8FF}")
        // The fruit is still found with it.
        XCTAssertTrue(EmojiSearch.search("pomme", in: all).contains { $0.character == "🍎" })
        XCTAssertEqual(EmojiSearch.search("cmd", in: all).first?.character, "⌘")
        XCTAssertEqual(EmojiSearch.search("commande", in: all).first?.character, "⌘")
        XCTAssertEqual(EmojiSearch.search("option", in: all).first?.character, "⌥")
        XCTAssertEqual(EmojiSearch.search("hyper", in: all).first?.character, "✦")
        // The Return key drawn as text; the emoji keeps its own name.
        XCTAssertEqual(EmojiSearch.search("return key", in: all).first?.character, "\u{21A9}\u{FE0E}")
        XCTAssertEqual(EmojiSearch.search("curving left", in: all).first?.character, "↩️")
    }

    func testFoundByNameInBothLanguagesAndByItself() {
        let all = all
        XCTAssertEqual(EmojiSearch.search("fleche droite", in: all).first?.character, "→")
        XCTAssertEqual(EmojiSearch.search("right arrow", in: all).first?.character, "→")
        XCTAssertEqual(EmojiSearch.search("tiret cadratin", in: all).first?.character, "—")
        XCTAssertEqual(EmojiSearch.search("euro", in: all).first?.character, "€")
        XCTAssertEqual(EmojiSearch.search("different", in: all).first?.character, "≠")
        XCTAssertEqual(EmojiSearch.search("au carré", in: all).first?.character, "²")
        // The symbol itself typed, or pasted.
        XCTAssertEqual(EmojiSearch.search("→", in: all).first?.character, "→")
        XCTAssertEqual(EmojiSearch.search(" ⌘ ", in: all).first?.character, "⌘")
        // An emoji first when both fit as well.
        XCTAssertEqual(EmojiSearch.search("star", in: all).first?.character, "⭐")
        XCTAssertTrue(EmojiSearch.search("star", in: all).contains { $0.character == "★" })
        // ♀️ ♂️: emoji macOS leaves unnamed, named here.
        XCTAssertEqual(EmojiSearch.search("female sign", in: all).first?.character, "\u{2640}\u{FE0F}")
        XCTAssertEqual(EmojiSearch.search("symbole masculin", in: all).first?.character, "\u{2642}\u{FE0F}")
    }

    /// Every other symbol Unicode names, by that name: never one written
    /// above, never an emoji.
    func testUnicodeNamesTheRest() {
        let keys = Set(SymbolTable.entries.map { SymbolTable.key($0.character) })
        let rest = SymbolTable.unicode(excluding: keys)
        XCTAssertGreaterThan(rest.count, 2000)
        XCTAssertTrue(rest.allSatisfy { $0.kind == .character && $0.name == $0.name.lowercased() })
        XCTAssertFalse(rest.contains { keys.contains($0.character) })
        XCTAssertFalse(rest.contains { $0.character == "→" }, "written above")
        XCTAssertFalse(rest.contains { $0.character == "↔" }, "an emoji")
        XCTAssertEqual(EmojiSearch.search("three rightwards arrows", in: all).first?.character, "⇶")
        XCTAssertEqual(EmojiSearch.search("box drawings light horizontal", in: all).first?.character, "─")
        // Names written for people come before Unicode's own ("arrowhead…").
        let arrows = EmojiSearch.search("arrow", in: all, limit: 96)
        let firstWritten = arrows.firstIndex { $0.kind == .symbol }
        let firstUnicode = arrows.firstIndex { $0.kind == .character }
        XCTAssertNotNil(firstWritten)
        XCTAssertLessThan(firstWritten ?? .max, firstUnicode ?? .max)
        XCTAssertTrue(SymbolTable.isDrawn("⇶"))
        XCTAssertTrue(SymbolTable.isDrawn("\u{F8FF}"))
    }

    /// Browsing: Unicode's emoji groups, then the symbols' in the table's
    /// order; Unicode's other characters only by search.
    func testBrowsingAfterTheEmoji() {
        let list = EmojiList.browsing(recent: [], all: all)
        let names = list.sections.map(\.name)
        XCTAssertEqual(Array(names.suffix(6)), SymbolTable.groupNames)
        let symbols = list.emoji.filter { $0.kind == .symbol }
        XCTAssertEqual(symbols.first?.character, "⌘")
        XCTAssertEqual(symbols.count, SymbolTable.entries.count - 2, "all but ♀️ ♂️, browsed among Unicode's Symbols")
        XCTAssertFalse(list.emoji.contains { $0.kind == .character })
        XCTAssertEqual(list.sections.map(\.count).reduce(0, +), list.emoji.count)
        XCTAssertEqual(EmojiList.groupNames.count, EmojiOrder.groupNames.count + 6)
    }

    /// A heart or a star among the symbols says no feeling.
    func testSymbolsAreNotFeelings() {
        let expressive = EmojiSearch.expressive(all)
        XCTAssertTrue(expressive.contains { $0.character == "😂" })
        XCTAssertFalse(expressive.contains { $0.kind != .emoji })
    }

    /// The keys that type a character, the fewest modifiers first.
    func testTypingKeysPreferFewerModifiers() {
        let k = Key.character("k"), two = Key.character("2"), e = Key.character("e")
        let keys = TypingKeys([
            (Chord(k, [.option, .shift]), "\u{F8FF}"),
            (Chord(two, [.option, .shift]), "€"),
            (Chord(e, [.option]), "€"),
            (Chord(k, []), "k"),
            (Chord(k, [.shift]), "K")
        ])
        XCTAssertEqual(keys.chord(typing: "\u{F8FF}")?.description, "⌥⇧K")
        XCTAssertEqual(keys.chord(typing: "€")?.description, "⌥E")
        XCTAssertEqual(keys.chord(typing: "K")?.description, "⇧K")
        XCTAssertNil(keys.chord(typing: "→"))
    }

    /// A key, whatever the text: thousands of names compared as bytes.
    func testSearchStaysFast() {
        let index = EmojiSearch.Index(all)
        let start = Date()
        for query in ["a", "ar", "arr", "arro", "arrow", "fleche", "pomme", "cmd", "star", "x"] {
            _ = EmojiSearch.search(query, in: index, limit: 96)
        }
        let perKey = Date().timeIntervalSince(start) / 10 * 1_000
        print("Emoji and symbols, \(index.emoji.count) names: \(String(format: "%.2f", perKey)) ms a key")
        XCTAssertLessThan(perKey, 25, "debug build; release is several times faster")
    }
}
