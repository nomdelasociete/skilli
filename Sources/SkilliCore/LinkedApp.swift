import CoreGraphics
import Foundation
import Synchronization

/// An app skil.li drives through its own links (`cleanshot://capture-area`):
/// each of its commands is a launcher row, a Catalog entry, a key and an
/// agent action while the app is installed (docs/apps.md). Only links the
/// app documents itself; CleanShot X's own windows do the work. CleanShot X
/// is written here; the others come from app files (`LinkedAppFile`):
/// skil.li's own, shipped with it, and the user's.
public struct LinkedApp: Identifiable, Sendable {
    /// Short and stable: commands are "<id>.<command>" ("cleanshot.capture-area").
    public let id: String
    public let name: String
    /// Before a command's title in a list of shortcuts: "CleanShot ·
    /// Capture Area".
    public let shortName: String
    public let bundleID: String
    public let scheme: String
    public let commands: [AppLinkCommand]
    /// Its commands as Settings → Apps lists them, under a title each.
    public let groups: [CommandGroup]
    /// Where the user lets other apps drive it, in the user's words, when
    /// the app asks for that. Nothing on the Mac says whether it is on:
    /// CleanShot keeps its switch out of its defaults and ignores links
    /// while it is off, asking nothing (checked on CleanShot X 5.0.1).
    public let allowance: String?
    /// ⌘K on a file skil.li lists (an image in the clipboard history, a
    /// file found): what the app does with it, offered where its type fits.
    public let fileActions: [FileAction]
    /// The oldest version its links work on; nil: any.
    public let minimumVersion: String?
    /// Where the app documents its links ("https://…"), shown on its page.
    public let documentation: String?
    /// Where it was read: nil for skil.li's own (CleanShot X, the files
    /// shipped with it), the file's name for the user's ("Zed.json").
    public let file: String?

    public init(id: String, name: String, shortName: String, bundleID: String, scheme: String, commands: [AppLinkCommand],
                groups: [CommandGroup], allowance: String? = nil, fileActions: [FileAction] = [], minimumVersion: String? = nil,
                documentation: String? = nil, file: String? = nil) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.bundleID = bundleID
        self.scheme = scheme
        self.commands = commands
        self.groups = groups
        self.allowance = allowance
        self.fileActions = fileActions
        self.minimumVersion = minimumVersion
        self.documentation = documentation
        self.file = file
    }

    /// One of the app's commands on a file skil.li already has: "Pin in
    /// CleanShot" runs `cleanshot.pin` with it.
    public struct FileAction: Sendable {
        /// The command's name after the app's id ("pin").
        public let command: String
        /// As ⌘K lists it, the app named: "Pin in CleanShot".
        public let title: String
        public let symbol: String
    }

    /// The file actions that open `file` (by its extension) on the
    /// installed version, each with its command.
    public func fileActions(opening file: String, version: String?) -> [(action: FileAction, command: AppLinkCommand)] {
        fileActions.compactMap { action in
            guard let command = commands.first(where: { $0.id == "\(id).\(action.command)" }), command.runs(onVersion: version),
                  command.files?.contains(file) == true else { return nil }
            return (action, command)
        }
    }

    /// A few of an app's commands under one title ("Capture"), by their
    /// name after the app's id ("capture-area").
    public struct CommandGroup: Sendable, Equatable {
        public let title: String
        public let commands: [String]

        public init(title: String, commands: [String]) {
            self.title = title
            self.commands = commands
        }
    }

    /// The commands of each group, in its order.
    public var grouped: [(title: String, commands: [AppLinkCommand])] {
        groups.map { group in
            (group.title, group.commands.compactMap { name in commands.first { $0.id == "\(id).\(name)" } })
        }
    }

    /// The apps written here: they win over any file that names their id,
    /// bundle id or scheme.
    public static let builtIn: [LinkedApp] = [.cleanShot]

    /// Read from app files (`LinkedAppFile.load`), set once they are read:
    /// at launch before the shortcuts, then again when a file changed.
    private static let fromFiles = Mutex<[LinkedApp]>([])

    /// Every app skil.li knows how to drive, installed or not: the built-in
    /// ones, then the files' in the order they were read.
    public static var all: [LinkedApp] {
        builtIn + fromFiles.withLock { $0 }
    }

    /// The apps the files define now (already checked against the
    /// built-in ones and each other).
    public static func useFiles(_ apps: [LinkedApp]) {
        fromFiles.withLock { $0 = apps }
    }

    public static func app(id: String) -> LinkedApp? {
        all.first { $0.id == id }
    }

    /// "cleanshot.capture-area": the app's command by its full id.
    public static func command(id: String) -> AppLinkCommand? {
        guard let dot = id.firstIndex(of: ".") else { return nil }
        return app(id: String(id[..<dot]))?.commands.first { $0.id == id }
    }

    /// The command (and variant) a raw link runs when its app's file says
    /// it asks first: an agent's `open_url` cannot go round it. Its scheme
    /// and path, and the variant's parameters among the link's, any case;
    /// nil when nothing in it asks.
    public static func asksFirst(_ url: URL) -> (command: AppLinkCommand, variant: AppLinkCommand.Variant?)? {
        guard let scheme = url.scheme?.lowercased(), let app = all.first(where: { $0.scheme == scheme }) else { return nil }
        let given = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { "\($0.name.lowercased())=\(($0.value ?? "").lowercased())" }
        for command in app.commands {
            guard let own = command.url(), Self.samePath(own, url) else { continue }
            if command.asksFirst { return (command, nil) }
            if let variant = command.variants.first(where: { $0.asksFirst && $0.query.allSatisfy { given.contains("\($0.name.lowercased())=\($0.value.lowercased())") } }) {
                return (command, variant)
            }
        }
        return nil
    }

    private static func samePath(_ one: URL, _ other: URL) -> Bool {
        func trimmed(_ path: String) -> String { path.hasSuffix("/") ? String(path.dropLast()) : path }
        return one.host()?.lowercased() == other.host()?.lowercased() && trimmed(one.path()) == trimmed(other.path())
    }
}

/// One command of a linked app: its link's path, and what skil.li adds to
/// it before it opens (the front window's frame, the latest screenshot).
public struct AppLinkCommand: Hashable, Sendable {
    /// What skil.li reads first and puts in the link.
    public enum Input: Hashable, Sendable {
        case none
        /// The front window's frame, as `x`, `y`, `width`, `height`, `display`.
        case frontWindow
        /// The newest screenshot's file, as `filepath`.
        case latestScreenshot
        /// The file selected in Finder, as `filepath`.
        case finderSelection
    }

    /// The files a link's `filepath` takes, by extension, and how the user
    /// reads them ("PNG and JPEG images").
    public struct FileTypes: Hashable, Sendable {
        /// Lowercased, without the dot: "png".
        public let extensions: Set<String>
        public let said: String

        public init(_ extensions: Set<String>, said: String) {
            self.extensions = extensions
            self.said = said
        }

        /// A path or a file name, by its extension in any case
        /// ("Shot.PNG"); none takes no type.
        public func contains(_ file: String) -> Bool {
            let name = file.split(separator: "/").last.map(String.init) ?? file
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
            return extensions.contains(name[name.index(after: dot)...].lowercased())
        }
    }

    /// The same command with more said: "Capture Area" then copy
    /// (`action=copy`). ⌘K lists them; a key can be given one.
    public struct Variant: Hashable, Sendable {
        /// Its part of the id ("copy"): "cleanshot.capture-area/copy".
        public let id: String
        /// As ⌘K lists it: "Capture and Copy".
        public let title: String
        /// After the command's title, where it is not under its row:
        /// "Capture Area · Copy".
        public let label: String
        public let symbol: String
        public let query: [Parameter]
        /// The app's version that first took these parameters.
        public let since: String?
        /// Asked first in skil.li's card when a link, Ask or an agent runs
        /// it (CleanShot's upload: the capture leaves the Mac); never
        /// trusted with Always. Picked in the launcher or on a key, it runs.
        public let asksFirst: Bool

        public init(id: String, title: String, label: String, symbol: String, query: [Parameter], since: String? = nil, asksFirst: Bool = false) {
            self.id = id
            self.title = title
            self.label = label
            self.symbol = symbol
            self.query = query
            self.since = since
            self.asksFirst = asksFirst
        }
    }

    /// A link's parameter, in the order written.
    public struct Parameter: Hashable, Sendable {
        public let name: String
        public let value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    /// "cleanshot.capture-area": the app's id, a dot, the command's name.
    public let id: String
    /// The link after its scheme: its host (`capture-area` in
    /// `cleanshot://capture-area`), then a path (`zoom.us/join`); one that
    /// starts with "/" has no host (`msteams:/l/meeting/new`).
    public let path: String
    public let title: String
    /// What it does, in one line of the user's words (Catalog, Ask).
    public let oneLine: String
    public let symbol: String
    /// Other words people type, in English and French.
    public let keywords: [String]
    public let input: Input
    public let variants: [Variant]
    /// The app's version that first took what `input` adds.
    public let since: String?
    /// The files its link takes as `filepath`; nil: none. An agent's
    /// `file` goes there, instead of what `input` reads (or the app asks).
    public let files: FileTypes?
    /// Parameters every run of it gives, before a variant's.
    public let query: [Parameter]
    /// Asked first when a link, Ask or an agent runs it (`Variant.asksFirst`).
    public let asksFirst: Bool

    public init(id: String, path: String, title: String, oneLine: String, symbol: String, keywords: [String] = [], input: Input = .none,
                variants: [Variant] = [], since: String? = nil, files: FileTypes? = nil, query: [Parameter] = [], asksFirst: Bool = false) {
        self.id = id
        self.path = path
        self.title = title
        self.oneLine = oneLine
        self.symbol = symbol
        self.keywords = keywords
        self.input = input
        self.variants = variants
        self.since = since
        self.files = files
        self.query = query
        self.asksFirst = asksFirst
    }

    /// Whether running it, or `variant` of it, asks first from a link, Ask
    /// or an agent.
    public func asksFirst(variant: Variant?) -> Bool {
        asksFirst || variant?.asksFirst == true
    }

    /// The app's id ("cleanshot").
    public var appID: String {
        String(id.prefix { $0 != "." })
    }

    public var app: LinkedApp? {
        LinkedApp.app(id: appID)
    }

    public func variant(id: String) -> Variant? {
        variants.first { $0.id == id }
    }

    /// The variants the installed version takes; nil version (unread):
    /// all of them.
    public func variants(forVersion version: String?) -> [Variant] {
        variants.filter { AppVersion.isAtLeast(version, $0.since) }
    }

    /// Whether the installed version takes it at all.
    public func runs(onVersion version: String?) -> Bool {
        AppVersion.isAtLeast(version, since)
    }

    /// Its link: `scheme://path?…`, its own parameters, the variant's,
    /// then what skil.li read for it (`extra`).
    public func url(variant: Variant? = nil, extra: [Parameter] = []) -> URL? {
        guard let scheme = app?.scheme else { return nil }
        return Self.url(scheme: scheme, path: path, query: query + (variant?.query ?? []) + extra)
    }

    /// Its link in `app`, known or not yet (an app shown before it is
    /// added).
    public func url(in app: LinkedApp, variant: Variant? = nil) -> URL? {
        Self.url(scheme: app.scheme, path: path, query: query + (variant?.query ?? []))
    }

    /// `scheme://host/rest?…`, or `scheme:/rest?…` for a path that starts
    /// with "/"; `+` in a value encoded too (some apps read it as a space).
    static func url(scheme: String, path: String, query: [Parameter]) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        if path.hasPrefix("/") {
            components.path = path
        } else if let slash = path.firstIndex(of: "/") {
            components.host = String(path[..<slash])
            components.path = String(path[slash...])
        } else {
            components.host = path
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.name, value: $0.value) }
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url
    }
}

/// "5.0.1" against "4.7", number by number.
public enum AppVersion {
    /// True when `since` is nil, or when the version is unknown (the app
    /// says what it does not take).
    public static func isAtLeast(_ version: String?, _ since: String?) -> Bool {
        guard let since, let version else { return true }
        let have = numbers(version), need = numbers(since)
        for index in 0..<max(have.count, need.count) {
            let (left, right) = (index < have.count ? have[index] : 0, index < need.count ? need[index] : 0)
            if left != right { return left > right }
        }
        return true
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split { !$0.isNumber }.compactMap { Int($0) }
    }
}

// MARK: - CleanShot X

extension LinkedApp {
    /// cleanshot.com/docs-api (read 2026-10-20). CleanShot runs them once
    /// its API is allowed (CleanShot → Settings → Advanced); the first asks.
    public static let cleanShot = LinkedApp(
        id: "cleanshot", name: "CleanShot X", shortName: "CleanShot", bundleID: "pl.maketheweb.cleanshotx", scheme: "cleanshot",
        commands: CleanShot.commands, groups: CleanShot.groups,
        allowance: "Its commands run while Allow URL scheme API is on:\nCleanShot → Settings → Advanced.",
        fileActions: [
            .init(command: "open-annotate", title: "Annotate in CleanShot", symbol: "pencil.tip.crop.circle"),
            .init(command: "pin", title: "Pin in CleanShot", symbol: "pin"),
            .init(command: "quick-access", title: "Add to CleanShot Quick Access", symbol: "rectangle.on.rectangle")
        ]
    )
}

/// CleanShot X's commands, as its API documents them, and the few skil.li
/// makes from them with what it knows (the front window, the latest
/// screenshot).
public enum CleanShot {
    static let capture = ["cleanshot", "screenshot", "capture", "capture d'écran", "copie d'écran", "screen", "écran"]
    static let selected = ["cleanshot", "selected", "selection", "sélection", "sélectionné", "finder", "file", "fichier"]

    /// After the capture: what CleanShot does with it (`action=`, 4.7+).
    static let afterCapture: [AppLinkCommand.Variant] = [
        .init(id: "copy", title: "Capture and Copy", label: "Copy", symbol: "doc.on.doc", query: [.init("action", "copy")], since: "4.7"),
        .init(id: "save", title: "Capture and Save", label: "Save", symbol: "square.and.arrow.down", query: [.init("action", "save")], since: "4.7"),
        .init(id: "annotate", title: "Capture and Annotate", label: "Annotate", symbol: "pencil.tip.crop.circle", query: [.init("action", "annotate")], since: "4.7"),
        .init(id: "pin", title: "Capture and Pin", label: "Pin", symbol: "pin", query: [.init("action", "pin")], since: "4.7"),
        .init(id: "upload", title: "Capture and Upload to Cloud", label: "Upload", symbol: "icloud.and.arrow.up", query: [.init("action", "upload")],
              since: "4.7", asksFirst: true)
    ]

    /// Settings' tabs (`tab=`, 4.7+).
    static let settingsTabs: [AppLinkCommand.Variant] = [
        ("general", "General"), ("wallpaper", "Wallpaper"), ("shortcuts", "Shortcuts"), ("quickaccess", "Quick Access"),
        ("recording", "Recording"), ("screenshots", "Screenshots"), ("annotate", "Annotate"), ("cloud", "Cloud"),
        ("advanced", "Advanced"), ("about", "About")
    ].map { .init(id: $0.0, title: "Open \($0.1)", label: $0.1, symbol: "gearshape", query: [.init("tab", $0.0)], since: "4.7") }

    /// What `pin`, `open-annotate` and `capture-text` open.
    public static let images = AppLinkCommand.FileTypes(["png", "jpg", "jpeg"], said: "PNG and JPEG images")
    /// What `add-quick-access-overlay` opens.
    public static let imagesAndVideos = AppLinkCommand.FileTypes(["png", "jpg", "jpeg", "mp4"], said: "PNG and JPEG images and MP4 videos")

    private static func command(_ name: String, path: String? = nil, _ title: String, _ oneLine: String, _ symbol: String,
                                _ keywords: [String], input: AppLinkCommand.Input = .none, variants: [AppLinkCommand.Variant] = [],
                                since: String? = nil, files: AppLinkCommand.FileTypes? = nil) -> AppLinkCommand {
        AppLinkCommand(id: "cleanshot.\(name)", path: path ?? name, title: title, oneLine: oneLine, symbol: symbol,
                       keywords: ["cleanshot"] + keywords, input: input, variants: variants, since: since, files: files)
    }

    public static let commands: [AppLinkCommand] = [
        command("capture-area", "Capture Area", "Takes a screenshot of the part of the screen you select", "camera.viewfinder",
                capture + ["area", "region", "selection", "zone"], variants: afterCapture),
        command("capture-front-window", path: "capture-area", "Capture Front Window",
                "Takes a screenshot of the window in front, nothing to pick", "macwindow",
                capture + ["window", "front", "fenêtre", "active"], input: .frontWindow, variants: afterCapture, since: "3.5.1"),
        command("capture-window", "Capture Window", "Takes a screenshot of the window you click", "macwindow.on.rectangle",
                capture + ["window", "fenêtre"], variants: afterCapture),
        command("capture-fullscreen", "Capture Fullscreen", "Takes a screenshot of the whole screen", "display",
                capture + ["fullscreen", "full screen", "plein écran", "entire"], variants: afterCapture),
        command("capture-previous-area", "Capture Previous Area", "Takes a screenshot of the same area as last time",
                "arrow.counterclockwise", capture + ["previous", "last", "again", "précédente", "même zone"], variants: afterCapture),
        command("self-timer", "Capture with Self-Timer", "Takes a screenshot of the area you select, after a countdown", "timer",
                capture + ["timer", "self-timer", "delay", "retardateur", "minuteur"], variants: afterCapture),
        command("scrolling-capture", "Scrolling Capture", "Takes a screenshot of a whole page, scrolling it for you", "scroll",
                capture + ["scrolling", "scroll", "long", "page", "défilement", "défilante"],
                variants: [
                    .init(id: "start", title: "Start at Once", label: "Start at Once", symbol: "play", query: [.init("start", "true")], since: "4.7"),
                    .init(id: "autoscroll", title: "Start with Auto-Scroll", label: "Auto-Scroll", symbol: "arrow.down.to.line",
                          query: [.init("start", "true"), .init("autoscroll", "true")], since: "4.7")
                ]),
        command("all-in-one", "All-In-One", "Captures, records or scrolls, picked in one overlay", "square.grid.2x2",
                capture + ["all in one", "all-in-one", "record", "tout-en-un"], since: "4.2"),
        command("capture-text", "Capture Text", "Copies the text in the area you select (OCR)", "text.viewfinder",
                ["cleanshot", "ocr", "text", "texte", "recognize", "extract", "extraire", "lire", "copy text"],
                variants: [
                    .init(id: "linebreaks", title: "Capture Text with Line Breaks", label: "Line Breaks", symbol: "text.alignleft", query: [.init("linebreaks", "true")]),
                    .init(id: "nolinebreaks", title: "Capture Text on One Line", label: "One Line", symbol: "text.justify.leading",
                          query: [.init("linebreaks", "false")])
                ], since: "3.8.1", files: images),
        command("record-screen", "Record Screen", "Records a video or a GIF of the area you select", "record.circle",
                ["cleanshot", "record", "recording", "video", "vidéo", "gif", "enregistrer", "enregistrement", "screencast"]),
        command("record-front-window", path: "record-screen", "Record Front Window", "Records a video or a GIF of the window in front",
                "record.circle.fill", ["cleanshot", "record", "recording", "video", "vidéo", "gif", "enregistrer", "window", "fenêtre"],
                input: .frontWindow, since: "4.7"),
        command("open-from-clipboard", "Annotate Clipboard Image", "Opens the image you copied in CleanShot's editor",
                "pencil.tip.crop.circle", ["cleanshot", "annotate", "annoter", "edit", "clipboard", "presse-papier", "draw", "arrow"]),
        command("annotate-latest-screenshot", path: "open-annotate", "Annotate Latest Screenshot",
                "Opens your last screenshot in CleanShot's editor", "pencil.and.outline",
                ["cleanshot", "annotate", "annoter", "edit", "last", "latest", "dernière", "screenshot", "capture"],
                input: .latestScreenshot, since: "3.8.1", files: images),
        command("annotate-selected-image", path: "open-annotate", "Annotate Selected Image",
                "Opens the image selected in Finder in CleanShot's editor", "pencil.and.scribble",
                selected + ["annotate", "annoter", "edit", "image"], input: .finderSelection, since: "3.8.1", files: images),
        command("open-annotate", "Annotate Image…", "Opens an image you choose in CleanShot's editor", "photo.badge.plus",
                ["cleanshot", "annotate", "annoter", "edit", "image", "file", "fichier"], since: "3.8.1", files: images),
        command("pin-latest-screenshot", path: "pin", "Pin Latest Screenshot", "Keeps your last screenshot floating above every window",
                "pin", ["cleanshot", "pin", "épingler", "float", "last", "latest", "dernière", "screenshot", "capture"],
                input: .latestScreenshot, files: images),
        command("pin-selected-image", path: "pin", "Pin Selected Image", "Keeps the image selected in Finder floating above every window",
                "pin.fill", selected + ["pin", "épingler", "float", "image"], input: .finderSelection, files: images),
        command("pin", "Pin Image…", "Keeps an image you choose floating above every window", "pin.circle",
                ["cleanshot", "pin", "épingler", "float", "image", "file", "fichier"], files: images),
        command("quick-access", path: "add-quick-access-overlay", "Add Selected File to Quick Access",
                "Opens the image or video selected in Finder in Quick Access", "rectangle.on.rectangle",
                selected + ["quick access", "overlay", "accès rapide", "image", "video", "vidéo", "mp4"], input: .finderSelection,
                since: "3.8.1", files: imagesAndVideos),
        command("toggle-desktop-icons", "Toggle Desktop Icons", "Hides the files on your desktop, or shows them again", "eye",
                ["cleanshot", "desktop", "icons", "bureau", "icônes", "clean", "hide", "show", "masquer"]),
        command("hide-desktop-icons", "Hide Desktop Icons", "Hides the files on your desktop before a capture", "eye.slash",
                ["cleanshot", "desktop", "icons", "bureau", "icônes", "clean", "masquer", "cacher"], since: "3.8.1"),
        command("show-desktop-icons", "Show Desktop Icons", "Shows the files on your desktop again", "eye",
                ["cleanshot", "desktop", "icons", "bureau", "icônes", "afficher", "montrer"], since: "3.8.1"),
        command("open-history", "Capture History", "Lists your past screenshots and recordings in CleanShot", "clock.arrow.circlepath",
                ["cleanshot", "history", "historique", "past", "screenshots", "captures", "recordings"], since: "4.4"),
        command("restore-recently-closed", "Restore Recently Closed", "Brings back the capture you closed last", "arrow.uturn.backward",
                ["cleanshot", "restore", "undo", "reopen", "closed", "rouvrir", "restaurer", "fermée"]),
        command("open-settings", "CleanShot Settings", "Opens CleanShot X's settings", "gearshape",
                ["cleanshot", "settings", "preferences", "réglages", "préférences"], variants: settingsTabs)
    ]

    /// The front window's place as CleanShot reads it: the display it is
    /// on (1 the main one, in `screens`' order) and its frame from that
    /// display's bottom left, in points. `window` is Accessibility's (top
    /// left of the main display); `screens` are AppKit's frames (bottom
    /// left), the main one first. Nil when it is on no display.
    public static func frame(of window: CGRect, screens: [CGRect]) -> [AppLinkCommand.Parameter]? {
        guard let main = screens.first, window.width >= 1, window.height >= 1 else { return nil }
        // Accessibility's top left → AppKit's bottom left.
        let flipped = CGRect(x: window.minX, y: main.maxY - window.maxY, width: window.width, height: window.height)
        let center = CGPoint(x: flipped.midX, y: flipped.midY)
        let index = screens.firstIndex { $0.contains(center) }
            ?? screens.indices.max { screens[$0].intersection(flipped).area < screens[$1].intersection(flipped).area }
        guard let index, screens[index].intersects(flipped) else { return nil }
        let screen = screens[index]
        // Only what is on that display: CleanShot captures one at a time.
        let shown = flipped.intersection(screen)
        return [
            .init("x", String(Int((shown.minX - screen.minX).rounded()))),
            .init("y", String(Int((shown.minY - screen.minY).rounded()))),
            .init("width", String(Int(shown.width.rounded()))),
            .init("height", String(Int(shown.height.rounded()))),
            .init("display", String(index + 1))
        ]
    }

    /// A CleanShot link that sends the capture to CleanShot Cloud
    /// (`action=upload`, whatever its path or case): asked every time,
    /// whoever opens it (an agent's `open_url`, `run_action`).
    public static func uploads(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == LinkedApp.cleanShot.scheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains { $0.name.lowercased() == "action" && $0.value?.lowercased() == "upload" }
    }

    static let groups: [LinkedApp.CommandGroup] = [
        .init(title: "Capture", commands: ["capture-area", "capture-front-window", "capture-window", "capture-fullscreen", "capture-previous-area",
                                           "self-timer", "scrolling-capture", "all-in-one", "capture-text"]),
        .init(title: "Record", commands: ["record-screen", "record-front-window"]),
        .init(title: "Annotate and Pin", commands: ["open-from-clipboard", "annotate-latest-screenshot", "annotate-selected-image", "open-annotate",
                                                    "pin-latest-screenshot", "pin-selected-image", "pin", "quick-access"]),
        .init(title: "Desktop Icons", commands: ["toggle-desktop-icons", "hide-desktop-icons", "show-desktop-icons"]),
        .init(title: "History and Settings", commands: ["open-history", "restore-recently-closed", "open-settings"])
    ]

    /// What Capture Text does with line breaks when ⌘K does not say
    /// (Settings → Apps): as CleanShot's own Keep line breaks is set, or
    /// one of its two variants each time.
    public enum TextLineBreaks: String, CaseIterable, Sendable {
        case asSet = "cleanshot"
        case kept = "linebreaks"
        case joined = "nolinebreaks"

        public var title: String {
            switch self {
            case .asSet: "As set in CleanShot"
            case .kept: "Kept"
            case .joined: "Joined on one line"
            }
        }

        /// The variant of Capture Text it runs; nil: CleanShot's setting.
        public var variant: String? {
            self == .asSet ? nil : rawValue
        }
    }

    /// The variant a command runs when none is said: Capture Text's line
    /// breaks; nil for every other.
    public static func defaultVariant(of command: AppLinkCommand, lineBreaks: TextLineBreaks) -> AppLinkCommand.Variant? {
        guard command.id == "cleanshot.capture-text", let id = lineBreaks.variant else { return nil }
        return command.variant(id: id)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
