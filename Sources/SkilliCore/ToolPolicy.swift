import Foundation

/// What a tool can do, which decides when it needs the user's approval.
public enum ToolRisk: String, Sendable {
    /// Talks to the user only (ask a question, show a note).
    case none
    /// Reads something (the selection, the clipboard, the menus).
    case read
    /// Changes something the user did not write: opens an app or a page.
    case harmless
    /// Changes the user's text, clipboard or app state.
    case changes
}

/// How tools that act are approved (Settings → Ask → When It Acts), Raycast-style.
public enum ApprovalMode: String, CaseIterable, Sendable {
    /// Every tool that reads or acts asks first.
    case ask
    /// Reading and opening run; changes ask first.
    case auto
    /// Everything runs.
    case always
}

/// A choice the user made for one tool, over the mode.
public enum ToolOverride: String, CaseIterable, Sendable {
    case ask
    case always
    /// Never runs: refused without asking.
    case never
}

public enum ToolPolicy {
    public enum Decision: Sendable {
        case run, ask, block
    }

    /// What a call of a tool does: runs, waits for the user's OK, or is
    /// refused (the user blocked it). `everyTime`: a tool that asks every
    /// time (a change to skil.li's own settings): only Block changes that,
    /// never Always Allow, the mode or an "allow" right.
    public static func decision(risk: ToolRisk, mode: ApprovalMode, override: ToolOverride?, everyTime: Bool = false) -> Decision {
        if override == .never { return .block }
        return needsApproval(risk: risk, mode: mode, override: override, everyTime: everyTime) ? .ask : .run
    }

    /// Whether a call of a tool with `risk` waits for the user's OK.
    public static func needsApproval(risk: ToolRisk, mode: ApprovalMode, override: ToolOverride?, everyTime: Bool = false) -> Bool {
        if risk == .none { return false }
        if everyTime { return true }
        switch override {
        case .always: return false
        case .ask, .never: return true
        case nil: break
        }
        switch mode {
        case .ask: return true
        case .auto: return risk == .changes
        case .always: return false
        }
    }
}
