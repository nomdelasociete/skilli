import CoreGraphics
import Foundation

// The launcher's root search, "our way" (fewer knobs than Raycast): ↑ in
// the empty field brings back what was searched, ⌘K → Pin keeps an item at
// the top, a name typed whole comes first, and two settings: which screen
// it opens on, and when it starts again empty.

/// What ↑ brings back in the launcher's empty field: the searches the user
/// acted on (ran a result, or asked), newest first. The same words again
/// move to the front; the oldest go past `limit`.
public struct RecentSearches: Codable, Equatable, Sendable {
    public static let limit = 20
    /// A search longer than this (a pasted paragraph asked about) is kept
    /// cut: the field shows one line anyway.
    public static let maxLength = 500

    /// Newest first.
    public private(set) var entries: [String]

    public init(entries: [String] = []) {
        self.entries = []
        for entry in entries.reversed() { record(entry) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try container.decode([String].self, forKey: .entries))
    }

    /// `text`, spaces around it aside, becomes the newest search.
    public mutating func record(_ text: String) {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
        guard !text.isEmpty, !text.contains(where: \.isNewline) else { return }
        let key = Self.key(text)
        entries.removeAll { Self.key($0) == key }
        entries.insert(text, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    /// ↑: the search before the one at `index` (nil: from the empty
    /// field), nil when there is none older.
    public func older(than index: Int?) -> Int? {
        let next = index.map { $0 + 1 } ?? 0
        return entries.indices.contains(next) ? next : nil
    }

    /// ↓: the search after the one at `index`; nil is the empty field
    /// again, as in a shell.
    public func newer(than index: Int) -> Int? {
        entries.indices.contains(index - 1) ? index - 1 : nil
    }

    /// "Safari" and "safari" are the same search.
    static func key(_ text: String) -> String {
        text.lowercased()
    }
}

/// Items pinned to the top of the empty launcher, by their launcher id
/// (`LauncherItem.learningID`: "app:/Applications/Safari.app",
/// "cmd:emoji", "system:settings.bluetooth"), in the order pinned.
public enum LauncherPins {
    /// What a pinned item gains when it fits what is typed: as much as a
    /// word typed whole (`FuzzyMatcher`'s exact match), less than one pick
    /// learned for those words.
    public static let boost = 20

    /// Pinned last, after the others.
    public static func pinning(_ id: String, in pins: [String]) -> [String] {
        pins.contains(id) ? pins : pins + [id]
    }

    public static func unpinning(_ id: String, in pins: [String]) -> [String] {
        pins.filter { $0 != id }
    }

    /// The pinned items first, in the order pinned, then the rest without
    /// them.
    public static func first<Item>(_ pinned: [Item], then rest: [Item], id: (Item) -> String) -> [Item] {
        guard !pinned.isEmpty else { return rest }
        let ids = Set(pinned.map(id))
        return pinned + rest.filter { !ids.contains(id($0)) }
    }

    /// The pins left once those whose item is gone for good are dropped,
    /// each once, in their order.
    public static func kept(_ pins: [String], gone: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        return pins.filter { !gone($0) && seen.insert($0).inserted }
    }
}

/// How root search ranks what fits the words typed: a row the query names
/// comes before rows it only describes ("display": System Settings'
/// Displays before Move to Next Display, whose keyword it is).
public enum LauncherRank {
    /// What a row gains when the query is one of its names typed whole
    /// (`FuzzyMatcher.names`): more than a keyword typed whole (the
    /// matcher's exact match, 20, as much as a pin), less than one pick
    /// learned (`QueryLearning.pointsPerBit`, 30), so the user's habits
    /// still come first.
    public static let namedBoost = 25

    /// Whether `query` is one of `names` typed whole.
    public static func names(_ query: FuzzyMatcher.Query, _ names: ArraySlice<FuzzyCandidate>) -> Bool {
        names.contains { FuzzyMatcher.names(query, $0) }
    }

    /// A row's score: its best match over its names (its title; an app's
    /// names; a pane's in each of the user's languages) and keywords (other
    /// words that lead to it), plus `namedBoost` when the query is one of
    /// its names typed whole. Nil when nothing matches.
    public static func score(_ query: FuzzyMatcher.Query, names: ArraySlice<FuzzyCandidate>,
                             keywords: ArraySlice<FuzzyCandidate> = []) -> Int? {
        var best: Int?
        for candidate in names {
            if let score = FuzzyMatcher.score(query, candidate) { best = max(best ?? score, score) }
        }
        for candidate in keywords {
            if let score = FuzzyMatcher.score(query, candidate) { best = max(best ?? score, score) }
        }
        guard let best else { return nil }
        return Self.names(query, names) ? best + namedBoost : best
    }

    /// Where a row offered for a word goes (Allow Bluetooth, for
    /// "bluetooth"), among rows where `named` says which the query names:
    /// first, unless the query asks for settings ("réglages bluetooth",
    /// `SystemSettingsPane.asked`): then right after the first row it
    /// names, the pane asked for.
    public static func offerPlace(asksForSettings: Bool, named: [Bool]) -> Int {
        guard asksForSettings, let first = named.firstIndex(of: true) else { return 0 }
        return first + 1
    }
}

/// Which screen the launcher opens on (Settings → Launcher → Opens on).
/// Where on that screen stays where the user dragged it (`LauncherPlace`).
public enum LauncherScreen: String, CaseIterable, Codable, Sendable {
    /// The screen the pointer is on, as before this setting.
    case pointer
    /// The screen of the window in front.
    case frontWindow
    /// The main display (the first in System Settings → Displays).
    case main

    public var title: String {
        switch self {
        case .pointer: "The screen with the pointer"
        case .frontWindow: "The screen of the window in front"
        case .main: "The main display"
        }
    }

    /// Which of `screens` (AppKit frames, the main display first) it opens
    /// on. `pointerScreen`: the one the pointer is on; `frontWindow`: the
    /// window in front, in the same coordinates, when there is one. A
    /// window on no screen, or none, falls back to the pointer's screen;
    /// nil when there is no screen to pick.
    public func pick(screens: [CGRect], pointerScreen: Int?, frontWindow: CGRect?) -> Int? {
        switch self {
        case .pointer:
            return pointerScreen
        case .main:
            return screens.isEmpty ? nil : 0
        case .frontWindow:
            return frontWindow.flatMap { Self.holding($0, in: screens) } ?? pointerScreen
        }
    }

    /// The screen that shows most of `window`; nil when none shows any.
    public static func holding(_ window: CGRect, in screens: [CGRect]) -> Int? {
        let shown = screens.map { screen -> CGFloat in
            let part = screen.intersection(window)
            return part.isNull ? 0 : part.width * part.height
        }
        guard let best = shown.indices.max(by: { shown[$0] < shown[$1] }), shown[best] > 0 else { return nil }
        return best
    }

    /// A window's frame as the window server gives it (origin at the top
    /// left of the main display, y going down) in AppKit's coordinates
    /// (origin at its bottom left, y going up).
    public static func appKitFrame(fromTopLeft frame: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

/// When the launcher opens with an empty field again (Settings → Launcher
/// → Starts again empty). Before that, it opens with what it had: the
/// words, the mode, the row selected.
public enum LauncherReset: String, CaseIterable, Codable, Sendable {
    /// Every time, as before this setting.
    case immediately
    case afterOneMinute
    case afterFiveMinutes
    case never

    public var title: String {
        switch self {
        case .immediately: "Right away"
        case .afterOneMinute: "After 1 minute"
        case .afterFiveMinutes: "After 5 minutes"
        case .never: "Never"
        }
    }

    /// How long what was typed is kept once the launcher closed; nil:
    /// until skil.li quits.
    public var keeps: Duration? {
        switch self {
        case .immediately: .zero
        case .afterOneMinute: .seconds(60)
        case .afterFiveMinutes: .seconds(300)
        case .never: nil
        }
    }

    /// Whether a launcher closed `closedFor` ago opens with what it had.
    public func keepsSearch(closedFor: Duration) -> Bool {
        guard let keeps else { return true }
        return closedFor < keeps
    }
}
