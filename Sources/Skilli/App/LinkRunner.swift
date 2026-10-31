import AppKit
import SkilliCore

/// `skilli://` links (`SkilliLink`) opened from another app, Shortcuts, a
/// Stream Deck or a web page: each runs what it names, as its row does in
/// the "?". A link can come from anywhere, so what changes the Mac out of
/// sight, types or runs the user's code asks in the card first
/// (`SkilliLink.asksFirst`, naming the link); opening and reading run at
/// once. Always (⌘↩) in that card trusts the entry: its next link runs at
/// once (`LinkTrust`, D6), never for what asks anyway. A link skil.li does
/// not know, or whose target is gone, says so in the card. Import links
/// stay `CommandLink`'s (Settings → Commands). `skilli://do` runs "do it
/// here" toward its goal, always asked first, one link after another
/// (docs/do-it-here-from-anywhere.md).
@MainActor
final class LinkRunner {
    /// What links can name, read when one is opened.
    var entries: () -> [CatalogEntry] = { [] }
    var quicklinks: () -> [Quicklink] = { [] }
    var skillies: () -> [ScriptCommand] = { [] }
    var skillieFolders: () -> [URL] = { [] }
    /// Asks in the card ("Allow “Lock Screen”?" and why), Always ⌘↩ only
    /// when `offersAlways`: deny keeps things as they are.
    var approve: (_ title: String, _ detail: String, _ offersAlways: Bool) async -> ToolApproval = { _, _, _ in .deny }
    /// The entries links run without asking (Settings → Catalog → Trusted
    /// Links).
    var trust: () -> LinkTrust = { LinkTrust() }
    /// Always was pressed: that entry (a skillie with these arguments)
    /// runs at once from its next link on.
    var onAlways: (_ run: CatalogEntry.Run, _ entry: String, _ title: String, _ arguments: [String]) -> Void = { _, _, _, _ in }
    /// What Return on the entry in the "?" does (`LauncherController.run(fromLink:)`).
    var runEntry: (CatalogEntry) -> Void = { _ in }
    /// Opens a quicklink's address (Reuse an open tab applies).
    var openAddress: (URL) -> Void = { _ in }
    /// The text selected in the app in front: a quicklink's query when the
    /// link gives none.
    var selectedText: () async -> String? = { nil }
    /// A skillie with its arguments (it asks again only when it says so).
    var runSkillie: (ScriptCommand, [String]) -> Void = { _, _ in }
    /// One line in the card.
    var notify: (String) -> Void = { _ in }
    /// The app named by a `do` link, in front (opened if needed).
    var bringForward: (String) async throws -> NSRunningApplication = { name in
        throw ControlTarget.Failure(message: "No app called “\(name)”.")
    }
    /// "Do it here" toward a goal in the app `pid`, in the card; whether it
    /// finished.
    var doItHere: (_ goal: String, _ pid: pid_t) async -> Bool = { _, _ in false }
    /// Always was pressed on a `do` link: that goal in that app runs at once
    /// from its next link on.
    var onAlwaysDo: (_ goal: String, _ app: String?) -> Void = { _, _ in }
    /// The Record card, its name given or not: nothing recorded before ↩
    /// in it, so it opens at once.
    var openRecordCard: (String?) -> Void = { _ in }
    /// Import Recording's panel, on a file when the link names one.
    var openImport: (URL?) -> Void = { _ in }
    /// The recording on now, by its name (nil: none).
    var recordingTitle: () -> String? = { nil }
    var controlRecording: (SkilliLink.RecordingControl) -> Void = { _ in }
    /// What a source link changes: which recording or Record card it is
    /// (the same until it stops or closes), and as the card names it
    /// (“Weekly sync”, the Record card); nil: no recording and no card.
    var recordingSourceTarget: () -> (moment: String, shown: String)? = { nil }
    /// The whole screen a link names: its display, and as the card says it
    /// ("Whole Screen · LG UltraFine"); nil: no such screen.
    var screenNamed: (String) -> (id: UInt32, title: String)? = { _ in nil }
    /// A source turned on or off once allowed (the screen: on that
    /// display, when one was named): what `set_recording_source`
    /// answers, or why not.
    var setRecordingSource: @MainActor (SkilliLink.RecordingSource, Bool, UInt32?) async throws -> String = { _, _, _ in "" }
    /// A recording's window, by its folder's name or its title, from a time
    /// in it; false when there is no such recording.
    var openRecording: (String, Double?) -> Bool = { _, _ in false }
    /// A recording by its folder's name or title (empty: the newest): its
    /// folder's name, the one allowed, and as the card names it ("“Weekly
    /// sync” · Wed 22 Oct"); nil when none is. And what its ⌘K does, once
    /// allowed, on that folder.
    var recordingNamed: (String) -> (id: String, shown: String)? = { _ in nil }
    var followUpRecording: (MeetingFollowUp.Action, String, String?) -> Void = { _, _, _ in }
    /// A GitHub workflow started and followed, once allowed.
    var startWorkflow: (WorkflowDispatch) async throws -> WorkflowProgress = { _ in
        throw GitHubWorkflows.Failure(message: "GitHub workflows are not available.")
    }
    /// A recording renamed, by its folder's name: once allowed.
    var renameRecording: (String, String) -> Void = { _, _ in }
    /// Who the recording's words go to ("Claude").
    var recordingWriter: () -> String = { WritingProvider.claude.title }
    /// macOS may bring skil.li forward to open a link: the app the user was
    /// in comes back first, so a window place or a snippet lands there. The
    /// self-test opens links itself, its own window in front: off.
    var handsFocusBack = true
    /// Self-test hooks: run nothing (what was asked and run is still
    /// logged), and what each link did ("asked system:ejectDisks").
    var dryRun = false
    /// Self-test hook: links macOS hands the self-test (a skillie's `open`
    /// lines) are run, as the normal app runs them.
    var opensFromMacOS = false
    private(set) var log: [String] = []
    private var lastOtherApp: NSRunningApplication?
    private var observer: NSObjectProtocol?
    /// The last `do` link's run, and how many wait or run: one that comes
    /// meanwhile follows it.
    private var lastDo: Task<Bool, Never>?
    private var doWaiting = 0

    init() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { lastOtherApp = front }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                                     queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid() else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = app }
        }
    }

    func open(_ url: URL) {
        Task { await openNow(url) }
    }

    func openNow(_ url: URL) async {
        guard let link = SkilliLink.parse(url) else {
            say("unknown \(url.host() ?? "")", "skil.li does not know this link: \(Self.shown(url)). ⌘K → Copy Link on a row gives one that works.")
            return
        }
        // In line before anything waits: links run in the order they came.
        if case .doHere(let goal, let app) = link {
            await chainDo(goal: goal, app: app)
            return
        }
        await handFocusBack()
        switch link {
        case .run(let id):
            guard let entry = entries().first(where: { $0.id == id }) else {
                say("missing \(id)", "Nothing in skil.li answers to “\(id)” any more: it was renamed or deleted.")
                return
            }
            await run(entry)
        case .quicklink(let name, let query):
            guard let quicklink = SkilliLink.quicklink(named: name, in: quicklinks()) else {
                say("missing quicklink \(name)", "No quicklink “\(name)” in skil.li: Settings → Catalog → Quicklinks lists them.")
                return
            }
            await open(quicklink, query: query)
        case .layout(let id):
            guard let entry = entries().first(where: { $0.id == "layout:\(id)" }) else {
                say("missing layout \(id)", "No window layout “\(id)” in skil.li: Settings → Windows lists them.")
                return
            }
            await run(entry)
        case .skillie(let path, let arguments):
            let all = skillies()
            let folders = skillieFolders().map(\.path)
            guard let found = SkilliLink.skillie(at: path, among: all.map(\.path), folders: folders),
                  let command = all.first(where: { $0.path == found }) else {
                say("missing skillie \(path)", "No skillie at “\(path)” in skil.li's skillies folder.")
                return
            }
            await run(command, arguments: arguments)
        case .doHere:
            break
        case .record(let title):
            log.append("record \(title ?? "")")
            if !dryRun { openRecordCard(title) }
        case .recording(let control):
            await askThenControl(control)
        case .recordingSource(let source, let on, let display):
            await askThenSetSource(source, on: on, display: display)
        case .importRecording(let file):
            // The panel only: the user's ↩ there imports.
            log.append("import \(file ?? "")")
            if !dryRun { openImport(file.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) }
        case .openRecording(let recording, let at):
            // Its window only: nothing leaves the Mac, nothing changes.
            log.append("open recording \(recording)")
            if !dryRun, !openRecording(recording, at) {
                say("missing recording \(recording)", "No recording “\(recording)” in skil.li: it was deleted, or renamed.")
            }
        case .recordingFollowUp(let action, let recording, let question):
            await askThenFollowUp(action, recording: recording, question: question)
        case .renameRecording(let recording, let title):
            await askThenRename(recording, to: title)
        case .workflow(let dispatch):
            await askThenStart(dispatch)
        }
    }

    /// A link starting a GitHub workflow (docs/github-workflow-runs.md):
    /// asked every time, the workflow and its inputs named, never trusted;
    /// the card that started it says why it did not start.
    private func askThenStart(_ dispatch: WorkflowDispatch) async {
        log.append("asked workflow \(dispatch.workflow)")
        guard await approve("Start a GitHub workflow", "\(dispatch.asked) \(Self.fromALink)", false) != .deny else {
            log.append("declined workflow \(dispatch.workflow)")
            return
        }
        log.append("did workflow \(dispatch.workflow)")
        guard !dryRun else { return }
        do {
            _ = try await startWorkflow(dispatch)
        } catch {
            notify(error.localizedDescription)
        }
    }

    /// A link renaming a recording (its folder too): asked every time, the
    /// recording and the name named, never trusted.
    private func askThenRename(_ recording: String, to title: String) async {
        guard let (id, named) = recordingNamed(recording) else {
            say("missing recording \(recording)", "No recording “\(recording)” in skil.li: it was deleted, or renamed.")
            return
        }
        log.append("asked record rename")
        guard await approve("Rename a recording", "\(named) becomes “\(title)”, its folder too. \(Self.fromALink)", false) != .deny else {
            log.append("declined record rename")
            return
        }
        log.append("did record rename")
        if !dryRun { renameRecording(id, title) }
    }

    /// A link pausing, resuming or stopping the recording on now: asked
    /// every time (a page could pause it unseen, or resume what the user
    /// paused), never trusted.
    private func askThenControl(_ control: SkilliLink.RecordingControl) async {
        guard let title = recordingTitle() else {
            say("no recording", "No recording is on: nothing to \(control.rawValue).")
            return
        }
        log.append("asked record \(control.rawValue)")
        guard await approve(control.title, "“\(title)”. \(Self.fromALink)", false) != .deny else {
            log.append("declined record \(control.rawValue)")
            return
        }
        log.append("did record \(control.rawValue)")
        if !dryRun { controlRecording(control) }
    }

    /// A link turning a source of the recording (or of the Record card) on
    /// or off, the whole screen by its name: asked every time, what it
    /// changes named (a page could turn the whole screen on unseen), never
    /// trusted.
    private func askThenSetSource(_ source: SkilliLink.RecordingSource, on: Bool, display: String?) async {
        guard let target = recordingSourceTarget() else {
            say("no recording", "No recording is on, and the Record card is not open: no source to turn \(on ? "on" : "off").")
            return
        }
        let title: String, detail: String
        // The screen named now, the one the card shows: never looked for
        // again once allowed (`meeting` could name another by then).
        var screen: (id: UInt32, title: String)?
        if let display {
            guard let named = screenNamed(display) else {
                say("missing screen \(display)", "No screen “\(display)” on this Mac: main, meeting, or a screen's name as the Record card lists it.")
                return
            }
            screen = named
            title = "Record the whole screen"
            detail = "\(target.shown): \(named.title), from now on. Notifications and other apps on it are recorded too."
        } else {
            title = "Turn \(on ? "on" : "off") \(source.title)"
            detail = "\(target.shown): \(source == .screen && on ? "the meeting's window, " : "")from now on."
        }
        log.append("asked record source \(source.rawValue)")
        guard await approve(title, "\(detail) \(Self.fromALink)", false) != .deny else {
            log.append("declined record source \(source.rawValue)")
            return
        }
        // Allowed for the recording or card the question named, and only it.
        guard recordingSourceTarget()?.moment == target.moment else {
            say("record source changed", "The recording changed while it was asked: nothing turned \(on ? "on" : "off").")
            return
        }
        log.append("did record source \(source.rawValue)\(display.map { " \($0)" } ?? "")")
        guard !dryRun else { return }
        do {
            _ = try await setRecordingSource(source, on, screen?.id)
        } catch {
            say("record source failed", error.localizedDescription)
        }
    }

    /// A link sending a recording's words to the user's writer: asked every
    /// time, the recording and where its words go named, never trusted (a
    /// page could send any meeting).
    private func askThenFollowUp(_ action: MeetingFollowUp.Action, recording: String, question: String?) async {
        guard let (id, named) = recordingNamed(recording) else {
            say("missing recording \(recording)", recording.isEmpty ? "No recordings in skil.li yet." : "No recording “\(recording)” in skil.li: it was deleted, or renamed.")
            return
        }
        log.append("asked record \(action.linkName)")
        let asked = question.map { "\n“\($0.prefix(200))”" } ?? ""
        let detail = "\(named): its transcript goes to \(recordingWriter())." + asked + " \(Self.fromALink)"
        guard await approve("\(action.asked) a recording", detail, false) != .deny else {
            log.append("declined record \(action.linkName)")
            return
        }
        log.append("did record \(action.linkName)")
        // The recording the card named, whatever is newest by now.
        if !dryRun { followUpRecording(action, id, question) }
    }

    /// `do` links run one at a time, in the order they came, so a skillie
    /// chains steps by opening them one after another. One that comes while
    /// another waits or runs follows it, and is dropped when that one did
    /// not finish (denied, stopped, cancelled): the chain's next step makes
    /// no sense then. Dropped, it says nothing more: the card that stopped
    /// says why. One that comes when none waits starts afresh.
    private func chainDo(goal: String, app: String?) async {
        let previous = doWaiting > 0 ? lastDo : nil
        doWaiting += 1
        defer { doWaiting -= 1 }
        let step = Task { () -> Bool in
            if let previous, await !previous.value {
                self.log.append("dropped do \(goal)")
                return false
            }
            return await self.runDo(goal: goal, app: app)
        }
        lastDo = step
        // Opening this link may have brought skil.li forward over the app a
        // step before acts in.
        await handFocusBack()
        _ = await step.value
    }

    /// One `do` link: asked first unless that goal in that app is trusted,
    /// then done in the app it names (brought forward), else the one the
    /// user was in.
    private func runDo(goal: String, app: String?) async -> Bool {
        guard !goal.isEmpty else {
            say("empty do", "This link says nothing to do: skilli://do?goal=… takes what to do, as you would ask it in Ask.")
            return false
        }
        // Shown whole in the card before it runs, or not at all.
        guard goal.count <= SkilliLink.longestGoal else {
            say("long do", "This link's goal is too long to show (\(goal.count) characters, \(SkilliLink.longestGoal) at most): skil.li does not run it.")
            return false
        }
        await handFocusBack()
        if case .asks = trust().askDo(goal: goal, app: app) {
            let place = app ?? NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == getpid() ? nil : $0.localizedName }
            let detail = "skil.li does it in \(place ?? "the app in front"), step by step: it reads the window and clicks for you. "
                + "What sends, deletes or pays still asks. \(Self.fromALink) \(Self.alwaysLine)"
            log.append("asked do \(goal)")
            switch await approve(goal, detail, true) {
            case .deny:
                log.append("declined do \(goal)")
                return false
            case .always:
                log.append("always do \(goal)")
                onAlwaysDo(goal, app)
            case .allow:
                break
            }
            // The card asked: the app the user was in comes back in front.
            await handFocusBack()
        }
        if dryRun {
            log.append("did do \(goal)")
            return true
        }
        let target: NSRunningApplication
        if let app {
            do {
                target = try await bringForward(app)
            } catch {
                say("missing app \(app)", error.localizedDescription)
                return false
            }
        } else {
            guard let front = ControlTarget.front(else: nil) else {
                say("no app for do", "No app in front to do “\(goal)” in.")
                return false
            }
            target = front
        }
        log.append("did do \(goal) in \(target.localizedName ?? "?")")
        return await doItHere(goal, target.processIdentifier)
    }

    /// The entry, asked first when it must and the user did not trust it.
    private func run(_ entry: CatalogEntry) async {
        if case .asks(let offersAlways) = trust().ask(entry.run, entry: entry.id) {
            guard await allowed(entry.run, id: entry.id, title: entry.title, detail: "\(entry.oneLine).", offersAlways: offersAlways) else { return }
        }
        log.append("ran \(entry.id)")
        if !dryRun { runEntry(entry) }
    }

    /// The card's answer: Allow, or Always (the entry trusted from now on);
    /// Deny logged and nothing runs.
    private func allowed(_ run: CatalogEntry.Run, id: String, title: String, detail: String, arguments: [String] = [],
                         offersAlways: Bool) async -> Bool {
        log.append("asked \(id)")
        let always = offersAlways ? " " + Self.alwaysLine : ""
        switch await approve(title, "\(detail) \(Self.fromALink)\(always)", offersAlways) {
        case .deny:
            log.append("declined \(id)")
            return false
        case .always where offersAlways:
            log.append("always \(id)")
            onAlways(run, id, title, arguments)
            return true
        case .allow, .always:
            return true
        }
    }

    /// Its query, else the selected text; with neither, a quicklink that
    /// takes one opens the launcher with its keyword typed.
    private func open(_ quicklink: Quicklink, query: String?) async {
        var text = query
        if text == nil, quicklink.takesQuery { text = Quicklink.query(fromSelection: await selectedText()) }
        if text == nil, quicklink.takesQuery, !quicklink.keyword.isEmpty,
           let entry = entries().first(where: { $0.id == "quicklink:\(quicklink.id.uuidString)" }) {
            await run(entry)
            return
        }
        guard let address = quicklink.address(for: text ?? "") else {
            say("bad quicklink \(quicklink.name)", "The quicklink “\(quicklink.name)” has no web address to open.")
            return
        }
        log.append("opened quicklink \(quicklink.name)")
        if !dryRun { openAddress(address) }
    }

    /// A skillie runs the user's code: asked first (once: one that asks by
    /// itself is not asked twice) unless trusted with these very
    /// arguments, with the arguments the link gives. Missing ones are
    /// asked in the launcher.
    private func run(_ command: ScriptCommand, arguments: [String]) async {
        // Given in order: up to the last one that is not optional.
        let required = (command.arguments.lastIndex { !$0.optional } ?? -1) + 1
        guard arguments.count >= required else {
            if let entry = entries().first(where: { $0.id == "script:\(command.path)" }) {
                log.append("arguments \(entry.id)")
                if !dryRun { runEntry(entry) }
            }
            return
        }
        let given = Array(arguments.prefix(command.arguments.count))
        for (argument, value) in zip(command.arguments, given) where argument.kind == .dropdown && !value.isEmpty {
            guard argument.choices.contains(where: { $0.value == value }) else {
                say("bad argument \(command.title)", "“\(value)” is not one of “\(command.title)”'s choices for \(argument.placeholder).")
                return
            }
        }
        let id = "script:\(command.path)"
        let run = CatalogEntry.Run.skillie(command.path)
        if case .asks(let offersAlways) = trust().ask(run, entry: id, arguments: given, asksItself: command.needsConfirmation) {
            let with = given.isEmpty ? "" : " With " + given.map { "“\($0)”" }.joined(separator: ", ") + "."
            let what = command.description.isEmpty ? "One of your skillies" : command.description
            guard await allowed(run, id: id, title: command.title, detail: "\(what).\(with)", arguments: given, offersAlways: offersAlways) else { return }
        }
        log.append("ran \(id)")
        if !dryRun { runSkillie(command, given) }
    }

    private static let fromALink = "A link asks for it: it came from another app or a web page."
    /// What Always does, said only where the card offers it.
    private static let alwaysLine = "Always: links run it at once from now on (Settings → Catalog lists them)."

    /// The app the user was in, in front again when opening the link
    /// brought skil.li forward; waits until it is (half a second at most).
    private func handFocusBack() async {
        guard handsFocusBack, NSApp.isActive, let app = lastOtherApp, !app.isTerminated else { return }
        app.activate()
        let deadline = ContinuousClock.now + .milliseconds(500)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func say(_ logged: String, _ message: String) {
        log.append(logged)
        Log.actions.notice("Link not run: \(logged, privacy: .public)")
        notify(message)
    }

    /// The link as the card shows it: 80 characters at most.
    private static func shown(_ url: URL) -> String {
        let text = url.absoluteString
        return text.count > 80 ? String(text.prefix(79)) + "…" : text
    }
}
