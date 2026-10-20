import Foundation

/// Auto Quit (Settings → Windows): the apps the user stopped using, quit
/// after a delay. This part decides who may go, from what the app reads
/// (when each app was last in front, which is in front now); the app then
/// checks what only a live Mac tells (unsaved work, sound in use, busy) and,
/// with a deciding key, asks Jev whether each one is safe to quit from its
/// windows' titles.
public enum AutoQuit {
    /// An open app with a Dock icon, as the app reads it.
    public struct App: Equatable, Sendable {
        public let bundleID: String
        public let name: String
        public let pid: Int32
        /// The last time it was in front, or launched, or skil.li started:
        /// whichever came last.
        public let lastUsed: Date
        public let isFront: Bool

        public init(bundleID: String, name: String, pid: Int32, lastUsed: Date, isFront: Bool) {
            self.bundleID = bundleID
            self.name = name
            self.pid = pid
            self.lastUsed = lastUsed
            self.isFront = isFront
        }
    }

    /// The delays offered, in minutes; one hour by default.
    public static let delays = [30, 60, 120, 240]
    public static let defaultDelay = 60

    /// "30 minutes", "1 hour", "2 hours".
    public static func spoken(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) minutes" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }

    /// Never quit, whatever the list says: skil.li, Finder, macOS's own
    /// faces.
    public static let protected: Set<String> = [
        "com.nomdelasociete.Skilli", "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.WindowManager",
        "com.apple.SecurityAgent", "com.apple.coreservices.uiagent"
    ]

    /// Jev's "safe to quit" from 70 %: unsure, the app stays.
    public static let safeThreshold = 0.7

    /// CPU over the time measured from which an app is busy (5 %: an
    /// export, a build, a download): it stays.
    public static let busyShare = 0.05

    /// The apps that went unused for `delay` seconds and may be quit:
    /// never the one in front, a protected one or one the user keeps
    /// (`never`, bundle ids). The longest unused first.
    public static func candidates(_ apps: [App], now: Date, delay: TimeInterval, never: Set<String>) -> [App] {
        apps.filter { app in
            !app.isFront && !protected.contains(app.bundleID) && !never.contains(app.bundleID) && now.timeIntervalSince(app.lastUsed) >= delay
        }
        .sorted { $0.lastUsed < $1.lastUsed }
    }

    /// When to look again: the moment the next app reaches the delay (a
    /// minute at least from now); nil when no app can.
    public static func nextCheck(_ apps: [App], now: Date, delay: TimeInterval, never: Set<String>) -> Date? {
        let waiting = apps.filter { !$0.isFront && !protected.contains($0.bundleID) && !never.contains($0.bundleID) }
        guard let due = waiting.map({ $0.lastUsed.addingTimeInterval(delay) }).min() else { return nil }
        return max(due, now.addingTimeInterval(60))
    }

    /// Busy: it used at least `busyShare` of a core over the time measured.
    public static func isBusy(cpuSeconds: Double, over seconds: Double) -> Bool {
        seconds > 0 && cpuSeconds / seconds >= busyShare
    }

    /// One app as Jev reads it: its name and its windows' titles, nothing
    /// else ("Terminal — windows: “~ — ssh deploy@box — 80×24”").
    public static func describe(name: String, titles: [String]) -> String {
        let shown = titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(8)
            .map { "“\($0.count > 120 ? String($0.prefix(119)) + "…" : $0)”" }
        return shown.isEmpty ? "\(name) — no window open" : "\(name) — windows: \(shown.joined(separator: ", "))"
    }

    /// The question each candidate is asked, in one request.
    public static let instructions = "The user has not used this Mac app for a long while; skil.li may quit it to free memory. Is it safe to quit now? Not safe when its windows show a call or meeting going on, something downloading, uploading, exporting, rendering, syncing or installing, a command or a server running in a terminal (a shell prompt alone is idle), a recording, or unsaved work. Answer from the app's name and its windows' titles only."
}
