import Foundation

/// A tool another MCP server offers, as its `tools/list` describes it: its
/// hints say whether it only reads or may destroy something.
public struct MCPToolInfo: Codable, Equatable, Sendable {
    public let name: String
    public let title: String?
    public let description: String
    /// `annotations.readOnlyHint`: changes nothing.
    public let readOnly: Bool?
    /// `annotations.destructiveHint`: may delete or overwrite.
    public let destructive: Bool?

    public init(name: String, title: String? = nil, description: String = "", readOnly: Bool? = nil, destructive: Bool? = nil) {
        self.name = name
        self.title = title
        self.description = description
        self.readOnly = readOnly
        self.destructive = destructive
    }

    /// Read-only ones ask like reading (in "Ask Before Changes" they run);
    /// everything else asks like a change.
    public var risk: ToolRisk { readOnly == true ? .read : .changes }

    public enum Kind: String, CaseIterable, Sendable {
        case reads, changes, destroys
        /// The server gave no hints.
        case unknown
    }

    /// As the MCP spec reads the hints: not read-only and not said to be
    /// harmless means it may destroy.
    public var kind: Kind {
        if readOnly == true { return .reads }
        if readOnly == nil && destructive == nil { return .unknown }
        return destructive == false ? .changes : .destroys
    }

    /// Claude Code's name for it: `mcp__server__tool`.
    public static func fullName(server: String, tool: String) -> String {
        "mcp__\(server)__\(tool)"
    }
}

/// The MCP wire bits skil.li needs to read a server's tools.
public enum MCPToolList {
    /// One `tools/list` page: its tools and the cursor of the next page.
    public static func page(_ result: [String: Any]) -> (tools: [MCPToolInfo], next: String?) {
        let tools = (result["tools"] as? [[String: Any]] ?? []).compactMap { tool -> MCPToolInfo? in
            guard let name = tool["name"] as? String, !name.isEmpty else { return nil }
            let annotations = tool["annotations"] as? [String: Any] ?? [:]
            let title = (tool["title"] as? String) ?? (annotations["title"] as? String)
            return MCPToolInfo(name: name, title: title, description: (tool["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                               readOnly: annotations["readOnlyHint"] as? Bool, destructive: annotations["destructiveHint"] as? Bool)
        }
        let next = (result["nextCursor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (tools, next)
    }

    /// A Streamable HTTP answer: plain JSON, or Server-Sent Events whose
    /// `data:` lines carry the messages. Every JSON-RPC message in it.
    public static func messages(_ body: Data, contentType: String) -> [[String: Any]] {
        if !contentType.lowercased().contains("text/event-stream") {
            let object = try? JSONSerialization.jsonObject(with: body)
            return (object as? [[String: Any]]) ?? [(object as? [String: Any])].compactMap { $0 }
        }
        var messages: [[String: Any]] = []
        var data = ""
        func flush() {
            if !data.isEmpty, let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] { messages.append(object) }
            data = ""
        }
        for line in String(decoding: body, as: UTF8.self).components(separatedBy: "\n") {
            let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("data:") {
                data += (data.isEmpty ? "" : "\n") + line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return messages
    }

    /// "12 tools · 8 read · 3 change · 1 can destroy · 2 without hints".
    public static func summary(_ tools: [MCPToolInfo]) -> String {
        let counts = Dictionary(grouping: tools, by: \.kind).mapValues(\.count)
        var parts = ["\(tools.count) tool\(tools.count == 1 ? "" : "s")"]
        if let reads = counts[.reads] { parts.append("\(reads) read") }
        if let changes = counts[.changes] { parts.append("\(changes) change") }
        if let destroys = counts[.destroys] { parts.append("\(destroys) can destroy") }
        if let unknown = counts[.unknown] { parts.append("\(unknown) without hints") }
        return parts.joined(separator: " · ")
    }
}
