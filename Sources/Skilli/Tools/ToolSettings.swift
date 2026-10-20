import Foundation
import Observation
import SkilliCore

/// An MCP server the user connected, for Act commands that name it
/// (`tools: [mcp:<name>]`). Passed to Claude Code as is: a command to run
/// (stdio) or an address (HTTP).
struct MCPServerConfig: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var command: String?
    var args: [String] = []
    var env: [String: String] = [:]
    var url: String?
    /// How a web server knows it is the user: a pasted token, or OAuth.
    var auth: Auth?
    /// The token's header; Authorization (as Bearer) when empty.
    var header: String?

    enum Auth: String, Codable, Sendable {
        case token, oauth
    }

    var id: String { name }

    /// What Settings shows under the name.
    var summary: String {
        if let url { return url }
        return ([command ?? ""] + args).joined(separator: " ")
    }

    /// The entry for Claude Code's `--mcp-config`, with this run's headers.
    func claudeConfig(headers: [String: String] = [:]) -> [String: Any] {
        if let url { return headers.isEmpty ? ["type": "http", "url": url] : ["type": "http", "url": url, "headers": headers] }
        var entry: [String: Any] = ["command": command ?? "", "args": args]
        if !env.isEmpty { entry["env"] = env }
        return entry
    }

    /// Letters, digits, - and _: the name appears in tool names.
    static func normalizedName(_ name: String) -> String {
        PromptQuestion.normalizedID(name)
    }
}

/// A tool the user describes and skil.li calls: a webhook. The model reads
/// `instructions` to know when to use it; skil.li POSTs the text as JSON.
struct CustomTool: Codable, Hashable, Identifiable, Sendable {
    /// The tool's name for agents: lowercase letters, digits, dashes.
    var name: String
    /// When to use it, in the user's words ("Send to my Grok bot on Telegram").
    var instructions: String
    var url: String

    var id: String { name }

    /// https, or plain http to this Mac only.
    static func isAllowed(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), let host = components.host, !host.isEmpty else { return false }
        switch components.scheme?.lowercased() {
        case "https": return true
        case "http": return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        default: return false
        }
    }
}

/// Settings → Tools, saved in `tools.json` next to the commands: how
/// tools are approved, the user's choice per tool, connected servers and
/// the user's own tools (their tokens stay in the Keychain); and the
/// entries `skilli://` links run without asking (`LinkTrust`, listed in
/// Settings → Catalog).
@MainActor
@Observable
final class ToolSettings {
    var mode: ApprovalMode = .auto {
        didSet { save() }
    }

    /// By tool name: skil.li's (`replace_selection`) or another server's as
    /// Claude Code names it (`mcp__linear__create_issue`).
    private(set) var overrides: [String: ToolOverride] = [:]
    private(set) var servers: [MCPServerConfig] = []
    private(set) var customTools: [CustomTool] = []
    /// Each connected server's tools as it last listed them, by server
    /// name: their hints set the defaults, Settings shows them.
    private(set) var serverTools: [String: [MCPToolInfo]] = [:]
    /// The user's rules, in their words (Settings → Ask → Your Rules):
    /// judged before an agent's step (`ApprovalRules`). Written only in the
    /// pane: an agent never widens its own rights.
    private(set) var rules: [ApprovalRule] = []
    /// What links run at once: Always ⌘↩ in a link's card (D6). Changed
    /// only there and in Settings → Catalog, never through tools.
    private(set) var linkTrust = LinkTrust()

    @ObservationIgnored private let fileURL: URL?
    /// No saving while the file is read: in an @Observable class, setting
    /// `mode` in init runs its didSet, which wrote the file before the
    /// servers and choices were read (they were lost on the next launch).
    @ObservationIgnored private var isLoading = true
    /// The self-test keeps its own Keychain items.
    @ObservationIgnored private let keychainPrefix: String
    /// Servers' tokens and sign-ins.
    @ObservationIgnored let auth: MCPAuth

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true)
            .appendingPathComponent("tools.json")
    }

    private struct File: Codable {
        var approval: String?
        var tools: [String: String]?
        var servers: [MCPServerConfig]?
        var custom: [CustomTool]?
        var rules: [ApprovalRule]?
        var trustedLinks: [TrustedLink]?
    }

    /// `nil` keeps everything in memory.
    init(fileURL: URL?, keychainPrefix: String = "") {
        self.fileURL = fileURL
        self.keychainPrefix = keychainPrefix
        auth = MCPAuth(keychainPrefix: keychainPrefix)
        defer { isLoading = false }
        if let url = serverToolsURL, let data = try? Data(contentsOf: url),
           let listed = try? JSONDecoder().decode([String: [MCPToolInfo]].self, from: data) {
            serverTools = listed
        }
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return }
        mode = file.approval.flatMap(ApprovalMode.init(rawValue:)) ?? .auto
        overrides = (file.tools ?? [:]).compactMapValues(ToolOverride.init(rawValue:))
        servers = file.servers ?? []
        customTools = (file.custom ?? []).filter { CustomTool.isAllowed($0.url) }
        rules = file.rules ?? []
        linkTrust = LinkTrust(file.trustedLinks ?? [])
    }

    func override(for tool: String) -> ToolOverride? {
        overrides[tool]
    }

    func setOverride(_ value: ToolOverride?, for tool: String) {
        overrides[tool] = value
        save()
    }

    /// Several choices at once, saved once (nil goes back to the default).
    func setOverrides(_ values: [String: ToolOverride?]) {
        for (tool, value) in values { overrides[tool] = value }
        save()
    }

    func needsApproval(_ tool: String, risk: ToolRisk) -> Bool {
        ToolPolicy.needsApproval(risk: risk, mode: mode, override: overrides[tool], everyTime: Self.asksEveryTime(tool))
    }

    /// Runs, asks, or is refused (blocked).
    func decision(_ tool: String, risk: ToolRisk) -> ToolPolicy.Decision {
        ToolPolicy.decision(risk: risk, mode: mode, override: overrides[tool], everyTime: Self.asksEveryTime(tool))
    }

    // MARK: - Links

    /// Always in a link's card: false (nothing kept) for what is never
    /// trusted (`LinkTrust.neverTrusted`).
    @discardableResult
    func trustLink(_ run: CatalogEntry.Run, entry: String, title: String, arguments: [String] = []) -> Bool {
        guard linkTrust.trust(run, entry: entry, title: title, arguments: arguments) else { return false }
        save()
        return true
    }

    /// Always in a "do it here" link's card: that goal in that app.
    func trustDoLink(goal: String, app: String?, title: String) {
        linkTrust.trustDo(goal: goal, app: app, title: title)
        save()
    }

    /// Settings → Catalog → Trusted Links: its next link asks again.
    func removeTrustedLink(_ link: TrustedLink) {
        linkTrust.remove(link)
        save()
    }

    // MARK: - Rules

    /// Adds a rule (a suggestion, or an empty one to write); returns its id.
    @discardableResult
    func addRule(_ text: String = "", effect: ApprovalRule.Effect = .ask) -> String {
        let rule = ApprovalRule(text: text, effect: effect)
        rules.append(rule)
        save()
        return rule.id
    }

    func updateRule(_ id: String, text: String? = nil, effect: ApprovalRule.Effect? = nil) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        if let text { rules[index].text = text }
        if let effect { rules[index].effect = effect }
        save()
    }

    /// Gone at once; what ⌘Z puts back where it was (`restoreRule`).
    @discardableResult
    func removeRule(_ id: String) -> RemovedElement<ApprovalRule>? {
        let removed = RemovedElement.take(id, from: &rules)
        save()
        return removed
    }

    func restoreRule(_ removed: RemovedElement<ApprovalRule>) {
        guard removed.putBack(into: &rules) else { return }
        save()
    }

    /// Rules left without words (the pane closed while one was empty).
    func removeEmptyRules() {
        guard rules.contains(where: { $0.said.isEmpty }) else { return }
        rules.removeAll { $0.said.isEmpty }
        save()
    }

    /// The self-test's rules, and back to what was there.
    func setRulesForSelfTest(_ rules: [ApprovalRule]) {
        self.rules = rules
        save()
    }

    /// A change to skil.li's own settings: it asks every time, whatever
    /// its right (Block aside) or the mode.
    nonisolated static func asksEveryTime(_ tool: String) -> Bool {
        SettingsTable.Tool.changes.contains(tool)
    }

    // MARK: - Servers' tools

    /// Another server's tool by Claude Code's name (`mcp__linear__list_issues`),
    /// if that server listed it.
    func serverTool(_ fullName: String) -> MCPToolInfo? {
        let (server, tool) = AgentStream.split(toolName: fullName)
        guard let server else { return nil }
        return serverTools[server]?.first { $0.name == tool }
    }

    /// Read-only tools ask like reading; the rest, and tools not listed
    /// yet, like changes.
    func risk(ofServerTool fullName: String) -> ToolRisk {
        serverTool(fullName)?.risk ?? .changes
    }

    /// The tools the user blocked on these servers: the agent never sees them.
    func blockedTools(on servers: [MCPServerConfig]) -> [String] {
        let prefixes = servers.map { "mcp__\($0.name)__" }
        return overrides.filter { $0.value == .never && prefixes.contains(where: $0.key.hasPrefix) }.keys.sorted()
    }

    /// Asks the server for its tools (signed in, without calling any) and
    /// keeps the list.
    @discardableResult
    func refreshTools(of server: MCPServerConfig) async throws -> [MCPToolInfo] {
        let headers = try await auth.headers(for: server)
        let tools = try await MCPClient.listTools(server, headers: headers)
        Log.trace("MCP tools of \(server.name): \(tools.count) (\(MCPToolList.summary(tools)))")
        serverTools[server.name] = tools
        saveServerTools()
        return tools
    }

    /// The self-test's stand-in lists, and where they are kept.
    func setServerToolsForSelfTest(_ tools: [MCPToolInfo], for server: String) {
        serverTools[server] = tools
        saveServerTools()
    }

    var serverToolsFileForSelfTest: URL? { serverToolsURL }

    /// Where the self-test's settings are kept.
    static func fileURLForSelfTest(_ settings: ToolSettings) -> URL {
        settings.fileURL ?? URL(fileURLWithPath: "/dev/null")
    }

    private var serverToolsURL: URL? {
        fileURL?.deletingLastPathComponent().appendingPathComponent("server-tools.json")
    }

    private func saveServerTools() {
        guard let url = serverToolsURL, let data = try? JSONEncoder().encode(serverTools) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func server(named name: String) -> MCPServerConfig? {
        servers.first { $0.name == name }
    }

    /// Adds or replaces the server with this name.
    func saveServer(_ server: MCPServerConfig) {
        var server = server
        server.name = MCPServerConfig.normalizedName(server.name)
        guard !server.name.isEmpty, server.name != "skilli" else { return }
        if let index = servers.firstIndex(where: { $0.name == server.name }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        save()
    }

    // MARK: - Custom tools

    func customTool(named name: String) -> CustomTool? {
        customTools.first { $0.name == name }
    }

    /// Adds or replaces the tool with this name; `token`, when given, goes to
    /// the Keychain (empty removes it). Returns why it was refused.
    @discardableResult
    func saveCustomTool(_ tool: CustomTool, replacing old: String? = nil, token: String? = nil) -> String? {
        var tool = tool
        tool.name = PromptQuestion.normalizedID(tool.name)
        tool.instructions = tool.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        tool.url = tool.url.trimmingCharacters(in: .whitespaces)
        guard !tool.name.isEmpty else { return "Give the tool a name." }
        guard SkilliTools.definition(tool.name) == nil else { return "“\(tool.name)” is one of skil.li's own tools." }
        guard CustomTool.isAllowed(tool.url) else { return "The address must start with https:// (or http://localhost)." }
        if let old, old != tool.name {
            customTools.removeAll { $0.name == old }
            if let token = self.token(for: old) { try? Keychain.save(token, account: tokenAccount(tool.name)) }
            Keychain.delete(account: tokenAccount(old))
        }
        if let index = customTools.firstIndex(where: { $0.name == tool.name }) {
            customTools[index] = tool
        } else {
            customTools.append(tool)
        }
        if let token {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty {
                Keychain.delete(account: tokenAccount(tool.name))
            } else {
                try? Keychain.save(token, account: tokenAccount(tool.name))
            }
        }
        save()
        return nil
    }

    /// One of the user's tools removed, all it had: ⌘Z puts it back.
    struct RemovedTool {
        let tool: RemovedElement<CustomTool>
        fileprivate let override: ToolOverride?
        fileprivate let token: String?
    }

    @discardableResult
    func removeCustomTool(named name: String) -> RemovedTool? {
        let token = token(for: name)
        let override = overrides[name]
        let removed = RemovedElement.take(name, from: &customTools)
        overrides[name] = nil
        Keychain.delete(account: tokenAccount(name))
        save()
        return removed.map { RemovedTool(tool: $0, override: override, token: token) }
    }

    /// Back with its right and its token; one made with its name meanwhile
    /// stays as it is.
    func restore(_ removed: RemovedTool) {
        let name = removed.tool.element.name
        guard removed.tool.putBack(into: &customTools) else { return }
        if let override = removed.override { overrides[name] = override }
        if let token = removed.token { try? Keychain.save(token, account: tokenAccount(name)) }
        save()
    }

    func token(for tool: String) -> String? {
        Keychain.read(account: tokenAccount(tool))
    }

    private func tokenAccount(_ tool: String) -> String {
        keychainPrefix + "tool-token-" + tool
    }

    /// A server removed, all it had (its place, token or sign-in, the
    /// rights of its tools, their list): ⌘Z puts it back.
    struct RemovedServer {
        let server: RemovedElement<MCPServerConfig>
        let signIn: MCPAuth.Kept
        fileprivate let overrides: [String: ToolOverride]
        fileprivate let tools: [MCPToolInfo]?
    }

    @discardableResult
    func removeServer(named name: String) -> RemovedServer? {
        let signIn = auth.kept(for: name)
        let prefix = "mcp__\(name)__"
        let rights = overrides.filter { $0.key.hasPrefix(prefix) }
        let tools = serverTools[name]
        let removed = RemovedElement.take(name, from: &servers)
        auth.forget(name)
        overrides = overrides.filter { !$0.key.hasPrefix(prefix) }
        serverTools[name] = nil
        saveServerTools()
        save()
        return removed.map { RemovedServer(server: $0, signIn: signIn, overrides: rights, tools: tools) }
    }

    /// Back as it was; a server added with its name meanwhile stays as it is.
    func restore(_ removed: RemovedServer) {
        let name = removed.server.element.name
        guard removed.server.putBack(into: &servers) else { return }
        auth.putBack(removed.signIn, for: name)
        overrides.merge(removed.overrides) { current, _ in current }
        if let tools = removed.tools {
            serverTools[name] = tools
            saveServerTools()
        }
        save()
    }

    private func save() {
        guard !isLoading, let fileURL else { return }
        let file = File(approval: mode.rawValue, tools: overrides.mapValues(\.rawValue), servers: servers, custom: customTools,
                        rules: rules.isEmpty ? nil : rules, trustedLinks: linkTrust.links.isEmpty ? nil : linkTrust.links)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
