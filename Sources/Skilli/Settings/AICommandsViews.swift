import AppKit
import Observation
import SkilliCore
import SwiftUI

/// What Settings → Commands edits: the commands (files in
/// `PromptLibrary`) and each command's shortcut; and About You, which
/// Settings → Your Details shows.
@MainActor
@Observable
final class AICommandsModel {
    private(set) var commands: [AICommand] = []
    var profile = ""
    /// The command open in the editor sheet.
    var editing: AICommand?
    /// Commands from a file or a link, waiting for the user to add them.
    var pendingImport: [ImportCandidate] = []
    /// Why some of them could not be read.
    var importErrors: [String] = []
    var isImporting: Bool {
        get { !pendingImport.isEmpty || !importErrors.isEmpty }
        set { if !newValue { pendingImport = []; importErrors = [] } }
    }
    /// Self-test hook: the open editor's prompt field.
    @ObservationIgnored weak var activeEditor: PromptEditorController?

    @ObservationIgnored let library: PromptLibrary
    @ObservationIgnored let shortcuts: ShortcutStore
    /// Connected servers a command can turn on.
    @ObservationIgnored var toolSettings: ToolSettings?
    /// Who can write, for each command's Model.
    @ObservationIgnored var ai: AIStore?
    /// The editor's Delete: at once, ⌘Z in the card puts it back.
    @ObservationIgnored var deletes: UndoableDeletes?

    init(library: PromptLibrary, shortcuts: ShortcutStore) {
        self.library = library
        self.shortcuts = shortcuts
    }

    func refresh() {
        library.reload()
        commands = library.all
        profile = library.profile
    }

    func isBuiltIn(_ id: String) -> Bool { PromptLibrary.isBuiltIn(id) }
    func isModified(_ id: String) -> Bool { library.isModified(id) }

    func save(_ command: AICommand) {
        var command = command
        command.title = command.title.trimmingCharacters(in: .whitespaces)
        if command.title.isEmpty { command.title = "Untitled" }
        command.questions = Self.cleaned(command.questions)
        library.save(command)
        commands = library.all
    }

    /// Questions with text, each with a distinct id; a default that is no
    /// longer an option is dropped.
    private static func cleaned(_ questions: [PromptQuestion]) -> [PromptQuestion] {
        var result: [PromptQuestion] = []
        for var question in questions {
            question.question = question.question.trimmingCharacters(in: .whitespaces)
            guard !question.question.isEmpty else { continue }
            var base = PromptQuestion.normalizedID(question.id)
            if base.isEmpty { base = PromptQuestion.normalizedID(question.question) }
            if base.isEmpty { base = "answer" }
            var id = base
            var number = 2
            while result.contains(where: { $0.id == id }) {
                id = "\(base)-\(number)"
                number += 1
            }
            question.id = id
            question.options = question.options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let value = question.defaultValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
               question.options.isEmpty || question.options.contains(value) {
                question.defaultValue = value
            } else {
                question.defaultValue = nil
            }
            result.append(question)
        }
        return result
    }

    func delete(_ id: String) {
        library.delete(id)
        shortcuts.removeEntries(for: .aiPrompt(id))
        commands = library.all
    }

    func reset(_ id: String) {
        library.reset(id)
        commands = library.all
    }

    /// New Command: a draft under a free id, not saved. Its editor writes
    /// it, with its shortcuts, only on Save; Cancel leaves nothing behind.
    func draft() -> AICommand {
        AICommand(
            id: library.newID(for: "New Command"),
            title: "New Command",
            prompt: "Describe what to do with the text.\n\n{selection}",
            includeProfile: false,
            model: nil
        )
    }

    /// Self-test hook: a new command saved at once, with an empty shortcut
    /// ready to record (the editor's New Command is a `draft()`).
    func newCommand() -> AICommand {
        let command = draft()
        save(command)
        shortcuts.add(.aiPrompt(command.id))
        return command
    }

    /// Whether `id` has a file yet: a draft from New Command or Duplicate
    /// has none until Save.
    func isSaved(_ id: String) -> Bool { library.command(id) != nil }

    /// A built-in command as skil.li ships it: Reset to Default puts it in
    /// the editor's draft, written on Save.
    func builtIn(_ id: String) -> AICommand? { PromptLibrary.builtIn.first { $0.id == id } }

    /// The editor's Save: the command, then the shortcuts it held.
    func saveFromEditor(_ draft: AICommand) {
        save(draft)
        shortcuts.commitStaged(.aiPrompt(draft.id))
    }

    /// The shortcuts the editor shows for `id`: its own until Save.
    func editorShortcuts(for id: String) -> [ShortcutConfig.Entry] {
        shortcuts.editorEntries(for: .aiPrompt(id))
    }

    // MARK: - Import

    struct ImportCandidate: Identifiable {
        let id = UUID()
        let file: PromptFile
        /// File name or web address it came from.
        let source: String
    }

    /// Reads command files; the import sheet shows what they hold.
    func prepareImport(_ files: [(text: String, source: String)]) {
        for (text, source) in files {
            let file = PromptFile(parsing: text)
            if file.instruction.isEmpty {
                importErrors.append("\(source) holds no command.")
            } else {
                pendingImport.append(ImportCandidate(file: file, source: source))
            }
        }
    }

    /// A `skilli://commands/import` link: commands it carries, then the
    /// ones it points to (https, small text files only).
    func receive(_ request: CommandLink.Request) async {
        prepareImport(request.files.map { ($0, "a link") })
        for url in request.urls {
            do {
                prepareImport([(try await Self.download(url), url.host() ?? url.absoluteString)])
            } catch {
                importErrors.append("\(url.absoluteString): \(error.localizedDescription)")
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
        guard status == 200 else { throw AIError.failed("the server answered \(status)") }
        guard data.count <= 256 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw AIError.failed("not a command file")
        }
        return text
    }

    /// Adds every pending command, each with a shortcut row ready to record.
    @discardableResult
    func confirmImport() -> [AICommand] {
        let added = pendingImport.map { library.importCommand($0.file) }
        for command in added { shortcuts.add(.aiPrompt(command.id)) }
        isImporting = false
        commands = library.all
        return added
    }

    /// Duplicate: a draft copy of `command` as the editor holds it, not
    /// saved; the original stays as it was.
    func duplicate(_ command: AICommand) -> AICommand {
        var copy = AICommand(id: library.newID(for: command.title + " Copy"), file: command.file)
        copy.title = command.title + " Copy"
        return copy
    }

    func saveProfile() {
        library.saveProfile(profile)
    }

    /// The shortcut entry that runs `id`, if any.
    func shortcutEntry(for id: String) -> ShortcutConfig.Entry? {
        shortcutEntries(for: id).first
    }

    /// Every shortcut that runs `id`: a direct one, a chain, or both.
    func shortcutEntries(for id: String) -> [ShortcutConfig.Entry] {
        shortcuts.config.shortcuts.filter { $0.action == .aiPrompt(id) }
    }
}

// MARK: - Pane

/// Settings → Commands, in the order of the Settings plan's rules: how a
/// command is reached (its keys on the selection, its name in the
/// launcher), what leaves the Mac when one runs, then the commands grouped
/// by owner (the user's, then the built-in ones; a click opens the
/// editor), and importing and the files under Advanced, closed.
struct AICommandsPane: View {
    @Bindable var model: AICommandsModel
    /// What leaves the Mac when a command runs (`PrivacyMap.line(for:)`).
    var leaves: PrivacyMap.PaneLine?
    /// Shows another pane (Privacy, SI Accounts).
    var open: (SettingsPane) -> Void = { _ in }
    /// The launcher's New Command asks through it.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if let leader {
                        HStack(spacing: 6) {
                            ShortcutView(chords: [leader])
                            Text("then its key").foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    LabelDetail("On the text you select", "Each command's own keys, beside it below.")
                }
                LabeledContent {
                    KeycapLabel("↩")
                } label: {
                    LabelDetail("From the launcher", "Type a command's name, then ↩.")
                }
            } header: {
                PaneHeader(pane: .commands)
            }

            if let leaves {
                Section {
                    LeavesMacRow(line: leaves, open: open)
                }
            }

            Section {
                let yours = model.commands.filter { !model.isBuiltIn($0.id) }
                if yours.isEmpty {
                    Text("None yet: write one, or import one someone shared (Advanced).").foregroundStyle(.secondary)
                }
                ForEach(yours) { command in row(command) }
                Button {
                    model.editing = model.draft()
                } label: {
                    Label("New Command", systemImage: "plus")
                }
            } header: {
                Text("Your Commands")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("commands")
            }

            Section {
                ForEach(model.commands.filter { model.isBuiltIn($0.id) }) { command in row(command) }
            } header: {
                Text("Built In")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("section.builtIn")
            } footer: {
                Text("A built-in command can be changed and reset, not deleted. About You, which a command can include, is in Your Details.")
            }

            AdvancedSection(summary: "Import commands, the files they are kept in",
                            footer: "Each command is a Markdown file in ~/Library/Application Support/skil.li/prompts. Edit it here or in any editor; changes apply on the next run.",
                            anchors: []) {
                LabeledContent {
                    Button("Import…") { chooseFiles() }
                } label: {
                    LabelDetail("Import commands", "Files (.md) someone shared, shown in full before they are added.")
                }
                if let folder = model.library.folder {
                    LabeledContent {
                        Button("Show Files") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                    } label: {
                        LabelDetail("Command files", "One Markdown file per command, in the Finder.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refresh()
            startAsked()
        }
        .onChange(of: navigation?.new) { startAsked() }
        .sheet(item: $model.editing) { command in
            CommandEditor(model: model, draft: command)
        }
        // The editor closed (Cancel, esc, Duplicate): its unsaved shortcuts
        // go at once, not after the sheet's animation. Save left none.
        .onChange(of: model.editing?.id) { closed, _ in
            if let closed { model.shortcuts.discardStaged(.aiPrompt(closed)) }
        }
        .sheet(isPresented: $model.isImporting) {
            ImportSheet(model: model)
        }
    }

    /// New Command in the launcher: New Command's editor, unless one is open.
    private func startAsked() {
        guard navigation?.take(.command) == true, model.editing == nil else { return }
        model.editing = model.draft()
    }

    private func row(_ command: AICommand) -> some View {
        Button {
            model.editing = command
        } label: {
            CommandRow(command: command, entry: model.shortcutEntry(for: command.id))
        }
        .buttonStyle(.plain)
    }

    /// The first key the commands' chains share (✦K), as keycaps.
    private var leader: [String]? {
        let firsts = model.commands.filter { !$0.isAsk }.flatMap { model.shortcutEntries(for: $0.id) }
            .compactMap(\.chords).filter { $0.count > 1 }.map { $0[0] }
        let counts = Dictionary(grouping: firsts, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key.keycaps
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .plainText]
        panel.message = "Choose command files (.md) to add."
        guard panel.runModal() == .OK else { return }
        model.prepareImport(panel.urls.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { ($0, url.lastPathComponent) }
        })
    }
}

private struct CommandRow: View {
    let command: AICommand
    let entry: ShortcutConfig.Entry?

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "sparkles", tint: .mint, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(command.title)
                    if command.isAct {
                        Text("Tools")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pink)
                    }
                }
                // Ask's prompt is only its {ask.instruction}: say what it is.
                Text(command.isAsk ? "What you type in Ask, with the text you selected" : command.prompt.split(separator: "\n").first.map(String.init) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let chords = entry?.chords {
                ShortcutView(chords: chords.map(\.keycaps))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Editor

/// One command: name, prompt with variables, About You, model, shortcut.
/// Nothing is written until Save (JB 2026-10-17): the draft, its
/// shortcuts (`ShortcutStore.stage`), Reset to Default and Duplicate all
/// stay in the editor; Cancel or esc leaves everything as it was.
struct CommandEditor: View {
    let model: AICommandsModel
    @State var draft: AICommand
    @State private var editor = PromptEditorController()
    @State private var linkCopied = false
    /// One per question: rows keep their identity while names change.
    @State private var questionKeys: [UUID] = []
    @Environment(\.dismiss) private var dismiss

    private var isBuiltIn: Bool { model.isBuiltIn(draft.id) }

    var body: some View {
        VStack(spacing: 0) {
            // The name stays on top while the rest scrolls.
            TextField("Name", text: $draft.title, prompt: Text("Command name"))
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider()
            Form {
                Section {
                    PromptEditor(text: $draft.prompt, controller: editor)
                        .frame(minHeight: 150)
                } header: {
                    HStack {
                        Text("Prompt")
                        Spacer()
                        Menu("Insert Variable") {
                            ForEach(PromptTemplate.Variable.allCases, id: \.self) { variable in
                                Button("\(variable.token)   \(variable.summary)") { editor.insert(variable.token) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } footer: {
                    Text(draft.needsSelection
                         ? "Type { for variables. {selection} is the selected text: the command needs one."
                         : "Type { for variables. Without {selection}, the selected text is added after the prompt, and with nothing selected the answer is inserted at the cursor.")
                    + Text(" Add | trim, | upper, | lower or | raw (no quotes) after a name.")
                }

                ForEach(Array(questionKeys.enumerated()), id: \.element) { index, _ in
                    QuestionEditor(
                        question: questionBinding(index),
                        number: index + 1,
                        insert: { if draft.questions.indices.contains(index) { editor.insert(draft.questions[index].token) } },
                        remove: { removeQuestion(at: index) }
                    )
                }
                Section {
                    Button {
                        addQuestion()
                    } label: {
                        Label(draft.questions.isEmpty ? "Add Question" : "Add Another Question", systemImage: "questionmark.bubble")
                    }
                } footer: {
                    Text("Asked in the card before the command runs: press 1, 2, 3… or click an option; with no options, type the answer. An answer the prompt does not use goes after it.")
                }

                Section {
                    // The tools it has, each with what it lets the command
                    // do; more from Add Tool.
                    ForEach(addedTools, id: \.id) { tool in
                        LabeledContent {
                            Button {
                                draft.tools.removeAll { $0 == tool.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this tool")
                        } label: {
                            Label {
                                LabelDetail(tool.title, tool.detail)
                            } icon: {
                                Image(systemName: tool.symbol)
                            }
                        }
                    }
                    if addedTools.isEmpty {
                        Text("None: it writes its answer from the prompt and your selection.")
                            .foregroundStyle(.secondary)
                    }
                    if !missingTools.isEmpty {
                        Button {
                            showToolMenu()
                        } label: {
                            Label("Add Tool", systemImage: "plus")
                        }
                        .help("Each tool lets the command do one more kind of thing: open apps, read your calendar, use a server…")
                    }
                } header: {
                    Text("Tools")
                } footer: {
                    Text(draft.isAct
                         ? "With tools, the command works as an agent in Claude Code: it takes steps, shows them in the card and asks before it changes anything, as Settings → Ask → When It Acts says. It takes a few seconds more."
                         : "Every command already gets your selection and puts its answer back. Add a tool only when it must do more on its own: open an app, choose a menu, read your calendar, use a server.")
                }

                Section {
                    Picker("Output", selection: Binding(
                        get: { draft.output ?? (draft.isAct ? .card : .replace) },
                        set: { draft.output = $0 == (draft.isAct ? .card : .replace) ? nil : $0 }
                    )) {
                        ForEach(OutputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Include About You", isOn: $draft.includeProfile)
                    if let ai = model.ai {
                        ModelPicker(ai: ai, choice: modelBinding, defaultTitle: "Default (\(defaultLabel(ai)))", claudeOnly: draft.isAct)
                    }
                    // The editor's own until Save (`ShortcutStore.stage`).
                    let entries = model.editorShortcuts(for: draft.id)
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ShortcutRow(store: model.shortcuts, id: entry.id, title: entries.count > 1 ? "Shortcut \(index + 1)" : "Shortcut", chords: entry.chords)
                    }
                    // Another one only once every row has keys; an empty row
                    // records itself on a click.
                    if entries.isEmpty || entries.allSatisfy({ $0.keys != nil }) {
                        LabeledContent(entries.isEmpty ? "Shortcut" : " ") {
                            Button(entries.isEmpty ? "Add Shortcut" : "Add Another Shortcut") {
                                model.shortcuts.beginRecording(model.shortcuts.addStaged())
                            }
                        }
                    }
                } footer: {
                    if let note = modelNote {
                        Text(note)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack(spacing: 10) {
                if isBuiltIn, let original = model.builtIn(draft.id) {
                    // The draft only: Save writes it, Cancel keeps the file.
                    Button("Reset to Default") { draft = original }
                        .disabled(draft == original)
                } else if model.isSaved(draft.id) {
                    Button("Delete", role: .destructive) {
                        if let deletes = model.deletes { deletes.command(draft.id, in: model) } else { model.delete(draft.id) }
                        dismiss()
                    }
                }
                // A copy of the draft in its own editor; this one is left
                // as it was saved.
                Button("Duplicate") {
                    let copy = model.duplicate(draft)
                    dismiss()
                    DispatchQueue.main.async { model.editing = copy }
                }
                Menu {
                    Button("Copy Link") { copyLink() }
                    Button("Export File…") { export() }
                } label: {
                    Text(linkCopied ? "Link Copied" : "Share")
                }
                .fixedSize()
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.saveFromEditor(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                // ⌘S saves too, as in any editor.
                .background {
                    Button("Save") {
                        model.saveFromEditor(draft)
                        dismiss()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            }
            .padding(14)
        }
        .frame(width: 580, height: 680)
        .onAppear {
            model.activeEditor = editor
            questionKeys = draft.questions.map { _ in UUID() }
            // Its shortcuts are the editor's until Save; a new command
            // starts with an empty one, ready to record.
            model.shortcuts.stage(.aiPrompt(draft.id), empty: !model.isSaved(draft.id))
        }
        .onDisappear {
            // Cancel, esc, Duplicate or the window closed: after Save
            // there is nothing left to drop.
            model.shortcuts.discardStaged(.aiPrompt(draft.id))
        }
        .onChange(of: draft.questions.count) {
            // Reset to Default can change the questions.
            while questionKeys.count < draft.questions.count { questionKeys.append(UUID()) }
            if questionKeys.count > draft.questions.count { questionKeys.removeLast(questionKeys.count - draft.questions.count) }
        }
    }

    /// Commands with tools run in Claude Code: a ChatGPT or OpenAI choice
    /// shows as the default there.
    private var modelBinding: Binding<ModelChoice?> {
        Binding(
            get: { draft.isAct && draft.model?.provider != .claude ? nil : draft.model },
            set: { draft.model = $0 }
        )
    }

    private func defaultLabel(_ ai: AIStore) -> String {
        draft.isAct ? "Claude · \(ai.claudeModel.title)" : ai.defaultModel.label
    }

    /// One line when this command cannot write as it says: its provider is
    /// not set up, or its file names a model this skil.li does not know.
    private var modelNote: String? {
        guard let ai = model.ai else { return nil }
        if let unknown = draft.unknownModel {
            return "“\(unknown)” is not a model this version of skil.li knows: the command writes with your default, \(defaultLabel(ai))."
        }
        if draft.isAct {
            return draft.model.map { $0.provider != .claude } == true
                ? "Commands with tools run in Claude Code: this one writes with your default Claude model." : nil
        }
        guard let choice = draft.model, choice.provider != ai.defaultModel.provider,
              case .unavailable(let why, let how) = ai.availability(choice.provider) else { return nil }
        return "\(choice.provider.title): \(why.lowercased()). The command writes with your default, \(ai.defaultModel.label), until you \(how)."
    }

    private func questionBinding(_ index: Int) -> Binding<PromptQuestion> {
        Binding(
            get: { draft.questions.indices.contains(index) ? draft.questions[index] : PromptQuestion(id: "", question: "") },
            set: { if draft.questions.indices.contains(index) { draft.questions[index] = $0 } }
        )
    }

    private func removeQuestion(at index: Int) {
        guard draft.questions.indices.contains(index) else { return }
        questionKeys.remove(at: index)
        draft.questions.remove(at: index)
    }

    /// A tool the command can have: one of skil.li's groups, or a
    /// connected server ("mcp:<name>").
    private struct ToolChoice {
        let id: String
        let title: String
        let detail: String
        let symbol: String
    }

    private var allTools: [ToolChoice] {
        ToolGroup.allCases.map { ToolChoice(id: $0.rawValue, title: $0.title, detail: $0.detail, symbol: $0.symbol) }
            + (model.toolSettings?.servers ?? []).map {
                ToolChoice(id: "mcp:" + $0.name, title: $0.name, detail: "A connected server's tools (Settings → Tools)", symbol: "server.rack")
            }
    }

    /// The command's tools, in the order they are offered.
    private var addedTools: [ToolChoice] { allTools.filter { draft.tools.contains($0.id) } }
    private var missingTools: [ToolChoice] { allTools.filter { !draft.tools.contains($0.id) } }

    /// Add Tool: the native menu of the tools not added yet, each with what
    /// it does under its name (and on hover, whole).
    private func showToolMenu() {
        let menu = NSMenu()
        for tool in missingTools {
            let item = NSMenuItem(title: tool.title, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
            item.subtitle = tool.detail
            item.toolTip = tool.detail
            item.representedObject = tool.id
            menu.addItem(item)
        }
        let target = ToolMenuTarget { id in
            if !draft.tools.contains(id) { draft.tools.append(id) }
        }
        for item in menu.items {
            item.target = target
            item.action = #selector(ToolMenuTarget.pick(_:))
        }
        // The menu holds its target only while it shows.
        withExtendedLifetime(target) {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func addQuestion() {
        var id = "answer"
        var number = 2
        while draft.questions.contains(where: { $0.id == id }) {
            id = "answer-\(number)"
            number += 1
        }
        questionKeys.append(UUID())
        draft.questions.append(PromptQuestion(id: id, question: ""))
    }

    /// The command as it is in the editor, saved or not.
    private var sharedText: String {
        var command = draft
        command.title = command.title.trimmingCharacters(in: .whitespaces)
        return command.file.text
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CommandLink.importLink(for: [sharedText]).absoluteString, forType: .string)
        linkCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { linkCopied = false }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(draft.id).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.message = "Anyone can add this command with Import… in Settings → Commands."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? sharedText.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension OutputMode {
    var title: String {
        switch self {
        case .replace: "Replace Selection"
        case .insert: "Insert After Selection"
        case .copy: "Copy to Clipboard"
        case .card: "Show in Card"
        }
    }
}

/// One question: its text, its options (or a typed answer), the default,
/// and the name the prompt uses.
private struct QuestionEditor: View {
    @Binding var question: PromptQuestion
    let number: Int
    let insert: () -> Void
    let remove: () -> Void
    @State private var optionsText = ""
    @State private var idText = ""

    var body: some View {
        Section {
            TextField("Question", text: $question.question, prompt: Text("Which tone?"))
            TextField("Options", text: $optionsText, prompt: Text("Friendly, Formal, Short — or empty to type the answer"))
                .onChange(of: optionsText) { question.options = PromptFile.list(optionsText) }
            if question.options.isEmpty {
                TextField("Default", text: Binding(
                    get: { question.defaultValue ?? "" },
                    set: { question.defaultValue = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Optional"))
            } else {
                Picker("Default", selection: Binding(
                    get: { question.defaultValue.flatMap { question.options.contains($0) ? $0 : nil } ?? question.options[0] },
                    set: { question.defaultValue = $0 }
                )) {
                    ForEach(question.options, id: \.self) { Text($0).tag($0) }
                }
            }
            LabeledContent("In the Prompt") {
                HStack(spacing: 8) {
                    TextField("Name", text: $idText)
                        .labelsHidden()
                        .frame(width: 120)
                        .onChange(of: idText) {
                            let id = PromptQuestion.normalizedID(idText)
                            if !id.isEmpty { question.id = id }
                        }
                    Button(question.token, action: insert)
                        .help("Insert \(question.token) in the prompt")
                }
            }
        } header: {
            HStack {
                Text("Question \(number)")
                Spacer()
                Button("Remove", role: .destructive, action: remove)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
        .onAppear {
            optionsText = question.options.joined(separator: ", ")
            idText = question.id
        }
    }
}

// MARK: - Import

/// What a file or link would add, in full, before anything is added: a
/// command's prompt goes to Claude with the user's selection.
private struct ImportSheet: View {
    let model: AICommandsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.pendingImport.count == 1 ? "Add This Command?" : model.pendingImport.isEmpty ? "Nothing to Add" : "Add These \(model.pendingImport.count) Commands?")
                    .font(.title3.weight(.semibold))
                SIText("Each prompt is sent to your SI with the text you select. Add only commands you trust.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            // As tall as the commands, up to a point; then it scrolls.
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
                if !model.pendingImport.isEmpty {
                    Button(model.pendingImport.count == 1 ? "Add Command" : "Add \(model.pendingImport.count) Commands") {
                        model.confirmImport()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 540)
    }

    private var candidates: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.importErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            ForEach(model.pendingImport) { candidate in
                CandidateCard(candidate: candidate, modelNote: modelNote(candidate.file))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A model this skil.li does not know, or one it cannot run now: the
    /// command is added all the same and writes with the default.
    private func modelNote(_ file: PromptFile) -> String? {
        let fallback = model.ai.map { "your default, \($0.defaultModel.label)" } ?? "your default"
        switch ModelChoice.parse(model: file.model, effort: file.effort) {
        case .standard:
            return nil
        case .unknown(let text):
            return "Names “\(text)”, a model this version of skil.li does not know: it will write with \(fallback)."
        case .choice(let choice):
            guard let ai = model.ai, case .unavailable(let why, let how) = ai.availability(choice.provider) else { return nil }
            return "Writes with \(choice.label). \(choice.provider.title): \(why.lowercased()), so it will use \(fallback) until you \(how)."
        }
    }

    private struct CandidateCard: View {
        let candidate: AICommandsModel.ImportCandidate
        let modelNote: String?

        var body: some View {
            let file = candidate.file
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconTile(symbol: "sparkles", tint: .mint, size: 22)
                    Text(file.title ?? "Untitled").font(.headline)
                    Spacer()
                    Text("from \(candidate.source)").font(.caption).foregroundStyle(.secondary)
                }
                Text(details(file)).font(.caption).foregroundStyle(.secondary)
                Text(file.instruction)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                if let modelNote {
                    Label(modelNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                if !file.tools.isEmpty {
                    Label("Acts with tools: " + file.tools.map { tool in
                        ToolGroup(rawValue: tool)?.title ?? tool.replacingOccurrences(of: "mcp:", with: "server ")
                    }.joined(separator: ", "), systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.pink)
                }
                ForEach(file.questions) { question in
                    Text("Asks “\(question.question)”" + (question.options.isEmpty ? " (typed answer)" : ": " + question.options.joined(separator: " · ")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }

        private func details(_ file: PromptFile) -> String {
            var parts = [(file.output ?? .replace).title]
            if case .choice(let model) = ModelChoice.parse(model: file.model, effort: file.effort) { parts.append(model.label) }
            if file.includeProfile { parts.append("Includes About You") }
            if !file.questions.isEmpty { parts.append(file.questions.count == 1 ? "1 question" : "\(file.questions.count) questions") }
            return parts.joined(separator: " · ")
        }
    }
}

/// Add Tool's menu items call this with the tool's id.
@MainActor
private final class ToolMenuTarget: NSObject {
    let picked: (String) -> Void

    init(_ picked: @escaping (String) -> Void) {
        self.picked = picked
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        picked(id)
    }
}
