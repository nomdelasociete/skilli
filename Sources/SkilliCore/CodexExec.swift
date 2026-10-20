import Foundation

/// `codex exec` as skil.li runs it for ChatGPT: one prompt on stdin, the
/// answer read from its JSON events. Measured with codex-cli 0.162.1:
/// docs/ai-engines.md.
public enum CodexExec {
    /// Features turned off: no tools, apps, plugins, browsers or agents in
    /// the context. ~11k input tokens become ~4.4k.
    public static let leanFeatures = [
        "apps", "browser_use", "browser_use_external", "browser_use_full_cdp_access", "browser_annotation_api",
        "computer_use", "goals", "image_generation", "multi_agent", "plugins", "remote_plugin", "shell_tool",
        "skill_search", "sleep_tool", "tool_suggest", "unified_exec", "view_image", "hooks", "in_app_browser",
        "realtime_conversation"
    ]

    /// The command line after the binary. Read-only sandbox, nothing
    /// approved, no web search, no session kept, the user's config.toml left
    /// out (its MCP servers, its model), skil.li's instructions in place of
    /// Codex's own, `directory` (empty) as the working root, the prompt on
    /// stdin. Features go off as config overrides: Codex ignores a name it
    /// does not know there, where `--disable` would stop it.
    public static func arguments(model: String, effort: ReasoningEffort?, instructions: String, directory: String) -> [String] {
        var arguments = [
            "exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
            "-s", "read-only",
            "-c", "approval_policy=\"never\"",
            "-c", "web_search=\"disabled\"",
            "-c", "model_instructions_file=" + tomlString(instructions),
            "-c", "include_permissions_instructions=false",
            "-c", "include_apps_instructions=false",
            "-c", "include_collaboration_mode_instructions=false",
            "-c", "include_environment_context=false",
            "-c", "project_doc_max_bytes=0",
            "-c", "skills.include_instructions=false"
        ]
        for feature in leanFeatures {
            arguments += ["-c", "features.\(feature)=false"]
        }
        arguments += ["-m", model]
        if let effort { arguments += ["-c", "model_reasoning_effort=\"\(effort.rawValue)\""] }
        arguments += ["-C", directory, "-"]
        return arguments
    }

    /// A TOML basic string.
    static func tomlString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// One line of `codex exec --json`.
    public enum Event: Equatable, Sendable {
        /// An agent message so far (Codex sends it whole, at the end).
        case text(id: String, text: String)
        case completed
        /// The turn failed: the reason as Codex says it.
        case failed(String)
        /// "Reconnecting... 2/5 (…)": Codex tries again on its own.
        case retrying(String)
        /// An error that may still be followed by the turn's end.
        case error(String)
        case other
    }

    public static func event(_ line: String) -> Event {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return .other }
        switch json["type"] as? String {
        case "item.updated", "item.completed":
            guard let item = json["item"] as? [String: Any], item["type"] as? String == "agent_message",
                  let text = item["text"] as? String
            else { return .other }
            return .text(id: item["id"] as? String ?? "", text: text)
        case "turn.completed":
            return .completed
        case "turn.failed":
            return .failed((json["error"] as? [String: Any])?["message"] as? String ?? "")
        case "error":
            let message = json["message"] as? String ?? ""
            return message.hasPrefix("Reconnecting") ? .retrying(message) : .error(message)
        default:
            return .other
        }
    }

    public enum Login: Equatable, Sendable {
        case chatGPT
        /// Codex was signed in with an OpenAI key: billed per use.
        case apiKey
        case signedOut
    }

    /// `codex login status` (it prints on standard error): "Logged in using
    /// ChatGPT", "Logged in using an API key - sk-…", "Not logged in".
    public static func login(_ output: String, status: Int32) -> Login {
        let text = output.lowercased()
        guard status == 0, text.contains("logged in using") else { return .signedOut }
        return text.contains("chatgpt") ? .chatGPT : .apiKey
    }
}

/// What went wrong with ChatGPT or the OpenAI API, in the user's words
/// rather than a status code.
public enum WritingFailure {
    /// From what Codex said (an event or its last line of errors).
    public static func codex(_ raw: String) -> String {
        let text = raw.lowercased()
        // Not a bare "401": request ids and cf-ray hex may hold one.
        if text.contains("unauthorized") || text.contains("not logged in") || text.contains("token expired")
            || text.contains("refresh token") {
            return "ChatGPT is signed out of Codex: run codex login in a terminal, then try again."
        }
        if text.contains("usage limit") || text.contains("too many requests") || text.contains("rate limit") || text.contains("quota") {
            return "Your ChatGPT plan’s limit is reached for now: try again later, or pick another model."
        }
        if text.contains("model") && (text.contains("not supported") || text.contains("does not exist") || text.contains("not found")) {
            let model = quotedModel(raw).map { "“\($0)”" } ?? "this model"
            return "ChatGPT does not offer \(model) on your plan: pick another model."
        }
        if text.contains("unknown feature") || text.contains("unexpected argument") || text.contains("unrecognized") {
            return "This Codex is too old or too new for skil.li: update Codex, then try again."
        }
        if text.contains("error sending request") || text.contains("dns") || text.contains("connection") || text.contains("network")
            || text.contains("timed out") || text.contains("stream disconnected") {
            return "ChatGPT could not be reached: check the connection, then try again."
        }
        return "ChatGPT failed: " + shortened(message(in: raw) ?? raw)
    }

    /// From the API's status and JSON error body.
    public static func openAI(status: Int, body: String) -> String {
        let message = message(in: body) ?? ""
        let lowered = (body + message).lowercased()
        switch status {
        case 401:
            return "OpenAI refused the key: check it in Settings → SI Accounts."
        case 429 where lowered.contains("insufficient_quota") || lowered.contains("billing"):
            return "Your OpenAI account is out of credit: add some at platform.openai.com."
        case 429:
            return "OpenAI is busy for this key (rate limit): try again in a moment."
        case 404:
            let model = quotedModel(message).map { "“\($0)”" } ?? "this model"
            return "OpenAI does not offer \(model) to this key: pick another model."
        case 400 where lowered.contains("model"):
            return "OpenAI refused this model: " + shortened(message.isEmpty ? body : message)
        case 500...599:
            return "OpenAI had a problem (\(status)): try again in a moment."
        default:
            return "OpenAI failed (\(status))" + (message.isEmpty ? "." : ": " + shortened(message))
        }
    }

    /// The `message` of a JSON error, however deep (Codex nests the API's
    /// body as a string in its own).
    static func message(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let json = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) else { return nil }
        func find(_ value: Any) -> String? {
            if let dictionary = value as? [String: Any] {
                if let error = dictionary["error"], let found = find(error) { return found }
                if let message = dictionary["message"] as? String {
                    return find(message) ?? message
                }
            } else if let string = value as? String, string.hasPrefix("{") {
                return WritingFailure.message(in: string)
            }
            return nil
        }
        return find(json)
    }

    /// "The 'gpt-x' model is not supported…" → gpt-x.
    static func quotedModel(_ text: String) -> String? {
        for quote in ["'", "`", "\u{201C}"] {
            let parts = text.components(separatedBy: quote)
            if parts.count >= 3 {
                let candidate = parts[1].replacingOccurrences(of: "\u{201D}", with: "")
                if ModelChoice.isModelID(candidate) { return candidate }
            }
        }
        return nil
    }

    static func shortened(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 160 ? String(trimmed.prefix(157)) + "…" : trimmed
    }
}
