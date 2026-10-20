import AppKit
import SkilliCore
import SwiftUI

/// Settings → Skillies: how one runs (its name in the launcher), skil.li's
/// own commands, scripts in its folder, and what leaves the Mac; then
/// every skillie, grouped by package when they have one (the long list,
/// last). Importing Raycast's Script Commands waits until it is
/// tried for real (`ScriptLibrary.importRaycast`, self-tested only).
struct SkilliesPane: View {
    let skillies: () -> [ScriptCommand]
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void
    @State private var shown: [ScriptCommand] = []

    var body: some View {
        Form {
            Section {
                // How one runs, first, as the Commands pane starts.
                LabeledContent {
                    KeycapLabel("↩")
                        .padding(.horizontal, 8)
                } label: {
                    LabelDetail("From the launcher", "Type a skillie's name, then ↩. Ask runs one too when you say what it does.")
                }
                LabeledContent {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: ScriptLibrary.defaultFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([ScriptLibrary.defaultFolder])
                    }
                } label: {
                    Text("Folder")
                    Text("~/Library/Application Support/skil.li/skillies").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                PaneHeader(pane: .skillies)
            } footer: {
                Text("A script whose first comments say “@skilli.title” and “@skilli.mode” shows in the launcher, takes its arguments there, and Ask and your agents can run it. Ask an agent to write one for you.")
            }

            if let line = PrivacyMap.line(for: SettingsPane.skillies.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            if shown.isEmpty {
                Section {
                    Text("None yet.").foregroundStyle(.secondary)
                } header: {
                    Text("Your Skillies")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingAnchor("skillies")
                }
            }
            // Read here, in the body, so the switches follow a change made
            // elsewhere (the menu bar's Remove, an agent's tool).
            let inMenuBar = Set(preferences.skilliesInMenuBar)
            let grouped = groups
            // Where Settings' search shows "In the menu bar": the first row that has it.
            let firstInMenuBar = grouped.flatMap(\.items).first { menuBarBinding($0, on: false) != nil }?.path
            ForEach(grouped, id: \.title) { group in
                Section {
                    ForEach(group.items, id: \.path) { skillie in
                        let row = SkillieRow(skillie: skillie, inMenuBar: menuBarBinding(skillie, on: inMenuBar.contains(skillie.path)))
                        if skillie.path == firstInMenuBar {
                            row.settingAnchor("skilliesInMenuBar")
                        } else {
                            row
                        }
                    }
                } header: {
                    if group.title == grouped.first?.title {
                        Text(group.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .settingAnchor("skillies")
                    } else {
                        Text(group.title)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { shown = skillies() }
    }

    /// An inline skillie with no argument can show its line in the menu
    /// bar; the others have nothing to show there.
    private func menuBarBinding(_ skillie: ScriptCommand, on: Bool) -> Binding<Bool>? {
        guard skillie.mode == .inline, skillie.arguments.isEmpty else { return nil }
        return Binding(
            get: { on },
            set: { on in
                preferences.skilliesInMenuBar.removeAll { $0 == skillie.path }
                if on { preferences.skilliesInMenuBar.append(skillie.path) }
            })
    }

    /// One group per package ("Developer Utils"), those without one first;
    /// a single group when no skillie names a package.
    private var groups: [(title: String, items: [ScriptCommand])] {
        let packages = Dictionary(grouping: shown, by: \.packageName)
        guard packages.count > 1 || packages.keys.first.map({ !$0.isEmpty }) == true else {
            return shown.isEmpty ? [] : [("Your Skillies", shown)]
        }
        return packages.keys.sorted { lhs, rhs in
            lhs.isEmpty != rhs.isEmpty ? lhs.isEmpty : lhs.localizedStandardCompare(rhs) == .orderedAscending
        }.map { ($0.isEmpty ? "Your Skillies" : $0, packages[$0] ?? []) }
    }

}

/// A skillie: its icon, title and what it does (or its file), the
/// arguments it asks for, and its file in the Finder.
private struct SkillieRow: View {
    let skillie: ScriptCommand
    /// Inline skillies only: its line in the menu bar.
    let inMenuBar: Binding<Bool>?

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let inMenuBar {
                    // The words first, then the switch, as a settings row reads.
                    Text("In the menu bar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Toggle("In the menu bar", isOn: inMenuBar)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .help("Its last line in the menu bar, read again at its own pace")
                }
                if !skillie.arguments.isEmpty {
                    Text(skillie.arguments.count == 1 ? "1 argument" : "\(skillie.arguments.count) arguments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skillie.path)])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skillie.title)
                    Text(skillie.description.isEmpty ? (skillie.path as NSString).lastPathComponent : skillie.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                SkillieIcon(skillie: skillie)
            }
        }
    }
}

/// The skillie's emoji or image, as the launcher shows it; else a terminal.
private struct SkillieIcon: View {
    let skillie: ScriptCommand

    var body: some View {
        let icon = skillie.icon
        if !icon.isEmpty, icon.count <= 2,
           icon.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0xFF }) {
            Text(icon)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)
        } else if let image = imageFile {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        } else {
            IconTile(symbol: "terminal.fill", tint: .gray, size: 22)
        }
    }

    /// An image named by the header, beside the script or by its path.
    private var imageFile: NSImage? {
        let icon = skillie.icon
        guard !icon.isEmpty, !icon.hasPrefix("http") else { return nil }
        let path = icon.hasPrefix("/") ? icon : ((skillie.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(icon)
        return NSImage(contentsOfFile: path)
    }
}
