import AppKit
import SkilliCore
import SwiftUI

/// Settings → Backup, in the order of the Settings plan's rules: how to
/// back up at once from the launcher (its alias as a keycap, when it has
/// one); where backups go, how often, how many stay, and Back Up Now; what
/// leaves the Mac (nothing from skil.li: a folder that syncs says who
/// syncs it); last, the long list: the backups made, each to put back.
struct BackupPane: View {
    @Bindable var preferences: Preferences
    let backup: BackupCenter
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void
    @State private var items: [BackupCenter.Backup] = []
    @State private var problem: String?
    @State private var restoring: (backup: BackupCenter.Backup, contents: [String])?

    var body: some View {
        Form {
            Section {
                ReachRow(title: "From the launcher", detail: "“Back Up skil.li Now” makes one at once, whatever the schedule.",
                         keys: alias.map { [$0] } ?? [])
                LabeledContent("Back up to") {
                    HStack {
                        Text(backup.folder.map(Self.shown) ?? "No folder yet")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(backup.folder == nil ? "Choose…" : "Change…") { choose() }
                    }
                }
                .settingAnchor("backupFolder")
                Picker("How often", selection: $preferences.backupSchedule) {
                    ForEach(BackupSchedule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .settingAnchor("backupSchedule")
                Picker("Keep", selection: $preferences.backupKeep) {
                    Text("The last 5").tag(5)
                    Text("The last 10").tag(10)
                    Text("The last 30").tag(30)
                    Text("All of them").tag(0)
                }
                .settingAnchor("backupKeep")
                HStack {
                    Button(backup.isWorking ? "Backing Up…" : "Back Up Now") { backUpNow() }
                        .disabled(backup.folder == nil || backup.isWorking)
                    Spacer()
                    if let error = problem ?? backup.lastError {
                        Text(error).foregroundStyle(.red).lineLimit(2)
                    } else if let last = items.first {
                        Text("Last: \(last.date.formatted(date: .abbreviated, time: .shortened)) · \(Self.size(last.bytes))")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingAnchor("section.backUpNow")
            } header: {
                PaneHeader(pane: .backup)
            } footer: {
                Text("Your settings, snippets, commands, quicklinks, skillies, window layouts, shortcuts and tools' rights, in a zip anyone can open. Never what you copied or recorded, nor API keys and sensitive fields: they stay on this Mac. In iCloud Drive, a backup also brings skil.li to a new Mac.")
            }

            if let line = PrivacyMap.line(for: SettingsPane.backup.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        LabeledContent(item.date.formatted(date: .abbreviated, time: .shortened)) {
                            HStack {
                                Text(Self.size(item.bytes)).foregroundStyle(.secondary)
                                Button("Restore…") { prepareRestore(item) }
                                    .disabled(backup.isWorking)
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                }
                                .buttonStyle(.borderless)
                                .help("Show in Finder")
                            }
                        }
                    }
                } header: {
                    Text("Backups")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingAnchor("section.backups")
                } footer: {
                    Text("Restoring backs up what skil.li has now first, then puts the backup's files and settings back and opens skil.li again.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onChange(of: backup.revision) { reload() }
        .onChange(of: preferences.backupFolder) { reload() }
        .confirmationDialog(restoring.map { "Restore the backup of \($0.backup.date.formatted(date: .abbreviated, time: .shortened))?" } ?? "",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restore") { restore() }
            Button("Cancel", role: .cancel) { restoring = nil }
        } message: {
            Text((restoring?.contents.joined(separator: ", ") ?? "") + ". It replaces what skil.li has now, which is backed up first.")
        }
    }

    private func reload() {
        items = backup.backups()
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Where should skil.li put its backups?"
        let iCloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        panel.directoryURL = backup.folder ?? (FileManager.default.fileExists(atPath: iCloud.path) ? iCloud : nil)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.backupFolder = url.path
        problem = nil
    }

    private func backUpNow() {
        problem = nil
        Task {
            do {
                try await backup.backUpNow()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func prepareRestore(_ item: BackupCenter.Backup) {
        problem = nil
        Task {
            do {
                restoring = (item, try await backup.contents(of: item.url))
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func restore() {
        guard let item = restoring?.backup else { return }
        restoring = nil
        Task {
            do {
                try await backup.restore(item.url)
                context.reopen()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Back Up skil.li Now's alias, set in Catalog or with ⌘K.
    private var alias: String? {
        preferences.launcherAliases.first { $0.id == "cmd:\(LauncherCommand.ID.backUpNow.rawValue)" }?.alias
    }

    /// "iCloud Drive › skil.li": the folder as the Finder names it.
    static func shown(_ url: URL) -> String {
        let components = FileManager.default.componentsToDisplay(forPath: url.path) ?? [url.lastPathComponent]
        return components.suffix(2).joined(separator: " › ")
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
