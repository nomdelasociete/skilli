import AppKit
import SkilliCore
import SwiftUI

/// Settings → Catalog → Quicklinks: "g skilli" opens Google's results.
/// The setting first (Reuse an open tab), then the list, then adding one:
/// by hand or from the library of ready ones (`QuicklinkLibrary`).
struct QuicklinksSection: View {
    @Bindable var preferences: Preferences
    let store: QuicklinkStore
    /// Delete: at once, its shortcuts too; ⌘Z in the card puts it back.
    let deletes: UndoableDeletes
    let shortcuts: ShortcutStore
    /// The list changed: the Catalog's rows read it again.
    var onChange: () -> Void = {}
    @State private var links: [Quicklink] = []
    @State private var editing: Quicklink?
    /// The default browser, when skil.li can choose its tab, and whether
    /// macOS lets it.
    @State private var browser: (bundleID: String, name: String)?
    @State private var browserState: AutomationAccess.State?
    /// The launcher's New Quicklink asks through it.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    /// The list and the browser read now: the section is drawn whole at
    /// once (opened at its end, it stays there).
    init(preferences: Preferences, store: QuicklinkStore, deletes: UndoableDeletes, shortcuts: ShortcutStore, onChange: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.store = store
        self.deletes = deletes
        self.shortcuts = shortcuts
        self.onChange = onChange
        _links = State(initialValue: store.links)
        _browser = State(initialValue: BrowserTabReuse.defaultBrowser())
    }

    var body: some View {
        Section {
            Toggle(isOn: $preferences.quicklinkReuseTab) {
                LabelDetail("Reuse an open tab", reuseDetail)
            }
            .settingAnchor("quicklinkReuseTab")
            if preferences.quicklinkReuseTab, let browser, browserState == .denied {
                LabeledContent {
                    Button("Open Settings") { NSWorkspace.shared.open(AutomationAccess.settingsURL) }
                } label: {
                    LabelDetail("\(browser.name) does not let skil.li choose its tab", "Turn skil.li on for \(browser.name) in Automation: until then quicklinks open a new tab.")
                }
            }
            ForEach(links) { link in
                Button {
                    editing = link
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.name)
                            Text(link.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        if !link.keyword.isEmpty {
                            Text(link.keyword)
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("Add Quicklink") { editing = Self.new }
                Menu("Add from Library…") {
                    ForEach(QuicklinkLibrary.groups, id: \.group) { group in
                        Section(group.group.title) {
                            ForEach(group.items) { item in
                                let added = QuicklinkLibrary.isAdded(item, in: links)
                                Button {
                                    add(item)
                                } label: {
                                    if added {
                                        Label("\(item.name) — added", systemImage: "checkmark")
                                    } else {
                                        Text("\(item.name)  ·  \(item.keyword)")
                                    }
                                }
                                .disabled(added)
                            }
                        }
                    }
                }
                .menuStyle(.button)
                .fixedSize()
                Spacer()
                Button("Reset to Defaults") {
                    let before = store.links.map(\.id)
                    store.resetToDefaults()
                    // The ones gone take their shortcuts with them.
                    for id in before where !store.links.contains(where: { $0.id == id }) {
                        shortcuts.removeEntries(for: .quicklink(id))
                    }
                    links = store.links
                    onChange()
                }
            }
        } header: {
            Text("Quicklinks")
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingAnchor("quicklinks")
        } footer: {
            Text("Type a keyword and what to look for: “g skilli” opens Google's results. {query} in the address takes what you type, else the text selected where you opened the launcher. When nothing on your Mac matches, the first quicklink searches the web.")
        }
        .onAppear {
            links = store.links
            startAsked()
        }
        .onChange(of: navigation?.new) { startAsked() }
        // Turned on: macOS asks now, beside the switch, when the browser is
        // open (it can only ask then); else the first time a quicklink opens.
        .onChange(of: preferences.quicklinkReuseTab) { _, on in
            guard on, let bundleID = browser?.bundleID,
                  !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
            Task {
                browserState = await Task.detached(priority: .userInitiated) { AutomationAccess.ask(bundleID) }.value
            }
        }
        .task(id: preferences.quicklinkReuseTab) {
            guard preferences.quicklinkReuseTab, let bundleID = browser?.bundleID else { return }
            browserState = await Task.detached(priority: .utility) { AutomationAccess.state(of: bundleID) }.value
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingTools.changed)) { _ in
            links = store.links
            onChange()
        }
        .sheet(item: $editing) { link in
            QuicklinkEditor(
                link: link,
                isNew: !store.links.contains { $0.id == link.id },
                keywordTaken: { keyword in links.contains { $0.keyword.lowercased() == keyword.lowercased() && $0.id != link.id } },
                save: { saved in
                    store.save(saved)
                    links = store.links
                    editing = nil
                    onChange()
                },
                delete: {
                    deletes.quicklink(link, in: store, shortcuts: shortcuts)
                    links = store.links
                    editing = nil
                    onChange()
                },
                cancel: { editing = nil }
            )
        }
    }
}

extension QuicklinksSection {
    private var reuseDetail: String {
        guard let browser else {
            let yours = BrowserTabReuse.anyDefaultBrowser().map { "\($0.name), your default browser, cannot" } ?? "Your default browser cannot"
            return "Safari, Chrome, Brave, Edge and Vivaldi can load a quicklink in the tab they have open on its site. \(yours): quicklinks open a new tab."
        }
        return "A quicklink loads in the tab \(browser.name) already has open on its site, instead of a new one: the page in that tab is replaced. macOS asks once to let skil.li choose it."
    }

    private static var new: Quicklink { Quicklink(name: "", keyword: "", url: "https://") }

    /// New Quicklink in the launcher: Add Quicklink's editor, unless one is
    /// open.
    private func startAsked() {
        guard navigation?.take(.quicklink) == true, editing == nil else { return }
        editing = Self.new
    }

    /// A ready quicklink, its keyword kept unless one of the user's has it.
    private func add(_ item: QuicklinkLibrary.Item) {
        store.save(QuicklinkLibrary.quicklink(for: item, among: store.links))
        links = store.links
        onChange()
    }
}

private struct QuicklinkEditor: View {
    @State var link: Quicklink
    let isNew: Bool
    let keywordTaken: (String) -> Bool
    let save: (Quicklink) -> Void
    let delete: () -> Void
    let cancel: () -> Void

    private var problem: String? {
        if link.keyword.contains(where: \.isWhitespace) { return "A keyword has no spaces." }
        if !link.keyword.isEmpty, keywordTaken(link.keyword) { return "Another quicklink uses “\(link.keyword)”." }
        if link.address(for: "test") == nil { return "The address starts with https:// or http://." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Quicklink" : "Edit Quicklink")
                .font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("", text: $link.name, prompt: Text("Google"))
                }
                GridRow {
                    Text("Keyword").foregroundStyle(.secondary)
                    TextField("", text: $link.keyword, prompt: Text("g"))
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Address").foregroundStyle(.secondary)
                    TextField("", text: $link.url, prompt: Text("https://www.google.com/search?q={query}"))
                        .font(.system(.body, design: .monospaced))
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if !isNew { Button("Delete", role: .destructive, action: delete) }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { save(link) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(link.name.trimmingCharacters(in: .whitespaces).isEmpty || problem != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
