import AppKit
import SkilliCore
import SwiftUI

/// The pages of Settings → Apps: the list, then one app's page pushed in
/// its place.
enum AppsPage: Hashable {
    /// A linked app, by its id ("cleanshot").
    case linked(String)
    /// The user's shortcuts in Apple's Shortcuts app.
    case shortcuts
}

/// Settings → Apps' state, kept by the window: the page shown, the
/// shortcut a row added to record, and the user's shortcuts as read for
/// the pane. The self-test calls what the pane's controls call; Settings'
/// search opens the page that holds the row it looks for.
@MainActor
@Observable
final class AppsPaneModel {
    /// Nil: the list.
    var page: AppsPage?

    /// The window's title on an app's page: the app's name.
    var title: String? {
        page.flatMap { page in AppsPaneApp.installed().first { $0.page == page }?.name }
    }
    let newShortcut = NewShortcut()
    /// The user's shortcuts as last read; read again as the pane shows.
    private(set) var shortcuts: [AppleShortcut] = AppleShortcuts.all()
    private(set) var readingShortcuts = false

    /// Reads them off the main thread (Apple's tool, ~10 ms).
    func readShortcuts() {
        guard !readingShortcuts else { return }
        readingShortcuts = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { AppleShortcuts.read() }.value
            shortcuts = found
            readingShortcuts = false
        }
    }

    // MARK: Import

    /// An app a link would add, read and checked, shown whole before Add.
    struct ImportCandidate: Identifiable {
        let id = UUID()
        let app: LinkedApp
        let text: String
        /// "a link", or the site it came from.
        let source: String
    }

    var pendingImport: [ImportCandidate] = []
    var importErrors: [String] = []
    /// The apps added from the last import, for the self-test.
    private(set) var added: [LinkedApp] = []
    var isImporting: Bool {
        get { !pendingImport.isEmpty || !importErrors.isEmpty }
        set { if !newValue { pendingImport = []; importErrors = [] } }
    }

    /// A `skilli://apps/import` link: the apps it carries, then the ones it
    /// points to (https, small files only); each checked as it would be read.
    func receive(_ request: AppFileLink.Request) async {
        prepareImport(request.files.map { ($0, "a link") })
        for url in request.urls {
            do {
                prepareImport([(try await Self.download(url), url.host() ?? url.absoluteString)])
            } catch {
                importErrors.append("\(url.absoluteString): \(error.localizedDescription)")
            }
        }
    }

    func prepareImport(_ files: [(text: String, source: String)]) {
        for (text, source) in files {
            do {
                let app = try LinkedApps.check(text)
                guard !pendingImport.contains(where: { $0.app.id == app.id || $0.app.bundleID == app.bundleID || $0.app.scheme == app.scheme }) else {
                    importErrors.append("\(app.name) is twice in this link.")
                    continue
                }
                pendingImport.append(ImportCandidate(app: app, text: text, source: source))
            } catch {
                importErrors.append("From \(source): \(error.localizedDescription)")
            }
        }
    }

    /// A plain GET: no cookies, no cache (a web page chose the address).
    private static func download(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SystemCommands.Failure(message: "the server answered \(status)") }
        guard data.count <= LinkedAppFile.largest, let text = String(data: data, encoding: .utf8) else {
            throw SystemCommands.Failure(message: "not an app file")
        }
        return text
    }

    /// Adds every pending app (its file, as the link gave it); one that
    /// cannot be added any more is said.
    @discardableResult
    func confirmImport() -> [LinkedApp] {
        var added: [LinkedApp] = []
        var failed: [String] = []
        for candidate in pendingImport {
            do {
                added.append(try LinkedApps.add(candidate.text))
            } catch {
                failed.append("\(candidate.app.name): \(error.localizedDescription)")
            }
        }
        pendingImport = []
        importErrors = failed
        self.added = added
        changed += 1
        onAppsChanged?()
        return added
    }

    /// Bumped when an app was added here: the list draws it.
    private(set) var changed = 0
    /// The launcher's rows follow (set by the app).
    var onAppsChanged: (() -> Void)?

    /// The page holding the row anchored `anchor`: a linked app's command
    /// or option, one of the user's shortcuts. Nil: none of the pages.
    static func page(for anchor: String) -> AppsPage? {
        if anchor == "cleanShotTextLineBreaks" { return .linked(LinkedApp.cleanShot.id) }
        if anchor.hasPrefix(SettingsSearch.entryAnchor(FeatureCatalog.shortcutEntryID(""))) { return .shortcuts }
        for app in LinkedApp.all where app.commands.contains(where: { SettingsSearch.entryAnchor(FeatureCatalog.appLinkEntryID($0.id)) == anchor }) {
            return .linked(app.id)
        }
        return nil
    }
}

/// One app the pane lists: what its row and its page's header show.
struct AppsPaneApp: Identifiable {
    let page: AppsPage
    let name: String
    /// In its button: "Open CleanShot".
    let shortName: String
    let url: URL
    let version: String?
    /// Where the app documents its links (an app file's).
    var documentation: URL?
    /// The user's file it comes from, in the Apps folder.
    var file: URL?

    var id: AppsPage { page }

    /// The apps skil.li drives that are on this Mac, by name.
    @MainActor
    static func installed() -> [AppsPaneApp] {
        let linked = LinkedApps.installed().map {
            AppsPaneApp(page: .linked($0.app.id), name: $0.app.name, shortName: $0.app.shortName, url: $0.url, version: $0.version,
                        documentation: $0.app.documentation.flatMap(URL.init(string:)),
                        file: $0.app.file.flatMap { name in LinkedApps.folder?.appendingPathComponent(name) })
        }
        let shortcuts = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppleShortcut.bundleID).map {
            AppsPaneApp(page: .shortcuts, name: "Shortcuts", shortName: "Shortcuts", url: $0,
                        version: Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String)
        }
        return (linked + [shortcuts].compactMap { $0 }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    /// The app itself, as the Dock opens it (CleanShot's own link to its
    /// settings needs its API allowed already).
    func open() {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Settings → Apps (docs/apps.md): the apps skil.li drives that are on
/// this Mac, a row each; a click pushes the app's page in its place, as
/// System Settings → Notifications does: its header, its options, then
/// its commands, the long list last, each with its keys and a ⋯ menu.
struct AppsPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    @Bindable var model: AppsPaneModel

    var body: some View {
        // An app added from a link: the list again, with it.
        let _ = model.changed
        let apps = AppsPaneApp.installed()
        Group {
            if let page = model.page, let app = apps.first(where: { $0.page == page }) {
                AppPageView(app: app, preferences: preferences, store: context.shortcuts, model: model)
                    .id(page)
            } else {
                AppsListView(apps: apps, store: context.shortcuts, model: model)
            }
        }
        // Another pane: the list again when it comes back.
        .onDisappear { model.page = nil }
        .sheet(isPresented: $model.isImporting) {
            AppImportSheet(model: model)
        }
    }
}

// MARK: - The list

private struct AppsListView: View {
    let apps: [AppsPaneApp]
    @Bindable var store: ShortcutStore
    @Bindable var model: AppsPaneModel

    var body: some View {
        Form {
            Section {
                if apps.isEmpty {
                    Text("None of the apps skil.li drives is on this Mac.")
                        .foregroundStyle(.secondary)
                }
                ForEach(apps) { app in
                    Button {
                        model.page = app.page
                    } label: {
                        HStack(spacing: 12) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                Text(status(app))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.name)
                }
            } header: {
                PaneHeader(pane: .apps)
            }
            problems
        }
        .formStyle(.grouped)
        .onAppear { model.readShortcuts() }
    }

    /// The user's app files left out, each with why: last, as long lists are.
    @ViewBuilder
    private var problems: some View {
        let problems = LinkedApps.problems
        if !problems.isEmpty {
            Section {
                ForEach(problems, id: \.file) { problem in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.file)
                            Text(problem.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 2)
                    .settingAnchor(problem.file == problems.first?.file ? "appFiles" : "appFile.\(problem.file)")
                }
            } header: {
                Text(problems.count == 1 ? "An App File Left Out" : "\(problems.count) App Files Left Out")
            } footer: {
                HStack {
                    Text("Fixed and saved, a file is read again as the launcher opens.")
                    Spacer()
                    Button("Show in Finder") { LinkedApps.revealFolder() }
                        .controlSize(.small)
                }
            }
        }
    }

    /// "22 commands · 2 on keys", "14 shortcuts · 1 on a key".
    private func status(_ app: AppsPaneApp) -> String {
        switch app.page {
        case .linked(let id):
            guard let installed = LinkedApps.installed(id) else { return "" }
            let commands = installed.app.commands.filter { $0.runs(onVersion: installed.version) }.count
            return AppsCount.line(commands, "command", keys: AppsCount.keys(store) { action in
                if case .mac(.appLink(let command, _)) = action { command.appID == id } else { false }
            })
        case .shortcuts:
            if model.shortcuts.isEmpty { return model.readingShortcuts ? "Reading your shortcuts…" : "No shortcuts yet" }
            return AppsCount.line(model.shortcuts.count, "shortcut", keys: AppsCount.keys(store) { action in
                if case .mac(.shortcut) = action { true } else { false }
            })
        }
    }
}

/// The counts an app's row says.
enum AppsCount {
    /// What has keys that work, each command or shortcut once (its
    /// variants with it).
    @MainActor
    static func keys(_ store: ShortcutStore, _ belongs: (SkilliAction) -> Bool) -> Int {
        Set(store.config.shortcuts.filter { $0.chords != nil && store.problems[$0.id] == nil && belongs($0.action) }.map(\.action.id)).count
    }

    /// "22 commands · 2 on keys", "1 shortcut · 1 on a key", "3 commands".
    static func line(_ count: Int, _ noun: String, keys: Int) -> String {
        let things = "\(count) \(noun)\(count == 1 ? "" : "s")"
        guard keys > 0 else { return things }
        return "\(things) · \(keys == 1 ? "1 on a key" : "\(keys) on keys")"
    }
}

// MARK: - An app's page

private struct AppPageView: View {
    let app: AppsPaneApp
    @Bindable var preferences: Preferences
    @Bindable var store: ShortcutStore
    @Bindable var model: AppsPaneModel

    var body: some View {
        let shortcuts = CatalogPane.shortcutIDs(store)
        Form {
            switch app.page {
            case .linked(let id):
                if let installed = LinkedApps.installed(id) {
                    linkedPage(installed, shortcuts: shortcuts)
                }
            case .shortcuts:
                shortcutsPage(shortcuts: shortcuts)
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.recordingID) { model.newShortcut.recordingEnded(store) }
        // Back to the list, another pane, or Settings closed: nothing goes
        // on recording out of sight, and a shortcut added for it without
        // keys goes.
        .onDisappear {
            if store.recordingID != nil { store.cancelRecording() }
            model.newShortcut.recordingEnded(store)
        }
    }

    // MARK: A linked app

    @ViewBuilder
    private func linkedPage(_ installed: LinkedApps.Installed, shortcuts: [String: String]) -> some View {
        let commands = installed.app.commands.filter { $0.runs(onVersion: installed.version) }
        let groups = installed.app.grouped.map { group in (title: group.title, commands: group.commands.filter { commands.contains($0) }) }
            .filter { !$0.commands.isEmpty }
        // Its options first, under its header.
        Section {
            if installed.app.id == LinkedApp.cleanShot.id, commands.contains(where: { $0.id == "cleanshot.capture-text" }) {
                Picker("Line breaks in Capture Text", selection: $preferences.cleanShotTextLineBreaks) {
                    ForEach(CleanShot.TextLineBreaks.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .settingAnchor("cleanShotTextLineBreaks")
            }
        } header: {
            AppPageHeader(app: app, detail: AppsCount.line(commands.count, "command", keys: 0), note: installed.app.allowance,
                          tooOld: commands.isEmpty ? installed.app.minimumVersion : nil) { model.page = nil }
        }
        // The long list last: the commands, by group.
        ForEach(Array(groups.enumerated()), id: \.element.title) { position, group in
            Section {
                ForEach(group.commands, id: \.id) { command in
                    commandRows(command, shortcuts: shortcuts)
                }
            } header: {
                Text(group.title)
            } footer: {
                if position == groups.count - 1 {
                    Text("A hidden command leaves the launcher's results; its keys, Ask and links still run it.")
                }
            }
        }
    }

    /// A command's row, then a row for each of its variants that has keys.
    @ViewBuilder
    private func commandRows(_ command: AppLinkCommand, shortcuts: [String: String]) -> some View {
        let action = SkilliAction.mac(.appLink(command, variant: nil))
        let entry = FeatureCatalog.appLinkEntryID(command.id)
        let others = LinkedApps.variants(of: command).map { AppItemRow.Other(title: $0.title, action: .mac(.appLink(command, variant: $0.id))) }
        AppItemRow(title: command.title, symbol: command.symbol, help: command.oneLine, action: action, shortcutID: shortcuts[action.id],
                   searchEntry: entry, store: store, preferences: preferences, model: model, others: others)
            .settingAnchor(SettingsSearch.entryAnchor(entry))
        ForEach(others, id: \.action.id) { other in
            if let id = withKeys(shortcuts[other.action.id]) {
                AppItemRow(title: other.title, symbol: "arrow.turn.down.right", help: nil, action: other.action, shortcutID: id, searchEntry: nil,
                           store: store, preferences: preferences, model: model, others: [])
            }
        }
    }

    /// The shortcut `id` when it has keys or is recording: a variant's row
    /// shows only then (its keys are typed in it).
    private func withKeys(_ id: String?) -> String? {
        guard let id, store.recordingID == id || store.config.shortcuts.first(where: { $0.id == id })?.chords != nil else { return nil }
        return id
    }

    // MARK: Shortcuts

    @ViewBuilder
    private func shortcutsPage(shortcuts: [String: String]) -> some View {
        let list = model.shortcuts
        Section {
            if list.isEmpty {
                if model.readingShortcuts {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your shortcuts…").foregroundStyle(.secondary)
                    }
                } else {
                    Text("None yet: the shortcuts you make in Shortcuts show here.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(list, id: \.id) { shortcut in
                let action = SkilliAction.mac(.shortcut(shortcut, withSelection: false))
                let selection = AppItemRow.Other(title: "With the Selection", action: .mac(.shortcut(shortcut, withSelection: true)))
                let entry = FeatureCatalog.shortcutEntryID(shortcut.id)
                AppItemRow(title: shortcut.name, symbol: FeatureCatalog.shortcutSymbol, help: nil, action: action, shortcutID: shortcuts[action.id],
                           searchEntry: entry, store: store, preferences: preferences, model: model, others: [selection], edit: shortcut.editURL)
                    .settingAnchor(SettingsSearch.entryAnchor(entry))
                if let id = withKeys(shortcuts[selection.action.id]) {
                    AppItemRow(title: selection.title, symbol: "arrow.turn.down.right", help: nil, action: selection.action, shortcutID: id,
                               searchEntry: nil, store: store, preferences: preferences, model: model, others: [])
                }
            }
        } header: {
            AppPageHeader(app: app, detail: list.isEmpty ? nil : AppsCount.line(list.count, "shortcut", keys: 0),
                          note: "Every shortcut in your library, run from the launcher, a key, Ask or a link.") { model.page = nil }
        } footer: {
            if !list.isEmpty {
                Text("A hidden shortcut leaves the launcher's results; its keys, Ask and links still run it.")
            }
        }
        .onAppear { model.readShortcuts() }
    }
}

/// The top of an app's page: "‹ Apps" back to the list, then centered
/// like a pane's header, the app's own icon, its name, its version and
/// what it has, what it needs, and the button that opens it.
private struct AppPageHeader: View {
    let app: AppsPaneApp
    let detail: String?
    let note: String?
    /// The version its links need, when the one here is older.
    var tooOld: String?
    let back: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // In the page, not the toolbar: a toolbar item would make the
            // window taller as the page opens.
            HStack {
                Button(action: back) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                        Text("Apps")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help("Back to the apps")
                Spacer()
            }
            .padding(.bottom, 2)
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
            Text(app.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            let line = [app.version, detail].compactMap { $0 }.joined(separator: " · ")
            if !line.isEmpty {
                Text(line)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let tooOld {
                Text("Its links need \(app.shortName) \(tooOld) or later: update it.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Open \(app.shortName)") { app.open() }
                if let documentation = app.documentation {
                    Button("Its Links") { NSWorkspace.shared.open(documentation) }
                        .help("Where \(app.shortName) documents its links: \(documentation.host() ?? "")")
                }
                if let file = app.file {
                    Button("Show File") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                        .help("Your \(file.lastPathComponent), in skil.li's Apps folder")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .textCase(nil)
    }
}

/// A command (or a shortcut) on its app's page: its symbol in grey, its
/// title, its keys when it has some; on hover a ⋯ menu (a right-click
/// too) to give it keys, give one of its variants keys, or take it out of
/// search. A variant's row (`searchEntry` nil) sits under its command,
/// indented. Recording shows in the row.
private struct AppItemRow: View {
    /// A variant with its own keys ("Capture and Copy", "With the Selection").
    struct Other {
        let title: String
        let action: SkilliAction
    }

    let title: String
    let symbol: String
    let help: String?
    let action: SkilliAction
    let shortcutID: String?
    /// Its Catalog entry: whether search shows it. Nil for a variant.
    let searchEntry: String?
    @Bindable var store: ShortcutStore
    @Bindable var preferences: Preferences
    let model: AppsPaneModel
    let others: [Other]
    /// Where its app edits it (a shortcut: Shortcuts' editor).
    var edit: URL?
    @State private var hovering = false

    private var variant: Bool { searchEntry == nil }
    private var hidden: Bool { searchEntry.map(preferences.catalogOff.contains) ?? false }
    private var chords: [Chord]? {
        guard let shortcutID, let chords = store.config.shortcuts.first(where: { $0.id == shortcutID })?.chords, !chords.isEmpty else { return nil }
        return chords
    }
    private var recording: Bool { shortcutID != nil && store.recordingID == shortcutID }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: variant ? 11 : 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.leading, variant ? 22 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(variant ? .secondary : .primary)
                if let shortcutID, ShortcutNote.shows(store, shortcutID) {
                    ShortcutNote(store: store, id: shortcutID)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(hidden ? 0.5 : 1)
            .help(help ?? "")
            Spacer(minLength: 8)
            if hidden {
                Text("Hidden from search")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if recording, let shortcutID {
                ShortcutField(store: store, id: shortcutID, chords: nil, minWidth: 0)
            } else if let chords {
                Button {
                    model.newShortcut.record(action, store)
                } label: {
                    ShortcutView(chords: chords.map(\.keycaps))
                }
                .buttonStyle(.plain)
                .help("Click to change")
            }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel("\(title) Options")
        }
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var menuItems: some View {
        if let shortcutID, chords != nil {
            Button("Change Shortcut") { model.newShortcut.record(action, store) }
            Button("Remove Shortcut") {
                // At once; ⌘Z in the card gives the keys back (rule 2).
                if let deletes = store.deletes {
                    deletes.shortcut(shortcutID, in: store, deleting: store.isCustom(shortcutID))
                } else {
                    store.clear(shortcutID)
                }
            }
        } else {
            Button("Add Shortcut") { model.newShortcut.record(action, store) }
        }
        if !others.isEmpty {
            Menu("Add a Shortcut for") {
                ForEach(others, id: \.action.id) { other in
                    Button("\(other.title)…") { model.newShortcut.record(other.action, store) }
                }
            }
        }
        if let searchEntry {
            Divider()
            if hidden {
                Button("Show in Search") { preferences.catalogOff.remove(searchEntry) }
            } else {
                Button("Hide from Search") { preferences.catalogOff.insert(searchEntry) }
            }
        }
        if let edit {
            Divider()
            Button("Edit in Shortcuts") { NSWorkspace.shared.open(edit) }
        }
    }
}

// MARK: - Import

/// What a `skilli://apps/import` link would add, whole, before anything is
/// added: each app, then every command with the very link it opens.
private struct AppImportSheet: View {
    let model: AppsPaneModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let count = model.pendingImport.count
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(count == 1 ? "Add This App?" : count == 0 ? "Nothing to Add" : "Add These \(count) Apps?")
                    .font(.title3.weight(.semibold))
                Text("skil.li will open these links in the app, from the launcher, your keys, Ask and agents. Add only apps you trust.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            // As tall as the apps, up to a point; then it scrolls.
            ViewThatFits(in: .vertical) {
                candidates
                ScrollView { candidates }
            }
            .frame(maxHeight: 460)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    model.isImporting = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if count > 0 {
                    Button(count == 1 ? "Add App" : "Add \(count) Apps") {
                        model.confirmImport()
                        if model.importErrors.isEmpty { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 560)
    }

    private var candidates: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.importErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.pendingImport) { candidate in
                AppCandidateCard(app: candidate.app, source: candidate.source)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One app of an import: who it is, where its links are documented, and
/// each command with its link (a variant's under it), what asks first said.
private struct AppCandidateCard: View {
    let app: LinkedApp
    let source: String

    var body: some View {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let installed {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: installed.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.headline)
                    Text(details(installed: installed != nil))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("from \(source)").font(.caption).foregroundStyle(.secondary)
            }
            if let documentation = app.documentation, let url = URL(string: documentation) {
                Link("Links documented at \(url.host() ?? documentation)", destination: url)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(app.commands, id: \.id) { command in
                    commandRow(command)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// "us.zoom.xos · zoommtg links · 2 commands · 5.0 or later".
    private func details(installed: Bool) -> String {
        var parts = [app.bundleID, "\(app.scheme) links", AppsCount.line(app.commands.count, "command", keys: 0)]
        if let minimum = app.minimumVersion { parts.append("\(minimum) or later") }
        if !installed { parts.append("not on this Mac") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func commandRow(_ command: AppLinkCommand) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: command.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(command.title)
                    if command.asksFirst { AsksFirstTag() }
                }
                Text(command.url()?.absoluteString ?? command.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(command.variants, id: \.id) { variant in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(variant.title).font(.caption)
                        if variant.asksFirst { AsksFirstTag() }
                        Text(command.url(variant: variant)?.absoluteString ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

/// "Asks first": what a link, Ask or an agent runs only once allowed.
private struct AsksFirstTag: View {
    var body: some View {
        Text("Asks first")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.orange.opacity(0.12), in: Capsule())
    }
}
