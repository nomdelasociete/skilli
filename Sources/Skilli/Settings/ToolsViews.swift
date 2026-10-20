import AppKit
import SkilliCore
import SwiftUI

/// Settings → Tools, in the order of the Settings plan's rules: how the
/// tools are reached (Ask's keys, any agent), the settings that matter
/// first (Help Me Choose, and when they ask, which is Ask's), what leaves
/// the Mac, then the long lists grouped by owner (each connected server,
/// skil.li's tools by group), and the user's own webhooks and the bridge's
/// command under Advanced, closed. When tools wait for an OK at all, and
/// the user's rules, are Ask's (Settings → Ask → When It Acts).
struct ToolsPane: View {
    @Bindable var settings: ToolSettings
    /// Which AI helps set the rights: the one Ask → Continue in uses.
    @Bindable var preferences: Preferences
    /// A server or a tool removed: at once, ⌘Z in the card puts it back.
    let deletes: UndoableDeletes
    /// The user's AIs that can help (those installed), Claude Code first.
    var helpers: [Handoff.Target] = []
    var openHelper: (_ server: String?) throws -> Void = { _ in }
    /// Ask's keys as keycaps: the tools are reached through it (rule 2).
    var askChords: [[String]] = []
    /// What leaves the Mac through the tools (`PrivacyMap.line(for:)`).
    var leaves: PrivacyMap.PaneLine?
    /// Shows another pane (Ask, Privacy).
    var open: (SettingsPane) -> Void = { _ in }
    @State private var helperError: String?
    /// The one chosen, else the one installed; nil without any.
    private var helper: Handoff.Target? { Self.chosen(preferences.handoffTarget, among: helpers) }
    @State private var editingServer: MCPServerConfig?
    @State private var editingTool: CustomTool?
    @State private var listingServer: MCPServerConfig?
    @State private var importingServers = false
    @State private var copied = false
    /// Sign-in state per server: "Waiting for the browser…", an error.
    @State private var signing: [String: String] = [:]
    /// Bumped after a sign-in, so the statuses read the Keychain again.
    @State private var signIns = 0

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    ShortcutView(chords: askChords)
                } label: {
                    LabelDetail("From Ask", "Ask uses these tools when it acts, and so do your commands with tools.")
                }
                LabeledContent {
                    Button(copied ? "Copied" : "Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.claudeCodeCommand, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                    .help(Self.claudeCodeCommand)
                } label: {
                    LabelDetail("From your agents", "Claude Code, Codex, Claude for Mac: any MCP client. Copy Command adds skil.li to Claude Code.")
                }
                if let helper {
                    LabeledContent {
                        HStack(spacing: 8) {
                            // Both installed: choose here (the same choice
                            // as Ask → Continue in).
                            if helpers.count > 1 {
                                Picker("With", selection: $preferences.handoffTarget) {
                                    ForEach(helpers, id: \.self) { Text($0.title).tag($0) }
                                }
                                .labelsHidden()
                                .fixedSize()
                                .help("The SI that helps. ⌘↩ continues a conversation in it too (Ask → Continue in).")
                            }
                            Button(helpers.count > 1 ? "Set Rights…" : "Set Rights With \(helper.title)…") {
                                do {
                                    try openHelper(nil)
                                    helperError = nil
                                } catch {
                                    helperError = error.localizedDescription
                                }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Help Me Choose")
                            Text(helperError ?? "\(helper.title) reads your tools, asks what you use them for and proposes rights. Every change waits for your OK here.")
                                .font(.caption).foregroundStyle(helperError == nil ? .secondary : Color.red)
                        }
                    }
                }
                LabeledContent {
                    PaneLink(pane: .ask, open: open)
                } label: {
                    LabelDetail("When they ask", whenTheyAsk)
                }
            } header: {
                PaneHeader(pane: .tools)
            }

            if let leaves {
                Section {
                    LeavesMacRow(line: leaves, open: open)
                }
            }

            Section {
                if settings.servers.isEmpty {
                    Text("No servers yet.").foregroundStyle(.secondary)
                }
                ForEach(settings.servers) { server in
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("Tools…") { listingServer = server }
                                .help("Its tools, what each one does, and when it may run.")
                            if server.auth == .oauth {
                                if settings.auth.session(for: server.name) == nil || signing[server.name] != nil {
                                    Button("Sign In…") { signIn(server) }
                                        .disabled(signing[server.name] == "Waiting for the browser…")
                                } else {
                                    Button("Sign Out") {
                                        settings.auth.signOut(server.name)
                                        signIns += 1
                                    }
                                }
                            }
                            Button("Edit") { editingServer = server }
                            Button {
                                // At once, its sign-in with it; ⌘Z in the card puts all back.
                                deletes.server(server.name, in: settings)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(server.name)")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            Text(server.summary).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            if let status = signing[server.name] ?? settings.auth.status(of: server) {
                                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    .id(signIns)
                            }
                            if let listed = settings.serverTools[server.name] {
                                Text(MCPToolList.summary(listed) + serverChoices(server.name))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                HStack(spacing: 16) {
                    Button {
                        editingServer = MCPServerConfig(name: "")
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                    Button {
                        importingServers = true
                    } label: {
                        Label("Import From Other Apps…", systemImage: "square.and.arrow.down")
                    }
                    .help("The MCP servers you set up in Claude Code, Claude for Mac, Codex or Cursor.")
                }
            } header: {
                Text("Connected Servers")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("servers")
            } footer: {
                Text("MCP servers: other apps' tools that Ask and your commands can use. A command uses a server when you turn it on under Tools in the command editor. Tools… sets what each tool may do; read-only ones run in Ask Before Changes, the rest ask in the card.")
            }

            Section {
                ForEach(Self.groups, id: \.group) { entry in
                    DisclosureGroup {
                        ForEach(entry.tools, id: \.name) { definition in
                            LabeledContent {
                                rightPicker(definition.name, defaultLabel: defaultLabel(definition))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(definition.title)
                                    Text(definition.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: entry.group.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.group.title)
                                Text(choices(entry.tools.map(\.name)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            setAllMenu(entry.tools.map(\.name))
                        }
                    }
                }
            } header: {
                Text("skil.li Tools")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("toolRights")
            } footer: {
                Text("Default follows Ask → When It Acts and your rules there. Block hides a tool from every agent, Claude Code and Codex included: no rule allows it. A change to skil.li's settings asks in the card every time.")
            }

            AdvancedSection(summary: "Your own tools (webhooks), the command other agents run",
                            footer: "skil.li sends {\"text\", \"note\", \"tool\", \"app\"} as JSON to a tool's address and gives the reply to the agent. Ask can use your tools; commands use them with Your Tools turned on. They ask first unless you choose Always. Approvals show in skil.li's card, whoever asks.",
                            anchors: ["customTools"]) {
                if settings.customTools.isEmpty {
                    Text("Your tools: none yet. A webhook skil.li can call, with a sentence saying when.").foregroundStyle(.secondary)
                }
                ForEach(settings.customTools) { tool in
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("Edit") { editingTool = tool }
                            Button {
                                deletes.customTool(tool.name, in: settings)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(tool.name)")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                            Text(tool.instructions.isEmpty ? tool.url : tool.instructions)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                Button {
                    editingTool = CustomTool(name: "", instructions: "", url: "https://")
                } label: {
                    Label("Add Tool", systemImage: "plus")
                }
                .settingAnchor("customTools")
                LabeledContent("Command for other agents") {
                    Text(Self.bridgeCommand)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingServer) { server in
            ServerEditor(settings: settings, draft: server)
        }
        .sheet(isPresented: $importingServers) {
            ImportServersSheet(settings: settings)
        }
        .sheet(item: $listingServer) { server in
            ServerToolsSheet(settings: settings, server: server, preferences: preferences, helpers: helpers, openHelper: openHelper)
        }
        .sheet(item: $editingTool) { tool in
            CustomToolEditor(settings: settings, draft: tool)
        }
    }

    /// "Ask Before Changes, and 2 rules in your words." (Ask's settings).
    private var whenTheyAsk: String {
        let mode = switch settings.mode {
        case .ask: "Ask Every Time"
        case .auto: "Ask Before Changes"
        case .always: "Always Allow"
        }
        let rules = ApprovalRules.active(settings.rules).count
        return mode + (rules == 0 ? "" : ", and \(rules) rule\(rules == 1 ? "" : "s") in your words") + ". Set in Ask."
    }

    /// The server's sign-in page in the browser; the row says how it went.
    private func signIn(_ server: MCPServerConfig) {
        signing[server.name] = "Waiting for the browser…"
        Task {
            do {
                try await settings.auth.signIn(server)
                signing[server.name] = nil
                // Its tools, for their rights, now that it lets skil.li in.
                _ = try? await settings.refreshTools(of: server)
            } catch {
                signing[server.name] = error.localizedDescription
            }
            signIns += 1
        }
    }

    private func defaultLabel(_ definition: ToolDefinition) -> String {
        if ToolSettings.asksEveryTime(definition.name) { return "Ask Every Time" }
        return ToolPolicy.needsApproval(risk: definition.risk, mode: settings.mode, override: nil) ? "Ask (Default)" : "Allow (Default)"
    }

    /// skil.li's tools by group, the ones that only talk to the user left out.
    private static let groups: [(group: ToolGroup, tools: [ToolDefinition])] = ToolGroup.allCases.compactMap { group in
        let tools = SkilliTools.definitions.filter { $0.group == group && $0.risk != .none }
        return tools.isEmpty ? nil : (group, tools)
    }

    private func rightPicker(_ tool: String, defaultLabel: String) -> some View {
        ToolRightPicker(settings: settings, tool: tool, defaultLabel: defaultLabel, everyTime: ToolSettings.asksEveryTime(tool))
    }

    /// "Default for All", "Block All"… for a group, from a ⋯ menu.
    private func setAllMenu(_ tools: [String]) -> some View {
        Menu {
            Button("Default for All") { settings.setOverrides(Dictionary(uniqueKeysWithValues: tools.map { ($0, nil) })) }
            Button("Always Ask for All") { settings.setOverrides(Dictionary(uniqueKeysWithValues: tools.map { ($0, .ask) })) }
            // A settings change asks every time: no Always Allow for it.
            Button("Always Allow All") {
                settings.setOverrides(Dictionary(uniqueKeysWithValues: tools.filter { !ToolSettings.asksEveryTime($0) }.map { ($0, .always) }))
            }
            Divider()
            Button("Block All") { settings.setOverrides(Dictionary(uniqueKeysWithValues: tools.map { ($0, .never) })) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Set every tool of this group")
        .accessibilityLabel("Set All")
    }

    /// "5 tools · 1 always allowed · 1 blocked", or "5 tools · default".
    private func choices(_ tools: [String]) -> String {
        // A settings change asks whatever its right says, Block aside.
        let counts = Self.counts(tools.compactMap { tool in
            let right = settings.override(for: tool)
            return ToolSettings.asksEveryTime(tool) && right != .never ? nil : right
        })
        let everyTime = tools.contains(where: ToolSettings.asksEveryTime) ? " · changes ask every time" : ""
        return "\(tools.count) tool\(tools.count == 1 ? "" : "s")" + (counts.isEmpty ? " · default" : counts) + everyTime
    }

    /// The user's choices among a server's tools: " · 3 blocked".
    private func serverChoices(_ server: String) -> String {
        Self.counts(settings.overrides.filter { $0.key.hasPrefix("mcp__\(server)__") }.map(\.value))
    }

    /// The AI chosen in Ask if installed, else the first one installed.
    static func chosen(_ choice: Handoff.Target, among helpers: [Handoff.Target]) -> Handoff.Target? {
        helpers.contains(choice) ? choice : helpers.first
    }

    static func counts(_ choices: [ToolOverride]) -> String {
        let counts = Dictionary(grouping: choices, by: { $0 }).mapValues(\.count)
        var parts: [String] = []
        if let always = counts[.always] { parts.append("\(always) always allowed") }
        if let ask = counts[.ask] { parts.append("\(ask) always ask") }
        if let never = counts[.never] { parts.append("\(never) blocked") }
        return parts.map { " · " + $0 }.joined()
    }

    static var bridgeCommand: String {
        Self.quoted(Bundle.main.executablePath ?? "Skilli") + " mcp"
    }

    static var claudeCodeCommand: String {
        "claude mcp add skilli -- " + bridgeCommand
    }

    private static func quoted(_ path: String) -> String {
        path.contains(" ") ? "\"\(path)\"" : path
    }
}

/// Adds or edits one of the user's tools: name, when to use it, webhook.
private struct CustomToolEditor: View {
    let settings: ToolSettings
    @State private var draft: CustomTool
    @State private var token = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    /// The name before editing: a rename moves its token and settings.
    private let original: String?

    init(settings: ToolSettings, draft: CustomTool) {
        self.settings = settings
        _draft = State(initialValue: draft)
        original = draft.name.isEmpty ? nil : draft.name
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("grok-bot"))
                    TextField("When to Use It", text: $draft.instructions, prompt: Text("Send a text to my Grok bot on Telegram"), axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Webhook", text: $draft.url, prompt: Text("https://example.com/hook"))
                    SecureField("Token", text: $token, prompt: Text(settings.token(for: draft.name) == nil ? "Optional: sent as Bearer" : "Saved — type to replace"))
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("The agent reads “When to Use It” to decide. The token stays in your Keychain.")
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    error = settings.saveCustomTool(draft, replacing: original, token: token.isEmpty ? nil : token)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 480)
    }
}

/// Adds or edits a connected server: a command to run, or a web address.
private struct ServerEditor: View {
    let settings: ToolSettings
    @State var draft: MCPServerConfig
    @State private var isWeb = false
    @State private var commandLine = ""
    @State private var token = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $draft.name, prompt: Text("linear"))
                Picker("Kind", selection: $isWeb) {
                    Text("Command").tag(false)
                    Text("Web Address").tag(true)
                }
                .pickerStyle(.segmented)
                if isWeb {
                    TextField("Address", text: Binding(get: { draft.url ?? "" }, set: { draft.url = $0 }),
                              prompt: Text("https://mcp.linear.app/mcp"))
                    Picker("Sign-In", selection: $draft.auth) {
                        Text("None").tag(MCPServerConfig.Auth?.none)
                        Text("Token").tag(MCPServerConfig.Auth?.some(.token))
                        Text("OAuth").tag(MCPServerConfig.Auth?.some(.oauth))
                    }
                    if draft.auth == .token {
                        SecureField("Token", text: $token,
                                    prompt: Text(settings.auth.token(for: draft.name) == nil ? "Sent as Bearer" : "Saved — type to replace"))
                        TextField("Header", text: Binding(get: { draft.header ?? "" }, set: { draft.header = $0.isEmpty ? nil : $0 }),
                                  prompt: Text("Authorization"))
                    }
                    if draft.auth == .oauth {
                        Text("After saving, Sign In… opens the server's own sign-in page in your browser. skil.li keeps the token in the Keychain and renews it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    TextField("Command", text: $commandLine, prompt: Text("npx -y @modelcontextprotocol/server-memory"))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var server = draft
                    if isWeb {
                        server.command = nil
                        server.args = []
                        if server.auth != .token { server.header = nil }
                    } else {
                        server.auth = nil
                        server.header = nil
                        let words = Self.words(commandLine)
                        server.url = nil
                        server.command = words.first
                        server.args = Array(words.dropFirst())
                    }
                    settings.saveServer(server)
                    let name = MCPServerConfig.normalizedName(server.name)
                    if server.auth == .token, !token.isEmpty { settings.auth.setToken(token, for: name) }
                    if server.auth != .token { settings.auth.setToken("", for: name) }
                    if server.auth != .oauth { settings.auth.signOut(name) }
                    // Its tools, for their rights (an OAuth server lists them once signed in).
                    if server.auth != .oauth, let saved = settings.server(named: name) {
                        Task { _ = try? await settings.refreshTools(of: saved) }
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(MCPServerConfig.normalizedName(draft.name).isEmpty
                          || (isWeb ? !(draft.url ?? "").hasPrefix("http") : Self.words(commandLine).isEmpty))
            }
            .padding(14)
        }
        .frame(width: 480)
        .onAppear {
            isWeb = draft.url != nil
            commandLine = ([draft.command].compactMap { $0 } + draft.args).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        }
    }

    /// Shell-like words: spaces split, quotes group.
    static func words(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

/// Default, Always Ask, Always Allow or Block for one tool.
private struct ToolRightPicker: View {
    let settings: ToolSettings
    let tool: String
    let defaultLabel: String
    /// A change to skil.li's settings: it asks every time, or is blocked.
    var everyTime = false

    var body: some View {
        Picker(tool, selection: Binding(
            // A right set before (or by hand) means nothing here: it asks.
            get: { everyTime && settings.override(for: tool) != .never ? nil : settings.override(for: tool) },
            set: { settings.setOverride($0, for: tool) }
        )) {
            Text(defaultLabel).tag(ToolOverride?.none)
            if !everyTime {
                Text("Always Ask").tag(ToolOverride?.some(.ask))
                Text("Always Allow").tag(ToolOverride?.some(.always))
            }
            Divider()
            Text("Block").tag(ToolOverride?.some(.never))
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// A connected server's tools as it lists them, by what they may do, each
/// with its right: search, and set many at once.
struct ServerToolsSheet: View {
    let settings: ToolSettings
    let server: MCPServerConfig
    /// Which AI helps set the rights: the one Ask → Continue in uses.
    @Bindable var preferences: Preferences
    /// The user's AIs that can help (those installed), Claude Code first.
    var helpers: [Handoff.Target] = []
    var openHelper: (_ server: String?) throws -> Void = { _ in }
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var helper: Handoff.Target? { ToolsPane.chosen(preferences.handoffTarget, among: helpers) }
    private var tools: [MCPToolInfo] { settings.serverTools[server.name] ?? [] }

    private func askHelper() {
        do {
            try openHelper(server.name)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var shown: [MCPToolInfo] {
        let words = search.lowercased().split(separator: " ")
        guard !words.isEmpty else { return tools }
        return tools.filter { tool in
            let text = [tool.name, tool.title ?? "", tool.description].joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.headline)
                    Text(tools.isEmpty ? server.summary : MCPToolList.summary(tools) + ToolsPane.counts(choices))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                }
                if let helper {
                    // Both installed: the arrow asks the other one (and
                    // keeps it as the choice).
                    if helpers.count > 1 {
                        Menu {
                            ForEach(helpers, id: \.self) { target in
                                Button("Ask \(target.title)…") {
                                    preferences.handoffTarget = target
                                    askHelper()
                                }
                            }
                        } label: {
                            Label("Ask \(helper.title)…", systemImage: "sparkles")
                        } primaryAction: {
                            askHelper()
                        }
                        .fixedSize()
                        .help("\(helper.title) reads these tools, asks what you use \(server.name) for and proposes rights; you confirm each change here. The arrow picks the other SI.")
                    } else {
                        Button {
                            askHelper()
                        } label: {
                            Label("Ask \(helper.title)…", systemImage: "sparkles")
                        }
                        .help("\(helper.title) reads these tools, asks what you use \(server.name) for and proposes rights; you confirm each change here.")
                    }
                }
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
                .help("Ask \(server.name) for its tools again.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                TextField("Search Tools", text: $search, prompt: Text("Search \(tools.count) tools"))
                    .textFieldStyle(.roundedBorder)
                Menu {
                    Button("Always Allow Read-Only Tools") { set(.always, where: { $0.kind == .reads }) }
                    Button("Block Tools That Can Destroy") { set(.never, where: { $0.kind == .destroys }) }
                    Button("Always Ask for the Others") { set(.ask, where: { $0.kind != .reads && $0.kind != .destroys }) }
                    Divider()
                    Button("Reset All to Default") { set(nil, where: { _ in true }) }
                } label: {
                    Text("Set Several")
                }
                .menuStyle(.button)
                .fixedSize()
                .disabled(tools.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()
            if tools.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    if loading {
                        Text("Asking \(server.name) for its tools…").foregroundStyle(.secondary)
                    } else if let error {
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await refresh() } }
                    } else {
                        Text("\(server.name) lists no tools.").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                Form {
                    ForEach(MCPToolInfo.Kind.allCases, id: \.self) { kind in
                        let items = shown.filter { $0.kind == kind }
                        if !items.isEmpty {
                            Section {
                                ForEach(items, id: \.name) { tool in row(tool) }
                            } header: {
                                Text("\(Self.title(kind)) · \(items.count)")
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(error.map { tools.isEmpty ? "" : $0 } ?? "Defaults follow Ask → When It Acts and the server's own hints. Block hides a tool from the agent.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 640, height: 600)
        .task {
            if tools.isEmpty { await refresh() }
        }
    }

    private func row(_ tool: MCPToolInfo) -> some View {
        LabeledContent {
            ToolRightPicker(settings: settings, tool: MCPToolInfo.fullName(server: server.name, tool: tool.name),
                            defaultLabel: ToolPolicy.needsApproval(risk: tool.risk, mode: settings.mode, override: nil) ? "Ask (Default)" : "Allow (Default)")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.displayName(tool))
                Text(tool.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                if !tool.description.isEmpty {
                    Text(tool.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .help(tool.description)
                }
            }
        }
    }

    /// Its title, else its name in words: "list_dns_records" → "List dns records".
    static func displayName(_ tool: MCPToolInfo) -> String {
        if let title = tool.title, !title.isEmpty { return title }
        let words = tool.name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private var choices: [ToolOverride] {
        tools.compactMap { settings.override(for: MCPToolInfo.fullName(server: server.name, tool: $0.name)) }
    }

    private func set(_ value: ToolOverride?, where matches: (MCPToolInfo) -> Bool) {
        let names = tools.filter(matches).map { MCPToolInfo.fullName(server: server.name, tool: $0.name) }
        settings.setOverrides(Dictionary(uniqueKeysWithValues: names.map { ($0, value) }))
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            try await settings.refreshTools(of: server)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func title(_ kind: MCPToolInfo.Kind) -> String {
        switch kind {
        case .reads: "Read Only"
        case .changes: "Change Things"
        case .destroys: "Can Delete or Overwrite"
        case .unknown: "No Hints From the Server"
        }
    }
}

/// The MCP servers set up in Claude Code, Claude for Mac, Codex and Cursor,
/// to add to skil.li in one go.
struct ImportServersSheet: View {
    let settings: ToolSettings
    /// The self-test's; nil reads the apps' own files.
    var found: [MCPImport.Candidate]?
    @State private var candidates: [MCPImport.Candidate] = []
    @State private var chosen: Set<Int> = []
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if !loaded {
                    Text("Looking in Claude Code, Claude for Mac, Codex and Cursor…").foregroundStyle(.secondary)
                } else if candidates.isEmpty {
                    Text("No MCP servers in Claude Code, Claude for Mac, Codex or Cursor.").foregroundStyle(.secondary)
                }
                ForEach(MCPImport.Source.allCases, id: \.self) { source in
                    let rows = candidates.indices.filter { candidates[$0].source == source }
                    if !rows.isEmpty {
                        Section(source.title) {
                            ForEach(rows, id: \.self) { index in row(index) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(alignment: .center, spacing: 12) {
                Text("skil.li reads only these apps' lists of servers. A token found goes to your Keychain; a server that signs in with OAuth signs in again here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.isEmpty ? "Import" : "Import \(chosen.count)") {
                    let picked = chosen.sorted().map { candidates[$0] }
                    // Their tools are listed after the sheet closes.
                    Task { await MCPServerImporter.add(picked, to: settings) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 620, height: 540)
        .task {
            let all: [MCPImport.Candidate]
            if let found {
                all = found
            } else {
                all = await Task.detached { MCPServerImporter.find(in: MCPServerImporter.defaultLocations) }.value
            }
            candidates = all
            chosen = Set(all.indices.filter { all[$0].problem == nil && existing(all[$0]) == nil })
            loaded = true
        }
    }

    private func row(_ index: Int) -> some View {
        let candidate = candidates[index]
        let present = existing(candidate)
        let blocked = candidate.problem != nil || present != nil
        return Toggle(isOn: Binding(
            get: { chosen.contains(index) },
            set: { if $0 { chosen.insert(index) } else { chosen.remove(index) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(candidate.name)
                    if let project = candidate.project {
                        Text(URL(fileURLWithPath: project).lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .help(project)
                    }
                }
                Text(candidate.summary).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Text(note(candidate, present: present)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(blocked)
    }

    /// The server already in skil.li with the same command or address.
    private func existing(_ candidate: MCPImport.Candidate) -> MCPServerConfig? {
        settings.servers.first { server in
            if let url = candidate.url { return server.url == url }
            return server.command == candidate.command && server.args == candidate.args
        }
    }

    private func note(_ candidate: MCPImport.Candidate, present: MCPServerConfig?) -> String {
        if let present { return "Already in skil.li as “\(present.name)”." }
        if let problem = candidate.problem { return problem }
        var notes: [String] = []
        let name = MCPServerConfig.normalizedName(candidate.name)
        if settings.server(named: name) != nil { notes.append("Comes in under another name: “\(name)” is taken.") }
        if candidate.token != nil {
            notes.append("Its token goes to your Keychain.")
        } else if let variable = candidate.tokenVariable {
            notes.append("Its token is in $\(variable): paste it with Edit after the import.")
        } else if candidate.url != nil {
            notes.append("Signs in again here if it asks.")
        } else if !candidate.env.isEmpty {
            notes.append("Comes with its \(candidate.env.count) environment variable\(candidate.env.count == 1 ? "" : "s").")
        }
        if !candidate.alsoIn.isEmpty { notes.append("Also in \(candidate.alsoIn.joined(separator: ", ")).") }
        return notes.isEmpty ? "Ready to import." : notes.joined(separator: " ")
    }
}
