import CoreText
import Foundation
import Synchronization

/// The symbols the emoji picker finds beside the emoji: written for
/// skil.li, each with its name in English and in French and the other
/// words people type for it (the Mac's keys and the Apple logo,
/// typography, arrows, math, currencies, signs), browsed in groups after
/// Unicode's; then every other symbol Unicode names in its symbol blocks,
/// by that name, found by search only. macOS names emoji, not symbols,
/// and the Apple logo nowhere: its emoji data and the Character Viewer's
/// names (`CharacterDB.sqlite3`) leave it out.
public enum SymbolTable {
    /// Each group's name and its symbols, one a line: the symbol, its
    /// English name, its French name, other words (both languages).
    /// U+FE0E after one that is also an emoji draws it as text, as macOS's
    /// menus draw ↩ (the emoji stays an emoji); U+FE0F marks an emoji
    /// macOS leaves unnamed (♀️ ♂️), named here until it names them.
    static let groups: [(name: String, entries: [String])] = [
        ("Mac Keys", [
            "⌘ | Command key | touche Commande | cmd, command, commande, pomme, cloverleaf",
            "⌥ | Option key | touche Option | opt, alt, option",
            "⌃ | Control key | touche Contrôle | ctrl, control, contrôle",
            "⇧ | Shift key | touche Maj | shift, maj, majuscule",
            "⇪ | Caps Lock key | touche Verr. Maj | caps lock, verrouillage majuscule",
            "✦ | Hyper Key | touche Hyper | hyper, skil.li, caps lock held",
            "\u{21A9}\u{FE0E} | Return key | touche Retour | return, enter, entrée, retour",
            "⌤ | Enter key | touche Entrée | enter, entrée, keypad, pavé numérique",
            "⌫ | Delete key | touche Effacer | delete, backspace, effacer, supprimer",
            "⌦ | Forward Delete key | touche Suppression | forward delete, del, suppr, suppression",
            "⎋ | Escape key | touche Échap | esc, escape, échap, échappement",
            "⇥ | Tab key | touche Tab | tab, tabulation",
            "⇤ | Back Tab | tabulation arrière | back tab, shift tab",
            "␣ | Space bar | barre d'espace | space, espace",
            "\u{23CF}\u{FE0E} | Eject key | touche Éjecter | eject, éjecter",
            "\u{F8FF} | Apple logo | logo Apple | apple, mac, pomme, logo",
            "⇞ | Page Up key | touche Page précédente | page up, pgup, haut de page",
            "⇟ | Page Down key | touche Page suivante | page down, pgdn, bas de page",
            "\u{2196}\u{FE0E} | Home key | touche Début | home, début, origine",
            "\u{2198}\u{FE0E} | End key | touche Fin | end, fin",
            "⌧ | Clear key | touche Effacer tout | clear, effacer tout",
            "⏻ | Power symbol | symbole marche-arrêt | power, on off, marche, arrêt, allumer"
        ]),
        ("Typography", [
            "— | em dash | tiret cadratin | dash, long dash, tiret, tiret long",
            "– | en dash | tiret demi-cadratin | dash, range, tiret, tiret court",
            "… | ellipsis | points de suspension | dots, three dots, trois points",
            "« | left guillemet | guillemet ouvrant | quote, guillemets, chevrons",
            "» | right guillemet | guillemet fermant | quote, guillemets, chevrons",
            "“ | left double quotation mark | guillemet anglais ouvrant | quote, quotes, citation",
            "” | right double quotation mark | guillemet anglais fermant | quote, quotes, citation",
            "‘ | left single quotation mark | guillemet simple ouvrant | quote, apostrophe",
            "’ | apostrophe | apostrophe typographique | right single quote, apostrophe courbe",
            "‹ | single left-pointing guillemet | chevron simple ouvrant | angle quote, guillemet",
            "› | single right-pointing guillemet | chevron simple fermant | angle quote, guillemet",
            "„ | low double quotation mark | guillemet bas | german quote, quote",
            "• | bullet | puce | dot, list, point, liste",
            "· | middle dot | point médian | interpunct, point milieu, inclusive",
            "§ | section sign | signe section | section, paragraphe, article, law, loi",
            "¶ | pilcrow | pied-de-mouche | paragraph, alinéa, paragraphe",
            "† | dagger | obèle | footnote, note, croix, death, décès",
            "‡ | double dagger | double obèle | footnote, note",
            "′ | prime | prime | minutes, feet, pieds",
            "″ | double prime | seconde | seconds, inches, pouces",
            "‰ | per mille | pour mille | permille, per thousand",
            "№ | numero sign | signe numéro | number, numéro, no",
            "¿ | inverted question mark | point d'interrogation inversé | spanish, espagnol",
            "¡ | inverted exclamation mark | point d'exclamation inversé | spanish, espagnol",
            "‽ | interrobang | point exclarogatif | interrobang",
            "\u{00A9}\u{FE0E} | copyright sign | symbole copyright | copyright, droits d'auteur",
            "\u{00AE}\u{FE0E} | registered sign | marque déposée | registered, trademark",
            "\u{2122}\u{FE0E} | trade mark sign | symbole marque commerciale | trademark, tm",
            "° | degree sign | symbole degré | degrees, température, angle",
            "ª | feminine ordinal indicator | indicateur ordinal féminin | ordinal, primera",
            "º | masculine ordinal indicator | indicateur ordinal masculin | ordinal, primo, numéro"
        ]),
        ("Arrows", [
            "→ | right arrow | flèche vers la droite | to, next, then, right, vers, suivant, droite",
            "← | left arrow | flèche vers la gauche | back, from, left, retour, précédent, gauche",
            "↑ | up arrow | flèche vers le haut | up, increase, haut, hausse",
            "↓ | down arrow | flèche vers le bas | down, decrease, bas, baisse",
            "⇒ | right double arrow | double flèche vers la droite | implies, therefore, donc, implique",
            "⇐ | left double arrow | double flèche vers la gauche | implied by, impliqué par",
            "⇔ | left right double arrow | double flèche gauche-droite | iff, equivalent, équivalent, si et seulement si",
            "⇑ | up double arrow | double flèche vers le haut | up, haut",
            "⇓ | down double arrow | double flèche vers le bas | down, bas",
            "⟶ | long right arrow | longue flèche vers la droite | to, maps to, vers",
            "⟵ | long left arrow | longue flèche vers la gauche | from, depuis",
            "⟷ | long left right arrow | longue flèche gauche-droite | both ways, aller-retour",
            "↦ | maps to | flèche d'application | maps to, function, fonction",
            "⇄ | right over left arrows | flèches opposées | swap, exchange, échange, échanger",
            "⇅ | up down arrows | flèches haut et bas | sort, trier, tri",
            "↻ | clockwise arrow | flèche sens horaire | refresh, reload, redo, rafraîchir, recharger, rétablir",
            "↺ | counterclockwise arrow | flèche sens antihoraire | undo, rotate, annuler, tourner",
            "↵ | return arrow | flèche retour chariot | return, enter, newline, retour à la ligne",
            "↳ | down then right arrow | flèche coudée | reply, sub item, indent, réponse, sous-élément",
            "➜ | heavy round-tipped arrow | flèche épaisse | go, next, aller",
            "➔ | heavy wide arrow | flèche large | go, next, aller",
            "⇢ | dashed right arrow | flèche pointillée | dashed, pointillés",
            "⤳ | wave arrow | flèche ondulée | leads to, mène à"
        ]),
        ("Math", [
            "× | multiplication sign | signe multiplication | times, multiply, by, fois, multiplier",
            "÷ | division sign | signe division | divide, divided, diviser, divisé",
            "± | plus-minus sign | signe plus ou moins | plus minus, about, environ",
            "∓ | minus-plus sign | signe moins ou plus | minus plus",
            "− | minus sign | signe moins | minus, subtract, moins, soustraire",
            "≠ | not equal to | différent de | not equal, unequal, différent, inégal",
            "≈ | almost equal to | environ égal à | approximately, approx, about, environ, à peu près",
            "≡ | identical to | identique à | identical, equivalent, congruent, identique",
            "≤ | less than or equal to | inférieur ou égal à | at most, lte, au plus, inférieur",
            "≥ | greater than or equal to | supérieur ou égal à | at least, gte, au moins, supérieur",
            "≪ | much less than | très inférieur à | much less",
            "≫ | much greater than | très supérieur à | much greater",
            "∞ | infinity | infini | infinite, forever, toujours",
            "√ | square root | racine carrée | root, sqrt, racine",
            "∛ | cube root | racine cubique | cube root, cbrt",
            "∑ | summation | somme | sum, sigma, total",
            "∏ | product | produit | product, pi",
            "∫ | integral | intégrale | integral, integrate, intégrer",
            "∂ | partial derivative | dérivée partielle | partial, derivative, d rond",
            "∆ | increment | delta | delta, difference, change, variation, différence",
            "∇ | nabla | nabla | gradient, del",
            "π | pi | pi | pi, 3.14",
            "µ | micro sign | signe micro | micro, mu",
            "Ω | omega | oméga | omega, ohm",
            "∅ | empty set | ensemble vide | empty, null, nothing, vide",
            "∈ | element of | appartient à | in, member, élément",
            "∉ | not an element of | n'appartient pas à | not in",
            "⊂ | subset of | inclus dans | subset, inclus",
            "⊃ | superset of | contient | superset",
            "∪ | union | union | union, or",
            "∩ | intersection | intersection | intersection, and",
            "∀ | for all | pour tout | for all, every, quel que soit, chaque",
            "∃ | there exists | il existe | exists, some, existe",
            "¬ | not sign | négation | not, negation, non",
            "∧ | logical and | et logique | and, et, wedge",
            "∨ | logical or | ou logique | or, ou, vee",
            "⊕ | circled plus | plus cerclé | xor, direct sum, ou exclusif",
            "∝ | proportional to | proportionnel à | proportional",
            "∠ | angle | angle | angle",
            "⊥ | perpendicular | perpendiculaire | perpendicular, orthogonal, bottom",
            "∥ | parallel to | parallèle à | parallel",
            "∴ | therefore | donc | therefore, so, donc",
            "∵ | because | parce que | because, since, car",
            "⌀ | diameter sign | symbole diamètre | diameter, diamètre",
            "½ | one half | un demi | half, demi, moitié, 1/2",
            "⅓ | one third | un tiers | third, tiers, 1/3",
            "⅔ | two thirds | deux tiers | two thirds, 2/3",
            "¼ | one quarter | un quart | quarter, quart, 1/4",
            "¾ | three quarters | trois quarts | three quarters, 3/4",
            "⅛ | one eighth | un huitième | eighth, 1/8",
            "¹ | superscript one | exposant un | power, puissance, exposant",
            "² | superscript two | exposant deux | squared, square, carré, au carré, puissance",
            "³ | superscript three | exposant trois | cubed, cube, au cube, puissance",
            "ⁿ | superscript n | exposant n | power, puissance, nth",
            "₂ | subscript two | indice deux | co2, h2o, indice",
            "℃ | degree Celsius | degré Celsius | celsius, temperature, température",
            "℉ | degree Fahrenheit | degré Fahrenheit | fahrenheit, temperature, température",
            "ℕ | natural numbers | entiers naturels | natural, naturels",
            "ℤ | integers | entiers relatifs | integers, entiers",
            "ℚ | rational numbers | nombres rationnels | rationals, rationnels",
            "ℝ | real numbers | nombres réels | reals, réels",
            "ℂ | complex numbers | nombres complexes | complex, complexes"
        ]),
        ("Currencies", [
            "€ | euro | euro | eur, money, argent",
            "$ | dollar | dollar | usd, money, argent",
            "£ | pound sterling | livre sterling | gbp, pound, livre",
            "¥ | yen | yen | jpy, yuan, cny",
            "¢ | cent | cent | cents, centime",
            "₿ | bitcoin | bitcoin | btc, crypto",
            "₽ | ruble | rouble | rub",
            "₹ | rupee | roupie | inr, india, inde",
            "₩ | won | won | krw, korea, corée",
            "₺ | lira | livre turque | try, turkey, turquie",
            "₪ | shekel | shekel | ils, israel",
            "₫ | dong | dong | vnd, vietnam",
            "₴ | hryvnia | hryvnia | uah, ukraine",
            "₦ | naira | naira | ngn, nigeria",
            "₱ | peso | peso | php, philippines",
            "฿ | baht | baht | thb, thailand, thaïlande",
            "₣ | franc | franc | frf, franc français",
            "¤ | currency sign | symbole monétaire | currency, monnaie"
        ]),
        ("Signs & Shapes", [
            "✓ | check mark | coche | check, tick, done, ok, yes, fait, oui, valider",
            "✗ | ballot x | croix | cross, wrong, no, faux, non",
            "★ | star | étoile | star, favorite, rating, favori, note",
            "☆ | white star | étoile vide | star, outline, rating, note",
            "✧ | four-pointed star | étoile à quatre branches | sparkle, twinkle, étincelle",
            "♡ | white heart | cœur vide | heart, love, like, amour",
            "● | black circle | rond plein | dot, circle, filled, cercle, point",
            "○ | white circle | rond vide | circle, ring, cercle",
            "■ | black square | carré plein | square, filled, carré",
            "□ | white square | carré vide | square, box, carré",
            "▲ | up triangle | triangle vers le haut | triangle, up, haut",
            "△ | white up triangle | triangle vide | triangle, delta",
            "▼ | down triangle | triangle vers le bas | triangle, down, menu, bas",
            "▽ | white down triangle | triangle vide vers le bas | triangle",
            "▸ | small right triangle | petit triangle vers la droite | disclosure, expand, déplier",
            "▾ | small down triangle | petit triangle vers le bas | dropdown, collapse, menu, replier",
            "◆ | black diamond | losange plein | diamond, losange",
            "◇ | white diamond | losange vide | diamond, losange",
            "☐ | ballot box | case vide | checkbox, todo, case, à faire",
            "☒ | ballot box with x | case barrée | checkbox, cancelled, case, annulé",
            "♪ | eighth note | croche | music, note, musique",
            "♫ | beamed eighth notes | doubles croches | music, song, notes, musique, chanson",
            "☾ | crescent moon | croissant de lune | moon, night, dark, lune, nuit, sombre",
            "☼ | sun | soleil | sun, light, brightness, clair, luminosité",
            "✿ | flower | fleur | flower, fleur",
            "⚑ | flag | drapeau | flag, report, signaler",
            "☛ | pointing hand | main qui pointe | pointing, see, voir",
            "✎ | pencil | crayon | edit, write, modifier, écrire",
            "☏ | telephone | téléphone | phone, call, tel, appeler",
            "\u{2640}\u{FE0F} | female sign | symbole féminin | female, woman, venus, femme, féminin",
            "\u{2642}\u{FE0F} | male sign | symbole masculin | male, man, mars, homme, masculin",
            "⚥ | male and female sign | symbole mixte | unisex, both, mixte"
        ])
    ]

    /// The groups' names, in order: shown after Unicode's while browsing.
    public static let groupNames: [String] = groups.map(\.name)

    struct Entry: Sendable {
        let character: String
        let english: String
        let french: String
        let words: [String]
        let group: Int
        let index: Int
    }

    static let entries: [Entry] = {
        var entries: [Entry] = []
        for (group, entry) in groups.enumerated() {
            for line in entry.entries {
                let parts = line.components(separatedBy: " | ")
                guard parts.count >= 3 else { continue }
                let words = parts.count > 3 ? parts[3].components(separatedBy: ", ") : []
                entries.append(Entry(character: parts[0], english: parts[1], french: parts[2], words: words, group: group, index: entries.count))
            }
        }
        return entries
    }()

    private static let places: [String: Entry] = Dictionary(entries.map { ($0.character, $0) }, uniquingKeysWith: { first, _ in first })

    /// Where it is browsed among the symbols: its group, then its rank; nil
    /// for one this table does not hold.
    static func place(of character: String) -> (group: Int, index: Int)? {
        places[character].map { ($0.group, $0.index) }
    }

    /// The table's symbols, named in `language` ("fr"; English otherwise),
    /// the English name and every word kept for the search. An emoji
    /// macOS leaves unnamed (U+FE0F) is an emoji.
    public static func written(language: String) -> [Emoji] {
        entries.map { entry in
            let isEmoji = entry.character.unicodeScalars.last?.value == 0xFE0F
            return Emoji(character: entry.character, name: language == "fr" ? entry.french : entry.english,
                         english: entry.english, words: entry.words, kind: isEmoji ? .emoji : .symbol)
        }
    }

    /// Unicode's blocks of symbols, punctuation and shapes: every one they
    /// name is found by that name ("three rightwards arrows").
    static let blocks: [ClosedRange<UInt32>] = [
        0xA1...0xBF,        // Latin-1 Supplement: its signs
        0x2010...0x205E,    // General Punctuation
        0x2070...0x209C,    // Superscripts and Subscripts
        0x20A0...0x20C0,    // Currency Symbols
        0x2100...0x214F,    // Letterlike Symbols
        0x2150...0x218B,    // Number Forms
        0x2190...0x21FF,    // Arrows
        0x2200...0x22FF,    // Mathematical Operators
        0x2300...0x23FF,    // Miscellaneous Technical
        0x2400...0x2426,    // Control Pictures
        0x2460...0x24FF,    // Enclosed Alphanumerics
        0x2500...0x257F,    // Box Drawing
        0x2580...0x259F,    // Block Elements
        0x25A0...0x25FF,    // Geometric Shapes
        0x2600...0x26FF,    // Miscellaneous Symbols
        0x2700...0x27BF,    // Dingbats
        0x27C0...0x27EF,    // Miscellaneous Mathematical Symbols-A
        0x27F0...0x27FF,    // Supplemental Arrows-A
        0x2900...0x297F,    // Supplemental Arrows-B
        0x2980...0x29FF,    // Miscellaneous Mathematical Symbols-B
        0x2A00...0x2AFF,    // Supplemental Mathematical Operators
        0x2B00...0x2BFF,    // Miscellaneous Symbols and Arrows
        0x2E00...0x2E5D     // Supplemental Punctuation
    ]

    /// Every other symbol of `blocks` with a Unicode name, by that name in
    /// lowercase: not an emoji, nor one `excluding` holds (`key`s).
    public static func unicode(excluding keys: Set<String>) -> [Emoji] {
        var found: [Emoji] = []
        for block in blocks {
            for value in block {
                guard let scalar = Unicode.Scalar(value), let name = scalar.properties.name else { continue }
                switch scalar.properties.generalCategory {
                case .unassigned, .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator, .privateUse:
                    continue
                default:
                    break
                }
                let character = String(scalar)
                guard !keys.contains(character), EmojiOrder.place(of: character) == nil else { continue }
                found.append(Emoji(character: character, name: name.lowercased(), english: name.lowercased(), kind: .character))
            }
        }
        return found
    }

    private static let drawn = Mutex<[String: Bool]>([:])

    /// Whether a font of this Mac draws `character`: Unicode names some
    /// that none does, which would show as an empty box.
    public static func isDrawn(_ character: String) -> Bool {
        if let known = drawn.withLock({ $0[character] }) { return known }
        let base = CTFontCreateUIFontForLanguage(.system, 32, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 32, nil)
        let text = character as CFString
        let font = CTFontCreateForString(base, text, CFRange(location: 0, length: CFStringGetLength(text)))
        var units = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        let result = CTFontCopyPostScriptName(font) as String != "LastResort"
            && CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count)
        drawn.withLock { $0[character] = result }
        return result
    }

    /// Compared without the presentation selectors U+FE0E and U+FE0F.
    public static func key(_ character: String) -> String {
        String(character.unicodeScalars.filter { $0.value != 0xFE0E && $0.value != 0xFE0F })
    }
}

/// The keys that type each character on a keyboard layout, the fewest
/// modifiers first: "\u{F8FF}" is ⌥⇧K on U.S., "€" ⌥$ on French. What the
/// emoji picker says beside a symbol's name, so it can be typed without it.
public struct TypingKeys: Sendable {
    private var chords: [String: Chord] = [:]

    /// What each key types with each set of modifiers held.
    public init(_ typed: [(chord: Chord, text: String)]) {
        for (chord, text) in typed where !text.isEmpty {
            let key = SymbolTable.key(text)
            if let known = chords[key], known.modifiers.rawValue.nonzeroBitCount <= chord.modifiers.rawValue.nonzeroBitCount { continue }
            chords[key] = chord
        }
    }

    public func chord(typing character: String) -> Chord? {
        chords[SymbolTable.key(character)]
    }
}
