import AppKit
import Carbon.HIToolbox
import SkilliCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: LaunchMode
    private let appIndex = AppIndex()
    private let usage = UsageStore()
    private let layout = KeyboardLayout()
    private let overlay = LeaderOverlay()
    private let remapper = HyperKeyRemapper()
    private let preferences = Preferences()
    private let shortcuts: ShortcutStore
    private let learning: LearningStore
    /// What ↑ brings back in the launcher; the self-test and the benchmark
    /// keep theirs in memory.
    private let recentSearches: RecentSearchStore
    private lazy var launcher = LauncherController(index: appIndex, usage: usage, learning: learning, recentSearches: recentSearches)
    private lazy var settings = SettingsWindowController(preferences: preferences) { [unowned self] in
        self.makeSettingsContext()
    }
    /// The self-test keeps its own Keychain item: never the user's API key.
    private lazy var ai = AIStore(
        preferences: preferences,
        keyAccount: { if case .selftest = mode { "selftest-anthropic-api-key" } else { AIStore.apiKeyAccount } }(),
        decisionKeyPrefix: { if case .selftest = mode { "selftest-" } else { "" } }()
    )
    private lazy var selection = SelectionService(layout: layout)
    /// The cup in the menu bar while the Mac is kept awake.
    private lazy var awakeIndicator: AwakeIndicator = {
        let indicator = AwakeIndicator()
        indicator.allowSleep = { [weak self] in _ = self?.systemCommands.keepAwake(.allowSleep) }
        return indicator
    }()
    private let permissions = PermissionCenter()
    private lazy var systemCommands: SystemCommands = {
        // The self-test keeps its own Keep Awake, never taken at launch.
        let scratch = { () -> UserDefaults? in
            if case .selftest = self.mode { return UserDefaults(suiteName: "skilli-selftest-awake-\(getpid())") }
            return nil
        }()
        let commands = SystemCommands(defaults: scratch ?? .standard)
        commands.confirm = { [weak self] question, detail, verb in
            guard let self else { return false }
            return await self.aiActions.approve(question, detail: detail, caller: "skil.li", run: nil, once: true, verb: verb, fromUser: true) != .deny
        }
        commands.onChange = { [weak self] in
            guard let self else { return }
            rebuildStatusMenu()
            awakeIndicator.update(awake: systemCommands.isKeepingAwake, until: systemCommands.awakeUntil)
        }
        // Settings → Windows → Space between windows, read at each press.
        commands.windows.gap = { [preferences] in CGFloat(preferences.windowGap) }
        return commands
    }()
    private lazy var setup: SetupWindowController = {
        let setup = SetupWindowController(permissions: permissions, ai: ai, preferences: preferences)
        madeSetup = true
        // The keys each action has now, as the welcome draws them.
        setup.model.keys = { [shortcuts] action in
            shortcuts.config.shortcuts.first { $0.action == action }?.chords.map { $0.map(\.keycaps) } ?? []
        }
        // The launcher's key, chosen and recorded in the welcome as in Settings → Keys.
        setup.model.shortcuts = shortcuts
        // Start, Later or ✕: done (D7). It never opens by itself again;
        // Set Up skil.li… stays in the menu bar and Settings → General
        // while Accessibility is off, and Welcome to skil.li in the launcher.
        setup.onClose = { [weak self] _ in
            self?.preferences.didCompleteSetup = true
            self?.rebuildStatusMenu()
        }
        return setup
    }()
    /// The welcome was made: only then do keys and the launcher report to it.
    private var madeSetup = false
    /// The welcome, when it shows (its live steps).
    private var shownWelcome: WelcomeModel? { madeSetup && setup.isVisible ? setup.model : nil }

    /// The welcome from its first step, or `step`, with Caps Lock as it is now.
    private func showWelcome(at step: WelcomeModel.Step = .welcome) {
        setup.model.hyperKey = remapper.welcomeState
        setup.show(at: step)
    }
    /// What the user copies, on this Mac. The self-test keeps its own;
    /// the benchmark none.
    private lazy var clipboard: ClipboardHistory = {
        let folder: URL? = switch mode {
        case .normal: ClipboardStore.defaultFolder
        case .selftest: FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/clipboard", isDirectory: true)
        case .benchmark: nil
        }
        var store: ClipboardStore?
        if let folder {
            do {
                store = try ClipboardStore(folder: folder)
            } catch {
                Log.actions.error("\(error.localizedDescription, privacy: .public)")
            }
        }
        return ClipboardHistory(preferences: preferences, store: store)
    }()
    /// Snippets as files; the self-test keeps its own, the benchmark none.
    private lazy var snippetLibrary = SnippetLibrary(folder: {
        switch mode {
        case .normal: SnippetLibrary.defaultFolder
        case .selftest: FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/snippets", isDirectory: true)
        case .benchmark: nil
        }
    }())
    /// Window layouts as files; the self-test keeps its own.
    private lazy var arranger = WindowArranger(folder: {
        switch mode {
        case .normal: WindowArranger.defaultFolder
        case .selftest: FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/layouts", isDirectory: true)
        case .benchmark: nil
        }
    }())
    /// Backups (Settings → Backup); the self-test backs up its own scratch
    /// folder and settings, never the user's.
    private lazy var backup: BackupCenter = {
        if case .selftest = mode {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/backup-source", isDirectory: true)
            return BackupCenter(preferences: preferences, source: .init(folder: scratch, defaultsSuite: "skilli-selftest-backup-\(getpid())"))
        }
        return BackupCenter(preferences: preferences)
    }()
    /// Asks on a schedule (Settings → Ask); the self-test keeps its own.
    private lazy var scheduler: AskScheduler = {
        switch mode {
        case .normal: AskScheduler(fileURL: AskScheduler.defaultFileURL)
        case .selftest: AskScheduler(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/scheduled-asks.json"))
        case .benchmark: AskScheduler(fileURL: nil)
        }
    }()
    /// The SKILL.md skills Ask's agent reads (Settings → Ask → Skills); the
    /// self-test writes its own.
    private lazy var skillsFolder: URL = {
        if case .selftest = mode {
            return FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/skills", isDirectory: true)
        }
        return AskSkillsRows.folder
    }()
    /// skil.li's skills, then Claude Code's when Settings → Ask says so
    /// (never the self-test's Mac's own).
    private func agentSkills() -> [AgentSkill] {
        var folders = [skillsFolder]
        if preferences.askUsesClaudeCodeSkills, case .normal = mode {
            folders.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills", isDirectory: true))
        }
        return AgentSkill.find(in: folders)
    }
    /// Where a window layout is looked over before it is saved.
    private lazy var layoutEditor = LayoutEditorController(arranger: arranger, preferences: preferences)
    /// Displays plugged in, and the question asked in their middle.
    private lazy var displayWatch = DisplayWatch()
    /// Sparkle, in the Developer ID build only (nil otherwise, and in the
    /// self-test and the benchmark).
    private var updates: SoftwareUpdate?
    /// Made the first time a display is asked about: its panel and views
    /// are not kept while nothing is plugged in (idle memory).
    private var madeDisplayPrompt: DisplayPrompt?
    /// A panel of skil.li's that took the keyboard to ask something, which
    /// a card behind it must not take keys from (the launcher is checked on
    /// its own). Settings is not one: an agent's question there is answered
    /// with ↩ in the card.
    private var ownWindowHasKeyboard: Bool {
        madeDisplayPrompt?.isKey == true || madeMeetingCard?.isKey == true
    }
    private var displayPrompt: DisplayPrompt {
        if let madeDisplayPrompt { return madeDisplayPrompt }
        let prompt = DisplayPrompt()
        prompt.onApply = { [weak self] layout in self?.applyLayout(layout) }
        prompt.onAlways = { [weak self] layout in self?.setAutomatic(layout, .always) }
        prompt.onNever = { [weak self] layout in self?.setAutomatic(layout, .never) }
        prompt.onIgnoreMonitors = { [weak self] monitors in self?.ignoreMonitors(monitors) }
        prompt.onEdit = { [weak self] layout in self?.layoutEditor.edit(layout) }
        prompt.onRecord = { [weak self] in self?.layoutEditor.capture(name: "") }
        madeDisplayPrompt = prompt
        return prompt
    }
    /// ⌘↩ in the card: the conversation goes on in Claude Code or Codex.
    private let handoff = HandoffLauncher()
    /// The editors' recent projects (read-only).
    private let editorProjects = EditorProjects()
    /// The user's contacts (the self-test's own, in memory, when it runs).
    private let contactBook = ContactBook()
    /// The card's Home and Work addresses found on Apple Maps, by address.
    private var cardPlaces: [String: SavedPlace] = [:]
    /// The user's calendars (the self-test's own events, in memory, when it
    /// runs).
    private let calendarBook = CalendarBook()
    /// The user's reminders (the self-test's own, in memory, when it runs).
    private let reminderBook = ReminderBook()
    /// The user's GitHub: pull requests and notifications (the self-test
    /// keeps its own token, never the user's).
    private lazy var githubBook: GitHubBook = {
        if case .selftest = mode { return GitHubBook(keychainPrefix: "selftest-") }
        return GitHubBook()
    }()
    /// Today's reminders in the menu bar.
    private lazy var reminderWatch = ReminderWatch(reminders: reminderBook, preferences: preferences)
    /// The next meeting in the menu bar, joined or offered as it starts.
    private lazy var meetingWatch = MeetingWatch(calendar: calendarBook, preferences: preferences)
    /// A meeting alert, in the middle of the screen: made for the first
    /// one (its card and views are not kept idle).
    private var madeMeetingCard: MeetingCard?
    private var meetingCard: MeetingCard {
        if let madeMeetingCard { return madeMeetingCard }
        let card = MeetingCard()
        card.onJoin = { [weak self] event in self?.calendarBook.join(event) }
        card.onShowInCalendar = { [weak self] event in self?.calendarBook.openInCalendar(event) }
        card.onOpenPrivacy = { [weak self] in
            self?.meetingCard.dismiss()
            self?.settings.show(pane: .privacy)
        }
        madeMeetingCard = card
        return card
    }
    /// Settings → Windows → Quit apps you stopped using.
    private lazy var autoQuitter: AutoQuitter = {
        let quitter = AutoQuitter(preferences: preferences)
        quitter.decisionKeys = { [ai] in AskRouter.keys(ai) }
        quitter.onFailure = { [weak self] message in self?.aiActions.notify(message, caller: "Auto Quit", run: nil, seconds: 6) }
        return quitter
    }()
    /// The folder whose new images join the clipboard history (screenshots).
    private let imageFolder = ImageFolderWatcher()
    /// Homebrew; the self-test only ever asks for --dry-run.
    private lazy var homebrew: Homebrew = {
        let homebrew = Homebrew()
        if case .selftest = mode { homebrew.dryRun = true }
        return homebrew
    }()
    /// Skillies; the self-test keeps its own folder.
    private lazy var scriptLibrary = ScriptLibrary(folders: { [mode] in
        switch mode {
        case .selftest: [FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/skillies", isDirectory: true)]
        default: [ScriptLibrary.defaultFolder]
        }
    })
    /// Inline skillies shown in the menu bar (Settings → Skillies).
    private lazy var menuBarSkillies = MenuBarSkillies(library: scriptLibrary, preferences: preferences)
    /// Quicklinks; the self-test keeps them in memory.
    private lazy var quicklinkStore = QuicklinkStore(fileURL: {
        if case .normal = mode { return QuicklinkStore.defaultFileURL }
        return nil
    }())
    /// Timers; the self-test keeps its own.
    private lazy var timers: TimerCenter = {
        if case .selftest = mode, let scratch = UserDefaults(suiteName: "skilli-selftest-timers-\(getpid())") {
            return TimerCenter(defaults: scratch)
        }
        return TimerCenter()
    }()
    /// Recent emoji: the self-test keeps its own.
    private lazy var emojiLibrary: EmojiLibrary = {
        if case .selftest = mode, let scratch = UserDefaults(suiteName: "skilli-selftest-emoji-\(getpid())") {
            return EmojiLibrary(defaults: scratch)
        }
        return EmojiLibrary()
    }()
    /// Search GIFs: Recently Used kept as ids; the self-test keeps its own.
    private lazy var gifLibrary: GIFLibrary = {
        if case .normal = mode { return GIFLibrary(recentsURL: GIFLibrary.defaultRecentsURL) }
        return GIFLibrary(recentsURL: nil, keychainAccount: "selftest-" + GIFLibrary.keyAccount)
    }()
    private lazy var snippetExpander = SnippetExpander(library: snippetLibrary, selection: selection, preferences: preferences)
    private lazy var aiActions = AIActionController(selection: selection, ai: ai, library: PromptLibrary.shared, layout: layout)
    /// Every delete of the user's data: at once, Undo ⌘Z in the card for
    /// 10 s (rule 2).
    private lazy var deletes = UndoableDeletes { [weak self] title, details, undo in
        self?.aiActions.offerUndo(title, details: details, undo)
    }
    private lazy var aiCommands: AICommandsModel = {
        let model = AICommandsModel(library: PromptLibrary.shared, shortcuts: shortcuts)
        model.toolSettings = toolSettings
        model.ai = ai
        model.deletes = deletes
        return model
    }()
    private let toolSettings: ToolSettings
    /// Where skil.li's tool server listens; nil in the benchmark.
    private let toolSocketPath: String?
    private lazy var toolServer = MCPService(
        tools: SkilliTools(selection: selection, library: PromptLibrary.shared, ai: ai),
        settings: toolSettings
    )
    /// skil.li's own settings for agents: the same preferences and stores
    /// as the panes (the self-test's scratch ones when it runs).
    private lazy var settingTools: SettingTools = {
        let tools = SettingTools(preferences: preferences, shortcuts: shortcuts, quicklinks: quicklinkStore, snippets: snippetLibrary,
                                 toolSettings: toolSettings)
        tools.ai = ai
        tools.aiCommands = aiCommands
        tools.github = githubBook
        tools.gifs = gifLibrary
        tools.permissions = permissions
        tools.clipboard = clipboard
        tools.calendarAccounts = { [calendarBook] in calendarBook.calendarAccounts() }
        tools.reminderLists = { [reminderBook] in reminderBook.listNames() }
        tools.windowLayouts = { [arranger] in arranger.layouts().map(\.name) }
        tools.skillies = { [scriptLibrary] in scriptLibrary.all() }
        tools.findApp = { [weak self] name in self?.toolServer.tools.findApp?(name) }
        tools.aliasTargets = { [weak self] in self?.aliasTargets() ?? [] }
        tools.shortcutActions = { [weak self] in self?.shortcutActions() ?? [] }
        tools.catalogEntries = { [weak self] in FeatureCatalog.entries(self?.catalogInput() ?? FeatureCatalog.Input()) }
        tools.scheduler = scheduler
        tools.agentSkills = { [weak self] in self?.agentSkills() ?? [] }
        return tools
    }()
    private lazy var actions = ActionRunner(launcher: launcher, selection: selection, ai: aiActions)
    /// Settings → Launcher → Type in English while open.
    private lazy var englishTyping: EnglishTyping = {
        let typing = EnglishTyping(layout: layout)
        typing.isOn = { [preferences] in preferences.launcherEnglishInput }
        return typing
    }()
    /// `skilli://run/…`, `quicklink/…`, `layout/…`, `skillie/…`: what each
    /// Catalog row does, from another app (asked first when it must).
    private lazy var links: LinkRunner = {
        let runner = LinkRunner()
        runner.entries = { [weak self] in FeatureCatalog.entries(self?.catalogInput() ?? FeatureCatalog.Input()) }
        runner.quicklinks = { [quicklinkStore] in quicklinkStore.links }
        runner.skillies = { [scriptLibrary] in scriptLibrary.all() }
        runner.skillieFolders = { [scriptLibrary] in scriptLibrary.folders() }
        runner.approve = { [weak self] title, detail, offersAlways in
            guard let self else { return .deny }
            return await self.aiActions.approve(title, detail: detail, caller: "skil.li Link", run: nil, once: !offersAlways)
        }
        runner.trust = { [toolSettings] in toolSettings.linkTrust }
        runner.onAlways = { [toolSettings] run, entry, title, arguments in
            toolSettings.trustLink(run, entry: entry, title: title, arguments: arguments)
        }
        runner.runEntry = { [weak self] entry in self?.launcher.run(fromLink: entry) }
        runner.openAddress = { [weak self] url in self?.openQuicklinkAddress(url) }
        runner.selectedText = { [weak self] in await self?.selection.read()?.text }
        runner.runSkillie = { [weak self] command, arguments in self?.runScript(command, arguments: arguments) }
        runner.notify = { [weak self] message in self?.aiActions.notify(message, caller: "skil.li Link", run: nil, seconds: 6) }
        runner.bringForward = { [weak self] name in
            try await ControlTarget.bringForward(name, findApp: { self?.toolServer.tools.findApp?($0) })
        }
        runner.doItHere = { [weak self] goal, pid in
            await self?.aiActions.doItHere(goal, pid: pid, caller: "skil.li Link", run: nil, saysStop: true).outcome == .done
        }
        runner.onAlwaysDo = { [toolSettings] goal, app in toolSettings.trustDoLink(goal: goal, app: app, title: "Do It Here") }
        if case .selftest = mode { runner.handsFocusBack = false }
        return runner
    }()
    private var router: KeyRouter?
    private var statusItem: NSStatusItem?
    /// "Shortcuts paused…" in the status menu while Secure Input is on.
    private var secureInputItem: NSMenuItem?
    private var tapRetryTimer: Timer?
    private var didPromptForAccessibility = false
    private var signalSource: DispatchSourceSignal?
    private var selfTestStarted = false

    init(mode: LaunchMode) {
        self.mode = mode
        // The self-test's sensitive form fields never touch the user's.
        if case .selftest = mode { FormSecrets.prefix = "selftest-" }
        // The linked apps' files before the shortcuts, which name their
        // commands by id: a few small files, read once here. The
        // self-test keeps its own folder; the benchmark reads skil.li's only.
        switch mode {
        case .normal: break
        case .selftest:
            LinkedApps.folder = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())/Apps", isDirectory: true)
        case .benchmark: LinkedApps.folder = nil
        }
        LinkedApps.readFiles(force: true)
        switch mode {
        case .normal:
            shortcuts = ShortcutStore(fileURL: ShortcutStore.defaultFileURL)
            learning = LearningStore(fileURL: LearningStore.defaultFileURL)
            recentSearches = RecentSearchStore(fileURL: RecentSearchStore.defaultFileURL)
            toolSettings = ToolSettings(fileURL: ToolSettings.defaultFileURL)
            toolSocketPath = MCPSocketServer.defaultPath
        case .selftest:
            // Never touch the user's shortcuts, prompts or what skil.li learned.
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-selftest-\(getpid())")
            PromptLibrary.shared = PromptLibrary(folder: scratch.appendingPathComponent("prompts", isDirectory: true))
            shortcuts = ShortcutStore(fileURL: scratch.appendingPathComponent("shortcuts.json"))
            learning = LearningStore(fileURL: nil)
            recentSearches = RecentSearchStore(fileURL: nil)
            toolSettings = ToolSettings(fileURL: scratch.appendingPathComponent("tools.json"), keychainPrefix: "selftest-")
            toolSocketPath = scratch.appendingPathComponent("mcp.sock").path
        case .benchmark:
            PromptLibrary.shared = PromptLibrary(folder: nil)
            shortcuts = ShortcutStore(fileURL: nil)
            learning = LearningStore(fileURL: nil)
            recentSearches = RecentSearchStore(fileURL: nil)
            toolSettings = ToolSettings(fileURL: nil)
            toolSocketPath = nil
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        routeTerminationSignal()
        // LaunchServices' first answer (~15 ms) off the main thread, before
        // the launcher's rows ask for CleanShot X; the user's shortcuts with
        // it (Apple's tool, a process).
        Task.detached(priority: .userInitiated) {
            LinkedApps.read()
            AppleShortcuts.read()
        }
        launcher.prewarm()

        if case .benchmark(let outputPath) = mode {
            Task {
                await appIndex.reload(usage: usage)
                let snapshotDirectory = outputPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
                let report = await Benchmark.run(
                    launcher: launcher,
                    index: appIndex,
                    usage: usage,
                    layout: layout,
                    overlay: overlay,
                    snapshotDirectory: snapshotDirectory
                )
                Benchmark.emit(report, to: outputPath)
                NSApp.terminate(nil)
            }
            return
        }

        Task { await appIndex.reload(usage: usage) }
        // System Settings' panes, for the launcher and Ask: read once
        // (~50 ms), not on the first key.
        Task.detached(priority: .utility) { _ = SystemSettingsPanes.all() }

        // First launch: the setup window says why Accessibility and the
        // user's SI, before macOS's own prompt. Closed once, never again by
        // itself (D7): the menu bar, Settings → General and the launcher's
        // first row offer it while Accessibility is off.
        if case .normal = mode, SetupWindowController.showsByItself(closedOnce: preferences.didCompleteSetup) {
            showWelcome()
        }

        let plan = remapper.activate()
        Log.input.notice("Hyper plan: \(String(describing: plan), privacy: .public)")
        // The welcome opened just before: Caps Lock as it is now.
        if madeSetup { setup.model.hyperKey = remapper.welcomeState }

        var triggerKeyCodes = remapper.triggerKeyCodes
        if case .selftest = mode {
            // A trigger no other Hyper tool listens to, so the self-test can
            // exercise skil.li's own Hyper handling next to Raycast's.
            #if SKILLI_SELFTEST
            triggerKeyCodes.insert(SelfTest.ownTriggerKeyCode)
            #endif
        }
        shortcuts.resolveKey = { [layout] code in layout.key(for: CGKeyCode(code)) }
        // Before the engine binds the shortcuts' names (✦K's overlay).
        SkilliAction.snippetName = { [snippetLibrary] id in snippetLibrary.snippet(id)?.name }
        SkilliAction.quicklinkName = { [quicklinkStore] id in quicklinkStore.links.first { $0.id == id }?.name }
        let router = KeyRouter(
            engine: shortcuts.makeEngine(),
            triggerKeyCodes: triggerKeyCodes,
            layout: layout,
            overlay: overlay
        ) { [weak self] action, triggeredAt in
            self?.actions.perform(action, triggeredAt: triggeredAt)
        }
        self.router = router
        router.onTypedKey = { [weak self] event in self?.snippetExpander.keyDown(event) ?? false }
        router.onHyperChange = { [weak self] held, tapped in self?.shownWelcome?.hyperChanged(held: held, tapped: tapped) }
        router.forwardToLauncher = { [weak self] event in
            self?.launcher.deliver(event) ?? false
        }
        launcher.onCommand = { [weak self] command in
            self?.run(command)
        }
        if case .normal = mode {
            // Not in the self-test: its launcher checks read the first row.
            launcher.missingPermissions = { [weak self] in
                guard let self else { return [] }
                // Only what the rows can show (once per show).
                self.permissions.refreshAttention()
                return self.permissions.needsAttention
            }
            launcher.onSetup = { [weak self] permission in
                self?.permissions.refresh([permission])
                switch permission.askedFrom {
                case .setup: self?.showWelcome(at: .accessibility)
                case .privacyPane: self?.settings.show(pane: .privacy)
                // macOS's own question right here, or its list once refused (D7).
                case .inPlace: self?.permissions.grant(permission)
                }
            }
            aiActions.onPermissionNeeded = { [weak self] permission in self?.permissions.needed(permission) }
            aiActions.onGrant = { [weak self] permission in self?.permissions.grant(permission) }
            toolServer.tools.onPermissionNeeded = { [weak self] permission in self?.permissions.needed(permission) }
        }
        launcher.systemCommands = { [weak self] in
            let current = (output: AudioDevices.current(output: true)?.uid, input: AudioDevices.current(output: false)?.uid)
            // Wi-Fi as last read: only the way it can go (no Wi-Fi: neither).
            let wifi = WiFi.cachedIsOn
            return MacAction.all.filter { action in
                switch action {
                case .system(.wifiOn): wifi == false
                case .system(.wifiOff): wifi == true
                default: true
                }
            }.map { action in
                (action, action == .system(.keepAwake) && self?.systemCommands.isKeepingAwake == true ? "Allow Sleep" : action.title)
            } + MacAction.sounds().map { action in
                guard case .sound(let target) = action, target.uid == (target.output ? current.output : current.input) else { return (action, action.title) }
                return (action, action.title + " (current)")
            } + MacAction.bluetoothDevices().map { ($0, $0.title) }
                + MacAction.settingsPanes().map { ($0, $0.title) }
                + MacAction.appLinks().map { ($0, $0.title) }
                + MacAction.appleShortcuts().map { ($0, $0.title) }
        }
        // Wi-Fi, Bluetooth, the linked apps and the shortcuts read again as
        // the launcher opens, off the main thread; a change redraws the rows.
        launcher.onShow = { [weak self] in self?.refreshRadios() }
        launcher.bluetoothAskable = { BluetoothDevices.authorization == .notDetermined }
        launcher.clipboardItems = { [weak self] text in self?.clipboard.search(text) ?? [] }
        launcher.clipboardImageURL = { [weak self] item in self?.clipboard.store?.imageURL(item) }
        launcher.clipboardPreview.links = clipboard.links
        launcher.clipboardStatus = { [weak self] in self?.clipboardStatus }
        launcher.onClipboardMode = { [weak self] in
            guard let self, self.preferences.clipboardHistory, !self.clipboard.mayRead else { return }
            self.permissions.needed(.pasteboard)
        }
        launcher.onDeleteClip = { [weak self] item in
            guard let self else { return }
            self.deletes.clip(item, in: self.clipboard) { [weak self] in
                if self?.launcher.isVisible == true { self?.launcher.refreshResults() }
            }
        }
        launcher.onMovedToTrash = { [weak self] original, trashed in self?.deletes.movedToTrash(original, now: trashed) }
        launcher.snippets = { [snippetLibrary] in snippetLibrary.all }
        launcher.onSnippet = { [weak self] snippet, copy in
            guard let self else { return }
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.snippetExpander.text(of: snippet), forType: .string)
                return
            }
            // Let the app that was in front get its focus back first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Task { await self.snippetExpander.insert(snippet) }
            }
        }
        // Search Snippets' preview: what the expander would type now, when
        // keywords expand, the file's date.
        launcher.snippetPreviewPieces = { [weak self] snippet in
            self?.snippetExpander.preview(of: snippet) ?? (snippet.expansion([:]), [])
        }
        launcher.snippetExpands = { [preferences] in
            guard preferences.snippetExpansion else { return "Off" }
            if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
               preferences.snippetExcludedApps.contains(id) {
                return "Not in \(app.localizedName ?? "this app")"
            }
            return preferences.snippetExpansionMode.title
        }
        launcher.snippetModified = { [snippetLibrary] snippet in snippetLibrary.modified(snippet.id) }
        launcher.snippetMeaningAvailable = { [weak self] in
            guard let self else { return false }
            return self.preferences.snippetMeaningSearch && !AskRouter.keys(self.ai).isEmpty
        }
        launcher.snippetMeaning = { [weak self] request in
            guard let self, self.preferences.snippetMeaningSearch else { return nil }
            return await self.snippetLibrary.searchByMeaning(request, keys: AskRouter.keys(self.ai))
        }
        actions.onPasteInSequence = { [weak self] in self?.pasteInSequence() }
        // Every launcher command, snippet and quicklink takes a shortcut:
        // what opens no mode runs as its row does, a snippet is typed.
        actions.onCommand = { [weak self] command in self?.run(command) }
        actions.onSnippet = { [weak self] snippet in
            guard let self else { return }
            Task { await self.snippetExpander.insert(snippet) }
        }
        launcher.filesByMeaningAvailable = { [weak self] in
            guard let self else { return false }
            return self.preferences.fileMeaningSearch && !AskRouter.keys(self.ai).isEmpty
        }
        launcher.fileDecisionKeys = { [weak self] in self.map { AskRouter.keys($0.ai) } ?? [:] }
        launcher.historyByMeaningAvailable = { [weak self] in
            guard let self else { return false }
            return self.preferences.historyMeaningSearch && !AskRouter.keys(self.ai).isEmpty
        }
        launcher.historyDecisionKeys = { [weak self] in self.map { AskRouter.keys($0.ai) } ?? [:] }
        launcher.onOpenVisit = { visit, copy in BrowserHistory.open(visit, copy: copy) }
        launcher.homebrew = homebrew
        launcher.onBrew = { [weak self] action, package in self?.runBrew(action, package) }
        toolServer.tools.homebrew = homebrew
        launcher.quicklinks = { [quicklinkStore] in quicklinkStore.links }
        launcher.onOpenURL = { [weak self] url in self?.openQuicklinkAddress(url) }
        launcher.onOpened = { [weak self] in
            self?.englishTyping.launcherOpened()
            self?.shownWelcome?.launcherShown()
        }
        launcher.onClosed = { [weak self] in
            self?.englishTyping.launcherClosed()
            self?.shownWelcome?.launcherClosed()
        }
        launcher.chordEvent = { [weak self] event in self?.englishTyping.chordEvent(event) ?? event }
        launcher.skilliePath = { [scriptLibrary] path in SkilliLink.skilliePath(path, folders: scriptLibrary.folders().map(\.path)) }
        launcher.runningTimers = { [timers] in timers.timers }
        launcher.timerRemaining = { [timers] timer in timers.remaining(timer) }
        launcher.onStartTimer = { [weak self] request in self?.startTimer(request) }
        launcher.onKeepAwake = { [weak self] request in self?.aiActions.keepAwake(request) }
        launcher.onCancelTimer = { [timers] timer in timers.cancel(timer.id) }
        aiActions.startTimer = { [weak self] request in self?.startTimer(request) ?? UUID() }
        aiActions.cancelTimer = { [timers] id in timers.cancel(id) }
        timers.onDone = { [weak self] timer in
            self?.aiActions.notify("⏱ \(timer.label.isEmpty ? "Timer" : timer.label) — \(TimerRequest.spoken(timer.seconds)), done.",
                                   caller: "Timer", run: nil, seconds: 12)
        }
        toolServer.tools.timers = timers
        launcher.windowLayouts = { [arranger] in arranger.layouts() }
        launcher.onLayout = { [weak self] layout in self?.applyLayout(layout) }
        // "save layout Coding": every window open, looked over in the editor first.
        launcher.onSaveLayout = { [layoutEditor] name in layoutEditor.capture(name: name) }
        launcher.onEditLayout = { [layoutEditor] layout in layoutEditor.edit(layout) }
        launcher.onUpdateLayout = { [layoutEditor] layout in layoutEditor.update(layout) }
        launcher.onDeleteLayout = { [weak self] layout in self?.deleteLayout(layout) }
        shortcuts.deletes = deletes
        layoutEditor.onTry = { [weak self] layout in self?.applyLayout(layout) }
        displayWatch.onPlugged = { [weak self] plugged in self?.displaysPlugged(plugged) }
        displayWatch.onUnplugged = { [weak self] gone in self?.displaysUnplugged(gone) }
        // The self-test offers displays itself: nothing is plugged there.
        if case .normal = mode {
            displayWatch.start()
            if SoftwareUpdate.isConfigured { updates = SoftwareUpdate() }
        }
        // Made now: it follows which app is in front, for links to come.
        if case .normal = mode { _ = links }
        launcher.openWindows = { [arranger] in arranger.windows() }
        launcher.onFocusWindow = { [arranger] window in arranger.focus(window) }
        actions.onWindowLayout = { [weak self] id in
            guard let self, let layout = self.arranger.layouts().first(where: { $0.id == id }) else { return }
            self.applyLayout(layout)
        }
        toolServer.tools.arranger = arranger
        toolServer.tools.layoutIgnoredApps = { [preferences] in preferences.windowLayoutIgnoredApps }
        toolServer.tools.projects = editorProjects
        launcher.projects = { [editorProjects] in editorProjects.all() }
        aiActions.recentProjects = { [editorProjects] in editorProjects.all() }
        launcher.onOpenProject = { project, reveal in EditorProjects.open(project, reveal: reveal) }
        launcher.scripts = { [scriptLibrary] in scriptLibrary.all() }
        launcher.scriptInline = { [scriptLibrary] in scriptLibrary.inlineLine($0) }
        launcher.refreshInlineScripts = { [scriptLibrary] done in scriptLibrary.refreshInline(done: done) }
        launcher.onRunScript = { [weak self] command, arguments in self?.runScript(command, arguments: arguments) }
        toolServer.tools.scripts = scriptLibrary
        scriptLibrary.toolSocket = { [toolServer] in toolServer.socketPath }
        aiActions.scriptCommands = { [scriptLibrary] in scriptLibrary.all() }
        aiActions.runScript = { [weak self] command, askFirst in self?.runScript(command, arguments: [], askFirst: askFirst) }
        aiActions.appleShortcuts = { AppleShortcuts.all() }
        aiActions.runShortcut = { [weak self] shortcut, input, askFirst in self?.runShortcut(shortcut, input: input, askFirst: askFirst) }
        launcher.onRunShortcut = { [weak self] shortcut, input in self?.runShortcut(shortcut, input: input) }
        launcher.onEditShortcut = { [weak self] shortcut in self?.editShortcut(shortcut) }
        launcher.emojiSearch = { [emojiLibrary] text in emojiLibrary.search(text) }
        launcher.emojiByFeelingAvailable = { [weak self] in
            guard let self else { return false }
            return self.preferences.emojiMeaningSearch && !AskRouter.keys(self.ai).isEmpty
        }
        launcher.emojiByFeeling = { [weak self] text in
            guard let self else { return nil }
            return await self.emojiLibrary.searchByMeaning(text, keys: AskRouter.keys(self.ai))
        }
        launcher.emojiTone = { [preferences] in preferences.emojiSkinTone }
        launcher.typingKeys = { [layout] character in layout.keys(typing: character) }
        launcher.onEmoji = { [weak self] emoji, copy, saidAs in
            guard let self else { return }
            self.emojiLibrary.used(emoji)
            if let saidAs { self.emojiLibrary.learn(saidAs, for: emoji) }
            let character = emoji.character(in: self.preferences.emojiSkinTone)
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(character, forType: .string)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Task { await self.selection.replace(with: character) }
            }
        }
        launcher.gifLibrary = gifLibrary
        launcher.gifEditors = Set(EditorProjects.editors.map(\.bundleID))
        launcher.onGIF = { [weak self] gif, use, query in self?.useGIF(gif, use, query: query) }
        // A paste's temp file from a run before: Klipy's GIFs are not kept.
        GIFLibrary.removePasteFiles()
        launcher.onCalculation = { [weak self] result, paste in
            guard let self else { return }
            if paste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Task { await self.selection.replace(with: result.copy) }
                }
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.copy, forType: .string)
        }
        toolServer.tools.snippets = snippetLibrary
        toolServer.tools.insertSnippet = { [weak self] snippet in await self?.snippetExpander.insert(snippet) }
        launcher.clipboardMeaningAvailable = { [weak self] in
            guard let self else { return false }
            return self.preferences.clipboardMeaningSearch && !AskRouter.keys(self.ai).isEmpty
        }
        launcher.clipboardMeaning = { [weak self] request in
            guard let self, self.preferences.clipboardMeaningSearch else { return nil }
            return await self.clipboard.searchByMeaning(request, keys: AskRouter.keys(self.ai))
        }
        launcher.onClip = { [weak self] item, use in
            guard let self else { return }
            guard self.clipboard.write(item, plain: use == .pastePlain) else {
                // Rule 6: what happened and what to do, never a bare beep.
                let line = switch (item.kind, use) {
                case (.image, .pastePlain): "This image has no text to paste as plain text: ↩ pastes the image itself."
                case (.image, _): "This image is no longer in the history's folder: pick another copy with ✦C."
                default: "macOS did not take this copy on the clipboard: try it again with ✦C."
                }
                self.aiActions.notify(line, caller: "Clipboard", run: nil)
                return
            }
            Log.trace("Clipboard: \(use) \(item.kind.rawValue)")
            guard use != .copy else { return }
            // Let the app that was in front get its focus back first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.selection.press("v", flags: .maskCommand)
            }
        }
        launcher.onQuitProcess = { [weak self] group, force in
            guard let self else { return }
            Task {
                let others = group.entries.count - 1
                let title = (force ? "Force Quit " : "Quit ") + group.name + (others > 0 ? " and its \(others) other process" + (others > 1 ? "es" : "") : "")
                // A quit at once: the app asks to save itself. A force quit
                // loses what is not saved: asked.
                if force {
                    guard await self.aiActions.approve(title, detail: "Unsaved changes are lost.", caller: "Kill Process", run: nil,
                                                       once: true, verb: "Force Quit", fromUser: true) != .deny else {
                        Log.trace("Kill Process: \(title), denied")
                        return
                    }
                }
                do {
                    // The app gone is the answer: nothing said.
                    let said = try Processes.quit(group, force: force)
                    Log.trace("Kill Process: \(said)")
                } catch {
                    Log.actions.notice("Kill Process: \(error.localizedDescription, privacy: .public)")
                    self.aiActions.notify(error.localizedDescription, caller: "Kill Process", run: nil)
                }
            }
        }
        launcher.onSystemCommand = { [weak self] action in self?.runMac(action) }
        launcher.onOpenFile = { [weak self] file, command, title in self?.aiActions.openFile(file, with: command, title: title) }
        actions.onMac = { [weak self] action in self?.runMac(action) }
        aiActions.systemCommands = systemCommands
        toolServer.tools.systemCommands = systemCommands
        systemCommands.pressPaste = { [selection] in
            // From the launcher or the card: the app that was in front
            // gets its focus back first.
            try? await Task.sleep(for: .milliseconds(50))
            selection.press("v", flags: .maskCommand)
        }
        systemCommands.screenshotFolders = { [preferences] in [ImageFolderWatcher.screenshotsFolder, preferences.imageFolder] }
        systemCommands.appLinkDefault = { [preferences] command in
            CleanShot.defaultVariant(of: command, lineBreaks: preferences.cleanShotTextLineBreaks)
        }
        toolServer.tools.contacts = contactBook
        launcher.contacts = contactBook
        aiActions.contacts = contactBook
        // Dictate: the contacts' names for the recognizer, only when they
        // are allowed already; the ones picked in the launcher first.
        aiActions.dictationVocabulary = { [contactBook, learning] in
            guard contactBook.isAllowed else { return .empty }
            let records = await contactBook.records()
            let me = await contactBook.me()
            let picks = learning.picks(prefix: "contact:")
            return await Task.detached(priority: .userInitiated) { DictationVocabulary(contacts: records, me: me, picks: picks) }.value
        }
        aiActions.dictateChords = { [shortcuts] in
            shortcuts.config.shortcuts.compactMap { entry in
                guard entry.action == .dictate, shortcuts.problems[entry.id] == nil, let chords = entry.chords, chords.count == 1 else { return nil }
                return chords[0]
            }
        }
        aiActions.dictationExcludedApps = { [preferences] in Set(preferences.clipboardExcludedApps) }
        aiActions.formProfiles = { [preferences] in preferences.formProfiles }
        launcher.aliases = { [preferences] in preferences.launcherAliases }
        launcher.onUninstall = { [weak self] app in self?.aiActions.runUninstall(app) }
        launcher.onSetShortcut = { [weak self] action, name in self?.recordShortcut(for: action, named: name) }
        launcher.onSetAlias = { [weak self, preferences] id, title, alias in
            // Removed (⌘K → Remove Alias, or the field left empty): ⌘Z
            // gives it back.
            if alias.trimmingCharacters(in: .whitespaces).isEmpty, preferences.launcherAliases.contains(where: { $0.id == id }) {
                self?.deletes.alias(of: id, in: preferences) { [weak self] in
                    if self?.launcher.isVisible == true { self?.launcher.refreshResults() }
                }
                return
            }
            preferences.launcherAliases = LauncherAliases.setting(alias, id: id, title: title, in: preferences.launcherAliases)
        }
        toolServer.tools.calendar = calendarBook
        launcher.calendar = calendarBook
        aiActions.calendar = calendarBook
        launcher.onShowAgenda = { [weak self] request in self?.aiActions.showAgenda(request) }
        launcher.onShowEvent = { [weak self] event in self?.aiActions.showEvent(event) }
        launcher.onCreateEvent = { [weak self] request in self?.aiActions.createEvent(request) }
        if case .selftest = mode {
            // Never the Mac's own: each check brings its events and reminders.
            calendarBook.readsTheMac = false
            reminderBook.readsTheMac = false
            // Contacts already allowed are read; never asked for there.
            contactBook.asksTheMac = false
        }
        toolServer.tools.reminders = reminderBook
        launcher.reminders = reminderBook
        aiActions.reminders = reminderBook
        launcher.onAddReminder = { [weak self] request in self?.aiActions.addReminder(request) }
        launcher.onReminderAction = { [weak self] item, choice in self?.aiActions.runReminderAction(item, choice) }
        launcher.onDeleteReminder = { [weak self] item in self?.aiActions.deleteReminder(item) }
        reminderBook.onChange = { [weak self] in self?.reminderWatch.refresh() }
        reminderWatch.onOpenReminders = { [weak self] in self?.launcher.openReminders() }
        toolServer.tools.github = githubBook
        launcher.github = githubBook
        aiActions.github = githubBook
        launcher.showsGitHubStrip = { [preferences] in preferences.githubUnderSearch }
        launcher.onPullRequestAction = { [weak self] pullRequest, choice in self?.aiActions.runPullRequestAction(pullRequest, choice) }
        launcher.onNotice = { [weak self] message in self?.aiActions.notify(message, caller: "skil.li", run: nil, seconds: 1.5) }
        launcher.onChangedInPlace = { [weak self] in self?.aiActions.dropUndo() }
        launcher.onFailure = { [weak self] message in self?.aiActions.notify(message, caller: "skil.li", run: nil) }
        ContactBook.onFailure = { [weak self] message in self?.aiActions.notify(message, caller: "Contacts", run: nil) }
        launcher.onGitHubSettings = { [weak self] in self?.settings.show(pane: .github) }
        githubBook.onChange = { [weak self] in self?.launcher.updateGitHubStrip() }
        calendarBook.onChange = { [weak self] in self?.meetingWatch.refresh() }
        // Joined from skil.li: the menu bar counts down at once.
        calendarBook.onJoin = { [weak self] in self?.meetingWatch.refresh() }
        permissions.onCalendarGranted = { [weak self] in self?.meetingWatch.refresh() }
        meetingWatch.onOpenAgenda = { [weak self] in self?.launcher.openAgenda() }
        meetingWatch.onAlert = { [weak self] event, alert in self?.meetingCard.show(event, dark: alert.style == .dark) }
        // In the call already (Join from the menu bar, the launcher or Ask,
        // or a call on the microphone): its alert goes, the screens come back.
        meetingWatch.onInCall = { [weak self] calls in
            if let card = self?.madeMeetingCard, let event = card.event, calls.contains(MeetingBar.key(event)) { card.dismiss() }
        }
        launcher.onDeleteEvent = { [weak self] event in self?.aiActions.deleteEvent(event) }
        launcher.onShowContact = { [weak self] record in self?.aiActions.showContact(record) }
        launcher.siCommands = {
            PromptLibrary.shared.all.map { LauncherSICommand(id: $0.id, title: $0.title) }
        }
        // The Catalog ("?"): what the user made, and each action's first
        // shortcut that works; what is off in Settings → Catalog.
        launcher.catalogInput = { [weak self] in self?.catalogInput() ?? FeatureCatalog.Input() }
        launcher.catalogOff = { [preferences] in preferences.catalogOff }
        launcher.shortcutKeys = { [shortcuts] in
            var keys: [String: [Chord]] = [:]
            for entry in shortcuts.config.shortcuts where shortcuts.problems[entry.id] == nil && keys[entry.action.id] == nil {
                if let chords = entry.chords { keys[entry.action.id] = chords }
            }
            return keys
        }
        launcher.onAction = { [weak self] action in
            // Let the app that was in front get its focus back first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.actions.perform(action, triggeredAt: .now)
            }
        }
        launcher.onSettingsPane = { [weak self] pane, section in self?.settings.show(pane: pane, section: section) }
        launcher.onSICommand = { [weak self] id, instruction in
            // The card takes the launcher's place.
            let frame = self?.launcher.glassFrame
            // Let the app that was in front get its focus back first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.aiActions.run(id, triggeredAt: .now, answers: instruction.map { ["instruction": $0] } ?? [:], fromLauncher: frame)
            }
        }
        aiActions.launcherSpot = { [weak self] in self?.launcher.restingGlassFrame() ?? .zero }
        aiActions.openLauncherFrame = { [weak self] in
            guard let launcher = self?.launcher, launcher.isVisible else { return nil }
            return launcher.glassFrame
        }
        handoff.claudeBinary = { [ai] in ai.subscription.binary }
        aiActions.handoff = handoff
        aiActions.handoffChoice = { [preferences] in (preferences.handoffTarget, preferences.handoffTerminal) }
        launcher.onOpenSettings = { [weak self] in
            self?.settings.show()
        }
        launcher.resolveKey = { [layout] code in layout.key(for: CGKeyCode(code)) }
        launcher.openSettingsChord = shortcuts.launcherOpenSettingsChord
        launcher.savedPlace = { [preferences] in preferences.launcherPlace }
        launcher.screenChoice = { [preferences] in preferences.launcherScreen }
        launcher.resetChoice = { [preferences] in preferences.launcherReset }
        launcher.pins = { [preferences] in preferences.launcherPins }
        launcher.onPinsChange = { [preferences] pins in preferences.launcherPins = pins }
        launcher.onPlaceChange = { [preferences] place in preferences.launcherPlace = place }
        actions.onOpenSettings = { [weak self] in
            self?.settings.show()
        }
        router.interceptForAI = { [weak self] key, modifiers, keyCode, event in
            guard let self else { return false }
            // The launcher opened over a card gets the keys: Esc closes the
            // launcher, not the card behind it. Only ⌘Z goes to an undo
            // card shown under it (a copy forgotten with ⌘⌫).
            if self.launcher.isVisible { return self.aiActions.undoKey(key, modifiers) }
            // A panel of skil.li's that took the keyboard to ask something
            // (a display plugged in, a meeting alert with the screens dark):
            // its keys are its own, esc included; a card behind it takes
            // only ⌘Z for its undo (rule 4).
            if self.ownWindowHasKeyboard { return self.aiActions.undoKey(key, modifiers) }
            return self.aiActions.handleKey(key, modifiers, keyCode, flags: event.flags, event: event)
        }
        router.repeatForAI = { [weak self] event in
            guard let self, !self.launcher.isVisible, !self.ownWindowHasKeyboard else { return false }
            return self.aiActions.repeatKey(event)
        }
        aiActions.onOpenSettings = { [weak self] in
            self?.settings.show(pane: .aiAccounts)
        }
        startToolServer()
        shortcuts.onEngineChange = { [weak self] engine in
            guard let self else { return }
            self.router?.replaceEngine(engine)
            self.launcher.openSettingsChord = self.shortcuts.launcherOpenSettingsChord
            // The status menu says the launcher's keys as they are now.
            if let menu = self.statusItem?.menu { self.showStatusMenuKeys(menu) }
            // ⌘Space for the launcher turns Spotlight's off, as Raycast does;
            // never from the self-test or the benchmark.
            if case .normal = self.mode {
                SpotlightKey.launcherKeysChanged(self.shortcuts.launcherEntry?.keys)
            }
        }
        shortcuts.onRecordingChange = { [weak self] recording in
            self?.router?.isRecording = recording
        }
        router.recordHandler = { [weak self] event in
            self?.shortcuts.handleRecording(event) ?? false
        }

        installStatusItem()
        preferences.onChange = { [weak self] preferences in
            self?.apply(preferences)
        }
        apply(preferences)
        startEventTap()
        if case .normal = mode {
            // Finds Claude Code and starts the spare if the user wants it;
            // writes the built-in AI prompt files the first time.
            Task { await ai.refresh() }
            PromptLibrary.shared.reload()
        }

        #if SKILLI_SELFTEST
        if case .selftest(let outputPath, _) = mode {
            // Without Accessibility the tap never starts; report instead of hanging.
            Task {
                try? await Task.sleep(for: .seconds(8))
                guard !self.selfTestStarted else { return }
                SelfTest.emit(.init(passed: 0, failed: 1, checks: [
                    .init(name: "Event tap", passed: false, detail: "tap not running — Accessibility not granted to this build", latencyMs: nil)
                ]), to: outputPath)
                NSApp.terminate(nil)
            }
        }
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // System Settings quits skil.li so a permission takes effect, and on
        // macOS 26 does not open it again: skil.li does, once it has quit.
        if mode == .normal, Relaunch.quitBySystemSettings() { Relaunch.afterExit() }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        remapper.deactivate()
        // The user's own input source, if the launcher had switched it.
        englishTyping.launcherClosed()
        ai.subscription.dropSpare()
        toolServer.stop()
    }

    /// skil.li's MCP server, for Act commands and any agent (`Skilli mcp`).
    private func startToolServer() {
        guard let toolSocketPath else { return }
        toolServer.tools.performAction = { [weak self] action in self?.actions.perform(action, triggeredAt: .now) }
        toolServer.tools.findApp = { [weak self] name in
            // The app's own name, give or take case, accents and a version
            // ("Affinity Designer" → "Affinity Designer 2"): never whatever
            // fuzzy search ranks first.
            let wanted = name.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard wanted.count >= 2 else { return nil }
            let entries = self?.appIndex.entries ?? []
            let folded = entries.map { ($0, $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
            return (folded.first { $0.1 == wanted }
                ?? folded.first { $0.1.hasPrefix(wanted + " ") || ($0.1.count >= 4 && wanted.hasPrefix($0.1 + " ")) })?.0.url
        }
        toolServer.tools.similarApps = { [weak self] name in
            guard let self else { return [] }
            return self.appIndex.search(name, usage: self.usage, limit: 5).map(\.name)
        }
        toolServer.tools.installedApps = { [weak self] in
            self?.appIndex.entries.map { ($0.name, $0.url) } ?? []
        }
        toolServer.tools.doItHere = { [weak self] goal, pid, caller, run in
            guard let self else { return AIActionController.ControlReport(app: "", outcome: .cancelled, steps: [], took: .zero) }
            return await self.aiActions.doItHere(goal, pid: pid, caller: caller, run: run, saysStop: false)
        }
        aiActions.installedApps = { [weak self] in
            self?.appIndex.entries.map { ($0.name, $0.url) } ?? []
        }
        toolServer.settingTools = settingTools
        toolServer.judge = RuleJudge { [weak self] in self.map { AskRouter.keys($0.ai) } ?? [:] }
        toolServer.presenter = aiActions
        aiActions.tools = toolServer
        toolServer.tools.skillsFolder = skillsFolder
        aiActions.agentSkills = { [weak self] in self?.agentSkills() ?? [] }
        aiActions.scheduler = scheduler
        aiActions.launcherIsOpen = { [weak self] in self?.launcher.isVisible ?? false }
        scheduler.run = { [weak self] ask in
            await self?.aiActions.runScheduled(ask) ?? ("skil.li could not run it.", true)
        }
        toolServer.start(path: toolSocketPath)
        if case .benchmark = mode {} else {
            clipboard.start()
            clipboard.imageKey = { [weak self] in self?.ai.decisionKey(for: .typeSafe) }
            imageFolder.onImage = { [weak self] url, date in
                self?.clipboard.keepImage(at: url, made: date, from: FileManager.default.displayName(atPath: url.deletingLastPathComponent().path))
            }
            if case .normal = mode {
                clipboard.tagUntagged()
                watchImageFolder()
            }
            snippetExpander.start()
            timers.restore()
            scheduler.start()
            if case .normal = mode {
                systemCommands.restoreAwake()
                autoQuitter.start()
            }
            refreshRadios()
        }
    }

    /// What an alias can name: the launcher's items it finds again by id
    /// (`LauncherController.takesAlias`).
    private func aliasTargets() -> [SettingTools.AliasTarget] {
        var items: [(item: LauncherItem, kind: String)] = []
        items += appIndex.entries.map { (.app($0), "App") }
        items += LauncherCommand.all.map { (.command($0), "Command") }
        items += PromptLibrary.shared.all.map { (.siCommand(LauncherSICommand(id: $0.id, title: $0.title)), "\(Brand.intelligence) Command") }
        items += scriptLibrary.all().map { (.script($0, inline: nil), "Skillie") }
        items += quicklinkStore.links.map { (.quicklink($0, query: ""), "Quicklink") }
        items += arranger.layouts().map { (.layout($0), "Window Layout") }
        items += snippetLibrary.all.map { (.snippet($0), "Snippet") }
        items += (launcher.systemCommands?() ?? []).map { (.system($0.0, title: $0.1), "Mac Command") }
        return items.map { SettingTools.AliasTarget(id: $0.item.learningID, title: $0.item.title, kind: $0.kind) }
    }

    /// What Settings → Keys → Add Shortcut offers, as its menu names it.
    private func shortcutActions() -> [(action: SkilliAction, title: String)] {
        let actions = ActionCatalog.general + ActionCatalog.ai + ActionCatalog.windows + ActionCatalog.mac + ActionCatalog.sound()
            + ActionCatalog.settingsPanes() + ActionCatalog.appLinks() + ActionCatalog.appleShortcuts()
            + editorProjects.all().prefix(12).map { SkilliAction.mac(.project($0)) }
            + scriptLibrary.all().filter { $0.arguments.allSatisfy(\.optional) }.map { SkilliAction.mac(.script($0)) }
            + ActionCatalog.launcherCommands.flatMap(\.actions)
            + snippetLibrary.all.map { SkilliAction.snippet($0.id) } + quicklinkStore.links.map { SkilliAction.quicklink($0.id) }
        // Clipboard History is in skil.li's own list and the launcher's.
        var seen = Set<String>()
        return actions.filter { seen.insert($0.id).inserted }.map { ($0, $0.title) }
            + arranger.layouts().map { (.windowLayout($0.id), "Window Layout · \($0.name)") }
    }

    /// A Mac command or a window place from the launcher or a shortcut: a
    /// card only for what is worth saying (Keep Awake, hidden files) and for
    /// what went wrong.
    private func runMac(_ action: MacAction) {
        aiActions.runMac(action)
    }

    /// Wi-Fi's state, the Bluetooth devices and the linked apps installed,
    /// read again off the main thread at launch and each time the launcher
    /// opens: its rows use what was read last, and are redrawn when it
    /// changed.
    private func refreshRadios() {
        let before = (wifi: WiFi.cachedIsOn, devices: BluetoothDevices.cached, apps: LinkedApps.summary, shortcuts: AppleShortcuts.summary)
        Task { [weak self] in
            await Task.detached(priority: .utility) {
                _ = WiFi.isOn()
                _ = BluetoothDevices.paired()
                // CleanShot X installed, updated or gone: its rows follow.
                LinkedApps.read()
                // A shortcut made, renamed or deleted in Shortcuts: its row too.
                AppleShortcuts.read()
            }.value
            guard WiFi.cachedIsOn != before.wifi || BluetoothDevices.cached != before.devices || LinkedApps.summary != before.apps
                    || AppleShortcuts.summary != before.shortcuts else { return }
            self?.launcher.reloadSources()
        }
    }

    /// One of the user's shortcuts (Apple's Shortcuts app), as a skillie
    /// runs: asked first when Ask was unsure; what it gave back in the card,
    /// one line for a moment, more for longer (scrolls); nothing given back,
    /// nothing said (the card goes). `input`: the selection read now, or
    /// text read already.
    private func runShortcut(_ shortcut: AppleShortcut, input: ShortcutInput, askFirst: Bool = false) {
        let name = AppleShortcuts.name(of: shortcut)
        Task {
            if askFirst {
                guard await systemCommands.confirm?("Run “\(name)”?", "One of your shortcuts, run by Apple's Shortcuts.", "Run") == true else { return }
            }
            var text: String?
            switch input {
            case .none: text = nil
            case .text(let given): text = given
            case .selection:
                guard let read = await selection.read()?.text else {
                    aiActions.notify("Nothing is selected: select the text “\(name)” works on, then run it again.", caller: name, run: nil)
                    return
                }
                text = read
            }
            aiActions.notify(caller: name, working: "Running “\(name)”…", seconds: 4, perLine: 16) {
                try await AppleShortcuts.run(shortcut, input: text) ?? ""
            }
        }
    }

    /// ⌘K → Edit in Shortcuts: its editor, through Shortcuts' own link.
    private func editShortcut(_ shortcut: AppleShortcut) {
        guard let url = AppleShortcuts.current(shortcut).editURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// A skillie, as Raycast runs a Script Command: asked first when it says so;
    /// silent leaves its last line a moment, compact its last line, full
    /// output all of it, in the card.
    private func runScript(_ command: ScriptCommand, arguments: [String], askFirst: Bool = false) {
        Task {
            if command.needsConfirmation || askFirst {
                let detail = command.needsConfirmation ? "It asks before it runs." : command.description.isEmpty ? "One of your skillies." : command.description
                guard await systemCommands.confirm?("Run “\(command.title)”?", detail, "Run") == true else { return }
            }
            let seconds: Double = command.mode == .fullOutput ? 20 : command.mode == .silent ? 2 : 4
            // Its own tool calls (`"$SKILLI_CLI" call do_in_app …`) borrow its card.
            let id = UUID().uuidString
            aiActions.notify(caller: command.title, working: "Running “\(command.title)”…", seconds: seconds, skillie: id) { [scriptLibrary] in
                let run = try await scriptLibrary.run(command, arguments: arguments, id: id)
                let text = command.mode == .fullOutput ? run.output.trimmingCharacters(in: .whitespacesAndNewlines) : ScriptCommand.lastLine(run.output)
                guard run.succeeded else {
                    throw ScriptLibrary.Failure(message: text.isEmpty ? "“\(command.title)” failed (exit \(run.status))." : text)
                }
                // Nothing printed: done is said by nothing (the card goes).
                return text
            }
        }
    }

    /// Homebrew; the card says it is working (it can take minutes), then
    /// what brew printed last. A formula installs at once (a command-line
    /// tool, removed as easily); an app (a cask), an upgrade or an
    /// uninstall asks first.
    private func runBrew(_ action: Homebrew.Action, _ package: BrewPackage?) {
        Task {
            let what = package.map { "“\($0.name)”" } ?? "every outdated package"
            let detail = package?.description ?? (action == .uninstall ? "Homebrew removes it." : "Homebrew downloads and installs it.")
            let asks = !(action == .install && package?.isCask == false)
            if asks {
                let verb = action.rawValue.capitalized
                guard await systemCommands.confirm?("\(verb) \(what) with Homebrew?", detail, verb) == true else { return }
            }
            aiActions.notify(caller: "Homebrew", working: "\(action.working) \(package?.name ?? "everything")… it can take a few minutes.", seconds: 8) { [homebrew] in
                try await homebrew.run(action, package)
            }
        }
    }

    /// Starts a timer: the menu bar counting down is the answer.
    @discardableResult
    private func startTimer(_ request: TimerRequest) -> UUID {
        let timer = timers.start(request)
        Log.trace("Timer started: \(timer.title)")
        return timer.id
    }

    /// Displays just plugged in: the layouts saved on them asked in the
    /// middle of the biggest (one already asked takes a dock's second
    /// display in); the one set to always, on a display surely the one
    /// saved, put back at once; a display no layout knows, nothing.
    private func displaysPlugged(_ plugged: [DisplayFingerprint]) {
        var all = madeDisplayPrompt.map { $0.isVisible ? $0.plugged : [] } ?? []
        for display in plugged where !all.contains(where: { $0.isSameDisplay(as: display) }) { all.append(display) }
        let layouts = arranger.layouts()
        let connected = Displays.current()
        let candidates = LayoutTrigger.candidates(for: all, connected: connected.map(\.fingerprint), layouts: layouts,
                                                  ignoredMonitors: preferences.ignoredMonitors)
        if let id = LayoutTrigger.automatic(candidates, layouts: layouts), let layout = layouts.first(where: { $0.id == id }) {
            madeDisplayPrompt?.hide()
            Log.trace("Displays: “\(layout.name)” put back without asking")
            applyLayout(layout)
            return
        }
        let offers = candidates.compactMap { candidate in
            layouts.first { $0.id == candidate.layoutID }.map { DisplayPrompt.Offer(layout: $0, certainty: candidate.certainty, exact: candidate.exact) }
        }
        let target = connected.filter { display in all.contains { $0.isSameDisplay(as: display.fingerprint) } }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard !offers.isEmpty, let target else { return }
        displayPrompt.show(offers, plugged: all, centeredIn: WindowManager.bottomLeft(target.visible))
    }

    /// A display asked about went away: asked again about those left, or
    /// not at all.
    private func displaysUnplugged(_ gone: [DisplayFingerprint]) {
        guard let prompt = madeDisplayPrompt, prompt.isVisible else { return }
        let left = prompt.plugged.filter { asked in !gone.contains { $0.isSameDisplay(as: asked) } }
        guard left.count != prompt.plugged.count else { return }
        prompt.hide()
        if !left.isEmpty { displaysPlugged(left) }
    }

    /// Always Apply Without Asking (put back now too) or Never Apply
    /// Automatically, from the question.
    private func setAutomatic(_ layout: SavedWindowLayout, _ automatic: SavedWindowLayout.Automatic) {
        guard var changed = arranger.layouts().first(where: { $0.id == layout.id }) else { return }
        changed.automatic = automatic
        do {
            try arranger.store(changed)
        } catch {
            aiActions.notify(error.localizedDescription, caller: "Window Layout", run: nil)
            return
        }
        Log.trace("Window layout “\(changed.name)”: \(automatic.rawValue) when its displays are plugged in")
        if automatic == .always {
            applyLayout(changed)
        } else {
            aiActions.notify("“\(changed.name)” is not offered any more when its displays are plugged in. Settings → Windows to change it.",
                             caller: "Window Layout", run: nil, seconds: 5)
        }
    }

    /// Ignore This Monitor: nothing offered when it is plugged in again.
    private func ignoreMonitors(_ monitors: [DisplayFingerprint]) {
        for monitor in monitors where !preferences.ignoredMonitors.contains(where: { $0.isSameDisplay(as: monitor) }) {
            preferences.ignoredMonitors.append(monitor)
        }
        aiActions.notify("\(monitors.map(\.name).joined(separator: " and ")) ignored: no layout offered when plugged in. Settings → Windows to change it.",
                         caller: "Window Layout", run: nil, seconds: 5)
    }

    /// ⌘K → Set Shortcut… on an app or a "?" entry: the card asks for the
    /// keys and the next ones pressed are its shortcut (the same recorder
    /// as Settings → Keys: conflicts refused, esc cancels); then it says
    /// them. A shortcut added for it and left without keys goes again.
    func recordShortcut(for action: SkilliAction, named name: String) {
        let existing = shortcuts.entryID(for: action)
        let id = existing ?? shortcuts.add(action)
        shortcuts.beginRecording(id)
        aiActions.notify(caller: "Shortcut", working: "Press the keys for \(name): ✦ (Caps Lock) and a key, or ⌘, ⌥ or ⌃ with one. esc cancels.",
                         seconds: 3) { [weak self] in
            guard let self else { return "" }
            // Until the keys are in, refused or cancelled; the card closed
            // or a minute gone: nothing goes on recording out of sight.
            let deadline = ContinuousClock.now + .seconds(60)
            while self.shortcuts.recordingID == id, self.aiActions.popover.isVisible, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if self.shortcuts.recordingID == id { self.shortcuts.cancelRecording() }
            let chords = self.shortcuts.config.shortcuts.first { $0.id == id }?.chords
            if existing == nil, chords == nil { self.shortcuts.remove(id) }
            if let error = self.shortcuts.lastError, error.id == id { return error.message }
            guard let chords else { return "" }
            let does = if case .openApp = action { "opens" } else { "runs" }
            return "\(chords.map { $0.keycaps.joined() }.joined(separator: " ")) \(does) \(name)."
        }
    }

    /// ⌘K → Delete Layout and Settings → Windows: deleted at once, its
    /// shortcuts with it; ⌘Z in the card for 10 s puts both back (the
    /// user's own data: no question first, an undo instead).
    private func deleteLayout(_ layout: SavedWindowLayout) {
        deletes.layout(layout, in: arranger, shortcuts: shortcuts)
    }

    /// Paste in Sequence (✦K V, again and again): the next older copy in
    /// the app in front, the newest first. Seen pasted: nothing said; why
    /// nothing was, in one line.
    private func pasteInSequence() {
        if let problem = clipboard.putNextInSequence() {
            aiActions.notify(problem, caller: "Paste in Sequence", run: nil, seconds: 2.5)
            return
        }
        // From the launcher, the app that was in front gets its focus back first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [selection] in
            selection.press("v", flags: .maskCommand)
        }
    }

    /// Search GIFs: ↩ pastes it animated (Markdown in a terminal or an
    /// editor), ⌘↩ and ⌘K copy it. Seen pasted: nothing said; what failed,
    /// in one line.
    private func useGIF(_ gif: GIF, _ use: GIFUse, query: String) {
        let klipy: KlipyGIF? = if case .klipy(let found) = gif { found } else { nil }
        func counted() {
            gifLibrary.used(gif)
            if let klipy { gifLibrary.shared(klipy, query: query) }
        }
        switch use {
        case .open:
            switch gif {
            case .klipy(let found): NSWorkspace.shared.open(found.full)
            case .file(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .copyLink, .copyMarkdown:
            guard let klipy else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(use == .copyLink ? klipy.full.absoluteString : klipy.markdown, forType: .string)
            counted()
        case .paste where GIFPaste.style(for: gif, frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                         editors: launcher.gifEditors) == .markdown:
            guard let klipy else { return }
            counted()
            // Let the app that was in front get its focus back first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Task { await self.selection.replace(with: klipy.markdown) }
            }
        case .paste, .copy:
            // The app ↩ was pressed for: ⌘V goes there only if it still is in front.
            let target = NSWorkspace.shared.frontmostApplication?.processIdentifier
            Task {
                let start = ContinuousClock.now
                do {
                    try await gifLibrary.putOnClipboard(gif)
                } catch {
                    let line = switch (gif, error as? GIFLibrary.Failure) {
                    case (.file(let url), _): "“\(url.lastPathComponent)” could not be read: it may have moved."
                    case (_, .tooLarge?): "This GIF is over 15 MB: pick another one, or use Copy Link in ⌘K."
                    default: "Klipy did not send the GIF: try again, or use Copy Link in ⌘K."
                    }
                    aiActions.notify(line, caller: "Search GIFs", run: nil)
                    return
                }
                Log.trace("GIFs: \(use == .paste ? "pasted" : "copied") in \((ContinuousClock.now - start).compact)")
                counted()
                guard use == .paste else { return }
                // From the launcher, the app that was in front gets its focus back first.
                if ContinuousClock.now - start < .milliseconds(50) { try? await Task.sleep(for: .milliseconds(50)) }
                // A slow GIF, and the launcher open again or another app in
                // front meanwhile: ⌘V would land there. Left on the clipboard.
                guard !launcher.isVisible, NSWorkspace.shared.frontmostApplication?.processIdentifier == target else {
                    aiActions.notify("The GIF is on the clipboard: ⌘V pastes it.", caller: "Search GIFs", run: nil, seconds: 3)
                    return
                }
                selection.press("v", flags: .maskCommand)
            }
        }
    }

    /// The folder Settings → Clipboard names (screenshots by default), its
    /// 20 newest images taken the first time it is watched.
    private func watchImageFolder() {
        let folder = preferences.clipboardScreenshots && preferences.clipboardHistory ? preferences.imageFolder : nil
        let done = UserDefaults.standard.stringArray(forKey: "ImageFolder.backfilled") ?? []
        let first = folder.map { !done.contains($0.path) } ?? false
        if imageFolder.watch(folder, backfill: first ? 20 : 0), first, let folder {
            UserDefaults.standard.set(done + [folder.path], forKey: "ImageFolder.backfilled")
        }
    }

    /// Every window of `layout` back in place: the windows moving are the
    /// answer. A card only when one could not be put back (with what was
    /// adapted), left longer to read the list.
    private func applyLayout(_ layout: SavedWindowLayout) {
        Task { [arranger, aiActions] in
            let report = await arranger.apply(layout)
            guard report.hasFailures else { return }
            aiActions.notify(report.message, caller: "Window Layout", run: nil, seconds: 3 + 2.5 * Double(report.changes.count))
        }
    }

    /// Why the clipboard history shows nothing, when it is not just empty.
    private var clipboardStatus: String? {
        if clipboard.store == nil { return "The clipboard history could not open its file" }
        if !preferences.clipboardHistory { return "Clipboard history is off: skil.li Settings → Clipboard" }
        if !clipboard.mayRead { return "Allow skil.li to keep what you copy: Settings → Clipboard" }
        return nil
    }

    /// Opening skil.li again (Finder, Spotlight, `open -a`) while it runs
    /// shows Settings: the only window it has, and the way back when the
    /// menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    /// `skilli://commands/import?…` from a web page or a shared link:
    /// Settings → Commands shows what it would add, and nothing is added
    /// until the user says so; `skilli://apps/import?…` the same in
    /// Settings → Apps. Every other `skilli://` link runs what it
    /// names (`LinkRunner`: asked first when it must; one skil.li does not
    /// know says so). The self-test and benchmark ignore links.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard case .normal = mode else {
            // The self-test's skillie opens its `do` links through macOS.
            if case .selftest = mode, links.opensFromMacOS { urls.forEach(links.open) }
            return
        }
        for url in urls {
            // An app's links (`skilli://apps/import`): Settings → Apps shows it whole first.
            if let request = AppFileLink.parse(url) {
                settings.apps.page = nil
                settings.show(pane: .apps)
                Task { await settings.apps.receive(request) }
                continue
            }
            guard let request = CommandLink.parse(url) else {
                Log.actions.notice("Link \(url.host() ?? "", privacy: .public)")
                links.open(url)
                continue
            }
            settings.show(pane: .commands)
            Task { await aiCommands.receive(request) }
        }
    }

    /// A quicklink's address: in a tab the browser has on that site when
    /// Settings → Catalog → Quicklinks → Reuse an open tab is on and it
    /// can (`BrowserTabReuse`), else as any link. The self-test records it.
    private func openQuicklinkAddress(_ url: URL) {
        guard preferences.quicklinkReuseTab, !actions.dryRunURLs else {
            actions.perform(.openURL(url.absoluteString), triggeredAt: .now)
            return
        }
        Task {
            if await BrowserTabReuse.open(url) { return }
            actions.perform(.openURL(url.absoluteString), triggeredAt: .now)
        }
    }

    // MARK: - Event tap

    private func startEventTap() {
        guard let router else { return }
        if router.start() {
            tapRetryTimer?.invalidate()
            tapRetryTimer = nil
            Log.input.notice("Event tap running")
            rebuildStatusMenu()
            if case .selftest(let outputPath, let scope) = mode {
                runSelfTest(outputPath: outputPath, scope: scope)
            }
            return
        }

        if !didPromptForAccessibility {
            didPromptForAccessibility = true
            if Permissions.isAccessibilityTrusted {
                // Trusted but the tap still failed: Input Monitoring is the
                // remaining gate on some setups.
                Permissions.requestInputMonitoring()
            } else if case .normal = mode {
                // The setup window explains, then asks (its Allow button):
                // only before it was ever closed (D7: closed means later).
                if SetupWindowController.showsByItself(closedOnce: preferences.didCompleteSetup), !setup.isVisible { showWelcome() }
            } else {
                Permissions.requestAccessibility()
            }
        }

        guard tapRetryTimer == nil else { return }
        Log.input.notice("Event tap unavailable; waiting for permission")
        tapRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startEventTap()
            }
        }
        rebuildStatusMenu()
    }

    // MARK: - Settings

    /// Responder-chain target for the Settings… menu items (⌘,).
    @objc private func checkForUpdates() {
        updates?.checkForUpdates()
    }

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    private func run(_ command: LauncherCommand.ID) {
        switch command {
        case .openSettings:
            settings.show()
        case .quit:
            NSApp.terminate(nil)
        case .resetLauncherPosition:
            preferences.launcherPlace = nil
        case .backUpNow:
            // Out of sight: one line says where it went.
            guard backup.folder != nil else {
                settings.show(pane: .backup)
                return
            }
            aiActions.notify(caller: "Backup", working: "Backing up skil.li…", seconds: 3) { [backup] in
                let url = try await backup.backUpNow()
                return "Backed up to \(BackupPane.shown(url.deletingLastPathComponent()))."
            }
        case .newWindowLayout:
            layoutEditor.capture(name: "")
        case .newEmptyWindowLayout:
            layoutEditor.startEmpty()
        case .newSnippet:
            settings.showNew(.snippet)
        case .newQuicklink:
            settings.showNew(.quicklink)
        case .newCommand:
            settings.showNew(.command)
        case .pasteInSequence:
            pasteInSequence()
        case .copyAvailability:
            // From a shortcut: the launcher's row shows it itself.
            aiActions.showAgenda(.availability)
        case .killProcess, .clipboardHistory, .searchSnippets, .emoji, .searchGIFs, .switchWindow, .searchMenus, .searchTabs, .searchFiles, .searchProjects, .searchHistory,
             .homebrew, .searchContacts, .agenda, .reminders, .github, .catalog:
            // Handled in the launcher: it turns into that mode.
            break
        case .welcome:
            showWelcome()
        }
    }

    private func apply(_ preferences: Preferences) {
        statusItem?.isVisible = preferences.showMenuBarIcon
        // Hidden calendars were saved by name before: by identifier now (two
        // accounts may each have a "Calendar"), turned once they can be read.
        let hidden = calendarBook.calendarIdentifiers(for: preferences.agendaHiddenCalendars)
        if hidden != Set(preferences.agendaHiddenCalendars) { preferences.agendaHiddenCalendars = hidden.sorted() }
        calendarBook.hiddenCalendars = hidden
        calendarBook.launcherMinutes = preferences.agendaLauncherMinutes
        calendarBook.calendarApp = preferences.agendaApp
        calendarBook.meetBrowser = preferences.agendaMeetBrowser
        meetingWatch.refresh()
        reminderBook.defaultList = preferences.remindersDefaultList
        reminderBook.places = preferences.reminderPlaces
        // "en arrivant à la maison" with no place saved under that name:
        // the Home or Work address on the user's card, found once on Apple
        // Maps, as Apple's Reminders does.
        reminderBook.cardPlace = { [weak self] said in
            guard let self, let kind = SavedPlace.cardAddress(for: said), let address = await self.contactBook.myAddress(kind) else { return nil }
            if let known = self.cardPlaces[address] { return known }
            guard let point = await self.settingTools.geocode(address) else { return nil }
            let place = SavedPlace(name: kind == .home ? "Home" : "Work", address: address, latitude: point.latitude, longitude: point.longitude)
            self.cardPlaces[address] = place
            return place
        }
        reminderWatch.refresh()
        githubBook.relayPublicURL = preferences.relayPublicURL
        githubBook.keepsFresh = preferences.githubUnderSearch
        menuBarSkillies.apply()
        launcher.applyGlassStyle(preferences.glassStyle.effectStyle)
        overlay.applyGlassStyle(preferences.glassStyle.effectStyle)
        aiActions.popover.applyGlassStyle(preferences.glassStyle.effectStyle)
        router?.tapSendsEscape = preferences.hyperTapSendsEscape
        ai.apply()
        if case .normal = mode {
            backup.refresh()
            // Once the history runs (it takes what the folder hands over).
            if imageFolder.onImage != nil { watchImageFolder() }
            autoQuitter.schedule()
        }
    }

    /// What the user made, for the Catalog: the launcher's "?" and
    /// Settings → Catalog read the same.
    private func catalogInput() -> FeatureCatalog.Input {
        FeatureCatalog.Input(
            commands: PromptLibrary.shared.all.filter { $0.id != PromptLibrary.askID }.map {
                FeatureCatalog.Command(id: $0.id, title: $0.title, oneLine: PromptLibrary.catalogLine(for: $0))
            },
            snippets: snippetLibrary.all, skillies: scriptLibrary.all(), quicklinks: quicklinkStore.links, layouts: arranger.layouts(),
            appLinks: MacAction.appLinks().compactMap { if case .appLink(let command, _) = $0 { command } else { nil } },
            shortcuts: AppleShortcuts.all(),
            intelligence: Brand.intelligence
        )
    }

    private func makeSettingsContext() -> SettingsContext {
        var context = makeBaseSettingsContext()
        context.catalogInput = { [weak self] in self?.catalogInput() ?? FeatureCatalog.Input() }
        context.showSetup = { [weak self] in self?.showWelcome(at: .accessibility) }
        context.recentProjects = { [editorProjects] in editorProjects.all() }
        context.skillies = { [scriptLibrary] in scriptLibrary.all() }
        context.calendarAccounts = { [calendarBook] in calendarBook.calendarAccounts() }
        context.reminderLists = { [reminderBook] in reminderBook.listNames() }
        context.myCard = { [contactBook] in await contactBook.me() }
        context.contactNamed = { [contactBook] words in await contactBook.person(named: words) }
        context.github = githubBook
        context.canCheckRules = { [weak self] in self?.toolServer.judge?.canJudge ?? false }
        context.scheduler = scheduler
        context.agentSkills = { [weak self] in self?.agentSkills() ?? [] }
        context.showScheduledAnswer = { [weak self] ask in
            guard let self, let answer = ask.lastAnswer else { return }
            let ran = ask.lastRun.map { " · " + ScheduledAsks.moment($0) } ?? ""
            Task { await self.aiActions.presentScheduled(ask, answer: answer, failed: ask.lastFailed, status: ask.schedule.spoken + ran, by: nil) }
        }
        context.scriptCommands = { [scriptLibrary] in scriptLibrary.all().filter { $0.arguments.allSatisfy(\.optional) } }
        context.arranger = arranger
        context.tryMeetingAlert = { [weak self] alert in
            self?.meetingCard.show(MeetingCardView.sample(startingIn: TimeInterval(alert.minutes * 60)), dark: alert.style == .dark)
        }
        context.backup = backup
        context.emoji = emojiLibrary
        context.gifs = gifLibrary
        context.hasImageKey = { [ai] in ai.decisionKey(for: .typeSafe) != nil }
        context.reopen = { [weak self] in
            guard case .normal = self?.mode else { return }
            Relaunch.afterExit()
            NSApp.terminate(nil)
        }
        context.editLayout = { [layoutEditor] layout in
            if let layout { layoutEditor.edit(layout) } else { layoutEditor.capture(name: "") }
        }
        context.updateLayout = { [layoutEditor] layout in layoutEditor.update(layout) }
        context.newEmptyLayout = { [layoutEditor] in layoutEditor.startEmpty() }
        context.setLayoutAutomatic = { [arranger] layout, automatic in
            guard var changed = arranger.layouts().first(where: { $0.id == layout.id }) else { return }
            changed.automatic = automatic
            try? arranger.store(changed)
        }
        context.applyLayout = { [weak self] layout in self?.applyLayout(layout) }
        context.deleteLayout = { [weak self] layout in self?.deleteLayout(layout) }
        context.deletes = deletes
        context.rightsHelpers = { [handoff] in handoff.targets }
        context.openRightsHelper = { [handoff, preferences] server in
            guard let target = handoff.preferred(preferences.handoffTarget) else {
                throw HandoffLauncher.Failure(message: "Install Claude Code or Codex first.")
            }
            try handoff.launchRights(target, in: preferences.handoffTerminal, server: server)
        }
        return context
    }

    private func makeBaseSettingsContext() -> SettingsContext {
        let trigger = remapper.triggerKeyCodes.first
        return SettingsContext(
            hyperStatus: { [remapper] in remapper.settingsSummary },
            hyperIsActive: { [remapper] in !remapper.triggerKeyCodes.isEmpty },
            receivesTrigger: { [weak self] in
                guard let trigger, let router = self?.router else { return false }
                return router.receivesTrigger(trigger)
            },
            accessibilityGranted: { Permissions.isAccessibilityTrusted },
            shortcutsActive: { [weak self] in self?.router?.isRunning ?? false },
            openAccessibilitySettings: { Permissions.openAccessibilitySettings() },
            shortcuts: shortcuts,
            chooseApp: { [weak self] in self?.chooseApp() },
            ai: ai,
            aiCommands: aiCommands,
            toolSettings: toolSettings,
            clipboard: clipboard,
            permissions: permissions,
            snippets: snippetLibrary,
            windowLayouts: { [arranger] in arranger.layouts() },
            quicklinks: quicklinkStore
        )
    }

    /// Native picker for "Add Shortcut → Open App…".
    private func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Self-test

    private func runSelfTest(outputPath: String?, scope: String) {
        guard !selfTestStarted else { return }
        selfTestStarted = true
        #if SKILLI_SELFTEST
        let scope = SelfTest.Scope(rawValue: scope) ?? .all
        Task {
            await appIndex.reload(usage: usage)
            guard let trigger = remapper.triggerKeyCodes.first, let router else {
                SelfTest.emit(.init(passed: 0, failed: 1, checks: [
                    .init(name: "Hyper trigger", passed: false, detail: "no trigger key (Caps Lock left alone)", latencyMs: nil)
                ]), to: outputPath)
                NSApp.terminate(nil)
                return
            }
            let test = SelfTest(context: .init(
                launcher: launcher,
                actions: actions,
                selection: selection,
                layout: layout,
                overlay: overlay,
                triggerKeyCode: trigger,
                receivesTrigger: { router.receivesTrigger(trigger) },
                settings: settings,
                preferences: preferences,
                shortcuts: shortcuts,
                router: router,
                performStatusMenuSettings: { self.performStatusMenuSettings() },
                ai: ai,
                aiActions: aiActions,
                aiCommands: aiCommands,
                tools: toolServer,
                clipboard: clipboard,
                snippets: snippetLibrary,
                snippetExpander: snippetExpander,
                arranger: arranger,
                layoutEditor: layoutEditor,
                displayPrompt: displayPrompt,
                offerDisplays: { [weak self] displays in self?.displaysPlugged(displays) },
                timers: timers,
                meetingWatch: meetingWatch,
                reminderWatch: reminderWatch,
                meetingCard: meetingCard,
                autoQuitter: autoQuitter,
                backup: backup,
                menuBarSkillies: menuBarSkillies,
                awakeIndicator: awakeIndicator,
                scheduler: scheduler,
                snapshotDirectory: outputPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() },
                links: links,
                englishTyping: englishTyping,
                deletes: deletes,
                statusMenu: { [weak self] in self?.statusItem?.menu },
                statusItemFrame: { [weak self] in
                    guard let item = self?.statusItem, item.isVisible else { return nil }
                    return item.button?.window?.frame
                },
                welcome: { [weak self] step in
                    self?.showWelcome(at: step)
                    return self?.setup
                }
            ))
            SelfTest.emit(await test.run(scope: scope), to: outputPath)
            NSApp.terminate(nil)
        }
        #else
        FileHandle.standardError.write(Data("This build has no self-tests (a release build: they are compiled only for development).\n".utf8))
        NSApp.terminate(nil)
        #endif
    }

    /// `pkill` sends SIGTERM, which bypasses `applicationWillTerminate`.
    /// Route it through NSApp so a Caps Lock mapping we installed is removed.
    private func routeTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        signalSource = source
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Brand kit: monochrome S, template so macOS tints it for the menu bar.
        item.button?.image = Theme.brandTemplate(size: 18)
            ?? NSImage(systemSymbolName: "command", accessibilityDescription: "skil.li")
        statusItem = item
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        // Its keys are the launcher's own, on the right (`showStatusMenuKeys`).
        let open = NSMenuItem(title: Self.openItemTitle, action: #selector(openLauncher), keyEquivalent: "")
        open.target = self
        open.identifier = StatusMenuKeys.open
        menu.addItem(open)
        menu.addItem(.separator())

        let tapRunning = router?.isRunning ?? false
        menu.addItem(Self.infoItem(tapRunning ? "Shortcuts active" : "Shortcuts inactive — needs Accessibility"))
        // Filled when the menu opens (`menuNeedsUpdate`).
        let secure = Self.infoItem("")
        secure.isHidden = true
        secureInputItem = secure
        menu.addItem(secure)
        permissions.refreshAttention()
        // Until Accessibility is on: every other permission is asked where
        // its feature needs it, not here (D7).
        if SetupWindowController.isOffered(tapRunning: tapRunning, ready: permissions.isReady) {
            let grant = NSMenuItem(title: "Set Up skil.li…", action: #selector(showSetup), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }
        menu.addItem(Self.infoItem(remapper.statusDescription))
        if systemCommands.isKeepingAwake {
            let until = systemCommands.awakeUntilText.map { " \($0)" } ?? ""
            let awake = NSMenuItem(title: "Keeping the Mac Awake\(until) — Allow Sleep", action: #selector(allowSleep), keyEquivalent: "")
            awake.target = self
            menu.addItem(awake)
        }
        menu.addItem(.separator())

        // Always there: what skil.li may use, and where to turn it on.
        let permissionsItem = NSMenuItem(title: "Privacy…", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.identifier = StatusMenuKeys.settings
        menu.addItem(settingsItem)
        menu.addItem(Self.hiddenKey(",", for: settingsItem))
        // The Developer ID build only: development builds have no feed.
        if updates != nil {
            let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            check.target = self
            menu.addItem(check)
        }
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit skil.li", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        quit.identifier = StatusMenuKeys.quit
        menu.addItem(quit)
        menu.addItem(Self.hiddenKey("q", for: quit))

        menu.delegate = self
        statusItem.menu = menu
        showStatusMenuKeys(menu)
    }

    static let openItemTitle = ShortcutStore.launcherTitle

    /// ⌘`key` for `item` while the menu is open, drawn by `item` itself
    /// (`showStatusMenuKeys`): a hidden twin holds the key equivalent.
    private static func hiddenKey(_ key: String, for item: NSMenuItem) -> NSMenuItem {
        let twin = NSMenuItem(title: item.title, action: item.action, keyEquivalent: key)
        twin.target = item.target
        twin.isHidden = true
        twin.allowsKeyEquivalentWhenHidden = true
        return twin
    }

    /// The keys on the right of Open skil.li, Settings… and Quit, lined up
    /// as macOS lines up key equivalents, in skil.li's words: ✦ for Hyper,
    /// a chain as its keys one after the other (macOS's own key equivalents
    /// can say neither). Open skil.li says the launcher's real keys, read
    /// again each time the menu opens; without keys, nothing.
    private func showStatusMenuKeys(_ menu: NSMenu) {
        let launcher = shortcuts.launcherEntry?.chords
        let keyed: [(id: NSUserInterfaceItemIdentifier, title: String, keys: String?)] = [
            (StatusMenuKeys.open, Self.openItemTitle, launcher.flatMap { $0.isEmpty ? nil : StatusMenuKeys.text($0) }),
            (StatusMenuKeys.settings, "Settings…", StatusMenuKeys.text([Chord(.character(","), .command)])),
            (StatusMenuKeys.quit, "Quit skil.li", StatusMenuKeys.text([Chord(.character("q"), .command)]))
        ]
        let ids = Set(keyed.map(\.id))
        let others = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem && !ids.contains($0.identifier ?? .init("")) }.map(\.title)
        let titles = StatusMenuKeys.titles(keyed.map { ($0.title, $0.keys) }, besides: others, font: menu.font ?? .menuFont(ofSize: 0))
        for (row, title) in zip(keyed, titles) {
            menu.items.first { $0.identifier == row.id }?.attributedTitle = title
        }
    }

    /// While Secure Input is on, no app's shortcuts work (the system keeps
    /// keys from every event tap): say so, and which app turned it on.
    static func secureInputStatus() -> String? {
        secureInputHolder().map { "Shortcuts paused: Secure Input is on" + ($0.isEmpty ? "" : " in \($0)") }
    }

    /// The app holding Secure Input ("" when macOS does not say); nil while
    /// it is off.
    static func secureInputHolder() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
        return pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? ""
    }

    private static func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Self-test hook: triggers the status menu's Settings… item.
    func performStatusMenuSettings() -> Bool {
        guard let menu = statusItem?.menu,
              let index = menu.items.firstIndex(where: { $0.identifier == StatusMenuKeys.settings })
        else { return false }
        menu.performActionForItem(at: index)
        return true
    }

    @objc private func openLauncher() {
        launcher.show(triggeredAt: .now)
    }

    @objc private func allowSleep() {
        Task { try? await systemCommands.run(.keepAwake) }
    }

    @objc private func showPermissions() {
        settings.show(pane: .privacy)
    }

    @objc private func showSetup() {
        showWelcome(at: .accessibility)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu, let item = secureInputItem else { return }
        let status = Self.secureInputStatus()
        item.title = status ?? ""
        item.isHidden = status == nil
        showStatusMenuKeys(menu)
    }
}

/// Keys drawn on the right of a menu item's title: one right tab stop for
/// every keyed item of the menu, past its widest title, so they line up.
@MainActor
enum StatusMenuKeys {
    static let open = NSUserInterfaceItemIdentifier("skilli.status.open")
    static let settings = NSUserInterfaceItemIdentifier("skilli.status.settings")
    static let quit = NSUserInterfaceItemIdentifier("skilli.status.quit")

    /// "✦ Space", "⌘ Space › Space".
    static func text(_ chords: [Chord]) -> String {
        chords.map(\.description).joined(separator: " › ")
    }

    static func titles(_ rows: [(title: String, keys: String?)], besides others: [String], font: NSFont) -> [NSAttributedString] {
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let titles = (rows.map(\.title) + others).map(width).max() ?? 0
        let keys = rows.compactMap(\.keys).map(width).max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: ceil(titles + 28 + keys))]
        return rows.map { row in
            let title = NSMutableAttributedString(string: row.title, attributes: [.font: font, .paragraphStyle: paragraph])
            if let keys = row.keys {
                // A system color: AppKit draws it light on the highlight.
                title.append(NSAttributedString(string: "\t" + keys, attributes: [
                    .font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            return title
        }
    }
}
