import AppKit
import SkilliCore
import SwiftUI

/// Settings → Auto Quit, everything about it in one place: off by default;
/// on, only the apps listed are quit, each once unused for its own delay
/// (a choice, or any time typed from 5 minutes to a week). Accessibility
/// only while it is missing (without it nothing goes), what leaves the Mac,
/// then the list, last, shown whether it is on or off.
struct AutoQuitPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.autoQuit) {
                    LabelDetail("Quit apps you stopped using", "Only the apps listed below, each once unused for the time set beside it.")
                }
                .settingAnchor("autoQuit")
                if preferences.autoQuit {
                    missing(.accessibility)
                }
            } header: {
                PaneHeader(pane: .autoQuit)
            } footer: {
                Text(preferences.autoQuit
                     ? "Quit without a word; one that does not quit is said. Never the app in front, one with unsaved work or a question open, one playing sound or in a call, or one still working."
                     : "Off: no app is ever quit. The list below stays as you set it.")
            }

            // The self-test draws it as set up (`PrivacyPane.sample`).
            if let line = PrivacyMap.line(for: SettingsPane.autoQuit.rawValue, PrivacyPane.sample ?? .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            Section {
                ForEach(preferences.autoQuitApps, id: \.bundleID) { rule in
                    AutoQuitAppRow(rule: rule, change: { minutes in
                        guard let index = preferences.autoQuitApps.firstIndex(where: { $0.bundleID == rule.bundleID }) else { return }
                        preferences.autoQuitApps[index].minutes = AutoQuit.clamped(minutes)
                    }, remove: {
                        preferences.autoQuitApps.removeAll { $0.bundleID == rule.bundleID }
                    })
                }
                Button("Add an App…") {
                    guard let url = context.chooseApp(), let bundleID = Bundle(url: url)?.bundleIdentifier,
                          !preferences.autoQuitApps.contains(where: { $0.bundleID == bundleID }) else { return }
                    preferences.autoQuitApps.append(AutoQuit.Rule(bundleID: bundleID, minutes: AutoQuit.defaultDelay))
                }
            } header: {
                Text("Apps to Quit")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("autoQuitApps")
            } footer: {
                Text(preferences.autoQuitApps.isEmpty
                     ? "No app yet: none is ever quit. Add the ones you leave open for nothing; an app not listed stays open however long you leave it."
                     : "Unused: not in front for that long. An app not listed stays open however long you leave it.")
            }
        }
        .formStyle(.grouped)
        .onAppear { context.permissions.startWatching() }
        .onDisappear { context.permissions.stopWatching() }
    }

    /// Accessibility, which seeing unsaved work needs, only while it is
    /// not granted.
    @ViewBuilder
    private func missing(_ permission: Permission) -> some View {
        let state = context.permissions.state(permission)
        if state != .granted {
            PermissionRow(permission: permission, state: state, notNeeded: false) {
                context.permissions.grant(permission)
            }
        }
    }
}

/// One listed app: its icon and name, how long it may go unused (a choice,
/// or Custom… for any time typed), and − to take it off the list.
private struct AutoQuitAppRow: View {
    let rule: AutoQuit.Rule
    let change: (Int) -> Void
    let remove: () -> Void
    @State private var typing = false
    @State private var draft = ""
    @State private var wrong = false

    /// The Custom… choice's tag: no delay is negative.
    private static let custom = -1

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) }

    var body: some View {
        HStack(spacing: 10) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.bundleID)
                    Text("Not on this Mac")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if typing {
                TextField("Unused for", text: $draft, prompt: Text("90 min, 3 h, 2 days"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .foregroundStyle(wrong ? .red : .primary)
                    .help("From 5 minutes to 7 days")
                    .onSubmit(commit)
                    .onExitCommand { typing = false }
                Button("Set", action: commit)
            } else {
                Picker("Unused for", selection: Binding(get: { rule.minutes }, set: { minutes in
                    if minutes == Self.custom {
                        draft = AutoQuit.spoken(minutes: rule.minutes)
                        wrong = false
                        typing = true
                    } else {
                        change(minutes)
                    }
                })) {
                    ForEach(choices, id: \.self) { Text(AutoQuit.spoken(minutes: $0)).tag($0) }
                    Divider()
                    Text("Custom…").tag(Self.custom)
                }
                .labelsHidden()
                .fixedSize()
            }
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Never quit this app")
        }
    }

    /// The usual delays, and this app's own when it is another.
    private var choices: [Int] {
        AutoQuit.delays.contains(rule.minutes) ? AutoQuit.delays : (AutoQuit.delays + [rule.minutes]).sorted()
    }

    private func commit() {
        guard let minutes = AutoQuit.minutes(from: draft) else {
            wrong = true
            return
        }
        change(minutes)
        typing = false
    }
}
