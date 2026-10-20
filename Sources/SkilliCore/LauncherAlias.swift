import Foundation

/// A short word the user gives a launcher item ("e" for Emoji, "cl" for the
/// clipboard history): typed then a space, it opens that item's mode or
/// its first argument; typed alone, it puts the item first.
public struct LauncherAlias: Codable, Equatable, Sendable {
    /// The item's stable identity (`LauncherItem.learningID`).
    public var id: String
    public var alias: String
    /// The item's name when the alias was set, for Settings.
    public var title: String

    public init(id: String, alias: String, title: String) {
        self.id = id
        self.alias = alias
        self.title = title
    }
}

public enum LauncherAliases {
    /// Lowercased, without spaces around.
    public static func normalized(_ alias: String) -> String {
        alias.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// One to twelve characters, no space.
    public static func isValid(_ alias: String) -> Bool {
        let alias = normalized(alias)
        return (1...12).contains(alias.count) && !alias.contains { $0.isWhitespace }
    }

    /// "e smile" → the alias "e" and "smile"; "e " → "e" and nothing. Only
    /// once the space is typed: "e" alone could still become "emoji".
    public static func split(_ text: String, among aliases: [LauncherAlias]) -> (alias: LauncherAlias, rest: String)? {
        guard let space = text.firstIndex(of: " ") else { return nil }
        let typed = normalized(String(text[..<space]))
        guard let alias = aliases.first(where: { $0.alias == typed }) else { return nil }
        return (alias, String(text[text.index(after: space)...]))
    }

    /// The alias typed exactly, nothing else: "e".
    public static func exact(_ text: String, among aliases: [LauncherAlias]) -> LauncherAlias? {
        let typed = normalized(text)
        return typed.isEmpty ? nil : aliases.first { $0.alias == typed }
    }

    /// `alias` for the item `id`; an empty one removes it. An alias belongs
    /// to one item: whoever had it loses it.
    public static func setting(_ alias: String, id: String, title: String, in list: [LauncherAlias]) -> [LauncherAlias] {
        let alias = normalized(alias)
        var kept = list.filter { $0.id != id && $0.alias != alias }
        if !alias.isEmpty { kept.append(LauncherAlias(id: id, alias: alias, title: title)) }
        return kept.sorted { $0.alias < $1.alias }
    }
}
