import Foundation

/// One item of a list as get_settings reports it: what may be read of it
/// (a snippet's name and keyword, a place's name, a field's label), and
/// whether it holds the user's own content (a text, an address, a value),
/// never that content.
public struct SettingItem: Equatable, Sendable {
    public var fields: [String: String]
    /// What its content is called ("text", "address", "value"); nil when
    /// it has none.
    public var contentName: String?
    /// The content itself: reported only as "set" or "not set".
    public var content: String

    public init(_ fields: [String: String], content contentName: String? = nil, _ content: String = "") {
        self.fields = fields
        self.contentName = contentName
        self.content = content
    }
}

/// What one setting holds now, as the app reads it for get_settings.
public struct SettingReading: Sendable {
    public var value: SettingValue
    /// The choices it takes (a choice this Mac has: the app's).
    public var options: [SettingOption]
    /// A secret: whether one is set; its value is never read.
    public var isSet: Bool
    /// A list's items, with what may be read of each; nil: the value's own
    /// words.
    public var items: [SettingItem]?

    public init(value: SettingValue, options: [SettingOption] = [], isSet: Bool = false, items: [SettingItem]? = nil) {
        self.value = value
        self.options = options
        self.isSet = isSet
        self.items = items
    }
}

/// get_settings' JSON: every setting with its value, except the user's own
/// content (`SettingEntry.personal`), which is reported only as set or not
/// set (About You "set (12 words)", a field "SIRET: set", a snippet's name
/// and keyword with "text": "set"), and secrets, only set or not set.
/// get_settings is a read, with no card: what it hands an agent stays
/// settings, never what the user wrote.
public enum SettingsReport {
    public static let how = "Change a setting with set_setting (pane, setting by its name or key, value); a list with change add or remove and one item; quicklinks, snippets, aliases and shortcuts with the tools each names. Every change asks the user in skil.li's card, every time. Settings with settable false are the user's alone: say where they are. The user's own content (About You, Your Details' values and people, snippets' text, addresses) is only said to be set or not set: ask the user when you need it."

    /// "set (12 words)" or "not set".
    public static func presence(of text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return words == 0 ? "not set" : "set (\(words) word\(words == 1 ? "" : "s"))"
    }

    private static func json(_ item: SettingItem) -> [String: String] {
        var fields = item.fields
        if let name = item.contentName {
            fields[name] = item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "not set" : "set"
        }
        return fields
    }

    /// One setting as get_settings says it.
    public static func describe(_ entry: SettingEntry, _ reading: SettingReading) -> [String: Any] {
        var item: [String: Any] = ["name": entry.name, "key": entry.key, "type": SettingsTable.type(of: entry)]
        if let note = entry.note { item["note"] = note }
        switch entry.access {
        case .tools(let tools): item["tools"] = tools
        case .paneOnly(let why):
            item["settable"] = false
            item["why"] = why
        }
        if entry.secret {
            item["value"] = reading.isSet ? "set" : "not set"
            return item
        }
        if entry.personal {
            item["content"] = "The user's own: only whether it is set."
            if let items = reading.items {
                item["value"] = items.map(json)
            } else {
                switch reading.value {
                case .bool(let on): item["value"] = on
                case .text(let text): item["value"] = presence(of: text)
                case .list(let list): item["value"] = list.isEmpty ? "not set" : "set (\(list.count))"
                }
            }
            if case .list(let what, let adds) = entry.kind {
                item["item"] = what
                if entry.usesSetSetting { item["change"] = adds ? ["add", "remove"] : ["remove"] }
            }
            return item
        }
        let value = reading.value
        let options = reading.options
        switch value {
        case .bool(let on): item["value"] = on
        case .text(let text):
            item["value"] = text
            switch entry.kind {
            case .choice, .choiceOnThisMac, .choiceOrNumber, .folder, .reset:
                item["shown"] = SettingsTable.shown(value, for: entry, options: options)
            default: break
            }
        case .list(let list): item["value"] = reading.items.map { $0.map(json) } ?? list
        }
        switch entry.kind {
        case .choice, .choiceOnThisMac:
            if entry.isSettable { item["allowed"] = options.map { ["value": $0.value, "title": $0.title] } }
        case .choiceOrNumber(_, let range, let unit):
            item["allowed"] = options.map { ["value": $0.value, "title": $0.title] }
            item["or"] = "a number of \(unit) from \(range.lowerBound) to \(range.upperBound)"
        case .folder(let empty):
            item["allowed"] = "a folder that exists on this Mac" + (empty.map { "; “default” for \($0)" } ?? "")
        case .reset:
            item["allowed"] = "default"
        case .list(let what, let adds):
            item["item"] = what
            if entry.usesSetSetting { item["change"] = adds ? ["add", "remove"] : ["remove"] }
        case .toggle, .text:
            break
        }
        return item
    }

    /// The whole answer: panes in order, each with its settings.
    public static func json(_ panes: [(title: String, settings: [[String: Any]])]) throws -> String {
        let root: [String: Any] = ["how": how, "panes": panes.map { ["pane": $0.title, "settings": $0.settings] }]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
