import Foundation

/// What, typed first, turns the launcher into a mode: "kill " into Kill
/// Process, ":" into the emoji picker. One list read by the launcher's
/// parsers and by the Catalog, which shows the first of each as its keycap:
/// it can never show a prefix that does not work.
public enum LauncherPrefix {
    /// Each mode's prefixes, the one the Catalog shows first. The launcher
    /// tries them in this order.
    public static let modes: [(command: LauncherCommand.ID, prefixes: [String])] = [
        (.killProcess, ["kill ", "quit ", "tuer ", "port "]),
        (.homebrew, ["brew "]),
        (.searchHistory, ["hist ", "history ", "historique "]),
        (.searchFiles, ["f ", "file ", "files ", "fichier ", "fichiers "]),
        (.searchContacts, ["@", "contact ", "contacts "]),
        (.reminders, ["todo ", "rappels ", "reminders ", "taches ", "tâches "]),
        // "gh " stays GitHub's search quicklink.
        (.github, ["pr ", "prs "]),
        (.agenda, ["cal ", "agenda "]),
        (.searchTabs, ["tab ", "tabs ", "onglet ", "onglets "]),
        (.emoji, [":", "emoji "]),
        (.searchGIFs, ["gif ", "gifs "]),
        // Not "menu ": "menu bar" finds apps named so.
        (.searchMenus, ["m ", "menus "]),
        // Not "clip ": "clip studio" is an app.
        (.clipboardHistory, ["cb ", "clipboard ", "presse-papier "]),
        (.searchSnippets, ["snip ", "snippet ", "snippets "]),
        (.catalog, ["?"])
    ]

    /// The prefixes that open `command`'s mode; empty when it has none.
    public static func prefixes(for command: LauncherCommand.ID) -> [String] {
        modes.first { $0.command == command }?.prefixes ?? []
    }

    /// The one to show and teach: the shortest to type.
    public static func shown(for command: LauncherCommand.ID) -> String? {
        prefixes(for: command).first
    }

    /// What follows the first of `prefixes` that `text` starts with, case
    /// aside: "@jean" → "jean". Nil when it starts with none.
    public static func rest(of text: String, after prefixes: [String]) -> String? {
        rest(of: text, lowercased: text.lowercased(), after: prefixes)
    }

    /// The mode `text` asks for and what follows its prefix. On every key:
    /// the text is lowercased once.
    public static func mode(of text: String) -> (command: LauncherCommand.ID, rest: String)? {
        let lower = text.lowercased()
        for (command, prefixes) in modes {
            if let rest = rest(of: text, lowercased: lower, after: prefixes) { return (command, rest) }
        }
        return nil
    }

    private static func rest(of text: String, lowercased lower: String, after prefixes: [String]) -> String? {
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        return String(text.dropFirst(prefix.count))
    }
}
