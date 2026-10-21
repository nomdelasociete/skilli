import Foundation

// The launcher's keys (rules 5 and 6, 2026-10-17): the footer says the
// selected row's own ↩, ⇥ only where ⇥ does something, and ⌘K; ⇥ in a mode
// never asks; esc goes back before it closes. The launcher reads its
// state, these decide.

/// What ⇥ does in the launcher.
public enum LauncherTab: Equatable, Sendable {
    /// Outside the modes, with words typed: Ask about them.
    case ask
    /// A mode's own, as the footer names it: "By Meaning", "By Feeling",
    /// "Processes", "Details".
    case own(String)
    /// In a mode where ⇥ has nothing of its own: the row's actions, as ⌘K.
    case actions
    /// Nothing: no words outside the modes, no row in one.
    case nothing

    /// `own`: what the mode's ⇥ does now, when it does something there
    /// (nil: nothing of its own). Inside a mode ⇥ never asks: the filter
    /// may be a password or a skillie's argument.
    public static func of(inMode: Bool, own: String?, hasRow: Bool, typed: Bool, canAsk: Bool) -> LauncherTab {
        guard inMode else { return typed && canAsk ? .ask : .nothing }
        if let own { return .own(own) }
        return hasRow ? .actions : .nothing
    }

    /// Its hint in the footer; none where it does what ⌘K does.
    public var hint: String? {
        switch self {
        case .ask: "Ask"
        case .own(let title): title
        case .actions, .nothing: nil
        }
    }
}

/// The footer under the results: the selected row's ↩ (its first action,
/// as ⌘K lists it), ⇥ where it does something, then ⌘K. Nothing else.
public enum LauncherFooter {
    public static let actions = (label: "Actions", key: "⌘K")

    /// `main`: the selected row's ↩ title; nil when no row is selected
    /// (then no ⌘K either: there is nothing to act on).
    public static func hints(main: String?, tab: LauncherTab) -> [(label: String, key: String)] {
        var hints: [(label: String, key: String)] = []
        if let main { hints.append((main, "↩")) }
        if let label = tab.hint { hints.append((label, "⇥")) }
        if main != nil { hints.append(actions) }
        return hints
    }
}

/// Where esc goes in the launcher: one step back each time.
public enum LauncherEscape: Equatable, Sendable {
    /// ⌘K's list closes: back to the rows.
    case closeActions
    /// The app Kill unfolded into its processes folds back.
    case fold
    /// Out of the mode: the root search, the field as it was before it.
    case root(String)
    /// The launcher closes.
    case close

    /// `back`: the field before the mode; nil when the mode was opened
    /// straight (✦C, the menu bar, a link): back is the app, esc closes.
    public static func of(showingActions: Bool, unfolded: Bool, inMode: Bool, back: String?) -> LauncherEscape {
        if showingActions { return .closeActions }
        guard inMode else { return .close }
        if unfolded { return .fold }
        return back.map(LauncherEscape.root) ?? .close
    }
}
