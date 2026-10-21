import AppKit
import Observation
import SkilliCore
import SwiftUI

/// Settings → Catalog's state: the entries as the pane opened, what is
/// typed in its search field, the entry being edited in its popover. Kept
/// by the window so the self-test calls what the pane's controls call.
@MainActor
@Observable
final class CatalogPaneModel {
    /// Everything skil.li does, read as the pane opens (`FeatureCatalog`,
    /// the list the launcher's "?" reads).
    private(set) var entries: [CatalogEntry] = []
    /// A skillie's shortcut runs its command.
    private(set) var skillies: [ScriptCommand] = []
    var search = ""
    /// The entry whose popover is open, and the alias typed there.
    private(set) var editing: String?
    var aliasDraft = ""
    /// Why the alias typed was not kept, under its field.
    private(set) var aliasProblem: String?
    /// A shortcut the popover added to record.
    @ObservationIgnored private let newShortcut = NewShortcut()
    /// Self-test hook: how long reading the entries took.
    private(set) var lastLoad: Duration?
    /// Every row is in the pane (it draws its first group first, the rest
    /// right after); then the window can scroll to its end.
    var allRowsShown = false
    @ObservationIgnored var onAllRowsShown: (() -> Void)?

    /// The entries that fit the search, best group first: the "?"'s own
    /// filter (each word starts a word of the entry).
    var shown: [CatalogEntry] { FeatureCatalog.filter(entries, search) }

    func load(_ input: FeatureCatalog.Input) {
        let start = ContinuousClock.now
        entries = FeatureCatalog.entries(input)
        skillies = input.skillies
        lastLoad = .now - start
    }

    func entry(_ id: String) -> CatalogEntry? {
        entries.first { $0.id == id }
    }

    func shortcutAction(_ entry: CatalogEntry) -> SkilliAction? {
        entry.shortcutAction(skillies: skillies)
    }

    /// Something to set in its popover: an alias, a shortcut, or whether
    /// search shows it. Rows without any open nothing.
    func isEditable(_ entry: CatalogEntry) -> Bool {
        entry.takesAlias || entry.canBeOff || shortcutAction(entry) != nil
    }

    // MARK: The popover

    /// A click on the row: its popover, the alias as it is.
    func open(_ entry: CatalogEntry, _ preferences: Preferences) {
        guard isEditable(entry) else { return }
        aliasDraft = alias(of: entry, preferences) ?? ""
        aliasProblem = nil
        editing = entry.id
    }

    /// Done or ↩: the alias typed is kept, then it closes. False when it is
    /// not an alias: it stays open and says why.
    @discardableResult
    func done(_ preferences: Preferences, _ store: ShortcutStore) -> Bool {
        guard commitAlias(preferences) else { return false }
        close(store)
        return true
    }

    /// Closed otherwise (⎋, a click away): a valid alias is kept, one that
    /// is not goes back to what it was.
    func dismissed(_ preferences: Preferences, _ store: ShortcutStore) {
        guard editing != nil else { return }
        if !commitAlias(preferences, quietly: true) { aliasProblem = nil }
        close(store)
    }

    private func close(_ store: ShortcutStore) {
        // Nothing may go on recording out of sight.
        if store.recordingID != nil { store.cancelRecording() }
        editing = nil
    }

    // MARK: Show in search

    func isOn(_ entry: CatalogEntry, _ preferences: Preferences) -> Bool {
        !preferences.catalogOff.contains(entry.id)
    }

    /// Off: its rows leave the launcher's results; the "?" lists it dimmed.
    func setOn(_ on: Bool, _ entry: CatalogEntry, _ preferences: Preferences) {
        guard entry.canBeOff else { return }
        if on {
            preferences.catalogOff.remove(entry.id)
        } else {
            preferences.catalogOff.insert(entry.id)
        }
    }

    // MARK: Alias

    func alias(of entry: CatalogEntry, _ preferences: Preferences) -> String? {
        preferences.launcherAliases.first { $0.id == entry.id }?.alias
    }

    /// Keeps what is typed, as ⌘K → Set Alias… does: one word, 12 letters
    /// at most, empty removes it, and given to another entry it moves.
    private func commitAlias(_ preferences: Preferences, quietly: Bool = false) -> Bool {
        guard let id = editing, let entry = entry(id), entry.takesAlias else { return true }
        let alias = LauncherAliases.normalized(aliasDraft)
        guard alias.isEmpty || LauncherAliases.isValid(alias) else {
            if !quietly {
                NSSound.beep()
                aliasProblem = "An alias is one word, 12 letters at most."
            }
            return false
        }
        aliasProblem = nil
        if alias != self.alias(of: entry, preferences) ?? "" {
            preferences.launcherAliases = LauncherAliases.setting(alias, id: id, title: entry.title, in: preferences.launcherAliases)
        }
        return true
    }

    // MARK: Shortcut

    /// A click on the popover's shortcut: records over the one shown, or
    /// adds one first (as Keys → Add Shortcut does).
    func recordShortcut(_ entry: CatalogEntry, _ store: ShortcutStore) {
        guard let action = shortcutAction(entry) else { return }
        newShortcut.record(action, store)
    }

    /// Recording ended: a shortcut added for it and left without keys goes.
    func recordingEnded(_ store: ShortcutStore) {
        newShortcut.recordingEnded(store)
    }
}

/// A shortcut recorded from a row that shows one per action (Catalog,
/// Apps): over the action's own, or added first, as Keys → Add Shortcut
/// does; one added and left without keys (⎋, or refused) goes again.
@MainActor
@Observable
final class NewShortcut {
    /// The one added for the recording going on.
    private(set) var added: String?

    func record(_ action: SkilliAction, _ store: ShortcutStore) {
        if let id = store.entryID(for: action) {
            store.beginRecording(id)
            return
        }
        let id = store.add(action)
        added = id
        store.beginRecording(id)
    }

    /// Recording ended (`ShortcutStore.recordingID` changed).
    func recordingEnded(_ store: ShortcutStore) {
        guard let id = added, store.recordingID != id else { return }
        added = nil
        if store.config.shortcuts.first(where: { $0.id == id })?.keys == nil {
            store.remove(id)
        }
    }
}

/// Settings → Catalog: everything skil.li does, grouped by what the user
/// wants, each with how it is reached (prefix, alias, shortcut) and whether
/// search shows it, read-only like the "?"; a click on a row opens its
/// popover to change them. Then the quicklinks, the other aliases and
/// the entries links run without asking (Trusted Links). The launcher's
/// "?" lists the same entries.
struct CatalogPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    @Bindable var model: CatalogPaneModel
    /// The first group is drawn as the pane opens, the others right after:
    /// the pane shows at once, the rows below the window follow.
    @State private var complete = false
    /// Settings' search looks for a row of the lists: all of it at once.
    @Environment(SettingsSearchModel.self) private var settingsSearch: SettingsSearchModel?

    /// The lists' rows (quicklinks, aliases), drawn after the entries.
    private static let listAnchors: Set<String> = ["quicklinks", "quicklinkReuseTab", "launcherAliases", "trustedLinks"]

    var body: some View {
        let searching = !model.search.trimmingCharacters(in: .whitespaces).isEmpty
        let wanted = settingsSearch?.revealing.map(Self.listAnchors.contains) ?? false
        let whole = complete || wanted
        let shown = model.shown
        let sections = FeatureCatalog.sections(whole || searching ? shown : Array(shown.prefix { $0.group == shown.first?.group }))
        let shortcuts = Self.shortcutIDs(context.shortcuts)
        let aliases = Dictionary(preferences.launcherAliases.map { ($0.id, $0.alias) }, uniquingKeysWith: { first, _ in first })
        Form {
            // How it is reached, first, as Ask's pane starts with its keys.
            Section {
                LabeledContent {
                    KeycapLabel("?")
                        .padding(.horizontal, 8)
                } label: {
                    LabelDetail("From the launcher", "Type ?, then a word to narrow the list.")
                }
                // Links: every entry runs from Shortcuts, a Stream Deck or a page.
                LabeledContent {
                    KeycapLabel("⌘K")
                        .padding(.horizontal, 8)
                } label: {
                    LabelDetail("From other apps",
                                "⌘K → Copy Link on an entry gives its skilli:// link, for Shortcuts, a Stream Deck or a page. What could change your Mac asks first; Always in that card lets links run it at once.")
                }
            } header: {
                PaneHeader(pane: .catalog)
            }
            if sections.isEmpty, searching {
                Section {
                    Text("Nothing skil.li does matches “\(model.search.trimmingCharacters(in: .whitespaces))”.")
                        .foregroundStyle(.secondary)
                } header: {
                    top(firstGroup: nil)
                }
            }
            ForEach(Array(sections.enumerated()), id: \.element.group) { index, section in
                Section {
                    ForEach(section.entries) { entry in
                        let action = model.shortcutAction(entry)
                        let shortcutID = action.flatMap { shortcuts[$0.id] }
                        CatalogRow(entry: entry, tint: Self.tint(section.group), alias: aliases[entry.id],
                                   chords: shortcutID.flatMap { id in context.shortcuts.config.shortcuts.first { $0.id == id }?.chords },
                                   off: entry.canBeOff && !model.isOn(entry, preferences), editable: model.isEditable(entry),
                                   open: { model.open(entry, preferences) })
                            // Found by Settings' search ("emoji").
                            .settingAnchor(SettingsSearch.entryAnchor(entry.id))
                            .background {
                                // Only the row being edited holds a popover.
                                if model.editing == entry.id {
                                    CatalogEditorAnchor(entry: entry, tint: Self.tint(section.group), action: action, shortcutID: shortcutID,
                                                        model: model, preferences: preferences, store: context.shortcuts)
                                }
                            }
                    }
                } header: {
                    if index == 0 {
                        top(firstGroup: section.group)
                    } else {
                        Text(section.group.title)
                    }
                } footer: {
                    if index == sections.count - 1 {
                        Text("Click an entry to give it an alias or a shortcut, or to take it out of search: it then leaves the launcher's results, stays in “?”, and its prefix, alias and shortcut still work. An alias then a space opens it at once: “e smile”.")
                    }
                }
            }

            // The lists, last, while nothing is searched.
            if whole, !searching {
                QuicklinksSection(preferences: preferences, store: context.quicklinks, deletes: context.deletes, shortcuts: context.shortcuts, onChange: reload)
                otherAliases
                trustedLinks
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            model.allRowsShown = false
            // Next turn of the run loop: once the first frame is up.
            DispatchQueue.main.async {
                complete = true
                model.allRowsShown = true
                model.onAllRowsShown?()
            }
        }
        .onChange(of: context.shortcuts.recordingID) { model.recordingEnded(context.shortcuts) }
    }

    /// The search field, then the first group's name where a section's
    /// name goes.
    private func top(firstGroup: CatalogEntry.Group?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CatalogSearchField(text: $model.search, prompt: "Search what skil.li can do")
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            if let firstGroup {
                Text(firstGroup.title)
                    .font(.headline)
            }
        }
        // Each entry's Show in search is in its popover: found here, at the entries.
        .settingAnchor("catalogOff")
    }

    /// Aliases for what has no row above: apps, a sound device, a System
    /// Settings pane, a project.
    private var otherAliases: some View {
        let inRows = Set(model.entries.filter(\.takesAlias).map(\.id))
        let others = preferences.launcherAliases.filter { !inRows.contains($0.id) }
        return Section {
            if others.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            }
            ForEach(others, id: \.alias) { alias in
                LabeledContent {
                    Button {
                        context.deletes.alias(of: alias.id, in: preferences)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this alias")
                } label: {
                    HStack(spacing: 10) {
                        Text(alias.alias)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                        Text(alias.title)
                    }
                }
            }
        } header: {
            Text("Aliases")
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingAnchor("launcherAliases")
        } footer: {
            Text("For apps and what has no row above, like a sound device or a System Settings pane: in the launcher, ⌘K on it, then Set Alias…")
        }
    }

    /// What links run without asking (D6): Always ⌘↩ in a link's card
    /// adds the entry, − asks again. The entry's name as the Catalog has
    /// it now; one deleted since says so.
    private var trustedLinks: some View {
        let tools = context.toolSettings
        let links = tools.linkTrust.byTitle
        return Section {
            if links.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            }
            ForEach(links) { link in
                let entry = model.entry(link.entry)
                LabeledContent {
                    Button {
                        tools.removeTrustedLink(link)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Ask again before a link runs it")
                } label: {
                    Label {
                        if let entry {
                            Text(TrustedLink(entry: link.entry, arguments: link.arguments, title: entry.title).shown)
                        } else {
                            LabelDetail(link.shown, "No longer in skil.li: its links say so.")
                        }
                    } icon: {
                        IconTile(symbol: entry?.symbol ?? "link", tint: entry.map { Self.tint($0.group) } ?? .gray, size: 22)
                    }
                }
            }
        } header: {
            Text("Trusted Links")
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingAnchor("trustedLinks")
        } footer: {
            Text("Links run these at once, from any app or page. Empty Trash, Restart, Shut Down, Log Out, Quit All Apps, Quit Other Apps and pastes of your copies ask every time.")
        }
    }

    private func reload() {
        model.load(context.catalogInput())
    }

    /// Each action's shortcut a row shows, by the action's id: the first
    /// that works, else the first (`ShortcutStore.entryID(for:)`), read
    /// once for every row.
    static func shortcutIDs(_ store: ShortcutStore) -> [String: String] {
        var working: [String: String] = [:]
        var first: [String: String] = [:]
        for entry in store.config.shortcuts {
            let action = entry.action.id
            if first[action] == nil { first[action] = entry.id }
            if working[action] == nil, entry.chords != nil, store.problems[entry.id] == nil { working[action] = entry.id }
        }
        return first.merging(working) { _, working in working }
    }

    /// One tint per group, for the icon tiles.
    static func tint(_ group: CatalogEntry.Group) -> Color {
        switch group {
        case .find: .blue
        case .act: .orange
        case .write: .purple
        case .stayOnTop: .red
        case .apps: .indigo
        case .yours: .green
        case .skilli: .teal
        }
    }
}

/// One entry, read-only like the "?": icon, name and prefix, its line;
/// on the right only what exists: "Off", the alias, the shortcut, and a
/// chevron when a click has something to change.
private struct CatalogRow: View {
    let entry: CatalogEntry
    let tint: Color
    let alias: String?
    let chords: [Chord]?
    let off: Bool
    let editable: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                IconTile(symbol: entry.symbol, tint: tint, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        SIText(entry.title)
                            .lineLimit(1)
                        if let prefix = entry.prefix?.trimmingCharacters(in: .whitespaces), !prefix.isEmpty {
                            KeycapLabel(prefix)
                                .fixedSize()
                        }
                    }
                    SIText(entry.oneLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .opacity(off ? 0.45 : 1)
            Spacer(minLength: 8)
            if off {
                Text("Off")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            if let alias {
                KeycapLabel(alias)
                    .fixedSize()
            }
            if let chords, !chords.isEmpty {
                ShortcutView(chords: chords.map(\.keycaps))
                    .fixedSize()
            }
            if editable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if editable { open() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(editable ? .isButton : [])
    }
}

/// The edited row's popover, attached to it: shown as it appears, and
/// closing it (⎋, a click away) tells the model.
private struct CatalogEditorAnchor: View {
    let entry: CatalogEntry
    let tint: Color
    let action: SkilliAction?
    let shortcutID: String?
    @Bindable var model: CatalogPaneModel
    @Bindable var preferences: Preferences
    @Bindable var store: ShortcutStore
    @State private var presented = false

    var body: some View {
        Color.clear
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                CatalogEntryEditor(entry: entry, tint: tint, action: action, shortcutID: shortcutID, model: model,
                                   preferences: preferences, store: store)
            }
            .onAppear { presented = true }
            .onChange(of: presented) { _, shown in
                if !shown { model.dismissed(preferences, store) }
            }
    }
}

/// What can be changed for one entry, with the controls of the rest of
/// Settings: the alias in a text field (⌘K → Set Alias…'s check), the
/// shortcut in the Keys pane's own recorder, and a switch for search.
private struct CatalogEntryEditor: View {
    let entry: CatalogEntry
    let tint: Color
    let action: SkilliAction?
    let shortcutID: String?
    @Bindable var model: CatalogPaneModel
    @Bindable var preferences: Preferences
    @Bindable var store: ShortcutStore
    @FocusState private var aliasFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                IconTile(symbol: entry.symbol, tint: tint, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    SIText(entry.title)
                        .font(.headline)
                    SIText(entry.oneLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 14) {
                if entry.takesAlias {
                    GridRow {
                        Text("Alias")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Alias", text: $model.aliasDraft, prompt: Text("none"))
                                .labelsHidden()
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 132)
                                .focused($aliasFocused)
                                .onSubmit { model.done(preferences, store) }
                            Text(model.aliasProblem ?? "Typed then a space in the launcher, it opens this.")
                                .font(.caption)
                                .foregroundStyle(model.aliasProblem == nil ? Color.secondary : Color.red)
                        }
                    }
                }
                if action != nil {
                    GridRow {
                        Text("Shortcut")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        VStack(alignment: .leading, spacing: 4) {
                            ShortcutField(store: store, id: shortcutID ?? "catalog.unbound.\(entry.id)",
                                          chords: shortcutID.flatMap { id in store.config.shortcuts.first { $0.id == id }?.chords },
                                          minWidth: 0, alignment: .leading) {
                                model.recordShortcut(entry, store)
                            }
                            if let shortcutID, ShortcutNote.shows(store, shortcutID) {
                                ShortcutNote(store: store, id: shortcutID)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if entry.canBeOff {
                    GridRow {
                        Text("Show in search")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Show in search", isOn: Binding(get: { model.isOn(entry, preferences) },
                                                                   set: { model.setOn($0, entry, preferences) }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            Text(model.isOn(entry, preferences) ? "In the launcher's results." : "Only in “?”; its prefix, alias and shortcut still work.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { model.done(preferences, store) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            // In the popover's window first, then it can take the keys.
            if entry.takesAlias { DispatchQueue.main.async { aliasFocused = true } }
        }
    }
}

/// The native search field (magnifier, ⓧ, ⎋ clears), filtering as typed.
struct CatalogSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.setAccessibilityLabel(prompt)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func changed(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }
    }
}
