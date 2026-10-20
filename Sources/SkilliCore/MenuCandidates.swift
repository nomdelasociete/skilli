import Foundation

/// Which menu items of an app may be sent to a decision model, in chunks a
/// Choice question accepts (255 options, one kept for "none").
public enum MenuCandidates {
    /// Menus that list the user's documents, pages or windows by name.
    static let privateMenus: Set<String> = [
        "window", "fenêtre", "history", "historique", "bookmarks", "signets", "favoris", "favorites", "services"
    ]

    /// Never names the user's files or pages: no Window, History or
    /// Bookmarks menu, no "Open Recent" list, no Services.
    public static func isShareable(_ path: [String]) -> Bool {
        guard let top = path.first?.lowercased(), !privateMenus.contains(top) else { return false }
        return !path.dropFirst().dropLast().contains { component in
            let lower = component.lowercased()
            return lower.contains("recent") || lower.contains("récent") || privateMenus.contains(lower)
        }
    }

    public static let chunkSize = 254

    public static func chunks<T>(_ items: [T], size: Int = chunkSize) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    /// Choosing it cannot be taken back, or ends what is open: it sends,
    /// shares, deletes, empties, pays or overwrites (`ScreenControl.isRisky`
    /// and `isOutbound`, on the item's whole path), or quits, closes,
    /// clears, signs or logs out, restarts, shuts down, discards or
    /// reverts. Ask chooses such an item only after ↩; any other one it is
    /// sure of at once (what it does shows, or is undone in the app).
    public static func isDestructive(_ path: [String]) -> Bool {
        let label = path.joined(separator: " ")
        if ScreenControl.isRisky(label) || ScreenControl.isOutbound(label) { return true }
        let words = ScreenControl.words(label)
        let ending = ["quit", "close", "ferm", "clear", "deconnect", "deconnex", "logout", "logoff", "signout", "restart", "redemarr",
                      "shut", "eteindr", "discard", "revert", "abandon", "force"]
        if words.contains(where: { word in ending.contains { word.hasPrefix($0) } }) { return true }
        return zip(words, words.dropFirst()).contains { ["sign", "log"].contains($0.0) && ["out", "off"].contains($0.1) }
    }

    /// "File > Export as PDF…" → "File › Export as PDF…".
    public static func display(_ path: [String]) -> String {
        path.joined(separator: " › ")
    }
}
