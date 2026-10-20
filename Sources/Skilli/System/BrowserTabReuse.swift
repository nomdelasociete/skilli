import AppKit
import SkilliCore

/// Settings → Catalog → Quicklinks → Reuse an open tab: a quicklink loads
/// in a tab the default browser already has on that site
/// (`Quicklink.tabToReuse`), instead of a new one. Only browsers whose
/// scripting dictionary lists tabs with their addresses and lets one be
/// chosen and loaded: Safari and Chrome's family (Chrome, Brave, Edge,
/// Chromium, Vivaldi). Arc, Firefox, Zen and Opera say nothing reliable
/// about that: a new tab, as always. Only with the browser's Automation
/// permission (macOS asks once, the first time); anything else, a script
/// that fails or no tab on the site: opened normally.
@MainActor
enum BrowserTabReuse {
    private enum Family {
        case safari, chrome
    }

    private static let browsers: [String: Family] = [
        "com.apple.Safari": .safari, "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chrome, "com.google.Chrome.canary": .chrome, "com.brave.Browser": .chrome,
        "com.microsoft.edgemac": .chrome, "org.chromium.Chromium": .chrome, "com.vivaldi.Vivaldi": .chrome
    ]

    /// The browser that opens web pages, when skil.li can reuse its tabs.
    static func defaultBrowser() -> (bundleID: String, name: String)? {
        guard let browser = anyDefaultBrowser(), browsers[browser.bundleID] != nil else { return nil }
        return browser
    }

    /// The browser that opens web pages, whichever it is ("Arc").
    static func anyDefaultBrowser() -> (bundleID: String, name: String)? {
        guard let probe = URL(string: "https://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let bundleID = Bundle(url: app)?.bundleIdentifier else { return nil }
        return (bundleID, FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""))
    }

    /// Loads `address` in a tab of the default browser on the same site and
    /// brings it forward. False: nothing was done, open it normally.
    static func open(_ address: URL) async -> Bool {
        guard let (bundleID, _) = defaultBrowser(), let family = browsers[bundleID],
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return false }
        // Asked once (macOS's prompt), off the main thread: it waits for
        // the user's answer.
        let state = await Task.detached(priority: .userInitiated) { () -> AutomationAccess.State in
            let state = AutomationAccess.state(of: bundleID)
            return state == .notAsked ? AutomationAccess.ask(bundleID) : state
        }.value
        guard state == .granted else {
            Log.trace("Reuse an open tab: \(bundleID) not allowed (\(state))")
            return false
        }
        guard let tab = Quicklink.tabToReuse(for: address, among: tabs(in: bundleID, family)) else { return false }
        let loaded = run(load(address, in: tab, bundleID, family)) != nil
        Log.trace("Reuse an open tab: \(loaded ? "loaded in" : "could not load in") window \(tab.window) tab \(tab.index) of \(bundleID)")
        return loaded
    }

    /// Every tab of every window, front window first: "window id, tab
    /// index, 1 when in front, address" per line.
    private static func tabs(in bundleID: String, _ family: Family) -> [Quicklink.OpenTab] {
        let front = family == .safari ? "index of current tab of w" : "active tab index of w"
        let skip = family == .chrome ? "if mode of w is \"incognito\" then error number -128\n" : ""
        let source = """
        set sep to character id 9
        set out to ""
        with timeout of 3 seconds
            tell application id "\(bundleID)"
                repeat with w in windows
                    try
                        \(skip)set wid to id of w
                        set cur to \(front)
                        set addresses to URL of every tab of w
                        repeat with t from 1 to count of addresses
                            set u to item t of addresses
                            if u is missing value then set u to ""
                            set out to out & wid & sep & t & sep & (t = cur) & sep & u & linefeed
                        end repeat
                    end try
                end repeat
            end tell
        end timeout
        return out
        """
        return (run(source) ?? "").split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, let window = Int(parts[0]), let index = Int(parts[1]) else { return nil }
            return Quicklink.OpenTab(window: window, index: index, url: parts[3], active: parts[2] == "true")
        }
    }

    /// That tab in front of its window, the address loaded there, the
    /// window in front, the browser forward.
    private static func load(_ address: URL, in tab: Quicklink.OpenTab, _ bundleID: String, _ family: Family) -> String {
        let quoted = address.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let select = family == .safari ? "set current tab of w to tab \(tab.index) of w" : "set active tab index of w to \(tab.index)"
        return """
        with timeout of 3 seconds
            tell application id "\(bundleID)"
                set w to window id \(tab.window)
                \(select)
                set URL of tab \(tab.index) of w to "\(quoted)"
                set index of w to 1
                activate
            end tell
        end timeout
        return "ok"
        """
    }

    /// The script's answer as text; nil when it failed.
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.trace("Reuse an open tab: script failed (\(error[NSAppleScript.errorNumber] as? Int ?? 0))")
            return nil
        }
        return result?.stringValue ?? ""
    }
}
