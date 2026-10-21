import AppKit
import Synchronization
import SkilliCore

/// The linked apps installed on this Mac (docs/apps.md), and their commands
/// run: what skil.li reads for one (the front window, the latest
/// screenshot) put in its link, then the link opened.
enum LinkedApps {
    struct Installed: Sendable {
        let app: LinkedApp
        let url: URL
        /// CFBundleShortVersionString: "5.0.1".
        let version: String?
    }

    /// What the last read found: a key never asks LaunchServices, whose
    /// first answer takes ~15 ms (then ~0.05 ms).
    private static let known = Mutex<[Installed]?>(nil)

    /// Each linked app LaunchServices knows, as last read (`read`); read
    /// now only before the first one.
    static func installed() -> [Installed] {
        known.withLock { $0 } ?? read()
    }

    /// Reads them again: off the main thread at launch and as the launcher
    /// opens, with the radios.
    @discardableResult
    static func read() -> [Installed] {
        let found = LinkedApp.all.compactMap { app -> Installed? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return nil }
            return Installed(app: app, url: url, version: Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String)
        }
        known.withLock { $0 = found }
        return found
    }

    /// The apps and versions as last read, to see a change.
    static var summary: [String] {
        installed().map { "\($0.app.id) \($0.version ?? "")" }
    }

    static func installed(_ appID: String) -> Installed? {
        installed().first { $0.app.id == appID }
    }

    /// Every command the installed apps' versions take, with the variants
    /// they take.
    static func commands() -> [MacAction] {
        installed().flatMap { installed in
            installed.app.commands.filter { $0.runs(onVersion: installed.version) }.map { MacAction.appLink($0, variant: nil) }
        }
    }

    /// The variants of `command` the installed version takes.
    static func variants(of command: AppLinkCommand) -> [AppLinkCommand.Variant] {
        command.variants(forVersion: installed(command.appID)?.version)
    }

    /// The app itself, as the Dock opens it: where the user turns on what
    /// lets skil.li drive it (its own link to its settings needs that on
    /// already).
    @MainActor
    static func open(_ installed: Installed) {
        NSWorkspace.shared.openApplication(at: installed.url, configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor private static var icons: [String: NSImage] = [:]

    /// The app's own icon, as rows show apps' (32 pt).
    @MainActor
    static func icon(for appID: String) -> NSImage? {
        if let icon = icons[appID] { return icon }
        guard let url = installed(appID)?.url else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        icons[appID] = icon
        return icon
    }

    /// What the installed apps do with `file` (⌘K on a clipboard image or
    /// a file found): only what its type and their versions take.
    static func fileActions(for file: URL) -> [(action: LinkedApp.FileAction, command: AppLinkCommand)] {
        installed().flatMap { $0.app.fileActions(opening: file.path, version: $0.version) }
    }

    /// Its link, with what skil.li read for it, or `file` (⌘K on a file,
    /// an agent's) in place of what its input reads; throws what is missing.
    @MainActor
    static func url(for command: AppLinkCommand, variant: AppLinkCommand.Variant?, file: URL? = nil, frontWindow: () throws -> CGRect,
                    latestScreenshot: () -> URL?, finderSelection: () throws -> URL) throws -> URL {
        guard let app = command.app else { throw SystemCommands.Failure(message: "skil.li no longer knows “\(command.title)”.") }
        guard let installed = installed(app.id) else { throw SystemCommands.Failure(message: "\(app.name) is not installed on this Mac.") }
        guard command.runs(onVersion: installed.version), AppVersion.isAtLeast(installed.version, variant?.since) else {
            throw SystemCommands.Failure(message: "\(app.name) \(installed.version ?? "") does not take “\(variant?.title ?? command.title)”: update it.")
        }
        /// `filepath`, once its type is one the link takes.
        func filepath(_ file: URL) throws -> [AppLinkCommand.Parameter] {
            guard let files = command.files else { throw SystemCommands.Failure(message: "“\(command.title)” takes no file.") }
            guard files.contains(file.lastPathComponent) else {
                throw SystemCommands.Failure(message: "“\(command.title)” opens \(files.said): “\(file.lastPathComponent)” is not one.")
            }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
                throw SystemCommands.Failure(message: "“\(file.lastPathComponent)” is no longer at \(file.deletingLastPathComponent().path).")
            }
            return [.init("filepath", file.path)]
        }
        var extra: [AppLinkCommand.Parameter] = []
        if let file {
            extra = try filepath(file)
        } else {
            switch command.input {
            case .none:
                break
            case .frontWindow:
                let frame = try frontWindow()
                guard let place = CleanShot.frame(of: frame, screens: NSScreen.screens.map(\.frame)) else {
                    throw SystemCommands.Failure(message: "The window in front is on no display.")
                }
                extra = place
            case .latestScreenshot:
                guard let file = latestScreenshot() else { throw SystemCommands.Failure(message: "No screenshot found to open in \(app.name).") }
                extra = try filepath(file)
            case .finderSelection:
                extra = try filepath(finderSelection())
            }
        }
        guard let url = command.url(variant: variant, extra: extra) else { throw SystemCommands.Failure(message: "“\(command.title)” has no link.") }
        return url
    }
}
