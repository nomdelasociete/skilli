import Foundation

/// "kill creative cloud", "quitte de force Slack" said to Ask (the name read
/// by the decision model, `AskValues.target`): the processes that may
/// belong to it, for the decision model to sort.
public enum QuitRequest {
    /// The groups that may be `target`: a word of it in the process's name,
    /// app or path; and, since helpers often bear another name
    /// (CCXProcess), every group under the same vendor's folder as one of
    /// those ("Adobe"). Busiest first, `limit` at most.
    public static func candidates(_ groups: [ProcessListing.Group], target: String, limit: Int = 30) -> [ProcessListing.Group] {
        let words = fold(target).split(separator: " ").map(String.init).filter { $0.count >= 3 }
        guard !words.isEmpty else { return [] }
        func text(_ group: ProcessListing.Group) -> String {
            fold(([group.name, group.appPath ?? ""] + group.entries.map(\.path)).joined(separator: " "))
        }
        let named = groups.filter { group in words.contains { text(group).contains($0) } }
        let vendors = Set(named.compactMap(vendor))
        let related = groups.filter { group in !named.contains(group) && vendor(group).map(vendors.contains) == true }
        return Array((named + related).prefix(limit))
    }

    /// The process says it by name: every word of the target is a whole
    /// word of its name or its app's ("kill chrome": Google Chrome Helper;
    /// "kill code": Visual Studio Code, never Xcode). Sure without asking.
    public static func namesIt(_ group: ProcessListing.Group, target: String) -> Bool {
        let wanted = fold(target).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !wanted.isEmpty else { return false }
        let app = group.appPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? ""
        let words = Set(fold(group.name + " " + app).split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return wanted.allSatisfy(words.contains)
    }

    /// "CCXProcess, in Adobe Creative Cloud Experience": its name and app,
    /// never a path under the user's home.
    public static func description(_ group: ProcessListing.Group) -> String {
        let app = group.appPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        return app.map { $0 == group.name ? group.name : "\(group.name), in \($0)" } ?? group.name
    }

    /// The first word of the vendor folder the process lives under:
    /// /Applications/Adobe Creative Cloud/… or /Library/Application
    /// Support/Adobe/… → "adobe".
    static func vendor(_ group: ProcessListing.Group) -> String? {
        let paths = [group.appPath ?? ""] + group.entries.map(\.path)
        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            for (index, part) in parts.enumerated() {
                let next = index + 1 < parts.count ? parts[index + 1] : ""
                let folder: String? = switch part {
                case "Applications": next.hasSuffix(".app") ? nil : next
                case "Application Support": next
                default: nil
                }
                // Folders of everyone's: no vendor.
                if let folder, let word = fold(folder).split(separator: " ").first, word.count >= 3,
                   !["utilities", "system", "library", "applications"].contains(String(word)) { return String(word) }
            }
        }
        return nil
    }

    private static func fold(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }
}
