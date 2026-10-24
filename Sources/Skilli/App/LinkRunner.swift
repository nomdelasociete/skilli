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
    /// The recording on now, by its name (nil: none).
    var recordingTitle: () -> String? = { nil }
    var controlRecording: (SkilliLink.RecordingControl) -> Void = { _ in }
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
        }
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
