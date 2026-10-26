import AppKit
import SkilliCore
import SwiftUI

/// Settings → Skillies' state, kept by the window: the skillies a
/// `.skilli` file or a `skilli://skillies/import` link would add
/// (docs/skillie-files.md), shown whole before Add. The self-test calls
/// what the sheet's buttons call.
@MainActor
@Observable
final class SkilliesPaneModel {
    /// A skillie a file or link would add, read and checked.
    struct ImportCandidate: Identifiable {
        let id = UUID()
        let checked: SkillieFile.Checked
        /// The site it was downloaded from, else the file's name.
        let source: String
        /// The user's skillie with its title: replaced in place.
        let replacing: ScriptCommand?
        /// Exactly the one the user has: nothing to add.
        let same: Bool
    }

    var pendingImport: [ImportCandidate] = []
    var importErrors: [String] = []
    var isImporting: Bool {
        get { !pendingImport.isEmpty || !importErrors.isEmpty }
        set { if !newValue { pendingImport = []; importErrors = [] } }
    }
    /// What Add or Replace would write.
    var toAdd: [ImportCandidate] { pendingImport.filter { !$0.same } }
    /// Where skillies are added (set by the app).
    var library: ScriptLibrary?
    /// Bumped when skillies were added here: the list draws them.
    private(set) var changed = 0
    /// The launcher's rows follow (set by the app).
    var onSkilliesChanged: (() -> Void)?

    /// `.skilli` files opened in skil.li (Finder, the Dock, Open With).
    func receive(files: [URL]) async {
        for file in files {
            let read = await Task.detached(priority: .userInitiated) { () -> Result<(Data, String?), Error> in
                Result(catching: { (try Self.read(file), Self.whereFrom(file)) })
            }.value
            switch read {
            case .success(let (data, from)): prepare(data, name: file.lastPathComponent, source: from ?? file.lastPathComponent)
            case .failure(let error): importErrors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// A `skilli://skillies/import` link's addresses (https, small files only).
    func receive(links: [URL]) async {
        for url in links {
            do {
                let data = try await SmallDownload.data(url, largest: SkillieFile.largest,
                                                        tooLarge: "over \(SkillieFile.largest / 1024) KB: not a skillie")
                prepare(data, name: url.lastPathComponent, source: url.host() ?? url.absoluteString)
            } catch {
                importErrors.append("\(url.absoluteString): \(error.localizedDescription)")
            }
        }
    }

    func prepare(_ data: Data, name: String, source: String) {
        do {
            let checked = try SkillieFile.check(data, name: name)
            guard !pendingImport.contains(where: { $0.checked.command.title.localizedCaseInsensitiveCompare(checked.command.title) == .orderedSame }) else {
                importErrors.append("“\(checked.command.title)” is twice in what was opened.")
                return
            }
            let replacing = SkillieFile.replaced(by: checked.command, among: library?.all() ?? [])
            let same = replacing.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } == checked.text
            pendingImport.append(ImportCandidate(checked: checked, source: source, replacing: replacing, same: same))
        } catch {
            importErrors.append("\(name): \(error.localizedDescription)")
        }
    }

    /// Adds (or replaces) every pending skillie; one that cannot be
    /// written is said.
    @discardableResult
    func confirmImport() -> [ScriptCommand] {
        var added: [ScriptCommand] = []
        var failed: [String] = []
        for candidate in toAdd {
            do {
                guard let library else { throw ScriptLibrary.Failure(message: "No skillies folder.") }
                added.append(try library.add(candidate.checked, replacing: candidate.replacing))
            } catch {
                failed.append("\(candidate.checked.command.title): \(error.localizedDescription)")
            }
        }
        pendingImport = []
        importErrors = failed
        changed += 1
        onSkilliesChanged?()
        return added
    }

    /// The file, refused before it is read when it is too large to be one.
    nonisolated private static func read(_ file: URL) throws -> Data {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= SkillieFile.largest else { throw SkillieFile.Problem(message: "It is over \(SkillieFile.largest / 1024) KB: not a skillie.") }
        return try Data(contentsOf: file)
    }

    /// Where macOS says the file came from (the download's site, or who
    /// sent it): the first address's host, else its first entry.
    nonisolated private static func whereFrom(_ file: URL) -> String? {
        // Spotlight's record; a folder it does not index keeps it on the file.
        let indexed = MDItemCreateWithURL(nil, file as CFURL).flatMap { MDItemCopyAttribute($0, kMDItemWhereFroms) as? [String] }
        guard let entries = indexed ?? onFile(file) else { return nil }
        return entries.lazy.compactMap { URL(string: $0)?.host() }.first ?? entries.first { !$0.isEmpty }
    }

    /// The file's own copy of it, as the browser or AirDrop wrote it.
    nonisolated private static func onFile(_ file: URL) -> [String]? {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let size = getxattr(file.path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(file.path, name, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String]
    }
}

/// Settings → Skillies: how one runs (its name in the launcher), skil.li's
/// own commands, scripts in its folder, and what leaves the Mac; then
/// every skillie, grouped by package when they have one (the long list,
/// last). Importing Raycast's Script Commands waits until it is
/// tried for real (`ScriptLibrary.importRaycast`, self-tested only).
/// A `.skilli` file or an import link shows its sheet here.
struct SkilliesPane: View {
    let skillies: () -> [ScriptCommand]
    @Bindable var preferences: Preferences
    let context: SettingsContext
    @Bindable var model: SkilliesPaneModel
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
        // Added from a file or link: the list with it.
        .onChange(of: model.changed) { shown = skillies() }
        .sheet(isPresented: $model.isImporting) {
            SkillieImportSheet(model: model)
        }
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
        if let emoji = skillie.emojiIcon {
            Text(emoji)
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
        skillie.iconImagePath.flatMap(NSImage.init(contentsOfFile:))
    }
}

// MARK: - Import

private extension ScriptCommand {
    /// Inline with no argument: its line is read (it runs) as the launcher
    /// opens (`ScriptLibrary.refreshInline`), with nobody running it.
    var runsByItself: Bool { mode == .inline && arguments.isEmpty }
}

/// What a `.skilli` file or a `skilli://skillies/import` link would add,
/// whole, before anything is added: each skillie, where it came from, and
/// every line of its code.
private struct SkillieImportSheet: View {
    let model: SkilliesPaneModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let toAdd = model.toAdd
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(toAdd.isEmpty ? "Nothing to Add" : toAdd.count > 1 ? "Add These \(toAdd.count) Skillies?"
                     : toAdd[0].replacing == nil ? "Add This Skillie?" : "Replace This Skillie?")
                    .font(.title3.weight(.semibold))
                if !toAdd.isEmpty {
                    Text("A skillie is a script: when it runs, it runs as you, with your files and apps"
                         + (toAdd.contains { $0.checked.command.runsByItself } ? ", and one that shows a line in the launcher runs each time it opens" : "")
                         + ". Read it, and add only skillies you trust.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            // As tall as the skillies, up to a point; then it scrolls.
            ViewThatFits(in: .vertical) {
                candidates
                ScrollView { candidates }
            }
            .frame(maxHeight: 480)

            Divider()
            HStack {
                Spacer()
                Button(toAdd.isEmpty ? "Close" : "Cancel") {
                    model.isImporting = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if !toAdd.isEmpty {
                    Button(toAdd.count > 1 ? "Add \(toAdd.count) Skillies" : toAdd[0].replacing == nil ? "Add Skillie" : "Replace Skillie") {
                        model.confirmImport()
                        if model.importErrors.isEmpty { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 600)
    }

    private var candidates: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.importErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.pendingImport) { candidate in
                SkillieCandidateCard(candidate: candidate)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One skillie of an import: what it is and does, what it asks, whom it
/// replaces, and its code.
private struct SkillieCandidateCard: View {
    let candidate: SkilliesPaneModel.ImportCandidate

    var body: some View {
        let skillie = candidate.checked.command
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                SkillieIcon(skillie: skillie)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skillie.title).font(.headline)
                    if !skillie.description.isEmpty {
                        Text(skillie.description)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("from \(candidate.source)").font(.caption).foregroundStyle(.secondary)
            }
            if candidate.same {
                Label("Already in your skillies, the same.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let replacing = candidate.replacing {
                Label("Replaces your “\(replacing.title)” (\((replacing.path as NSString).lastPathComponent)).",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            // Every line, as it will be written.
            ScrollView([.vertical, .horizontal]) {
                Text(candidate.checked.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(240, CGFloat(lineCount) * 13 + 22))
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var lineCount: Int { candidate.checked.text.split(separator: "\n", omittingEmptySubsequences: false).count }

    /// "week-number.sh · 1 argument · asks before it runs · Everyday";
    /// an inline one with no argument says it runs as the launcher opens.
    private var details: String {
        let skillie = candidate.checked.command
        var parts = [candidate.checked.fileName]
        if !skillie.arguments.isEmpty { parts.append(skillie.arguments.count == 1 ? "1 argument" : "\(skillie.arguments.count) arguments") }
        if skillie.runsByItself { parts.append("runs each time the launcher opens") }
        if skillie.needsConfirmation { parts.append("asks before it runs") }
        if !skillie.packageName.isEmpty { parts.append(skillie.packageName) }
        return parts.joined(separator: " · ")
    }
}
