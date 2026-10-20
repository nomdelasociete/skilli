/// Something else that answers a key skil.li's shortcuts could take: one
/// of macOS's own shortcuts, or a key of the launcher while it is open.
///
/// skil.li's event tap sees a key before macOS acts on it (measured on the
/// Mac mini, 2026-10-16: ⌥⌘Space bound in skil.li ran skil.li's action and
/// Finder's search window never opened), and its shortcuts run before the
/// launcher's keys. A shortcut on such a key silently takes it away, so the
/// recorder refuses it and Settings says it of one read from the file.
public struct KeyOwner: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// One of macOS's: `section` is where System Settings → Keyboard →
        /// Keyboard Shortcuts… lists it, nil when it cannot be turned off.
        case macOS(section: String?)
        /// A key of the launcher while it is open.
        case launcher
    }

    public let chord: Chord
    /// As its owner names it: "Show Spotlight search", "Actions".
    public let name: String
    public let kind: Kind
    /// The skil.li action that does the same, which may take its keys
    /// (its `SkilliAction.id`), as Raycast's do: skil.li's emoji search has
    /// macOS's Emoji & Symbols key, the launcher Spotlight's ⌘Space. Nil
    /// for every other.
    public let replacedBy: String?

    public init(chord: Chord, name: String, kind: Kind, replacedBy: String? = nil) {
        self.chord = chord
        self.name = name
        self.kind = kind
        self.replacedBy = replacedBy
    }

    /// Where System Settings turns it off, when it can.
    public var section: String? {
        if case .macOS(let section) = kind { return section }
        return nil
    }

    /// Why a skil.li shortcut cannot have these keys.
    public var refusal: String {
        switch kind {
        case .launcher: "Used by the launcher: \(name)."
        case .macOS(let section?): "Used by macOS: \(name). Turn it off in System Settings → Keyboard → Keyboard Shortcuts… → \(section)."
        case .macOS(nil): "Used by macOS: \(name), which cannot be turned off."
        }
    }

    /// What a shortcut read from the file shares with it: the shortcut
    /// still works and takes the keys first, so the other one does not.
    public var sharing: String {
        switch kind {
        case .launcher: "The launcher's \(name) has these keys too: while it is open, this shortcut runs instead."
        case .macOS(let section?): "macOS's \(name) has these keys too and no longer works. Turn it off in System Settings → Keyboard → Keyboard Shortcuts… → \(section), or choose other keys."
        case .macOS(nil): "macOS's \(name) has these keys too and no longer works. Choose other keys."
        }
    }

    /// What Settings says under the shortcut that took its keys.
    public var replaced: String {
        "Replaces macOS's \(name)."
    }

    /// The owner of the key a shortcut starts with: a chain that starts
    /// with ⌘Space shares ⌘Space, its first key is taken. `action` (its
    /// id) keeps the keys of an owner it replaces.
    public static func owner(of chords: [Chord], in owners: [KeyOwner], for action: String? = nil) -> KeyOwner? {
        guard let first = chords.first else { return nil }
        return owners.first { $0.chord == first && ($0.replacedBy == nil || $0.replacedBy != action) }
    }

    /// The owner whose keys `action` took, by replacing it.
    public static func replaced(by action: String, with chords: [Chord], in owners: [KeyOwner]) -> KeyOwner? {
        guard let first = chords.first else { return nil }
        return owners.first { $0.chord == first && $0.replacedBy == action }
    }
}

/// The launcher's own keys while it is open, besides typing and the keys
/// without ⌘, ⌃ or ⌥ (a shortcut cannot start with those). A shortcut on
/// one would take it from the launcher: the bindings run first. Kept in
/// step with `LauncherController.deliver`, `actionPanelKey`,
/// `LauncherPanel.performKeyEquivalent` and `LauncherAction.Key`; its
/// "Open Settings" key is the user's (`ShortcutConfig.launcherOpenSettings`).
public enum LauncherKeys {
    public static let all: [KeyOwner] = [
        own("cmd+k", "Actions"),
        own("cmd+return", "the selected row's second action"),
        own("cmd+c", "Copy"),
        own("cmd+shift+c", "Copy Second Value"),
        own("cmd+delete", "Remove"),
        own("ctrl+n", "Next Row"),
        own("ctrl+p", "Previous Row"),
        own("cmd+w", "Close"),
        own("cmd+x", "Cut"),
        own("cmd+v", "Paste"),
        own("cmd+a", "Select All"),
        own("cmd+z", "Undo")
    ]

    public static let openSettingsName = "Open Settings"

    private static func own(_ spec: String, _ name: String) -> KeyOwner {
        // The specs above are literals: a typo fails the unit tests.
        KeyOwner(chord: (try? Chord(parsing: spec)) ?? Chord(.named(.escape)), name: name, kind: .launcher)
    }
}

/// macOS's own shortcuts, as System Settings → Keyboard → Keyboard
/// Shortcuts… lists them: their entries in `com.apple.symbolichotkeys`
/// (`AppleSymbolicHotKeys`), named and with their defaults from macOS's
/// own table (`KeyboardSettings.appex`'s `DefaultShortcutsTable.xml`,
/// macOS 26–27), plus the few it keeps for itself.
public enum SystemShortcuts {
    public struct Entry: Sendable {
        /// Its number in `AppleSymbolicHotKeys`.
        public let id: String
        public let name: String
        /// Its group in Keyboard Shortcuts….
        public let section: String
        /// Its keys while the user never changed it; nil when it has none.
        public let standard: SymbolicHotKey?
        /// The character macOS keeps with them ("m" for Minimize), if any.
        public let standardCharacter: UInt16?
        public let onByDefault: Bool
    }

    // NSEvent's modifier bits, as macOS stores them.
    private static let shift: UInt64 = 1 << 17
    private static let control: UInt64 = 1 << 18
    private static let option: UInt64 = 1 << 19
    private static let command: UInt64 = 1 << 20
    private static let function: UInt64 = 1 << 23

    private static func entry(_ id: Int, _ name: String, _ section: String, _ keyCode: UInt16? = nil, _ modifiers: UInt64 = 0,
                              char: Character? = nil, on: Bool = true) -> Entry {
        Entry(id: String(id), name: name, section: section,
              standard: keyCode.map { SymbolicHotKey(keyCode: $0, modifiers: modifiers) },
              standardCharacter: char?.asciiValue.map(UInt16.init), onByDefault: on && keyCode != nil)
    }

    /// Every shortcut Keyboard Shortcuts… lists that a key can reach; the
    /// "slow" variants (with ⇧) are hidden there and follow their main one.
    public static let table: [Entry] = {
        var entries: [Entry] = [
            entry(52, "Turn Dock hiding on/off", "Dock", 2, option | command, char: "d"),
            entry(32, "Mission Control", "Mission Control", 126, control),
            entry(34, "Mission Control", "Mission Control", 126, control | shift),
            entry(33, "Application windows", "Mission Control", 125, control),
            entry(35, "Application windows", "Mission Control", 125, control | shift),
            entry(36, "Show Desktop", "Mission Control", 103, 0),
            entry(37, "Show Desktop", "Mission Control", 103, shift),
            entry(79, "Move left a Space", "Mission Control", 123, control),
            entry(80, "Move left a Space", "Mission Control", 123, control | shift),
            entry(81, "Move right a Space", "Mission Control", 124, control),
            entry(82, "Move right a Space", "Mission Control", 124, control | shift),
            entry(163, "Show Notification Center", "Mission Control"),
            entry(175, "Turn Do Not Disturb on/off", "Mission Control"),
            entry(222, "Turn Stage Manager on/off", "Mission Control"),
            entry(190, "Quick Note", "Mission Control", 12, function, char: "q"),
            entry(260, "Game Overlay", "Mission Control", 53, command),
            entry(233, "Minimize", "Windows", 46, command, char: "m"),
            entry(235, "Zoom", "Windows"),
            entry(237, "Fill", "Windows", 3, function | control, char: "f"),
            entry(238, "Center", "Windows", 8, function | control, char: "c"),
            entry(239, "Return to Previous Size", "Windows", 15, function | control, char: "r"),
            entry(240, "Tile Left Half", "Windows", 123, function | control),
            entry(241, "Tile Right Half", "Windows", 124, function | control),
            entry(242, "Tile Top Half", "Windows", 126, function | control),
            entry(243, "Tile Bottom Half", "Windows", 125, function | control),
            entry(244, "Tile Top Left Quarter", "Windows"),
            entry(245, "Tile Top Right Quarter", "Windows"),
            entry(246, "Tile Bottom Left Quarter", "Windows"),
            entry(247, "Tile Bottom Right Quarter", "Windows"),
            entry(248, "Arrange Left and Right", "Windows", 123, function | control | shift),
            entry(249, "Arrange Right and Left", "Windows", 124, function | control | shift),
            entry(250, "Arrange Top and Bottom", "Windows", 126, function | control | shift),
            entry(251, "Arrange Bottom and Top", "Windows", 125, function | control | shift),
            entry(256, "Arrange in Quarters", "Windows"),
            entry(257, "Full Screen Tile Left", "Windows"),
            entry(258, "Full Screen Tile Right", "Windows"),
            entry(13, "Change the way Tab moves focus", "Keyboard", 98, control),
            entry(12, "Turn keyboard access on or off", "Keyboard", 122, control),
            entry(7, "Move focus to the menu bar", "Keyboard", 120, control),
            entry(8, "Move focus to the Dock", "Keyboard", 99, control),
            entry(9, "Move focus to active or next window", "Keyboard", 118, control),
            entry(10, "Move focus to the window toolbar", "Keyboard", 96, control),
            entry(11, "Move focus to the floating window", "Keyboard", 97, control),
            entry(27, "Move focus to next window", "Keyboard", 50, command, char: "`"),
            entry(57, "Move focus to status menus", "Keyboard", 100, control),
            entry(159, "Show contextual menu", "Keyboard", 36, control),
            entry(156, "Show/Hide Trackpad Handwriting", "Keyboard", 49, control | shift, on: false),
            entry(60, "Select the previous input source", "Input Sources", 49, control, char: " "),
            entry(61, "Select next source in Input menu", "Input Sources", 49, control | option, char: " "),
            entry(28, "Save picture of screen as a file", "Screenshots", 20, shift | command, char: "3"),
            entry(29, "Copy picture of screen to the clipboard", "Screenshots", 20, control | shift | command, char: "3"),
            entry(30, "Save picture of selected area as a file", "Screenshots", 21, shift | command, char: "4"),
            entry(31, "Copy picture of selected area to the clipboard", "Screenshots", 21, control | shift | command, char: "4"),
            entry(184, "Screenshot and recording options", "Screenshots", 23, shift | command, char: "5"),
            entry(261, "Ask Siri about selected area", "Screenshots", 22, shift | command, char: "6"),
            entry(263, "Ask Siri about active window", "Screenshots", 49, shift | command, char: " "),
            entry(181, "Save picture of the Touch Bar as a file", "Screenshots", 26, shift | command, char: "7"),
            entry(182, "Copy picture of the Touch Bar to the clipboard", "Screenshots", 26, control | shift | command, char: "7"),
            entry(224, "Turn Presenter Overlay (small) on or off", "Presenter Overlay"),
            entry(223, "Turn Presenter Overlay (large) on or off", "Presenter Overlay"),
            entry(64, "Show Spotlight search", "Spotlight", 49, command, char: " "),
            entry(65, "Show Finder search window", "Spotlight", 49, option | command, char: " "),
            entry(160, "Show Apps", "Spotlight"),
            entry(25, "Increase contrast", "Accessibility", 47, control | option | command, char: ".", on: false),
            entry(26, "Decrease contrast", "Accessibility", 43, control | option | command, char: ",", on: false),
            entry(21, "Invert colors", "Accessibility", 28, control | option | command, char: "8", on: false),
            entry(162, "Show Accessibility controls", "Accessibility", 96, option | command),
            entry(59, "Turn VoiceOver on or off", "Accessibility", 96, command),
            entry(15, "Turn zoom on or off", "Accessibility", 28, option | command, char: "8", on: false),
            entry(23, "Turn image smoothing on or off", "Accessibility", 42, option | command, char: "\\", on: false),
            entry(19, "Zoom out", "Accessibility", 27, option | command, char: "-", on: false),
            entry(17, "Zoom in", "Accessibility", 24, option | command, char: "=", on: false),
            entry(53, "Decrease display brightness", "Display", 107, 0),
            entry(54, "Increase display brightness", "Display", 113, 0),
            entry(98, "Show Help menu", "App Shortcuts", 44, shift | command, char: "/")
        ]
        // Switch to Desktop 1…16: ⌃1…⌃0 offered, off until turned on.
        let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for desktop in 1...16 {
            entries.append(entry(117 + desktop, "Switch to Desktop \(desktop)", "Mission Control",
                                 desktop <= digits.count ? digits[desktop - 1] : nil, control, on: false))
        }
        return entries
    }()

    /// The id of skil.li's emoji search (`SkilliAction.searchEmoji`), the
    /// one action that may take macOS's Emoji & Symbols key.
    public static let emojiSearch = "emoji.search"

    /// The id of the launcher (`SkilliAction.toggleLauncher`), which may take
    /// Spotlight's search key, as Raycast does: the welcome recommends
    /// ⌘Space, and skil.li then turns Spotlight's own ⌘Space off
    /// (`settingSpotlightKey`), and back on once the launcher leaves it.
    public static let launcher = "launcher.toggle"

    /// Spotlight's search shortcut in `AppleSymbolicHotKeys`.
    public static let spotlightID = "64"

    /// Whether Spotlight's search shortcut answers ⌘Space now.
    public static func spotlightTakesCommandSpace(in hotKeys: [String: Any]?) -> Bool {
        active(in: hotKeys).contains { $0.entry.id == spotlightID && $0.hotKey == SymbolicHotKey(keyCode: 49, modifiers: command) }
    }

    /// `hotKeys` with Spotlight's search shortcut turned on or off, its keys
    /// kept as they are (macOS's default when the file has no entry for it).
    public static func settingSpotlightKey(on: Bool, in hotKeys: [String: Any]?) -> [String: Any] {
        var hotKeys = hotKeys ?? [:]
        var entry = hotKeys[spotlightID] as? [String: Any] ?? [
            "value": ["parameters": [32, 49, Int(command)], "type": "standard"] as [String: Any]
        ]
        entry["enabled"] = on
        hotKeys[spotlightID] = entry
        return hotKeys
    }

    /// Keyboard Shortcuts… entries a skil.li action may replace, by id.
    static let replaceable = ["64": launcher]

    /// Shortcuts macOS keeps for itself (not in Keyboard Shortcuts…), with
    /// the skil.li action that may replace one (`KeyOwner.replacedBy`).
    public static let fixed: [(hotKey: SymbolicHotKey, name: String, replacedBy: String?)] = [
        (SymbolicHotKey(keyCode: 48, modifiers: command), "Switch apps", nil),
        (SymbolicHotKey(keyCode: 48, modifiers: shift | command), "Switch apps", nil),
        (SymbolicHotKey(keyCode: 53, modifiers: option | command), "Force Quit Applications", nil),
        (SymbolicHotKey(keyCode: 12, modifiers: control | command), "Lock Screen", nil),
        (SymbolicHotKey(keyCode: 12, modifiers: shift | command), "Log Out", nil),
        // Each app's Edit → Emoji & Symbols (the key is its menu's, not in
        // Keyboard Shortcuts…): skil.li's tap sees it first.
        (SymbolicHotKey(keyCode: 49, modifiers: control | command), "Emoji & Symbols", emojiSearch)
    ]

    /// The shortcuts on now, each with its keys and character: an entry
    /// the file has says it (on or off, its keys), one it lacks has its
    /// default.
    public static func active(in hotKeys: [String: Any]?) -> [(entry: Entry, hotKey: SymbolicHotKey, character: UInt16?)] {
        table.compactMap { entry in
            guard hotKeys?[entry.id] != nil else {
                return entry.onByDefault ? entry.standard.map { (entry, $0, entry.standardCharacter) } : nil
            }
            return SymbolicHotKey.read(entry.id, in: hotKeys, standard: entry.standard).map {
                (entry, $0, SymbolicHotKey.character(entry.id, in: hotKeys))
            }
        }
    }

    /// The keys taken, as skil.li's chords. One kept with its character
    /// is that character's key, as the Mac's menus read it (Minimize is ⌘
    /// and the key typing "m" on any layout, not key code 46, which types
    /// "," on a French one); one without is its key code on the layout
    /// (`resolve`). Those skil.li cannot press (an F-key, 🌐) are left out.
    public static func owners(in hotKeys: [String: Any]?, resolve: (UInt16) -> Key?) -> [KeyOwner] {
        let set = active(in: hotKeys).map { ($0.hotKey, $0.character, $0.entry.name, Optional($0.entry.section), replaceable[$0.entry.id]) }
            + fixed.map { ($0.hotKey, UInt16?.none, $0.name, String?.none, $0.replacedBy) }
        return set.compactMap { hotKey, character, name, section, replacedBy in
            guard let modifiers = hotKey.chordModifiers,
                  let key = character.flatMap(key(typing:)) ?? resolve(hotKey.keyCode) else { return nil }
            return KeyOwner(chord: Chord(key, modifiers), name: name, kind: .macOS(section: section), replacedBy: replacedBy)
        }
    }

    /// The key typing a character macOS kept (ASCII; 32 is Space).
    static func key(typing character: UInt16) -> Key? {
        if character == 32 { return .named(.space) }
        guard character > 32, character < 127, let scalar = Unicode.Scalar(character) else { return nil }
        return Character(scalar).lowercased().first.map(Key.character)
    }
}

extension SymbolicHotKey {
    /// Its modifiers as skil.li's; nil when it needs 🌐 (fn), which
    /// skil.li's shortcuts never hold.
    public var chordModifiers: Modifiers? {
        guard modifiers & (1 << 23) == 0 else { return nil }
        var result: Modifiers = []
        if modifiers & (1 << 17) != 0 { result.insert(.shift) }
        if modifiers & (1 << 18) != 0 { result.insert(.control) }
        if modifiers & (1 << 19) != 0 { result.insert(.option) }
        if modifiers & (1 << 20) != 0 { result.insert(.command) }
        return result
    }
}
