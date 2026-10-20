import CoreGraphics
import Foundation

/// A saved arrangement of windows ("Coding": Xcode on the left two thirds,
/// Safari on the right), and how to put it back on the screens there are
/// now.
public struct SavedWindowLayout: Codable, Equatable, Sendable, Identifiable {
    public struct Window: Codable, Equatable, Sendable {
        public enum State: String, Codable, Sendable {
            case normal
            /// In the Dock.
            case minimized
            /// macOS full screen, in its own space.
            case fullScreen
        }

        public var bundleID: String
        public var appName: String
        public var title: String
        /// Its rank among its app's windows when saved, front first.
        public var index: Int
        /// Top-left origin, y down, like Accessibility.
        public var frame: CGRect
        /// Which of the layout's displays it was on (most of it).
        public var display: Int?
        public var state: State
        /// The file it showed (Accessibility's AXDocument, a file URL), to
        /// open it again when it is not open.
        public var document: String?
        /// What applying the layout opens for this window when nothing
        /// shows it yet: a file or a folder (a file URL) or a web link,
        /// added in the editor (`LayoutOpening`). The window it opens in
        /// takes this place.
        public var opens: String?

        public init(bundleID: String, appName: String, title: String, index: Int, frame: CGRect,
                    display: Int? = nil, state: State = .normal, document: String? = nil, opens: String? = nil) {
            self.bundleID = bundleID
            self.appName = appName
            self.title = title
            self.index = index
            self.frame = frame
            self.display = display
            self.state = state
            self.document = document
            self.opens = opens
        }

        private enum CodingKeys: String, CodingKey {
            case bundleID, appName, title, index, frame, display, state, document, opens
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bundleID = try container.decode(String.self, forKey: .bundleID)
            appName = try container.decode(String.self, forKey: .appName)
            title = try container.decode(String.self, forKey: .title)
            index = try container.decode(Int.self, forKey: .index)
            frame = try container.decode(CGRect.self, forKey: .frame)
            // Saved before skil.li knew displays and states.
            display = try container.decodeIfPresent(Int.self, forKey: .display)
            state = try container.decodeIfPresent(State.self, forKey: .state) ?? .normal
            document = try container.decodeIfPresent(String.self, forKey: .document)
            opens = try container.decodeIfPresent(String.self, forKey: .opens)
        }
    }

    /// The files, folders and links it opens when applied, each with the
    /// window that takes its place.
    public var openings: [Window] { windows.filter { $0.opens != nil } }

    /// Its openings' windows where applying it would put them on
    /// `displays`, each on the one it is now on: what a layout taken anew
    /// from the windows open keeps.
    public func openings(on displays: [LayoutDisplay]) -> [Window] {
        let opened = openings
        guard !displays.isEmpty, !opened.isEmpty else { return opened }
        var alone = self
        alone.windows = opened
        let plan = WindowLayoutPlan.placement(of: alone, on: displays)
        return zip(opened, plan.frames).map { window, frame in
            var window = window
            window.frame = frame
            window.display = WindowLayoutPlan.display(of: frame, among: displays)
            return window
        }
    }

    /// The file's name.
    public var id: String
    public var name: String
    public var windows: [Window]
    /// Who and where the displays were, the menu bar's first. Empty in
    /// layouts saved before skil.li knew displays.
    public var displays: [LayoutDisplay]
    /// The apps that were hidden (⌘H), by bundle id.
    public var hiddenApps: [String]
    /// The apps left out when it was saved: left out again when it is
    /// taken anew from the windows open.
    public var ignoredApps: [String]
    /// What happens when one of its displays is plugged in.
    public var automatic: Automatic

    public enum Automatic: String, Codable, Sendable, CaseIterable {
        /// skil.li asks, centered on the display plugged in.
        case ask
        /// Put back at once, when the display is surely the one saved.
        case always
        case never
    }
    /// The displays' frames (top-left): what layouts saved before
    /// `displays` have, still written for older skil.li builds reading the
    /// same folder.
    public var screens: [CGRect]
    public var saved: Date

    public init(id: String, name: String, windows: [Window], displays: [LayoutDisplay] = [], hiddenApps: [String] = [],
                ignoredApps: [String] = [], automatic: Automatic = .ask, screens: [CGRect]? = nil, saved: Date = .now) {
        self.id = id
        self.name = name
        self.windows = windows
        self.displays = displays
        self.hiddenApps = hiddenApps
        self.ignoredApps = ignoredApps
        self.automatic = automatic
        self.screens = screens ?? displays.map(\.frame)
        self.saved = saved
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, windows, displays, hiddenApps, ignoredApps, automatic, screens, saved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        windows = try container.decode([Window].self, forKey: .windows)
        displays = try container.decodeIfPresent([LayoutDisplay].self, forKey: .displays) ?? []
        hiddenApps = try container.decodeIfPresent([String].self, forKey: .hiddenApps) ?? []
        ignoredApps = try container.decodeIfPresent([String].self, forKey: .ignoredApps) ?? []
        automatic = try container.decodeIfPresent(Automatic.self, forKey: .automatic) ?? .ask
        screens = try container.decodeIfPresent([CGRect].self, forKey: .screens) ?? []
        saved = try container.decode(Date.self, forKey: .saved)
    }

    /// "Xcode, Safari and 2 more".
    public var summary: String {
        var apps: [String] = []
        for window in windows where !apps.contains(window.appName) { apps.append(window.appName) }
        switch apps.count {
        case 0: return "No windows"
        case 1: return apps[0]
        case 2: return "\(apps[0]) and \(apps[1])"
        default: return "\(apps[0]), \(apps[1]) and \(apps.count - 2) more"
        }
    }
}

/// What putting a layout back did, and what it had to adapt: said in the
/// card afterwards.
public struct LayoutReport: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        /// The display is there with another size: proportions kept.
        case resized(display: String, from: CGSize, to: CGSize)
        /// The saved display is not connected: its windows went to another.
        case standIn(saved: String, current: String, windows: Int)
        /// The app keeps its window larger than saved (its minimum size).
        case larger(app: String)
        case notInstalled(app: String)
        /// Its windows never showed.
        case notOpen(app: String, windows: Int)

        /// Put back, but not quite as saved.
        var isAdaptation: Bool {
            switch self {
            case .resized, .standIn, .larger: true
            case .notInstalled, .notOpen: false
            }
        }
    }

    public var name: String
    public var placed: Int
    public var total: Int
    public var changes: [Change]

    public init(name: String, placed: Int = 0, total: Int, changes: [Change] = []) {
        self.name = name
        self.placed = placed
        self.total = total
        self.changes = changes
    }

    /// A window not put back (not open, its app not installed): said in a
    /// card. Adaptations alone (a resized display) are seen, not said.
    public var hasFailures: Bool {
        placed < total || changes.contains { !$0.isAdaptation }
    }

    /// One line when all went as saved; else a line per change, in Markdown.
    public var message: String {
        let count = placed == total ? "\(placed) window\(placed == 1 ? "" : "s")" : "\(placed) of \(total) windows"
        guard !changes.isEmpty else { return "“\(name)”: \(count) in place." }
        let adapted = changes.contains(where: \.isAdaptation)
        let lines = changes.map { change -> String in
            switch change {
            case .resized(let display, let from, let to):
                "\(display): \(Self.size(from)) → \(Self.size(to)), proportions kept"
            case .standIn(let saved, let current, let windows):
                "\(saved) not connected: \(windows == 1 ? "its window" : "its \(windows) windows") on \(current), proportions kept"
            case .larger(let app):
                "\(app) keeps its window a little larger than saved (its minimum size)"
            case .notInstalled(let app):
                "\(app) is not installed"
            case .notOpen(let app, let windows):
                "\(app): \(windows == 1 ? "a window" : "\(windows) windows") did not open"
            }
        }
        return "“\(name)”: \(count) in place\(adapted ? ", adapted" : ""):\n\n" + lines.map { "- \($0)" }.joined(separator: "\n")
    }

    static func size(_ size: CGSize) -> String { "\(Int(size.width))×\(Int(size.height))" }
}

/// A file, a folder or a web link a window layout opens when it is
/// applied (`SavedWindowLayout.Window.opens`): the window it opens in
/// takes the place drawn for it.
public enum LayoutOpening {
    public enum Kind: Equatable, Sendable {
        case file
        case folder
        case link
    }

    /// A link as typed ("github.com/nomdelasociete", "https://…"): only
    /// http and https, with a host; "https://" added when no scheme was.
    public static func link(_ typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, host.contains(".") || host == "localhost" || host == "127.0.0.1"
        else { return nil }
        return url
    }

    /// File URLs are files or folders (a trailing slash, as Foundation
    /// writes a folder's URL); anything else is a link.
    public static func kind(of opening: String) -> Kind {
        guard let url = URL(string: opening), url.isFileURL else { return .link }
        return opening.hasSuffix("/") ? .folder : .file
    }

    /// What the editor and the canvas call it: the file's or folder's
    /// name, the link's site and path ("github.com/nomdelasociete").
    public static func name(of opening: String) -> String {
        guard let url = URL(string: opening) else { return opening }
        if url.isFileURL { return url.lastPathComponent }
        var host = url.host ?? opening
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path == "/" ? "" : url.path
        let name = host + path
        return name.count > 60 ? String(name.prefix(59)) + "…" : name
    }

    /// Whether a window titled `title`, showing `document` (its
    /// AXDocument), shows `opening`: the same file, folder or page; for a
    /// file or a folder, also its name as the window's title (Finder's
    /// windows, apps that say no document).
    public static func shows(_ opening: String, title: String, document: String?) -> Bool {
        guard let wanted = URL(string: opening) else { return false }
        if let document, let shown = URL(string: document) {
            if wanted.isFileURL, shown.isFileURL, wanted.standardizedFileURL.path == shown.standardizedFileURL.path { return true }
            if !wanted.isFileURL, trimmed(document) == trimmed(opening) { return true }
        }
        guard wanted.isFileURL, !title.isEmpty else { return false }
        let name = wanted.lastPathComponent
        return title == name || title == (name as NSString).deletingPathExtension
    }

    private static func trimmed(_ link: String) -> String {
        link.hasSuffix("/") ? String(link.dropLast()) : link
    }
}

public enum WindowLayoutPlan {
    /// Which current window each saved one is: the same document first,
    /// then the same title (a document keeps its name), then the same rank
    /// among what is left. Each current window is used once.
    public static func match(saved: [SavedWindowLayout.Window], current: [String], documents: [String?] = []) -> [Int?] {
        var used = Set<Int>()
        var result = [Int?](repeating: nil, count: saved.count)
        for (offset, window) in saved.enumerated() {
            guard let document = window.document else { continue }
            if let index = documents.indices.first(where: { !used.contains($0) && documents[$0] == document }), index < current.count {
                result[offset] = index
                used.insert(index)
            }
        }
        for (offset, window) in saved.enumerated() where result[offset] == nil && !window.title.isEmpty {
            if let index = current.indices.first(where: { !used.contains($0) && current[$0] == window.title }) {
                result[offset] = index
                used.insert(index)
            }
        }
        for (offset, window) in saved.enumerated() where result[offset] == nil {
            let left = current.indices.filter { !used.contains($0) }
            guard !left.isEmpty else { break }
            let index = left.contains(window.index) ? window.index : left[0]
            result[offset] = index
            used.insert(index)
        }
        return result
    }

    /// As `match(saved:current:documents:)`, after the windows already
    /// decided (`decided`: a saved window's offset → the current window
    /// the file or link it opens showed in): the other saved windows are
    /// matched among the windows left. A window that opens something and
    /// found none stays without one.
    public static func match(saved: [SavedWindowLayout.Window], current: [String], documents: [String?], decided: [Int: Int]) -> [Int?] {
        var result = [Int?](repeating: nil, count: saved.count)
        var taken = Set<Int>()
        for (offset, index) in decided where saved.indices.contains(offset) && current.indices.contains(index) && !taken.contains(index) {
            result[offset] = index
            taken.insert(index)
        }
        let free = current.indices.filter { !taken.contains($0) }
        let rest = saved.indices.filter { result[$0] == nil && saved[$0].opens == nil }
        let matched = match(saved: rest.map { saved[$0] }, current: free.map { current[$0] },
                            documents: free.map { documents.indices.contains($0) ? documents[$0] : nil })
        for (offset, match) in matched.enumerated() {
            if let match { result[rest[offset]] = free[match] }
        }
        return result
    }

    /// The display showing most of `frame` (its center's when none does).
    public static func display(of frame: CGRect, among displays: [LayoutDisplay]) -> Int? {
        let areas = displays.map { display -> CGFloat in
            let overlap = display.frame.intersection(frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.indices.first { displays[$0].frame.contains(center) }
    }

    /// Where a window saved at `frame` on `from` goes on `to`: the same
    /// place when the display kept its size, else the same place in
    /// proportion, kept on it.
    public static func frame(_ frame: CGRect, from: LayoutDisplay, to: LayoutDisplay) -> CGRect {
        if abs(from.visible.width - to.visible.width) <= 1, abs(from.visible.height - to.visible.height) <= 1 {
            return WindowLayout.rounded(frame.offsetBy(dx: to.visible.minX - from.visible.minX, dy: to.visible.minY - from.visible.minY))
        }
        return WindowLayout.moved(frame, from: from.visible, to: to.visible)
    }

    /// Where every saved window goes on the displays there are now, the
    /// usable area of its display, and what had to be adapted (a display
    /// resized, one missing).
    public struct Placement: Equatable, Sendable {
        public var frames: [CGRect]
        public var visible: [CGRect]
        public var changes: [LayoutReport.Change]
    }

    public static func placement(of layout: SavedWindowLayout, on current: [LayoutDisplay]) -> Placement {
        guard let main = current.first else {
            return Placement(frames: layout.windows.map(\.frame), visible: layout.windows.map(\.frame), changes: [])
        }
        // Saved before skil.li knew displays: by their frames only.
        guard !layout.displays.isEmpty else {
            return Placement(
                frames: layout.windows.map { fit($0.frame, savedScreens: layout.screens, screens: current.map(\.frame), main: main.visible) },
                visible: layout.windows.map { window in
                    current.first { $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) }?.visible ?? main.visible
                },
                changes: []
            )
        }
        let pairs = DisplayPairing.pair(saved: layout.displays, current: current)
        // The saved display each window was on.
        let origins = layout.windows.map { window in
            window.display.flatMap { layout.displays.indices.contains($0) ? $0 : nil }
                ?? display(of: window.frame, among: layout.displays) ?? 0
        }
        var frames: [CGRect] = []
        var visible: [CGRect] = []
        for (window, origin) in zip(layout.windows, origins) {
            let target = current[pairs[origin].index]
            frames.append(frame(window.frame, from: layout.displays[origin], to: target))
            visible.append(target.visible)
        }
        var changes: [LayoutReport.Change] = []
        for (index, pair) in pairs.enumerated() {
            let windows = origins.filter { $0 == index }.count
            guard windows > 0 else { continue }
            let saved = layout.displays[index]
            let now = current[pair.index]
            switch pair.match {
            case .standIn:
                changes.append(.standIn(saved: saved.fingerprint.name, current: now.fingerprint.name, windows: windows))
            case .same:
                if abs(saved.frame.width - now.frame.width) > 1 || abs(saved.frame.height - now.frame.height) > 1 {
                    changes.append(.resized(display: saved.fingerprint.name, from: saved.frame.size, to: now.frame.size))
                }
            }
        }
        return Placement(frames: frames, visible: visible, changes: changes)
    }

    /// A frame saved on a display that is gone comes onto the main one,
    /// same place in proportion; one still on a display stays as it was.
    /// For layouts saved before skil.li knew displays.
    public static func fit(_ frame: CGRect, savedScreens: [CGRect], screens: [CGRect], main: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if screens.contains(where: { $0.contains(center) }) { return frame }
        let from = savedScreens.first { $0.contains(center) } ?? savedScreens.first ?? main
        return WindowLayout.moved(frame, from: from, to: main)
    }

    /// `frame` moved (not resized) to stay inside `visible` as much as its
    /// size allows: a window an app keeps larger than asked must not hang
    /// off the display.
    public static func kept(_ frame: CGRect, inside visible: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = max(min(frame.minX, visible.maxX - frame.width), visible.minX)
        frame.origin.y = max(min(frame.minY, visible.maxY - frame.height), visible.minY)
        return frame
    }

    /// "save layout coding" → "coding"; nil when the text does not save one.
    public static func saveName(_ text: String) -> String? {
        let lower = text.lowercased()
        for prefix in ["save layout ", "save window layout ", "enregistrer disposition ", "sauver disposition "] where lower.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
