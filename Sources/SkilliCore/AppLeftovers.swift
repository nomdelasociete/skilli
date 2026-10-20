import Foundation

/// What an app leaves in the user's Library once removed, as Raycast's
/// Uninstall finds it: its folders and files named after its bundle id or
/// its name. Only under ~/Library: never another app's, never the system's.
public enum AppLeftovers {
    /// Paths under ~/Library to look at for `bundleID` and `name`.
    public static func paths(bundleID: String, name: String) -> [String] {
        var paths = [
            "Application Support/\(bundleID)", "Caches/\(bundleID)", "Preferences/\(bundleID).plist",
            "Containers/\(bundleID)", "Saved Application State/\(bundleID).savedState", "Logs/\(bundleID)",
            "HTTPStorages/\(bundleID)", "HTTPStorages/\(bundleID).binarycookies", "WebKit/\(bundleID)",
            "Cookies/\(bundleID).binarycookies", "Application Scripts/\(bundleID)", "LaunchAgents/\(bundleID).plist"
        ]
        // Folders named after the app, when its name is its own ("Slack",
        // not "Notes" or "Mail": a word every app could use).
        if isDistinctive(name) {
            paths += ["Application Support/\(name)", "Caches/\(name)", "Logs/\(name)"]
        }
        return paths
    }

    /// Folders where the app's items carry its id among other words:
    /// "Group Containers/T23Q.com.tinyspeck.slackmacgap",
    /// "Preferences/ByHost/com.tinyspeck.slackmacgap.6F1….plist".
    public static let listedFolders = ["Group Containers", "Preferences/ByHost", "LaunchAgents"]

    /// An entry of a listed folder belongs to the app: its id is one of
    /// the entry's dot-separated runs ("T23Q.com.tinyspeck.slackmacgap").
    public static func belongs(_ entry: String, bundleID: String) -> Bool {
        guard bundleID.split(separator: ".").count >= 2 else { return false }
        return entry == bundleID || entry.hasPrefix(bundleID + ".") || entry.contains("." + bundleID + ".")
            || entry.hasSuffix("." + bundleID)
    }

    /// An app whose name is no common word: its own folders may be named so.
    public static func isDistinctive(_ name: String) -> Bool {
        let common: Set<String> = ["notes", "mail", "music", "photos", "calendar", "reminders", "preview", "messages", "maps", "news",
                                   "books", "home", "files", "chat", "code", "terminal", "browser", "editor", "player", "camera", "google",
                                   "microsoft", "adobe", "apple"]
        return name.count >= 3 && !common.contains(name.lowercased())
    }

    /// Apps that are macOS's own, or skil.li: never uninstalled.
    public static func isProtected(_ path: String, bundleID: String?) -> Bool {
        path.hasPrefix("/System/") || bundleID?.hasPrefix("com.apple.") == true || bundleID == "com.nomdelasociete.Skilli"
    }
}
