import AppKit
import Observation
import SkilliCore
import SwiftUI

/// A window layout being looked over before it is saved: every window
/// taken, each kept or left out, moved and resized on a picture of the
/// displays, its state chosen.
@MainActor
@Observable
final class LayoutDraft {
    struct Item: Identifiable, Equatable {
        /// Its place in what was taken.
        let id: Int
        var window: SavedWindowLayout.Window
        var included: Bool
    }

    var name: String
    var items: [Item]
    let displays: [LayoutDisplay]
    /// Which displays are connected now (the others are drawn as such).
    let connected: Set<Int>
    var hiddenApps: Set<String>
    /// What happens when one of its displays is plugged in.
    var automatic: SavedWindowLayout.Automatic
    /// Left out of every layout taken (Settings → Windows).
    var alwaysIgnored: Set<String>
    var selection: Int?
    /// The layout this one replaces: the one edited, or taken anew.
    let replacing: String?
    /// Points between windows and at the edges (Settings → Windows): where
    /// windows placed here stick, as ✦W leaves them.
    let gap: CGFloat
    @ObservationIgnored private let original: [Item]
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    /// `leftOut`: apps unticked from the start (left out of the layout it
    /// replaces, or always). What the layout opens is always kept.
    init(layout: SavedWindowLayout, current: [LayoutDisplay], replacing: String?, alwaysIgnored: Set<String>, leftOut: Set<String>,
         gap: CGFloat = 0) {
        // Layouts saved before skil.li knew displays are drawn on today's.
        let shown = layout.displays.isEmpty ? current : layout.displays
        let pairs = DisplayPairing.pair(saved: shown, current: current)
        let taken = layout.windows.enumerated().map { offset, window in
            var window = window
            if window.display == nil { window.display = WindowLayoutPlan.display(of: window.frame, among: shown) }
            return Item(id: offset, window: window,
                        included: window.opens != nil || (!leftOut.contains(window.bundleID) && !alwaysIgnored.contains(window.bundleID)))
        }
        self.gap = gap
        name = layout.name
        displays = shown
        connected = Set(pairs.indices.filter { if case .same = pairs[$0].match { true } else { false } })
        items = taken
        original = taken
        hiddenApps = Set(layout.hiddenApps)
        automatic = layout.automatic
        self.alwaysIgnored = alwaysIgnored
        self.replacing = replacing
    }

    /// The apps in the order taken, each with its windows (what the layout
    /// opens is listed apart: `openings`).
    var apps: [(bundleID: String, name: String, items: [Item])] {
        var order: [String] = []
        var byApp: [String: [Item]] = [:]
        for item in items where item.window.opens == nil {
            if byApp[item.window.bundleID] == nil { order.append(item.window.bundleID) }
            byApp[item.window.bundleID, default: []].append(item)
        }
        return order.map { ($0, byApp[$0]?.first?.window.appName ?? $0, byApp[$0] ?? []) }
    }

    /// The files, folders and links the layout opens, in the order added.
    var openings: [Item] { items.filter { $0.window.opens != nil } }

    /// The displays that can be plugged in (not the built-in one), by name.
    var pluggable: [String] { displays.filter { !$0.fingerprint.builtIn }.map(\.fingerprint.name) }

    var includedCount: Int { items.filter(\.included).count }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && includedCount > 0 }

    /// The saved layout with this name, when it is another one than the
    /// one replaced: saving writes over it.
    func overwrites(among layouts: [SavedWindowLayout]) -> SavedWindowLayout? {
        let id = Snippet.fileID(for: name.trimmingCharacters(in: .whitespaces))
        return layouts.first { $0.id == id && $0.id != replacing }
    }

    /// What is saved: the windows kept, the apps left out remembered.
    func layout() -> SavedWindowLayout {
        let name = name.trimmingCharacters(in: .whitespaces)
        let kept = items.filter(\.included).map(\.window)
        let keptApps = Set(kept.map(\.bundleID))
        var leftOut: [String] = []
        for item in items where !keptApps.contains(item.window.bundleID) && !leftOut.contains(item.window.bundleID) {
            leftOut.append(item.window.bundleID)
        }
        return SavedWindowLayout(id: Snippet.fileID(for: name), name: name, windows: kept, displays: displays,
                                 hiddenApps: hiddenApps.filter { keptApps.contains($0) }.sorted(), ignoredApps: leftOut, automatic: automatic)
    }

    func item(_ id: Int) -> Item? { items.first { $0.id == id } }

    func setIncluded(_ id: Int, _ on: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].included = on
    }

    /// Every window of an app kept or left out (what the layout opens in
    /// it stays: it goes with −).
    func setIncluded(app bundleID: String, _ on: Bool) {
        for index in items.indices where items[index].window.bundleID == bundleID && items[index].window.opens == nil {
            items[index].included = on
        }
    }

    func setState(_ id: Int, _ state: SavedWindowLayout.Window.State) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].window.state = state
    }

    /// A window at `frame`, on the display under its middle.
    func move(_ id: Int, to frame: CGRect) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].window.frame = frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let display = displays.indices.first(where: { displays[$0].frame.contains(center) }) {
            items[index].window.display = display
        }
    }

    /// A window put where ✦W would: half, third, quarter, fill, center.
    func place(_ id: Int, _ place: WindowLayout) {
        guard let item = item(id), let display = item.window.display, displays.indices.contains(display),
              case .frame(let frame) = place.target(current: item.window.frame, visible: displays[display].visible, gap: gap)
        else { return }
        move(id, to: frame)
    }

    /// A window onto another display, same place in proportion.
    func send(_ id: Int, to display: Int) {
        guard let item = item(id), displays.indices.contains(display) else { return }
        let from = item.window.display.flatMap { displays.indices.contains($0) ? displays[$0] : nil } ?? displays[display]
        move(id, to: WindowLayout.moved(item.window.frame, from: from.visible, to: displays[display].visible))
    }

    /// A window of an app added by hand (an app not open, a layout started
    /// empty): kept, on the display in use (the selected window's, else the
    /// menu bar's), on its first free half or quarter, and selected.
    @discardableResult
    func add(app bundleID: String, name: String) -> Int {
        add(SavedWindowLayout.Window(bundleID: bundleID, appName: name, title: "",
                                     index: items.filter { $0.window.bundleID == bundleID }.count, frame: .zero))
    }

    /// A file, a folder or a link the layout opens when applied
    /// (`LayoutOpening`), in the app that opens it now (`appID`, its name):
    /// its window placed like an app added by hand, to drag where it goes.
    @discardableResult
    func add(opening: String, appID: String, appName: String) -> Int {
        add(SavedWindowLayout.Window(bundleID: appID, appName: appName, title: LayoutOpening.name(of: opening),
                                     index: items.filter { $0.window.bundleID == appID }.count, frame: .zero, opens: opening))
    }

    private func add(_ window: SavedWindowLayout.Window) -> Int {
        let display = selection.flatMap { item($0)?.window.display }.flatMap { displays.indices.contains($0) ? $0 : nil } ?? 0
        let id = (items.map(\.id).max() ?? -1) + 1
        guard displays.indices.contains(display) else { return id }
        let taken = items.filter { $0.included && $0.window.display == display }.map(\.window.frame)
        var window = window
        window.frame = LayoutSnap.freeSpot(among: taken, in: displays[display].visible, gap: gap)
        window.display = display
        items.append(Item(id: id, window: window, included: true))
        alwaysIgnored.remove(window.bundleID)
        selection = id
        return id
    }

    /// Out of the layout altogether (unticking only leaves it out).
    func remove(_ id: Int) {
        items.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    /// Every window out: an empty layout to fill by hand.
    func clear() {
        items.removeAll()
        selection = nil
    }

    /// Every window as it was taken.
    func revert() {
        items = original
    }

    /// The app's icon, small, read once.
    func icon(_ bundleID: String) -> NSImage {
        if let icon = icons[bundleID] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        icon.size = NSSize(width: 32, height: 32)
        icons[bundleID] = icon
        return icon
    }
}

/// The window where a layout is looked over: taken from the windows open
/// ("save layout Coding", New Window Layout…, Update to Current Windows),
/// started empty, or opened to edit. Built on open and released on close, like Settings.
@MainActor
final class LayoutEditorController: NSObject, NSWindowDelegate {
    private let arranger: WindowArranger
    private let preferences: Preferences
    /// The windows put where the draft says, nothing saved.
    var onTry: ((SavedWindowLayout) -> Void)?
    private var window: NSWindow?
    /// The layout being looked over; the self-test reads and changes it.
    private(set) var draft: LayoutDraft?

    init(arranger: WindowArranger, preferences: Preferences) {
        self.arranger = arranger
        self.preferences = preferences
    }

    var isVisible: Bool { window?.isVisible ?? false }
    /// Self-test hook: keys typed now go to the editor.
    var isKey: Bool { window?.isKeyWindow ?? false }

    /// Every window open now, to look over before saving under `name`. A
    /// layout with that name is replaced, and the apps it left out stay out.
    func capture(name: String) {
        let existing = arranger.layout(named: name)
        open(LayoutDraft(layout: taken(name, keeping: existing), current: Displays.current(), replacing: existing?.id,
                         alwaysIgnored: Set(preferences.windowLayoutIgnoredApps), leftOut: Set(existing?.ignoredApps ?? []), gap: gap),
             title: existing == nil ? "New Window Layout" : "Update “\(name)”")
    }

    /// `layout` taken anew from the windows open, its name kept.
    func update(_ layout: SavedWindowLayout) {
        open(LayoutDraft(layout: taken(layout.name, keeping: layout), current: Displays.current(), replacing: layout.id,
                         alwaysIgnored: Set(preferences.windowLayoutIgnoredApps), leftOut: Set(layout.ignoredApps), gap: gap),
             title: "Update “\(layout.name)”")
    }

    /// The windows open now under `name`; a layout taken anew keeps the
    /// files and links it opens.
    private func taken(_ name: String, keeping existing: SavedWindowLayout?) -> SavedWindowLayout {
        var layout = arranger.capture(name)
        layout.windows += existing?.openings(on: layout.displays) ?? []
        return layout
    }

    /// Settings → Windows → Space between windows.
    private var gap: CGFloat { CGFloat(preferences.windowGap) }

    /// A layout started empty: the displays there are now, apps added by
    /// hand.
    func startEmpty(name: String = "") {
        open(LayoutDraft(layout: SavedWindowLayout(id: Snippet.fileID(for: name), name: name, windows: []), current: Displays.current(),
                         replacing: nil, alwaysIgnored: Set(preferences.windowLayoutIgnoredApps), leftOut: [], gap: gap),
             title: "New Empty Window Layout")
    }

    /// A saved layout, as saved.
    func edit(_ layout: SavedWindowLayout) {
        open(LayoutDraft(layout: layout, current: Displays.current(), replacing: layout.id,
                         alwaysIgnored: Set(preferences.windowLayoutIgnoredApps), leftOut: [], gap: gap),
             title: "Edit “\(layout.name)”")
    }

    private func open(_ draft: LayoutDraft, title: String) {
        self.draft = draft
        let view = LayoutEditorView(
            draft: draft, arranger: arranger,
            save: { [weak self] in self?.save() },
            cancel: { [weak self] in self?.close() },
            tryIt: { [weak self] in self?.onTry?(draft.layout()) },
            alwaysIgnore: { [weak self] bundleID, on in self?.alwaysIgnore(bundleID, on) }
        )
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let window = self.window ?? {
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            return window
        }()
        window.contentViewController = host
        window.title = title
        let isNew = self.window == nil
        self.window = window
        if isNew {
            window.setContentSize(NSSize(width: 980, height: 640))
            window.center()
        }
        Foreground.bring(window)
        Log.trace("Layout editor: \(title), \(draft.items.count) windows on \(draft.displays.count) displays")
    }

    /// Writes the draft (renamed: the old file goes), closes, says so.
    @discardableResult
    func save() -> Bool {
        guard let draft, draft.isValid else {
            NSSound.beep()
            return false
        }
        let layout = draft.layout()
        do {
            try arranger.store(layout)
        } catch {
            NSSound.beep()
            Log.trace("Layout editor: “\(layout.name)” not saved: \(error.localizedDescription)")
            return false
        }
        if let replacing = draft.replacing, replacing != layout.id { arranger.delete(replacing) }
        Log.trace("Layout editor: “\(layout.name)” saved, \(layout.windows.count) windows, \(layout.ignoredApps.count) apps left out")
        close()
        return true
    }

    func close() {
        window?.close()
    }

    /// Left out of every layout taken from now on (Settings → Windows),
    /// or not any more.
    private func alwaysIgnore(_ bundleID: String, _ on: Bool) {
        if on {
            if !preferences.windowLayoutIgnoredApps.contains(bundleID) { preferences.windowLayoutIgnoredApps.append(bundleID) }
            draft?.alwaysIgnored.insert(bundleID)
            draft?.setIncluded(app: bundleID, false)
        } else {
            preferences.windowLayoutIgnoredApps.removeAll { $0 == bundleID }
            draft?.alwaysIgnored.remove(bundleID)
        }
    }

    /// Self-test hook: the window as PNG, as it shows on screen; drawn off
    /// screen when the window server cannot give it yet, like Settings.
    func snapshotPNG() async -> Data? {
        guard let window else { return nil }
        if let png = await WindowCapture.png(of: window) { return png }
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the SwiftUI hierarchy and the draft.
        window = nil
        draft = nil
    }
}
