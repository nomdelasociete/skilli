import CoreGraphics
import Foundation

/// Something in the window in front that a goal can name: an Accessibility
/// element, a menu item, or words read on screen (OCR) where the app tells
/// Accessibility nothing. Frames are in screen points, top-left origin, as
/// Accessibility gives them.
public struct ScreenItem: Equatable, Sendable {
    public enum Source: String, Sendable {
        case element, menu, text
    }

    /// "i12": what the decision model answers with.
    public let id: String
    public let source: Source
    /// "button", "text field", "checkbox", "menu item", "text"…
    public let role: String
    public let label: String
    public let value: String?
    public let enabled: Bool
    public let frame: CGRect?
    /// "top left", "center"… in the window; empty for menu items.
    public let region: String

    public init(id: String, source: Source, role: String, label: String, value: String? = nil, enabled: Bool = true,
                frame: CGRect? = nil, region: String = "") {
        self.id = id
        self.source = source
        self.role = role
        self.label = label
        self.value = value
        self.enabled = enabled
        self.frame = frame
        self.region = region
    }

    /// A field typed into: a text field, a text area, a combo box.
    public var isField: Bool { role.hasSuffix("field") || role == "text area" || role == "combo box" }

    /// Something to press or fill that Accessibility gives no words for
    /// (an icon-only button), where it is: only a picture tells it apart.
    public var isWordless: Bool {
        source == .element && role != "text" && label.isEmpty && (value ?? "").isEmpty && frame != nil
    }

    /// `button “Share” · top right`, `text field “To” = “paul@…”`,
    /// `checkbox “Subscribe” (off)`: how the model reads it.
    public var description: String {
        var text = role
        if !label.isEmpty { text += " “\(label)”" }
        if let value, !value.isEmpty {
            text += role == "checkbox" || role == "radio" || role == "switch" ? " (\(value == "1" ? "on" : "off"))" : " = “\(value)”"
        }
        if !enabled { text += " (disabled)" }
        if !region.isEmpty { text += " · \(region)" }
        return text
    }
}

/// The pure part of acting in the window in front (Ask's "do it here"):
/// which of its items to offer the decision model for a goal, which labels
/// do what cannot be taken back, the text a goal quotes. The reading,
/// deciding and clicking live in the app (`ComputerControl`).
public enum ScreenControl {
    /// Where `frame` sits in `window`: "top left", "top", "center"…
    public static func region(of frame: CGRect, in window: CGRect) -> String {
        guard window.width > 0, window.height > 0 else { return "" }
        let x = (frame.midX - window.minX) / window.width
        let y = (frame.midY - window.minY) / window.height
        let row = y < 1.0 / 3 ? "top" : y > 2.0 / 3 ? "bottom" : ""
        let column = x < 1.0 / 3 ? "left" : x > 2.0 / 3 ? "right" : ""
        switch (row, column) {
        case ("", ""): return "center"
        case ("", _): return column
        case (_, ""): return row
        default: return "\(row) \(column)"
        }
    }

    /// The items worth offering for `goal`, at most `limit` (a decision
    /// question takes 255 options): those the goal names first, then what
    /// can be pressed or filled, then texts; one per role and label (fields
    /// all kept: two empty fields are two places; with `keepsWordless`,
    /// when a picture of the window can tell them apart, every item without
    /// words too). Back in reading order.
    public static func candidates(_ items: [ScreenItem], goal: String, limit: Int = 120, keepsWordless: Bool = false) -> [ScreenItem] {
        let goalWords = words(goal)
        var seen = Set<String>()
        let unique = items.enumerated().filter { _, item in
            item.isField || (keepsWordless && item.isWordless)
                || seen.insert("\(item.role)|\(item.label.lowercased())|\(item.value ?? "")").inserted
        }
        let ranked = unique.map { index, item in
            (index: index, item: item, score: matches(goalWords, words(item.label + " " + (item.value ?? ""))))
        }
        let named = ranked.filter { $0.score > 0 }.sorted { $0.score > $1.score || $0.score == $1.score && $0.index < $1.index }
        let actionable = ranked.filter { $0.score == 0 && $0.item.role != "text" }
        let texts = ranked.filter { $0.score == 0 && $0.item.role == "text" }
        return (named + actionable + texts).prefix(limit).sorted { $0.index < $1.index }.map(\.item)
    }

    /// Words that mean the press cannot be taken back: sending, publishing,
    /// deleting, paying, buying. Asked first in the card.
    public static func isRisky(_ label: String) -> Bool {
        let risky = ["send", "envoy", "envoi", "delete", "supprim", "remove", "retir", "effac", "erase", "trash", "corbeille",
                     "pay", "paie", "paiement", "buy", "achet", "achat", "order", "command", "checkout", "purchase", "publish",
                     "publi", "post", "tweet", "submit", "soumet", "valider", "confirm", "transfer", "virement", "uninstall",
                     "desinstall", "reset", "reinitialis", "empty", "vider", "resilier", "unsubscribe", "desabonn", "replace", "remplac",
                     "overwrite", "ecras"]
        return words(label).contains { word in risky.contains { word.hasPrefix($0) } }
    }

    /// Items that send, share or publish what is open ("Envoyer au format
    /// PDF", "Partager › Mail", "Send", "AirDrop"): never picked for a goal
    /// that asks for none of that. A menu item counts by its whole path.
    public static func isOutbound(_ label: String) -> Bool {
        let outbound = ["send", "envoy", "envoi", "share", "partag", "airdrop", "publish", "publi", "post", "tweet", "upload"]
        return words(label).contains { word in outbound.contains { word.hasPrefix($0) } }
    }

    /// The goal's own words ask to send, share or publish ("envoie-le à
    /// Paul", "partage la partie", "publie-le"). A field named "email" is
    /// not asking: only verbs count.
    public static func asksToSend(_ goal: String) -> Bool {
        let verbs = ["send", "envoy", "envoi", "share", "partag", "airdrop", "publish", "publi", "post", "tweet", "upload",
                     "forward", "transfer"]
        return words(goal).contains { word in verbs.contains { word.hasPrefix($0) } }
    }

    /// The goal asks to submit what is filled ("valide", "inscris-moi",
    /// "soumets"), saving aside: "enregistre en PDF" never reaches
    /// "Envoyer au format PDF". No "sign": "signale ce mail" is no submit.
    static func asksToSubmitForm(_ goal: String) -> Bool {
        let verbs = ["submit", "soumet", "valid", "confirm", "inscri", "register", "command", "order", "pay", "paie"]
        return words(goal).contains { word in verbs.contains { word.hasPrefix($0) } }
    }

    /// Whether `item` may be acted on for `goal`: one that sends or shares
    /// only when the goal's words ask for it, whatever a model judged (Jev
    /// once ranked "Partie › Partager › Mail" first for "joue le prochain
    /// coup", at 60 %). A form's own "Envoyer" / "Send" button submits it
    /// for a goal that asks to; never Share or a menu item.
    public static func mayAct(on item: ScreenItem, goal: String) -> Bool {
        guard isOutbound(item.label) else { return true }
        if asksToSend(goal) { return true }
        let sends = words(item.label).contains { word in ["send", "envoy", "envoi"].contains { word.hasPrefix($0) } }
        return item.source != .menu && sends && asksToSubmitForm(goal)
    }

    /// The goal asks to send the form once filled ("…et envoie", "valide",
    /// "inscris-moi"): filling it alone never submits it.
    public static func asksToSubmit(_ goal: String) -> Bool {
        let verbs = ["envoi", "envoy", "send", "submit", "soumet", "valid", "enregistr", "save", "confirm", "inscri", "register",
                     "sign", "command", "order", "pay", "paie"]
        return words(goal).contains { word in verbs.contains { word.hasPrefix($0) } }
    }

    /// A save dialog's last button: what saves or exports where it is.
    public static func isFinalSave(_ label: String) -> Bool {
        let folded = label.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
        return ["enregistrer", "save", "exporter", "export"].contains(folded)
    }

    /// The place in a save dialog (its sidebar, or the "Where:" list once
    /// open) that the goal names, in either language: "dans mes documents"
    /// → Documents, "sur mon bureau" → Desktop or Bureau.
    public static func place(in goal: String, among items: [ScreenItem]) -> ScreenItem? {
        let said = Set(words(goal))
        // One folder, its names in English and French.
        let folders: [Set<String>] = [["desktop", "bureau"], ["documents"], ["downloads", "telechargements"], ["pictures", "images"],
                                      ["music", "musique"], ["movies", "videos", "films"], ["applications"], ["icloud"]]
        let wanted = folders.filter { !$0.isDisjoint(with: said) }
        return items.first { item in
            let label = words(item.label)
            guard label.count == 1, let name = label.first, item.source != .menu, !item.isField,
                  item.region.hasSuffix("left") || item.role == "menu item" else { return false }
            return said.contains(name) || wanted.contains { $0.contains(name) }
        }
    }

    /// Text the goal quotes, to type as is: `écris "Bonjour Paul"`,
    /// `cherche « vols Rome »`, `tape 'hello'`; in the goal's order.
    public static func quotes(in goal: String) -> [String] {
        let pairs: [Character: Character] = ["\"": "\"", "“": "”", "«": "»", "‘": "’", "'": "'"]
        var found: [String] = []
        var index = goal.startIndex
        while index < goal.endIndex {
            let character = goal[index]
            // An apostrophe inside a word ("l'objet") is not a quote.
            let inWord = character == "'" && index > goal.startIndex && goal[goal.index(before: index)].isLetter
            if let close = pairs[character], !inWord, let end = goal[goal.index(after: index)...].firstIndex(of: close) {
                let text = goal[goal.index(after: index)..<end].trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { found.append(text.replacingOccurrences(of: "\u{00A0}", with: " ")) }
                index = goal.index(after: end)
            } else {
                index = goal.index(after: index)
            }
        }
        return found
    }

    public static func quoted(in goal: String) -> String? {
        quotes(in: goal).first
    }

    /// The item a plan's line names by its exact words ("Click the button
    /// “pion blanc, e2”"): the only enabled item whose label is a text the
    /// line quotes, a field when typing (in "Type “Bonjour” in “To”", the
    /// field “To”, never the word Bonjour shown). Nil when none or several
    /// fit.
    public static func named(by line: String, among items: [ScreenItem], typing: Bool = false) -> ScreenItem? {
        for quote in quotes(in: line).map(folded) {
            let fitting = items.filter { $0.enabled && (!typing || $0.isField) && folded($0.label) == quote }
            if fitting.count == 1 { return fitting[0] }
        }
        return nil
    }

    /// The words a plan's line quotes for the item it clicks ("Click the
    /// button “b5”" → b5); none for a line that presses a key or types
    /// ("Press “⌘S”", "Type “Bonjour” in “To”"), whose quotes are not all
    /// items.
    public static func clickedWords(in line: String) -> [String] {
        let said = words(line)
        guard let verb = said.first else { return [] }
        let clicks = ["click", "cliqu", "double", "choose", "chois", "select", "pick", "tap"].contains { verb.hasPrefix($0) }
        let presses = ["press", "appui"].contains { verb.hasPrefix($0) } && said.contains { ["button", "bouton"].contains($0) }
        return clicks || presses ? quotes(in: line) : []
    }

    /// What a plan's line clicks by its words when no item read is it: its
    /// quote ("b5" for "Click the button “b5”" when Chess answered 15 of
    /// its 73 elements in time, the square not among them). Nil when an item
    /// read is it, or when the line names none by its words (a key,
    /// something drawn described by its look).
    public static func unread(by line: String, among items: [ScreenItem]) -> String? {
        let clicked = clickedWords(in: line)
        guard !clicked.isEmpty, !items.contains(where: { item in clicked.contains { reads(item, $0) } }) else { return nil }
        return clicked.first
    }

    /// Whether a step did what the plan's line says: it acted on the item
    /// the line clicks by its words (`acted`, empty for a key). A line that
    /// names none by its words takes any step: nothing tells it apart.
    public static func follows(_ line: String, acted: [ScreenItem]) -> Bool {
        let clicked = clickedWords(in: line)
        return clicked.isEmpty || acted.contains { item in clicked.contains { reads(item, $0) } }
    }

    /// Whether `item` reads what `quote` says: its words, or one part of
    /// them ("b5" for the square “fou blanc, b5”, "Mail" for “Partie ›
    /// Partager › Mail”), case, spaces and a closing ellipsis aside ("Save
    /// As" for “Save As…”).
    static func reads(_ item: ScreenItem, _ quote: String) -> Bool {
        func bare(_ text: String) -> String {
            var text = folded(text)
            while text.hasSuffix("…") { text.removeLast() }
            if text.hasSuffix("...") { text.removeLast(3) }
            return text.trimmingCharacters(in: .whitespaces)
        }
        let quote = bare(quote)
        guard !quote.isEmpty else { return false }
        let parts = item.label.components(separatedBy: " › ").flatMap { $0.components(separatedBy: ", ") }
        return bare(item.label) == quote || parts.contains { bare($0) == quote }
    }

    /// Lowercased, spaces made one, ’ as ': how a quote and a label compare.
    private static func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'").split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Words read on screen that Accessibility did not already give: kept
    /// when no element with a label covers their middle.
    public static func merge(elements: [ScreenItem], text: [ScreenItem]) -> [ScreenItem] {
        let covered = elements.compactMap { item -> CGRect? in item.label.isEmpty && item.value == nil ? nil : item.frame }
        return elements + text.filter { item in
            guard let frame = item.frame else { return true }
            let middle = CGPoint(x: frame.midX, y: frame.midY)
            return !covered.contains { $0.contains(middle) }
        }
    }

    // MARK: - A picture of the window

    /// Why one step shows Jev a picture of the window: what was read says
    /// too little to tell the items apart.
    public enum PictureNeed: String, Sendable, Equatable {
        /// Things to press or fill with no words (icon-only buttons): the
        /// picture shows what each is (`ScreenItem.isWordless`).
        case wordless
        /// Fewer than `fewThings` things to press or fill have words, and
        /// the screen shows words Accessibility did not give: drawn (a
        /// canvas, a web view, a game).
        case drawn
        /// Read in words, the model was unsure which item: under
        /// `unsureBelow` for the one to click or type into.
        case unsure
    }

    /// Fewer things with words than this, beside words read on screen: the
    /// window is drawn more than it is told.
    public static let fewThings = 6
    /// The likeliest item under this: the model is unsure.
    public static let unsureBelow = 0.5

    /// Before asking: whether what `candidates` holds says too little.
    public static func pictureNeed(_ candidates: [ScreenItem]) -> PictureNeed? {
        if candidates.contains(where: \.isWordless) { return .wordless }
        let told = candidates.filter { $0.source == .element && $0.role != "text" && !$0.isWordless }.count
        let drawnWords = candidates.contains { $0.source == .text }
        return told < fewThings && drawnWords ? .drawn : nil
    }

    /// The goal names an item by all of its words ("clique sur Snooze", and
    /// “Snooze” is read on screen): asked in words first, which finds it;
    /// the picture waits until the words are unsure (`isUnsure`). With the
    /// picture first, Jev once took Safari's Back button for a drawn
    /// “Snooze”. Menus do not count: they are always there.
    public static func goalNames(_ candidates: [ScreenItem], goal: String) -> Bool {
        let goalWords = Set(words(goal))
        return candidates.contains { item in
            guard item.source != .menu, !item.isWordless else { return false }
            let label = words(item.label)
            return !label.isEmpty && label.allSatisfy(goalWords.contains)
        }
    }

    /// After asking in words: a click or a typing whose likeliest item
    /// (`best`, nil when none fits) is under `unsureBelow`.
    public static func isUnsure(next: String, best: Double?) -> Bool {
        guard next == "click" || next == "type" else { return false }
        return (best ?? 0) < unsureBelow
    }

    /// Where an item without words sits among those beside it, left to
    /// right: "3rd of 6 in a row"; nil when it stands alone. Steps and
    /// questions name it so (its id changes from one look to the next).
    public static func rowPlace(of item: ScreenItem, among items: [ScreenItem]) -> String? {
        guard item.isWordless, let frame = item.frame else { return nil }
        let row = items.filter { other in
            guard other.isWordless, let rect = other.frame else { return false }
            return abs(rect.midY - frame.midY) <= max(frame.height, rect.height) / 2
        }.sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }
        guard row.count > 1, let index = row.firstIndex(where: { $0.id == item.id }) else { return nil }
        return "\(ordinal(index + 1)) of \(row.count) in a row"
    }

    public static func ordinal(_ number: Int) -> String {
        let suffix = (11...13).contains(number % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][number % 10] ?? "th"
        return "\(number)\(suffix)"
    }

    /// The target option for a place in the window's picture that no item
    /// names (a board, a map, a canvas): picked, Jev's Box finds where to
    /// click (`ComputerControl.pickSpot`, docs/click-what-you-see.md).
    public static let spotID = "spot"

    /// Never a picture of a window that shows a password field.
    public static func mayPicture(_ items: [ScreenItem]) -> Bool {
        !items.contains { $0.role == "password field" }
    }

    /// Lowercased, accents off, cut at anything not a letter or a digit;
    /// short and common words dropped.
    static func words(_ text: String) -> [String] {
        let stop: Set<String> = ["the", "and", "les", "des", "une", "pour", "avec", "dans", "sur", "puis", "then", "this", "that",
                                 "est", "qui", "que", "mon", "mes", "ton", "son", "ses", "aux", "par", "from", "into", "with", "your"]
        return text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }

    /// How many of the goal's words a label has: the same word, or one
    /// sharing its first five letters ("enregistre" and "Enregistrer").
    static func matches(_ goal: [String], _ label: [String]) -> Int {
        guard !goal.isEmpty, !label.isEmpty else { return 0 }
        return goal.filter { word in
            label.contains { other in
                word == other || zip(word, other).prefix { $0 == $1 }.count >= min(5, min(word.count, other.count))
                    && min(word.count, other.count) >= 4
            }
        }.count
    }
}

/// A plan the writer made for "do it here" (one click or key a line) and
/// how far it got. A line is done only by a step that did what it says
/// (`ScreenControl.follows`): in JB's Chess run of 2026-10-18 a click on
/// “pion blanc, b2” counted for "Click the button “b5”", every line looked
/// done and the run said done with no move played.
public struct PlanProgress: Equatable, Sendable {
    public private(set) var lines: [String]
    /// Lines done, from the first.
    public private(set) var done = 0

    public init(_ lines: [String] = []) {
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }

    /// The line to follow now; nil without a plan or once every line was
    /// done.
    public var next: String? { lines.indices.contains(done) ? lines[done] : nil }

    public var isFinished: Bool { !lines.isEmpty && done >= lines.count }

    /// One step taken while following it, on `acted` (empty for a key).
    /// `spot`: a click in the window's picture for the line, which only the
    /// next look can check; `grounded`: the item the decision model was
    /// sure the line meant, when none read its words. Whether it did the
    /// next line.
    @discardableResult
    public mutating func step(acted: [ScreenItem], spot: Bool = false, grounded: Bool = false) -> Bool {
        guard let line = next, spot || grounded || ScreenControl.follows(line, acted: acted) else { return false }
        done += 1
        return true
    }
}
