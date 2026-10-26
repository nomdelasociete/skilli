import Foundation

/// Settings → Privacy's "What Leaves This Mac": every feature that sends
/// something off the Mac, what it sends, when, and to whom. Each flow is
/// written from the code that sends it (named beside it); `sections(for:)`
/// places it under where it would go today, from what is set up, and a
/// place nothing goes to says so. A new feature that sends anything off
/// the Mac adds its flow here.
public enum PrivacyMap {
    /// Where it goes, in the pane's order.
    public enum Destination: String, CaseIterable, Sendable {
        case claude, chatGPT, openAI, typeSafe, github, klipy, websites, yours, apple

        public var title: String {
            switch self {
            case .claude: "Claude"
            case .chatGPT: "ChatGPT"
            case .openAI: "OpenAI API"
            case .typeSafe: "TypeSafe Jev"
            case .github: "GitHub"
            case .klipy: "Klipy"
            case .websites: "Websites"
            case .yours: "Your Servers and Agents"
            case .apple: "Apple"
            }
        }

        /// Who writes with `provider`.
        public init(writer provider: WritingProvider) {
            switch provider {
            case .claude: self = .claude
            case .chatGPT: self = .chatGPT
            case .openAI: self = .openAI
            }
        }
    }

    /// One feature that sends something: what, when, and the Settings pane
    /// that holds what controls it (`SettingsPane`'s raw value).
    public struct Flow: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        /// What goes, in the user's words.
        public let sends: String
        /// When it goes.
        public let when: String
        /// The pane where its switch or its account lives; nil when none
        /// has a say (a speed test asked for).
        public let pane: String?
        /// The switch there that turns it off, when there is one.
        public let toggle: String?

        init(_ id: String, _ title: String, sends: String, when: String, pane: String?, toggle: String? = nil) {
            self.id = id
            self.title = title
            self.sends = sends
            self.when = when
            self.pane = pane
            self.toggle = toggle
        }
    }

    // MARK: - The flows

    // Writing: AIActionController (message(for:), Ask, followUpTurn,
    // writeMail, writeField), PromptLibrary (Ask includes About You),
    // AIStore.writer(for:), the engines (ClaudeSubscriptionEngine,
    // ClaudeAPIEngine, CodexEngine, OpenAIEngine).
    public static let ask = Flow(
        "ask", "Ask",
        sends: "Your request, the text you selected, and About You.",
        when: "When you ask: ✦A, ⇥ in the launcher, or ✦V.",
        pane: "ask")
    public static let commands = Flow(
        "commands", "Commands",
        sends: "The command's prompt and what it names: the text you selected (or the field you are in), the clipboard, the app and window in front, your name, About You.",
        when: "When you run one, from its keys, the launcher or an agent.",
        pane: "commands")
    public static let followUps = Flow(
        "followUps", "Follow-ups",
        sends: "The conversation so far, then what you type next.",
        when: "When you press ⇥ after an answer.",
        pane: "ask")
    public static let mail = Flow(
        "mail", "A mail to someone",
        sends: "Your request, and their name, job and company; never their address.",
        when: "When your request says what the mail is about.",
        pane: "ask")
    public static let fieldWords = Flow(
        "fieldWords", "Words for a field",
        sends: "Your request, the field's name and what it holds, and what was typed before.",
        when: "When doing it here needs words your request does not quote.",
        pane: "ask")
    // ComputerControl.plan → AIActionController.planSteps.
    public static let plannedSteps = Flow(
        "plannedSteps", "Thinking it through",
        sends: "Your request, the app's and window's names, what the window shows (as doing it here reads it, never passwords), the steps so far; to Claude, one picture of that window.",
        when: "When doing it here has a next step to work out (a move in a game, a puzzle); pictures only with Screen Recording on, never with a password field showing.",
        pane: "ask")

    // Acting: AgentRun (Claude Code with skil.li's tools and the servers),
    // AIActionController.act, HandoffLauncher (Continue in, Help Me Choose).
    public static let agent = Flow(
        "agent", "Ask with tools, and commands that act",
        sends: "Your request, the text you selected and About You, then what skil.li's tools read for it and what your connected servers answer.",
        when: "When Ask decides to act (always, with no deciding key), when you run a command with tools, and their follow-ups.",
        pane: "tools")
    // AskScheduler (the times), AIActionController.runScheduled (the run,
    // as Ask's: AskRouter, the writer, AgentRun).
    public static let scheduled = Flow(
        "scheduled", "Asks on a schedule",
        sends: "What Ask sends for the request you scheduled (never a selection), then what its tools read for it.",
        when: "At each time you set, and once when the Mac wakes for a time missed while it slept.",
        pane: "ask")
    public static let continueIn = Flow(
        "continueIn", "Continue a conversation",
        sends: "The conversation: your request as sent, what was done, the answer.",
        when: "When you press ⌘↩ after an answer.",
        pane: "ask")
    public static let rightsHelp = Flow(
        "rightsHelp", "Help with tool rights",
        sends: "Your servers' tools with their descriptions and rights, and what you tell it.",
        when: "When you open Help Me Choose in Tools.",
        pane: "tools")

    // Deciding: DecisionClient, from AskRouter, ComputerControl,
    // AIActionController.quitByAsk, FileSearch, BrowserHistory,
    // ClipboardHistory, SnippetLibrary, EmojiLibrary,
    // SkilliTools.findElement.
    public static let route = Flow(
        "route", "Choosing what Ask does",
        sends: "Your request, whether text is selected (never the text), the app's name and menu items, your apps' names and kinds, your recent projects, skillies, sound and Bluetooth devices, your connected servers' and tools' names; and when you ask about your calendar or reminders, your calendars' and lists' names.",
        when: "Each time you ask, and once more for what it acts with (how long, when, who, what for) when it needs it.",
        pane: "aiAccounts")
    // The picture: ComputerControl.picture(of:), WindowPicture, DecisionClient.reply.
    public static let doItHere = Flow(
        "doItHere", "Doing it here",
        sends: "Your request, the app's and window's names, what the window shows (buttons, fields and what they hold, menus, words on screen; never passwords), the steps so far, the kinds of details a form asks, never yours; and, when the window says too little, pictures of that window (the whole of it, then a close-up of a part where something only drawn is clicked), to TypeSafe Jev.",
        when: "At each step, when Ask does it in the window in front; the picture only with Screen Recording on, never with a password field showing.",
        pane: "ask")
    public static let quit = Flow(
        "quit", "Quitting by name",
        sends: "The name you said, and the names and folders of the processes that may be it.",
        when: "When you ask to quit something and a process is not surely it.",
        pane: "ask")
    public static let files = Flow(
        "files", "Files by meaning",
        sends: "Your words, and the names, kinds, folders and dates of up to \(FileMeaning.candidateLimit) files that may fit.",
        when: "Only when you press ⇥ in Search Files.",
        pane: "launcher", toggle: "Search files by meaning with ⇥")
    public static let history = Flow(
        "history", "Browser history by meaning",
        sends: "Your words, and the titles, sites and dates of your last \(HistoryMeaning.candidateLimit) pages.",
        when: "Only when you press ⇥ in Browser History.",
        pane: "launcher", toggle: "Search browser history by meaning with ⇥")
    public static let clipboard = Flow(
        "clipboard", "Clipboard by meaning",
        sends: "Your words, and your last \(ClipboardMeaning.candidateLimit) copies in short: \(ClipboardMeaning.excerptLength) characters each (words read in images, what images show), their app and date; a bank or card number or a key goes as what it is, never itself.",
        when: "Only when you press ⇥ in Clipboard History.",
        pane: "clipboard", toggle: "Search by meaning with ⇥")
    public static let snippets = Flow(
        "snippets", "Snippets by meaning",
        sends: "Your words, and each snippet's name, keyword and first \(SnippetMeaning.previewLength) characters as written: placeholders unfilled, never the rest; a bank or card number or a key goes as what it is (“an IBAN”), never itself.",
        when: "Only when you press ⇥ in Search Snippets.",
        pane: "snippets", toggle: "Find snippets by meaning with ⇥")
    public static let emoji = Flow(
        "emoji", "Emoji by feeling",
        sends: "What you typed, with emoji names.",
        when: "When you press ⇥ in Emoji, or by itself when no emoji's name fits what you typed.",
        pane: "emoji", toggle: "Find emoji by feeling with ⇥")
    public static let findControl = Flow(
        "findControl", "Finding a control for an agent",
        sends: "What the agent looks for, and the names of the window's controls.",
        when: "When an agent asks skil.li to find a button or a field.",
        pane: "tools")
    // AutoQuitter.judge (Settings → Windows → Quit apps you stopped using).
    public static let autoQuit = Flow(
        "autoQuit", "Quitting apps you stopped using",
        sends: "The names of the apps about to be quit and their windows' titles, to tell one still busy (a call, a download, a command running).",
        when: "When an app has gone unused for the time you set, with Quit apps you stopped using on.",
        pane: "windows", toggle: "Quit apps you stopped using")
    // MCPService.ruled, RuleJudge: before an agent's tool runs, while the
    // user has rules (Settings → Ask → Your Rules).
    public static let rules = Flow(
        "rules", "Your rules for agents",
        sends: "Your rules, and the step an agent is about to take: the tool's name and what it does, who asks, and a short summary of what it sends (passwords, keys and tokens left out).",
        when: "Before a step an agent takes, while you have rules.",
        pane: "ask")
    /// OpenAI Decisions when both keys are there: what Jev did not answer.
    public static let fallback = Flow(
        "fallback", "When Jev does not answer",
        sends: "The same as Jev's choices listed under TypeSafe Jev; never images.",
        when: "Only when TypeSafe Jev fails to answer.",
        pane: "aiAccounts")

    // Images: ImageTagger, JevImages, ClipboardHistory (capture,
    // keepImage, tagUntagged), ImageFolderWatcher.
    public static let imagesCopied = Flow(
        "imagesCopied", "Images you copy",
        sends: "Each image once, as a 512 px JPEG, to say what it shows.",
        when: "In the background, after you copy it; images kept with no key, at the next launch.",
        pane: "clipboard", toggle: "Images you copy, by what they show")
    public static let imagesFolder = Flow(
        "imagesFolder", "Screenshots",
        sends: "Each new image of the folder once, as a 512 px JPEG; the words in it are read on this Mac.",
        when: "In the background, when it appears there, while screenshots join the history.",
        pane: "clipboard", toggle: "Screenshots, by what they show")

    // Websites: ClipboardLinks, LinkPreviewFetcher (a copied link shown in
    // Clipboard History's preview).
    public static let linkPreviews = Flow(
        "linkPreviews", "Link previews",
        sends: "The link you look at: skil.li opens it as a browser would, without your cookies or sign-ins, to read its title, description, picture and icon.",
        when: "When a copied link shows in Clipboard History's preview, then once a week at most while you look at it; never for the copies you do not look at.",
        pane: "clipboard", toggle: "Show link previews")

    // GitHub: GitHubBook, GitHubInbox, GitHubNotifications; RelayStream.
    public static let github = Flow(
        "github", "Pull requests and notifications",
        sends: "Your sign-in with each request, and what you do there: merge, update a branch, mark read.",
        when: "While the strip under the search field, “pr” or an agent shows them: every minute, every 15 s while checks run.",
        pane: "github")
    /// Server sync on: GitHub is asked only for what the user does.
    public static let githubActions = Flow(
        "githubActions", "Pull request actions",
        sends: "Your sign-in with what you do there: merge, update a branch, mark read; and to check which account this Mac uses for the relay.",
        when: "When you do it, and once per relay token for the check; pull requests and notifications are read by the relay (Server sync).",
        pane: "github")
    /// Settings → GitHub → Server sync: the relay reads GitHub for the
    /// user's Macs (`GitHubServerInbox`, `RelayInbox`).
    public static let serverSync = Flow(
        "serverSync", "Server sync",
        sends: "This Mac's relay token. The relay reads your pull requests and notifications on GitHub with the authorization you gave it in your browser, and keeps one encrypted copy for your Macs.",
        when: "While GitHub shows: the relay's copy every minute and when a pull request changes; the relay asks GitHub at most once a minute for all your Macs.",
        pane: "github")
    /// Settings → GitHub → Advanced → Live updates from: the user's relay.
    public static let relay = Flow(
        "relay", "Live updates",
        sends: "Its token only; never your GitHub sign-in.",
        when: "While GitHub shows: one open stream.",
        pane: "github")

    // Klipy: GIFLibrary (the GIF mode's searches, Trending, Recently Used
    // read back by slug, a share counted).
    public static let gifs = Flow(
        "gifs", "GIF search",
        sends: "The words you type in the GIF mode, your country, a random id made on this Mac (never your name), and which GIF you paste or copy; the GIFs shown load from Klipy.",
        when: "When the GIF mode opens (Trending, Recently Used) and when typing pauses there; when you paste or copy one of Klipy's GIFs.",
        pane: "gifs", toggle: "Search GIFs")

    // Yours: MCPClient, MCPAuth, ToolSettings, AgentRun (servers);
    // SkilliTools.callWebhook; MCPSocketServer, MCPService (agents).
    public static let servers = Flow(
        "servers", "Connected servers",
        sends: "What an agent sends their tools, with your sign-in to them.",
        when: "When an agent uses them; their list of tools after Save, Sign In, Refresh or an import.",
        pane: "tools")
    public static let webhooks = Flow(
        "webhooks", "Your tools",
        sends: "The text the agent sends, a note, the tool's name and the name of the app in front.",
        when: "When an agent calls one.",
        pane: "tools")
    public static let agents = Flow(
        "agents", "Your agents",
        sends: "What skil.li's tools read for them: your selection, calendar, contacts, reminders, windows and menus; skil.li's settings, without your own content (About You, your details, snippets' text, addresses: only whether they are set).",
        when: "When an app you connected to skil.li, such as Claude Code or Codex, calls one of its tools.",
        pane: "tools")

    // Apple: RemindersPane (MKGeocodingRequest), SystemCommands
    // (networkQuality).
    public static let places = Flow(
        "places", "Places for reminders",
        sends: "The address you type, to find it on Apple Maps; for a reminder at home or at work with no place saved, your card's Home or Work address, once.",
        when: "When you add a place, or a reminder at home or at work with none saved.",
        pane: "reminders")
    public static let speedTest = Flow(
        "speedTest", "Internet speed test",
        sends: "Test data to Apple's servers; nothing of yours.",
        when: "When you run Test Internet Speed.",
        pane: nil)

    /// What decides: Jev first, else OpenAI Decisions.
    static let deciding = [route, doItHere, rules, quit, files, history, clipboard, snippets, emoji, findControl, autoQuit]

    /// Every flow, once.
    public static let all: [Flow] = [ask, commands, followUps, mail, fieldWords, plannedSteps, agent, scheduled, continueIn, rightsHelp]
        + deciding + [fallback, imagesCopied, imagesFolder, linkPreviews, github, githubActions, serverSync, relay, gifs, servers, webhooks, agents, places, speedTest]

    /// Said once, above the list: the promise, then what it means.
    public static let statement = "Only what is listed below, only when it says, only to these places."
    public static let staysHere = "Everything else skil.li reads or keeps stays on this Mac: your clipboard history, snippets, files, contacts, calendars, browser history, what you dictate and settings. skil.li has no server, no account and no analytics."

    /// What syncs because the user's own accounts do.
    public static let syncs = "Events and reminders you add go where your calendars and lists sync (iCloud, Google…), as when you add them yourself; a backup goes where its folder syncs."

    // MARK: - Placed for what is set up

    /// What is set up now, as the app reads it.
    public struct Setup: Sendable {
        /// How Claude writes now: the user's Claude Code, or their key.
        public enum ClaudeRoute: Sendable { case claudeCode, apiKey }

        /// One of the user's commands (Ask aside).
        public struct Command: Sendable {
            public var title: String
            /// Who writes it now (its own model, else the default); nil
            /// when it acts (Claude Code) or nothing can write it.
            public var writer: WritingProvider?
            public var acts: Bool
            /// It sends About You (Include About You, or `{profile}`).
            public var aboutYou: Bool

            public init(title: String, writer: WritingProvider?, acts: Bool = false, aboutYou: Bool = false) {
                self.title = title
                self.writer = writer
                self.acts = acts
                self.aboutYou = aboutYou
            }
        }

        public var claude: ClaudeRoute?
        /// Codex signed in to ChatGPT.
        public var chatGPT = false
        public var openAIKey = false
        public var typeSafeKey = false
        /// Claude Code found: Ask with tools and commands that act run there.
        public var claudeCode = false
        /// Who writes Ask's answers now; nil when nothing can.
        public var askWriter: WritingProvider?
        public var commands: [Command] = []
        /// The scheduled asks turned on, by when they run ("Every Monday at
        /// 9:00"): they go where Ask's answers and its agent go.
        public var scheduledAsks: [String] = []
        /// Where "Continue a conversation" and Help Me Choose open:
        /// `.claude` (Claude Code) or `.chatGPT` (Codex); nil when neither
        /// is installed.
        public var continueIn: WritingProvider?
        public var fileMeaning = true
        public var historyMeaning = true
        public var clipboardMeaning = true
        public var snippetMeaning = true
        public var emojiMeaning = true
        public var clipboardHistory = true
        /// Screenshots (the folder's new images) join the history.
        public var screenshots = true
        public var imagesCopied = true
        public var imagesFolder = true
        /// Settings → Clipboard → Show link previews.
        public var linkPreviews = true
        /// Search GIFs on (Settings → Catalog) with a Klipy key.
        public var gifSearch = true
        /// Settings → Windows → Quit apps you stopped using (off by default).
        public var autoQuit = false
        /// The folder whose new images are tagged.
        public var imageFolder = ""
        /// nil when not signed in; "" when the login is not known yet.
        public var githubLogin: String?
        /// The relay's host, when one is set with its token.
        public var relayHost: String?
        /// Settings → GitHub → Server sync is on.
        public var githubServerSync = false
        public var servers: [String] = []
        public var webhooks: [String] = []
        /// The user has rules for agents (Settings → Ask → Your Rules).
        public var rules = false
        /// Settings → Backup's folder as the Finder names it ("iCloud Drive
        /// › skil.li"); nil until one is chosen.
        public var backupFolder: String?
        /// Who syncs that folder ("iCloud", "Dropbox"); nil when it stays
        /// on this Mac.
        public var backupSyncs: String?

        public init() {}
    }

    /// A flow placed under a destination: whether its switch is on (nil
    /// when it has none) and what it applies to ("Fix Spelling & Grammar,
    /// Translate").
    public struct Row: Identifiable, Hashable, Sendable {
        public let flow: Flow
        public let isOn: Bool?
        public let note: String?

        public var id: String { flow.id }

        init(_ flow: Flow, isOn: Bool? = nil, note: String? = nil) {
            self.flow = flow
            self.isOn = isOn
            self.note = note
        }
    }

    public struct Section: Identifiable, Sendable {
        public let destination: Destination
        /// How it is reached, or that nothing goes there.
        public let status: String
        public let rows: [Row]

        public var id: String { destination.rawValue }
        /// Something can go there now.
        public var inUse: Bool { !rows.isEmpty }
    }

    /// Every destination once, in order, with what would go there now.
    public static func sections(for setup: Setup) -> [Section] {
        Destination.allCases.map { destination in
            let rows = rows(for: destination, setup)
            return Section(destination: destination, status: status(of: destination, setup, inUse: !rows.isEmpty), rows: rows)
        }
    }

    static func rows(for destination: Destination, _ setup: Setup) -> [Row] {
        var rows: [Row] = []
        switch destination {
        case .claude, .chatGPT, .openAI:
            rows += writing(for: destination, setup)
        default:
            break
        }
        switch destination {
        case .claude:
            if setup.claudeCode {
                let acting = setup.commands.filter(\.acts).map(\.title)
                rows.append(Row(agent, note: acting.isEmpty ? "Through Claude Code" : "Through Claude Code. Commands: " + list(acting)))
                if !setup.scheduledAsks.isEmpty { rows.append(Row(scheduled, note: "Through Claude Code: " + list(setup.scheduledAsks))) }
            }
            if setup.continueIn == .claude {
                rows += [Row(continueIn, note: "In Claude Code"), Row(rightsHelp, note: "With Claude Code")]
            }
        case .chatGPT:
            if setup.continueIn == .chatGPT {
                rows += [Row(continueIn, note: "In Codex"), Row(rightsHelp, note: "With Codex")]
            }
        case .openAI:
            if setup.openAIKey {
                rows += setup.typeSafeKey ? [Row(fallback)] : decisions(setup)
            }
        case .typeSafe:
            if setup.typeSafeKey {
                rows += decisions(setup)
                let images = setup.clipboardHistory
                rows.append(Row(imagesCopied, isOn: images && setup.imagesCopied))
                rows.append(Row(imagesFolder, isOn: images && setup.screenshots && setup.imagesFolder,
                                note: setup.imageFolder.isEmpty ? nil : "Folder: \(setup.imageFolder)"))
            }
        case .github:
            if setup.githubLogin != nil {
                rows.append(Row(setup.githubServerSync ? githubActions : github))
                // Server sync on: said even when this Mac's relay access is gone.
                if setup.githubServerSync { rows.append(Row(serverSync, note: setup.relayHost)) }
                else if let host = setup.relayHost { rows.append(Row(relay, note: host)) }
            }
        case .klipy:
            rows.append(Row(gifs, isOn: setup.gifSearch))
        case .websites:
            rows.append(Row(linkPreviews, isOn: setup.clipboardHistory && setup.linkPreviews))
        case .yours:
            if !setup.servers.isEmpty { rows.append(Row(servers, note: list(setup.servers))) }
            if !setup.webhooks.isEmpty { rows.append(Row(webhooks, note: list(setup.webhooks))) }
            rows.append(Row(agents))
        case .apple:
            rows += [Row(places), Row(speedTest)]
        }
        return rows
    }

    /// What a writer gets: Ask and what comes with it when it writes Ask,
    /// the commands it writes, their follow-ups.
    private static func writing(for destination: Destination, _ setup: Setup) -> [Row] {
        let writesAsk = setup.askWriter.map(Destination.init(writer:)) == destination
        let written = setup.commands.filter { !$0.acts && $0.writer.map(Destination.init(writer:)) == destination }.map(\.title)
        var rows: [Row] = []
        if writesAsk { rows.append(Row(ask)) }
        if !written.isEmpty { rows.append(Row(commands, note: list(written))) }
        if writesAsk || !written.isEmpty { rows.append(Row(followUps)) }
        if writesAsk { rows += [Row(mail), Row(fieldWords), Row(plannedSteps)] }
        // Without Claude Code, a scheduled ask is written like Ask's answers.
        if writesAsk, !setup.claudeCode, !setup.scheduledAsks.isEmpty { rows.append(Row(scheduled, note: list(setup.scheduledAsks))) }
        return rows
    }

    private static func decisions(_ setup: Setup) -> [Row] {
        deciding.filter { $0.id != rules.id || setup.rules }.map { flow in
            switch flow.id {
            case files.id: Row(flow, isOn: setup.fileMeaning)
            case history.id: Row(flow, isOn: setup.historyMeaning)
            case clipboard.id: Row(flow, isOn: setup.clipboardMeaning && setup.clipboardHistory)
            case autoQuit.id: Row(flow, isOn: setup.autoQuit)
            case snippets.id: Row(flow, isOn: setup.snippetMeaning)
            case emoji.id: Row(flow, isOn: setup.emojiMeaning)
            default: Row(flow)
            }
        }
    }

    static func status(of destination: Destination, _ setup: Setup, inUse: Bool) -> String {
        let route = route(of: destination, setup, inUse: inUse)
        // Set up, and nothing goes there: no command writes with it.
        guard inUse || !isSetUp(destination, setup) else { return route + "; nothing goes there now" }
        return route
    }

    private static func isSetUp(_ destination: Destination, _ setup: Setup) -> Bool {
        switch destination {
        case .claude: setup.claude != nil
        case .chatGPT: setup.chatGPT
        case .openAI: setup.openAIKey
        case .typeSafe: setup.typeSafeKey
        case .github: setup.githubLogin != nil
        case .klipy: setup.gifSearch
        case .websites, .yours, .apple: true
        }
    }

    private static func route(of destination: Destination, _ setup: Setup, inUse: Bool) -> String {
        switch destination {
        case .claude:
            switch setup.claude {
            case .claudeCode: "Your Claude plan, through Claude Code on this Mac"
            case .apiKey: "Your Claude API key, billed by Anthropic"
            case nil: inUse ? "Claude Code on this Mac" : "Not set up: nothing goes to Claude"
            }
        case .chatGPT:
            setup.chatGPT ? "Your ChatGPT account, through Codex on this Mac"
                : inUse ? "Codex on this Mac" : "Not signed in: nothing goes to ChatGPT"
        case .openAI:
            setup.openAIKey ? "Your OpenAI key, billed by OpenAI" : "No key: nothing goes to OpenAI"
        case .typeSafe:
            !setup.typeSafeKey ? "No key: nothing goes to TypeSafe"
                : setup.openAIKey ? "Your TypeSafe key: Jev decides first" : "Your TypeSafe key"
        case .github:
            switch setup.githubLogin {
            case nil: "Not signed in: nothing goes to GitHub"
            case let login? where !login.isEmpty: "Signed in as @\(login)"
            default: "Signed in"
            }
        case .klipy:
            setup.gifSearch ? "Klipy's GIFs, searched from the GIF mode" : "GIF search off or no Klipy key: nothing goes to Klipy"
        case .websites:
            setup.clipboardHistory && setup.linkPreviews
                ? "The sites of the links you look at in Clipboard History"
                : "Link previews off: nothing goes to websites"
        case .yours:
            setup.servers.isEmpty && setup.webhooks.isEmpty
                ? "Nothing connected in Tools; only apps you connect to skil.li"
                : "What you connect in Tools, and apps you connect to skil.li"
        case .apple:
            "Apple Maps and Apple's speed test"
        }
    }

    // MARK: - One line in a pane

    /// What a pane's features send off the Mac, in one sentence (rule 7 of
    /// the Settings plan: "any feature that sends text to a model or a
    /// server says so in the pane, with which provider"), and the pane that
    /// says more: Privacy, or SI Accounts when nothing can write yet.
    public struct PaneLine: Equatable, Sendable {
        public let text: String
        /// `SettingsPane`'s raw value.
        public let more: String
    }

    /// The line for `pane` (`SettingsPane`'s raw value), from what is set
    /// up; nil for a pane that has none yet.
    public static func line(for pane: String, _ setup: Setup) -> PaneLine? {
        switch pane {
        case "ask": askLine(setup)
        case "aiAccounts": accountsLine(setup)
        case "calendar": calendarLine(setup)
        case "reminders": remindersLine(setup)
        case "commands": commandsLine(setup)
        case "tools": toolsLine(setup)
        case "clipboard": clipboardLine(setup)
        case "snippets": snippetsLine(setup)
        case "emoji": emojiLine(setup)
        case "gifs": gifsLine(setup)
        case "windows": windowsLine(setup)
        case "launcher": launcherLine(setup)
        case "skillies": skilliesLine(setup)
        case "github": githubLine(setup)
        case "backup": backupLine(setup)
        case "yourDetails": detailsLine(setup)
        default: nil
        }
    }

    /// A flow's what and when, as one sentence after "To …:".
    static func sentence(_ flow: Flow) -> String {
        flow.sends.prefix(1).lowercased() + flow.sends.dropFirst() + " " + flow.when
    }


    /// The name a sentence uses: "OpenAI", not "OpenAI API".
    static func spoken(_ destination: Destination) -> String {
        destination == .openAI ? "OpenAI" : destination.title
    }

    /// Who chooses what Ask does: Jev first, else OpenAI's key.
    static func decider(_ setup: Setup) -> Destination? {
        setup.typeSafeKey ? .typeSafe : setup.openAIKey ? .openAI : nil
    }

    /// Ask: who writes the answer (`ask`), who acts with tools (`agent`,
    /// Claude Code), who chooses the way and reads the window when it does
    /// it there (`route`, `doItHere`).
    static func askLine(_ setup: Setup) -> PaneLine {
        guard let writer = setup.askWriter.map(Destination.init(writer:)) else {
            return PaneLine(text: "Nothing leaves this Mac yet: Ask needs an account to write with.", more: "aiAccounts")
        }
        var text = "When you ask, your request, the text you selected and About You go to \(spoken(writer))"
        if setup.claudeCode, writer != .claude { text += ", and to Claude when it acts with your tools" }
        // AskScheduler: the same at each time, never a selection.
        if !setup.scheduledAsks.isEmpty { text += "; your asks on a schedule send their request and About You at their times" }
        if let decider = decider(setup) {
            text += decider == writer
                ? "; \(spoken(decider)) also chooses what to do, and reads the window when it acts there"
                : "; \(spoken(decider)) gets your request to choose what to do, and what the window shows when it acts there"
            if setup.rules { text += ", and each step an agent takes, to check it against your rules" }
        }
        return PaneLine(text: text + ".", more: "privacy")
    }

    /// Calendar: read here; what Ask is told about it goes to the decision
    /// model with the calendars' names.
    static func calendarLine(_ setup: Setup) -> PaneLine {
        guard let decider = decider(setup) else {
            return PaneLine(text: "Nothing leaves this Mac: your calendars are read here, and Check Camera & Mic shows you only here.", more: "privacy")
        }
        return PaneLine(text: "Your calendars are read here; when you ask about them, your request and your calendars' names go to \(spoken(decider)) to read it. Check Camera & Mic shows you only here.",
                        more: "privacy")
    }

    /// Reminders: places to Apple; what Ask is told goes to the decision
    /// model with the lists' names.
    static func remindersLine(_ setup: Setup) -> PaneLine {
        var text = "To Apple: " + sentence(places)
        if let decider = decider(setup) {
            text += " When you ask about your reminders, your request and your lists' names go to \(spoken(decider)) to read it."
        }
        return PaneLine(text: text, more: "privacy")
    }

    /// Commands: who writes them (each its own model, else the default),
    /// and Claude Code for those that act.
    static func commandsLine(_ setup: Setup) -> PaneLine {
        var writers: [Destination] = []
        for writer in setup.commands.filter({ !$0.acts }).compactMap(\.writer).map(Destination.init(writer:)) where !writers.contains(writer) {
            writers.append(writer)
        }
        let acting = setup.claudeCode && setup.commands.contains(where: \.acts)
        guard !writers.isEmpty || acting else {
            return PaneLine(text: "Nothing leaves this Mac yet: commands need an account to write with.", more: "aiAccounts")
        }
        var text = "When you run a command, its prompt and what it names (the text you selected, the clipboard, About You when it includes it)"
        if writers.isEmpty {
            text += " go to Claude, through Claude Code"
        } else {
            let names = writers.map(spoken)
            text += " go to " + (names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1])
            if names.count > 1 { text += ", as each command says" }
            if acting { text += "; commands with tools go to Claude through Claude Code, with what its tools read" }
        }
        return PaneLine(text: text + ".", more: "privacy")
    }

    /// Tools: what skil.li's tools read goes to the agent that asked; the
    /// user's servers and webhooks get what an agent sends them; the rules
    /// go to the decision model.
    static func toolsLine(_ setup: Setup) -> PaneLine {
        var parts = ["What skil.li's tools read goes to the agent that asked for it"]
        if !setup.servers.isEmpty { parts.append("what an agent sends your servers' tools goes to those servers, with your sign-in") }
        if !setup.webhooks.isEmpty { parts.append("your tools get the text an agent sends them") }
        if setup.rules, let decider = decider(setup) { parts.append("\(spoken(decider)) checks each step against your rules") }
        return PaneLine(text: parts.joined(separator: "; ") + ".", more: "privacy")
    }

    /// SI Accounts: each account in use and what goes to it, from the
    /// same rows as Settings → Privacy.
    static func accountsLine(_ setup: Setup) -> PaneLine {
        let accounts: [Destination] = [.claude, .chatGPT, .openAI, .typeSafe]
        let sentences = sections(for: setup).filter { accounts.contains($0.destination) }.compactMap { section -> String? in
            let ids = Set(section.rows.filter { $0.isOn != false }.map(\.id))
            var what: [String] = []
            if ids.contains(ask.id) { what.append("what you ask") }
            if ids.contains(commands.id) { what.append(ids.contains(ask.id) ? "your commands" : "the commands set to it") }
            if ids.contains(agent.id) { what.append("what Ask does with tools") }
            if ids.contains(continueIn.id) { what.append("conversations you continue") }
            if ids.contains(route.id) { what.append("Ask's choices") }
            if ids.contains(rules.id) { what.append("agents' steps, to check them against your rules") }
            if !ids.isDisjoint(with: [files.id, history.id, clipboard.id, snippets.id, emoji.id]) { what.append("searches by meaning") }
            if ids.contains(autoQuit.id) { what.append("the apps Auto Quit may quit") }
            if ids.contains(fallback.id) { what.append("Ask's choices when Jev fails") }
            switch (ids.contains(imagesCopied.id), ids.contains(imagesFolder.id)) {
            case (true, true): what.append("the images you copy and your screenshots")
            case (true, false): what.append("the images you copy")
            case (false, true): what.append("your screenshots")
            case (false, false): break
            }
            guard !what.isEmpty else { return nil }
            let joined = what.count == 1 ? what[0] : what.dropLast().joined(separator: ", ") + " and " + what[what.count - 1]
            // "what you ask goes", "what you ask and your commands go".
            return "\(joined) \(what.count == 1 && what[0].hasPrefix("what") ? "goes" : "go") to \(spoken(section.destination))"
        }
        guard let first = sentences.first else {
            return PaneLine(text: "Nothing leaves this Mac: no account is set up.", more: "privacy")
        }
        let text = ([first.prefix(1).uppercased() + first.dropFirst()] + sentences.dropFirst()).joined(separator: "; ")
        return PaneLine(text: text + ".", more: "privacy")
    }

    /// Where the pane's own switches send something now, by flow id: the
    /// rows Settings → Privacy shows on, for `pane`.
    static func goingFrom(_ pane: String, _ setup: Setup) -> [(flow: String, to: Destination)] {
        sections(for: setup).flatMap { section in
            section.rows.filter { $0.flow.pane == pane && $0.isOn != false }.map { ($0.flow.id, section.destination) }
        }
    }

    /// Clipboard: excerpts of the copies on ⇥, each image or screenshot
    /// once to say what it shows, and a link looked at, opened to read its
    /// title and picture.
    static func clipboardLine(_ setup: Setup) -> PaneLine {
        let going = goingFrom("clipboard", setup)
        var sentences: [String] = []
        if let to = going.first(where: { $0.flow == clipboard.id })?.to {
            sentences.append("when you press ⇥, short excerpts of your last copies go to \(spoken(to))")
        }
        let images = going.filter { [imagesCopied.id, imagesFolder.id].contains($0.flow) }
        if let to = images.first?.to {
            let what = images.count == 2 ? "each image you copy and each screenshot go" : images[0].flow == imagesCopied.id ? "each image you copy goes" : "each screenshot goes"
            sentences.append("\(what) once to \(spoken(to)), as a small picture, to say what it shows")
        }
        if going.contains(where: { $0.flow == linkPreviews.id }) {
            sentences.append("a link you look at is opened, without your cookies, to read its title and picture")
        }
        guard let first = sentences.first else {
            return PaneLine(text: "Nothing leaves this Mac: what you copy, your screenshots and the words read in them stay here.", more: "privacy")
        }
        let text = ([first.prefix(1).uppercased() + first.dropFirst()] + sentences.dropFirst()).joined(separator: "; ")
        // Said of images whichever sentence comes last.
        return PaneLine(text: text + ". Words in images are read here.", more: "privacy")
    }

    /// Snippets: names, keywords and first words on ⇥ in Search Snippets.
    static func snippetsLine(_ setup: Setup) -> PaneLine {
        guard let to = goingFrom("snippets", setup).first?.to else {
            return PaneLine(text: "Nothing leaves this Mac: your snippets and what you type stay here.", more: "privacy")
        }
        return PaneLine(text: "When you press ⇥ in Search Snippets, your words and each snippet's name, keyword and first \(SnippetMeaning.previewLength) characters go to \(spoken(to)); what you type stays here.", more: "privacy")
    }

    /// Emoji: what was typed, with emoji names, on ⇥ or when no name fits
    /// (`emoji`); the words learned from a pick stay.
    static func emojiLine(_ setup: Setup) -> PaneLine {
        guard let to = goingFrom("emoji", setup).first?.to else {
            return PaneLine(text: "Nothing leaves this Mac: what you type and the words learned stay here.", more: "privacy")
        }
        return PaneLine(text: "When you press ⇥, or when no emoji's name fits, what you typed goes to \(spoken(to)) with emoji names; the words learned stay here.",
                        more: "privacy")
    }

    /// GIFs: the words typed in the GIF mode go to Klipy (`gifs`); the
    /// GIFs on this Mac are found here.
    static func gifsLine(_ setup: Setup) -> PaneLine {
        guard setup.gifSearch else {
            return PaneLine(text: "Nothing leaves this Mac: the GIFs on this Mac are found here, and Klipy is not searched.", more: "privacy")
        }
        return PaneLine(text: "What you type in the GIF mode goes to Klipy once typing pauses, with your country and a random id; the GIFs on this Mac are found here.",
                        more: "privacy")
    }

    /// Launcher: the pages and files found by meaning, only on ⇥
    /// (`history`, `files`); what is typed stays.
    static func launcherLine(_ setup: Setup) -> PaneLine {
        let going = goingFrom("launcher", setup)
        var sentences: [String] = []
        if let to = going.first(where: { $0.flow == history.id })?.to {
            sentences.append("when you press ⇥ in Search Browser History, your words and the titles, sites and dates of your last pages go to \(spoken(to))")
        }
        if let to = going.first(where: { $0.flow == files.id })?.to {
            sentences.append("in Search Files, your words and the names, kinds, folders and dates of the files that may fit go to \(spoken(to))")
        }
        guard let first = sentences.first else {
            return PaneLine(text: "Nothing leaves this Mac: what you type and what it finds stay here.", more: "privacy")
        }
        let text = ([first.prefix(1).uppercased() + first.dropFirst()] + sentences.dropFirst()).joined(separator: "; ")
        return PaneLine(text: text + ". Typing alone stays here.", more: "privacy")
    }

    /// Skillies: they run on this Mac and send only what their own code
    /// sends; Ask, choosing what to do, reads their names and what they do
    /// (`route`).
    static func skilliesLine(_ setup: Setup) -> PaneLine {
        guard let to = decider(setup) else {
            return PaneLine(text: "Nothing: skillies run on this Mac and send only what their own code sends.", more: "privacy")
        }
        return PaneLine(text: "Skillies run on this Mac and send only what their own code sends. To pick one when you ask, Ask sends their names and what they do to \(spoken(to)).",
                        more: "privacy")
    }

    /// Windows: windows move and layouts stay on this Mac (a link a layout
    /// opens is the browser's to load); Quit apps you stopped using, when
    /// on with a deciding key, asks it first (`autoQuit`).
    static func windowsLine(_ setup: Setup) -> PaneLine {
        let local = "Windows move and layouts are kept on this Mac. A link a layout opens is loaded by your browser."
        guard setup.autoQuit, let decider = decider(setup) else { return PaneLine(text: "Nothing: " + local.prefix(1).lowercased() + local.dropFirst(), more: "privacy") }
        return PaneLine(text: "To \(spoken(decider)), for Quit apps you stopped using: " + sentence(autoQuit) + " " + local, more: "privacy")
    }

    /// GitHub: the sign-in with each read and what is done there
    /// (`github`); the relay's token, when one is set (`relay`).
    static func githubLine(_ setup: Setup) -> PaneLine {
        guard setup.githubLogin != nil else {
            return PaneLine(text: "Nothing leaves this Mac: you are not signed in to GitHub.", more: "privacy")
        }
        if setup.githubServerSync {
            return PaneLine(text: "GitHub gets your sign-in only for what you do there (merge, update a branch, mark read) and to check which "
                            + "account this Mac uses for the relay; \(setup.relayHost ?? "the relay") reads "
                            + "your pull requests and notifications on GitHub with its own authorization and keeps one copy for your Macs.",
                            more: "privacy")
        }
        var text = "GitHub gets your sign-in with each read, every minute while the strip or “pr” shows, and what you do there: merge, "
            + "update a branch, mark read"
        if let host = setup.relayHost { text += "; \(host) gets only its own token, never your GitHub sign-in" }
        return PaneLine(text: text + ".", more: "privacy")
    }

    /// Backup: skil.li sends nothing; the folder chosen may sync (`syncs`).
    static func backupLine(_ setup: Setup) -> PaneLine {
        guard let folder = setup.backupFolder else {
            return PaneLine(text: "Nothing leaves this Mac: until you choose a folder, nothing is backed up.", more: "privacy")
        }
        guard let service = setup.backupSyncs else {
            return PaneLine(text: "Nothing leaves this Mac: backups stay in \(folder).", more: "privacy")
        }
        return PaneLine(text: "skil.li sends nothing: backups go to \(folder), which \(service) syncs like your other files there.", more: "privacy")
    }

    /// Your Details: forms are typed on this Mac, the chooser reads only
    /// what each field asks (`doItHere`); without one, forms wait for its
    /// key (SI Accounts). About You goes with Ask and the commands that
    /// include it (`ask`, `agent`, `commands`).
    static func detailsLine(_ setup: Setup) -> PaneLine {
        let decider = decider(setup)
        var text = if let decider {
            "Forms are typed on this Mac: \(spoken(decider)) reads the fields and the kinds of details they ask for, never the details themselves"
        } else {
            "Your details stay on this Mac, and forms wait for a key that chooses where each goes"
        }
        var aboutYou: [Destination] = []
        if let writer = setup.askWriter { aboutYou.append(Destination(writer: writer)) }
        if setup.claudeCode { aboutYou.append(.claude) }
        for command in setup.commands where command.aboutYou {
            if let writer = command.writer { aboutYou.append(Destination(writer: writer)) }
            if command.acts, setup.claudeCode { aboutYou.append(.claude) }
        }
        let names = Destination.allCases.filter(aboutYou.contains).map(spoken)
        if !names.isEmpty { text += "; About You goes to \(and(names)) with Ask and the commands that include it" }
        return PaneLine(text: text + ".", more: decider == nil ? "aiAccounts" : "privacy")
    }

    /// "Claude", "Claude and ChatGPT", "Claude, ChatGPT and OpenAI".
    static func and(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// "Fix, Translate, Reply and 2 more".
    static func list(_ names: [String], shown: Int = 3) -> String {
        guard names.count > shown + 1 else { return names.joined(separator: ", ") }
        return names.prefix(shown).joined(separator: ", ") + " and \(names.count - shown) more"
    }
}
