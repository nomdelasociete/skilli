import AppKit
import SkilliCore
import SwiftUI

/// Settings → Clipboard, in the order of the Settings plan's rules: how
/// to reach it first, as keys (✦C, Paste in Sequence's ✦K V, "cb" in the
/// launcher); keeping copies and screenshots, for how long; what leaves the
/// Mac and to whom; the rest (search by meaning, the words and kinds of
/// images, the apps never kept) under Advanced, closed. A permission shows
/// only while the history lacks it.
struct ClipboardPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy, SI Accounts).
    let open: (SettingsPane) -> Void
    @State private var confirmClear = false

    /// Where the images that join the history come from.
    private func chooseImageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Images saved in this folder join the clipboard history, their words read on this Mac."
        panel.directoryURL = preferences.imageFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.imageTagsFolderPath = url.path == ImageFolderWatcher.screenshotsFolder.path ? "" : url.path
    }

    private enum Keep: Hashable {
        case day, week, month, unlimited, custom
    }

    var body: some View {
        Form {
            Section {
                ForEach(shortcutRows, id: \.id) { row in
                    ShortcutRow(store: context.shortcuts, id: row.id, title: row.title, chords: row.chords)
                }
                if let prefix = LauncherPrefix.shown(for: .clipboardHistory)?.trimmingCharacters(in: .whitespaces) {
                    LabeledContent {
                        KeycapLabel(prefix)
                            .padding(.trailing, 8)
                    } label: {
                        LabelDetail("From the launcher", "Type \(prefix) and a space, then what you look for.")
                    }
                }
                Toggle("Keep clipboard history", isOn: $preferences.clipboardHistory)
                    .settingAnchor("clipboardHistory")
                if preferences.clipboardHistory {
                    missing(.pasteboard)
                    Toggle(isOn: $preferences.clipboardScreenshots) {
                        LabelDetail("Keep screenshots too",
                                    "Found by the words in them, read on this Mac. Paste Latest Screenshot pastes the last one.")
                    }
                    .settingAnchor("clipboardScreenshots")
                    if preferences.clipboardScreenshots {
                        LabeledContent("Folder") {
                            HStack {
                                Text(FileManager.default.displayName(atPath: preferences.imageFolder.path))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("Change…") { chooseImageFolder() }
                            }
                        }
                        .settingAnchor("imageTagsFolderPath")
                    }
                }
            } header: {
                PaneHeader(pane: .clipboard)
            } footer: {
                Text("Type to search, even words inside images. ↩ pastes in the app you are in, ⇧↩ pastes plain text, ⌘↩ only copies, ⌘⌫ forgets.")
            }

            Section {
                Picker("Keep copies for", selection: keep) {
                    Text("1 day").tag(Keep.day)
                    Text("1 week").tag(Keep.week)
                    Text("1 month").tag(Keep.month)
                    Text("Unlimited").tag(Keep.unlimited)
                    Text("Custom").tag(Keep.custom)
                }
                .settingAnchor("clipboardRetention")
                if case .days(let days) = preferences.clipboardRetention {
                    Stepper(value: customDays, in: 1...3650) {
                        Text(days == 1 ? "1 day" : "\(days) days")
                            .monospacedDigit()
                    }
                }
                // Nothing goes as the choice changes: the next hourly pass
                // removes them, and this says it first.
                if let line = preferences.clipboardRetention.removalLine(older: context.clipboard.pendingRemoval) {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                } label: {
                    Text(summary)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .settingAnchor("section.clearHistory")
            } footer: {
                Text(preferences.clipboardRetention == .unlimited
                     ? "Everything stays until you clear it."
                     : "Older copies are removed every hour.")
            }

            // The self-test draws it as set up (`PrivacyPane.sample`).
            if let line = PrivacyMap.line(for: SettingsPane.clipboard.rawValue, PrivacyPane.sample ?? .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            AdvancedSection(summary: "Search by meaning, link previews, words and kinds of images, apps never kept",
                            footer: "Passwords that password managers mark as secret are never kept, whatever the app.",
                            anchors: ["clipboardMeaningSearch", "clipboardLinkPreviews", "clipboardOCR", "imageTagsClipboard", "imageTagsFolder",
                                      "clipboardExcludedApps"]) {
                Toggle(isOn: $preferences.clipboardMeaningSearch) {
                    LabelDetail("Search by meaning with ⇥", "Type what you remember (“the electricity bill from yesterday”), then ⇥.")
                }
                .settingAnchor("clipboardMeaningSearch")
                Toggle(isOn: $preferences.clipboardLinkPreviews) {
                    LabelDetail("Show link previews",
                                "A link you look at shows its page's picture and title: skil.li opens it, without your cookies.")
                }
                .settingAnchor("clipboardLinkPreviews")
                Toggle(isOn: $preferences.clipboardOCR) {
                    LabelDetail("Read text in images", "Vision reads the words of images and screenshots on this Mac, so search finds them.")
                }
                .settingAnchor("clipboardOCR")
                Toggle(isOn: $preferences.imageTagsClipboard) {
                    LabelDetail("Images you copy, by what they show",
                                "Jev says once what each shows: a chart, an invoice, a person… “the invoice” then finds it.")
                }
                .settingAnchor("imageTagsClipboard")
                Toggle(isOn: $preferences.imageTagsFolder) {
                    LabelDetail("Screenshots, by what they show", "The same, for each new image of the folder.")
                }
                .disabled(!preferences.clipboardScreenshots)
                .settingAnchor("imageTagsFolder")
                if !context.hasImageKey() {
                    SIText("Add a TypeSafe key in SI Accounts: images are told what they show once there is one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabelDetail("Never keep copies from", "What you copy in these apps never joins the history.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("clipboardExcludedApps")
                ForEach(preferences.clipboardExcludedApps, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID) {
                        preferences.clipboardExcludedApps.removeAll { $0 == bundleID }
                    }
                }
                Button {
                    guard let url = context.chooseApp(), let bundleID = Bundle(url: url)?.bundleIdentifier,
                          !preferences.clipboardExcludedApps.contains(bundleID) else { return }
                    preferences.clipboardExcludedApps.append(bundleID)
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { context.permissions.startWatching() }
        .onDisappear { context.permissions.stopWatching() }
        .confirmationDialog("Clear the clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { context.clipboard.clear() }
        } message: {
            Text("Every copy and image kept by skil.li is deleted. This cannot be undone.")
        }
    }

    /// The history's keys and Paste in Sequence's, as Settings → Keys
    /// records them.
    private var shortcutRows: [(id: String, title: String, chords: [Chord]?)] {
        [(SkilliAction.clipboardHistory, "Clipboard History"), (SkilliAction.pasteInSequence, "Paste in Sequence")]
            .compactMap { action, title in
                context.shortcuts.config.shortcuts.first { $0.action == action }.map { ($0.id, title, $0.chords) }
            }
    }

    /// Rule 6: a permission the history needs, only while it is not granted.
    @ViewBuilder
    private func missing(_ permission: Permission) -> some View {
        let state = context.permissions.state(permission)
        if state != .granted {
            PermissionRow(permission: permission, state: state, notNeeded: false) {
                context.permissions.grant(permission)
            }
        }
    }

    private var keep: Binding<Keep> {
        Binding(
            get: {
                switch preferences.clipboardRetention {
                case .day: .day
                case .week: .week
                case .month: .month
                case .unlimited: .unlimited
                case .days: .custom
                }
            },
            set: { choice in
                // Never removes anything now: the hourly pass does, said
                // under the choice first.
                preferences.clipboardRetention = switch choice {
                case .day: .day
                case .week: .week
                case .month: .month
                case .unlimited: .unlimited
                case .custom: preferences.clipboardRetention.asCustom
                }
            }
        )
    }

    private var customDays: Binding<Int> {
        Binding(
            get: { preferences.clipboardRetention.days ?? 30 },
            set: { preferences.clipboardRetention = .days($0) }
        )
    }

    /// "124 copies · 18 MB", recounted when the history changes.
    private var summary: String {
        _ = context.clipboard.revision
        guard let store = context.clipboard.store else { return "No history file" }
        let count = store.count
        let size = ByteCountFormatter.string(fromByteCount: store.diskSize, countStyle: .file)
        return "\(count) \(count == 1 ? "copy" : "copies") · \(size)"
    }
}

/// An app left out (its copies never kept, its windows never in layouts):
/// its icon and name, and remove.
struct ExcludedAppRow: View {
    let bundleID: String
    var help = "Keep this app's copies again"
    let remove: () -> Void

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

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
                    Text(ClipboardPolicy.knownNames[bundleID] ?? bundleID)
                    Text("Not on this Mac")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }
}
