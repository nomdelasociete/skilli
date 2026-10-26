import AppKit
import SkilliCore

/// The meeting's tab brought forward in its window as a recording starts
/// (docs/meeting-recorder.md, "A browser tab"): selected (Chrome's family
/// `set active tab index`, Safari's `current tab`), never reloaded
/// (`BrowserTabReuse` loads its address, which would leave the call), the
/// browser left where it is, so the user's app keeps the keyboard. macOS
/// records a window, not a tab: the window holding the tab is the one
/// recorded, found in the window list by its place on screen.
@MainActor
enum MeetingTabSelect {
    enum Plan: Equatable {
        /// The tab (its window in the browser's own numbering) and the
        /// window on screen holding it.
        case tab(Quicklink.OpenTab, window: CGWindowID?)
        /// It cannot: the card's line, and whether ⌘↩ opens Automation.
        case cannot(String, automation: Bool)
    }

    /// Whether the app opens web pages (a browser, scripted or not).
    static func isBrowser(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty, let probe = URL(string: "https://example.com") else { return false }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).contains { Bundle(url: $0)?.bundleIdentifier == bundleID }
    }

    /// Whether `app`'s tab on `link`'s meeting can be brought forward, and
    /// which window holds it. macOS's question for Automation, never asked,
    /// comes now (off the main thread: it waits for the answer).
    static func plan(for link: URL, in app: MicrophoneApp) async -> Plan {
        guard let family = BrowserTabReuse.browsers[app.bundleID] else {
            return .cannot("Bring the meeting's tab forward in \(app.name): its window is recorded as it is.", automation: false)
        }
        let bundleID = app.bundleID
        let state = await Task.detached(priority: .userInitiated) { () -> AutomationAccess.State in
            let state = AutomationAccess.state(of: bundleID)
            return state == .notAsked ? AutomationAccess.ask(bundleID) : state
        }.value
        switch state {
        case .granted:
            break
        case .denied:
            return .cannot("\(app.name) said no to skil.li · ⌘↩ opens Automation. Bring the meeting's tab forward: its window is recorded as it is.",
                           automation: true)
        case .notAsked, .unknown:
            return .cannot(noTab(app), automation: false)
        }
        guard let listed = tabs(in: bundleID, family) else {
            return .cannot("\(app.name) did not answer: bring the meeting's tab forward, its window is recorded as it is.", automation: false)
        }
        guard let tab = MeetingTab.find(link, among: listed.map(\.tab)) else { return .cannot(noTab(app), automation: false) }
        let found = listed.first { $0.tab == tab }
        return .tab(tab, window: found.flatMap { window(of: app.pid, at: $0.bounds, showing: $0.front) })
    }

    private static func noTab(_ app: MicrophoneApp) -> String {
        "No tab of \(app.name) is on the meeting's address: bring it forward, its window is recorded as it is."
    }

    /// The tab in front of its window, nothing else: not reloaded, the
    /// browser not brought forward. Whether it was.
    static func select(_ tab: Quicklink.OpenTab, in bundleID: String) -> Bool {
        guard let family = BrowserTabReuse.browsers[bundleID] else { return false }
        let select = family == .safari ? "set current tab of window id \(tab.window) to tab \(tab.index) of window id \(tab.window)"
            : "set active tab index of window id \(tab.window) to \(tab.index)"
        // A browser slow to answer is not waited for long: the recording
        // has started already.
        let selected = run("""
        with timeout of 1 second
            tell application id "\(bundleID)"
                \(select)
            end tell
        end timeout
        return "ok"
        """) != nil
        Log.trace("Recorder: the meeting's tab \(selected ? "brought forward" : "not brought forward") in \(bundleID)")
        return selected
    }

    /// Every tab of every window with its window's place and the title of
    /// the tab in front of it: nil when the script failed.
    private static func tabs(in bundleID: String, _ family: BrowserTabReuse.Family) -> [(tab: Quicklink.OpenTab, bounds: CGRect, front: String)]? {
        let front = family == .safari ? "index of current tab of w" : "active tab index of w"
        let frontTitle = family == .safari ? "name of current tab of w" : "title of active tab of w"
        let source = """
        set sep to character id 9
        set out to ""
        with timeout of 3 seconds
            tell application id "\(bundleID)"
                repeat with w in windows
                    try
                        set wid to id of w
                        set b to bounds of w
                        set cur to \(front)
                        set wt to \(frontTitle)
                        if wt is missing value then set wt to ""
                        set wb to ((item 1 of b) as text) & "," & (item 2 of b) & "," & (item 3 of b) & "," & (item 4 of b)
                        set addresses to URL of every tab of w
                        repeat with t from 1 to count of addresses
                            set u to item t of addresses
                            if u is missing value then set u to ""
                            set out to out & wid & sep & t & sep & (t = cur) & sep & wb & sep & wt & sep & u & linefeed
                        end repeat
                    end try
                end repeat
            end tell
        end timeout
        return out
        """
        guard let text = run(source) else { return nil }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6, let window = Int(parts[0]), let index = Int(parts[1]) else { return nil }
            let edges = parts[3].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let bounds = edges.count == 4 ? CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1]) : .null
            return (Quicklink.OpenTab(window: window, index: index, url: parts[5], active: parts[2] == "true"), bounds, parts[4])
        }
    }

    /// `pid`'s window at `bounds` showing a tab titled `front` (the
    /// browser's own numbering is not the window list's): its place on
    /// screen, its title when windows share a place (two maximized). Nil
    /// when that still leaves several: the user picks.
    private static func window(of pid: pid_t, at bounds: CGRect, showing front: String) -> CGWindowID? {
        guard !bounds.isNull, let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let matching = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid, (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let frame = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return false }
            return abs(frame.minX - bounds.minX) <= 2 && abs(frame.minY - bounds.minY) <= 2 && abs(frame.width - bounds.width) <= 2
                && abs(frame.height - bounds.height) <= 2
        }
        let id: ([String: Any]) -> CGWindowID? = { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        guard matching.count > 1 else { return matching.first.flatMap(id) }
        let titled = matching.filter { info in
            let name = info[kCGWindowName as String] as? String ?? ""
            return !front.isEmpty && !name.isEmpty && (name == front || name.hasPrefix(front))
        }
        return titled.count == 1 ? titled.first.flatMap(id) : nil
    }

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.trace("Recorder: the browser's script failed (\(error[NSAppleScript.errorNumber] as? Int ?? 0))")
            return nil
        }
        return result?.stringValue ?? ""
    }
}
