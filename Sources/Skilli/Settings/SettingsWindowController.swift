import AppKit
import SwiftUI

/// The Settings window, laid out like System Settings: a glass sidebar of
/// panes and a grouped form per pane. Built on first open and released on
/// close, so SwiftUI costs nothing until Settings is used.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    /// What the panes are given; the self-test calls what their buttons do.
    let makeContext: @MainActor () -> SettingsContext
    private let navigation: SettingsNavigation
    /// Where the pointer is over General; the self-test reads it.
    let markTilt = MarkTilt()
    /// Settings → Catalog's search and the alias being typed; the
    /// self-test calls what its controls call.
    let catalog = CatalogPaneModel()
    /// Settings → Apps' page and the shortcut its rows record; the
    /// self-test calls what its controls call.
    let apps = AppsPaneModel()
    /// The search atop the sidebar; kept with its index while the window
    /// comes and goes. The self-test reads it.
    let search: SettingsSearchModel
    /// The part of the Catalog to show once all its rows are in.
    private var pendingSection: String?
    /// A New … asked while an editor was open: shown once it closes.
    private var waitingNew: SettingsNew?
    private var sheetObserver: NSObjectProtocol?
    /// The commands' model outlives the window: its editor is closed with it.
    private weak var commands: AICommandsModel?
    private var window: NSWindow?

    init(preferences: Preferences, makeContext: @escaping @MainActor () -> SettingsContext) {
        self.preferences = preferences
        self.makeContext = makeContext
        let navigation = SettingsNavigation()
        self.navigation = navigation
        search = SettingsSearchModel(navigation: navigation)
        super.init()
        // A row looked for in the Catalog: its whole list, not what was
        // searched there.
        search.beforeReveal = { [weak self] pane, anchor in
            guard let self else { return false }
            if pane == .catalog { self.catalog.search = "" }
            // A row of an app's page: that page, drawn anew.
            guard pane == .apps else { return false }
            let page = AppsPaneModel.page(for: anchor)
            defer { self.apps.page = page }
            return self.apps.page != page
        }
        search.scrollToTop = { [weak self] in self?.scrollDetailToTop() }
        catalog.onAllRowsShown = { [weak self] in
            guard let self, self.pendingSection != nil else { return }
            self.pendingSection = nil
            self.showCatalogEnd()
        }
    }

    /// The Catalog's end, where its quicklinks are: laid out now, then
    /// scrolled to.
    private func showCatalogEnd() {
        window?.contentView?.layoutSubtreeIfNeeded()
        _ = scrollPaneToBottom()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Self-test hook: the window's number, to tell it under the pointer.
    var windowNumber: Int? { window?.windowNumber }

    /// Self-test hook: the pane on screen.
    var pane: SettingsPane? { navigation.pane }

    /// Self-test hook: what the panes are given, made now.
    func freshContext() -> SettingsContext { makeContext() }
    var isKey: Bool { window?.isKeyWindow ?? false }
    /// Self-test hook: where the window is on screen.
    var frame: NSRect? { window?.frame }

    /// `section`: a part of the pane to show ("quicklinks", at the end of
    /// Catalog).
    func show(pane: SettingsPane? = nil, section: String? = nil) {
        let isNew = window == nil
        // Already on the Catalog with every row: no new pane to wait for.
        let catalogReady = !isNew && navigation.pane == .catalog && catalog.allRowsShown
        let window = self.window ?? makeWindow()
        self.window = window
        if let pane {
            navigation.pane = pane
            // Opened on a part: the whole list, not what was searched.
            if pane == .catalog, section != nil { catalog.search = "" }
        }
        // SwiftUI retitles the window after its first pass; no "Untitled".
        window.title = navigation.pane == .apps ? apps.title ?? SettingsPane.apps.title : (navigation.pane ?? .general).title
        if isNew { window.center() }
        Foreground.bring(window)
        if isNew {
            // SwiftUI ignores the sidebar's column width in this window;
            // set the divider so the longest name ("Your Details") fits.
            DispatchQueue.main.async { [weak self] in
                self?.widenSidebar()
                // The panes' list takes the keys, as System Settings' does:
                // ↑↓ move through the panes, a letter goes into the search
                // field. AppKit hands them to the field, the first key view.
                self?.sidebarTakesKeys()
            }
        }
        if pane == .catalog, section == "quicklinks" {
            // The quicklinks close the Catalog, with the other aliases: its
            // end, once its rows are all in.
            if catalogReady {
                showCatalogEnd()
            } else {
                pendingSection = section
            }
        }
    }

    /// The launcher's New Snippet, New Quicklink, New Command: the pane that
    /// makes it, its editor open on a new one. An editor open already, on
    /// any pane, keeps its edits: the new one waits until it closes (Save,
    /// Cancel), the window brought forward meanwhile.
    func showNew(_ item: SettingsNew) {
        if window?.attachedSheet != nil {
            waitingNew = item
            show()
            return
        }
        // The latest asked wins: one still waiting does not come after it.
        waitingNew = nil
        navigation.new = item
        switch item {
        case .snippet: show(pane: .snippets)
        case .quicklink: show(pane: .catalog, section: "quicklinks")
        case .command: show(pane: .commands)
        }
    }

    /// Self-test hook: a sheet is open over the window (an editor).
    var sheetShown: Bool { window?.attachedSheet?.isVisible ?? false }
    /// Self-test hook: that sheet has the keys.
    var sheetIsKey: Bool { window?.attachedSheet?.isKeyWindow ?? false }

    /// Self-test hook: switches the open window to `pane` and draws it
    /// now, as a click in the sidebar does; how long that took.
    func showAndDraw(_ pane: SettingsPane) -> Duration {
        guard let window else {
            show(pane: pane)
            return .zero
        }
        let start = ContinuousClock.now
        navigation.pane = pane
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return .now - start
    }

    /// Self-test hook: lays out and draws what changed, now.
    func drawNow() {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
    }

    /// Self-test hook: the window in light or dark (nil follows the Mac),
    /// a popover or a sheet open over it too.
    func setAppearance(_ appearance: NSAppearance?) {
        window?.appearance = appearance
        for popover in Self.popoverWindows + (window?.sheets ?? []) { popover.appearance = appearance }
    }

    /// Self-test hook: a popover is open (a Catalog entry's).
    var popoverShown: Bool { !Self.popoverWindows.isEmpty }

    /// skil.li's popover windows on screen.
    private static var popoverWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
    }

    /// Self-test hook: scrolls the pane back to its top.
    func scrollPaneToTop() {
        guard let content = window?.contentView else { return }
        for scrollView in Self.scrollViews(in: content) where (scrollView.documentView?.frame.height ?? 0) > scrollView.contentView.bounds.height + 1 {
            guard let document = scrollView.documentView else { continue }
            // Its first point in sight, under the toolbar's inset.
            document.scrollToVisible(NSRect(x: 0, y: document.isFlipped ? 0 : document.frame.height - 1, width: 1, height: 1))
        }
    }

    private static let sidebarWidth: CGFloat = 196

    private func widenSidebar() {
        guard let content = window?.contentView, let split = Self.splitView(in: content),
              let sidebar = split.arrangedSubviews.first, sidebar.frame.width < Self.sidebarWidth
        else { return }
        split.setPosition(Self.sidebarWidth, ofDividerAt: 0)
    }

    private static func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.isVertical { return split }
        for subview in view.subviews {
            if let found = splitView(in: subview) { return found }
        }
        return nil
    }

    func close() {
        window?.close()
    }

    /// Self-test hook: the window as PNG, as it shows on screen. Falls back
    /// to an off-screen render, which leaves the sidebar's glass blank.
    func snapshotPNG(withMenu: Bool = false) async -> Data? {
        guard let window else { return nil }
        // A menu open over it (a row's ⋯): both.
        if withMenu, let png = await WindowCapture.png(of: [window], withMenu: true) { return png }
        // A popover (Catalog's) or a sheet (a dialog) open over it: both,
        // as they show.
        let popovers = Self.popoverWindows + window.sheets.filter(\.isVisible)
        if !popovers.isEmpty, let png = await WindowCapture.png(of: [window] + popovers) { return png }
        if let png = await WindowCapture.png(of: window) { return png }
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Self-test hook: whether each switch in the window is on, as AppKit
    /// draws it.
    func switchStates() -> [Bool] {
        guard let content = window?.contentView else { return [] }
        var found: [Bool] = []
        func walk(_ view: NSView) {
            if let control = view as? NSSwitch { found.append(control.state == .on) }
            view.subviews.forEach(walk)
        }
        walk(content)
        return found
    }

    /// Self-test hook: scrolls the pane to its end so a snapshot shows the
    /// rest. False when the pane fits.
    func scrollPaneToBottom() -> Bool {
        guard let content = window?.contentView else { return false }
        // The detail pane's scroll view: the right-most one that overflows.
        let candidates = Self.scrollViews(in: content).filter {
            ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1
        }
        guard let scrollView = candidates.max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }),
              let document = scrollView.documentView
        else { return false }
        let bottom = document.isFlipped ? document.frame.height - scrollView.contentView.bounds.height : 0
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    /// Self-test hook: scrolls the pane down by a screenful (a little less,
    /// so a row cut at the bottom shows whole on the next one). False when
    /// it was already at its end.
    func scrollPaneOnePage() -> Bool {
        guard let content = window?.contentView,
              let scrollView = Self.scrollViews(in: content)
                  .filter({ ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1 })
                  .max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }),
              let document = scrollView.documentView
        else { return false }
        let visible = scrollView.contentView.bounds
        let end = document.frame.height - visible.height
        // Flipped (SwiftUI's forms are): y grows downward.
        let now = document.isFlipped ? visible.minY : end - visible.minY
        guard now < end - 1 else { return false }
        let next = min(end, now + visible.height - 60)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? next : end - next))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    /// Self-test hook: the pane shows its end (opened on Catalog's
    /// quicklinks, or scrolled down).
    var paneAtEnd: Bool {
        guard let content = window?.contentView else { return false }
        let candidates = Self.scrollViews(in: content).filter {
            ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1
        }
        guard let scrollView = candidates.max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }),
              let document = scrollView.documentView
        else { return false }
        let visible = scrollView.documentVisibleRect
        return document.isFlipped ? visible.maxY >= document.frame.height - 2 : visible.minY <= 2
    }

    /// Self-test hook: how far the pane's content runs past the window on
    /// the right (0 when everything fits): a row cut off, a control hidden.
    /// Every visible view's right edge, in the window, against the window's.
    func paneOverflow() -> CGFloat {
        guard let content = window?.contentView else { return 0 }
        func farthest(_ view: NSView) -> CGFloat {
            guard !view.isHidden, view.alphaValue > 0, view.bounds.width > 0 else { return 0 }
            let own = view.convert(view.bounds, to: nil).maxX
            return view.subviews.reduce(own) { max($0, farthest($1)) }
        }
        return max(0, farthest(content) - content.bounds.width)
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        var found = view.subviews.flatMap(scrollViews(in:))
        if let scrollView = view as? NSScrollView { found.append(scrollView) }
        return found
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the SwiftUI hierarchy; reopening rebuilds it in a few ms.
        window = nil
        // Asked and never shown: not on the next open.
        navigation.new = nil
        waitingNew = nil
        if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
        sheetObserver = nil
        // Its sheet went with the window, not its draft: as on Cancel.
        commands?.editing = nil
        search.windowClosed()
        markTilt.pointer(at: nil)
        // A command editor closed with the window: its unsaved shortcuts
        // go with it, as on Cancel.
        search.shortcuts?.discardStaged()
    }

    private func makeWindow() -> NSWindow {
        let context = makeContext()
        search.shortcuts = context.shortcuts
        search.catalogInput = context.catalogInput
        let root = SettingsRootView(preferences: preferences, navigation: navigation, context: context, markTilt: markTilt,
                                    catalog: catalog, apps: apps, search: search)
        let host = NSHostingController(rootView: root)
        // SwiftUI owns the title (the selected pane) and the toolbar.
        host.sceneBridgingOptions = [.title, .toolbars]
        host.sizingOptions = [.preferredContentSize]

        let window = SettingsWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onFind = { [weak self] in self?.search.focus() }
        window.onSidebarKey = { [weak self] event in self?.sidebarKey(event) ?? false }
        commands = context.aiCommands
        // An editor closed: the New … that waited for it.
        sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.waitingNew != nil else { return }
                // After SwiftUI let go of the sheet. Read then, not now: the
                // window closed meanwhile dropped it (`windowWillClose`), so
                // a window opened again never gets it.
                DispatchQueue.main.async {
                    guard let item = self.waitingNew, self.window?.isVisible == true else { return }
                    self.waitingNew = nil
                    self.showNew(item)
                }
            }
        }
        return window
    }

    // MARK: - Search

    /// A key typed while the sidebar's list has the keys: a letter goes into
    /// the search field (as System Settings does), esc ends a search.
    private func sidebarKey(_ event: NSEvent) -> Bool {
        guard let window, let responder = window.firstResponder as? NSView, !(responder is NSText),
              let sidebar = sidebarColumn, responder.isDescendant(of: sidebar)
        else { return false }
        if SettingsWindow.isEscape(event) {
            guard search.isSearching else { return false }
            search.clear()
            return true
        }
        guard let text = SettingsWindow.typedText(event), search.isSearching || text != " " else { return false }
        search.type(text)
        return true
    }

    /// The sidebar's column: the split view's first.
    private var sidebarColumn: NSView? {
        window?.contentView.flatMap(Self.splitView(in:))?.arrangedSubviews.first
    }

    /// The pane on screen, scrolled to its top.
    private func scrollDetailToTop() {
        guard let scrollView = detailScrollView, let document = scrollView.documentView else { return }
        let top = document.isFlipped ? -scrollView.contentInsets.top : document.frame.height - scrollView.contentView.bounds.height
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// The pane's scroll view: the largest outside the sidebar (a text
    /// editor in a pane has its own, inside it).
    private var detailScrollView: NSScrollView? {
        guard let content = window?.contentView else { return nil }
        let sidebar = sidebarColumn
        return Self.scrollViews(in: content).filter { sidebar.map($0.isDescendant(of:)) != true }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// As the window opens: the panes' list has the keys, unless a search
    /// was typed already.
    private func sidebarTakesKeys() {
        guard !search.isSearching else { return }
        _ = focusSidebar()
    }

    /// The sidebar's list takes the keys, as after a click on it (also a
    /// self-test hook).
    func focusSidebar() -> Bool {
        guard let window, let sidebar = sidebarColumn,
              let list = Self.views(in: sidebar).first(where: { $0 is NSTableView })
        else { return false }
        return window.makeFirstResponder(list)
    }

    /// Self-test hook: the panes' list has the keys.
    var sidebarHasKeys: Bool {
        guard let responder = window?.firstResponder as? NSTableView, let sidebar = sidebarColumn else { return false }
        return responder.isDescendant(of: sidebar)
    }

    /// Self-test hook: the text field being typed in (its field editor),
    /// its words and caret.
    var editedText: NSTextView? {
        window?.firstResponder as? NSTextView
    }

    /// Self-test hook: the pane's editable field whose placeholder says
    /// `placeholder` takes the keys.
    func focusField(placeholder: String) -> Bool {
        guard let window, let content = window.contentView else { return false }
        let field = Self.views(in: content).compactMap { $0 as? NSTextField }.first { field in
            field.isEditable && ((field.placeholderString ?? "").contains(placeholder)
                || (field.placeholderAttributedString?.string ?? "").contains(placeholder))
        }
        guard let field else { return false }
        return window.makeFirstResponder(field)
    }

    /// Self-test hook: the search field has the keys.
    var searchFieldFocused: Bool {
        guard let field = search.field, let editor = field.currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    /// Self-test hook: how much of the row anchored `anchor` is in sight in
    /// the pane (0 to 1): under the toolbar or past the window is not.
    func anchorVisibility(_ anchor: String) -> CGFloat {
        guard let content = window?.contentView, let frame = search.frames[anchor], frame.height > 0,
              let scrollView = detailScrollView
        else { return 0 }
        // SwiftUI's global space is the hosting view's, from its top.
        var visible = scrollView.convert(scrollView.bounds, to: content)
        if !content.isFlipped { visible.origin.y = content.bounds.height - visible.maxY }
        visible.origin.y += scrollView.contentInsets.top
        visible.size.height -= scrollView.contentInsets.top
        let shown = visible.intersection(frame)
        return shown.isNull ? 0 : shown.height / frame.height
    }

    private static func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(views(in:))
    }
}
