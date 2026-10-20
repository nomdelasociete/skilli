import Foundation

/// A conversation started in skil.li that goes on in the user's own AI, in
/// a terminal: Claude Code gets it as context and waits for the next
/// message; Codex gets it as its first message (it has no documented way to
/// take context without answering).
public enum Handoff {
    public enum Target: String, CaseIterable, Sendable {
        case claude, codex

        public var title: String { self == .claude ? "Claude Code" : "Codex" }
    }

    public enum Terminal: String, CaseIterable, Sendable {
        case terminal, ghostty

        public var title: String { self == .terminal ? "Terminal" : "Ghostty" }
        public var bundleID: String { self == .terminal ? "com.apple.Terminal" : "com.mitchellh.ghostty" }
    }

    /// What the new session is told: where the conversation comes from, the
    /// request (its selection quoted, as sent), what was done, the answer.
    /// `earlier`: the turns before this one, when the user followed up in
    /// the card.
    public static func conversation(request: String, answer: String, steps: [String] = [], earlier: [CardConversation.Turn] = [],
                                    for target: Target) -> String {
        var text = "The user started this conversation in skil.li, their Mac launcher, and goes on with it here, with you. What was said so far:\n\n"
        text += CardConversation.transcript(earlier)
        // A command line takes about 1 MB: a long selection is cut.
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        text += "User:\n\(request.count > 60_000 ? String(request.prefix(60_000)) + "\n[…cut]" : request)\n\n"
        if !steps.isEmpty {
            text += "What you did on their Mac:\n" + steps.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        text += "You answered:\n\(answer.count > 30_000 ? String(answer.prefix(30_000)) + "\n[…cut]" : answer)\n\n"
        switch target {
        case .claude:
            text += "Go on from there when they write, in their language."
        case .codex:
            text += "Say in one short line, in their language, that you have this conversation and are ready for what's next; then wait for their message."
        }
        return text
    }

    /// The script the terminal runs: it reads the conversation, deletes it
    /// and itself, then becomes the CLI in `directory`. Nothing stays on disk.
    public static func script(target: Target, binary: String, conversationFile: String, directory: String) -> String {
        script(binary: binary, arguments: [], contextFile: conversationFile, asSystemPrompt: target == .claude, message: nil, directory: directory)
    }

    /// A session with skil.li's tools and a skill: skil.li's MCP server is
    /// given on the command line (the CLI's own settings are not touched).
    /// Claude Code gets only skil.li (`--strict-mcp-config`), `tools`
    /// allowed up front (skil.li asks in its card itself), the skill as its
    /// system prompt and `request` as the first message; Codex gets the
    /// server as `-c` overrides with only `tools`, run without its own
    /// prompt (skil.li's card is the one) and time to answer that card, and
    /// the skill then the request as its first message. `skilli`: the app's
    /// executable (`Skilli mcp`).
    public static func skillScript(target: Target, binary: String, skilli: String, socket: String? = nil, tools: [String],
                                   contextFile: String, request: String, directory: String) -> String {
        let bridge = ["mcp"] + (socket.map { ["--socket", $0] } ?? [])
        switch target {
        case .claude:
            let config = ["mcpServers": ["skilli": ["command": skilli, "args": bridge]]]
            let json = (try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            let arguments = ["--strict-mcp-config", "--mcp-config", json, "--allowedTools", tools.map { "mcp__skilli__\($0)" }.joined(separator: ",")]
            return script(binary: binary, arguments: arguments, contextFile: contextFile, asSystemPrompt: true, message: request, directory: directory)
        case .codex:
            let only = tools.isEmpty ? [] : ["-c", "mcp_servers.skilli.enabled_tools=[" + tools.map(tomlString).joined(separator: ",") + "]"]
            let arguments = ["-c", "mcp_servers.skilli.command=" + tomlString(skilli),
                             "-c", "mcp_servers.skilli.args=[" + bridge.map(tomlString).joined(separator: ",") + "]"] + only
                + ["-c", #"mcp_servers.skilli.default_tools_approval_mode="approve""#,
                   "-c", "mcp_servers.skilli.tool_timeout_sec=\(cardWait)"]
            return script(binary: binary, arguments: arguments, contextFile: contextFile, asSystemPrompt: false, message: nil, directory: directory)
        }
    }

    /// How long Codex waits for a tool (seconds): long enough for the user
    /// to answer skil.li's card.
    static let cardWait = 600

    /// What the context file holds for `skillScript`: the skill alone
    /// (Claude Code), or the skill then the request (Codex).
    public static func skillContext(_ skill: String, request: String, for target: Target) -> String {
        target == .claude ? skill : skill + "\n\nThe user asks: " + request
    }

    static func script(binary: String, arguments: [String], contextFile: String, asSystemPrompt: Bool, message: String?, directory: String) -> String {
        var call = ([binary] + arguments).map(quoted).joined(separator: " ")
        call += asSystemPrompt ? " --append-system-prompt \"$context\"" : " \"$context\""
        if let message { call += " " + quoted(message) }
        return """
            #!/bin/zsh
            cd \(quoted(directory)) 2>/dev/null || cd ~
            context=$(cat \(quoted(contextFile)))
            rm -f \(quoted(contextFile)) "$0"
            exec \(call)

            """
    }

    /// A TOML basic string, for Codex's `-c key=value`.
    static func tomlString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// For the self-test's stand-in CLI.
    public static func quotedForTest(_ text: String) -> String { quoted(text) }

    /// `it's here` → `'it'\''s here'`: one shell word, nothing expanded.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
