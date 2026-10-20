import Foundation
import SkilliCore

/// One AI command: what Settings edits and the leader runs.
struct AICommand: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    /// Template with `{variables}` (see `PromptTemplate`).
    var prompt: String
    var includeProfile: Bool
    /// `model:` and `effort:` as the file says them, kept even when this
    /// build cannot run them (a newer skil.li's file).
    private(set) var fileModel: String?
    private(set) var fileEffort: String?
    /// nil: replace the selection, or insert at the cursor without one.
    var output: OutputMode? = nil
    /// Asked in the card before the prompt is sent.
    var questions: [PromptQuestion] = []
    /// Tool groups (`ToolGroup`) and `mcp:<server>`; any makes it an Act
    /// command, run by an agent with those tools.
    var tools: [String] = []

    /// Who writes it; nil: Settings → SI Accounts' default (also when the file
    /// names a model this build does not know, `unknownModel`).
    var model: ModelChoice? {
        get {
            if case .choice(let choice) = ModelChoice.parse(model: fileModel, effort: fileEffort) { return choice }
            return nil
        }
        set {
            fileModel = newValue?.fileModel
            fileEffort = newValue?.fileEffort
        }
    }

    /// What the file names when this build cannot run it ("gemini/x").
    var unknownModel: String? {
        if case .unknown(let text) = ModelChoice.parse(model: fileModel, effort: fileEffort) { return text }
        return nil
    }

    var template: PromptTemplate { PromptTemplate(prompt) }
    var isAct: Bool { !tools.isEmpty }
    /// Ask picks its route from what the user types.
    var isAsk: Bool { id == PromptLibrary.askID }

    /// Without `{selection}` a command also runs with nothing selected; the
    /// selection, when there is one, is added after the prompt.
    var needsSelection: Bool { template.uses(.selection) }

    var file: PromptFile {
        PromptFile(title: title, instruction: prompt, includeProfile: includeProfile, model: fileModel, effort: fileEffort,
                   output: output, questions: questions, tools: tools)
    }

    /// A command read from a file (`id` names it in the library).
    init(id: String, file: PromptFile) {
        self.init(
            id: id,
            title: file.title ?? id.capitalized,
            prompt: file.instruction,
            includeProfile: file.includeProfile,
            model: nil,
            output: file.output,
            questions: file.questions,
            tools: file.tools
        )
        fileModel = file.model
        fileEffort = file.effort
    }

    init(id: String, title: String, prompt: String, includeProfile: Bool, model: ModelChoice?,
         output: OutputMode? = nil, questions: [PromptQuestion] = [], tools: [String] = []) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.includeProfile = includeProfile
        self.output = output
        self.questions = questions
        self.tools = tools
        self.model = model
    }
}

/// AI commands as Markdown files in
/// `~/Library/Application Support/skil.li/prompts/<id>.md`, plus About You
/// in `about-you.md` next to them. Built-ins are written once and can be
/// edited or reset; a file with any other name adds a command. Files are the
/// source of truth: Settings writes them, and they are re-read before each
/// run, so edits in any editor apply at once.
final class PromptLibrary: @unchecked Sendable {
    /// The app's library; the self-test and benchmark install their own
    /// before anything reads it.
    nonisolated(unsafe) static var shared = PromptLibrary(folder: PromptLibrary.defaultFolder)

    /// Ask: type what to do; skil.li answers, rewrites or acts (`AskRouter`).
    static let askID = "ask"

    static let builtIn: [AICommand] = [
        AICommand(id: askID, title: "Ask",
                  prompt: "{ask.instruction}",
                  includeProfile: true, model: nil,
                  questions: [PromptQuestion(id: "instruction", question: "What should I do?")]),
        // Words that sound alike are named: Haiku left "on mangé" for "ont
        // mangé" and rewrote "manger" as "mangent" half the time, and changed
        // correct text ("t'envoie" → "t'enverrai"). 94 % → 95 % on 12
        // sentences × 16 runs, and correct text left alone.
        AICommand(id: "fix", title: "Fix Spelling & Grammar",
                  prompt: "Correct this text: every spelling, grammar, conjugation, agreement and punctuation mistake, including words that sound alike (on/ont, a/à, et/est, ces/ses/c'est, ou/où, -er/-é, its/it's, your/you're, their/there/they're). Change nothing else: keep the words, tone, language, line breaks and formatting. If it is already correct, return it exactly as it is.\n\n{selection}",
                  includeProfile: false, model: nil),
        AICommand(id: "improve", title: "Improve Writing",
                  prompt: "Rewrite this to be clearer and more fluent. Keep the meaning, language and formatting, and sound like me.\n\n{selection}",
                  includeProfile: true, model: nil),
        AICommand(id: "english", title: "Translate to English",
                  prompt: "Translate into natural English. Keep the tone and formatting.\n\n{selection}",
                  includeProfile: false, model: nil),
        AICommand(id: "french", title: "Translate to French",
                  prompt: "Translate into natural French. Keep the tone and formatting.\n\n{selection}",
                  includeProfile: false, model: nil)
    ]

    /// Built-in files as earlier versions wrote them: still untouched, they
    /// are upgraded to the current built-in. The first had no `{selection}`.
    private static let earlierBuiltInTexts: [String: Set<String>] = {
        var texts: [String: Set<String>] = [:]
        let first = [
            "fix": "Fix spelling, grammar and punctuation. Keep the wording, tone, language and formatting.",
            "improve": "Rewrite to be clearer and more fluent. Keep the meaning, tone, language and formatting.",
            "english": "Translate into natural English. Keep the tone and formatting.",
            "french": "Translate into natural French. Keep the tone and formatting."
        ]
        for (id, instruction) in first {
            let title = PromptLibrary.builtIn.first { $0.id == id }?.title
            texts[id, default: []].insert(PromptFile(title: title, instruction: instruction).text)
        }
        // Fix before it named the words that sound alike.
        let fix = AICommand(id: "fix", title: "Fix Spelling & Grammar",
                            prompt: "Fix spelling, grammar, conjugation and punctuation mistakes. Change only what is wrong; keep the tone, language and formatting.\n\n{selection}",
                            includeProfile: false, model: nil)
        texts["fix", default: []].insert(fix.file.text)
        return texts
    }()

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true)
            .appendingPathComponent("prompts", isDirectory: true)
    }

    /// `nil` keeps everything in memory (benchmark).
    let folder: URL?
    private let lock = NSLock()
    private var commands: [AICommand] = PromptLibrary.builtIn
    private var storedProfile = ""

    init(folder: URL?) {
        self.folder = folder
    }

    var all: [AICommand] {
        lock.withLock { commands }
    }

    var profile: String {
        lock.withLock { storedProfile }
    }

    func command(_ id: String) -> AICommand? {
        all.first { $0.id == id }
    }

    /// Title for a shortcut entry, even before the files are read.
    func title(for id: String) -> String {
        command(id)?.title ?? id.capitalized
    }

    /// What a command does, in one line of the Catalog: the built-ins in
    /// the user's words, the others by their prompt's first sentence.
    static func catalogLine(for command: AICommand) -> String {
        switch command.id {
        case "fix": "Fixes spelling and grammar in the selected text"
        case "improve": "Rewrites the selection clearer, in your own voice"
        case "english": "Translates the selection into English"
        case "french": "Translates the selection into French"
        default: FeatureCatalog.firstSentence(ofPrompt: command.prompt)
        }
    }

    static func isBuiltIn(_ id: String) -> Bool {
        builtIn.contains { $0.id == id }
    }

    func isModified(_ id: String) -> Bool {
        guard let original = Self.builtIn.first(where: { $0.id == id }) else { return false }
        return command(id) != original
    }

    // MARK: - Reading

    /// Reads the folder, writing the built-in files the first time. Cheap:
    /// a handful of small files.
    func reload() {
        guard let folder else { return }
        let manager = FileManager.default
        if !manager.fileExists(atPath: folder.path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for command in Self.builtIn { write(command) }
        }
        var loaded = Self.builtIn
        var profile = ""
        let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension == "md" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            if url.lastPathComponent == Self.profileFileName {
                profile = text.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if Self.earlierBuiltInTexts[id]?.contains(text) == true, let current = Self.builtIn.first(where: { $0.id == id }) {
                write(current)
                continue
            }
            let file = PromptFile(parsing: text)
            guard !file.instruction.isEmpty else { continue }
            let command = AICommand(id: id, file: file)
            if let index = loaded.firstIndex(where: { $0.id == id }) {
                loaded[index] = command
            } else {
                loaded.append(command)
            }
        }
        lock.withLock {
            commands = loaded
            storedProfile = profile
        }
    }

    // MARK: - Editing (Settings)

    static let profileFileName = "about-you.md"

    func save(_ command: AICommand) {
        if folder == nil {
            lock.withLock {
                if let index = commands.firstIndex(where: { $0.id == command.id }) {
                    commands[index] = command
                } else {
                    commands.append(command)
                }
            }
            return
        }
        write(command)
        reload()
    }

    /// What a delete took: the command and its file as written, for ⌘Z.
    struct Deleted {
        let command: AICommand
        fileprivate let file: Data?
    }

    /// Deletes it as `delete` does; what `restore` puts back.
    func deleteForUndo(_ id: String) -> Deleted? {
        guard !Self.isBuiltIn(id), let command = command(id) else { return nil }
        let file = folder.flatMap { try? Data(contentsOf: $0.appendingPathComponent("\(id).md")) }
        delete(id)
        return Deleted(command: command, file: file)
    }

    /// Back as it was written, under its own id; one made with that id
    /// meanwhile keeps it, this one gets a free id.
    @discardableResult
    func restore(_ deleted: Deleted) -> AICommand {
        let id = command(deleted.command.id) == nil ? deleted.command.id : newID(for: deleted.command.title)
        if let folder, let file = deleted.file {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? file.write(to: folder.appendingPathComponent("\(id).md"), options: .atomic)
            reload()
            return command(id) ?? deleted.command
        }
        let command = id == deleted.command.id ? deleted.command : AICommand(id: id, file: deleted.command.file)
        save(command)
        return command
    }

    /// Custom commands only; built-ins are reset instead.
    func delete(_ id: String) {
        guard !Self.isBuiltIn(id) else { return }
        if let folder {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id).md"))
            reload()
        } else {
            lock.withLock { commands.removeAll { $0.id == id } }
        }
    }

    /// Adds a command from a file someone shared, under a free id (an
    /// import never replaces a command).
    @discardableResult
    func importCommand(_ file: PromptFile) -> AICommand {
        let command = AICommand(id: newID(for: file.title ?? "Imported Command"), file: file)
        save(command)
        return command
    }

    func reset(_ id: String) {
        guard let original = Self.builtIn.first(where: { $0.id == id }) else { return }
        save(original)
    }

    func saveProfile(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock { storedProfile = text }
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? (text + "\n").write(to: folder.appendingPathComponent(Self.profileFileName), atomically: true, encoding: .utf8)
    }

    /// A file name that is free: "my-command", "my-command-2"…
    func newID(for title: String) -> String {
        let slug = title.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = slug.isEmpty || slug == "about-you" ? "command" : slug
        var id = base
        var number = 2
        while command(id) != nil {
            id = "\(base)-\(number)"
            number += 1
        }
        return id
    }

    private func write(_ command: AICommand) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? command.file.text.write(to: folder.appendingPathComponent("\(command.id).md"), atomically: true, encoding: .utf8)
    }
}
