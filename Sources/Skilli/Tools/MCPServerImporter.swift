import Foundation
import SkilliCore

/// Settings → Tools → Import From Other Apps: the MCP servers set up in
/// Claude Code, Claude for Mac, Codex and Cursor (see `MCPImport`), added
/// to skil.li when the user picks them.
enum MCPServerImporter {
    struct Location: Sendable {
        let source: MCPImport.Source
        let file: URL
    }

    /// Where each app keeps its servers.
    static var defaultLocations: [Location] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex", isDirectory: true)
        return [
            Location(source: .claudeCode, file: home.appendingPathComponent(".claude.json")),
            Location(source: .claudeDesktop, file: home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")),
            Location(source: .codex, file: codex.appendingPathComponent("config.toml")),
            Location(source: .cursor, file: home.appendingPathComponent(".cursor/mcp.json"))
        ]
    }

    /// Every server found, once each, skil.li itself left out. Reads only
    /// these files.
    static func find(in locations: [Location]) -> [MCPImport.Candidate] {
        MCPImport.merged(locations.flatMap { location -> [MCPImport.Candidate] in
            guard let data = try? Data(contentsOf: location.file) else { return [] }
            switch location.source {
            case .codex: return MCPImport.codex(String(decoding: data, as: UTF8.self))
            default: return MCPImport.json(data, source: location.source)
            }
        }
        .filter { !MCPImport.isSkilli($0) })
    }

    /// The name it gets in skil.li: its own, or with its app's when that
    /// one is taken.
    @MainActor
    static func name(for candidate: MCPImport.Candidate, taken: Set<String>) -> String {
        let name = MCPServerConfig.normalizedName(candidate.name)
        guard taken.contains(name) || name == "skilli" else { return name }
        let suffix = switch candidate.source {
        case .claudeCode: "claude"
        case .claudeDesktop: "claude-mac"
        case .codex: "codex"
        case .cursor: "cursor"
        }
        var renamed = "\(name)-\(suffix)"
        var number = 2
        while taken.contains(renamed) {
            renamed = "\(name)-\(suffix)-\(number)"
            number += 1
        }
        return renamed
    }

    /// Adds them: a token goes to the Keychain, never to tools.json. Then
    /// lists each one's tools; a web server that answers 401 signs in with
    /// OAuth (Sign In… on its row). Returns the names given.
    @MainActor
    @discardableResult
    static func add(_ candidates: [MCPImport.Candidate], to settings: ToolSettings) async -> [String] {
        var taken = Set(settings.servers.map(\.name))
        var added: [MCPServerConfig] = []
        for candidate in candidates where candidate.problem == nil {
            let name = name(for: candidate, taken: taken)
            taken.insert(name)
            var server = MCPServerConfig(name: name, command: candidate.url == nil ? candidate.command : nil,
                                         args: candidate.url == nil ? candidate.args : [], env: candidate.url == nil ? candidate.env : [:],
                                         url: candidate.url)
            if candidate.url != nil, candidate.token != nil || candidate.tokenVariable != nil {
                server.auth = .token
                server.header = candidate.header
            }
            settings.saveServer(server)
            if let token = candidate.token { settings.auth.setToken(token, for: name) }
            added.append(server)
        }
        Log.actions.notice("Imported \(added.count, privacy: .public) MCP servers")
        for var server in added where server.auth != .token || settings.auth.token(for: server.name) != nil {
            do {
                try await settings.refreshTools(of: server)
            } catch let failure as MCPClient.Failure where failure.needsSignIn && server.url != nil && server.auth == nil {
                server.auth = .oauth
                settings.saveServer(server)
            } catch {
                Log.trace("MCP tools of \(server.name) not listed after import: \(error.localizedDescription)")
            }
        }
        return added.map(\.name)
    }
}
