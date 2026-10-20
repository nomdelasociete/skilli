import Foundation

/// Settings → About: one line per feature, whether it works now and where to
/// fix it, built from facts the app reads. No personal content in it, so it
/// can be copied as diagnostics.
public enum Health {
    public enum State: String, Sendable {
        case ok
        /// Needs the user: something is missing or failing.
        case attention
        /// Not set up or turned off, on purpose or not yet.
        case off
    }

    public struct Line: Equatable, Sendable {
        public let feature: String
        public let state: State
        /// "Mapped to F18 by skil.li", "Paused: Secure Input is on in 1Password".
        public let detail: String
        /// The Settings pane that fixes it (its title), nil when none does.
        public let pane: String?

        public init(feature: String, state: State, detail: String, pane: String?) {
            self.feature = feature
            self.state = state
            self.detail = detail
            self.pane = pane
        }
    }

    /// What the app knows now.
    public struct Facts: Sendable {
        public var accessibility = false
        public var superKeyActive = false
        /// "Mapped to F18 by skil.li", "Handled by Raycast".
        public var superKeyStatus = ""
        public var shortcutsActive = false
        /// The app holding Secure Input, "" when unknown; nil when it is off.
        public var secureInputApp: String?
        /// "Claude · Haiku"; nil when nothing can write.
        public var writer: String?
        /// Why nothing writes: "Not set up: sign in to Claude Code…".
        public var writerProblem: String?
        /// "TypeSafe Jev", "OpenAI": the decision keys set, in the order used.
        public var deciders: [String] = []
        public var clipboardHistory = false
        public var clipboardAsksEachTime = false
        public var calendarAccess = false
        public var screenRecording = false
        public var githubSignedIn = false
        public var githubProblem: String?
        public var githubUpdated: Date?
        public var backupFolderSet = false
        public var lastBackup: Date?
        public var backupProblem: String?

        public init() {}
    }

    public static func lines(_ facts: Facts, now: Date = .now) -> [Line] {
        var lines: [Line] = []
        lines.append(facts.accessibility
            ? Line(feature: "Accessibility", state: .ok, detail: "Allowed", pane: nil)
            : Line(feature: "Accessibility", state: .attention, detail: "Not allowed: shortcuts and the selection cannot work", pane: "Privacy"))
        lines.append(Line(feature: "Hyper Key", state: facts.superKeyActive ? .ok : .attention,
                          detail: facts.superKeyStatus.isEmpty ? (facts.superKeyActive ? "Ready" : "Caps Lock is not set up") : facts.superKeyStatus,
                          pane: facts.superKeyActive ? nil : "Keys"))
        if let app = facts.secureInputApp {
            lines.append(Line(feature: "Shortcuts", state: .attention,
                              detail: "Paused: Secure Input is on" + (app.isEmpty ? "" : " in \(app)"), pane: nil))
        } else {
            lines.append(facts.shortcutsActive
                ? Line(feature: "Shortcuts", state: .ok, detail: "Working", pane: nil)
                : Line(feature: "Shortcuts", state: .attention, detail: "Not receiving keys", pane: "Keys"))
        }
        if let writer = facts.writer {
            lines.append(Line(feature: "Writing", state: .ok, detail: writer, pane: nil))
        } else {
            lines.append(Line(feature: "Writing", state: .attention, detail: facts.writerProblem ?? "No account can write", pane: "SI Accounts"))
        }
        lines.append(facts.deciders.isEmpty
            ? Line(feature: "Ask's choices", state: .attention, detail: "No key: Ask hands everything to Claude Code, slower", pane: "SI Accounts")
            : Line(feature: "Ask's choices", state: .ok, detail: facts.deciders.joined(separator: ", then "), pane: nil))
        if !facts.clipboardHistory {
            lines.append(Line(feature: "Clipboard history", state: .off, detail: "Off", pane: "Clipboard"))
        } else if facts.clipboardAsksEachTime {
            lines.append(Line(feature: "Clipboard history", state: .attention, detail: "macOS asks before each read", pane: "Privacy"))
        } else {
            lines.append(Line(feature: "Clipboard history", state: .ok, detail: "Keeping what you copy", pane: nil))
        }
        lines.append(facts.calendarAccess
            ? Line(feature: "Calendar", state: .ok, detail: "Reading your calendars", pane: nil)
            : Line(feature: "Calendar", state: .off, detail: "No access", pane: "Privacy"))
        lines.append(facts.screenRecording
            ? Line(feature: "Do it here", state: .ok, detail: "Reads the words a window shows", pane: nil)
            : Line(feature: "Do it here", state: .off, detail: "Accessibility only", pane: "Privacy"))
        if !facts.githubSignedIn {
            lines.append(Line(feature: "GitHub", state: .off, detail: "Not signed in", pane: "GitHub"))
        } else if let problem = facts.githubProblem {
            lines.append(Line(feature: "GitHub", state: .attention, detail: problem, pane: "GitHub"))
        } else {
            lines.append(Line(feature: "GitHub", state: .ok, detail: facts.githubUpdated.map { "Updated \(ago($0, now: now))" } ?? "Signed in", pane: nil))
        }
        if !facts.backupFolderSet {
            lines.append(Line(feature: "Backup", state: .off, detail: "No folder chosen", pane: "Backup"))
        } else if let problem = facts.backupProblem {
            lines.append(Line(feature: "Backup", state: .attention, detail: problem, pane: "Backup"))
        } else {
            lines.append(Line(feature: "Backup", state: .ok, detail: facts.lastBackup.map { "Last one \(ago($0, now: now))" } ?? "None yet", pane: nil))
        }
        return lines
    }

    /// The lines as plain text, with the version and the system, to paste
    /// in a message.
    public static func diagnostics(_ lines: [Line], version: String, system: String) -> String {
        (["skil.li \(version) · \(system)"] + lines.map { "\($0.feature): \($0.state.rawValue) — \($0.detail)" })
            .joined(separator: "\n")
    }

    /// "just now", "5 min ago", "3 h ago", "2 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3_600)) h ago"
        default:
            let days = Int(seconds / 86_400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }
}
