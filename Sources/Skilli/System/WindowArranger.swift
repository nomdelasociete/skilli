import AppKit
import ApplicationServices
import Observation
import SkilliCore

/// Every window on screen, and saved arrangements of them ("Coding"):
/// saved as JSON in `~/Library/Application Support/skil.li/layouts`, put
/// back with the apps opened when they are not running. Accessibility for
/// the other apps' windows; skil.li's own are left out.
@MainActor
@Observable
final class WindowArranger {
    /// A window open now.
    struct OpenWindow {
        let app: NSRunningApplication
        let appElement: AXUIElement
        let element: AXUIElement
        let title: String
        /// Top-left, like Accessibility.
        let frame: CGRect
        /// Its rank among its app's windows, front first.
        let index: Int
        let state: SavedWindowLayout.Window.State
        /// The file it shows (AXDocument, a file URL); read only for layouts.
        let document: String?

        var appName: String { app.localizedName ?? "?" }
        /// "Safari — GitHub".
        var line: String { title.isEmpty ? appName : "\(appName) — \(title)" }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @ObservationIgnored let folder: URL?
    @ObservationIgnored private var cached: (stamp: Date?, layouts: [SavedWindowLayout])?
    /// Goes up each time skil.li writes or deletes a layout: Settings'
    /// list reads it to follow.
    private(set) var revision = 0

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li/layouts", isDirectory: true)
    }

    init(folder: URL?) {
        self.folder = folder
    }

    // MARK: - Windows open now

    /// Standard, not minimized windows of the visible apps with a Dock
    /// icon; `all` adds the minimized ones and the hidden apps', with the
    /// file each window shows (for layouts).
    func windows(all: Bool = false) -> [OpenWindow] {
        var found: [OpenWindow] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && (all || !app.isHidden) && app.processIdentifier != getpid() {
            found += windows(of: app, all: all)
        }
        return found
    }

    private func windows(of app: NSRunningApplication, all: Bool) -> [OpenWindow] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw) == .success,
              let list = raw as? [AXUIElement] else { return [] }
        var found: [OpenWindow] = []
        for window in list {
            guard Self.string(window, kAXSubroleAttribute) == "AXStandardWindow", let frame = Self.frame(window) else { continue }
            let minimized = Self.bool(window, kAXMinimizedAttribute) == true
            if minimized, !all { continue }
            let state: SavedWindowLayout.Window.State = minimized ? .minimized : Self.bool(window, "AXFullScreen") == true ? .fullScreen : .normal
            let document = all ? Self.string(window, kAXDocumentAttribute).flatMap { URL(string: $0)?.isFileURL == true ? $0 : nil } : nil
            found.append(OpenWindow(app: app, appElement: element, element: window, title: Self.string(window, kAXTitleAttribute) ?? "",
                                    frame: frame, index: found.count, state: state, document: document))
        }
        return found
    }

    /// Brings a window to the front: its app, then the window itself.
    func focus(_ window: OpenWindow) {
        window.app.activate()
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        Log.trace("Window focused: \(window.appName)")
    }

    // MARK: - Layouts

    /// By name. Read again only when the folder changed: the launcher asks
    /// on every key.
    func layouts() -> [SavedWindowLayout] {
        guard let folder else { return [] }
        let stamp = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached, cached.stamp == stamp, stamp != nil { return cached.layouts }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let layouts = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SavedWindowLayout.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cached = (stamp, layouts)
        return layouts
    }

    func layout(named name: String) -> SavedWindowLayout? {
        let all = layouts()
        return all.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ?? all.first { $0.id == Snippet.fileID(for: name) }
    }

    /// Where every window is now, under `name`, not written: minimized and
    /// full-screen ones too, hidden apps', each window's display by who it
    /// is. The layout editor shows it before it is saved.
    func capture(_ name: String) -> SavedWindowLayout {
        let open = windows(all: true)
        let displays = Displays.current()
        var hidden: [String] = []
        for window in open where window.app.isHidden {
            if let id = window.app.bundleIdentifier, !hidden.contains(id) { hidden.append(id) }
        }
        return SavedWindowLayout(
            id: Snippet.fileID(for: name), name: name,
            windows: open.map {
                .init(bundleID: $0.app.bundleIdentifier ?? "", appName: $0.appName, title: $0.title, index: $0.index, frame: $0.frame,
                      display: WindowLayoutPlan.display(of: $0.frame, among: displays), state: $0.state, document: $0.document)
            },
            displays: displays,
            hiddenApps: hidden
        )
    }

    /// Where every window is now, saved under `name` at once (the same name
    /// replaces), but the apps in `ignoring`: for agents, which have no
    /// editor.
    @discardableResult
    func save(_ name: String, ignoring: Set<String> = []) throws -> SavedWindowLayout {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw Failure(message: "A layout needs a name: “save layout Coding”.") }
        var layout = capture(name)
        layout.windows.removeAll { ignoring.contains($0.bundleID) }
        layout.hiddenApps.removeAll { ignoring.contains($0) }
        // Taken anew, a layout keeps the files and links it opens.
        if let existing = self.layout(named: name) { layout.windows += existing.openings(on: layout.displays) }
        guard !layout.windows.isEmpty else { throw Failure(message: "No windows to save.") }
        try store(layout)
        Log.trace("Window layout “\(name)” saved: \(layout.windows.count) windows on \(layout.displays.map(\.label).joined(separator: ", "))")
        return layout
    }

    /// Written to its file (the same id replaces).
    func store(_ layout: SavedWindowLayout) throws {
        guard let folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(layout).write(to: folder.appendingPathComponent("\(layout.id).json"), options: .atomic)
        cached = nil
        revision += 1
    }

    func delete(_ id: String) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id).json"))
        cached = nil
        revision += 1
    }

    /// Every saved window back in its place: its app opened when it is not
    /// running, its file opened when it is not; the same file first, then
    /// the same title, then the same rank. The files, folders and links the
    /// layout opens are opened when no window shows them yet, and the
    /// window each opens in takes its place. Each display is found by who
    /// it is; one resized keeps the proportions, one that is gone hands its
    /// windows to the nearest. What it did and had to adapt.
    func apply(_ layout: SavedWindowLayout) async -> LayoutReport {
        let start = ContinuousClock.now
        let plan = WindowLayoutPlan.placement(of: layout, on: Displays.current())
        var report = LayoutReport(name: layout.name, total: layout.windows.count, changes: plan.changes)
        var bundleIDs: [String] = []
        for window in layout.windows where !bundleIDs.contains(window.bundleID) { bundleIDs.append(window.bundleID) }
        for bundleID in bundleIDs {
            let indices = layout.windows.indices.filter { layout.windows[$0].bundleID == bundleID }
            let saved = indices.map { layout.windows[$0] }
            // Not running: started with what the layout opens in it.
            let openings = saved.compactMap { $0.opens.flatMap(URL.init(string:)) }
                .filter { !$0.isFileURL || FileManager.default.fileExists(atPath: $0.path) }
            guard let (app, launched) = await running(bundleID, opening: openings) else {
                report.changes.append(.notInstalled(app: saved[0].appName))
                continue
            }
            if app.isHidden { app.unhide() }
            // Just opened: its windows come a moment later (the files are
            // opened below, no need to wait for them to come back alone).
            var current = launched
                ? await windowsAppearing(of: app, wanted: saved.contains { $0.document != nil || $0.opens != nil } ? 0 : saved.count)
                : windows(of: app, all: true)
            // Files that are not open: opened again by their app.
            let shown = Set(current.compactMap(\.document))
            let files = saved.compactMap(\.document).filter { !shown.contains($0) }
                .compactMap { URL(string: $0) }.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
            if !files.isEmpty, let appURL = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.open(files, withApplicationAt: appURL, configuration: configuration)
                current = await windowsAppearing(of: app, wanted: 0, documents: Set(files.map(\.absoluteString)))
            }
            // What the layout opens: the window showing it, else opened now
            // and the window it came in. Kept by element: a new window
            // comes first in the app's list, the indices move.
            var opened: [Int: AXUIElement] = [:]
            for (offset, window) in saved.enumerated() {
                guard let opening = window.opens else { continue }
                let (now, element) = await openingWindow(opening, of: app, current: current, taken: Array(opened.values), opened: launched)
                current = now
                if let element { opened[offset] = element }
            }
            var decided: [Int: Int] = [:]
            for (offset, element) in opened {
                if let index = current.firstIndex(where: { CFEqual($0.element, element) }) { decided[offset] = index }
            }
            let matches = WindowLayoutPlan.match(saved: saved, current: current.map(\.title), documents: current.map(\.document), decided: decided)
            var larger = false
            for (offset, match) in matches.enumerated() {
                guard let match else { continue }
                let index = indices[offset]
                guard let keptLarger = await put(current[match], at: plan.frames[index], within: plan.visible[index], as: saved[offset].state) else { continue }
                report.placed += 1
                larger = larger || keptLarger
            }
            if larger { report.changes.append(.larger(app: saved[0].appName)) }
            let missing = matches.filter { $0 == nil }.count
            if missing > 0 { report.changes.append(.notOpen(app: saved[0].appName, windows: missing)) }
            if layout.hiddenApps.contains(bundleID) { app.hide() }
        }
        Log.trace("Window layout “\(layout.name)”: \(report.placed) of \(layout.windows.count) windows placed, \(report.changes.count) changes, in \((ContinuousClock.now - start).compact)")
        return report
    }

    /// One window at `frame` in the state saved: out of full screen or the
    /// Dock first when it has to move, kept on its display when its app
    /// keeps it larger, then into the Dock or full screen again. Nil when it
    /// could not be moved; true when the app kept it larger than asked.
    private func put(_ window: OpenWindow, at frame: CGRect, within visible: CGRect, as state: SavedWindowLayout.Window.State) async -> Bool? {
        let pid = window.app.processIdentifier
        // Already where it should be: left alone (no Dock or full-screen animation).
        if state == .minimized, window.state == .minimized { return false }
        if state == .fullScreen, window.state == .fullScreen, visible.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) { return false }
        if window.state == .fullScreen {
            AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, kCFBooleanFalse)
            _ = await AXWait.until(pid: pid, element: window.element, notifications: [kAXResizedNotification, kAXMovedNotification], timeout: .seconds(3)) {
                Self.bool(window.element, "AXFullScreen") == false
            }
        }
        if window.state == .minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            _ = await AXWait.until(pid: pid, element: window.element, notifications: [kAXWindowDeminiaturizedNotification], timeout: .seconds(2)) {
                Self.bool(window.element, kAXMinimizedAttribute) == false
            }
        }
        guard (try? WindowManager.place(window.element, of: window.appElement, at: frame)) != nil else { return nil }
        var placed = Self.frame(window.element) ?? frame
        let inside = WindowLayoutPlan.kept(placed, inside: visible)
        if inside.origin != placed.origin, (try? WindowManager.place(window.element, of: window.appElement, at: inside)) != nil {
            placed = Self.frame(window.element) ?? inside
        }
        let larger = placed.width > frame.width + 12 || placed.height > frame.height + 12
        switch state {
        case .normal: break
        case .minimized: AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        case .fullScreen: AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, kCFBooleanTrue)
        }
        return larger
    }

    /// The window of `app` that shows `opening` (a file, a folder, a link):
    /// one already does, or it is opened now (in the background; `opened`:
    /// the app was just started with it) and the window it shows in is
    /// waited for: the one that says it shows it (its file, its address,
    /// its name as the title), else, for a link (browsers that say no
    /// address) or once the wait is over, the first new window. Woken by
    /// Accessibility, 4 s at most. The app's windows after it, and that
    /// window. `taken`: windows other openings already have.
    private func openingWindow(_ opening: String, of app: NSRunningApplication, current: [OpenWindow], taken: [AXUIElement],
                               opened: Bool) async -> (windows: [OpenWindow], window: AXUIElement?) {
        let before = opened ? [] : current
        let link = LayoutOpening.kind(of: opening) == .link
        func free(_ window: OpenWindow) -> Bool { !taken.contains { CFEqual($0, window.element) } }
        func showing(_ windows: [OpenWindow]) -> Int? {
            windows.indices.first { index in
                guard free(windows[index]) else { return false }
                // A browser that says no document: its page's address.
                let document = Self.rawDocument(windows[index].element)
                    ?? (link ? BrowserTabs.pageURL(of: windows[index].element)?.absoluteString : nil)
                return LayoutOpening.shows(opening, title: windows[index].title, document: document)
            }
        }
        func new(_ windows: [OpenWindow]) -> Int? {
            windows.indices.first { index in free(windows[index]) && !before.contains { CFEqual($0.element, windows[index].element) } }
        }
        if !opened, let index = showing(current) { return (current, current[index].element) }
        guard let url = URL(string: opening), !url.isFileURL || FileManager.default.fileExists(atPath: url.path) else {
            Log.trace("Window layout: “\(LayoutOpening.name(of: opening))” is gone, not opened")
            return (current, nil)
        }
        if !opened, let appURL = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
        var now = windows(of: app, all: true)
        var index = showing(now) ?? (link ? new(now) : nil)
        if index == nil {
            _ = await AXWait.until(pid: app.processIdentifier, element: AXUIElementCreateApplication(app.processIdentifier),
                                   notifications: [kAXWindowCreatedNotification, kAXTitleChangedNotification, kAXFocusedWindowChangedNotification],
                                   timeout: .seconds(4)) {
                now = windows(of: app, all: true)
                index = showing(now) ?? (link ? new(now) : nil)
                return index != nil
            }
            if index == nil { index = new(now) }
            // A link opened in a tab of the window in front, by a browser
            // that does not say its address: that window.
            if index == nil, link, let front = Self.focusedWindow(of: app) {
                index = now.indices.first { free(now[$0]) && CFEqual(now[$0].element, front) }
            }
        }
        Log.trace("Window layout: opened “\(LayoutOpening.name(of: opening))” in \(app.localizedName ?? "?") (\(app.processIdentifier)), \(index == nil ? "no window showed it among \(now.map { "“\($0.title)”" })" : "its window found")")
        return (now, index.map { now[$0].element })
    }

    /// The app's window in front (Accessibility's focused window).
    private static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// A window's AXDocument as the app says it: a file's URL, or a page's
    /// address (Safari).
    private static func rawDocument(_ window: AXUIElement) -> String? {
        string(window, kAXDocumentAttribute)
    }

    /// The app, opened (in the background) when it is not running, with
    /// `opening` (files, folders, links) when there are some.
    private func running(_ bundleID: String, opening: [URL] = []) async -> (app: NSRunningApplication, launched: Bool)? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { return (app, false) }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let app = opening.isEmpty
            ? try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            : try? await NSWorkspace.shared.open(opening, withApplicationAt: url, configuration: configuration)
        guard let app else { return nil }
        return (app, true)
    }

    /// An app just opened shows its windows a moment later: waits until it
    /// finished launching with `wanted` windows and the files in
    /// `documents` shown, woken by Accessibility each time a window is
    /// created, 4 s at most.
    private func windowsAppearing(of app: NSRunningApplication, wanted: Int, documents: Set<String> = []) async -> [OpenWindow] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var current = windows(of: app, all: true)
        _ = await AXWait.until(pid: app.processIdentifier, element: element, notifications: [kAXWindowCreatedNotification], timeout: .seconds(4)) {
            current = windows(of: app, all: true)
            return app.isFinishedLaunching && current.count >= wanted && documents.isSubset(of: Set(current.compactMap(\.document)))
        }
        return current
    }

    // MARK: - Accessibility

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func frame(_ window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }
}
