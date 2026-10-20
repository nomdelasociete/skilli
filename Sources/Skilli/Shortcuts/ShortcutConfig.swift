import Foundation
import SkilliCore

/// Every shortcut skil.li listens to, as saved in
/// `~/Library/Application Support/skil.li/shortcuts.json`.
///
/// Hand-editable: keys use the same spec as everywhere else
/// (`hyper+space`, `hyper+k u`, `cmd+shift+k`).
struct ShortcutConfig: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        /// Stable across edits; defaults use readable ids.
        var id: String
        var action: SkilliAction
        /// `nil` when the action has no shortcut.
        var keys: String?
        /// Shown in Settings and the leader overlay; `nil` uses the action's title.
        var label: String?

        var title: String { label ?? action.title }

        var chords: [Chord]? {
            keys.flatMap { try? Chord.sequence($0) }
        }
    }

    /// A named prefix, e.g. `hyper+k` → "Leader", titling its overlay.
    struct Group: Codable, Equatable {
        var keys: String
        var label: String
    }

    var version = 1
    var shortcuts: [Entry]
    var groups: [Group]
    /// Opens Settings while the launcher is open.
    var launcherOpenSettings: String?

    static let defaults = ShortcutConfig(
        shortcuts: [
            Entry(id: "launcher", action: .toggleLauncher, keys: "hyper+space", label: nil),
            Entry(id: "ai.ask", action: .aiPrompt("ask"), keys: "hyper+a", label: nil),
            Entry(id: "ai.voice", action: .askByVoice, keys: "hyper+v", label: nil),
            Entry(id: "dictate", action: .dictate, keys: "hyper+d", label: nil),
            Entry(id: "clipboard", action: .clipboardHistory, keys: "hyper+c", label: nil),
            // macOS's Emoji & Symbols key, as Raycast takes it: the same
            // thing, skil.li's picker instead (`KeyOwner.replacedBy`).
            Entry(id: "emoji", action: .searchEmoji, keys: "ctrl+cmd+space", label: nil),
            Entry(id: "settings", action: .openSettings, keys: nil, label: nil),
            Entry(id: "uppercase", action: .transformSelection(.uppercase), keys: "hyper+u", label: nil),
            Entry(id: "leader.uppercase", action: .transformSelection(.uppercase), keys: "hyper+k u", label: "UPPERCASE"),
            Entry(id: "leader.lowercase", action: .transformSelection(.lowercase), keys: "hyper+k l", label: "lowercase"),
            Entry(id: "leader.titlecase", action: .transformSelection(.capitalized), keys: "hyper+k t", label: "Title Case"),
            Entry(id: "leader.ai.fix", action: .aiPrompt("fix"), keys: "hyper+k g", label: nil),
            Entry(id: "leader.ai.improve", action: .aiPrompt("improve"), keys: "hyper+k i", label: nil),
            Entry(id: "leader.ai.english", action: .aiPrompt("english"), keys: "hyper+k e", label: nil),
            Entry(id: "leader.ai.french", action: .aiPrompt("french"), keys: "hyper+k r", label: nil),
            // Again and again: the next older copy each time.
            Entry(id: "leader.paste.sequence", action: .pasteInSequence, keys: "hyper+k v", label: nil),
            Entry(id: "leader.cleanshot.area", action: cleanShot("capture-area"), keys: "hyper+k c", label: "CleanShot · Capture Area"),
            Entry(id: "leader.cleanshot.fullscreen", action: cleanShot("capture-fullscreen"), keys: "hyper+k f", label: "CleanShot · Fullscreen"),
            Entry(id: "leader.cleanshot.scrolling", action: cleanShot("scrolling-capture"), keys: "hyper+k s", label: "CleanShot · Scrolling Capture")
        ] + windowDefaults,
        groups: [Group(keys: "hyper+k", label: "Leader"), Group(keys: "hyper+w", label: "Windows")],
        launcherOpenSettings: "cmd+,"
    )

    /// CleanShot X's command, as the launcher lists it.
    private static func cleanShot(_ path: String) -> SkilliAction {
        SkilliAction.appLink(url: "cleanshot://\(path)") ?? .openURL("cleanshot://\(path)")
    }

    /// ✦W then a key: arrows for halves (again for ⅔ and ⅓), F fills, C
    /// centers, U I J K the quarters (as on the keyboard), 1 2 3 the thirds,
    /// N and P the other displays, R back. The overlay lists them.
    private static let windowDefaults: [Entry] = [
        ("left", WindowLayout.leftHalf), ("right", .rightHalf), ("up", .topHalf), ("down", .bottomHalf),
        ("f", .maximize), ("a", .almostMaximize), ("c", .center),
        ("u", .topLeft), ("i", .topRight), ("j", .bottomLeft), ("k", .bottomRight),
        ("1", .leftThird), ("2", .centerThird), ("3", .rightThird), ("4", .leftTwoThirds), ("5", .rightTwoThirds),
        ("n", .nextDisplay), ("p", .previousDisplay), ("r", .restore)
    ].map { key, layout in
        Entry(id: "window.\(layout.rawValue)", action: .mac(.window(layout)), keys: "hyper+w \(key)", label: nil)
    }

    func defaultEntry(id: String) -> Entry? {
        Self.defaults.shortcuts.first { $0.id == id }
    }

    /// Chains saved before the engine's chain rule (`Chord.chain`) kept on
    /// their later chords what was still held from the first: Hyper
    /// (`hyper+k hyper+y`), ⌘ (`cmd+space cmd+space`). Written as the
    /// engine matches them, whichever way they are typed.
    func normalizingChains() -> ShortcutConfig {
        var config = self
        for index in config.shortcuts.indices {
            guard let chords = config.shortcuts[index].chords, chords.count > 1 else { continue }
            let chain = Chord.chain(chords)
            if chain != chords { config.shortcuts[index].keys = Chord.spec(chain) }
        }
        return config
    }

    /// Adds built-in entries introduced after this file was written, so an
    /// update brings its new shortcuts. Keys already taken stay with the
    /// user's binding; the new entry then starts without keys.
    func addingMissingDefaults() -> ShortcutConfig {
        var config = self
        for entry in Self.defaults.shortcuts where !config.shortcuts.contains(where: { $0.id == entry.id }) {
            var added = entry
            if let chords = entry.chords, config.shortcuts.contains(where: { other in
                guard let taken = other.chords else { return false }
                return taken.starts(with: chords) || chords.starts(with: taken)
            }) {
                added.keys = nil
            }
            config.shortcuts.append(added)
        }
        // New groups name their overlay ("Windows"), unless the prefix is
        // the user's own.
        for group in Self.defaults.groups where !config.groups.contains(where: { $0.keys == group.keys }) {
            config.groups.append(group)
        }
        return config
    }
}

enum ShortcutError: LocalizedError, Equatable {
    case needsModifier
    case conflict(with: String)
    /// macOS or the launcher answers the first key (`KeyOwner`).
    case taken(KeyOwner)
    case invalid

    var errorDescription: String? {
        switch self {
        case .needsModifier: "Start with ✦, ⌘, ⌃ or ⌥ so normal typing keeps working."
        case .conflict(let title): "Already used by “\(title)”."
        case .taken(let owner): owner.refusal
        case .invalid: "This key cannot be used in a shortcut."
        }
    }
}
