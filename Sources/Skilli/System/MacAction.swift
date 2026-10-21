import Foundation
import SkilliCore

/// Something skil.li does on the Mac itself: a Mac command (lock, dark
/// mode…), a place for the front window, a sound device to switch to, a
/// recent project to open in its editor, or a pane of System Settings to
/// open. One list for the launcher, Ask's decisions, agents and shortcuts.
enum MacAction: Hashable, Sendable {
    case system(SystemCommand)
    case window(WindowLayout)
    case sound(AudioTarget)
    case project(EditorProject)
    /// A skillie with no argument it needs.
    case script(ScriptCommand)
    /// A pane of System Settings ("Displays").
    case settings(SystemSettingsPane)
    /// A Bluetooth device paired with this Mac, to connect or disconnect.
    case bluetooth(BluetoothTarget, connect: Bool)
    /// The output volume at a level, 0…100 ("volume 30").
    case volume(Int)
    /// A command of an app skil.li drives through its links (CleanShot X's
    /// Capture Area), and one of its variants ("copy": the capture copied).
    case appLink(AppLinkCommand, variant: String?)
    /// One of the user's shortcuts in Apple's Shortcuts app; with the
    /// selection as its input, read where it runs.
    case shortcut(AppleShortcut, withSelection: Bool)

    /// Commands and window places: the same on every Mac.
    static let all: [MacAction] = SystemCommand.allCases.map(MacAction.system) + WindowLayout.allCases.map(MacAction.window)

    /// The sound outputs and microphones connected now.
    static func sounds() -> [MacAction] {
        let devices = AudioDevices.all()
        return devices.filter(\.hasOutput).map { .sound(AudioTarget($0, output: true)) }
            + devices.filter(\.hasInput).map { .sound(AudioTarget($0, output: false)) }
    }

    /// The Bluetooth accessories paired with this Mac (not computers,
    /// phones or watches), as last read: each offered the other way from
    /// where it is (connected: Disconnect).
    static func bluetoothDevices() -> [MacAction] {
        BluetoothDevices.cached.filter(\.kind.isAccessory).map { .bluetooth(BluetoothTarget($0), connect: !$0.connected) }
    }

    /// System Settings' panes on this Mac.
    static func settingsPanes() -> [MacAction] {
        SystemSettingsPanes.all().map(MacAction.settings)
    }

    /// The commands of the linked apps installed (CleanShot X), each the
    /// command itself, not a variant.
    static func appLinks() -> [MacAction] {
        LinkedApps.commands()
    }

    /// The user's shortcuts as last read (`AppleShortcuts.read`), each run
    /// as it is.
    static func appleShortcuts() -> [MacAction] {
        AppleShortcuts.all().map { .shortcut($0, withSelection: false) }
    }

    /// The variant an `appLink` names, when it names one the command has.
    var appLinkVariant: AppLinkCommand.Variant? {
        guard case .appLink(let command, let variant?) = self else { return nil }
        return command.variant(id: variant)
    }

    /// Stable id: a Mac command's own ("lockScreen", as before windows
    /// existed), "window.leftHalf" for a window, "sound.output.<uid>" for a
    /// device.
    var rawValue: String {
        switch self {
        case .system(let command): command.rawValue
        case .window(let layout): "window.\(layout.rawValue)"
        case .sound(let target): "sound.\(target.output ? "output" : "input").\(target.uid)"
        case .project(let project): "project:\(project.bundleID):\(project.path)"
        case .script(let command): "script:\(command.path)"
        case .settings(let pane): "settings:\(pane.id)"
        // One id per device, whichever way it goes: the launcher learns the
        // device, and offers it the way it can go then.
        case .bluetooth(let target, _): "bluetooth.\(target.address)"
        case .volume(let level): "volume.\(level)"
        // "link:cleanshot.capture-area", "link:cleanshot.capture-area/copy".
        case .appLink(let command, let variant): "link:\(command.id)" + (variant.map { "/\($0)" } ?? "")
        // By Shortcuts' identifier: renamed, it keeps its keys and alias.
        case .shortcut(let shortcut, let withSelection): "shortcut:\(shortcut.id)" + (withSelection ? "/selection" : "")
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix("shortcut:") {
            // Its name as last read, if read: it runs by its identifier.
            let parts = rawValue.dropFirst(9).split(separator: "/", maxSplits: 1).map(String.init)
            guard let id = parts.first, UUID(uuidString: id) != nil, parts.count == 1 || parts[1] == "selection" else { return nil }
            self = .shortcut(AppleShortcuts.current(AppleShortcut(id: id, name: "")), withSelection: parts.count > 1)
        } else if rawValue.hasPrefix("link:") {
            let parts = rawValue.dropFirst(5).split(separator: "/", maxSplits: 1).map(String.init)
            guard let id = parts.first, let command = LinkedApp.command(id: id) else { return nil }
            let variant = parts.count > 1 ? parts[1] : nil
            if let variant, command.variant(id: variant) == nil { return nil }
            self = .appLink(command, variant: variant)
        } else if rawValue.hasPrefix("bluetooth.") {
            let address = String(rawValue.dropFirst(10))
            guard let device = BluetoothDevices.cached.first(where: { $0.address == address }) else { return nil }
            self = .bluetooth(BluetoothTarget(device), connect: !device.connected)
        } else if rawValue.hasPrefix("volume.") {
            guard let level = Int(rawValue.dropFirst(7)), (0...100).contains(level) else { return nil }
            self = .volume(level)
        } else if rawValue.hasPrefix("settings:") {
            guard let pane = SystemSettingsPanes.pane(id: String(rawValue.dropFirst(9))) else { return nil }
            self = .settings(pane)
        } else if rawValue.hasPrefix("script:") {
            // Read again from its file: the title or mode may have changed.
            let path = String(rawValue.dropFirst(7))
            guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
            defer { try? handle.close() }
            let head = String(decoding: (try? handle.read(upToCount: 8_192)) ?? Data(), as: UTF8.self)
            guard let command = ScriptCommand.parse(head, path: path) else { return nil }
            self = .script(command)
        } else if rawValue.hasPrefix("project:") {
            // "project:<bundle id>:<path>": bundle ids have no colon.
            let rest = rawValue.dropFirst(8)
            guard let colon = rest.firstIndex(of: ":") else { return nil }
            let bundleID = String(rest[..<colon])
            let path = String(rest[rest.index(after: colon)...])
            guard path.hasPrefix("/") else { return nil }
            let editor = EditorProjects.editors.first { $0.bundleID == bundleID }?.name ?? bundleID
            self = .project(EditorProject(path: path, kind: path.hasSuffix(".code-workspace") ? .workspace : .folder,
                                          editor: editor, bundleID: bundleID, rank: 0))
        } else if rawValue.hasPrefix("sound.output.") || rawValue.hasPrefix("sound.input.") {
            let output = rawValue.hasPrefix("sound.output.")
            let uid = String(rawValue.dropFirst(output ? 13 : 12))
            guard !uid.isEmpty else { return nil }
            // A device not connected now keeps its id; its name comes back with it.
            let device = AudioDevices.all().first { $0.uid == uid }
            self = .sound(AudioTarget(uid: uid, name: device?.name ?? uid, transport: device?.transport ?? .other, output: output))
        } else if rawValue.hasPrefix("window.") {
            guard let layout = WindowLayout(rawValue: String(rawValue.dropFirst(7))) else { return nil }
            self = .window(layout)
        } else {
            guard let command = SystemCommand(rawValue: rawValue) else { return nil }
            self = .system(command)
        }
    }

    var title: String {
        switch self {
        case .system(let command): command.title
        case .window(let layout): layout.title
        case .sound(let target): AudioRoute.title(name: target.name, output: target.output)
        case .project(let project): "Open “\(project.name)” in \(project.editor)"
        case .script(let command): command.title
        case .settings(let pane): pane.name
        case .bluetooth(let target, let connect): BluetoothRoute.title(name: target.name, connect: connect)
        case .volume(let level): VolumeRequest.title(level)
        case .appLink(let command, _): appLinkVariant?.title ?? command.title
        case .shortcut(let shortcut, let withSelection): AppleShortcuts.name(of: shortcut) + (withSelection ? " · With the Selection" : "")
        }
    }

    /// What the row is called: its title, and a pane's name in the user's
    /// other languages ("Moniteurs", "Displays"). Typed whole, it ranks the
    /// row first (`LauncherRank`); keywords only lead to it.
    var names: [String] {
        if case .settings(let pane) = self { return [pane.name] + pane.otherNames }
        return [title]
    }

    var keywords: [String] {
        switch self {
        case .system(let command): command.keywords
        case .window(let layout): layout.keywords
        case .sound(let target): AudioRoute.keywords(transport: target.transport, output: target.output)
        case .project: ["project", "projet", "code"]
        case .script(let command): [command.packageName, "skillie"]
        // "display settings" (its names are `names`); "réglages bluetooth"
        // is matched on what follows the word
        // (`SystemSettingsPane.paneQuery`), the sections apart, strictly
        // (`sectionKeywords`).
        case .settings(let pane):
            ([pane.name] + pane.otherNames).map { "\($0) settings" }
        case .bluetooth(let target, let connect): BluetoothRoute.keywords(kind: target.kind, connect: connect)
        case .volume: ["volume", "son", "sound"]
        case .appLink(let command, _): command.keywords
        case .shortcut: AppleShortcut.keywords
        }
    }

    /// What a pane holds ("Night Shift"): many long phrases, so the
    /// launcher counts only queries made of their words' starts
    /// (`FuzzyMatcher.matchesWordStarts`).
    var sectionKeywords: [String] {
        if case .settings(let pane) = self { return pane.sections }
        return []
    }

    var description: String {
        switch self {
        case .system(let command): command.description
        case .window(let layout): layout.description
        case .sound(let target): AudioRoute.description(name: target.name, transport: target.transport, output: target.output)
        case .project(let project): "Open the code project “\(project.name)” (in \(project.folder())) in \(project.editor), to work on it"
        case .script(let command): "Run the user's own command “\(command.title)”" + (command.description.isEmpty ? "" : ": \(command.description)")
        case .settings(let pane):
            "The \(pane.name)" + (pane.otherNames.isEmpty ? "" : " (\(pane.otherNames.joined(separator: ", ")))")
                + " pane of System Settings" + (pane.sections.isEmpty ? "" : ": \(pane.sections.prefix(16).joined(separator: ", "))")
        case .bluetooth(let target, let connect): BluetoothRoute.description(name: target.name, kind: target.kind, connect: connect)
        case .volume(let level): "Set the sound's volume to \(level) %"
        case .appLink(let command, _):
            "\(command.app?.name ?? "An app"): \(command.oneLine)" + (appLinkVariant.map { " (\($0.title))" } ?? "")
        case .shortcut(let shortcut, let withSelection):
            "Run the user's shortcut “\(AppleShortcuts.name(of: shortcut))” (Apple's Shortcuts app)" + (withSelection ? ", on the selected text" : "")
        }
    }

    var symbol: String {
        switch self {
        case .system(let command): command.symbol
        case .window(let layout): layout.symbol
        case .sound(let target): AudioRoute.symbol(name: target.name, transport: target.transport, output: target.output)
        case .project: "chevron.left.forwardslash.chevron.right"
        case .script: "terminal"
        case .settings: "gearshape"
        case .bluetooth(let target, _): BluetoothRoute.symbol(name: target.name, kind: target.kind)
        case .volume: "speaker.wave.2.fill"
        case .appLink(let command, _): appLinkVariant?.symbol ?? command.symbol
        case .shortcut: FeatureCatalog.shortcutSymbol
        }
    }

    /// The launcher's accessory: "Mac", "Window" or "Sound".
    var kind: String {
        switch self {
        case .system: "Mac"
        case .window: "Window"
        case .sound: "Sound"
        case .project: "Project"
        case .script: "Skillie"
        case .settings: "System Settings"
        case .bluetooth: "Bluetooth"
        case .volume: "Sound"
        case .appLink(let command, _): command.app?.name ?? "App"
        case .shortcut: "Shortcuts"
        }
    }
}

/// A Bluetooth device paired with this Mac, by its address (stable); the
/// name and kind say it in words. Equal by address.
struct BluetoothTarget: Hashable, Sendable {
    let address: String
    let name: String
    let kind: BluetoothRoute.Kind

    init(address: String, name: String, kind: BluetoothRoute.Kind) {
        self.address = address
        self.name = name
        self.kind = kind
    }

    init(_ device: BluetoothDevices.Device) {
        self.init(address: device.address, name: device.name, kind: device.kind)
    }

    static func == (lhs: BluetoothTarget, rhs: BluetoothTarget) -> Bool {
        lhs.address == rhs.address
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(address)
    }
}

/// A sound output or microphone to switch to, by CoreAudio's UID (stable
/// across reconnections); the name and kind say it in words. Equal by UID
/// and direction.
struct AudioTarget: Hashable, Sendable {
    let uid: String
    let name: String
    let transport: AudioRoute.Transport
    let output: Bool

    init(uid: String, name: String, transport: AudioRoute.Transport, output: Bool) {
        self.uid = uid
        self.name = name
        self.transport = transport
        self.output = output
    }

    init(_ device: AudioDevices.Device, output: Bool) {
        self.init(uid: device.uid, name: device.name, transport: device.transport, output: output)
    }

    static func == (lhs: AudioTarget, rhs: AudioTarget) -> Bool {
        lhs.uid == rhs.uid && lhs.output == rhs.output
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
        hasher.combine(output)
    }
}
