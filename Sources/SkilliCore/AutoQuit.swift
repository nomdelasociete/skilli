import Foundation

/// Auto Quit (Settings → Auto Quit): the apps the user listed, each quit
/// once unused for its own delay; an app not listed is never quit. This
/// part decides who may go, from what the app reads (when each app was last
/// in front, which is in front now); the app then checks what only a live
/// Mac tells (unsaved work, sound in use, busy) and, with a deciding key,
/// asks Jev whether each one is safe to quit from its windows' titles.
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

    /// One app the user listed and how long it may go unused, in minutes.
    public struct Rule: Codable, Equatable, Hashable, Sendable {
        public let bundleID: String
        public var minutes: Int

        public init(bundleID: String, minutes: Int) {
            self.bundleID = bundleID
            self.minutes = AutoQuit.clamped(minutes)
        }
    }

    /// The delays the pane offers first, in minutes; any other in `range`
    /// is typed (Custom…).
    public static let delays = [15, 30, 60, 120, 240, 480, 1_440]
    /// A new app's delay: one hour.
    public static let defaultDelay = 60
    /// From 5 minutes to a week.
    public static let range = 5...10_080

    public static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, range.lowerBound), range.upperBound)
    }

    /// "30 minutes", "1 hour", "2 hours", "1 hour 30 minutes", "1 day".
    public static func spoken(minutes: Int) -> String {
        func unit(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
        if minutes >= 1_440, minutes % 1_440 == 0 { return unit(minutes / 1_440, "day") }
        if minutes < 60 { return unit(minutes, "minute") }
        let hours = unit(minutes / 60, "hour")
        return minutes % 60 == 0 ? hours : hours + " " + unit(minutes % 60, "minute")
    }

    /// A delay as typed: "90", "90 min", "2 h", "1h30", "1.5 hours",
    /// "2 jours"; a bare number is minutes. Nil when it says none, or one
    /// out of `range`.
    public static func minutes(from text: String) -> Int? {
        let folded = text.lowercased().replacingOccurrences(of: ",", with: ".")
        var total = 0.0
        var found = false
        var number = ""
        var word = ""
        func flush() {
            guard let value = Double(number) else { return }
            let unit: Double = word.hasPrefix("d") || word.hasPrefix("j") ? 1_440 : word.hasPrefix("h") ? 60 : 1
            total += value * unit
            found = true
            number = ""
            word = ""
        }
        for character in folded + " " {
            if character.isNumber || (character == "." && !number.isEmpty && word.isEmpty) {
                // "1h30": the hours end, the bare number after is minutes.
                if !word.isEmpty { flush() }
                number.append(character)
            } else if character.isLetter {
                guard !number.isEmpty else { continue }
                word.append(character)
            } else if !word.isEmpty {
                flush()
            }
        }
        flush()
        let minutes = Int(total.rounded())
        return found && range.contains(minutes) ? minutes : nil
    }

    /// A list item as tools read it: "Arc: 2 hours".
    public static func item(name: String, minutes: Int) -> String {
        "\(name): \(spoken(minutes: minutes))"
    }

    /// A list item as tools write it: the app, then its delay after ":",
    /// "," or " after " ("Arc: 2 h", "Docker Desktop, 90 min"); without a
    /// delay, `defaultDelay`. Nil minutes: a delay was given but is not one.
    public static func parseItem(_ text: String) -> (app: String, minutes: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" after ", ":", ","] {
            guard let range = trimmed.range(of: separator, options: [.backwards, .caseInsensitive]) else { continue }
            let app = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let delay = String(trimmed[range.upperBound...])
            guard !app.isEmpty, delay.contains(where: \.isNumber) else { continue }
            return (app, minutes(from: delay))
        }
        return (trimmed, defaultDelay)
    }

    /// Never quit, even listed: skil.li, Finder, macOS's own faces.
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

    /// The listed apps (`rules`: bundle id → minutes) that went unused for
    /// their delay and may be quit: never one not listed, the one in front
    /// or a protected one. The longest unused first.
    public static func candidates(_ apps: [App], now: Date, rules: [String: Int]) -> [App] {
        apps.filter { app in
            guard let minutes = waiting(app, rules) else { return false }
            return now.timeIntervalSince(app.lastUsed) >= TimeInterval(minutes * 60)
        }
        .sorted { $0.lastUsed < $1.lastUsed }
    }

    /// When to look again: the moment the next listed app reaches its delay
    /// (a minute at least from now); nil when none can.
    public static func nextCheck(_ apps: [App], now: Date, rules: [String: Int]) -> Date? {
        let due = apps.compactMap { app in waiting(app, rules).map { app.lastUsed.addingTimeInterval(TimeInterval($0 * 60)) } }.min()
        return due.map { max($0, now.addingTimeInterval(60)) }
    }

    /// Its delay, when it is listed, not in front and not protected.
    private static func waiting(_ app: App, _ rules: [String: Int]) -> Int? {
        guard !app.isFront, !protected.contains(app.bundleID), let minutes = rules[app.bundleID] else { return nil }
        return clamped(minutes)
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
