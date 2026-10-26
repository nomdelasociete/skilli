import AppKit
import Carbon.HIToolbox
import Observation
import SkilliCore
import SwiftUI

/// Settings' search (`SettingsSearch`): the field atop the sidebar, as in
/// System Settings; while it holds text, the panes that match in place of
/// the sidebar, each with its rows that match under it; and the way to a
/// row: its pane opened, Advanced opened when the row is under it, the row
/// scrolled to the middle and glowing a moment in the accent color.
@MainActor
@Observable
final class SettingsSearchModel {
    /// One line of the results: a pane (`item` nil) or a row of it.
    struct Row: Identifiable, Equatable {
        let id: String
        let pane: SettingsPane
        let item: SettingsSearch.Item?
    }

    /// What is typed in the field.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            // A search starts: the Catalog as it is now, the index built again.
            if oldValue.trimmingCharacters(in: .whitespaces).isEmpty {
                catalogEntries = FeatureCatalog.entries(catalogInput())
                index = nil
            }
            refresh()
        }
    }
    private(set) var rows: [Row] = []
    /// The row ↑↓ moved to and ↩ opens (an anchor; a pane's own row:
    /// `SettingsSearch.paneAnchor`).
    var selected: String?
    /// The row to scroll to, each time `scrollRequest` changes.
    private(set) var scrollTarget: String?
    private(set) var scrollRequest = 0
    /// The row glowing now; its glow starts each time `glowRequest` changes.
    private(set) var glowing: String?
    private(set) var glowRequest = 0
    /// The row being looked for: an Advanced section holding it opens
    /// (`AdvancedSection.anchors`), Catalog draws its lists at once.
    private(set) var revealing: String?

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Self-test hook: the glow stays lit, for its capture.
    static var holdsGlow = false

    @ObservationIgnored private let navigation: SettingsNavigation
    /// The shortcuts the index holds (Keys), read when a search starts.
    @ObservationIgnored var shortcuts: ShortcutStore?
    /// What skil.li does and what the user made, as the Catalog lists it:
    /// read when a search starts (a command or a snippet made meanwhile).
    @ObservationIgnored var catalogInput: () -> FeatureCatalog.Input = { FeatureCatalog.Input() }
    /// Before a row of `pane` is looked for (Catalog: its own search cleared).
    /// Before a row is looked for in `pane`: true when that makes the
    /// pane draw anew (Apps pushes the app's page holding it).
    @ObservationIgnored var beforeReveal: (_ pane: SettingsPane, _ anchor: String) -> Bool = { _, _ in false }
    /// `pane` still reads what its rows show (Apps' shortcuts): a row not
    /// there yet is waited for, within the reveal's 2 s.
    @ObservationIgnored var revealIsLoading: (_ pane: SettingsPane) -> Bool = { _ in false }
    /// The pane on screen back to its top.
    @ObservationIgnored var scrollToTop: () -> Void = {}
    @ObservationIgnored weak var field: NSSearchField?
    @ObservationIgnored private var index: SettingsSearch.Index?
    @ObservationIgnored private var indexedShortcuts: [String] = []
    /// The Catalog's entries, read when a search starts.
    @ObservationIgnored private var catalogEntries: [CatalogEntry] = []
    /// Anchors on screen now, counted: a shortcut's row shows in several
    /// panes, and the one leaving may say so after the one coming.
    @ObservationIgnored private var present: [String: Int] = [:]
    /// Where each anchor is, in the window's content (SwiftUI's global).
    @ObservationIgnored private(set) var frames: [String: CGRect] = [:]
    /// The pane of the row being looked for; whether that pane is still
    /// to be drawn (it was switched to).
    @ObservationIgnored private var revealPane: SettingsPane?
    @ObservationIgnored private var awaitingPane = false
    @ObservationIgnored private var revealCount = 0
    /// The anchors under an Advanced section on screen that is closed.
    @ObservationIgnored private var closedAdvanced: [String: Int] = [:]
    /// Self-test hook: where the last row looked for was shown ("" its
    /// pane's top), and how long the last keystroke's search took.
    @ObservationIgnored private(set) var landed: String?
    @ObservationIgnored private(set) var lastSearch: Duration = .zero

    init(navigation: SettingsNavigation) {
        self.navigation = navigation
    }

    // MARK: Typing

    private func refresh() {
        guard isSearching else {
            rows = []
            selected = nil
            return
        }
        let start = ContinuousClock.now
        let groups = currentIndex().search(query)
        lastSearch = .now - start
        rows = groups.flatMap { group -> [Row] in
            guard let pane = SettingsPane(rawValue: group.pane) else { return [] }
            return [Row(id: SettingsSearch.paneAnchor(group.pane), pane: pane, item: nil)]
                + group.hits.map { Row(id: $0.anchor, pane: pane, item: $0) }
        }
        // The best first: the pane when it matched best, else its best row.
        selected = groups.first.flatMap { $0.paneFirst ? SettingsSearch.paneAnchor($0.pane) : $0.hits.first?.anchor }
    }

    /// Built once, again when the shortcuts changed since.
    private func currentIndex() -> SettingsSearch.Index {
        let entries = shortcuts?.config.shortcuts ?? []
        let signature = entries.map { "\($0.id)\u{1}\($0.title)" }
        if let index, signature == indexedShortcuts { return index }
        let index = Self.makeIndex(shortcuts, entries: catalogEntries)
        self.index = index
        indexedShortcuts = signature
        return index
    }

    /// Every pane, setting, row, shortcut, permission and Catalog entry, as
    /// Settings names them.
    static func makeIndex(_ store: ShortcutStore?, entries: [CatalogEntry] = []) -> SettingsSearch.Index {
        let panes = SettingsPane.allCases.map { SettingsSearch.PaneInfo(id: $0.rawValue, title: $0.title, line: $0.subtitle) }
        var shortcuts: [SettingsSearch.Named] = []
        if let store {
            shortcuts = store.config.shortcuts.map {
                SettingsSearch.Named(pane: SettingsPane.keys.rawValue, anchor: SettingsSearch.shortcutAnchor($0.id), title: store.title(of: $0))
            }
            shortcuts.append(SettingsSearch.Named(pane: SettingsPane.launcher.rawValue,
                                                  anchor: SettingsSearch.shortcutAnchor(ShortcutStore.launcherOpenSettingsID),
                                                  title: LauncherPane.openSettingsTitle))
        }
        let permissions = Permission.allCases.map {
            SettingsSearch.Named(pane: SettingsPane.privacy.rawValue, anchor: SettingsSearch.permissionAnchor($0.rawValue), title: $0.title)
        }
        return SettingsSearch.Index(panes: panes, shortcuts: shortcuts, permissions: permissions, entries: SettingsSearch.entries(entries))
    }

    /// Letters typed while the sidebar's list has the keys: into the field.
    func type(_ text: String) {
        query += text
        // In the field now, before it takes the keys: the caret after it.
        field?.stringValue = query
        focus(selectingAll: false)
    }

    /// ⌘F: the field, its text selected.
    func focus(selectingAll: Bool = true) {
        guard let field, let window = field.window else { return }
        if window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
        let length = (field.stringValue as NSString).length
        field.currentEditor()?.selectedRange = selectingAll ? NSRange(location: 0, length: length) : NSRange(location: length, length: 0)
    }

    /// Esc: the whole sidebar again, the pane open selected in it.
    func clear() {
        query = ""
    }

    /// ↑↓ (and ⌃P ⌃N) in the field.
    func move(_ step: Int) {
        guard !rows.isEmpty else { return }
        let now = selected.flatMap { id in rows.firstIndex { $0.id == id } } ?? (step > 0 ? -1 : rows.count)
        selected = rows[min(max(now + step, 0), rows.count - 1)].id
    }

    /// ↩ in the field.
    func openSelected() {
        if let selected { open(selected) }
    }

    /// A result clicked, or ↩ on it: its pane, at its row.
    func open(_ id: String) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        selected = id
        if let item = row.item {
            reveal(item.anchor, in: row.pane)
            return
        }
        // The pane itself: its top (Apps: its list, not an app's page).
        _ = beforeReveal(row.pane, row.id)
        if navigation.pane == row.pane {
            scrollToTop()
        } else {
            navigation.pane = row.pane
        }
    }

    // MARK: Showing a row

    /// Opens `pane` at the row anchored `anchor`: scrolled to the middle,
    /// glowing. Advanced opens when the row is under it; a row shown only
    /// with another setting on leads to that one (`SettingsSearch.shownWith`).
    /// Each step follows what SwiftUI draws (the rows' `onAppear`), never a
    /// delay; a guard gives up after 2 s on a pane that draws no row.
    /// `drawing`: the row was just added, not drawn yet: waited for.
    func reveal(_ anchor: String, in pane: SettingsPane, drawing: Bool = false) {
        revealing = anchor
        revealPane = pane
        landed = nil
        revealCount += 1
        let redrawn = beforeReveal(pane, anchor) || drawing
        if navigation.pane != pane || redrawn {
            // Its rows say when it is drawn.
            awaitingPane = true
            navigation.pane = pane
        } else {
            awaitingPane = false
            settle()
        }
        // A pane that never draws a row (none): given up, not left waiting.
        let count = revealCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.revealCount == count, self.revealing != nil else { return }
            self.awaitingPane = false
            self.giveUp()
        }
    }

    /// Once SwiftUI has drawn what changed: the main queue's next turn
    /// (an update's `onAppear`s all run within it).
    private func settle() {
        DispatchQueue.main.async { [weak self] in self?.step() }
    }

    private func step() {
        guard let anchor = revealing, !awaitingPane else { return }
        if (present[anchor] ?? 0) > 0 {
            land(anchor)
        } else if (closedAdvanced[anchor] ?? 0) > 0 {
            // Its Advanced opens (it saw `revealing`): the row lands as it appears.
        } else if let pane = revealPane, revealIsLoading(pane) {
            // Its rows are being read: the row lands as it appears.
        } else {
            giveUp()
        }
    }

    /// Not in the pane as it is now (shown only while another setting is
    /// on, or a list with nothing in it): that setting, else the pane's top.
    private func giveUp() {
        guard let anchor = revealing, let pane = revealPane else { return }
        revealing = nil
        if let other = SettingsSearch.shownWith[anchor], !other.isEmpty {
            reveal(other, in: pane)
        } else {
            landed = ""
            scrollToTop()
        }
    }

    private func land(_ anchor: String) {
        revealing = nil
        landed = anchor
        scrollTarget = anchor
        scrollRequest += 1
        glowing = anchor
        glowRequest += 1
    }

    // MARK: Anchors (`settingAnchor`, `AdvancedSection`)

    func appeared(_ anchor: String) {
        present[anchor, default: 0] += 1
        guard let revealing else { return }
        if anchor == revealing {
            awaitingPane = false
            settle()
        } else if awaitingPane {
            // The pane's first rows: it is drawn, all of it.
            awaitingPane = false
            settle()
        }
    }

    func disappeared(_ anchor: String) {
        let count = (present[anchor] ?? 1) - 1
        present[anchor] = count > 0 ? count : nil
    }

    func moved(_ anchor: String, to frame: CGRect) {
        frames[anchor] = frame
    }

    /// An Advanced section on screen, closed: what it holds is looked for
    /// there (it opens when `revealing` is one of them).
    func advancedClosed(_ anchors: [String]) {
        for anchor in anchors { closedAdvanced[anchor, default: 0] += 1 }
    }

    /// It opened, or left the screen closed.
    func advancedOpened(_ anchors: [String]) {
        for anchor in anchors {
            let count = (closedAdvanced[anchor] ?? 0) - 1
            closedAdvanced[anchor] = count > 0 ? count : nil
        }
        // Opened for a row it does not show now: what shows it instead.
        if let revealing, anchors.contains(revealing) { settle() }
    }

    /// The window closed: its rows are gone with it (their `onDisappear`
    /// may not say so), and the next opening starts with the panes.
    func windowClosed() {
        present = [:]
        closedAdvanced = [:]
        frames = [:]
        revealing = nil
        awaitingPane = false
        query = ""
    }
}

extension SettingsPane {
    /// The pane a sidebar row's anchor names (`SettingsSearch.paneAnchor`).
    init?(anchor: String) {
        guard anchor.hasPrefix("pane.") else { return nil }
        self.init(rawValue: String(anchor.dropFirst(5)))
    }
}

// MARK: - Anchors

extension View {
    /// Where Settings' search finds this row: a `SettingsTable` key or one
    /// of `SettingsSearch.rows`' anchors, written as a literal (the unit
    /// tests read them). Scrolled to and glowing when found.
    func settingAnchor(_ key: String) -> some View {
        modifier(SettingAnchor(key: key))
    }
}

private struct SettingAnchor: ViewModifier {
    let key: String
    @Environment(SettingsSearchModel.self) private var search: SettingsSearchModel?
    @State private var glow = 0.0

    func body(content: Content) -> some View {
        content
            // Only while it glows: every row of every pane has an anchor.
            .background { if glow > 0 { SettingGlow(level: glow) } }
            .id(key)
            .onAppear { search?.appeared(key) }
            .onDisappear { search?.disappeared(key) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { search?.moved(key, to: $0) }
            .onChange(of: search?.glowRequest) {
                guard search?.glowing == key else { return }
                // In at once, a moment lit, then gone: about a second.
                withAnimation(.easeOut(duration: 0.12)) {
                    glow = 1
                } completion: {
                    guard !SettingsSearchModel.holdsGlow else { return }
                    withAnimation(.easeInOut(duration: 0.8).delay(0.3)) { glow = 0 }
                }
            }
    }
}

/// A soft accent glow around a found row, just past its edges and inside
/// its group's card.
private struct SettingGlow: View {
    let level: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        shape
            .fill(Color.accentColor.opacity(0.15 * level))
            .overlay { shape.strokeBorder(Color.accentColor.opacity(0.5 * level), lineWidth: 1) }
            .padding(.horizontal, -6)
            .padding(.vertical, -4)
            .allowsHitTesting(false)
    }
}

// MARK: - Sidebar

/// The sidebar: the search field on top; under it the panes in their
/// blocks, or, while searching, what was found.
struct SettingsSidebar: View {
    @Bindable var navigation: SettingsNavigation
    @Bindable var search: SettingsSearchModel

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                if search.isSearching {
                    ForEach(search.rows) { row in
                        if let item = row.item {
                            SIText(item.title)
                                .lineLimit(2)
                                .padding(.leading, Self.indent)
                                .tag(row.id)
                        } else {
                            PaneLabel(pane: row.pane)
                                .tag(row.id)
                        }
                    }
                } else {
                    // One section per block, without a header: the gap
                    // between them is the grouping, as in System Settings.
                    ForEach(Array(SettingsPane.blocks.enumerated()), id: \.offset) { _, block in
                        Section {
                            ForEach(block) { pane in
                                PaneLabel(pane: pane)
                                    .tag(SettingsSearch.paneAnchor(pane.rawValue))
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if search.isSearching, search.rows.isEmpty {
                    Text("No Results for “\(search.query.trimmingCharacters(in: .whitespaces))”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
            .onChange(of: search.selected) {
                if let selected = search.selected { proxy.scrollTo(selected) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsSearchField(model: search)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
    }

    /// A found row starts where its pane's title does: past the tile.
    static let indent: CGFloat = 30

    /// The panes' rows select a pane; the results' open what they found.
    private var selection: Binding<String?> {
        Binding(
            get: { search.isSearching ? search.selected : navigation.pane.map { SettingsSearch.paneAnchor($0.rawValue) } },
            set: { id in
                guard let id else { return }
                if search.isSearching {
                    search.open(id)
                } else if let pane = SettingsPane(anchor: id) {
                    navigation.pane = pane
                }
            })
    }
}

/// A pane in the sidebar: its tinted tile and its name.
private struct PaneLabel: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            SIText(pane.title)
        } icon: {
            IconTile(symbol: pane.symbol, tint: pane.tint, size: 22)
        }
    }
}

/// The native search field (magnifier, ⓧ): ↑↓ move through what was
/// found, ↩ opens it, esc gives the panes back.
struct SettingsSearchField: NSViewRepresentable {
    let model: SettingsSearchModel

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.setAccessibilityLabel("Search Settings")
        model.field = field
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.model = model
        if field.stringValue != model.query { field.stringValue = model.query }
        model.field = field
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var model: SettingsSearchModel

        init(model: SettingsSearchModel) {
            self.model = model
        }

        /// Each key typed, and the ⓧ.
        @objc func changed(_ sender: NSSearchField) {
            if model.query != sender.stringValue { model.query = sender.stringValue }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            changed(field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                model.move(-1)
            case #selector(NSResponder.moveDown(_:)):
                model.move(1)
            // ⌘↓ to the end, as ⌘↑ goes to the start: a search field
            // ignores it on its own.
            case #selector(NSResponder.moveToEndOfDocument(_:)):
                textView.moveToEndOfLine(nil)
            case #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)):
                textView.moveToEndOfLineAndModifySelection(nil)
            case #selector(NSResponder.insertNewline(_:)):
                guard model.isSearching else { return false }
                model.openSelected()
            case #selector(NSResponder.cancelOperation(_:)):
                guard model.isSearching else { return false }
                model.clear()
            default:
                return false
            }
            return true
        }
    }
}

/// The Settings window: ⌘F goes to the search field, and a letter typed
/// while the sidebar's list has the keys goes into it.
final class SettingsWindow: NSWindow {
    var onFind: () -> Void = {}
    /// A key typed while the sidebar has the keys; true when it was taken.
    var onSidebarKey: (NSEvent) -> Bool = { _ in false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFind()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onSidebarKey(event) { return }
        super.sendEvent(event)
    }

    /// What typing a key in a list would type: no ⌘, ⌃ or ⌥, no arrow,
    /// function key, ↩, ⇥ or esc.
    static func typedText(_ event: NSEvent) -> String? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .control, .option]),
              let text = event.characters, !text.isEmpty
        else { return nil }
        let typed = text.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return typed ? text : nil
    }

    static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_Escape)
    }
}
