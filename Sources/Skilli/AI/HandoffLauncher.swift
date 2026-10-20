import AppKit
import SkilliCore

/// "Continue in Claude Code / Codex": a terminal opens on a new session of
/// the user's own CLI that already has the conversation (see `Handoff`).
/// The conversation and the script go in a private folder and delete
/// themselves when the session starts.
@MainActor
final class HandoffLauncher {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The `claude` skil.li already uses.
    var claudeBinary: () -> URL? = { nil }
    /// The self-test records what would open instead of opening a terminal.
    var opened: ((Handoff.Target, String) -> Void)?
    /// The self-test records which AI a rights session would open, and on
    /// which server, instead of opening a terminal.
    var openedRights: ((Handoff.Target, String?) -> Void)?

    /// Where Codex is usually installed; read off the main actor too
    /// (`CodexCLI.locate`).
    nonisolated static let codexPaths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex",
                                         "/Applications/Codex.app/Contents/Resources/codex"]

    func binary(for target: Handoff.Target) -> URL? {
        switch target {
        case .claude: claudeBinary()
        case .codex: Self.codexPaths.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
        }
    }

    /// The CLIs found on this Mac, Claude Code first.
    var targets: [Handoff.Target] { Handoff.Target.allCases.filter { binary(for: $0) != nil } }

    /// Terminal, and Ghostty when it is installed.
    static var terminals: [Handoff.Terminal] {
        Handoff.Terminal.allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// Opens `terminal` on a new `target` session that has `conversation`.
    func launch(_ target: Handoff.Target, in terminal: Handoff.Terminal, conversation: String, binaryOverride: URL? = nil) throws {
        if let opened, binaryOverride == nil {
            opened(target, conversation)
            return
        }
        guard let binary = binaryOverride ?? binary(for: target) else { throw Failure(message: "\(target.title) is not installed.") }
        try open(terminal, context: conversation) { file in
            Handoff.script(target: target, binary: binary.path, conversationFile: file, directory: NSHomeDirectory())
        }
        Log.trace("Conversation continued in \(target.title), \(terminal.title)")
    }

    /// Opens `terminal` on a `target` session with skil.li's rights tools
    /// and the skill that helps set them (Settings → Tools). `server`:
    /// the one to start with, nil for all. `socket`: the self-test's server.
    func launchRights(_ target: Handoff.Target, in terminal: Handoff.Terminal, server: String?, binaryOverride: URL? = nil,
                      socket: String? = nil) throws {
        if let openedRights, binaryOverride == nil {
            openedRights(target, server)
            return
        }
        guard let binary = binaryOverride ?? binary(for: target) else { throw Failure(message: "\(target.title) is not installed.") }
        guard let skilli = Bundle.main.executablePath else { throw Failure(message: "skil.li cannot find itself.") }
        let request = ToolRights.request(server: server)
        let context = Handoff.skillContext(ToolRights.skill(language: Self.languageName), request: request, for: target)
        try open(terminal, context: context) { file in
            Handoff.skillScript(target: target, binary: binary.path, skilli: skilli, socket: socket,
                                tools: ToolRightsTools.definitions.map(\.name), contextFile: file, request: request, directory: NSHomeDirectory())
        }
        Log.trace("Tool rights with \(target.title), \(terminal.title), server \(server ?? "all")")
    }

    /// The Mac's language, in English: what the skill asks the AI to speak.
    static var languageName: String {
        let code = Locale(identifier: Locale.preferredLanguages.first ?? "en").language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    /// Writes `context` and the script `makeScript` gives for it in a
    /// private folder (both delete themselves when the session starts) and
    /// opens the script in `terminal`.
    private func open(_ terminal: Handoff.Terminal, context: String, makeScript: (String) -> String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-handoff", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = UUID().uuidString
        let file = folder.appendingPathComponent("\(id).md")
        let script = folder.appendingPathComponent("\(id).command")
        try context.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try makeScript(file.path).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        switch terminal {
        case .terminal:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else {
                throw Failure(message: "Terminal is not installed.")
            }
            NSWorkspace.shared.open([script], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        case .ghostty:
            // Ghostty takes its command after -e, in a new instance.
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-na", "Ghostty.app", "--args", "-e", script.path]
            try open.run()
        }
    }

    /// The CLI chosen in Settings, else the other one found; nil without one.
    func preferred(_ choice: Handoff.Target) -> Handoff.Target? {
        let found = targets
        return found.contains(choice) ? choice : found.first
    }
}
