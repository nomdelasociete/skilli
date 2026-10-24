import AppKit
import MapKit
import Speech
import SkilliCore

/// skil.li's settings for agents (rule 11 of the Settings plan: anything a
/// pane sets, an agent can set through skil.li's tools under the same name,
/// after the user's OK in the card). `get_settings` reads every setting of
/// `SettingsTable`, pane by pane; `set_setting` and the lists' own tools
/// change one, checked first against what the pane offers, then applied
/// once the user allows it (`MCPService`). Each table key is bound here to
/// what the pane itself changes: the same `Preferences` property (its
/// `didSet` saves, `onChange` applies), the same store. Never through
/// tools: keys and sign-ins, permissions, tool rights, the approval mode,
/// servers and the user's own tools.
@MainActor
final class SettingTools {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// A change checked and said in the user's words, applied once allowed.
    struct Plan {
        /// What the card shows the user: "Backup: How often → Every week",
        /// with what is there now (the user's own content may be in it).
        let summary: String
        /// One line for the agent, never the user's own content.
        let said: String
        /// Nothing to change (it is so already): said without a card.
        var unchanged: String?
        let apply: @MainActor () async throws -> String

        init(summary: String, said: String? = nil, unchanged: String? = nil, apply: @escaping @MainActor () async throws -> String) {
            self.summary = summary
            self.said = said ?? summary.components(separatedBy: "\n")[0]
            self.unchanged = unchanged
            self.apply = apply
        }

        static func already(_ text: String) -> Plan {
            Plan(summary: "", said: text, unchanged: text) { text }
        }
    }

    /// One item of a list, checked; `apply` adds or removes it.
    struct ListChange {
        /// What the agent reads back: what it gave, never more of the
        /// user's own content.
        let item: String
        /// What the card shows the user, when it says more (the address of
        /// a place removed, a field's value replaced).
        var card: String?
        var unchanged = false
        var apply: @MainActor () -> Void = {}
    }

    /// What a table key reads and writes.
    struct Binding {
        var get: @MainActor () -> SettingValue
        var set: (@MainActor (SettingValue) throws -> Void)?
        /// The choices this Mac has (`choiceOnThisMac`).
        var options: (@MainActor () async -> [SettingOption])?
        /// Checked before the card (a writer that cannot write now).
        var check: (@MainActor (SettingValue) throws -> Void)?
        var add: (@MainActor (String) async throws -> ListChange)?
        var remove: (@MainActor (String) throws -> ListChange)?
        /// A secret: only whether one is set.
        var isSet: (@MainActor () -> Bool)?
        /// A list's items as get_settings reports them: what may be read
        /// of each, the user's own content only as set or not set.
        var items: (@MainActor () -> [SettingItem])?

        init(get: @escaping @MainActor () -> SettingValue, set: (@MainActor (SettingValue) throws -> Void)? = nil) {
            self.get = get
            self.set = set
        }
    }

    /// Something the launcher opens, that an alias can name.
    struct AliasTarget {
        /// `LauncherItem.learningID`.
        let id: String
        let title: String
        /// "App", "Quicklink", "Snippet"…
        let kind: String
    }

    /// Posted after a tool changed something a pane reads once (quicklinks,
    /// snippets, the login item), so an open pane shows it.
    static let changed = Notification.Name("SettingTools.changed")

    nonisolated static let names = Set(SettingsTable.Tool.all)

    nonisolated static let definitions: [ToolDefinition] = {
        typealias Tool = SettingsTable.Tool
        let never = "Never API keys, tokens, permissions, tool rights or the approval mode: the user sets those in the pane."
        let asks = "The user confirms in skil.li's card every time (no Always: no right or approval mode makes it silent); declined, nothing changes."
        return [
            ToolDefinition(name: Tool.getSettings, title: "Read skil.li's settings",
                           description: "Every setting of skil.li's Settings window, pane by pane, as JSON: its name as the pane shows it, its key, its value, its type, the values it takes and the tools that change it. Keys and tokens, and the user's own content (About You, Your Details' values and people, snippets' text, places' and quicklinks' addresses), only say set or not set: ask the user when you need them. Read it before changing anything.",
                           group: .settings, risk: .read,
                           parameters: [.init(name: "pane", description: "Only this pane (its title: Backup, Clipboard…).", isRequired: false)]),
            ToolDefinition(name: Tool.setSetting, title: "Change a setting",
                           description: "Changes one setting of skil.li, as its pane would, after the user's OK in skil.li's card. setting is its name or key from get_settings; value one of the values it takes (true/false, a choice, a folder that exists). For a list, change is add or remove and value one item. \(asks) \(never)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "pane", description: "The pane, as get_settings names it.", isRequired: false),
                                        .init(name: "setting", description: "The setting's name or key."),
                                        .init(name: "value", description: "The new value; for a list, the item to add or remove."),
                                        .init(name: "change", description: "For a list: add or remove.", options: ["add", "remove"], isRequired: false)]),
            ToolDefinition(name: Tool.setAlias, title: "Set a launcher alias",
                           description: "Gives an item of the launcher (an app, a command, a quicklink, a snippet, a skillie, a window layout…) an alias: typed then a space, it opens it at once. An alias belongs to one item. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "alias", description: "One word, 12 characters at most: gh."),
                                        .init(name: "item", description: "The item's name as the launcher shows it: GitHub."),
                                        .init(name: "kind", description: "When several items have that name: app, command, quicklink, snippet, skillie, window layout, mac command, \(Brand.intelligence) command.", isRequired: false)]),
            ToolDefinition(name: Tool.removeAlias, title: "Remove a launcher alias",
                           description: "Removes one of the launcher's aliases. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "alias", description: "The alias.")]),
            ToolDefinition(name: Tool.createQuicklink, title: "Add a quicklink",
                           description: "Adds a quicklink: its keyword then words opens the address with {query} replaced by the words (“jira 1234”). \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "name", description: "Its name: Jira."),
                                        .init(name: "url", description: "https:// address, {query} where the words go."),
                                        .init(name: "keyword", description: "Typed first, no space: jira.", isRequired: false)]),
            ToolDefinition(name: Tool.updateQuicklink, title: "Change a quicklink",
                           description: "Changes a quicklink found by its name or keyword: only what is given changes. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "name", description: "Its name or keyword now."),
                                        .init(name: "new_name", description: "A new name.", isRequired: false),
                                        .init(name: "url", description: "A new address.", isRequired: false),
                                        .init(name: "keyword", description: "A new keyword; empty for none.", isRequired: false)]),
            ToolDefinition(name: Tool.deleteQuicklink, title: "Delete a quicklink",
                           description: "Deletes a quicklink, by its name or keyword. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "name", description: "Its name or keyword.")]),
            ToolDefinition(name: Tool.createSnippet, title: "Add a snippet",
                           description: "Adds a snippet: found by name in the launcher, typed where its keyword is typed. {cursor} where the caret ends; {clipboard}, {date}, {time}, {day}, {name} are filled in. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "name", description: "Its name: Home address."),
                                        .init(name: "text", description: "Its text."),
                                        .init(name: "keyword", description: "Typed anywhere, it becomes the text: ;addr (two characters at least, no space).", isRequired: false)]),
            ToolDefinition(name: Tool.updateSnippet, title: "Change a snippet",
                           description: "Changes a snippet found by its name or keyword: only what is given changes. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "name", description: "Its name or keyword now."),
                                        .init(name: "new_name", description: "A new name.", isRequired: false),
                                        .init(name: "text", description: "A new text.", isRequired: false),
                                        .init(name: "keyword", description: "A new keyword; empty for none.", isRequired: false)]),
            ToolDefinition(name: Tool.deleteSnippet, title: "Delete a snippet",
                           description: "Deletes a snippet, by its name or keyword. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "name", description: "Its name or keyword.")]),
            ToolDefinition(name: Tool.addShortcut, title: "Add a shortcut",
                           description: "Gives an action a global shortcut (another one if it has some): skil.li actions (Open Launcher, Clipboard History…), \(Brand.intelligence) commands, window places, Mac commands, System Settings panes, window layouts, skillies, projects, an app by its name. Keys: hyper+y (hyper is ✦, Caps Lock held), cmd+shift+k, or a chain hyper+k y. The first key needs hyper, cmd, ctrl or opt; no shortcut may equal or start another. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "action", description: "What it runs: its name (Open Launcher) or id (launcher.toggle), or an app's name."),
                                        .init(name: "keys", description: "hyper+y, cmd+shift+k, hyper+k y.")]),
            ToolDefinition(name: Tool.changeShortcut, title: "Change a shortcut",
                           description: "Gives the shortcut with these keys new keys, same rules as add_shortcut. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "keys", description: "Its keys now: hyper+space."),
                                        .init(name: "new_keys", description: "Its new keys.")]),
            ToolDefinition(name: Tool.removeShortcut, title: "Remove a shortcut",
                           description: "Removes the shortcut with these keys (a built-in action keeps its row, without keys). \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "keys", description: "Its keys: hyper+u.")]),
            ToolDefinition(name: Tool.listScheduledAsks, title: "List the asks on a schedule",
                           description: "What skil.li asks by itself at set times (Settings → Ask → On a Schedule), as JSON: id, when, what is asked, whether it is on, its next and last run. A last answer is the user's own: only whether there is one.",
                           group: .settings, risk: .read, parameters: []),
            ToolDefinition(name: Tool.addScheduledAsk, title: "Ask on a schedule",
                           description: "Has skil.li ask something at set times, as Ask would (with its tools; the answer waits for the user in skil.li's card): every day, some days of the week or a day of the month, at a time. Missed while the Mac slept: once when it wakes. \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "when", description: "As said: “every Monday at 9:00”, “every weekday at 8:30”, “every month on the 1st at 9am”, “tous les jours à 18h”."),
                                        .init(name: "ask", description: "What to ask then, in the user's words, without the time: “sum up my pull requests”.")]),
            ToolDefinition(name: Tool.pauseScheduledAsk, title: "Pause an ask on a schedule",
                           description: "Pauses an ask on a schedule, or turns it on again; the times while paused are not caught up. Found by its id, what it asks or its when (list_scheduled_asks). \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "ask", description: "Its id, what it asks, or its when."),
                                        .init(name: "paused", description: "true pauses it, false turns it on again.", options: ["true", "false"], isRequired: false)]),
            ToolDefinition(name: Tool.removeScheduledAsk, title: "Remove an ask on a schedule",
                           description: "Deletes an ask on a schedule, found by its id, what it asks or its when (list_scheduled_asks). \(asks)",
                           group: .settings, risk: .changes,
                           parameters: [.init(name: "ask", description: "Its id, what it asks, or its when.")])
        ]
    }()

    /// The preferences tools change: the app's; the self-test's scratch
    /// ones while it runs.
    var preferences: Preferences
    let shortcuts: ShortcutStore
    let quicklinks: QuicklinkStore
    let snippets: SnippetLibrary
    let toolSettings: ToolSettings
    var ai: AIStore?
    var aiCommands: AICommandsModel?
    var github: GitHubBook?
    var gifs: GIFLibrary?
    var permissions: PermissionCenter?
    var clipboard: ClipboardHistory?
    var calendarAccounts: () -> [CalendarAccount] = { [] }
    var reminderLists: () -> [String] = { [] }
    var windowLayouts: () -> [String] = { [] }
    /// Settings → Recorder → Keep recordings in: the recordings moved
    /// there (nil), or why not (one is being recorded).
    var moveRecordings: @MainActor (URL) -> String? = { _ in nil }
    var skillies: () -> [ScriptCommand] = { [] }
    var aliasTargets: () -> [AliasTarget] = { [] }
    /// Everything the Catalog lists (Settings → Catalog, the launcher's "?").
    var catalogEntries: () -> [CatalogEntry] = { [] }
    /// Asks on a schedule, and the skills Ask's agent finds (Settings → Ask).
    var scheduler: AskScheduler?
    var agentSkills: () -> [AgentSkill] = { [] }
    /// Everything Add Shortcut offers, with the name its menu shows.
    var shortcutActions: () -> [(action: SkilliAction, title: String)] = { [] }
    /// An installed app by its own name.
    var findApp: (String) -> URL? = { _ in nil }
    /// Apple Maps for a place's address; the self-test's stands in.
    var geocode: (String) async -> (latitude: Double, longitude: Double)? = { address in
        guard let request = MKGeocodingRequest(addressString: address),
              let location = (try? await request.mapItems)?.first?.location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
    private let loginItem = LoginItem()
    private var voiceLocales: [String]?

    init(preferences: Preferences, shortcuts: ShortcutStore, quicklinks: QuicklinkStore, snippets: SnippetLibrary, toolSettings: ToolSettings) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.quicklinks = quicklinks
        self.snippets = snippets
        self.toolSettings = toolSettings
    }

    static func title(of pane: String) -> String {
        SettingsPane(rawValue: pane)?.title ?? pane
    }

    /// The title of the pane that shows `key`: "Catalog" for quicklinks.
    private static func pane(showing key: String) -> String {
        title(of: SettingsTable.entries.first { $0.key == key }?.pane ?? key)
    }

    // MARK: - Reading

    /// get_settings: every pane, or one, as JSON.
    func read(pane name: String?) async throws -> String {
        var wanted: String?
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let pane = SettingsTable.pane(name, title: Self.title) else {
                throw Failure("No pane is named “\(name)”. Panes: \(SettingsTable.panes.map(Self.title).joined(separator: ", ")).")
            }
            wanted = pane
        }
        var panes: [(title: String, settings: [[String: Any]])] = []
        for pane in SettingsTable.panes where wanted == nil || pane == wanted {
            let entries = SettingsTable.entries.filter { $0.pane == pane }
            guard !entries.isEmpty else { continue }
            var settings: [[String: Any]] = []
            for entry in entries { settings.append(SettingsReport.describe(entry, await reading(entry))) }
            panes.append((Self.title(of: pane), settings))
        }
        return try SettingsReport.json(panes)
    }

    /// What `entry` holds now, for get_settings (`SettingsReport` keeps the
    /// user's own content out).
    func reading(_ entry: SettingEntry) async -> SettingReading {
        guard let binding = bindings[entry.key] else { return SettingReading(value: .text("")) }
        if entry.secret { return SettingReading(value: .text(""), isSet: binding.isSet?() == true) }
        return SettingReading(value: binding.get(), options: await binding.options?() ?? SettingsTable.options(of: entry),
                              items: binding.items?())
    }

    /// A tool that only reads: get_settings, list_scheduled_asks.
    func read(tool: String, _ arguments: [String: Any]) async throws -> String {
        guard tool == SettingsTable.Tool.listScheduledAsks else { return try await read(pane: arguments["pane"] as? String) }
        guard let scheduler else { throw Failure("The asks on a schedule cannot be reached now.") }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let items: [[String: Any]] = scheduler.asks.map { ask in
            var item: [String: Any] = ["id": Self.shortID(ask), "when": ask.schedule.spoken, "ask": ask.ask, "on": ask.isOn,
                                       "last_answer": (ask.lastAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "not set" : "set"]
            if let next = scheduler.next(ask) { item["next_run"] = formatter.string(from: next) }
            if let last = ask.lastRun {
                item["last_run"] = formatter.string(from: last)
                item["last_failed"] = ask.lastFailed
            }
            if scheduler.running.contains(ask.id) { item["running"] = true }
            return item
        }
        let root: [String: Any] = [
            "scheduled_asks": items,
            "how": "add_scheduled_ask (when, ask), pause_scheduled_ask and remove_scheduled_ask (ask: its id, what it asks or its when); each change asks the user in skil.li's card. A last answer is the user's own: ask them."
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Changing

    /// Checks a change and says it; nothing changes until `apply`.
    func prepare(_ tool: String, _ arguments: [String: Any]) async throws -> Plan {
        typealias Tool = SettingsTable.Tool
        switch tool {
        case Tool.setSetting: return try await prepareSetting(arguments)
        case Tool.setAlias: return try prepareAlias(arguments)
        case Tool.removeAlias: return try prepareRemoveAlias(arguments)
        case Tool.createQuicklink, Tool.updateQuicklink, Tool.deleteQuicklink: return try prepareQuicklink(tool, arguments)
        case Tool.createSnippet, Tool.updateSnippet, Tool.deleteSnippet: return try prepareSnippet(tool, arguments)
        case Tool.addShortcut, Tool.changeShortcut, Tool.removeShortcut: return try prepareShortcut(tool, arguments)
        case Tool.addScheduledAsk, Tool.pauseScheduledAsk, Tool.removeScheduledAsk: return try prepareScheduledAsk(tool, arguments)
        default: throw Failure("Unknown tool “\(tool)”.")
        }
    }

    private static func text(_ name: String, in arguments: [String: Any]) throws -> String {
        guard let value = try optional(name, in: arguments), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure("Missing “\(name)”.")
        }
        return value
    }

    /// A text, a number or true/false, as text; nil when not given.
    private static func optional(_ name: String, in arguments: [String: Any]) throws -> String? {
        switch arguments[name] {
        case nil, is NSNull: return nil
        case let text as String: return text
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        default: throw Failure("“\(name)” is one value: a text, a number, true or false.")
        }
    }

    private func prepareSetting(_ arguments: [String: Any]) async throws -> Plan {
        let entry = try SettingsTable.entry(pane: try Self.optional("pane", in: arguments), setting: try Self.text("setting", in: arguments),
                                            title: Self.title)
        let pane = Self.title(of: entry.pane)
        let label = "\(pane) → \(entry.name)"
        switch entry.access {
        case .paneOnly(let why):
            throw Failure("\(label) is set only by the user, in Settings → \(pane). \(why)")
        case .tools(let tools) where !entry.usesSetSetting:
            throw Failure("\(label) changes with \(tools.joined(separator: ", ")), not set_setting.")
        case .tools:
            break
        }
        guard let binding = bindings[entry.key] else { throw Failure("No tool changes \(label) yet.") }
        guard let raw = try Self.optional("value", in: arguments) else { throw Failure("Missing “value”.") }
        if case .list(_, let adds) = entry.kind {
            let change = try Self.optional("change", in: arguments).map(SettingsTable.folded) ?? ""
            let adding: Bool
            switch change {
            case "add" where adds: adding = true
            case "add": throw Failure("\(label): tools only remove one; the user adds them.")
            case "remove": adding = false
            default:
                let now = entry.personal ? "" : " Now: \(SettingsTable.shown(binding.get(), for: entry))."
                throw Failure("\(label) is a list: change “add” or “remove”, with one item as value.\(now)")
            }
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { throw Failure("Missing the item to \(change).") }
            let found: ListChange?
            if adding {
                found = try await binding.add?(item)
            } else {
                found = try binding.remove?(item)
            }
            guard let listChange = found else { throw Failure("No tool changes \(label) yet.") }
            if listChange.unchanged {
                return .already(adding ? "\(label) has \(listChange.item) already." : "\(label) does not have \(listChange.item).")
            }
            let said = SettingsTable.listChange(entry, paneTitle: pane, adding: adding, item: listChange.item)
            let card = SettingsTable.listChange(entry, paneTitle: pane, adding: adding, item: listChange.card ?? listChange.item)
            return Plan(summary: card, said: said) {
                listChange.apply()
                return "Done: \(said)."
            }
        }
        let options = await binding.options?() ?? SettingsTable.options(of: entry)
        let value = try SettingsTable.parse(raw, for: entry, options: options, paneTitle: pane, isFolder: Self.isFolder)
        try binding.check?(value)
        let before = binding.get()
        let shown = SettingsTable.shown(value, for: entry, options: options)
        if before == value { return .already(entry.personal ? "\(label) is so already." : "\(label) is \(shown) already.") }
        let was = SettingsTable.shown(before, for: entry, options: options)
        let summary = SettingsTable.change(entry, paneTitle: pane, to: shown)
        // What the user wrote before is theirs: in the card, not for the agent.
        return Plan(summary: summary + "\nNow: \(was)", said: entry.personal ? "\(label) changes" : summary) {
            guard let set = binding.set else { throw Failure("No tool changes \(label) yet.") }
            try set(value)
            return entry.personal ? "Done: \(label) changed." : "Done: \(summary) (it was \(was))."
        }
    }

    private static func isFolder(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    private static func folded(_ text: String) -> String { SettingsTable.folded(text) }

    // MARK: - Aliases

    private func prepareAlias(_ arguments: [String: Any]) throws -> Plan {
        let alias = LauncherAliases.normalized(try Self.text("alias", in: arguments))
        guard LauncherAliases.isValid(alias) else { throw Failure("An alias is one word of 1 to 12 characters, without a space.") }
        let wanted = try Self.text("item", in: arguments)
        let kind = try Self.optional("kind", in: arguments).map(Self.folded).flatMap { $0.isEmpty ? nil : $0 }
        let targets = aliasTargets().filter { kind == nil || Self.folded($0.kind) == kind }
        let exact = targets.filter { Self.folded($0.title) == Self.folded(wanted) }
        let target: AliasTarget
        if exact.count == 1 {
            target = exact[0]
        } else if exact.count > 1 {
            throw Failure("Several items are named “\(wanted)”: \(exact.map { "\($0.title) (\($0.kind))" }.joined(separator: ", ")). Pass kind.")
        } else {
            let close = targets.filter { Self.folded($0.title).contains(Self.folded(wanted)) }
            guard close.count == 1 else {
                let hint = close.prefix(10).map { "\($0.title) (\($0.kind))" }.joined(separator: ", ")
                throw Failure("No item of the launcher is named “\(wanted)”." + (hint.isEmpty ? "" : " Close: \(hint)."))
            }
            target = close[0]
        }
        let current = preferences.launcherAliases
        if current.contains(where: { $0.alias == alias && $0.id == target.id }) {
            return .already("“\(alias)” opens \(target.title) already.")
        }
        var summary = "\(Self.pane(showing: "launcherAliases")): Aliases → “\(alias)” opens \(target.title) (\(target.kind))"
        if let taken = current.first(where: { $0.alias == alias }) { summary += "\nIt opened \(taken.title)" }
        if let previous = current.first(where: { $0.id == target.id }) { summary += "\nInstead of “\(previous.alias)”" }
        return Plan(summary: summary) { [weak self] in
            guard let self else { return "" }
            self.preferences.launcherAliases = LauncherAliases.setting(alias, id: target.id, title: target.title, in: self.preferences.launcherAliases)
            return "Done: “\(alias)” then a space opens \(target.title)."
        }
    }

    private func prepareRemoveAlias(_ arguments: [String: Any]) throws -> Plan {
        let alias = LauncherAliases.normalized(try Self.text("alias", in: arguments))
        guard let found = preferences.launcherAliases.first(where: { $0.alias == alias }) else {
            let all = preferences.launcherAliases.map { "\($0.alias) (\($0.title))" }.joined(separator: ", ")
            throw Failure("No alias “\(alias)”. Aliases: \(all.isEmpty ? "none" : all).")
        }
        return Plan(summary: "\(Self.pane(showing: "launcherAliases")): Aliases − “\(alias)” (\(found.title))") { [weak self] in
            guard let self else { return "" }
            self.preferences.launcherAliases = LauncherAliases.setting("", id: found.id, title: found.title, in: self.preferences.launcherAliases)
            return "Done: the alias “\(alias)” is gone."
        }
    }

    // MARK: - Quicklinks

    private func quicklink(named name: String) throws -> Quicklink {
        let wanted = Self.folded(name)
        guard let link = quicklinks.links.first(where: { Self.folded($0.name) == wanted })
            ?? quicklinks.links.first(where: { !$0.keyword.isEmpty && Self.folded($0.keyword) == wanted }) else {
            throw Failure("No quicklink is named “\(name)”. Quicklinks: \(quicklinks.links.map(\.name).joined(separator: ", ")).")
        }
        return link
    }

    /// The quicklink editor's rules.
    private func check(_ link: Quicklink) throws {
        guard !link.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Failure("A quicklink needs a name.") }
        if link.keyword.contains(where: \.isWhitespace) { throw Failure("A keyword has no spaces.") }
        if !link.keyword.isEmpty, let other = quicklinks.links.first(where: { $0.keyword.lowercased() == link.keyword.lowercased() && $0.id != link.id }) {
            throw Failure("“\(link.keyword)” is \(other.name)'s keyword already.")
        }
        guard link.address(for: "test") != nil else { throw Failure("The address starts with https:// or http://.") }
    }

    /// "Jira (jira): https://…" for the card; without its address for the
    /// agent (`withAddress` false): an address the user kept is theirs.
    private static func describe(_ link: Quicklink, withAddress: Bool = true) -> String {
        "\(link.name)\(link.keyword.isEmpty ? "" : " (\(link.keyword))")" + (withAddress ? ": \(link.url)" : "")
    }

    private func prepareQuicklink(_ tool: String, _ arguments: [String: Any]) throws -> Plan {
        typealias Tool = SettingsTable.Tool
        let pane = Self.pane(showing: "quicklinks")
        var link: Quicklink
        let summary: String
        switch tool {
        case Tool.createQuicklink:
            let name = try Self.text("name", in: arguments).trimmingCharacters(in: .whitespaces)
            if let taken = try? quicklink(named: name), Self.folded(taken.name) == Self.folded(name) {
                throw Failure("A quicklink is named “\(taken.name)” already: update_quicklink changes it.")
            }
            link = Quicklink(name: name, keyword: (try Self.optional("keyword", in: arguments) ?? "").trimmingCharacters(in: .whitespaces),
                             url: try Self.text("url", in: arguments).trimmingCharacters(in: .whitespaces))
            try check(link)
            summary = "\(pane): Quicklinks + \(Self.describe(link))"
        case Tool.updateQuicklink:
            let old = try quicklink(named: try Self.text("name", in: arguments))
            link = old
            if let name = try Self.optional("new_name", in: arguments), !name.trimmingCharacters(in: .whitespaces).isEmpty {
                link.name = name.trimmingCharacters(in: .whitespaces)
            }
            if let url = try Self.optional("url", in: arguments), !url.trimmingCharacters(in: .whitespaces).isEmpty {
                link.url = url.trimmingCharacters(in: .whitespaces)
            }
            if let keyword = try Self.optional("keyword", in: arguments) { link.keyword = keyword.trimmingCharacters(in: .whitespaces) }
            guard link != old else { return .already("\(old.name) is so already.") }
            try check(link)
            summary = "\(pane): Quicklinks → \(Self.describe(link))\nNow: \(Self.describe(old))"
        default:
            link = try quicklink(named: try Self.text("name", in: arguments))
            return Plan(summary: "\(pane): Quicklinks − \(Self.describe(link))",
                        said: "\(pane): Quicklinks − \(Self.describe(link, withAddress: false))") { [weak self] in
                self?.quicklinks.delete(link.id)
                // Its shortcuts with it, as Settings deletes them.
                self?.shortcuts.removeEntries(for: .quicklink(link.id))
                Self.notify("quicklinks")
                return "Done: the quicklink \(link.name) is gone."
            }
        }
        let said = "\(pane): Quicklinks \(tool == Tool.createQuicklink ? "+" : "→") \(Self.describe(link, withAddress: false))"
        return Plan(summary: summary, said: said) { [weak self] in
            self?.quicklinks.save(link)
            Self.notify("quicklinks")
            return "Done: \(said)."
        }
    }

    private static func notify(_ key: String) {
        NotificationCenter.default.post(name: changed, object: key)
    }

    // MARK: - Asks on a schedule

    /// The id agents name one by: its first eight characters.
    private static func shortID(_ ask: ScheduledAsk) -> String {
        String(ask.id.uuidString.prefix(8)).lowercased()
    }

    /// One scheduled ask by its id, what it asks or its when.
    private func scheduledAsk(_ text: String, in scheduler: AskScheduler) throws -> ScheduledAsk {
        let wanted = Self.folded(text)
        let all = scheduler.asks
        let listed = all.isEmpty ? "none" : all.map { "\(Self.shortID($0)) \($0.spoken)" }.joined(separator: "; ")
        if wanted.count >= 4, let byID = all.first(where: { $0.id.uuidString.lowercased().hasPrefix(wanted) }) { return byID }
        if let exact = all.first(where: { Self.folded($0.ask) == wanted || Self.folded($0.spoken) == wanted }) { return exact }
        let close = all.filter { Self.folded($0.ask).contains(wanted) || Self.folded($0.schedule.spoken) == wanted }
        if close.count == 1 { return close[0] }
        throw Failure(close.count > 1 ? "Several asks on a schedule fit “\(text)”: give its id. Now: \(listed)."
                                      : "No ask on a schedule fits “\(text)”. Now: \(listed).")
    }

    private func prepareScheduledAsk(_ tool: String, _ arguments: [String: Any]) throws -> Plan {
        typealias Tool = SettingsTable.Tool
        guard let scheduler else { throw Failure("The asks on a schedule cannot be reached now.") }
        let label = "\(Self.pane(showing: "scheduledAsks")) → On a Schedule"
        switch tool {
        case Tool.addScheduledAsk:
            let when = try Self.text("when", in: arguments)
            guard let schedule = AskSchedule.when(when) else {
                throw Failure("“\(when)” is not a schedule skil.li reads. Say it as: every Monday at 9:00, every weekday at 8:30, every day at 18:00, every month on the 1st at 9:00, tous les lundis à 9h.")
            }
            var ask = try Self.text("ask", in: arguments).trimmingCharacters(in: .whitespacesAndNewlines)
            // The time said again in what is asked: the ask alone.
            if let (again, rest) = AskSchedule.read(ask), again == schedule { ask = rest }
            let line = "\(schedule.spoken): \(ask)"
            if scheduler.asks.contains(where: { $0.schedule.spoken == schedule.spoken && Self.folded($0.ask) == Self.folded(ask) }) {
                return .already("\(line) is on the schedule already.")
            }
            let first = schedule.next(after: .now).map { ScheduledAsks.moment($0) }
            return Plan(summary: "\(label) + \(line)" + (first.map { "\nFirst: \($0)" } ?? ""), said: "\(label) + \(line)") {
                scheduler.add(ask, schedule: schedule)
                Self.notify("scheduledAsks")
                return "Done: \(line)." + (first.map { " First run: \($0)." } ?? "")
            }
        case Tool.pauseScheduledAsk:
            let found = try scheduledAsk(try Self.text("ask", in: arguments), in: scheduler)
            let paused = try Self.optional("paused", in: arguments).map { !["false", "no", "off", "0", "non"].contains(Self.folded($0)) } ?? true
            guard found.isOn == paused else { return .already("\(found.spoken) is \(paused ? "paused" : "on") already.") }
            let summary = "\(label): \(found.spoken) → \(paused ? "Paused" : "On")"
            return Plan(summary: summary) {
                scheduler.setOn(found.id, !paused)
                Self.notify("scheduledAsks")
                return "Done: \(summary)."
            }
        default:
            let found = try scheduledAsk(try Self.text("ask", in: arguments), in: scheduler)
            return Plan(summary: "\(label) − \(found.spoken)") {
                scheduler.remove(found.id)
                Self.notify("scheduledAsks")
                return "Done: \(found.spoken) is gone."
            }
        }
    }

    // MARK: - Snippets

    private func snippet(named name: String) throws -> Snippet {
        let all = snippets.all
        let wanted = Self.folded(name)
        guard let found = all.first(where: { Self.folded($0.name) == wanted })
            ?? all.first(where: { !$0.keyword.isEmpty && $0.keyword == name.trimmingCharacters(in: .whitespaces) }) else {
            throw Failure("No snippet is named “\(name)”. Snippets: \(all.isEmpty ? "none" : all.map(\.name).joined(separator: ", ")).")
        }
        return found
    }

    /// The snippet editor's rules.
    private func check(_ snippet: Snippet) throws {
        guard !snippet.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Failure("A snippet needs a name.") }
        guard !snippet.text.isEmpty else { throw Failure("A snippet needs a text.") }
        let keyword = snippet.keyword
        if keyword.contains(where: \.isWhitespace) { throw Failure("A keyword has no spaces.") }
        if !keyword.isEmpty, keyword.count < 2 { throw Failure("A keyword has at least two characters.") }
        if !keyword.isEmpty, let other = snippets.all.first(where: { $0.keyword == keyword && $0.id != snippet.id }) {
            throw Failure("“\(keyword)” is \(other.name)'s keyword already.")
        }
    }

    /// "Address (;addr): 12 rue…" for the card; its name and keyword only
    /// for the agent (`withText` false): a snippet's text is the user's.
    private static func describe(_ snippet: Snippet, withText: Bool = true) -> String {
        "\(snippet.name)\(snippet.keyword.isEmpty ? "" : " (\(snippet.keyword))")"
            + (withText ? ": \(ClipboardSearch.title(of: snippet.text, limit: 60))" : "")
    }

    private func prepareSnippet(_ tool: String, _ arguments: [String: Any]) throws -> Plan {
        typealias Tool = SettingsTable.Tool
        let pane = Self.pane(showing: "snippets")
        var snippet: Snippet
        let summary: String
        switch tool {
        case Tool.createSnippet:
            let name = try Self.text("name", in: arguments).trimmingCharacters(in: .whitespaces)
            if let taken = try? self.snippet(named: name), Self.folded(taken.name) == Self.folded(name) {
                throw Failure("A snippet is named “\(taken.name)” already: update_snippet changes it.")
            }
            snippet = Snippet(id: "", name: name, keyword: (try Self.optional("keyword", in: arguments) ?? "").trimmingCharacters(in: .whitespaces),
                              text: try Self.text("text", in: arguments))
            try check(snippet)
            summary = "\(pane) + \(Self.describe(snippet))"
        case Tool.updateSnippet:
            let old = try self.snippet(named: try Self.text("name", in: arguments))
            snippet = old
            if let name = try Self.optional("new_name", in: arguments), !name.trimmingCharacters(in: .whitespaces).isEmpty {
                snippet.name = name.trimmingCharacters(in: .whitespaces)
            }
            if let text = try Self.optional("text", in: arguments), !text.isEmpty { snippet.text = text }
            if let keyword = try Self.optional("keyword", in: arguments) { snippet.keyword = keyword.trimmingCharacters(in: .whitespaces) }
            guard snippet != old else { return .already("\(old.name) is so already.") }
            try check(snippet)
            summary = "\(pane) → \(Self.describe(snippet))\nNow: \(Self.describe(old))"
        default:
            snippet = try self.snippet(named: try Self.text("name", in: arguments))
            return Plan(summary: "\(pane) − \(Self.describe(snippet))", said: "\(pane) − \(Self.describe(snippet, withText: false))") { [weak self] in
                self?.snippets.delete(snippet.id)
                self?.shortcuts.removeEntries(for: .snippet(snippet.id))
                Self.notify("snippets")
                return "Done: the snippet \(snippet.name) is gone."
            }
        }
        let said = "\(pane) \(tool == Tool.createSnippet ? "+" : "→") \(Self.describe(snippet, withText: false))"
        return Plan(summary: summary, said: said) { [weak self] in
            guard let self else { return "" }
            _ = self.snippets.save(snippet)
            Self.notify("snippets")
            return "Done: \(said)."
        }
    }

    // MARK: - Shortcuts

    /// "✦ K › U".
    private static func shown(_ chords: [Chord]) -> String {
        chords.map(\.description).joined(separator: " › ")
    }

    private static let openSettingsTitle = "Open Settings from the launcher"

    private func keys(_ name: String, in arguments: [String: Any]) throws -> [Chord] {
        let text = try Self.text(name, in: arguments)
        guard let chords = try? Chord.sequence(said: text) else {
            throw Failure("“\(text)” is not keys skil.li reads: hyper+y, cmd+shift+k, or a chain hyper+k y.")
        }
        guard chords.count <= ShortcutStore.maxChords else { throw Failure("A shortcut has \(ShortcutStore.maxChords) keys at most.") }
        return chords
    }

    /// The store's rules (`ShortcutStore.validated`): a modifier first, no
    /// shortcut equal to or starting another, no key macOS or the launcher
    /// answers.
    private func checkKeys(_ chords: [Chord], for id: String?, action: SkilliAction? = nil) throws {
        do {
            _ = try shortcuts.validated(chords, for: id, action: action)
        } catch ShortcutError.needsModifier {
            throw Failure(ShortcutError.needsModifier.errorDescription ?? "")
        } catch let error as ShortcutError {
            throw Failure("\(Self.shown(chords)): \(error.errorDescription ?? "")")
        }
    }

    /// The shortcut with these keys: an entry's id and title, or the
    /// launcher's own ⌘,.
    private func shortcut(with chords: [Chord]) throws -> (id: String, title: String) {
        let chain = Chord.chain(chords)
        if let entry = shortcuts.config.shortcuts.first(where: { $0.chords.map(Chord.chain) == chain }) { return (entry.id, entry.title) }
        if let chord = shortcuts.launcherOpenSettingsChord, [chord] == chords { return (ShortcutStore.launcherOpenSettingsID, Self.openSettingsTitle) }
        throw Failure("No shortcut is \(Self.shown(chords)). get_settings lists them under Keys.")
    }

    /// The action `text` names: its id, its name, or an app's name.
    private func action(_ text: String) throws -> SkilliAction {
        let actions = shortcutActions()
        if let action = SkilliAction(id: text.trimmingCharacters(in: .whitespaces)) {
            if actions.contains(where: { $0.action == action }) { return action }
            // An app by its id ("app:/…"), as a name both an app and a command say.
            if case .openApp(let path) = action, FileManager.default.fileExists(atPath: path) { return action }
        }
        let wanted = Self.folded(text)
        // "SI · Fix" is also "Fix"; "Window Layout · Coding" also "Coding".
        func plain(_ title: String) -> String {
            Self.folded(title.components(separatedBy: " · ").last ?? title)
        }
        var exact = actions.filter { Self.folded($0.title) == wanted }
        if exact.isEmpty { exact = actions.filter { plain($0.title) == wanted } }
        // "Calendar" is skil.li's command and the app: neither is guessed.
        if exact.count == 1, let app = findApp(text), Self.folded(app.deletingPathExtension().lastPathComponent) == wanted {
            throw Failure("Two are named “\(text)”: \(exact[0].title) (\(exact[0].action.id)) and the app (\(SkilliAction.openApp(app.path).id)). Pass its id.")
        }
        if exact.count == 1 { return exact[0].action }
        if exact.isEmpty, let app = findApp(text) { return .openApp(app.path) }
        if exact.count > 1 {
            throw Failure("Several actions are named “\(text)”: \(exact.map { "\($0.title) (\($0.action.id))" }.joined(separator: ", ")). Pass its id.")
        }
        let close = actions.filter { $0.title.localizedCaseInsensitiveContains(text) }.prefix(12)
        throw Failure("No action or app is named “\(text)”." + (close.isEmpty ? "" : " Close: \(close.map(\.title).joined(separator: ", "))."))
    }

    private func prepareShortcut(_ tool: String, _ arguments: [String: Any]) throws -> Plan {
        typealias Tool = SettingsTable.Tool
        let pane = Self.pane(showing: "shortcuts")
        switch tool {
        case Tool.addShortcut:
            let actionText = try Self.text("action", in: arguments)
            let chords = try keys("keys", in: arguments)
            if [Self.folded(Self.openSettingsTitle), Self.folded(ShortcutStore.launcherOpenSettingsID)].contains(Self.folded(actionText)) {
                guard chords.count == 1 else { throw Failure("\(Self.openSettingsTitle) takes one key, like cmd+,.") }
                try checkKeys(chords, for: ShortcutStore.launcherOpenSettingsID)
                return Plan(summary: "\(pane): \(Self.shown(chords)) → \(Self.openSettingsTitle)") { [weak self] in
                    try self?.shortcuts.setKeys(chords, for: ShortcutStore.launcherOpenSettingsID)
                    return "Done: \(Self.shown(chords)) opens Settings from the launcher."
                }
            }
            let action = try action(actionText)
            if shortcuts.config.shortcuts.contains(where: { $0.action == action && $0.chords.map(Chord.chain) == Chord.chain(chords) }) {
                return .already("\(Self.shown(chords)) runs \(action.title) already.")
            }
            try checkKeys(chords, for: nil, action: action)
            let empty = shortcuts.config.shortcuts.first { $0.action == action && $0.keys == nil }
            let title = empty?.title ?? shortcutActions().first { $0.action == action }?.title ?? action.title
            return Plan(summary: "\(pane): \(Self.shown(chords)) → \(title)") { [weak self] in
                guard let self else { return "" }
                if let empty {
                    try self.shortcuts.setKeys(chords, for: empty.id)
                } else {
                    let id = self.shortcuts.add(action)
                    do {
                        try self.shortcuts.setKeys(chords, for: id)
                    } catch {
                        self.shortcuts.remove(id)
                        throw error
                    }
                }
                return "Done: \(Self.shown(chords)) runs \(title)."
            }
        case Tool.changeShortcut:
            let chords = try keys("keys", in: arguments)
            let found = try shortcut(with: chords)
            let new = try keys("new_keys", in: arguments)
            guard Chord.chain(new) != Chord.chain(chords) else { return .already("\(found.title) is \(Self.shown(chords)) already.") }
            if found.id == ShortcutStore.launcherOpenSettingsID, new.count != 1 {
                throw Failure("\(Self.openSettingsTitle) takes one key, like cmd+,.")
            }
            try checkKeys(new, for: found.id)
            return Plan(summary: "\(pane): \(found.title) \(Self.shown(chords)) → \(Self.shown(new))") { [weak self] in
                try self?.shortcuts.setKeys(new, for: found.id)
                return "Done: \(found.title) is \(Self.shown(new))."
            }
        default:
            let chords = try keys("keys", in: arguments)
            let found = try shortcut(with: chords)
            return Plan(summary: "\(pane): − \(Self.shown(chords)) (\(found.title))") { [weak self] in
                self?.shortcuts.clear(found.id)
                return "Done: \(Self.shown(chords)) runs nothing now."
            }
        }
    }

    // MARK: - Bindings

    /// What each table key reads and writes, built once.
    private(set) lazy var bindings: [String: Binding] = makeBindings()

    private func toggle(_ path: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding {
        Binding(get: { [unowned self] in .bool(self.preferences[keyPath: path]) },
                set: { [unowned self] value in
                    guard case .bool(let on) = value else { throw Failure("On or off: true or false.") }
                    self.preferences[keyPath: path] = on
                })
    }

    private func choice<Value: RawRepresentable>(_ path: ReferenceWritableKeyPath<Preferences, Value>) -> Binding where Value.RawValue == String {
        Binding(get: { [unowned self] in .text(self.preferences[keyPath: path].rawValue) },
                set: { [unowned self] value in
                    guard case .text(let raw) = value, let chosen = Value(rawValue: raw) else { throw Failure("Not one of its values.") }
                    self.preferences[keyPath: path] = chosen
                })
    }

    private func number(_ path: ReferenceWritableKeyPath<Preferences, Int>) -> Binding {
        Binding(get: { [unowned self] in .text(String(self.preferences[keyPath: path])) },
                set: { [unowned self] value in
                    guard case .text(let raw) = value, let chosen = Int(raw) else { throw Failure("Not one of its values.") }
                    self.preferences[keyPath: path] = chosen
                })
    }

    private func string(_ path: ReferenceWritableKeyPath<Preferences, String>) -> Binding {
        Binding(get: { [unowned self] in .text(self.preferences[keyPath: path]) },
                set: { [unowned self] value in
                    guard case .text(let text) = value else { throw Failure("A text.") }
                    self.preferences[keyPath: path] = text
                })
    }

    /// A choice the pane makes among what this Mac has.
    private func string(_ path: ReferenceWritableKeyPath<Preferences, String>, options: @escaping @MainActor () async -> [SettingOption]) -> Binding {
        var binding = string(path)
        binding.options = options
        return binding
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Apps left out, by bundle id, as the pane's Add App… keeps them.
    private func apps(_ path: ReferenceWritableKeyPath<Preferences, [String]>) -> Binding {
        var binding = Binding(get: { [unowned self] in .list(self.preferences[keyPath: path].map(Self.appName)) })
        binding.add = { [unowned self] text in
            let bundleID: String
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: text) != nil {
                bundleID = text
            } else if let url = self.findApp(text), let id = Bundle(url: url)?.bundleIdentifier {
                bundleID = id
            } else {
                throw Failure("No app named “\(text)” on this Mac.")
            }
            let name = Self.appName(bundleID)
            if self.preferences[keyPath: path].contains(bundleID) { return ListChange(item: name, unchanged: true) }
            return ListChange(item: name) { [unowned self] in
                if !self.preferences[keyPath: path].contains(bundleID) { self.preferences[keyPath: path].append(bundleID) }
            }
        }
        binding.remove = { [unowned self] text in
            let wanted = Self.folded(text)
            guard let bundleID = self.preferences[keyPath: path].first(where: { $0 == text || Self.folded(Self.appName($0)) == wanted }) else {
                throw Failure("“\(text)” is not in the list. Now: \(self.preferences[keyPath: path].map(Self.appName).joined(separator: ", ")).")
            }
            return ListChange(item: Self.appName(bundleID)) { [unowned self] in
                self.preferences[keyPath: path].removeAll { $0 == bundleID }
            }
        }
        return binding
    }

    private func makeBindings() -> [String: Binding] {
        var bindings: [String: Binding] = [:]

        // General
        let login = Binding(get: { [unowned self] in
            self.loginItem.refresh()
            return .bool(self.loginItem.isEnabled)
        }, set: { [unowned self] value in
            guard case .bool(let on) = value else { return }
            self.loginItem.setEnabled(on)
            Self.notify("openAtLogin")
            if let error = self.loginItem.error { throw Failure(error) }
        })
        bindings["openAtLogin"] = login
        bindings["showMenuBarIcon"] = toggle(\.showMenuBarIcon)
        bindings["glassStyle"] = choice(\.glassStyle)
        bindings["launcherPlace"] = Binding(get: { [unowned self] in .text(self.preferences.launcherPlace == nil ? "default" : "moved") },
                                            set: { [unowned self] _ in self.preferences.launcherPlace = nil })

        // Keys
        bindings["hyperTapSendsEscape"] = toggle(\.hyperTapSendsEscape)
        var keys = Binding(get: { [unowned self] in .list(self.shortcutRows().map { "\($0.keys): \($0.runs)" }) })
        keys.items = { [unowned self] in
            self.shortcutRows().map { row in
                // An id with a path (a project's folder, a skillie's file) says more than a setting.
                var fields = ["keys": row.spec, "shown": row.keys, "runs": row.runs]
                if !row.action.contains("/") { fields["action"] = row.action }
                return SettingItem(fields)
            }
        }
        bindings["shortcuts"] = keys

        // Privacy
        bindings["permissions"] = Binding(get: { [unowned self] in
            .list(Permission.allCases.map { permission in
                let state = self.permissions?.state(permission)
                return "\(permission.title): \(state == .granted ? "on" : "off")"
            })
        })

        // Backup
        bindings["backupFolder"] = string(\.backupFolder)
        bindings["backupSchedule"] = choice(\.backupSchedule)
        bindings["backupKeep"] = number(\.backupKeep)

        // Launcher
        bindings["launcherScreen"] = choice(\.launcherScreen)
        bindings["launcherReset"] = choice(\.launcherReset)
        bindings["historyMeaningSearch"] = toggle(\.historyMeaningSearch)
        bindings["emojiSkinTone"] = choice(\.emojiSkinTone)
        bindings["emojiMeaningSearch"] = toggle(\.emojiMeaningSearch)
        bindings["launcherEnglishInput"] = toggle(\.launcherEnglishInput)
        bindings["quicklinkReuseTab"] = toggle(\.quicklinkReuseTab)
        bindings["fileMeaningSearch"] = toggle(\.fileMeaningSearch)
        var links = Binding(get: { [unowned self] in .list(self.quicklinks.links.map { Self.describe($0) }) })
        links.items = { [unowned self] in
            self.quicklinks.links.map { SettingItem(["name": $0.name, "keyword": $0.keyword], content: "address", $0.url) }
        }
        bindings["quicklinks"] = links
        bindings["catalogOff"] = catalogOff()
        bindings["skilliesInMenuBar"] = skilliesInMenuBar()
        var aliases = Binding(get: { [unowned self] in .list(self.preferences.launcherAliases.map { "\($0.alias): \($0.title)" }) })
        aliases.items = { [unowned self] in self.preferences.launcherAliases.map { SettingItem(["alias": $0.alias, "item": $0.title]) } }
        bindings["launcherAliases"] = aliases
        // Read here, changed only by Always in a link's card and the pane.
        bindings["trustedLinks"] = Binding(get: { [unowned self] in .list(self.toolSettings.linkTrust.byTitle.map(\.shown)) })

        // Clipboard
        bindings["clipboardHistory"] = toggle(\.clipboardHistory)
        bindings["clipboardRetention"] = Binding(get: { [unowned self] in .text(self.preferences.clipboardRetention.rawValue) },
                                                 set: { [unowned self] value in
                                                     guard case .text(let raw) = value else { return }
                                                     // As the pane does: nothing goes now; older
                                                     // copies go on the hourly pass.
                                                     self.preferences.clipboardRetention = ClipboardRetention(rawValue: raw)
                                                 })
        bindings["clipboardScreenshots"] = toggle(\.clipboardScreenshots)
        bindings["clipboardOCR"] = toggle(\.clipboardOCR)
        bindings["imageTagsClipboard"] = toggle(\.imageTagsClipboard)
        bindings["imageTagsFolder"] = toggle(\.imageTagsFolder)
        bindings["imageTagsFolderPath"] = Binding(get: { [unowned self] in .text(self.preferences.imageTagsFolderPath) },
                                                  set: { [unowned self] value in
                                                      guard case .text(let path) = value else { return }
                                                      // As the pane keeps it: macOS's own folder is the default.
                                                      self.preferences.imageTagsFolderPath = path == ImageFolderWatcher.screenshotsFolder.path ? "" : path
                                                  })
        bindings["clipboardMeaningSearch"] = toggle(\.clipboardMeaningSearch)
        bindings["clipboardLinkPreviews"] = toggle(\.clipboardLinkPreviews)
        bindings["clipboardExcludedApps"] = apps(\.clipboardExcludedApps)

        // Snippets
        bindings["snippetExpansion"] = toggle(\.snippetExpansion)
        bindings["snippetExpansionMode"] = choice(\.snippetExpansionMode)
        bindings["snippetMeaningSearch"] = toggle(\.snippetMeaningSearch)
        bindings["snippetExcludedApps"] = apps(\.snippetExcludedApps)
        var snippetList = Binding(get: { [unowned self] in .list(self.snippets.all.map { Self.describe($0) }) })
        snippetList.items = { [unowned self] in
            self.snippets.all.map { SettingItem(["name": $0.name, "keyword": $0.keyword], content: "text", $0.text) }
        }
        bindings["snippets"] = snippetList

        // Windows
        bindings["windowGap"] = number(\.windowGap)
        bindings["autoQuit"] = toggle(\.autoQuit)
        bindings["autoQuitMinutes"] = number(\.autoQuitMinutes)
        bindings["autoQuitNever"] = apps(\.autoQuitNever)
        bindings["windowLayoutIgnoredApps"] = apps(\.windowLayoutIgnoredApps)
        var monitors = Binding(get: { [unowned self] in .list(self.preferences.ignoredMonitors.map(\.name)) })
        monitors.remove = { [unowned self] text in
            guard let monitor = self.preferences.ignoredMonitors.first(where: { Self.folded($0.name) == Self.folded(text) }) else {
                throw Failure("No monitor named “\(text)” is ignored. Ignored: \(self.preferences.ignoredMonitors.map(\.name).joined(separator: ", ")).")
            }
            return ListChange(item: monitor.name) { [unowned self] in
                self.preferences.ignoredMonitors.removeAll { $0.isSameDisplay(as: monitor) }
            }
        }
        bindings["ignoredMonitors"] = monitors
        bindings["windowLayouts"] = Binding(get: { [unowned self] in .list(self.windowLayouts()) })

        // Calendar
        bindings["agendaLauncherMinutes"] = number(\.agendaLauncherMinutes)
        bindings["agendaMenuBar"] = choice(\.agendaMenuBar)
        bindings["agendaMenuBarCallsOnly"] = toggle(\.agendaMenuBarCallsOnly)
        bindings["agendaCountdown"] = toggle(\.agendaCountdown)
        bindings["agendaHideAfter"] = number(\.agendaHideAfter)
        bindings["agendaNextDuringMeeting"] = toggle(\.agendaNextDuringMeeting)
        bindings["agendaAlerts"] = alerts()
        bindings["agendaAlertWithoutCall"] = toggle(\.agendaAlertWithoutCall)
        bindings["agendaAutoJoin"] = choice(\.agendaAutoJoin)
        bindings["agendaApp"] = string(\.agendaApp) {
            AgendaPane.installedCalendarApps.map { SettingOption($0.id, $0.name) }
        }
        bindings["agendaMeetBrowser"] = string(\.agendaMeetBrowser) {
            [SettingOption("", "Default browser")] + AgendaPane.browsers().map { SettingOption($0.id, $0.name) }
        }
        bindings["agendaHiddenCalendars"] = hiddenCalendars()

        // Recorder
        bindings["recorderMeetingCard"] = toggle(\.recorderMeetingCard)
        bindings["recorderMicrophone"] = toggle(\.recorderMicrophone)
        bindings["recorderMacSound"] = toggle(\.recorderMacSound)
        bindings["recorderLanguage"] = string(\.recorderLanguage) {
            [SettingOption("", "As Ask")] + (await MeetingTranscriber.languages()).map { SettingOption($0.id, $0.name) }
        }
        bindings["recorderFolderPath"] = Binding(get: { [unowned self] in .text(self.preferences.recorderFolderPath) },
                                                 set: { [unowned self] value in
                                                     guard case .text(let path) = value else { return }
                                                     // As the pane does: the recordings move there.
                                                     let folder = path.isEmpty ? Recordings.standard : URL(fileURLWithPath: path, isDirectory: true)
                                                     if let refused = self.moveRecordings(folder) { throw Failure(refused) }
                                                 })
        bindings["recorderRetention"] = Binding(get: { [unowned self] in .text(self.preferences.recorderRetention.rawValue) },
                                                set: { [unowned self] value in
                                                    guard case .text(let raw) = value else { return }
                                                    // As the pane does: nothing goes now; expired
                                                    // recordings go on the hourly pass.
                                                    self.preferences.recorderRetention = RecordingRetention(rawValue: raw)
                                                })

        // Reminders
        bindings["remindersDefaultList"] = string(\.remindersDefaultList) { [unowned self] in
            [SettingOption("", "The Reminders app's default list")] + self.reminderLists().map { SettingOption($0, $0) }
        }
        bindings["remindersMenuBar"] = choice(\.remindersMenuBar)
        bindings["reminderPlaces"] = places()

        // GitHub
        bindings["githubUnderSearch"] = toggle(\.githubUnderSearch)
        bindings["relayPublicURL"] = string(\.relayPublicURL)
        bindings["githubAccount"] = Binding(get: { [unowned self] in
            // Signed in or not: who is the user's own.
            .text(self.github?.isSignedIn == true ? "Signed in" : "Not signed in")
        })
        bindings["relayToken"] = secret { [unowned self] in self.github?.hasRelayToken == true }

        // Apps
        bindings["cleanShotTextLineBreaks"] = choice(\.cleanShotTextLineBreaks)

        // Your Details
        bindings["otherDetails"] = otherDetails()
        bindings["people"] = people()
        bindings["aboutYou"] = Binding(get: { .text(PromptLibrary.shared.profile) },
                                       set: { [unowned self] value in
                                           guard case .text(let text) = value else { return }
                                           // Through the pane's model when it is there: an open pane shows it.
                                           if let model = self.aiCommands {
                                               model.profile = text
                                               model.saveProfile()
                                           } else {
                                               PromptLibrary.shared.saveProfile(text)
                                           }
                                       })

        // Ask
        bindings["approvalMode"] = Binding(get: { [unowned self] in .text(self.toolSettings.mode.rawValue) })
        bindings["approvalRules"] = Binding(get: { [unowned self] in
            .list(ApprovalRules.active(self.toolSettings.rules).map { "\($0.effect.title): \($0.said)" })
        })
        bindings["keepClaudeReady"] = toggle(\.keepClaudeReady)
        bindings["voiceLanguage"] = string(\.voiceLanguage) { [unowned self] in
            let locales = await self.supportedVoiceLocales()
            let automatic = Locale.current.localizedString(forIdentifier: VoiceInput.keyboardLanguage ?? "") ?? "keyboard"
            return [SettingOption("", "Automatic (\(automatic))")]
                + locales.map { SettingOption($0, Locale.current.localizedString(forIdentifier: $0) ?? $0) }
        }
        bindings["handoffTarget"] = choice(\.handoffTarget)
        bindings["handoffTerminal"] = choice(\.handoffTerminal)
        bindings["askUsesClaudeCodeSkills"] = toggle(\.askUsesClaudeCodeSkills)
        bindings["skills"] = Binding(get: { [unowned self] in .list(self.agentSkills().map(\.name)) })
        var scheduled = Binding(get: { [unowned self] in .list(self.scheduler?.asks.map(\.spoken) ?? []) })
        scheduled.items = { [unowned self] in
            (self.scheduler?.asks ?? []).map { ask in
                SettingItem(["id": Self.shortID(ask), "when": ask.schedule.spoken, "ask": ask.ask, "on": ask.isOn ? "true" : "false"],
                            content: "last_answer", ask.lastAnswer ?? "")
            }
        }
        bindings["scheduledAsks"] = scheduled

        // Commands, Tools, Skillies: read here, changed elsewhere.
        bindings["commands"] = Binding(get: { .list(PromptLibrary.shared.all.map(\.title)) })
        bindings["toolRights"] = Binding(get: { [unowned self] in
            .list(self.toolSettings.overrides.sorted { $0.key < $1.key }.map { "\($0.key): \(ToolRights.word($0.value))" })
        })
        bindings["servers"] = Binding(get: { [unowned self] in .list(self.toolSettings.servers.map(\.name)) })
        bindings["customTools"] = Binding(get: { [unowned self] in .list(self.toolSettings.customTools.map(\.name)) })
        bindings["skillies"] = Binding(get: { [unowned self] in .list(self.skillies().map(\.title)) })

        // SI Accounts
        var model = Binding(get: { [unowned self] in .text(self.preferences.writingModel.id) },
                            set: { [unowned self] value in
                                guard case .text(let id) = value, let choice = ModelChoice(id: id) else { throw Failure("Not a model skil.li offers.") }
                                self.preferences.writingModel = choice
                            })
        model.options = { [unowned self] in self.writingModels() }
        model.check = { [unowned self] value in
            guard case .text(let id) = value, let choice = ModelChoice(id: id), let ai = self.ai else { return }
            if case .unavailable(let why, let how) = ai.availability(choice.provider) {
                throw Failure("\(choice.provider.title) can't write now (\(why.lowercased())): \(how).")
            }
        }
        bindings["writingModel"] = model
        bindings["aiEngineMode"] = choice(\.aiEngineMode)
        bindings["claudeSubscription"] = Binding(get: { [unowned self] in
            switch self.ai?.claudeStatus {
            case .signedIn(let plan)?: .text(plan.map { "Connected · \($0.capitalized)" } ?? "Connected")
            case .signedOut?: .text("Not signed in")
            case .notInstalled?: .text("Claude Code is not installed")
            case nil: .text("Not checked yet")
            }
        })
        bindings["chatGPTSubscription"] = Binding(get: { [unowned self] in
            switch self.ai?.codexStatus {
            case .signedIn?: .text("Connected")
            case .signedOut?: .text("Not signed in")
            case .notInstalled?: .text("Codex is not installed")
            case nil: .text("Not checked yet")
            }
        })
        bindings["claudeAPIKey"] = secret { [unowned self] in self.ai?.hasAPIKey == true }
        bindings["openAIKey"] = secret { [unowned self] in self.ai?.decisionKeys.contains(.openAI) == true }
        bindings["typeSafeKey"] = secret { [unowned self] in self.ai?.decisionKeys.contains(.typeSafe) == true }
        bindings["klipyKey"] = secret { [unowned self] in self.gifs?.ownKey != nil }
        return bindings
    }

    /// A key or a token: never read, only whether one is there.
    private func secret(_ isSet: @escaping @MainActor () -> Bool) -> Binding {
        var binding = Binding(get: { .text("") })
        binding.isSet = isSet
        return binding
    }

    /// Every shortcut, with its keys or none.
    private func shortcutRows() -> [(spec: String, keys: String, runs: String, action: String)] {
        var rows = shortcuts.config.shortcuts.map { entry in
            (entry.keys ?? "", entry.chords.map(Self.shown) ?? "none", entry.title, entry.action.id)
        }
        if let chord = shortcuts.launcherOpenSettingsChord {
            rows.append((chord.spec, chord.description, Self.openSettingsTitle, ShortcutStore.launcherOpenSettingsID))
        }
        return rows
    }

    /// What can write, each model at each effort it takes.
    private func writingModels() -> [SettingOption] {
        guard let ai else { return [] }
        var options: [SettingOption] = []
        for provider in WritingProvider.allCases {
            for offer in ai.models(provider) {
                let efforts: [ReasoningEffort?] = provider.hasEffort ? (offer.efforts.isEmpty ? [.low] : offer.efforts).map { Optional($0) } : [nil]
                for effort in efforts {
                    let choice = ModelChoice(provider: provider, model: offer.id, effort: effort)
                    options.append(SettingOption(choice.id, choice.label))
                }
            }
        }
        let current = preferences.writingModel
        if !options.contains(where: { $0.value == current.id }) { options.append(SettingOption(current.id, current.label)) }
        return options
    }

    private func supportedVoiceLocales() async -> [String] {
        if let voiceLocales { return voiceLocales }
        let locales = await SpeechTranscriber.supportedLocales.map(\.identifier)
            .sorted { (Locale.current.localizedString(forIdentifier: $0) ?? $0) < (Locale.current.localizedString(forIdentifier: $1) ?? $1) }
        voiceLocales = locales
        return locales
    }

    private func alerts() -> Binding {
        var binding = Binding(get: { [unowned self] in .list(self.preferences.agendaAlerts.map(\.spoken)) })
        binding.add = { [unowned self] text in
            guard let alert = MeetingAlert.parse(text) else {
                throw Failure("“\(text)” is not an alert: on time, or 1, 2, 5, 10, 15, 30 min or 1 hour before; add “screens dark” for the dark card.")
            }
            let alerts = self.preferences.agendaAlerts
            if alerts.contains(alert) { return ListChange(item: alert.spoken, unchanged: true) }
            return ListChange(item: alert.spoken) { [unowned self] in
                // One alert at a time of the meeting: another style changes it.
                if let index = self.preferences.agendaAlerts.firstIndex(where: { $0.minutes == alert.minutes }) {
                    self.preferences.agendaAlerts[index] = alert
                } else {
                    self.preferences.agendaAlerts.append(alert)
                }
            }
        }
        binding.remove = { [unowned self] text in
            guard let said = MeetingAlert.parse(text), let alert = self.preferences.agendaAlerts.first(where: { $0.minutes == said.minutes }) else {
                throw Failure("No such alert. Alerts: \(self.preferences.agendaAlerts.map(\.spoken).joined(separator: ", ")).")
            }
            return ListChange(item: alert.spoken) { [unowned self] in
                self.preferences.agendaAlerts.removeAll { $0.minutes == alert.minutes }
            }
        }
        return binding
    }

    /// Every calendar by its name; "Work (iCloud)" only when two share it
    /// (an account's name can be the user's address).
    private func calendars() -> [CalendarRow] {
        let all = calendarAccounts().flatMap { account in account.calendars.map { (id: $0.id, title: $0.title, account: account.name) } }
        let names = Dictionary(grouping: all, by: { Self.folded($0.title) }).mapValues(\.count)
        return all.map { calendar in
            (calendar.id, calendar.title, names[Self.folded(calendar.title), default: 0] > 1 ? "\(calendar.title) (\(calendar.account))" : calendar.title)
        }
    }

    private typealias CalendarRow = (id: String, title: String, shown: String)

    /// The calendar `text` names: "Work (iCloud)", or a name only one has.
    private static func find(_ text: String, among list: [CalendarRow]) throws -> CalendarRow {
        let wanted = folded(text)
        if let exact = list.first(where: { folded($0.shown) == wanted || $0.id == text }) { return exact }
        let named = list.filter { folded($0.title) == wanted }
        if named.count == 1 { return named[0] }
        if named.count > 1 { throw Failure("Several calendars are named “\(text)”: \(named.map(\.shown).joined(separator: ", ")).") }
        throw Failure("No calendar is named “\(text)”. Calendars: \(list.map(\.shown).joined(separator: ", ")).")
    }

    /// The hidden calendars, by what the pane shows (an account away: its id).
    private func hidden() -> [CalendarRow] {
        let all = calendars()
        return preferences.agendaHiddenCalendars.map { id in all.first { $0.id == id } ?? (id, id, id) }
    }

    private func hiddenCalendars() -> Binding {
        var binding = Binding(get: { [unowned self] in .list(self.hidden().map(\.shown)) })
        binding.add = { [unowned self] text in
            let calendar = try Self.find(text, among: self.calendars())
            if self.preferences.agendaHiddenCalendars.contains(calendar.id) { return ListChange(item: calendar.shown, unchanged: true) }
            return ListChange(item: calendar.shown) { [unowned self] in
                self.preferences.agendaHiddenCalendars = Set(self.preferences.agendaHiddenCalendars + [calendar.id]).sorted()
            }
        }
        binding.remove = { [unowned self] text in
            let calendar = try Self.find(text, among: self.hidden())
            return ListChange(item: calendar.shown) { [unowned self] in
                self.preferences.agendaHiddenCalendars.removeAll { $0 == calendar.id }
            }
        }
        return binding
    }

    /// Settings → Catalog's "Show in search", one entry at a time: the
    /// entries turned off, by their names.
    private func skilliesInMenuBar() -> Binding {
        func inline() -> [ScriptCommand] { skillies().filter { $0.mode == .inline && $0.arguments.isEmpty } }
        func find(_ text: String, among commands: [ScriptCommand]) throws -> ScriptCommand {
            let wanted = Self.folded(text)
            if let command = commands.first(where: { Self.folded($0.title) == wanted || $0.path == text }) { return command }
            let names = commands.map(\.title)
            throw Failure("No inline skillie is named “\(text)”." + (names.isEmpty ? " None shows a line: one says “@skilli.mode inline”." : " Inline ones: \(names.joined(separator: ", "))."))
        }
        var binding = Binding(get: { [unowned self] in
            let all = self.skillies()
            return .list(self.preferences.skilliesInMenuBar.map { path in all.first { $0.path == path }?.title ?? (path as NSString).lastPathComponent })
        })
        binding.add = { [unowned self] text in
            let command = try find(text, among: inline())
            if self.preferences.skilliesInMenuBar.contains(command.path) { return ListChange(item: command.title, unchanged: true) }
            return ListChange(item: command.title) { [unowned self] in self.preferences.skilliesInMenuBar.append(command.path) }
        }
        binding.remove = { [unowned self] text in
            let shown = self.skillies().filter { self.preferences.skilliesInMenuBar.contains($0.path) }
            let command = try find(text, among: shown)
            return ListChange(item: command.title) { [unowned self] in self.preferences.skilliesInMenuBar.removeAll { $0 == command.path } }
        }
        return binding
    }

    private func catalogOff() -> Binding {
        func name(_ id: String, among entries: [CatalogEntry]) -> String { entries.first { $0.id == id }?.title ?? id }
        func find(_ text: String, among entries: [CatalogEntry]) throws -> CatalogEntry {
            let wanted = Self.folded(text)
            let named = entries.filter { Self.folded($0.title) == wanted || $0.id == text }
            if named.count == 1 { return named[0] }
            if named.count > 1 {
                throw Failure("Several entries are named “\(text)”: \(named.map { "\($0.title) (\($0.group.title))" }.joined(separator: ", ")).")
            }
            let close = entries.filter { $0.title.localizedCaseInsensitiveContains(text) }.prefix(10).map(\.title)
            throw Failure("No entry of the Catalog is named “\(text)”." + (close.isEmpty ? "" : " Close: \(close.joined(separator: ", "))."))
        }
        var binding = Binding(get: { [unowned self] in
            let entries = self.catalogEntries()
            return .list(self.preferences.catalogOff.sorted().map { name($0, among: entries) })
        })
        binding.add = { [unowned self] text in
            let entry = try find(text, among: self.catalogEntries())
            guard entry.canBeOff else {
                throw Failure("\(entry.title) has no row in the launcher's results to take out (Settings → Catalog shows no switch for it).")
            }
            if self.preferences.catalogOff.contains(entry.id) { return ListChange(item: entry.title, unchanged: true) }
            return ListChange(item: entry.title) { [unowned self] in self.preferences.catalogOff.insert(entry.id) }
        }
        binding.remove = { [unowned self] text in
            let entries = self.catalogEntries()
            let off = self.preferences.catalogOff.map { id in entries.first { $0.id == id } }.compactMap { $0 }
            let entry = try find(text, among: off)
            return ListChange(item: entry.title) { [unowned self] in self.preferences.catalogOff.remove(entry.id) }
        }
        return binding
    }

    private func places() -> Binding {
        var binding = Binding(get: { [unowned self] in .list(self.preferences.reminderPlaces.map { "\($0.name): \($0.address)" }) })
        // Their names; an address is the user's own.
        binding.items = { [unowned self] in
            self.preferences.reminderPlaces.map { SettingItem(["name": $0.name], content: "address", $0.address) }
        }
        binding.add = { [unowned self] text in
            guard let colon = text.firstIndex(of: ":") else { throw Failure("A place is said “Name: address”, like “Bureau: 12 rue de la Paix, Paris”.") }
            let name = text[..<colon].trimmingCharacters(in: .whitespaces)
            let address = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !address.isEmpty else { throw Failure("A place needs a name and an address: “Bureau: 12 rue de la Paix, Paris”.") }
            if let taken = self.preferences.reminderPlaces.first(where: { Self.folded($0.name) == Self.folded(name) }) {
                throw Failure("A place is named “\(taken.name)” already: remove it first.")
            }
            guard let found = await self.geocode(address) else { throw Failure("Apple Maps found no place at “\(address)”.") }
            return ListChange(item: "\(name): \(address)") { [unowned self] in
                self.preferences.reminderPlaces.append(SavedPlace(name: name, address: address, latitude: found.latitude, longitude: found.longitude))
            }
        }
        binding.remove = { [unowned self] text in
            let wanted = Self.folded(text.components(separatedBy: ":").first ?? text)
            guard let place = self.preferences.reminderPlaces.first(where: { Self.folded($0.name) == wanted }) else {
                throw Failure("No place is named “\(text)”. Places: \(self.preferences.reminderPlaces.map(\.name).joined(separator: ", ")).")
            }
            return ListChange(item: place.name, card: "\(place.name): \(place.address)") { [unowned self] in
                self.preferences.reminderPlaces.removeAll { $0.id == place.id }
            }
        }
        return binding
    }

    /// Fields whose values belong in the Keychain, never in a tool's hands.
    private static func isSensitive(_ label: String) -> Bool {
        let folded = Self.folded(label)
        if FormProfile.suggestedFields.contains(where: { $0.sensitive && Self.folded($0.label) == folded }) { return true }
        return ["password", "mot de passe", "passcode", "pin", "cvv", "cvc", "card number", "numero de carte", "iban", "securite sociale",
                "social security", "passport", "passeport"].contains { folded.contains($0) }
    }

    private func otherDetails() -> Binding {
        func shown(_ extra: FormExtra) -> String {
            extra.isSensitive ? "\(extra.label): \(FormSecrets.value(of: extra)?.isEmpty == false ? "set" : "not set") (in the Keychain)"
                : "\(extra.label): \(extra.value)"
        }
        var binding = Binding(get: { [unowned self] in .list(self.preferences.formProfiles.mine.map(shown)) })
        // Which fields there are; their values are the user's own (a
        // Keychain one is never read here, only whether it is there).
        binding.items = { [unowned self] in
            self.preferences.formProfiles.mine.map { extra in
                extra.isSensitive
                    ? SettingItem(["field": extra.label, "kept": "in the Keychain"], content: "value", FormSecrets.value(of: extra)?.isEmpty == false ? "•" : "")
                    : SettingItem(["field": extra.label], content: "value", extra.value)
            }
        }
        binding.add = { [unowned self] text in
            guard let colon = text.firstIndex(of: ":") else { throw Failure("A detail is said “Field: value”, like “SIRET: 123 456 789 00012”.") }
            let label = text[..<colon].trimmingCharacters(in: .whitespaces)
            let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !value.isEmpty else { throw Failure("A detail needs a field and a value: “SIRET: 123 456 789 00012”.") }
            let existing = self.preferences.formProfiles.mine.first { Self.folded($0.label) == Self.folded(label) }
            if Self.isSensitive(label) || existing?.isSensitive == true {
                throw Failure("\(label) is kept in the Keychain: the user types it in Settings → Your Details. Never ask them for it.")
            }
            if existing?.value == value { return ListChange(item: "\(label): \(value)", unchanged: true) }
            return ListChange(item: "\(label): \(value)", card: "\(label): \(value)" + (existing.map { " (was \($0.value))" } ?? "")) { [unowned self] in
                if let index = self.preferences.formProfiles.mine.firstIndex(where: { $0.id == existing?.id }) {
                    self.preferences.formProfiles.mine[index].value = value
                } else {
                    self.preferences.formProfiles.mine.append(FormExtra(label: label, isSensitive: false, value: value))
                }
            }
        }
        binding.remove = { [unowned self] text in
            let wanted = Self.folded(text.components(separatedBy: ":").first ?? text)
            guard let extra = self.preferences.formProfiles.mine.first(where: { Self.folded($0.label) == wanted }) else {
                throw Failure("No detail “\(text)”. Details: \(self.preferences.formProfiles.mine.map(\.label).joined(separator: ", ")).")
            }
            return ListChange(item: extra.label) { [unowned self] in
                FormSecrets.forget(extra)
                self.preferences.formProfiles.mine.removeAll { $0.id == extra.id }
            }
        }
        return binding
    }

    private func people() -> Binding {
        var binding = Binding(get: { [unowned self] in
            .list(self.preferences.formProfiles.others.map { $0.extras.isEmpty ? $0.name : "\($0.name) (\($0.extras.count) field\($0.extras.count == 1 ? "" : "s"))" })
        })
        binding.add = { [unowned self] text in
            let name = text.trimmingCharacters(in: .whitespaces)
            if self.preferences.formProfiles.others.contains(where: { Self.folded($0.name) == Self.folded(name) }) {
                return ListChange(item: name, unchanged: true)
            }
            return ListChange(item: name) { [unowned self] in
                self.preferences.formProfiles.others.append(FormPerson(name: name))
            }
        }
        binding.remove = { [unowned self] text in
            guard let person = self.preferences.formProfiles.others.first(where: { Self.folded($0.name) == Self.folded(text) }) else {
                // Their names are the user's own: not listed here.
                throw Failure("No one in People and companies is named “\(text)”.")
            }
            return ListChange(item: person.name) { [unowned self] in
                person.extras.forEach(FormSecrets.forget)
                self.preferences.formProfiles.others.removeAll { $0.id == person.id }
            }
        }
        return binding
    }
}
