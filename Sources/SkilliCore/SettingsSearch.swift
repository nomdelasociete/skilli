import Foundation

/// Settings' search, the field atop the sidebar as in System Settings: each
/// pane by its title, then its one line; each setting by its name as the
/// pane shows it (`SettingsTable`); the sections and rows in `rows`; the
/// shortcuts (Keys) and the permissions (Privacy) by theirs. Case and
/// accents ignored; the words typed start words of a name, in any order.
/// Built once (again when the shortcuts change): a keystroke only compares
/// words, well under 5 ms over everything.
public enum SettingsSearch {
    /// Something Settings shows that the search finds, and where: the pane,
    /// and the anchor its row carries (`.id`), the `SettingsTable` key for a
    /// setting.
    public struct Item: Equatable, Sendable, Identifiable {
        public enum Kind: Int, Sendable, Comparable {
            /// `entry`: what skil.li does and what the user made, as the
            /// Catalog lists it (Search Emoji, a command, a snippet…).
            case pane, setting, section, permission, shortcut, entry

            public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        public let pane: String
        public let anchor: String
        /// As the pane shows it.
        public let title: String
        public let kind: Kind
        /// Its words, folded: those of the title, a word joined back
        /// ("skil.li" → "skilli"), "ai" beside "si" (the SI label reveals AI).
        let words: [String]
        /// The title's words with single spaces: "open skil li at login".
        let key: String
        /// The title's letters and digits only: "openskilliatlogin".
        let compact: String
        /// Words that find it less surely: a pane's one line.
        let detailWords: [String]
        /// Its place in the index: ties keep the panes' order.
        let order: Int

        public var id: String { anchor }

        init(pane: String, anchor: String, title: String, kind: Kind, detail: String?, order: Int) {
            self.pane = pane
            self.anchor = anchor
            self.title = title
            self.kind = kind
            self.order = order
            let parts = SettingsSearch.parts(title)
            words = SettingsSearch.words(parts)
            key = parts.flatMap { $0 }.joined(separator: " ")
            compact = parts.flatMap { $0 }.joined()
            detailWords = detail.map { SettingsSearch.words(SettingsSearch.parts($0)) } ?? []
        }
    }

    /// A pane as the sidebar names it.
    public struct PaneInfo: Sendable {
        public let id: String
        public let title: String
        /// Its one line, under its header.
        public let line: String

        public init(id: String, title: String, line: String) {
            self.id = id
            self.title = title
            self.line = line
        }
    }

    /// A row the search finds outside `SettingsTable`: a shortcut, a
    /// permission, a Catalog entry (`detail`: its other words).
    public struct Named: Sendable {
        public let pane: String
        public let anchor: String
        public let title: String
        public let detail: String?

        public init(pane: String, anchor: String, title: String, detail: String? = nil) {
            self.pane = pane
            self.anchor = anchor
            self.title = title
            self.detail = detail
        }
    }

    /// A Catalog entry's row in Settings → Catalog, and a linked app's
    /// command's in Apps.
    public static func entryAnchor(_ id: String) -> String { "entry.\(id)" }

    /// Every Catalog entry, in the Catalog pane (a linked app's command and
    /// a shortcut of the user's in Apps, where their settings are): its title, then its one line and the
    /// words people type for it ("emoji", "smiley").
    public static func entries(_ entries: [CatalogEntry]) -> [Named] {
        entries.map { entry in
            let pane = switch entry.run {
            case .appLink, .shortcut: "apps"
            default: "catalog"
            }
            return Named(pane: pane, anchor: entryAnchor(entry.id), title: entry.title,
                         detail: ([entry.oneLine, entry.prefix ?? ""] + entry.otherWords).joined(separator: " "))
        }
    }

    /// The panes that matched, best first, each with its rows that matched.
    public struct Group: Equatable, Sendable, Identifiable {
        public let pane: String
        /// The pane itself matched: its title, else its one line.
        public let paneMatched: Bool
        /// Its rows, best first; never the pane itself.
        public let hits: [Item]
        /// The pane matched better than its rows: it is the best of the
        /// group (↩ opens the pane), else its first row is.
        public let paneFirst: Bool

        public var id: String { pane }
    }

    /// A pane's anchor: its top.
    public static func paneAnchor(_ pane: String) -> String { "pane.\(pane)" }

    /// A shortcut's row, by its entry's id (Keys, and wherever it shows).
    public static func shortcutAnchor(_ id: String) -> String { "shortcut.\(id)" }

    /// A permission's row in Privacy.
    public static func permissionAnchor(_ id: String) -> String { "permission.\(id)" }

    /// Section headers no setting is named after, and rows people look
    /// for that are not settings. Each anchor is written in its pane
    /// (`.settingAnchor("section.superKey")`); `SettingsSearchTests` checks.
    public static let rows: [(pane: String, anchor: String, title: String)] = [
        ("keys", "section.superKey", "Hyper Key"),
        ("keys", "section.addShortcut", "Add Shortcut"),
        ("privacy", "section.automation", "Apps skil.li Sends Commands To"),
        ("privacy", "section.whatLeaves", "What Leaves This Mac"),
        ("backup", "section.backUpNow", "Back Up Now"),
        ("backup", "section.backups", "Backups"),
        ("clipboard", "section.clearHistory", "Clear History"),
        ("emoji", "section.wordsLearned", "Words Learned"),
        ("windows", "section.appsStoppedUsing", "Apps You Stopped Using"),
        ("ask", "section.whenItActs", "When It Acts"),
        ("commands", "section.builtIn", "Built In"),
        ("aiAccounts", "section.writing", "Writing"),
        ("aiAccounts", "section.choosing", "Choosing"),
        ("about", "section.health", "Health"),
        ("about", "section.copyDiagnostics", "Copy Diagnostics")
    ]

    /// Rows a pane shows only while another setting allows them (or while
    /// it has something to list): while hidden, the search takes the user
    /// there instead. "" is the pane's top.
    public static let shownWith: [String: String] = [
        "clipboardScreenshots": "clipboardHistory",
        "imageTagsFolderPath": "clipboardScreenshots",
        "snippetExpansionMode": "snippetExpansion",
        "autoQuitMinutes": "autoQuit",
        "autoQuitNever": "autoQuit",
        "agendaMenuBarCallsOnly": "agendaMenuBar",
        "agendaCountdown": "agendaMenuBar",
        "agendaNextDuringMeeting": "agendaMenuBar",
        "agendaHideAfter": "agendaCountdown",
        "agendaAlertWithoutCall": "agendaAlerts",
        "agendaHiddenCalendars": "",
        "githubAccount": "",
        "cleanShotTextLineBreaks": "",
        "scheduledAsks": "",
        "skilliesInMenuBar": "skillies",
        "section.backups": "backupFolder"
    ]

    /// Every anchor a pane carries for the search: each setting's key and
    /// each of `rows`.
    public static var anchors: Set<String> {
        Set(SettingsTable.entries.map(\.key)).union(rows.map(\.anchor))
    }

    /// What every search reads: the panes, the settings, `rows`, then the
    /// shortcuts and permissions the app has now.
    public struct Index: Sendable {
        public let items: [Item]
        private let paneOrder: [String: Int]

        public init(panes: [PaneInfo], shortcuts: [Named] = [], permissions: [Named] = [], entries: [Named] = []) {
            var items: [Item] = []
            func add(_ pane: String, _ anchor: String, _ title: String, _ kind: Item.Kind, detail: String? = nil) {
                items.append(Item(pane: pane, anchor: anchor, title: title, kind: kind, detail: detail, order: items.count))
            }
            for pane in panes {
                add(pane.id, SettingsSearch.paneAnchor(pane.id), pane.title, .pane, detail: pane.line)
            }
            for entry in SettingsTable.entries {
                add(entry.pane, entry.key, entry.name, .setting)
            }
            for row in SettingsSearch.rows {
                add(row.pane, row.anchor, row.title, .section)
            }
            for permission in permissions {
                add(permission.pane, permission.anchor, permission.title, .permission)
            }
            // A shortcut twice under one name (Add Shortcut on a command
            // that has one): found once.
            var seen = Set<String>()
            for shortcut in shortcuts where seen.insert("\(shortcut.pane)/\(SettingsTable.folded(shortcut.title))").inserted {
                add(shortcut.pane, shortcut.anchor, shortcut.title, .shortcut)
            }
            for entry in entries {
                add(entry.pane, entry.anchor, entry.title, .entry, detail: entry.detail)
            }
            self.items = items
            paneOrder = Dictionary(panes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        /// The panes that match `query`, best first (a pane's own title
        /// before a row of another pane named the same), each with its
        /// rows that match, best first. Empty for an empty query.
        public func search(_ query: String) -> [Group] {
            let parts = SettingsSearch.parts(query)
            let words = parts.flatMap { $0 }
            guard !words.isEmpty else { return [] }
            let query = Query(words: words, key: words.joined(separator: " "), compact: words.joined())

            var paneScores: [String: Int] = [:]
            var hits: [String: [(item: Item, score: Int)]] = [:]
            for item in items {
                guard let score = SettingsSearch.score(item, query) else { continue }
                if item.kind == .pane {
                    // Its own title wins over a row of another pane with the same name.
                    paneScores[item.pane] = score + 5
                } else {
                    hits[item.pane, default: []].append((item, score))
                }
            }
            let panes = Set(paneScores.keys).union(hits.keys)
            let groups = panes.map { pane -> (group: Group, score: Int) in
                let rows = (hits[pane] ?? []).sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    if lhs.item.kind != rhs.item.kind { return lhs.item.kind < rhs.item.kind }
                    return lhs.item.order < rhs.item.order
                }
                let own = paneScores[pane] ?? 0
                let best = max(own, rows.first?.score ?? 0)
                let group = Group(pane: pane, paneMatched: paneScores[pane] != nil, hits: rows.map(\.item),
                                  paneFirst: paneScores[pane] != nil && own >= (rows.first?.score ?? 0))
                return (group, best)
            }
            return groups.sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return (paneOrder[lhs.group.pane] ?? .max) < (paneOrder[rhs.group.pane] ?? .max)
            }.map(\.group)
        }
    }

    // MARK: - Matching

    struct Query {
        let words: [String]
        /// "open skil".
        let key: String
        /// "openskil".
        let compact: String
    }

    /// How well `item` matches, higher first; nil when it does not.
    static func score(_ item: Item, _ query: Query) -> Int? {
        if item.key == query.key { return 1000 }
        if item.key.hasPrefix(query.key) { return 900 }
        if query.words.allSatisfy({ word in item.words.contains { matches(word, $0) } }) {
            // "dark" in "Screens dark"; better when it starts the name.
            let first = item.words.first.map { matches(query.words[0], $0) } ?? false
            return first ? 730 : 700
        }
        if !item.detailWords.isEmpty,
           query.words.allSatisfy({ word in item.words.contains { matches(word, $0) } || item.detailWords.contains { matches(word, $0) } }) {
            return 400
        }
        // Inside a word: "board" in "Clipboard", "shot" in "Screenshots".
        if query.compact.count >= 3, item.compact.contains(query.compact) { return 200 }
        return nil
    }

    /// A word typed starts a word of the name; "backups" also finds "backup".
    static func matches(_ typed: String, _ word: String) -> Bool {
        if word.hasPrefix(typed) { return true }
        return typed.count > 3 && typed.hasSuffix("s") && word == typed.dropLast()
    }

    /// The text's words, folded, each split where it holds punctuation:
    /// "Open skil.li" → [["open"], ["skil", "li"]].
    static func parts(_ text: String) -> [[String]] {
        SettingsTable.folded(text).split(separator: " ").map { token in
            token.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }.filter { !$0.isEmpty }
    }

    /// Every word, a split word joined back, and "ai" beside "si".
    static func words(_ parts: [[String]]) -> [String] {
        var words: [String] = []
        for token in parts {
            words += token
            if token.count > 1 { words.append(token.joined()) }
            if token.contains("si") { words.append("ai") }
        }
        return words
    }
}
