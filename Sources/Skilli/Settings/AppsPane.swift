import AppKit
import SkilliCore
import SwiftUI

/// Settings → Apps (docs/apps.md): the apps skil.li drives through their
/// own links, only those installed. For each, by the Settings rules: a row
/// with its icon, name, version and whether it lets skil.li drive it; its
/// options; then its commands, the long list last, by group, each with its
/// shortcut (recorded as in Catalog) and whether search shows it (the
/// Catalog's switch). Keys and Catalog list the same commands.
struct AppsPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// A shortcut a row added to record (kept by the window).
    let newShortcut: NewShortcut

    var body: some View {
        let apps = LinkedApps.installed()
        let store = context.shortcuts
        let shortcuts = CatalogPane.shortcutIDs(store)
        Form {
            if apps.isEmpty {
                Section {
                    Text("None of the apps skil.li drives is on this Mac.")
                        .foregroundStyle(.secondary)
                } header: {
                    PaneHeader(pane: .apps)
                }
            }
            ForEach(Array(apps.enumerated()), id: \.element.app.id) { index, installed in
                let commands = installed.app.commands.filter { $0.runs(onVersion: installed.version) }
                Section {
                    LinkedAppRow(installed: installed)
                } header: {
                    if index == 0 {
                        PaneHeader(pane: .apps)
                    }
                } footer: {
                    Text("skil.li opens \(installed.app.shortName)'s own links: \(installed.app.shortName) does the work, in its own windows.")
                }

                if installed.app.id == LinkedApp.cleanShot.id, commands.contains(where: { $0.id == "cleanshot.capture-text" }) {
                    Section {
                        Picker(selection: $preferences.cleanShotTextLineBreaks) {
                            ForEach(CleanShot.TextLineBreaks.allCases, id: \.self) { Text($0.title).tag($0) }
                        } label: {
                            LabelDetail("Line breaks in Capture Text", "From its row, a shortcut or Ask. ⌘K on its row in the launcher offers both.")
                        }
                        .settingAnchor("cleanShotTextLineBreaks")
                    }
                }

                // The long list last: the commands, by group.
                let groups = installed.app.grouped.map { group in (group.title, group.commands.filter { commands.contains($0) }) }
                    .filter { !$0.1.isEmpty }
                ForEach(Array(groups.enumerated()), id: \.element.0) { position, group in
                    Section {
                        ForEach(group.1, id: \.id) { command in
                            commandRows(command, store: store, shortcuts: shortcuts)
                        }
                    } header: {
                        AppCommandsHeader(title: group.0, columns: position == 0)
                    } footer: {
                        if position == groups.count - 1 {
                            Text("Click a shortcut to record it; right-click a command to give one of its variants a shortcut (Capture and Copy…). Out of search, a command leaves the launcher's results; its shortcut, Ask and links still run it.")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.recordingID) { newShortcut.recordingEnded(store) }
    }

    /// A command's row, then a row for each of its variants that has a
    /// shortcut.
    @ViewBuilder
    private func commandRows(_ command: AppLinkCommand, store: ShortcutStore, shortcuts: [String: String]) -> some View {
        let action = SkilliAction.mac(.appLink(command, variant: nil))
        let entry = FeatureCatalog.appLinkEntryID(command.id)
        let variants = LinkedApps.variants(of: command)
        AppCommandRow(title: command.title, symbol: command.symbol, help: command.oneLine, action: action, shortcutID: shortcuts[action.id],
                      isOn: Binding(get: { !preferences.catalogOff.contains(entry) },
                                    set: { on in
                                        if on { preferences.catalogOff.remove(entry) } else { preferences.catalogOff.insert(entry) }
                                    }),
                      store: store, newShortcut: newShortcut)
            .settingAnchor(SettingsSearch.entryAnchor(entry))
            .contextMenu {
                if !variants.isEmpty {
                    Section("Add a Shortcut for") {
                        ForEach(variants, id: \.id) { variant in
                            Button(variant.title) { newShortcut.record(.mac(.appLink(command, variant: variant.id)), store) }
                        }
                    }
                }
            }
        ForEach(variants, id: \.id) { variant in
            let variantAction = SkilliAction.mac(.appLink(command, variant: variant.id))
            if let id = shortcuts[variantAction.id] {
                AppCommandRow(title: variant.title, symbol: variant.symbol, help: "\(command.title), then \(variant.label)", action: variantAction,
                              shortcutID: id, isOn: nil, store: store, newShortcut: newShortcut)
            }
        }
    }
}

/// One linked app: its own icon, name and version, and where the user
/// lets skil.li drive it, with the app a click away (nothing on the Mac
/// says whether it is on: `LinkedApp.allowance`).
private struct LinkedAppRow: View {
    let installed: LinkedApps.Installed

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: installed.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(installed.app.name)
                        .font(.headline)
                    if let version = installed.version {
                        Text(version)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let allowance = installed.app.allowance {
                    Text(allowance)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if installed.app.allowance != nil {
                Button("Open \(installed.app.shortName)") { LinkedApps.open(installed) }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A group's name; over the first, what the two columns are.
private struct AppCommandsHeader: View {
    let title: String
    let columns: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
            Spacer(minLength: 8)
            if columns {
                Group {
                    // Its right edge on the keys' (`AppCommandRow.trailing`).
                    Text("Shortcut")
                    Text("In Search")
                        .frame(width: AppCommandRow.trailing, alignment: .trailing)
                }
                .font(.caption)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }
}

/// A command in Settings → Apps: its symbol and name (its line on hover),
/// its shortcut, and whether search shows it. A variant's row (a shortcut
/// given to Capture and Copy) sits under its command, without a switch:
/// only ⌘K lists variants.
private struct AppCommandRow: View {
    let title: String
    let symbol: String
    let help: String
    let action: SkilliAction
    let shortcutID: String?
    let isOn: Binding<Bool>?
    @Bindable var store: ShortcutStore
    let newShortcut: NewShortcut

    private var variant: Bool { isOn == nil }

    /// From the keys' right edge to the row's: ⓧ and its gap (17), the
    /// keys' padding (8), the gap and the switch (10 + 6 + 32).
    static let trailing: CGFloat = 73

    var body: some View {
        let chords = shortcutID.flatMap { id in store.config.shortcuts.first { $0.id == id }?.chords }
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                IconTile(symbol: symbol, tint: SettingsPane.apps.tint, size: variant ? 18 : 22)
                    .frame(width: 22)
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
            }
            .padding(.leading, variant ? 24 : 0)
            .opacity(isOn?.wrappedValue == false ? 0.45 : 1)
            .help(help)
            Spacer(minLength: 8)
            ShortcutField(store: store, id: shortcutID ?? "apps.unbound.\(action.id)", chords: chords, minWidth: 120) {
                newShortcut.record(action, store)
            }
            Group {
                if let isOn {
                    Toggle("Show in search", isOn: isOn)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help(isOn.wrappedValue ? "In the launcher's results" : "Out of the launcher's results; its shortcut, Ask and links still run it")
                } else {
                    Color.clear
                }
            }
            .frame(width: 32, alignment: .trailing)
            .padding(.leading, 6)
        }
        .padding(.vertical, 1)
        .animation(.easeOut(duration: 0.15), value: store.recordingID == shortcutID)
    }
}
