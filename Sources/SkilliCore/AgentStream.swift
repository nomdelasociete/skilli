import Foundation

/// What Claude Code's `--output-format stream-json` says while an agent
/// works, reduced to what the card shows.
public enum AgentEvent: Equatable, Sendable {
    /// Text being written (with `--include-partial-messages`).
    case text(String)
    /// The agent calls a tool; `input` is its JSON arguments.
    case toolUse(id: String, name: String, input: String)
    /// A tool answered.
    case toolResult(id: String, isError: Bool)
    /// The turn is over: the final reply, or the reason it failed.
    case finished(result: String, isError: Bool, costUSD: Double?)
}

public enum AgentStream {
    /// Events in one line of output; nothing for lines that do not matter.
    public static func events(in line: String) -> [AgentEvent] {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return [] }
        switch event["type"] as? String {
        case "stream_event":
            let streamEvent = event["event"] as? [String: Any]
            guard streamEvent?["type"] as? String == "content_block_delta",
                  let delta = streamEvent?["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return [] }
            return [.text(text)]
        case "assistant":
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap { block in
                guard block["type"] as? String == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
                let input = (block["input"]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                return .toolUse(id: id, name: name, input: input.map { String(decoding: $0, as: UTF8.self) } ?? "{}")
            }
        case "user":
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap { block in
                guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
                return .toolResult(id: id, isError: block["is_error"] as? Bool ?? false)
            }
        case "result":
            let isError = event["is_error"] as? Bool ?? (event["subtype"] as? String != "success")
            let result = event["result"] as? String ?? (isError ? "Claude Code stopped: \(event["subtype"] as? String ?? "error")." : "")
            return [.finished(result: result, isError: isError, costUSD: event["total_cost_usd"] as? Double)]
        default:
            return []
        }
    }

    /// `mcp__skilli__get_selection` → (server "skilli", tool "get_selection").
    public static func split(toolName: String) -> (server: String?, tool: String) {
        let parts = toolName.components(separatedBy: "__")
        guard parts.count >= 3, parts[0] == "mcp" else { return (nil, toolName) }
        return (parts[1], parts[2...].joined(separator: "__"))
    }
}
