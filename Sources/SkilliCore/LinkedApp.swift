import CoreGraphics
import Foundation

/// An app skil.li drives through its own links (`cleanshot://capture-area`):
/// each of its commands is a launcher row, a Catalog entry, a key and an
/// agent action while the app is installed (docs/apps.md). Only links the
/// app documents itself; CleanShot X's own windows do the work.
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

    /// A few of an app's commands under one title ("Capture"), by their
    /// name after the app's id ("capture-area").
    public struct CommandGroup: Sendable {
        public let title: String
        public let commands: [String]
    }

    /// The commands of each group, in its order.
    public var grouped: [(title: String, commands: [AppLinkCommand])] {
        groups.map { group in
            (group.title, group.commands.compactMap { name in commands.first { $0.id == "\(id).\(name)" } })
        }
    }

    public static let all: [LinkedApp] = [.cleanShot]

    public static func app(id: String) -> LinkedApp? {
        all.first { $0.id == id }
    }

    /// "cleanshot.capture-area": the app's command by its full id.
    public static func command(id: String) -> AppLinkCommand? {
        guard let dot = id.firstIndex(of: ".") else { return nil }
        return app(id: String(id[..<dot]))?.commands.first { $0.id == id }
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

        public init(id: String, title: String, label: String, symbol: String, query: [Parameter], since: String? = nil) {
            self.id = id
            self.title = title
            self.label = label
            self.symbol = symbol
            self.query = query
            self.since = since
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
    /// The link's path, its host: `capture-area` in `cleanshot://capture-area`.
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

    public init(id: String, path: String, title: String, oneLine: String, symbol: String, keywords: [String] = [], input: Input = .none,
                variants: [Variant] = [], since: String? = nil) {
        self.id = id
        self.path = path
        self.title = title
        self.oneLine = oneLine
        self.symbol = symbol
        self.keywords = keywords
        self.input = input
        self.variants = variants
        self.since = since
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

    /// Its link: `scheme://path?…`, the variant's parameters, then what
    /// skil.li read for it (`extra`).
    public func url(variant: Variant? = nil, extra: [Parameter] = []) -> URL? {
        guard let scheme = app?.scheme else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = path
        let items = (variant?.query ?? []) + extra
        if !items.isEmpty { components.queryItems = items.map { URLQueryItem(name: $0.name, value: $0.value) } }
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
        allowance: "Its commands run while Allow URL scheme API is on, in CleanShot → Settings → Advanced."
    )
}

/// CleanShot X's commands, as its API documents them, and the few skil.li
/// makes from them with what it knows (the front window, the latest
/// screenshot).
public enum CleanShot {
    static let capture = ["cleanshot", "screenshot", "capture", "capture d'écran", "copie d'écran", "screen", "écran"]

    /// After the capture: what CleanShot does with it (`action=`, 4.7+).
    static let afterCapture: [AppLinkCommand.Variant] = [
        .init(id: "copy", title: "Capture and Copy", label: "Copy", symbol: "doc.on.doc", query: [.init("action", "copy")], since: "4.7"),
        .init(id: "save", title: "Capture and Save", label: "Save", symbol: "square.and.arrow.down", query: [.init("action", "save")], since: "4.7"),
        .init(id: "annotate", title: "Capture and Annotate", label: "Annotate", symbol: "pencil.tip.crop.circle", query: [.init("action", "annotate")], since: "4.7"),
        .init(id: "pin", title: "Capture and Pin", label: "Pin", symbol: "pin", query: [.init("action", "pin")], since: "4.7"),
        .init(id: "upload", title: "Capture and Upload to Cloud", label: "Upload", symbol: "icloud.and.arrow.up", query: [.init("action", "upload")],
              since: "4.7")
    ]

    /// Settings' tabs (`tab=`, 4.7+).
    static let settingsTabs: [AppLinkCommand.Variant] = [
        ("general", "General"), ("wallpaper", "Wallpaper"), ("shortcuts", "Shortcuts"), ("quickaccess", "Quick Access"),
        ("recording", "Recording"), ("screenshots", "Screenshots"), ("annotate", "Annotate"), ("cloud", "Cloud"),
        ("advanced", "Advanced"), ("about", "About")
    ].map { .init(id: $0.0, title: "Open \($0.1)", label: $0.1, symbol: "gearshape", query: [.init("tab", $0.0)], since: "4.7") }

    private static func command(_ name: String, path: String? = nil, _ title: String, _ oneLine: String, _ symbol: String,
                                _ keywords: [String], input: AppLinkCommand.Input = .none, variants: [AppLinkCommand.Variant] = [],
                                since: String? = nil) -> AppLinkCommand {
        AppLinkCommand(id: "cleanshot.\(name)", path: path ?? name, title: title, oneLine: oneLine, symbol: symbol,
                       keywords: ["cleanshot"] + keywords, input: input, variants: variants, since: since)
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
                ], since: "3.8.1"),
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
                input: .latestScreenshot, since: "3.8.1"),
        command("open-annotate", "Annotate Image…", "Opens an image you choose in CleanShot's editor", "photo.badge.plus",
                ["cleanshot", "annotate", "annoter", "edit", "image", "file", "fichier"], since: "3.8.1"),
        command("pin-latest-screenshot", path: "pin", "Pin Latest Screenshot", "Keeps your last screenshot floating above every window",
                "pin", ["cleanshot", "pin", "épingler", "float", "last", "latest", "dernière", "screenshot", "capture"],
                input: .latestScreenshot),
        command("pin", "Pin Image…", "Keeps an image you choose floating above every window", "pin.circle",
                ["cleanshot", "pin", "épingler", "float", "image", "file", "fichier"]),
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
        .init(title: "Annotate and Pin", commands: ["open-from-clipboard", "annotate-latest-screenshot", "open-annotate", "pin-latest-screenshot",
                                                    "pin"]),
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

    /// The image types CleanShot opens (`pin`, `open-annotate`).
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
