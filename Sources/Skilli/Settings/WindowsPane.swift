import AppKit
import SkilliCore
import SwiftUI

/// Settings → Windows, the Settings rules in order: how to reach it (✦W,
/// "save layout"), Accessibility only while it is missing, the settings
/// that matter (the space between windows with its preview, the apps you
/// stopped using quit), the layouts,
/// grouped by the displays they are made for, what leaves the Mac
/// (nothing), and what is rarely changed under Advanced, closed.
struct WindowsPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    reach
                } label: {
                    LabelDetail("Move the window in front",
                                "An arrow for a half, again soon for ⅔ then ⅓; F fills, C centers, N the next display, R puts it back.")
                }
                LabeledContent {
                    KeycapLabel("save layout")
                } label: {
                    LabelDetail("Save where every window is", "In the launcher, with a name: “save layout Coding”.")
                }
                missing(.accessibility)
            } header: {
                PaneHeader(pane: .windows)
            } footer: {
                Text("Or type “left half” in the launcher, or ask.")
            }

            Section {
                Picker("Space between windows", selection: $preferences.windowGap) {
                    ForEach(Preferences.windowGaps, id: \.self) { points in
                        Text(points == 0 ? "None" : "\(points) points").tag(points)
                    }
                }
                .settingAnchor("windowGap")
                WindowGapPreview(gap: CGFloat(preferences.windowGap))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } footer: {
                Text("Between windows side by side and at the screen's edges, for every place: halves, thirds, quarters, Maximize, and the windows you place in a layout.")
            }

            ArrangeSection(preferences: preferences, context: context)

            AutoQuitSection(preferences: preferences, context: context)

            Section {
                HStack {
                    Button("New Layout from the Windows Open…") { context.editLayout(nil) }
                    Button("New Empty Layout…") { context.newEmptyLayout() }
                }
                if layouts.isEmpty {
                    Text("No layouts yet.")
                        .foregroundStyle(.secondary)
                }
                // One group: the layouts right here.
                if groups.count == 1 {
                    ForEach(groups[0].layouts) { layout in
                        LayoutRow(layout: layout, context: context, delete: { context.deleteLayout(layout) })
                    }
                }
            } header: {
                Text("Layouts")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("windowLayouts")
            } footer: {
                Text("Every window open, minimized and full screen too, looked over before it is saved; or start empty and add apps, files, folders and links. Typing its name in the launcher puts them all back.")
            }

            // Several: grouped by the displays they are made for.
            ForEach(groups.count > 1 ? groups : [], id: \.title) { group in
                Section {
                    ForEach(group.layouts) { layout in
                        LayoutRow(layout: layout, context: context, delete: { context.deleteLayout(layout) })
                    }
                } header: {
                    Text(group.title)
                }
            }

            if let line = PrivacyMap.line(for: SettingsPane.windows.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            AdvancedSection(summary: "Apps never placed, apps always left out of layouts, monitors ignored when plugged in",
                            anchors: ["windowNeverPlace", "windowLayoutIgnoredApps", "ignoredMonitors"]) {
                advancedRows
            }
        }
        .formStyle(.grouped)
        .onAppear { context.permissions.startWatching() }
        .onDisappear { context.permissions.stopWatching() }
    }

    /// ✦W, as Keys has it now: the first keys of Left Half's shortcut.
    @ViewBuilder
    private var reach: some View {
        let chords = context.shortcuts.config.shortcuts.first { $0.action == .mac(.window(.leftHalf)) }?.chords ?? []
        if chords.count > 1 {
            HStack(spacing: 6) {
                ShortcutView(chords: chords.dropLast().map(\.keycaps))
                Text("then a key")
                    .foregroundStyle(.secondary)
            }
        } else if !chords.isEmpty {
            ShortcutView(chords: chords.map(\.keycaps))
        }
    }

    /// Rule 6: Accessibility, which moving another app's windows needs,
    /// only while it is not granted.
    @ViewBuilder
    private func missing(_ permission: Permission) -> some View {
        let state = context.permissions.state(permission)
        if state != .granted {
            PermissionRow(permission: permission, state: state, notNeeded: false) {
                context.permissions.grant(permission)
            }
        }
    }

    /// Rarely changed: the apps every layout leaves out, the monitors that
    /// offer nothing when plugged in. One row each, like the lists above.
    @ViewBuilder
    private var advancedRows: some View {
        LabelDetail("Never place", "Arrange Windows leaves their windows where they are, and nothing is learned from them.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingAnchor("windowNeverPlace")
        ForEach(preferences.windowNeverPlace, id: \.self) { bundleID in
            ExcludedAppRow(bundleID: bundleID, help: "Arrange this app's windows again") {
                preferences.windowNeverPlace.removeAll { $0 == bundleID }
            }
        }
        HStack {
            Button("Never Place an App…") {
                guard let url = context.chooseApp(), let bundleID = Bundle(url: url)?.bundleIdentifier,
                      !preferences.windowNeverPlace.contains(bundleID) else { return }
                preferences.windowNeverPlace.append(bundleID)
            }
            Spacer()
        }
        LabelDetail("Always leave out of layouts", "Their windows show unticked in the editor: tick one to keep it in a layout once.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingAnchor("windowLayoutIgnoredApps")
        ForEach(preferences.windowLayoutIgnoredApps, id: \.self) { bundleID in
            ExcludedAppRow(bundleID: bundleID, help: "Take this app in layouts again") {
                preferences.windowLayoutIgnoredApps.removeAll { $0 == bundleID }
            }
        }
        HStack {
            Button("Add App…") {
                guard let url = context.chooseApp(), let bundleID = Bundle(url: url)?.bundleIdentifier,
                      !preferences.windowLayoutIgnoredApps.contains(bundleID) else { return }
                preferences.windowLayoutIgnoredApps.append(bundleID)
            }
            Spacer()
        }
        LabelDetail("Monitors ignored when plugged in",
                    preferences.ignoredMonitors.isEmpty
                        ? "None. Ignore in the question a monitor asks when it is plugged in adds it here."
                        : "Their layouts are not offered when they are plugged in.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingAnchor("ignoredMonitors")
        ForEach(preferences.ignoredMonitors, id: \.uuid) { monitor in
            HStack {
                Image(systemName: "display")
                    .foregroundStyle(.secondary)
                Text(monitor.name)
                if let serial = monitor.serialText ?? (monitor.serial == 0 ? nil : String(monitor.serial)) {
                    Text("serial \(serial)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    preferences.ignoredMonitors.removeAll { $0.isSameDisplay(as: monitor) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Offer its layouts again when it is plugged in")
            }
        }
    }

    /// Read again whenever skil.li writes or deletes one.
    private var layouts: [SavedWindowLayout] {
        _ = context.arranger?.revision
        return context.arranger?.layouts() ?? []
    }

    /// The layouts by the displays their windows are on ("On Built-in
    /// Retina Display and SAMSUNG"), the largest group first.
    private var groups: [(title: String, layouts: [SavedWindowLayout])] {
        var order: [String] = []
        var byDisplays: [String: [SavedWindowLayout]] = [:]
        for layout in layouts {
            let used = Set(layout.windows.compactMap(\.display))
            let names = layout.displays.indices.filter { used.contains($0) }.map { layout.displays[$0].fingerprint.name }
            let key = names.isEmpty ? "" : names.joined(separator: " and ")
            if byDisplays[key] == nil { order.append(key) }
            byDisplays[key, default: []].append(layout)
        }
        return order.sorted { (byDisplays[$0]?.count ?? 0) > (byDisplays[$1]?.count ?? 0) }
            .map { ($0.isEmpty ? "Saved before displays were known" : "On \($0)", byDisplays[$0] ?? []) }
    }
}

/// A saved layout: what it holds, on which displays, its shortcuts, and
/// what can be done with it.
private struct LayoutRow: View {
    let layout: SavedWindowLayout
    let context: SettingsContext
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.name)
                        .font(.body.weight(.medium))
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Apply") { context.applyLayout(layout) }
                Button("Edit…") { context.editLayout(layout) }
                Menu {
                    if layout.displays.contains(where: { !$0.fingerprint.builtIn }) {
                        Picker("When Its Displays Are Plugged In", selection: Binding(
                            get: { layout.automatic }, set: { context.setLayoutAutomatic(layout, $0) }
                        )) {
                            Text("Ask").tag(SavedWindowLayout.Automatic.ask)
                            Text("Apply Without Asking").tag(SavedWindowLayout.Automatic.always)
                            Text("Never").tag(SavedWindowLayout.Automatic.never)
                        }
                        Divider()
                    }
                    Button("Update to the Windows Open…") { context.updateLayout(layout) }
                    Divider()
                    Button("Delete", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            ForEach(shortcuts, id: \.id) { entry in
                ShortcutRow(store: context.shortcuts, id: entry.id, title: "Shortcut", chords: entry.chords)
            }
            if shortcuts.isEmpty {
                Button("Add Shortcut") { context.shortcuts.beginRecording(context.shortcuts.add(.windowLayout(layout.id))) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    /// "Xcode, Safari and 2 more · 6 windows · opens 2 · asks when SAMSUNG
    /// is plugged in": the displays are the group's title.
    private var details: String {
        let opened = layout.openings.count
        let windows = layout.windows.count - opened
        var parts = [layout.summary]
        if windows > 0 { parts.append("\(windows) window\(windows == 1 ? "" : "s")") }
        if opened > 0 { parts.append("opens " + layout.openings.prefix(2).map { LayoutOpening.name(of: $0.opens ?? "") }.joined(separator: ", ")
            + (opened > 2 ? " and \(opened - 2) more" : "")) }
        let pluggable = layout.displays.filter { !$0.fingerprint.builtIn }.map(\.fingerprint.name)
        if !pluggable.isEmpty {
            let when = pluggable.joined(separator: " or ")
            let plugged: String = switch layout.automatic {
            case .ask: "asks when \(when) is plugged in"
            case .always: "goes back when \(when) is plugged in"
            case .never: "never on its own"
            }
            parts.append(plugged)
        }
        return parts.joined(separator: " · ")
    }

    private var shortcuts: [ShortcutConfig.Entry] {
        context.shortcuts.config.shortcuts.filter { $0.action == .windowLayout(layout.id) }
    }
}

/// Arrange Windows: how it is reached (the launcher; a shortcut only if
/// the user gives it one), learning on or off, and forgetting what was
/// learned (⌘Z for 10 s). The apps never placed are under Advanced.
private struct ArrangeSection: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext

    var body: some View {
        Section {
            LabeledContent {
                if let chords = context.shortcuts.config.shortcuts.first(where: { $0.action == .mac(.system(.arrangeWindows)) })?.chords,
                   !chords.isEmpty {
                    ShortcutView(chords: chords.map(\.keycaps))
                } else {
                    KeycapLabel("arrange")
                }
            } label: {
                LabelDetail("Arrange every window", "Where you usually put it; again within 10 seconds puts them back. A shortcut, if you want one: Catalog.")
            }
            Toggle("Learn where you put windows", isOn: $preferences.windowLearning)
                .settingAnchor("windowLearning")
            Button("Forget What skil.li Learned") { context.forgetPlacements() }
                .settingAnchor("section.forgetPlaces")
        } header: {
            Text("Arrange Windows")
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingAnchor("section.arrangeWindows")
        } footer: {
            Text(preferences.windowLearning
                 ? "From your own moves and ✦W: each app's place, its windows' titles and files, the displays and the apps beside it. Kept on this Mac, never sent. A layout saved for the apps open comes first."
                 : "Off: nothing is read or kept, and Arrange Windows uses only your saved layouts.")
        }
    }
}

/// Auto Quit: off by default; on, how long an app goes unused before it is
/// quit, and the apps never quit (+ and −).
private struct AutoQuitSection: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext

    var body: some View {
        Section {
            Toggle("Quit apps you stopped using", isOn: $preferences.autoQuit)
                .settingAnchor("autoQuit")
            if preferences.autoQuit {
                Picker("Unused for", selection: $preferences.autoQuitMinutes) {
                    ForEach(AutoQuit.delays, id: \.self) { Text(AutoQuit.spoken(minutes: $0)).tag($0) }
                }
                .settingAnchor("autoQuitMinutes")
                if !preferences.autoQuitNever.isEmpty {
                    LabelDetail("Never quit", "These stay open however long you leave them.")
                }
                ForEach(preferences.autoQuitNever, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID, help: "Quit this app too when you stop using it") {
                        preferences.autoQuitNever.removeAll { $0 == bundleID }
                    }
                }
                Button("Never Quit an App…") {
                    guard let url = context.chooseApp(), let bundleID = Bundle(url: url)?.bundleIdentifier,
                          !preferences.autoQuitNever.contains(bundleID) else { return }
                    preferences.autoQuitNever.append(bundleID)
                }
                .settingAnchor("autoQuitNever")
            }
        } header: {
            Text("Apps You Stopped Using")
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingAnchor("section.appsStoppedUsing")
        } footer: {
            if preferences.autoQuit {
                Text("Quit without a word once unused that long; one that does not quit is said. Never the app in front, one with unsaved work or a question open, one playing sound or in a call, or one still working.")
            } else {
                Text("Frees memory: the apps you have not used for a while are quit for you.")
            }
        }
    }
}
