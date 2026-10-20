import AppKit
import SkilliCore
import SwiftUI

/// Settings → Snippets, in the order of the Settings plan's rules: how to
/// reach them first ("snip" in the launcher, a keyword anywhere), when
/// keywords expand (with a preview by the same matcher typing uses),
/// snippets by meaning; what leaves the Mac; the snippets, an editor
/// each; the apps where keywords stay as typed under Advanced, closed.
struct SnippetsPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy, SI Accounts).
    let open: (SettingsPane) -> Void
    @State private var snippets: [Snippet] = []
    @State private var editing: Snippet?
    /// The launcher's New Snippet asks through it.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    private var library: SnippetLibrary { context.snippets }

    var body: some View {
        Form {
            Section {
                if let prefix = LauncherPrefix.shown(for: .searchSnippets)?.trimmingCharacters(in: .whitespaces) {
                    LabeledContent {
                        KeycapLabel(prefix)
                            .padding(.trailing, 8)
                    } label: {
                        LabelDetail("From the launcher", "Type \(prefix) and a space, then a snippet's name, or what you need then ⇥.")
                    }
                }
                Toggle(isOn: $preferences.snippetExpansion) {
                    LabelDetail("Expand keywords as you type", "Type a snippet's keyword in any app (;date) and it becomes the snippet.")
                }
                .settingAnchor("snippetExpansion")
                if preferences.snippetExpansion {
                    missing(.accessibility)
                    Picker("Expand", selection: $preferences.snippetExpansionMode) {
                        ForEach(SnippetExpansionMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .settingAnchor("snippetExpansionMode")
                    SnippetExpansionPreview(mode: preferences.snippetExpansionMode)
                }
                Toggle(isOn: $preferences.snippetMeaningSearch) {
                    LabelDetail("Find snippets by meaning with ⇥", "In the launcher, type snip and a space, then what you need (“my iban”, “adresse du bureau”), then ⇥. Elsewhere in the launcher, ⇥ asks Ask.")
                }
                .settingAnchor("snippetMeaningSearch")
            } header: {
                PaneHeader(pane: .snippets)
            } footer: {
                Text("Never in password fields. To spot keywords skil.li keeps the last few characters typed, in memory only.")
            }

            // The self-test draws it as set up (`PrivacyPane.sample`).
            if let line = PrivacyMap.line(for: SettingsPane.snippets.rawValue, PrivacyPane.sample ?? .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            Section {
                ForEach(snippets) { snippet in
                    Button {
                        editing = snippet
                    } label: {
                        SnippetRow(snippet: snippet)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    editing = Self.new
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
            } header: {
                Text("Snippets")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("snippets")
            } footer: {
                Text("↩ types one in the app you are in, ⌘↩ copies it. Each is a Markdown file in ~/Library/Application Support/skil.li/snippets.")
            }

            AdvancedSection(summary: "Apps where keywords stay as typed", footer: "Password fields never expand, whatever the app.",
                            anchors: ["snippetExcludedApps"]) {
                LabelDetail("Keywords stay as typed in", "Password managers out of the box.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("snippetExcludedApps")
                ForEach(preferences.snippetExcludedApps, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID, help: "Expand keywords in this app again") {
                        preferences.snippetExcludedApps.removeAll { $0 == bundleID }
                    }
                }
                Button {
                    guard let url = context.chooseApp(), let bundleID = Bundle(url: url)?.bundleIdentifier,
                          !preferences.snippetExcludedApps.contains(bundleID) else { return }
                    preferences.snippetExcludedApps.append(bundleID)
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            snippets = library.all
            context.permissions.startWatching()
            startAsked()
        }
        .onChange(of: navigation?.new) { startAsked() }
        .onDisappear { context.permissions.stopWatching() }
        .onReceive(NotificationCenter.default.publisher(for: SettingTools.changed)) { _ in snippets = library.all }
        .sheet(item: $editing) { snippet in
            SnippetEditor(
                snippet: snippet,
                keywordTaken: { keyword in snippets.contains { $0.keyword == keyword && $0.id != snippet.id } },
                save: { saved in
                    _ = library.save(saved)
                    snippets = library.all
                    editing = nil
                },
                delete: {
                    // At once; ⌘Z in the card puts it back (rule 2).
                    context.deletes.snippet(snippet, in: library)
                    snippets = library.all
                    editing = nil
                },
                cancel: { editing = nil }
            )
        }
    }

    private static var new: Snippet { Snippet(id: "", name: "", text: "") }

    /// New Snippet in the launcher: Add Snippet's editor, unless one is open.
    private func startAsked() {
        guard navigation?.take(.snippet) == true, editing == nil else { return }
        editing = Self.new
    }

    /// Rule 6: a permission expansion needs, only while it is not granted.
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

/// What typing becomes with the mode picked, by `SnippetMatcher.result`:
/// the matcher typing uses, on two sample snippets.
private struct SnippetExpansionPreview: View {
    let mode: SnippetExpansionMode

    private static let samples = [
        Snippet(id: "sig", name: "Signature", keyword: ";sig", text: "Camille"),
        Snippet(id: "addr", name: "Address", keyword: "addr", text: "12 rue des Lilas")
    ]
    private static let typed = ["Merci, ;sig", "chez addr "]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.typed, id: \.self) { typed in
                let result = SnippetMatcher.result(of: typed, snippets: Self.samples, mode: mode)
                HStack(spacing: 8) {
                    Text(Self.shown(typed))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    if result == typed {
                        Text("waits for ␣ or ↩")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(Self.shown(result))
                    }
                }
                .font(.system(.callout, design: .monospaced))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(mode.title)")
    }

    /// A space at the end as ␣, a new line as ↩: what was typed shows.
    private static func shown(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\n", with: "↩")
        if text.hasSuffix(" ") { text = String(text.dropLast()) + "␣" }
        return text
    }
}

/// Name and first words; the keyword as a keycap.
private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                Text(ClipboardSearch.title(of: snippet.text, limit: 70))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !snippet.keyword.isEmpty {
                Text(snippet.keyword)
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
}

/// One snippet: name, keyword, text with its placeholders.
private struct SnippetEditor: View {
    @State var snippet: Snippet
    let keywordTaken: (String) -> Bool
    let save: (Snippet) -> Void
    let delete: () -> Void
    let cancel: () -> Void

    private var isNew: Bool { snippet.id.isEmpty }

    private static let placeholders: [(token: String, help: String)] = [
        (Snippet.cursorToken, "Where the caret ends"),
        (PromptTemplate.Variable.clipboard.token, PromptTemplate.Variable.clipboard.summary),
        (PromptTemplate.Variable.date.token, PromptTemplate.Variable.date.summary),
        (PromptTemplate.Variable.time.token, PromptTemplate.Variable.time.summary),
        (PromptTemplate.Variable.day.token, PromptTemplate.Variable.day.summary),
        (PromptTemplate.Variable.name.token, PromptTemplate.Variable.name.summary)
    ]

    /// What stops Save, said plainly.
    private var problem: String? {
        let keyword = snippet.keyword
        if keyword.contains(where: \.isWhitespace) { return "A keyword has no spaces." }
        if !keyword.isEmpty, keyword.count < 2 { return "A keyword has at least two characters." }
        if !keyword.isEmpty, keywordTaken(keyword) { return "Another snippet uses “\(keyword)”." }
        return nil
    }

    private var canSave: Bool {
        !snippet.name.trimmingCharacters(in: .whitespaces).isEmpty && !snippet.text.isEmpty && problem == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Snippet" : "Edit Snippet")
                .font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("", text: $snippet.name, prompt: Text("Home address"))
                }
                GridRow {
                    Text("Keyword").foregroundStyle(.secondary)
                    TextField("", text: $snippet.keyword, prompt: Text(";addr"))
                        .font(.system(.body, design: .monospaced))
                }
            }
            TextEditor(text: $snippet.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 170)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 6) {
                Text("Insert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Self.placeholders, id: \.token) { placeholder in
                    Button(placeholder.token) { snippet.text += placeholder.token }
                        .controlSize(.small)
                        .help(placeholder.help)
                }
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive, action: delete)
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(snippet) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    // ⌘S saves too: ↩ is a new line in the text.
                    .background {
                        Button("Save") { save(snippet) }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!canSave)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
