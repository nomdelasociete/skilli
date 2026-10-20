import Foundation

/// MCP servers the user already set up in another app, to bring into
/// skil.li in one go: Claude Code (`~/.claude.json`, user and project
/// servers), Claude for Mac, Cursor (the same JSON shape) and Codex
/// (`~/.codex/config.toml`). Only the servers are read; a token found in a
/// header goes to skil.li's Keychain, and a server that signs in with OAuth
/// is signed in again in skil.li (other apps' sign-ins are never read).
public enum MCPImport {
    public enum Source: String, CaseIterable, Sendable {
        case claudeCode, claudeDesktop, codex, cursor

        public var title: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .claudeDesktop: "Claude for Mac"
            case .codex: "Codex"
            case .cursor: "Cursor"
            }
        }
    }

    /// One server found in another app.
    public struct Candidate: Equatable, Sendable {
        public let source: Source
        /// A Claude Code project's folder, for its project servers.
        public let project: String?
        public let name: String
        public var command: String?
        public var args: [String] = []
        public var env: [String: String] = [:]
        public var url: String?
        /// From an Authorization header (as is, "Bearer …" included) or the
        /// one other header that carries a token.
        public var token: String?
        /// That other header's name; nil for Authorization.
        public var header: String?
        /// Codex's `bearer_token_env_var`: the token is in that variable.
        public var tokenVariable: String?
        /// Why it cannot come over as is; nil when it can.
        public var problem: String?
        /// The same server elsewhere: "Cursor", "Claude Code · app".
        public var alsoIn: [String] = []

        /// "Claude Code", or "Claude Code · app" for a project's server.
        public var place: String {
            project.map { "\(source.title) · \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? source.title
        }

        /// The same server whatever its name: its address, or its command.
        var identity: String {
            url.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                ?? ([command ?? ""] + args).joined(separator: "\u{0}")
        }

        public init(source: Source, project: String? = nil, name: String) {
            self.source = source
            self.project = project
            self.name = name
        }

        /// What the import sheet shows under the name.
        public var summary: String {
            if let url { return url }
            return ([command ?? ""] + args).joined(separator: " ")
        }
    }

    // MARK: - JSON (Claude Code, Claude for Mac, Cursor)

    /// `{"mcpServers": {…}}`, and for `~/.claude.json` each project's own
    /// `projects[path].mcpServers`.
    public static func json(_ data: Data, source: Source) -> [Candidate] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var found = servers(root["mcpServers"], source: source, project: nil)
        if let projects = root["projects"] as? [String: Any] {
            for path in projects.keys.sorted() {
                let project = projects[path] as? [String: Any]
                found += servers(project?["mcpServers"], source: source, project: path)
            }
        }
        return found
    }

    private static func servers(_ value: Any?, source: Source, project: String?) -> [Candidate] {
        guard let servers = value as? [String: Any] else { return [] }
        return servers.keys.sorted().compactMap { name in
            guard let entry = servers[name] as? [String: Any] else { return nil }
            var candidate = Candidate(source: source, project: project, name: name)
            let type = (entry["type"] as? String)?.lowercased()
            candidate.command = entry["command"] as? String
            candidate.args = entry["args"] as? [String] ?? []
            candidate.env = (entry["env"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            candidate.url = entry["url"] as? String ?? entry["serverUrl"] as? String
            readHeaders((entry["headers"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }, into: &candidate)
            if type == "sse" || candidate.url?.hasSuffix("/sse") == true && type != "http" {
                candidate.problem = "Uses the older SSE transport, which skil.li does not speak yet."
            }
            check(&candidate)
            return candidate
        }
    }

    // MARK: - TOML (Codex)

    /// `[mcp_servers.<name>]` tables of Codex's `config.toml`.
    public static func codex(_ text: String) -> [Candidate] {
        let tables = TOML.tables(text)
        var names: [String] = []
        for key in tables.keys where key.count >= 2 && key[0] == "mcp_servers" && !names.contains(key[1]) {
            names.append(key[1])
        }
        return names.sorted().map { name in
            let table = tables[["mcp_servers", name]] ?? [:]
            var candidate = Candidate(source: .codex, name: name)
            candidate.command = table["command"]?.string
            candidate.args = table["args"]?.strings ?? []
            candidate.env = table["env"]?.table ?? tables[["mcp_servers", name, "env"]]?.compactMapValues(\.string) ?? [:]
            candidate.url = table["url"]?.string
            candidate.tokenVariable = table["bearer_token_env_var"]?.string
            let headers = table["http_headers"]?.table ?? tables[["mcp_servers", name, "http_headers"]]?.compactMapValues(\.string) ?? [:]
            readHeaders(headers, into: &candidate)
            if case .bool(false)? = table["enabled"] {
                candidate.problem = "Turned off in Codex."
            }
            check(&candidate)
            return candidate
        }
    }

    // MARK: - Shared

    /// Authorization (or a single header that looks like a key) becomes the
    /// token; other headers are not carried over.
    private static func readHeaders(_ headers: [String: String], into candidate: inout Candidate) {
        if let (_, value) = headers.first(where: { $0.key.lowercased() == "authorization" }) {
            candidate.token = value
        } else if let (name, value) = headers.first(where: { ["key", "token", "auth"].contains(where: $0.key.lowercased().contains) }) {
            candidate.token = value
            candidate.header = name
        }
    }

    private static func check(_ candidate: inout Candidate) {
        guard candidate.problem == nil else { return }
        if candidate.url == nil && (candidate.command ?? "").isEmpty {
            candidate.problem = "Has neither a command nor an address."
        } else if let url = candidate.url, !(url.hasPrefix("https://") || url.hasPrefix("http://localhost") || url.hasPrefix("http://127.0.0.1")) {
            candidate.problem = "Its address is not https."
        } else if candidate.token?.contains("${") == true {
            candidate.problem = "Its token comes from an environment variable: add it by hand with Edit."
        }
    }

    /// One per server: the same address or command found in several apps
    /// or projects is kept once (the one with a token, else the first),
    /// with the other places in `alsoIn`.
    public static func merged(_ candidates: [Candidate]) -> [Candidate] {
        var kept: [Candidate] = []
        for candidate in candidates {
            guard let index = kept.firstIndex(where: { $0.identity == candidate.identity }) else {
                kept.append(candidate)
                continue
            }
            if kept[index].token == nil, candidate.token != nil {
                var replacement = candidate
                replacement.alsoIn = [kept[index].place] + kept[index].alsoIn
                kept[index] = replacement
            } else if !kept[index].alsoIn.contains(candidate.place), kept[index].place != candidate.place {
                kept[index].alsoIn.append(candidate.place)
            }
        }
        return kept
    }

    /// skil.li itself, set up in the other app: not imported.
    public static func isSkilli(_ candidate: Candidate) -> Bool {
        candidate.name.lowercased() == "skilli"
            || (candidate.command?.hasSuffix("/Skilli") == true && candidate.args.first == "mcp")
    }
}

/// The part of TOML Codex's settings use: `[a.b."c d"]` tables, strings
/// (basic and literal), booleans, numbers, arrays of strings (on several
/// lines too) and inline tables of strings.
enum TOML {
    enum Value: Equatable {
        case string(String)
        case bool(Bool)
        case number(Double)
        case strings([String])
        case table([String: String])
        case other

        var string: String? { if case .string(let value) = self { value } else { nil } }
        var strings: [String]? { if case .strings(let value) = self { value } else { nil } }
        var table: [String: String]? { if case .table(let value) = self { value } else { nil } }
    }

    /// Every table's keys and values, by the table's dotted path.
    static func tables(_ text: String) -> [[String]: [String: Value]] {
        var tables: [[String]: [String: Value]] = [[]: [:]]
        var current: [String] = []
        var pending = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = pending.isEmpty ? stripComment(raw).trimmingCharacters(in: .whitespaces) : pending + " " + stripComment(raw).trimmingCharacters(in: .whitespaces)
            pending = ""
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") && !line.hasPrefix("[[") && line.hasSuffix("]") {
                current = keyPath(String(line.dropFirst().dropLast()))
                if tables[current] == nil { tables[current] = [:] }
                continue
            }
            guard let equals = topLevelEquals(line) else { continue }
            let key = keyPath(String(line[..<equals]))
            let rawValue = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            // An array or inline table that goes on to the next lines.
            if depth(rawValue) > 0 {
                pending = line
                continue
            }
            guard let last = key.last else { continue }
            let table = current + key.dropLast()
            tables[table, default: [:]][last] = value(rawValue)
        }
        return tables
    }

    /// `a."b.c".d` → ["a", "b.c", "d"].
    static func keyPath(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text.trimmingCharacters(in: .whitespaces) {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "." {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    static func value(_ text: String) -> Value {
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            return strings(in: text).first.map(Value.string) ?? .other
        }
        if text == "true" || text == "false" { return .bool(text == "true") }
        if let number = Double(text.replacingOccurrences(of: "_", with: "")) { return .number(number) }
        if text.hasPrefix("[") { return .strings(strings(in: text)) }
        if text.hasPrefix("{") {
            var table: [String: String] = [:]
            for pair in splitTopLevel(String(text.dropFirst().dropLast())) {
                guard let equals = topLevelEquals(pair) else { continue }
                let key = keyPath(String(pair[..<equals])).joined(separator: ".")
                if let string = value(String(pair[pair.index(after: equals)...]).trimmingCharacters(in: .whitespaces)).string {
                    table[key] = string
                }
            }
            return .table(table)
        }
        return .other
    }

    /// Every quoted string in `text`, escapes read in basic strings.
    private static func strings(in text: String) -> [String] {
        var found: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if let open = quote {
                if open == "\"" && escaped {
                    switch character {
                    case "n": current.append("\n")
                    case "t": current.append("\t")
                    default: current.append(character)
                    }
                    escaped = false
                } else if open == "\"" && character == "\\" {
                    escaped = true
                } else if character == open {
                    found.append(current)
                    current = ""
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
            }
        }
        return found
    }

    /// The line without its `# comment` (a # inside quotes stays).
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(line[..<index])
            }
        }
        return line
    }

    /// The first `=` outside quotes.
    private static func topLevelEquals(_ text: String) -> String.Index? {
        var quote: Character?
        for index in text.indices {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "=" {
                return index
            }
        }
        return nil
    }

    /// Open brackets and braces outside quotes, minus closed ones.
    private static func depth(_ text: String) -> Int {
        var depth = 0
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" || character == "{" {
                depth += 1
            } else if character == "]" || character == "}" {
                depth -= 1
            }
        }
        return depth
    }

    /// `a = "x", b = "y, z"` → the two pairs.
    private static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
                current.append(character)
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(current) }
        return parts
    }
}
