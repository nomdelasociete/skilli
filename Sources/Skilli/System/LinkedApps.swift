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

    /// Its link, with what skil.li read for it; throws what is missing.
    @MainActor
    static func url(for command: AppLinkCommand, variant: AppLinkCommand.Variant?, frontWindow: () throws -> CGRect,
                    latestScreenshot: () -> URL?) throws -> URL {
        guard let app = command.app else { throw SystemCommands.Failure(message: "skil.li no longer knows “\(command.title)”.") }
        guard let installed = installed(app.id) else { throw SystemCommands.Failure(message: "\(app.name) is not installed on this Mac.") }
        guard command.runs(onVersion: installed.version), AppVersion.isAtLeast(installed.version, variant?.since) else {
            throw SystemCommands.Failure(message: "\(app.name) \(installed.version ?? "") does not take “\(variant?.title ?? command.title)”: update it.")
        }
        var extra: [AppLinkCommand.Parameter] = []
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
            guard CleanShot.imageExtensions.contains(file.pathExtension.lowercased()) else {
                throw SystemCommands.Failure(message: "\(app.name) opens PNG and JPEG images: “\(file.lastPathComponent)” is neither.")
            }
            extra = [.init("filepath", file.path)]
        }
        guard let url = command.url(variant: variant, extra: extra) else { throw SystemCommands.Failure(message: "“\(command.title)” has no link.") }
        return url
    }
}
