import AppKit
import CoreServices

/// The apps skil.li sends commands to (System Settings → Privacy &
/// Security → Automation) and whether macOS lets it, read without asking
/// (`AEDeterminePermissionToAutomateTarget`, never a prompt). macOS asks
/// the user the first time skil.li sends each one a command.
enum AutomationAccess {
    struct Target: Identifiable, Sendable {
        let bundleID: String
        let name: String
        /// What skil.li asks it, in the user's words.
        let uses: String

        var id: String { bundleID }
    }

    enum State: Equatable, Sendable {
        case granted
        case denied
        /// macOS will ask the first time.
        case notAsked
        /// The app is not open: macOS only says while it is.
        case unknown
    }

    /// Every app skil.li scripts: `SystemCommands` (System Events, Finder;
    /// `FinderSelection`, the file selected),
    /// `CalendarBook.openInCalendar` (Calendar, the event's day),
    /// `MailSelection` (Mail, the message selected).
    static let targets = [
        Target(bundleID: "com.apple.systemevents", name: "System Events", uses: "Dark mode, restart, shut down, log out"),
        Target(bundleID: "com.apple.finder", name: "Finder", uses: "Empty the Trash, the selected file sent to CleanShot"),
        Target(bundleID: "com.apple.iCal", name: "Calendar", uses: "An event shown on its day"),
        Target(bundleID: "com.apple.mail", name: "Mail", uses: "“This email” in a reminder")
    ]

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// The targets, and the default browser while Settings → Catalog →
    /// Quicklinks → Reuse an open tab is on (`BrowserTabReuse`).
    @MainActor
    static func targets(reusingTabs: Bool) -> [Target] {
        guard reusingTabs, let browser = BrowserTabReuse.defaultBrowser() else { return targets }
        return targets + [Target(bundleID: browser.bundleID, name: browser.name, uses: "A quicklink loaded in a tab already open")]
    }

    /// Every target's state, read off the main thread: macOS may take a
    /// moment to answer for an app that is busy.
    static func states(of targets: [Target] = targets) async -> [String: State] {
        await Task.detached(priority: .utility) {
            Dictionary(targets.map { ($0.bundleID, state(of: $0.bundleID)) }, uniquingKeysWith: { first, _ in first })
        }.value
    }

    nonisolated static func state(of bundleID: String) -> State {
        state(determining: bundleID, ask: false)
    }

    /// macOS's prompt when it never asked (it waits for the answer): only
    /// off the main thread, for a feature the user turned on.
    nonisolated static func ask(_ bundleID: String) -> State {
        state(determining: bundleID, ask: true)
    }

    private nonisolated static func state(determining bundleID: String, ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch Int(status) {
        case Int(noErr): return .granted
        case errAEEventNotPermitted: return .denied
        case errAEEventWouldRequireUserConsent: return .notAsked
        // procNotFound: not open.
        default: return .unknown
        }
    }
}
