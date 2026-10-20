import Foundation
import SkilliCore

/// An Act command's agent: the user's own Claude Code, headless, with only
/// MCP tools — skil.li's (through `Skilli mcp`) and the servers the command
/// names. No built-in tools (no shell, no files), no user settings or
/// CLAUDE.md, no session files. skil.li's tools are allowed up front and
/// approved by skil.li itself; other servers' tools go through skil.li's
/// `approve` tool (`--permission-prompt-tool`), so every approval shows in
/// the card.
///
/// The user's skills (Settings → Ask → Skills: SKILL.md folders) reach it
/// as Claude Code's own: a plugin folder made for the run (`--plugin-dir`,
/// one link per skill, removed with the run) and its Skill tool, the only
/// built-in one. Claude Code's bundled skills stay out
/// (`CLAUDE_CODE_DISABLE_BUNDLED_SKILLS`, and `skillOverrides` for the few
/// its built-in plugins bring), and so does every skill of the user's
/// settings (`--setting-sources ""`). Checked with the real CLI (2.1.296,
/// Mac mini): only the plugin's skills listed.
final class AgentRun: @unchecked Sendable {
    private let child = ChildProcess()
    private let input = Pipe()
    private let output = Pipe()
    private let configURL: URL
    /// The run's plugin folder of skills; nil without any.
    private let skillsURL: URL?

    /// Skills that ship inside Claude Code without the bundled ones, turned
    /// off by name.
    static let builtInSkills = ["design", "doctor", "plugin-authoring"]

    private static let basePrompt = """
        You are skil.li's agent on the user's Mac. Carry out the instruction with the tools you have. Text the user \
        gives you (their selection, their clipboard) is between triple quotes. Use ask_user only when you cannot \
        decide on your own. Never claim a tool did something it did not report. To act in an app: one menu item \
        (search_menus, press_menu) for one step; a goal of several steps there (export, fill a form, play a move) whole \
        to do_in_app; for a single press, find_ui or list_ui for an element's id, press_ui or set_ui_value on it, \
        press_keys for a shortcut; read the window again after it changed. When you are done, reply with the \
        result only, or one short sentence saying what you did, in the language of the user's text. No preamble.
        """

    private static let skillsPrompt = """
        The Skill tool holds the user's own skills: how they want some jobs done. When one fits the request, use it \
        first and follow it; its steps that need files or a shell you do not have, skip and say so.
        """

    /// With the date and time, so "tonight" and "tomorrow" mean something.
    static func systemPrompt(skills: Bool = false) -> String {
        let now = DateFormatter.localizedString(from: .now, dateStyle: .full, timeStyle: .short)
        return basePrompt + (skills ? "\n" + skillsPrompt : "") + "\nNow: \(now), time zone \(TimeZone.current.identifier)."
    }

    /// `servers` are the connected servers this command may use.
    /// `skilliTools`: names of skil.li's tools, allowed up front (skil.li
    /// approves them itself).
    /// `headers`: by server name, this run's sign-in (the file is private
    /// and goes when the run does).
    /// `blockedTools`: other servers' tools the user blocked, hidden from
    /// the agent (skil.li's `approve` refuses them too).
    /// `skills`: the user's skills this run may use.
    init(binary: URL, model: AIModel, runID: String, socketPath: String, servers: [MCPServerConfig], skilliTools: [String],
         headers: [String: [String: String]] = [:], blockedTools: [String] = [], skills: [AgentSkill] = []) throws {
        var mcpServers: [String: Any] = [
            MCPService.serverName: [
                "command": Bundle.main.executablePath ?? "",
                "args": ["mcp", "--socket", socketPath, "--run", runID]
            ]
        ]
        for server in servers { mcpServers[server.name] = server.claudeConfig(headers: headers[server.name] ?? [:]) }
        let data = try JSONSerialization.data(withJSONObject: ["mcpServers": mcpServers], options: [.prettyPrinted])
        configURL = ClaudeCLI.scratchDirectory.appendingPathComponent("mcp-\(runID).json")
        // Holds server commands and their environment: the user's only.
        FileManager.default.createFile(atPath: configURL.path, contents: data, attributes: [.posixPermissions: 0o600])

        skillsURL = skills.isEmpty ? nil : try Self.pluginFolder(skills, runID: runID)
        var allowed = skilliTools.map { "mcp__\(MCPService.serverName)__\($0)" }
        let process = child.process
        process.executableURL = binary
        var arguments = [
            "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--no-session-persistence", "--model", model.cliName, "--setting-sources", ""
        ]
        if let skillsURL {
            // The Skill tool alone; slash commands stay on, or skills go too.
            allowed.append("Skill")
            let overrides = Dictionary(uniqueKeysWithValues: Self.builtInSkills.map { ($0, "off") })
            let settings = try JSONSerialization.data(withJSONObject: ["skillOverrides": overrides], options: [.sortedKeys])
            arguments += ["--tools", "Skill", "--plugin-dir", skillsURL.path, "--settings", String(decoding: settings, as: UTF8.self)]
        } else {
            arguments += ["--tools", "", "--disable-slash-commands"]
        }
        arguments += [
            "--strict-mcp-config", "--mcp-config", configURL.path,
            "--allowedTools", allowed.joined(separator: ","),
            "--permission-prompt-tool", "mcp__\(MCPService.serverName)__\(SkilliTools.approve)",
            "--system-prompt", Self.systemPrompt(skills: skillsURL != nil)
        ] + (blockedTools.isEmpty ? [] : ["--disallowedTools", blockedTools.joined(separator: ",")])
        process.arguments = arguments
        var environment = ClaudeCLI.environment(for: binary)
        if skillsURL != nil { environment["CLAUDE_CODE_DISABLE_BUNDLED_SKILLS"] = "1" }
        process.environment = environment
        process.currentDirectoryURL = ClaudeCLI.scratchDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    func terminate() {
        child.terminate()
        try? FileManager.default.removeItem(at: configURL)
        if let skillsURL { try? FileManager.default.removeItem(at: skillsURL) }
    }

    /// A plugin folder for one run: its manifest and a link to each skill's
    /// folder, named as Claude Code takes a skill's name.
    private static func pluginFolder(_ skills: [AgentSkill], runID: String) throws -> URL {
        let manager = FileManager.default
        let root = ClaudeCLI.scratchDirectory.appendingPathComponent("skills-\(runID)", isDirectory: true)
        let folder = root.appendingPathComponent("skills", isDirectory: true)
        try manager.createDirectory(at: root.appendingPathComponent(".claude-plugin", isDirectory: true), withIntermediateDirectories: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = try JSONSerialization.data(withJSONObject: ["name": MCPService.serverName, "description": "Your skills, from skil.li",
                                                                  "version": "1.0.0"])
        try manifest.write(to: root.appendingPathComponent(".claude-plugin/plugin.json"))
        var taken = Set<String>()
        for skill in skills {
            var name = AgentSkill.name(from: skill.name)
            if name.isEmpty { name = AgentSkill.name(from: skill.folder.lastPathComponent) }
            guard !name.isEmpty, taken.insert(name).inserted else { continue }
            try? manager.createSymbolicLink(at: folder.appendingPathComponent(name), withDestinationURL: skill.folder)
        }
        return root
    }

    /// Sends the instruction and streams what the agent does until its
    /// final reply.
    func start(_ message: String, timeout: Duration = .seconds(180)) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            // A request starting with "/" would be read as a slash command.
            let message = message.drop { $0.isWhitespace }.hasPrefix("/") ? "Request: " + message : message
            do {
                try input.fileHandleForWriting.write(contentsOf: Data(message.utf8))
                try input.fileHandleForWriting.close()
            } catch {
                terminate()
                continuation.finish(throwing: AIError.failed("Claude Code stopped before the request."))
                return
            }
            let reader = Task.detached { [self] in
                defer { terminate() }
                do {
                    for try await line in output.fileHandleForReading.bytes.lines {
                        for event in AgentStream.events(in: line) {
                            continuation.yield(event)
                            if case .finished = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish(throwing: AIError.failed("Claude Code stopped without answering."))
                } catch {
                    continuation.finish(throwing: AIError.failed(error.localizedDescription))
                }
            }
            let timer = Task.detached { [self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                continuation.finish(throwing: AIError.timedOut)
                terminate()
            }
            continuation.onTermination = { [self] _ in
                reader.cancel()
                timer.cancel()
                terminate()
            }
        }
    }
}
