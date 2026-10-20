import XCTest
@testable import SkilliCore

final class KeyOwnersTests: XCTestCase {
    private func entry(enabled: Int, _ parameters: [Int]) -> [String: Any] {
        ["enabled": NSNumber(value: enabled), "value": ["parameters": parameters.map { NSNumber(value: $0) }, "type": "standard"]]
    }

    /// A US layout for the few keys these tests read; F-keys have no key.
    private func resolve(_ code: UInt16) -> Key? {
        let named: [UInt16: NamedKey] = [49: .space, 36: .return, 48: .tab, 53: .escape, 51: .delete,
                                         123: .left, 124: .right, 125: .down, 126: .up]
        let characters: [UInt16: Character] = [2: "d", 12: "q", 20: "3", 21: "4", 22: "6", 23: "5", 26: "7",
                                                44: "/", 46: "m", 50: "`", 18: "1", 19: "2"]
        if let key = named[code] { return .named(key) }
        return characters[code].map(Key.character)
    }

    private func chord(_ spec: String) throws -> Chord {
        try Chord(parsing: spec)
    }

    func testDefaultsWhenTheUserNeverChangedThem() throws {
        let owners = SystemShortcuts.owners(in: [:], resolve: resolve)
        func owner(_ spec: String) throws -> KeyOwner? { KeyOwner.owner(of: [try chord(spec)], in: owners) }
        XCTAssertEqual(try owner("cmd+space")?.name, "Show Spotlight search")
        XCTAssertEqual(try owner("cmd+space")?.section, "Spotlight")
        XCTAssertEqual(try owner("opt+cmd+space")?.name, "Show Finder search window")
        XCTAssertEqual(try owner("ctrl+space")?.name, "Select the previous input source")
        XCTAssertEqual(try owner("ctrl+opt+space")?.section, "Input Sources")
        XCTAssertEqual(try owner("shift+cmd+3")?.name, "Save picture of screen as a file")
        XCTAssertEqual(try owner("ctrl+up")?.name, "Mission Control")
        XCTAssertEqual(try owner("ctrl+shift+up")?.name, "Mission Control", "its slow variant")
        XCTAssertEqual(try owner("ctrl+left")?.name, "Move left a Space")
        XCTAssertEqual(try owner("ctrl+return")?.name, "Show contextual menu")
        XCTAssertEqual(try owner("cmd+m")?.section, "Windows")
        XCTAssertEqual(try owner("shift+cmd+/")?.section, "App Shortcuts")
        XCTAssertNil(try owner("ctrl+1"), "Switch to Desktop 1 is off until turned on")
        XCTAssertNil(try owner("hyper+space"))
        XCTAssertNil(try owner("cmd+j"))
        // F-keys and 🌐 shortcuts cannot be skil.li's: left out.
        XCTAssertFalse(owners.contains { $0.name == "Show Desktop" || $0.name == "Fill" || $0.name == "Quick Note" })
    }

    func testTheFileSaysWhatIsOnAndItsKeys() throws {
        let hotKeys: [String: Any] = [
            "64": entry(enabled: 0, [32, 49, 1_048_576]),          // Spotlight off (JB's Mac, the mini)
            "65": entry(enabled: 1, [65535, 49, 1_572_864]),
            "60": entry(enabled: 0, [32, 49, 262_144]),
            "118": entry(enabled: 1, [65535, 18, 262_144]),        // Desktop 1 turned on
            "28": entry(enabled: 1, [100, 2, 1_179_648]),          // changed to ⇧⌘D
            "163": entry(enabled: 1, [109, 46, 1_572_864])         // given ⌥⌘M
        ]
        let owners = SystemShortcuts.owners(in: hotKeys, resolve: resolve)
        func owner(_ spec: String) throws -> KeyOwner? { KeyOwner.owner(of: [try chord(spec)], in: owners) }
        XCTAssertNil(try owner("cmd+space"), "turned off: ⌘Space is free")
        XCTAssertEqual(try owner("opt+cmd+space")?.name, "Show Finder search window")
        XCTAssertNil(try owner("ctrl+space"))
        XCTAssertEqual(try owner("ctrl+1")?.name, "Switch to Desktop 1")
        XCTAssertEqual(try owner("shift+cmd+d")?.name, "Save picture of screen as a file")
        XCTAssertNil(try owner("shift+cmd+3"), "its old keys are free")
        XCTAssertEqual(try owner("opt+cmd+m")?.name, "Show Notification Center")
    }

    /// A shortcut macOS keeps with its character is that character's key
    /// on any layout: on a French one, key code 46 types ",", and ⌘, stays
    /// free for Open Settings while ⌘M is Minimize.
    func testACharacterKeptWithTheShortcutWinsOverItsKeyCode() throws {
        func french(_ code: UInt16) -> Key? {
            [46: .character(","), 41: .character("m"), 49: .named(.space), 18: .character("1")][code]
        }
        let owners = SystemShortcuts.owners(in: ["118": entry(enabled: 1, [65535, 18, 262_144])], resolve: french)
        XCTAssertEqual(KeyOwner.owner(of: [try chord("cmd+m")], in: owners)?.name, "Minimize")
        XCTAssertNil(KeyOwner.owner(of: [try chord("cmd+,")], in: owners))
        XCTAssertEqual(KeyOwner.owner(of: [try chord("cmd+space")], in: owners)?.name, "Show Spotlight search")
        XCTAssertEqual(KeyOwner.owner(of: [try chord("ctrl+1")], in: owners)?.name, "Switch to Desktop 1", "no character: its key code")
        XCTAssertEqual(SymbolicHotKey.character("118", in: ["118": entry(enabled: 1, [65535, 18, 262_144])]), nil)
        XCTAssertEqual(SymbolicHotKey.character("28", in: ["28": entry(enabled: 1, [100, 2, 1_179_648])]), 100)
    }

    func testMacOSKeepsSomeForItself() throws {
        let owners = SystemShortcuts.owners(in: [:], resolve: resolve)
        let tab = KeyOwner.owner(of: [try chord("cmd+tab")], in: owners)
        XCTAssertEqual(tab?.name, "Switch apps")
        XCTAssertEqual(tab?.kind, .macOS(section: nil))
        XCTAssertEqual(tab?.refusal, "Used by macOS: Switch apps, which cannot be turned off.")
        XCTAssertEqual(KeyOwner.owner(of: [try chord("opt+cmd+escape")], in: owners)?.name, "Force Quit Applications")
    }

    /// macOS's Emoji & Symbols key goes to skil.li's emoji search, which
    /// does the same, and stays refused for anything else.
    func testEmojiSearchMayReplaceEmojiAndSymbols() throws {
        let owners = SystemShortcuts.owners(in: [:], resolve: resolve)
        let keys = [try chord("ctrl+cmd+space")]
        XCTAssertEqual(KeyOwner.owner(of: keys, in: owners)?.name, "Emoji & Symbols")
        XCTAssertEqual(KeyOwner.owner(of: keys, in: owners, for: "settings.open")?.name, "Emoji & Symbols")
        XCTAssertNil(KeyOwner.owner(of: keys, in: owners, for: SystemShortcuts.emojiSearch))
        XCTAssertNil(KeyOwner.owner(of: try Chord.sequence("ctrl+cmd+space e"), in: owners, for: SystemShortcuts.emojiSearch))
        XCTAssertEqual(KeyOwner.replaced(by: SystemShortcuts.emojiSearch, with: keys, in: owners)?.replaced,
                       "Replaces macOS's Emoji & Symbols.")
        XCTAssertNil(KeyOwner.replaced(by: "settings.open", with: keys, in: owners))
        // Only that one: the emoji search still cannot take Switch apps.
        XCTAssertEqual(KeyOwner.owner(of: [try chord("cmd+tab")], in: owners, for: SystemShortcuts.emojiSearch)?.name, "Switch apps")
    }

    /// Spotlight's ⌘Space goes to the launcher, which opens the same way
    /// (the welcome's choice), and stays refused for anything else.
    func testLauncherMayReplaceSpotlight() throws {
        let owners = SystemShortcuts.owners(in: [:], resolve: resolve)
        let keys = [try chord("cmd+space")]
        XCTAssertEqual(KeyOwner.owner(of: keys, in: owners)?.name, "Show Spotlight search")
        XCTAssertEqual(KeyOwner.owner(of: keys, in: owners, for: "clipboard.history")?.name, "Show Spotlight search")
        XCTAssertNil(KeyOwner.owner(of: keys, in: owners, for: SystemShortcuts.launcher))
        XCTAssertEqual(KeyOwner.replaced(by: SystemShortcuts.launcher, with: keys, in: owners)?.replaced,
                       "Replaces macOS's Show Spotlight search.")
        // Only that one: the launcher still cannot take Finder's search window.
        XCTAssertEqual(KeyOwner.owner(of: [try chord("opt+cmd+space")], in: owners, for: SystemShortcuts.launcher)?.name,
                       "Show Finder search window")
    }

    /// The input-source keys (⌃Space, ⌃⌥Space) and ⌘` are macOS's: a
    /// launcher on them would take them silently.
    func testInputSourcesAndWindowFocusAreMacOS() throws {
        let owners = SystemShortcuts.owners(in: [:], resolve: resolve)
        XCTAssertEqual(KeyOwner.owner(of: [try chord("ctrl+space")], in: owners)?.name, "Select the previous input source")
        XCTAssertEqual(KeyOwner.owner(of: [try chord("ctrl+opt+space")], in: owners)?.name, "Select next source in Input menu")
        XCTAssertEqual(KeyOwner.owner(of: [try chord("ctrl+space")], in: owners, for: SystemShortcuts.launcher)?.section, "Input Sources")
    }

    /// Spotlight's ⌘Space turned off and on again, its keys kept; a file
    /// without its entry gets macOS's default.
    func testSpotlightKeyTurnsOffAndOn() {
        let none: [String: Any] = [:]
        XCTAssertTrue(SystemShortcuts.spotlightTakesCommandSpace(in: none))
        let off = SystemShortcuts.settingSpotlightKey(on: false, in: none)
        XCTAssertFalse(SystemShortcuts.spotlightTakesCommandSpace(in: off))
        XCTAssertEqual((off["64"] as? [String: Any])?["enabled"] as? Bool, false)
        let on = SystemShortcuts.settingSpotlightKey(on: true, in: off)
        XCTAssertTrue(SystemShortcuts.spotlightTakesCommandSpace(in: on))
        // Moved to ⌥Space by the user: kept there, only switched.
        let moved: [String: Any] = ["64": ["enabled": true, "value": ["parameters": [32, 49, 524288], "type": "standard"]], "65": ["enabled": false]]
        let movedOff = SystemShortcuts.settingSpotlightKey(on: false, in: moved)
        XCTAssertEqual(((movedOff["64"] as? [String: Any])?["value"] as? [String: Any])?["parameters"] as? [Int], [32, 49, 524288])
        XCTAssertNotNil(movedOff["65"])
        XCTAssertFalse(SystemShortcuts.spotlightTakesCommandSpace(in: moved))
    }

    /// A chain that starts with a key someone else answers shares it.
    func testOnlyTheFirstKeyOfAChainCounts() throws {
        let owners = SystemShortcuts.owners(in: [:], resolve: resolve) + LauncherKeys.all
        XCTAssertEqual(KeyOwner.owner(of: try Chord.sequence("cmd+space space"), in: owners)?.name, "Show Spotlight search")
        XCTAssertEqual(KeyOwner.owner(of: try Chord.sequence("cmd+k x"), in: owners)?.name, "Actions")
        XCTAssertNil(KeyOwner.owner(of: try Chord.sequence("hyper+k cmd+space"), in: owners), "inside a chain skil.li has the keys")
        XCTAssertNil(KeyOwner.owner(of: [], in: owners))
    }

    func testRefusalsSayWhoAndWhereToFreeIt() throws {
        let spotlight = KeyOwner(chord: try chord("cmd+space"), name: "Show Spotlight search", kind: .macOS(section: "Spotlight"))
        XCTAssertEqual(spotlight.refusal,
                       "Used by macOS: Show Spotlight search. Turn it off in System Settings → Keyboard → Keyboard Shortcuts… → Spotlight.")
        XCTAssertEqual(spotlight.sharing, "macOS's Show Spotlight search has these keys too and no longer works. "
                       + "Turn it off in System Settings → Keyboard → Keyboard Shortcuts… → Spotlight, or choose other keys.")
        let actions = LauncherKeys.all.first { $0.chord == (try? self.chord("cmd+k")) }
        XCTAssertEqual(actions?.refusal, "Used by the launcher: Actions.")
        XCTAssertNil(actions?.section)
    }

    func testLauncherKeysAreRealChordsWithAModifier() throws {
        XCTAssertEqual(LauncherKeys.all.count, 12)
        XCTAssertEqual(Set(LauncherKeys.all.map(\.chord)).count, LauncherKeys.all.count, "each once")
        for owner in LauncherKeys.all {
            XCTAssertNotEqual(owner.chord.key, .named(.escape), "\(owner.name): its spec did not parse")
            XCTAssertFalse(owner.chord.modifiers.intersection([.command, .control, .option]).isEmpty, owner.name)
        }
    }

    func testTableIsMacOSOwn() {
        let ids = SystemShortcuts.table.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "each entry once")
        XCTAssertTrue(SystemShortcuts.table.filter(\.onByDefault).allSatisfy { $0.standard != nil })
        XCTAssertEqual(SystemShortcuts.table.first { $0.id == "64" }?.standard, SymbolicHotKey(keyCode: 49, modifiers: 1_048_576))
    }

    func testModifiersWithoutGlobe() {
        XCTAssertEqual(SymbolicHotKey(keyCode: 49, modifiers: 1_572_864).chordModifiers, [.option, .command])
        XCTAssertEqual(SymbolicHotKey(keyCode: 20, modifiers: 1_441_792).chordModifiers, [.control, .shift, .command])
        XCTAssertNil(SymbolicHotKey(keyCode: 123, modifiers: 8_650_752).chordModifiers, "🌐⌃←: skil.li has no 🌐")
    }
}
