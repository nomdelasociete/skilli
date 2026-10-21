import AppKit
import SkilliCore

/// Everything a binding can trigger.
enum SkilliAction: Hashable, Sendable {
    case toggleLauncher
    case openSettings
    /// Read the selection in the frontmost app, transform it, paste it back.
    /// AI presets will be another transform source on the same pipeline.
    case transformSelection(TextTransform)
    /// Deep app actions through URL schemes, e.g. `cleanshot://capture-area`.
    case openURL(String)
    /// Launch or bring forward an app by bundle path.
    case openApp(String)
    /// Rewrite the selection with Claude using a prompt from `PromptLibrary`.
    case aiPrompt(String)
    /// Ask, with the instruction spoken.
    case askByVoice
    /// What the user says, typed at the caret of the app in front.
    case dictate
    /// The launcher, straight in the clipboard history.
    case clipboardHistory
    /// The launcher, straight in the emoji picker. The one action macOS's
    /// Emoji & Symbols key (⌃⌘Space) may be given to (`KeyOwner.replacedBy`).
    case searchEmoji
    /// The launcher, straight in the menu items of the app in front.
    case searchMenus
    /// The launcher, straight in Search GIFs.
    case searchGIFs
    /// The next older copy pasted, again and again (the newest first).
    case pasteInSequence
    /// A Mac command or a place for the front window (✦W ←).
    case mac(MacAction)
    /// A saved window layout, by its file id.
    case windowLayout(String)
    /// A launcher command: the mode it turns the launcher into ("Search
    /// Snippets"), or what its row does. The six that had a case of their
    /// own before keep it (`command(_:)`).
    case launcherCommand(LauncherCommand.ID)
    /// One of the user's snippets, by its file id: typed in the app in
    /// front, as ↩ on its row does.
    case snippet(String)
    /// One of the user's quicklinks: the launcher with its keyword typed,
    /// as its row picked by name puts it.
    case quicklink(UUID)

    /// A launcher command's action: the case it always had when it has one
    /// (✦C's `clipboardHistory`), else `launcherCommand`. Its id is the
    /// command's `shortcutID` either way.
    static func command(_ id: LauncherCommand.ID) -> SkilliAction {
        switch id {
        case .openSettings: .openSettings
        case .clipboardHistory: .clipboardHistory
        case .pasteInSequence: .pasteInSequence
        case .emoji: .searchEmoji
        case .searchGIFs: .searchGIFs
        case .searchMenus: .searchMenus
        default: .launcherCommand(id)
        }
    }

    /// Runs inside the event tap callback instead of after it. The launcher
    /// must be key before the next key event is routed, or the first letters
    /// typed after the hotkey land in the previous app.
    var runsInline: Bool {
        switch self {
        case .toggleLauncher, .clipboardHistory, .searchEmoji, .searchMenus, .searchGIFs, .quicklink: true
        case .launcherCommand(let id): LauncherController.mode(for: id) != nil
        default: false
        }
    }

    /// Stable, readable identifier used in `shortcuts.json`.
    var id: String {
        switch self {
        case .toggleLauncher: "launcher.toggle"
        case .openSettings: LauncherCommand.ID.openSettings.shortcutID
        case .transformSelection(let transform): "text.\(transform.rawValue)"
        case .openURL(let url): "url:\(url)"
        case .openApp(let path): "app:\(path)"
        case .aiPrompt(let prompt): "ai.\(prompt)"
        case .askByVoice: "voice.ask"
        case .dictate: "voice.dictate"
        case .clipboardHistory: LauncherCommand.ID.clipboardHistory.shortcutID
        case .searchEmoji: LauncherCommand.ID.emoji.shortcutID
        case .searchMenus: LauncherCommand.ID.searchMenus.shortcutID
        case .searchGIFs: LauncherCommand.ID.searchGIFs.shortcutID
        case .pasteInSequence: LauncherCommand.ID.pasteInSequence.shortcutID
        case .mac(.window(let layout)): "window.\(layout.rawValue)"
        case .mac(.system(let command)): "mac.\(command.rawValue)"
        case .mac(.sound(let target)): MacAction.sound(target).rawValue
        case .mac(.project(let project)): MacAction.project(project).rawValue
        case .mac(.script(let command)): MacAction.script(command).rawValue
        case .mac(.settings(let pane)): MacAction.settings(pane).rawValue
        // Not offered in Add Shortcut yet (a device read after shortcuts
        // load would be dropped); the id still says what it is.
        case .mac(let action): action.rawValue
        case .windowLayout(let id): "layout.\(id)"
        case .launcherCommand(let command): command.shortcutID
        // The launcher row's own ids ("snippet:<file id>").
        case .snippet(let id): "snippet:\(id)"
        case .quicklink(let id): "quicklink:\(id.uuidString)"
        }
    }

    init?(id: String) {
        switch id {
        case "launcher.toggle": self = .toggleLauncher
        case "voice.ask": self = .askByVoice
        case "voice.dictate": self = .dictate
        default:
            if let command = LauncherCommand.ID(shortcutID: id) {
                self = .command(command)
            } else if id.hasPrefix("snippet:"), id.count > 8 {
                self = .snippet(String(id.dropFirst(8)))
            } else if id.hasPrefix("quicklink:"), let link = UUID(uuidString: String(id.dropFirst(10))) {
                self = .quicklink(link)
            } else if id.hasPrefix("text."), let transform = TextTransform(rawValue: String(id.dropFirst(5))) {
                self = .transformSelection(transform)
            } else if id.hasPrefix("url:"), id.count > 4 {
                // A linked app's own link saved before its commands were
                // skil.li's (✦K C's "cleanshot://capture-area"): that command.
                let url = String(id.dropFirst(4))
                self = Self.appLink(url: url) ?? .openURL(url)
            } else if id.hasPrefix("app:"), id.count > 4 {
                self = .openApp(String(id.dropFirst(4)))
            } else if id.hasPrefix("ai."), id.count > 3 {
                self = .aiPrompt(String(id.dropFirst(3)))
            } else if id.hasPrefix("window.") || id.hasPrefix("sound.") || id.hasPrefix("project:") || id.hasPrefix("script:")
                        || id.hasPrefix("settings:") || id.hasPrefix("link:") || id.hasPrefix("shortcut:"), let action = MacAction(rawValue: id) {
                self = .mac(action)
            } else if id.hasPrefix("mac."), let command = SystemCommand(rawValue: String(id.dropFirst(4))) {
                self = .mac(.system(command))
            } else if id.hasPrefix("layout."), id.count > 7 {
                self = .windowLayout(String(id.dropFirst(7)))
            } else {
                return nil
            }
        }
    }

    /// Name shown in Settings and in the leader overlay.
    var title: String {
        switch self {
        case .toggleLauncher: "Open Launcher"
        case .openSettings: "Open Settings"
        case .transformSelection(let transform): transform.title
        case .openURL(let url): ActionCatalog.urlTitles[url] ?? url
        case .openApp(let path):
            FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        case .aiPrompt(let prompt): "\(Brand.intelligence) · \(PromptLibrary.shared.title(for: prompt))"
        case .askByVoice: "\(Brand.intelligence) · Ask by Voice"
        case .dictate: "Dictate"
        case .clipboardHistory: "Clipboard History"
        case .searchEmoji: "Search Emoji"
        case .searchMenus: "Search Menu Items"
        case .searchGIFs: "Search GIFs"
        case .pasteInSequence: "Paste in Sequence"
        // "Displays" alone says nothing in a list of shortcuts.
        case .mac(.settings(let pane)): "System Settings · \(pane.name)"
        // "CleanShot · Capture Area", "CleanShot · Capture Area · Copy".
        case .mac(.appLink(let command, let variant)):
            ([command.app?.shortName ?? "App", command.title] + (variant.flatMap(command.variant(id:)).map { [$0.label] } ?? []))
                .joined(separator: " · ")
        // "Shortcuts · Morning Routine · With the Selection".
        case .mac(.shortcut(let shortcut, let withSelection)):
            "Shortcuts · \(MacAction.shortcut(shortcut, withSelection: withSelection).title)"
        case .mac(let action): action.title
        case .windowLayout(let id): "Window Layout · \(id)"
        case .launcherCommand(let id): LauncherCommand.all.first { $0.id == id }?.title ?? id.rawValue
        case .snippet(let id): "Snippet · \(Self.snippetName(id) ?? id)"
        case .quicklink(let id): "Quicklink · \(Self.quicklinkName(id) ?? "deleted")"
        }
    }

    /// The names of what the user made, read as a title is shown: a
    /// snippet or quicklink renamed keeps its shortcut, under its new name.
    /// Set once by the app.
    nonisolated(unsafe) static var snippetName: (String) -> String? = { _ in nil }
    nonisolated(unsafe) static var quicklinkName: (UUID) -> String? = { _ in nil }
}

extension SkilliAction {
    /// The linked app's command a link of its own is: the command's link as
    /// written, or with one of its variants' parameters
    /// ("cleanshot://capture-area?action=copy"). Nil for any other link.
    static func appLink(url: String) -> SkilliAction? {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(), let path = components.host,
              let app = LinkedApp.all.first(where: { $0.scheme == scheme }) else { return nil }
        let query = (components.queryItems ?? []).map { AppLinkCommand.Parameter($0.name, $0.value ?? "") }
        for command in app.commands where command.path == path && command.input == .none {
            if query.isEmpty { return .mac(.appLink(command, variant: nil)) }
            if let variant = command.variants.first(where: { $0.query == query }) { return .mac(.appLink(command, variant: variant.id)) }
        }
        return nil
    }
}

extension SkilliAction: Codable {
    init(from decoder: Decoder) throws {
        let id = try decoder.singleValueContainer().decode(String.self)
        guard let action = SkilliAction(id: id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown action \(id)"))
        }
        self = action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// Actions offered by "Add Shortcut" in Settings.
enum ActionCatalog {
    static let urlTitles: [String: String] = [
        "cleanshot://capture-area": "CleanShot · Capture Area",
        "cleanshot://capture-previous-area": "CleanShot · Capture Previous Area",
        "cleanshot://capture-fullscreen": "CleanShot · Capture Fullscreen",
        "cleanshot://capture-window": "CleanShot · Capture Window",
        "cleanshot://scrolling-capture": "CleanShot · Scrolling Capture",
        "cleanshot://all-in-one": "CleanShot · All-In-One",
        "cleanshot://self-timer": "CleanShot · Self-Timer"
    ]

    static let general: [SkilliAction] = [
        .toggleLauncher,
        .openSettings,
        .askByVoice,
        .dictate,
        .clipboardHistory,
        .pasteInSequence,
        .searchEmoji,
        .searchGIFs,
        .searchMenus,
        .transformSelection(.uppercase),
        .transformSelection(.lowercase),
        .transformSelection(.capitalized)
    ]

    /// Every launcher command, under the Catalog's groups (Find, Do…), in
    /// its order: the "?" lists them so.
    static let launcherCommands: [(group: String, actions: [SkilliAction])] =
        FeatureCatalog.sections(FeatureCatalog.entries().filter { if case .command = $0.run { true } else { false } }).map { section in
            (section.group.title, section.entries.compactMap { entry in
                if case .command(let id) = entry.run { SkilliAction.command(id) } else { nil }
            })
        }

    static let windows: [SkilliAction] = WindowLayout.allCases.map { .mac(.window($0)) }

    static let mac: [SkilliAction] = SystemCommand.allCases.map { .mac(.system($0)) }

    /// The sound outputs and microphones connected now.
    static func sound() -> [SkilliAction] {
        MacAction.sounds().map(SkilliAction.mac)
    }

    /// System Settings' panes on this Mac ("Displays").
    static func settingsPanes() -> [SkilliAction] {
        MacAction.settingsPanes().map(SkilliAction.mac)
    }

    static var ai: [SkilliAction] {
        PromptLibrary.shared.all.map { .aiPrompt($0.id) }
    }

    /// The installed linked apps' commands (CleanShot X), each followed by
    /// its variants ("Capture Area · Copy").
    static func appLinks() -> [SkilliAction] {
        MacAction.appLinks().flatMap { action -> [SkilliAction] in
            guard case .appLink(let command, _) = action else { return [] }
            return [.mac(action)] + LinkedApps.variants(of: command).map { .mac(.appLink(command, variant: $0.id)) }
        }
    }

    /// The user's shortcuts in Apple's Shortcuts app, each followed by its
    /// run on the selection.
    static func appleShortcuts() -> [SkilliAction] {
        AppleShortcuts.all().flatMap { shortcut -> [SkilliAction] in
            [.mac(.shortcut(shortcut, withSelection: false)), .mac(.shortcut(shortcut, withSelection: true))]
        }
    }
}
