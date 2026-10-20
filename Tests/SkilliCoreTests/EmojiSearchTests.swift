import XCTest
@testable import SkilliCore

final class EmojiSearchTests: XCTestCase {
    private let catalog = [
        Emoji(character: "❤️", name: "cœur rouge", english: "red heart"),
        Emoji(character: "💔", name: "cœur brisé", english: "broken heart"),
        Emoji(character: "😂", name: "visage riant aux larmes", english: "face with tears of joy"),
        Emoji(character: "😴", name: "visage endormi", english: "sleeping face"),
        Emoji(character: "🔥", name: "feu", english: "fire"),
        Emoji(character: "🕰️", name: "pendule", english: "mantelpiece clock"),
        Emoji(character: "👍🏽", name: "pouce vers le haut : peau légèrement mate", english: "thumbs up: medium skin tone"),
        Emoji(character: "👍", name: "pouce vers le haut", english: "thumbs up"),
        Emoji(character: "🐱", name: "tête de chat", english: "cat face")
    ]

    func testSearchByNameInBothLanguages() {
        XCTAssertEqual(EmojiSearch.search("coeur", in: catalog).map(\.character), ["❤️", "💔"])
        XCTAssertEqual(EmojiSearch.search("brisé", in: catalog).first?.character, "💔")
        XCTAssertEqual(EmojiSearch.search("heart broken", in: catalog).map(\.character), ["💔"])
        XCTAssertEqual(EmojiSearch.search("feu", in: catalog).first?.character, "🔥")
        XCTAssertEqual(EmojiSearch.search("tears", in: catalog).first?.character, "😂")
        XCTAssertTrue(EmojiSearch.search("zzzz", in: catalog).isEmpty)
        XCTAssertEqual(EmojiSearch.search("", in: catalog).count, catalog.count)
    }

    /// What was typed to find one by meaning finds it by name next time,
    /// first when typed the same way.
    func testSaidWordsFindItAgain() {
        let said = ["😴": ["complètement crevé"]]
        XCTAssertTrue(EmojiSearch.search("complètement crevé", in: catalog).isEmpty)
        XCTAssertEqual(EmojiSearch.search("completement  crevé", in: catalog, said: said).map(\.character), ["😴"])
        XCTAssertEqual(EmojiSearch.search("crevé", in: catalog, said: said).first?.character, "😴")
        // The same words first, over a name they also match.
        let fire = ["🔥": ["feu de joie"]]
        XCTAssertEqual(EmojiSearch.search("feu", in: catalog, said: fire).first?.character, "🔥")
        XCTAssertEqual(EmojiSearch.search("feu de joie", in: catalog, said: fire).map(\.character), ["🔥"])
    }

    /// Each person or hand toned, the presentation selector dropped, only
    /// when macOS draws the result as one emoji.
    func testSkinTone() {
        XCTAssertEqual(EmojiSkinTone.medium.apply(to: "👍"), "👍🏽")
        XCTAssertEqual(EmojiSkinTone.dark.apply(to: "✌️"), "✌🏿")
        XCTAssertEqual(EmojiSkinTone.light.apply(to: "🧑\u{200D}💻"), "🧑🏻\u{200D}💻")
        XCTAssertEqual(EmojiSkinTone.mediumDark.apply(to: "🕵️\u{200D}♀️"), "🕵🏾\u{200D}♀️")
        XCTAssertEqual(EmojiSkinTone.standard.apply(to: "👍"), "👍")
        XCTAssertEqual(EmojiSkinTone.medium.apply(to: "❤️"), "❤️", "no tones")
        XCTAssertEqual(EmojiSkinTone.medium.apply(to: "🐱"), "🐱")
        // Families do not come in one tone for all.
        let family = "👨\u{200D}👩\u{200D}👧"
        XCTAssertEqual(EmojiSkinTone.medium.apply(to: family), family)
        XCTAssertEqual(Emoji(character: "👋", name: "main qui salue", english: "waving hand").character(in: .mediumLight), "👋🏼")
        XCTAssertEqual(EmojiSkinTone.allCases.count, 6)
    }

    /// Browsing: the recent ones, then Unicode's groups in its order;
    /// what Unicode does not order is left to the search.
    func testBrowsingInUnicodesOrder() {
        let all = [
            Emoji(character: "🐱", name: "tête de chat", english: "cat face"),
            Emoji(character: "❤️", name: "cœur rouge", english: "red heart"),
            Emoji(character: "😂", name: "visage riant aux larmes", english: "face with tears of joy"),
            Emoji(character: "👍", name: "pouce vers le haut", english: "thumbs up"),
            Emoji(character: "😀", name: "visage rieur", english: "grinning face"),
            Emoji(character: "🫱\u{200D}🫲", name: "poignée de main", english: "handshake parts"),
            Emoji(character: "🇫🇷", name: "drapeau : France", english: "flag: France")
        ]
        let list = EmojiList.browsing(recent: [all[3]], all: all)
        XCTAssertEqual(list.emoji.map(\.character), ["👍", "😀", "😂", "❤️", "🐱", "🇫🇷"])
        XCTAssertEqual(list.sections, [
            .init(name: "Recently Used", count: 1), .init(name: "Smileys & Emotion", count: 3),
            .init(name: "Animals & Nature", count: 1), .init(name: "Flags", count: 1)
        ])
        XCTAssertEqual(list.sections.map(\.count).reduce(0, +), list.emoji.count)
        XCTAssertEqual(EmojiList.browsing(recent: [], all: all).sections.first?.name, "Smileys & Emotion")
        // macOS writes some without U+FE0F.
        XCTAssertEqual(EmojiOrder.place(of: "❤"), EmojiOrder.place(of: "❤️"))
        XCTAssertNil(EmojiOrder.place(of: "👍🏽"), "tones are put on by the setting")
        XCTAssertEqual(EmojiOrder.groupNames.count, 9)
        XCTAssertFalse(EmojiOrder.groupNames.contains("Component"))
    }

    func testExpressiveKeepsFeelingsNotClocksOrSkinTones() {
        let expressive = EmojiSearch.expressive(catalog).map(\.character)
        XCTAssertTrue(expressive.contains("😂"))
        XCTAssertTrue(expressive.contains("💔"))
        XCTAssertTrue(expressive.contains("🔥"))
        XCTAssertTrue(expressive.contains("👍"))
        XCTAssertFalse(expressive.contains("🕰️"), "a clock is not a feeling")
        XCTAssertFalse(expressive.contains("👍🏽"), "one skin tone is enough")
        XCTAssertFalse(expressive.contains("🐱"))
    }
}
