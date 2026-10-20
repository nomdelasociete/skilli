import AppKit
import ApplicationServices

/// Where "do it here" acts when a link (`skilli://do`) or an agent's tool
/// (`do_in_app`) asks for it rather than Ask: the app it names, brought
/// forward (opened when it is not running), else the app the caller came
/// from, else the one in front; never skil.li itself
/// (docs/do-it-here-from-anywhere.md).
@MainActor
enum ControlTarget {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The app named, in front: a running app by its bundle id or name
    /// (case aside), else installed (`findApp`: the launcher's index) and
    /// opened. Thrown: no app by that name, or it did not come forward.
    static func bringForward(_ name: String, findApp: (String) -> URL?) async throws -> NSRunningApplication {
        let wanted = name.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let running = NSWorkspace.shared.runningApplications.first { app in
            app.activationPolicy == .regular && app.processIdentifier != getpid()
                && [app.bundleIdentifier, app.localizedName].contains { $0?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == wanted }
        }
        let app: NSRunningApplication
        var opened = false
        if let running {
            app = running
            app.activate()
        } else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) ?? findApp(name) else {
                throw Failure(message: "No app called “\(name)” is installed.")
            }
            app = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            opened = true
        }
        // Since macOS 14 activating is cooperative and the app in front may
        // decline: with Accessibility, made frontmost as a click would.
        if await !untilFront(app, within: .milliseconds(500)) {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        guard await untilFront(app, within: .seconds(opened ? 10 : 3)) else {
            throw Failure(message: "\(app.localizedName ?? name) did not come forward.")
        }
        // Just opened: its first window, before the first look reads it.
        if opened { await untilWindow(app, within: .seconds(5)) }
        return app
    }

    /// The app to act in when none is named: `pid` (where a command
    /// started) while it runs, else the app in front unless it is skil.li.
    static func front(else pid: pid_t?) -> NSRunningApplication? {
        if let pid, pid != getpid(), let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated { return app }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return nil }
        return front
    }

    private static func untilFront(_ app: NSRunningApplication, within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            guard ContinuousClock.now < deadline, !app.isTerminated else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// Until Accessibility lists a window of `app` (an app just opened
    /// shows its first one a moment after it is in front).
    private static func untilWindow(_ app: NSRunningApplication, within limit: Duration) async {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            var windows: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success, let list = windows as? [AnyObject],
               !list.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
