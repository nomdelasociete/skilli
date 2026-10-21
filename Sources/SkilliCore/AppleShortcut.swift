import Foundation

/// A shortcut the user made in Apple's Shortcuts app (docs/apps.md, Next
/// apps 1): each one a launcher row, a Catalog entry, a key, a link, an Ask
/// candidate and an agent action. Through them skil.li reaches every app's
/// App Intents without knowing them. Shortcuts runs it
/// (`/usr/bin/shortcuts run`), by its identifier: a shortcut renamed keeps
/// its keys, alias and what the launcher learned. Equal by identifier.
public struct AppleShortcut: Hashable, Sendable {
    /// Shortcuts' own identifier (`shortcuts list --show-identifiers`).
    public let id: String
    /// Its name as last read; empty when it was not read yet (a key saved
    /// before, decoded at launch).
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static func == (lhs: AppleShortcut, rhs: AppleShortcut) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// The Shortcuts app.
    public static let bundleID = "com.apple.shortcuts"
    /// Apple's command-line tool (`shortcuts help run`).
    public static let tool = "/usr/bin/shortcuts"
    /// What `tool` is given to list them, each with its identifier.
    public static let listArguments = ["list", "--show-identifiers"]
    /// Words that lead to every shortcut, in English and French.
    public static let keywords = ["shortcut", "shortcuts", "raccourci", "raccourcis"]

    /// What `tool` is given to run it: its identifier, so a name that looks
    /// like another's runs the right one. Its input comes on the standard
    /// input, which Shortcuts reads as text.
    public var runArguments: [String] {
        ["run", id]
    }

    /// `shortcuts list --show-identifiers`: "Name (identifier)" on each
    /// line, in Shortcuts' order. A line without an identifier is left out.
    public static func list(_ output: String) -> [AppleShortcut] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            // The last parentheses: a name may hold some of its own.
            guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else { return nil }
            let id = String(line[open.upperBound..<line.index(before: line.endIndex)])
            let name = String(line[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard UUID(uuidString: id) != nil, !name.isEmpty else { return nil }
            return AppleShortcut(id: id, name: name)
        }
    }

    /// Opens it in Shortcuts' editor: `shortcuts://open-shortcut?name=…`
    /// (Shortcuts User Guide, "Open and create a shortcut using a URL
    /// scheme"), its name encoded whole (`&`, `+` and `#` too).
    public var editURL: URL? {
        guard !name.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "shortcuts://open-shortcut?name=\(encoded)")
    }

    /// What a run gave back, as the card shows it: its text, trimmed; nil
    /// when it gave nothing or something that is not text (an image, a
    /// file), which the card does not show.
    public static func shownOutput(_ data: Data) -> String? {
        guard !data.isEmpty, !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Why a run failed, from what `tool` wrote on its errors: the last
    /// line that says something, without its "Error: ".
    public static func failure(_ errors: String) -> String? {
        guard let line = errors.split(whereSeparator: \.isNewline).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("error:") { text = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        return text.isEmpty ? nil : text
    }
}
