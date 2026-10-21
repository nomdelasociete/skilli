import AppKit
import Synchronization
import SkilliCore

/// The linked apps installed on this Mac (docs/apps.md), and their commands
/// run: what skil.li reads for one (the front window, the latest
/// screenshot) put in its link, then the link opened. The apps written in
/// files (`LinkedAppFile`) are read here too: skil.li's own, in its bundle's
/// `Apps` folder, then the user's.
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
    /// opens, with the radios; the app files first, when one changed.
    @discardableResult
    static func read() -> [Installed] {
        readFiles()
        let found = LinkedApp.all.compactMap { app -> Installed? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return nil }
            return Installed(app: app, url: url, version: Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String)
        }
        known.withLock { $0 = found }
        return found
    }

    /// The apps and versions as last read, and the files read, to see a
    /// change.
    static var summary: [String] {
        installed().map { "\($0.app.id) \($0.version ?? "")" } + ["files \(files.withLock { $0.generation })"]
    }

    // MARK: - App files

    /// Where the user's app files are: `~/Library/Application Support/skil.li/Apps`.
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li/Apps", isDirectory: true)
    }

    /// The user's folder (the self-test keeps its own; nil: none read).
    nonisolated(unsafe) static var folder: URL? = defaultFolder

    /// What the files gave, when they were read, and how often they changed.
    private static let files = Mutex<(stamp: [String: Date]?, problems: [LinkedAppFile.Problem], generation: Int)>((nil, [], 0))

    /// The files left out, with why, as last read (Settings → Apps).
    static var problems: [LinkedAppFile.Problem] {
        files.withLock { $0.problems }
    }

    /// The user's files by name, each with when it last changed.
    private static func userFiles() -> [String: Date] {
        guard let folder else { return [:] }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: .skipsHiddenFiles)) ?? []
        var found: [String: Date] = [:]
        for url in urls where url.pathExtension.lowercased() == "json" {
            found[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        return found
    }

    /// skil.li's own files, in its bundle.
    private static func shippedFiles() -> [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Apps") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Reads the app files again when one was added, changed or removed
    /// (`force`: whatever their dates); true when it read them. At launch
    /// before the shortcuts (a key names its command by id), then with the
    /// radios. Shortcuts and rows of an app whose file went stay until it
    /// comes back: nothing is deleted.
    @discardableResult
    static func readFiles(force: Bool = false) -> Bool {
        let stamp = userFiles()
        guard force || files.withLock({ $0.stamp }) != stamp else { return false }
        var sources = shippedFiles().compactMap { url in
            (try? Data(contentsOf: url)).map { LinkedAppFile.Source(name: url.lastPathComponent, data: $0, shipped: true) }
        }
        if let folder {
            for name in stamp.keys {
                let url = folder.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url) else { continue }
                sources.append(LinkedAppFile.Source(name: name, data: data, shipped: false))
            }
        }
        let loaded = LinkedAppFile.load(sources, symbolExists: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
        LinkedApp.useFiles(loaded.apps)
        files.withLock { $0 = (stamp, loaded.problems, $0.generation + 1) }
        for problem in loaded.problems {
            Log.trace("App file \(problem.file) left out: \(problem.message)")
        }
        return true
    }

    /// An app file checked as it would be read: the app it defines, or why
    /// it cannot join the apps known now. An app on this Mac must open the
    /// scheme the file gives it (its Info.plist says which).
    static func check(_ text: String) throws -> LinkedApp {
        let app: LinkedApp
        do {
            app = try LinkedAppFile.read(Data(text.utf8), file: "", symbolExists: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
        } catch {
            throw SystemCommands.Failure(message: error.message)
        }
        let fromFiles = LinkedApp.all.filter { other in !LinkedApp.builtIn.contains { $0.id == other.id } }
        if let clash = LinkedAppFile.clash(app, read: fromFiles) {
            throw SystemCommands.Failure(message: clash)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID), !opens(url, scheme: app.scheme) {
            throw SystemCommands.Failure(message: "\(app.name) does not open “\(app.scheme)” links: its scheme is another.")
        }
        return app
    }

    /// Whether the app at `url` says it opens `scheme` links.
    static func opens(_ url: URL, scheme: String) -> Bool {
        let types = Bundle(url: url)?.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains { $0.lowercased() == scheme } }
    }

    /// The user's Apps folder in Finder, made first when there is none.
    @MainActor
    static func revealFolder() {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Writes an app file in the user's folder (an agent's, an import) once
    /// it reads as an app no other one clashes with; "zed-2.json" when its
    /// name is taken by a file left out. Read again at once.
    @discardableResult
    static func add(_ text: String) throws -> LinkedApp {
        let app = try check(text)
        guard let folder else { throw SystemCommands.Failure(message: "No folder for app files.") }
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent("\(app.id).json")
        var index = 2
        while manager.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(app.id)-\(index).json")
            index += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        readFiles(force: true)
        read()
        Log.trace("App file \(url.lastPathComponent) added: \(app.name)")
        return LinkedApp.app(id: app.id) ?? app
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
