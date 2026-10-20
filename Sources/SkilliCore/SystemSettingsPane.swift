import Foundation

/// One pane of macOS System Settings ("Displays"), read from the Settings
/// extension that draws it; `x-apple.systempreferences:<id>` opens it.
/// Equal by id.
public struct SystemSettingsPane: Hashable, Sendable {
    /// The extension's bundle id: "com.apple.Displays-Settings.extension".
    public let id: String
    /// In the Mac's language, as the Settings sidebar says it.
    public let name: String
    /// The pane in the user's other languages ("Moniteurs"), and the
    /// other name it can show under ("Energy" for "Battery").
    public let otherNames: [String]
    /// What the pane holds, as Settings' own search knows it ("Night
    /// Shift", "True Tone"), in each of the user's languages.
    public let sections: [String]
    /// The extension, for its icon.
    public let path: String
    /// The sidebar icon's type when the pane picks one by Mac
    /// ("com.apple.graphic-icon.battery").
    public let iconType: String?

    public init(id: String, name: String, otherNames: [String] = [], sections: [String] = [], path: String = "", iconType: String? = nil) {
        self.id = id
        self.name = name
        self.otherNames = otherNames
        self.sections = sections
        self.path = path
        self.iconType = iconType
    }

    public var url: URL? { URL(string: "x-apple.systempreferences:\(id)") }

    /// What follows "settings" or "réglages" in a launcher query: the pane
    /// asked for ("réglages bluetooth" → "bluetooth"); nil when the query
    /// does not start so. Panes are matched on it too, so their names need
    /// no "settings …" forms that would answer "sett" before skil.li's
    /// own Settings.
    public static func paneQuery(_ text: String) -> String? {
        let folded = fold(text)
        for prefix in prefixes where folded.hasPrefix(prefix) {
            let rest = folded.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// The pane a query asks for by name with a settings word before or
    /// after it ("réglages bluetooth", "bluetooth settings" → "bluetooth");
    /// nil without one. A pane named so is the one asked for: it comes
    /// before an offer for the same word (Allow Bluetooth,
    /// `LauncherRank.offerPlace`). Never used to look for panes ("system
    /// settings" must not list those that hold "system").
    public static func asked(_ text: String) -> String? {
        let folded = fold(text)
        // "system settings" alone is the app, not a pane named "system".
        guard !settingsWords.contains(folded) else { return nil }
        if let pane = paneQuery(text) { return pane }
        for suffix in suffixes where folded.hasSuffix(suffix) {
            let rest = folded.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// Longest first: "system settings" before "settings".
    private static let settingsWords = ["system settings", "settings", "reglages systeme", "reglages", "preferences systeme", "preferences"]
    private static let prefixes = settingsWords.map { $0 + " " }
    private static let suffixes = settingsWords.map { " " + $0 }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    public static func == (lhs: SystemSettingsPane, rhs: SystemSettingsPane) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Section titles of a `.searchTerms` file
    /// (`{group: {localizableStrings: [{title, index}]}}`), groups in key
    /// order, each title once.
    public static func sectionTitles(_ searchTerms: [String: Any]) -> [String] {
        var seen = Set<String>()
        var titles: [String] = []
        for key in searchTerms.keys.sorted() {
            guard let group = searchTerms[key] as? [String: Any],
                  let strings = group["localizableStrings"] as? [[String: Any]] else { continue }
            for entry in strings {
                guard let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty, seen.insert(title.lowercased()).inserted else { continue }
                titles.append(title)
            }
        }
        return titles
    }

    /// A name a person reads, not an extension's code name
    /// ("HeadphoneSettingsExtension", "DisplaysExt", "PowerPreferences",
    /// "CoverageSettingPane_macOS").
    public static func isReadable(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasSuffix("Ext") else { return false }
        return !["_", "Extension", "Settings", "Setting", "Preferences", "Pane"].contains { trimmed.contains($0) }
    }

    /// The representation macOS shows on this Mac: the first whose
    /// predicate ("powersource.battery == YES") holds. A fact not in
    /// `facts` counts as yes.
    public static func representation(_ representations: [[String: Any]], facts: [String: Bool]) -> [String: Any]? {
        representations.first { holds($0["predicate"] as? String, facts: facts) }
    }

    /// "device.touchID != YES" with `facts`; no predicate holds.
    public static func holds(_ predicate: String?, facts: [String: Bool]) -> Bool {
        guard let predicate = predicate?.trimmingCharacters(in: .whitespaces), !predicate.isEmpty else { return true }
        for (symbol, equal) in [("==", true), ("!=", false)] {
            let parts = predicate.components(separatedBy: " \(symbol) ")
            guard parts.count == 2 else { continue }
            let fact = facts[parts[0].trimmingCharacters(in: .whitespaces)] ?? true
            let value = parts[1].trimmingCharacters(in: .whitespaces).uppercased() == "YES"
            return (fact == value) == equal
        }
        return true
    }
}
