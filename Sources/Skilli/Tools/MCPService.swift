import AppKit
import SkilliCore

/// The user's answer to "Allow …?" in the card.
enum ToolApproval: Sendable {
    case allow
    /// Allow, and never ask again for this tool.
    case always
    case deny
}

/// Where tools reach the user: the AI card.
@MainActor
protocol ToolPresenter: AnyObject {
    /// `caller` is who asks: the command's name, or the agent ("Claude Code").
    /// `once`: no Always (a change of the rights themselves, or a call one
    /// of the user's rules asked for). `reason`: the rule that asked, as
    /// the card says it ("Asked because of your rule: …").
    func approve(_ title: String, detail: String, caller: String, run: AgentContext?, once: Bool, reason: String?) async -> ToolApproval
    /// A step a tool takes after it was allowed, asked as what it does
    /// ("Send to #general in Slack?", ↩ Send); Always only when it is kept.
    func approve(_ question: String, detail: String, verb: String, caller: String, run: AgentContext?, offersAlways: Bool) async -> ToolApproval
    /// One of the user's rules let a step run or refused it: said under
    /// the step in the run's card ("Allowed by your rule: …"). `tool` as
    /// the agent names it (`mcp__skilli__get_clipboard`).
    func ruleApplied(_ line: String, tool: String, run: AgentContext?)
    /// nil when the user dismissed the question.
    func ask(_ question: PromptQuestion, caller: String, run: AgentContext?) async -> String?
    func notify(_ message: String, caller: String, run: AgentContext?)
}

/// skil.li's MCP server: speaks MCP (2025 revisions) to every connection of
/// `MCPSocketServer`, offers `SkilliTools`, and asks the user through the
/// card before tools that change things (`ToolSettings`). Act commands
/// register their run, so their agent sees only the tools they allow and
/// its questions land in their card.
@MainActor
final class MCPService {
    private struct Session {
        /// "Claude Code", "Terminal"…
        var client = "An agent"
        var runID: String?
        /// The skillie run whose process calls (`SKILLI_SKILLIE`).
        var skillie: String?
    }

    let tools: SkilliTools
    let settings: ToolSettings
    /// skil.li's own settings (get_settings, set_setting, the lists' tools).
    var settingTools: SettingTools?
    /// Checks the user's rules (Settings → Ask → Your Rules) before a step.
    var judge: RuleJudge?
    weak var presenter: ToolPresenter?

    private var server: MCPSocketServer?
    private var sessions: [UUID: Session] = [:]
    private var runs: [String: AgentContext] = [:]
    /// The tool whose call the user has just allowed in the card: its own
    /// ask in the same call (a skillie's "ask first") would ask twice.
    private var justAllowed: String?

    nonisolated static let serverName = "skilli"
    private static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    init(tools: SkilliTools, settings: ToolSettings) {
        self.tools = tools
        self.settings = settings
        // Tools that confirm mid-way (send_message, with the conversation it
        // found) ask through the card, unless the user chose Always.
        tools.confirm = { [weak self] title, detail, verb, tool, run, alwaysMaySkip in
            guard let self else { return .deny }
            if self.justAllowed == tool {
                self.justAllowed = nil
                return .allow
            }
            if alwaysMaySkip, self.settings.override(for: tool) == .always { return .allow }
            let caller = run?.title ?? "An agent"
            // Always is offered only where it is kept and honored.
            let answer = await self.presenter?.approve(title, detail: detail, verb: verb, caller: caller, run: run, offersAlways: alwaysMaySkip) ?? .deny
            if answer == .always { self.settings.setOverride(.always, for: tool) }
            return answer
        }
    }

    var socketPath: String? { server?.path }

    func start(path: String) {
        let server = MCPSocketServer(
            path: path,
            onLine: { [weak self] connection, line in
                Task { @MainActor in await self?.handle(line, from: connection) }
            },
            onClose: { [weak self] connection in
                Task { @MainActor in self?.sessions[connection.id] = nil }
            }
        )
        do {
            try server.start()
            self.server = server
            Log.actions.notice("Tool server listening at \(path, privacy: .public)")
        } catch {
            Log.actions.error("Tool server did not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }

    func register(_ run: AgentContext) {
        runs[run.id] = run
    }

    func unregister(_ run: AgentContext) {
        runs[run.id] = nil
    }

    // MARK: - JSON-RPC

    private func handle(_ line: Data, from connection: MCPConnection) async {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]], to: connection)
            return
        }
        // The bridge's first line: which run this connection belongs to.
        if let hello = message["skilli"] as? [String: Any] {
            var session = sessions[connection.id] ?? Session()
            session.runID = hello["run"] as? String
            session.skillie = hello["skillie"] as? String
            sessions[connection.id] = session
            return
        }
        let method = message["method"] as? String ?? ""
        // Notifications get no answer.
        guard let id = message["id"] else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        var session = sessions[connection.id] ?? Session()
        // A skillie's calls go by its name, within the run of the Act
        // command whose agent started it; while it runs only. Its id lends
        // it its own card, never a right.
        let skillie = session.skillie.flatMap { tools.scripts?.running[$0] }
        let run = session.runID.flatMap { runs[$0] } ?? skillie?.agentRun.flatMap { runs[$0.id] }

        switch method {
        case "initialize":
            let client = params["clientInfo"] as? [String: Any]
            session.client = Self.clientTitle(client)
            sessions[connection.id] = session
            let requested = params["protocolVersion"] as? String ?? ""
            var instructions = "skil.li works in the user's Mac apps: their selection, clipboard, apps, menus and \(Brand.intelligence) Commands. Tools that change something may wait for the user's OK in skil.li's card."
            // The skill that ships with the app, where its tools are offered.
            if run?.groups.contains(.settings) ?? true { instructions += " " + SettingsSkill.pointer }
            send(result(id, [
                "protocolVersion": Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0],
                "capabilities": ["tools": ["listChanged": false], "resources": ["listChanged": false], "prompts": ["listChanged": false]],
                "serverInfo": ["name": Self.serverName, "title": "skil.li", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"],
                "instructions": instructions
            ]), to: connection)
        case "ping":
            send(result(id, [:]), to: connection)
        // The skill that ships with the app: a resource agents read, and a
        // prompt (Claude Code shows server prompts as slash commands).
        case "resources/list":
            send(result(id, ["resources": [["uri": SettingsSkill.uri, "name": SettingsSkill.name, "title": SettingsSkill.title,
                                            "description": SettingsSkill.description, "mimeType": "text/markdown"]]]), to: connection)
        case "resources/read":
            guard params["uri"] as? String == SettingsSkill.uri else {
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32002, "message": "Resource not found: \(params["uri"] as? String ?? "")"]], to: connection)
                return
            }
            send(result(id, ["contents": [["uri": SettingsSkill.uri, "mimeType": "text/markdown", "text": SettingsSkill.markdown]]]), to: connection)
        case "prompts/list":
            send(result(id, ["prompts": [["name": SettingsSkill.name, "title": SettingsSkill.title, "description": SettingsSkill.description,
                                          "arguments": [["name": "request", "description": "What to set up, in the user's words.", "required": false]]]]]),
                 to: connection)
        case "prompts/get":
            guard params["name"] as? String == SettingsSkill.name else {
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown prompt: \(params["name"] as? String ?? "")"]], to: connection)
                return
            }
            let request = ((params["arguments"] as? [String: Any])?["request"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Help me set up skil.li."
            send(result(id, ["description": SettingsSkill.description,
                             "messages": [["role": "user", "content": ["type": "text", "text": SettingsSkill.markdown + "\n\n" + request]]]]),
                 to: connection)
        case "tools/list":
            send(result(id, ["tools": available(for: run).map(\.listing)]), to: connection)
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let caller = run?.title ?? skillie?.command.title ?? session.client
            let reply = await SkillieCall.$id.withValue(skillie == nil ? nil : session.skillie) {
                await call(name, arguments: arguments, caller: caller, run: run)
            }
            send(result(id, reply), to: connection)
        default:
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]], to: connection)
        }
    }

    private static func clientTitle(_ info: [String: Any]?) -> String {
        if let title = info?["title"] as? String, !title.isEmpty { return title }
        switch info?["name"] as? String {
        case "claude-code": return "Claude Code"
        case let name?: return name
        case nil: return "An agent"
        }
    }

    private func result(_ id: Any, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    private func send(_ message: [String: Any], to connection: MCPConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        connection.send(data)
    }

    // MARK: - Tools

    private func text(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    /// skil.li's tools for this connection, with the user's own tools when
    /// the run allows them (always outside a run). Tools the user blocked
    /// are not offered at all.
    private func available(for run: AgentContext?) -> [ToolDefinition] {
        var tools = SkilliTools.available(for: run)
        if run?.groups.contains(.personal) ?? true {
            tools += settings.customTools.map(SkilliTools.definition(for:))
        }
        // Setting the rights: the user's own AI, never a command's agent.
        if run == nil { tools += ToolRightsTools.definitions }
        return tools.filter { settings.override(for: $0.name) != .never }
    }

    /// Every tool name skil.li may offer, for Claude Code's `--allowedTools`.
    var allToolNames: [String] {
        SkilliTools.definitions.map(\.name) + settings.customTools.map(\.name)
    }

    private func call(_ name: String, arguments: [String: Any], caller: String, run: AgentContext?) async -> [String: Any] {
        if settings.override(for: name) == .never, SkilliTools.definition(name) != nil || settings.customTool(named: name) != nil {
            Log.actions.notice("Tool \(name, privacy: .public) blocked")
            return text("The user blocked “\(name)” in skil.li. Do not try again; say what you would have done.", isError: true)
        }
        guard let definition = available(for: run).first(where: { $0.name == name }) else {
            return text("Unknown tool “\(name)”.", isError: true)
        }
        switch name {
        case SkilliTools.approve:
            return await approveForClaudeCode(arguments, caller: caller, run: run)
        case SkilliTools.askUser:
            guard let question = arguments["question"] as? String, !question.isEmpty else {
                return text("Missing “question”.", isError: true)
            }
            let options = (arguments["options"] as? [String] ?? []).filter { !$0.isEmpty }
            let prompt = PromptQuestion(id: "answer", question: question, options: Array(options.prefix(9)), defaultValue: options.first)
            guard let answer = await presenter?.ask(prompt, caller: caller, run: run) else {
                return text("The user dismissed the question.", isError: true)
            }
            return text(answer)
        case "notify":
            presenter?.notify(arguments["message"] as? String ?? "", caller: caller, run: run)
            return text("Shown.")
        case ToolRightsTools.list:
            let server = (arguments["server"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            guard let server else { return text(ToolRightsTools.overview(settings)) }
            do {
                return text(try await ToolRightsTools.tools(settings, server: server, search: arguments["search"] as? String))
            } catch {
                return text(error.localizedDescription, isError: true)
            }
        case ToolRightsTools.set:
            return await setToolRights(arguments, caller: caller)
        case _ where SettingTools.names.contains(name):
            return await callSettingTool(definition, arguments: arguments, caller: caller, run: run)
        default:
            break
        }

        let risk = SkilliTools.risk(of: definition, arguments: arguments)
        let custom = settings.customTool(named: name)
        let call = ApprovalRules.Call(tool: name, title: definition.title, description: custom?.instructions ?? definition.description,
                                      kind: Self.kind(risk), caller: caller, arguments: ToolCallSummary.arguments(arguments))
        switch await gate(name, fullName: MCPToolInfo.fullName(server: Self.serverName, tool: name), title: definition.title,
                          detail: SkilliTools.summary(of: definition, arguments: arguments), risk: risk, call: call, caller: caller, run: run) {
        case .go:
            break
        case .declined:
            return text("The user declined “\(definition.title)”. Do not try again; say what you would have done.", isError: true)
        case .refused(let rule):
            return text("The user's rule “\(rule)” refuses “\(definition.title)”. Do not try again; say what you would have done.", isError: true)
        }
        Log.trace("Tool \(name) for \(caller): \(arguments)")
        do {
            let answer: String
            if let custom = settings.customTool(named: name) {
                answer = try await tools.callWebhook(custom, arguments: arguments, token: settings.token(for: name))
            } else {
                answer = try await tools.call(name, arguments: arguments, run: run, caller: caller)
            }
            Log.actions.notice("Tool \(name, privacy: .public) for \(caller, privacy: .public)")
            Log.trace("Tool \(name) answered ⟪\(answer)⟫")
            return text(answer)
        } catch {
            Log.actions.notice("Tool \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return text(error.localizedDescription, isError: true)
        }
    }

    /// skil.li's own settings: read at once (or after an OK in Ask Every
    /// Time), the user's own content only as set or not set; a change is
    /// checked first (a refusal names what is valid), then waits for the
    /// user's OK in the card every time, said in the pane's words ("Backup:
    /// How often → Every week"), then applied as the pane would. No Always:
    /// a setting can turn on something that sends data out, so no right or
    /// mode makes a change silent (only Block, refused before this).
    private func callSettingTool(_ definition: ToolDefinition, arguments: [String: Any], caller: String,
                                 run: AgentContext?) async -> [String: Any] {
        let name = definition.name
        guard let settingTools else { return text("skil.li's settings cannot be reached now.", isError: true) }
        if SettingsTable.Tool.reads.contains(name) {
            let pane = arguments["pane"] as? String
            let detail = name != SettingsTable.Tool.getSettings ? ""
                : pane.flatMap { $0.isEmpty ? nil : "Pane: \($0)" } ?? "Every pane (keys only as set or not set)"
            let call = ApprovalRules.Call(tool: name, title: definition.title, description: definition.description,
                                          kind: Self.kind(definition.risk), caller: caller, arguments: ToolCallSummary.arguments(arguments))
            switch await gate(name, fullName: MCPToolInfo.fullName(server: Self.serverName, tool: name), title: definition.title, detail: detail,
                              risk: definition.risk, call: call, caller: caller, run: run) {
            case .go: break
            case .declined: return text("The user declined “\(definition.title)”. Do not try again.", isError: true)
            case .refused(let rule): return text("The user's rule “\(rule)” refuses “\(definition.title)”. Do not try again.", isError: true)
            }
            do {
                return text(try await settingTools.read(tool: name, arguments))
            } catch {
                return text(error.localizedDescription, isError: true)
            }
        }
        let plan: SettingTools.Plan
        do {
            plan = try await settingTools.prepare(name, arguments)
        } catch {
            Log.trace("Tool \(name) refused: \(error.localizedDescription)")
            return text(error.localizedDescription, isError: true)
        }
        if let unchanged = plan.unchanged { return text(unchanged) }
        // Never put to the user's rules: a change asks every time (#150).
        guard await presenter?.approve(definition.title, detail: plan.summary, caller: caller, run: run, once: true, reason: nil) ?? .deny != .deny else {
            Log.actions.notice("Tool \(name, privacy: .public) declined")
            return text("The user declined: \(plan.said). Nothing changed; ask them what they want instead.", isError: true)
        }
        do {
            let said = try await plan.apply()
            Log.actions.notice("Tool \(name, privacy: .public) for \(caller, privacy: .public)")
            Log.trace("Tool \(name): \(said)")
            return text(said)
        } catch {
            return text(error.localizedDescription, isError: true)
        }
    }

    /// The rights the user's AI proposes, applied once the user allows them
    /// in the card (never remembered: every change asks).
    private func setToolRights(_ arguments: [String: Any], caller: String) async -> [String: Any] {
        let server = arguments["server"] as? String ?? ""
        // An array, or one string of lines.
        let entries = (arguments["rights"] as? [String])
            ?? (arguments["rights"] as? String)?.split(whereSeparator: { $0.isNewline || $0 == "," }).map(String.init) ?? []
        let change: ToolRightsTools.Change
        do {
            change = try await ToolRightsTools.change(settings, server: server, entries: entries)
        } catch {
            return text(error.localizedDescription, isError: true)
        }
        let title = server == ToolRights.skilliServer ? "Change the rights of skil.li's tools" : "Change the rights of \(server)'s tools"
        guard await presenter?.approve(title, detail: change.summary, caller: caller, run: nil, once: true, reason: nil) ?? .deny != .deny else {
            Log.actions.notice("Tool rights for \(server, privacy: .public) declined")
            return text("The user declined these rights; nothing changed. Ask them what to change.", isError: true)
        }
        Log.actions.notice("Tool rights for \(server, privacy: .public) set by \(caller, privacy: .public): \(change.rights.count)")
        return text(ToolRightsTools.apply(change, to: settings))
    }

    /// `--permission-prompt-tool`: Claude Code asks before using a tool of
    /// another server (skil.li's own are allowed up front and approved
    /// here, in `call`). Its hints, as the server listed them, set the
    /// default: read-only ones run in "Ask Before Changes". Blocked ones
    /// are refused without a card. The answer is Claude Code's JSON.
    private func approveForClaudeCode(_ arguments: [String: Any], caller: String, run: AgentContext?) async -> [String: Any] {
        let toolName = arguments["tool_name"] as? String ?? ""
        let input = arguments["input"] as? [String: Any] ?? [:]
        let (server, tool) = AgentStream.split(toolName: toolName)
        let message: String?
        if settings.override(for: toolName) == .never {
            Log.actions.notice("Tool \(toolName, privacy: .public) blocked")
            message = "The user blocked this tool in skil.li. Do not try again; say what you would have done."
        } else {
            let detail = (try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
            let title = server.map { "\(tool.replacingOccurrences(of: "_", with: " ")) (\($0))" } ?? tool
            let info = settings.serverTool(toolName)
            let call = ApprovalRules.Call(tool: tool, title: info?.title ?? "", description: info?.description ?? "",
                                          kind: Self.kind(info?.kind ?? .unknown), server: server ?? "the agent's own", caller: caller,
                                          arguments: ToolCallSummary.arguments(input))
            switch await gate(toolName, fullName: toolName, title: title, detail: String(detail.prefix(400)),
                              risk: settings.risk(ofServerTool: toolName), call: call, caller: caller, run: run) {
            case .go: message = nil
            case .declined: message = "The user declined this tool. Do not try again."
            case .refused(let rule): message = "The user's rule “\(rule)” refuses this. Do not try again; say what you would have done."
            }
        }
        let reply: [String: Any] = message.map { ["behavior": "deny", "message": $0] } ?? ["behavior": "allow", "updatedInput": input]
        let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        return text(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Rights and rules

    /// Whether a call goes ahead.
    private enum Gate {
        case go
        case declined
        /// By the user's rule, in their words.
        case refused(String)
    }

    /// The tool's right and the mode, with the user's rules as the decision
    /// model reads them (`ApprovalRules` gives the order): refused by a
    /// rule, asked in the card (naming the rule that asked; no Always then,
    /// the rule would ask again), or run (the rule that let it run said
    /// under its step). A blocked tool is refused before this.
    private func gate(_ name: String, fullName: String, title: String, detail: @autoclosure () -> String, risk: ToolRisk,
                      call: @autoclosure () -> ApprovalRules.Call, caller: String, run: AgentContext?) async -> Gate {
        justAllowed = nil
        let ruled = await ruled(name, risk: risk, call: call())
        switch ruled.decision {
        case .block:
            if let reason = ruled.reason { presenter?.ruleApplied(reason.line, tool: fullName, run: run) }
            Log.actions.notice("Tool \(name, privacy: .public) refused by a rule")
            return .refused(ruled.reason?.rule?.said ?? "")
        case .ask:
            let once = ruled.reason != nil
            switch await presenter?.approve(title, detail: detail(), caller: caller, run: run, once: once, reason: ruled.reason?.line) ?? .deny {
            case .deny:
                Log.actions.notice("Tool \(name, privacy: .public) declined")
                return .declined
            case .always where !once:
                settings.setOverride(.always, for: name)
            case .always, .allow:
                break
            }
            justAllowed = name
            return .go
        case .run:
            if let reason = ruled.reason { presenter?.ruleApplied(reason.line, tool: fullName, run: run) }
            return .go
        }
    }

    /// What a call does now. The rules are judged only when one could
    /// change it (`ApprovalRules.shouldJudge`) and a key can check them.
    private func ruled(_ name: String, risk: ToolRisk, call: @autoclosure () -> ApprovalRules.Call) async -> ToolPolicy.Ruled {
        let everyTime = ToolSettings.asksEveryTime(name)
        let rules = ApprovalRules.active(settings.rules)
        var verdict = ApprovalRules.Verdict.none
        if let judge, judge.canJudge,
           ApprovalRules.shouldJudge(rules, risk: risk, mode: settings.mode, override: settings.override(for: name), everyTime: everyTime) {
            verdict = await judge.judge(call(), rules: rules)
        }
        return ToolPolicy.decision(risk: risk, mode: settings.mode, override: settings.override(for: name), everyTime: everyTime,
                                   verdict: verdict, hasStrictRules: rules.contains(where: \.isStrict))
    }

    /// What a tool does, for the decision model.
    static func kind(_ risk: ToolRisk) -> String {
        switch risk {
        case .none: "only talks to the user"
        case .read: "reads"
        case .harmless: "makes a light change (opens an app or a link, writes a draft)"
        case .changes: "changes things"
        }
    }

    /// What a connected server says its tool does.
    static func kind(_ kind: MCPToolInfo.Kind) -> String {
        switch kind {
        case .reads: "reads, the service says"
        case .changes: "changes things, the service says"
        case .destroys: "can delete or overwrite, the service says"
        case .unknown: "may change things (the service does not say)"
        }
    }
}
