import AppKit
import SkilliCore

/// One of the user's commands as the launcher lists it: findable by name
/// when its shortcut is forgotten.
struct LauncherSICommand: Sendable {
    let id: String
    let title: String
    let candidates: [FuzzyCandidate]

    init(id: String, title: String) {
        self.id = id
        self.title = title
        candidates = [title, "\(Brand.intelligence) \(title)"].map(FuzzyCandidate.init)
    }

    /// Its title is its name; "SI …" leads to it (`LauncherRank`).
    func score(_ query: FuzzyMatcher.Query) -> Int? {
        LauncherRank.score(query, names: candidates.prefix(1), keywords: candidates.dropFirst())
    }
}

/// One row in the launcher.
enum LauncherItem {
    case app(AppIndex.Entry)
    case command(LauncherCommand)
    case siCommand(LauncherSICommand)
    /// Last row for any text: Ask skil.li to do it.
    case ask(String)
    /// A permission to switch on, first row while it is missing.
    case setup(Permission)
    /// A Mac command (lock, sleep, dark mode, keep awake…) or a window place.
    case system(MacAction, title: String)
    /// Kill Process: an app with all its processes, or one process (and
    /// the port it listens on).
    case process(ProcessListing.Group, port: Int?)
    /// Clipboard history: something copied.
    case clip(ClipboardStore.Item)
    /// A snippet: Return types it in the app in front.
    case snippet(Snippet)
    /// What the typed calculation, conversion or time comes to.
    case calculation(Calculator.Result)
    case emoji(Emoji)
    /// Search GIFs: one of Klipy's, or a file on this Mac. Return pastes it.
    case gif(GIF)
    /// A saved window layout: Return puts every window back.
    case layout(SavedWindowLayout)
    /// "save layout Coding": Return saves where every window is.
    case saveLayout(String)
    /// A window open now (Switch Window).
    case openWindow(WindowArranger.OpenWindow)
    /// "timer 10 min pâtes": Return starts it.
    case startTimer(TimerRequest)
    /// "awake 1 hour", "turn off awake": Return does it.
    case keepAwake(AwakeRequest)
    /// A timer counting down: Return cancels it.
    case runningTimer(TimerCenter.Running)
    /// The Mac kept awake now, until then (nil: until turned off): Return
    /// turns it off.
    case keptAwake(until: Date?)
    /// "rec Weekly sync": Return opens the Record card with that name.
    case recordNamed(String)
    /// The recording on now: Return stops it, ⌘K pauses or resumes it.
    case recording(LauncherRecording)
    /// "g skilli": Google's results for skilli. No query: the link itself.
    /// A browser tab open now (Search Tabs).
    case browserTab(BrowserTabs.Tab)
    /// A file from Spotlight: Return opens it, ⌘Return shows it in Finder.
    case file(FileSearch.File)
    /// A contact: Return shows it in the card, ⌘Return in Contacts.
    case contact(ContactSearch.Match)
    /// A calendar event: Return joins its call (else shows it in
    /// Calendar), ⌘Return shows it in Calendar, ⇧Return writes to whoever
    /// is invited.
    case event(AgendaEvent)
    /// "rdv demain 14h point budget": Return adds it to the calendar.
    case createEvent(EventRequest)
    /// A reminder: Return checks it off (or on again), ⌘Return opens
    /// Reminders, ⇧Return its link, ⇥ what else can be done.
    case reminder(ReminderItem)
    /// "rappelle-moi d'appeler Paul demain 9h": Return adds it.
    case addReminder(ReminderRequest)
    /// One of the user's pull requests: Return opens it, ⌘Return copies its
    /// link, ⇥ merges, updates its branch…
    case pullRequest(PullRequest)
    /// An unread GitHub notification: Return opens it, ⌘⌫ marks it read.
    case githubNotification(GitHubNotification)
    /// A folder an editor opened lately: Return opens it there again.
    case project(EditorProject)
    /// A page from a browser's history: Return opens it there again.
    case visit(HistoryVisit)
    /// A Homebrew formula or cask: Return installs or upgrades it.
    case brew(BrewPackage)
    /// Every outdated Homebrew package at once.
    case brewUpgradeAll(Int)
    /// A skillie; `inline`: its last line, for inline mode.
    case script(ScriptCommand, inline: String?)
    /// Filling a skillie's argument: the text typed, or a dropdown's
    /// choice.
    case scriptArgument(ScriptCommand, index: Int, text: String)
    case scriptChoice(title: String, value: String)
    /// `fallback`: offered because nothing on the Mac matched.
    case quicklink(Quicklink, query: String, fallback: Bool = false)
    /// The Catalog ("?"): one thing skil.li does; Return runs it as its own
    /// row would.
    case catalog(CatalogEntry)
    /// A group's name over its entries in the Catalog; never selected.
    case catalogHeader(CatalogEntry.Group)
    /// A menu item of the app in front (Search Menu Items): Return chooses it.
    case menuItem(MenuSearch.Entry, MenuReader.Item)

    /// "Keep Awake · 1 h (until 14:05)", "Turn Off Keep Awake".
    static func awakeTitle(_ request: AwakeRequest) -> String {
        switch request {
        case .allowSleep: return AwakeStatus.turnOff
        case .awake(let seconds):
            let until = DateFormatter.localizedString(from: .now.addingTimeInterval(TimeInterval(seconds)), dateStyle: .none, timeStyle: .short)
            return "Keep Awake · \(AwakeRequest.spoken(seconds)) (until \(until))"
        }
    }

    var title: String {
        switch self {
        case .app(let entry): entry.name
        case .command(let command): command.title
        case .siCommand(let command): command.title
        case .ask(let text): "Ask “\(text)”"
        case .setup(let permission): "Allow \(permission.title)"
        case .system(_, let title): title
        case .process(let group, _): "Quit \(group.name)"
        case .clip(let item): item.title
        case .snippet(let snippet): snippet.name
        case .calculation(let result): result.display
        case .emoji(let emoji): emoji.name
        case .gif(let gif): gif.title
        case .layout(let layout): layout.name
        case .saveLayout(let name): "Save Window Layout “\(name)”"
        case .openWindow(let window): window.title.isEmpty ? window.appName : window.title
        case .startTimer(let request): "Start Timer · " + (request.label.isEmpty ? "" : request.label + " · ") + TimerRequest.spoken(request.seconds)
        case .keepAwake(let request): Self.awakeTitle(request)
        case .runningTimer(let timer): timer.title
        case .keptAwake(let until):
            AwakeStatus.title(until: until) { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
        case .recordNamed(let name): "Record “\(name)”"
        case .recording(let live): live.title
        case .browserTab(let tab): tab.title
        case .file(let file): file.name
        case .contact(let match): match.record.name
        case .event(let event): event.title.isEmpty ? "Untitled" : event.title
        case .createEvent(let request): "Add “\(request.title)”"
        case .reminder(let item): item.title
        case .addReminder(let request): "Remind Me: \(request.title)"
        case .pullRequest(let pullRequest): pullRequest.title
        case .githubNotification(let notification): notification.title
        case .project(let project): project.name
        case .script(let command, _): command.title
        case .visit(let visit): visit.shownTitle
        case .brew(let package): package.name
        case .brewUpgradeAll(let count): "Upgrade All (\(count))"
        case .scriptArgument(let command, let index, let text):
            text.isEmpty ? (command.arguments[index].optional ? "Without “\(command.arguments[index].placeholder)”" : command.title)
                : command.arguments[index].kind == .password ? String(repeating: "•", count: text.count) : "“\(text)”"
        case .scriptChoice(let title, _): title
        case .quicklink(let link, let query, let fallback):
            query.isEmpty ? link.name : fallback ? "Search \(link.name) for “\(query)”" : "\(link.name) · \(query)"
        case .catalog(let entry): entry.title
        case .catalogHeader(let group): group.title
        case .menuItem(let entry, _): entry.title
        }
    }

    /// Key for `LearningStore`: survives relaunches and reindexing.
    var learningID: String {
        switch self {
        case .app(let entry): "app:\(entry.url.path)"
        case .command(let command): "cmd:\(command.id.rawValue)"
        case .siCommand(let command): "si:\(command.id)"
        case .ask: "ask"
        case .setup(let permission): "setup:\(permission.rawValue)"
        case .system(let command, _): "system:\(command.rawValue)"
        case .process(let group, _): "process:\(group.key)"
        case .clip(let item): "clip:\(item.id)"
        case .snippet(let snippet): "snippet:\(snippet.id)"
        case .calculation: "calculation"
        case .emoji(let emoji): "emoji:\(emoji.character)"
        case .gif(let gif):
            switch gif.recent {
            case .klipy(let slug): "gif:klipy:\(slug)"
            case .file(let path): "gif:file:\(path)"
            }
        case .layout(let layout): "layout:\(layout.id)"
        case .saveLayout: "save-layout"
        case .openWindow(let window): "window:\(window.app.bundleIdentifier ?? ""):\(window.title)"
        case .startTimer: "start-timer"
        case .keepAwake: "keep-awake-for"
        case .runningTimer(let timer): "timer:\(timer.id)"
        case .keptAwake: "kept-awake"
        case .recordNamed: "record-named"
        case .recording: "recording"
        case .browserTab(let tab): "tab:\(tab.title)"
        case .file(let file): "file:\(file.url.path)"
        case .contact(let match): "contact:\(match.record.id)"
        case .event: "event"
        case .createEvent: "create-event"
        case .reminder: "reminder"
        case .addReminder: "add-reminder"
        case .pullRequest(let pullRequest): "pr:\(pullRequest.repositoryFullName)#\(pullRequest.number)"
        case .githubNotification: "github-notification"
        case .project(let project): "project:\(project.bundleID):\(project.path)"
        case .script(let command, _): "script:\(command.path)"
        case .visit(let visit): "visit:\(visit.url)"
        case .brew(let package): "brew:\(package.isCask ? "cask" : "formula"):\(package.name)"
        case .brewUpgradeAll: "brew-upgrade-all"
        case .scriptArgument(let command, let index, _): "script-argument:\(command.path):\(index)"
        case .scriptChoice(_, let value): "script-choice:\(value)"
        case .quicklink(let link, _, _): "quicklink:\(link.id)"
        case .catalog(let entry): "catalog:\(entry.id)"
        case .catalogHeader(let group): "catalog-group:\(group.rawValue)"
        case .menuItem(let entry, _): "menu:\(entry.place) › \(entry.title)"
        }
    }
}

/// The recording on now, as its launcher row says it.
struct LauncherRecording: Equatable {
    let name: String
    let elapsed: Double
    let paused: Bool

    /// "Recording “Weekly sync” · 12:04", "Paused · “Weekly sync” · 12:04".
    var title: String {
        (paused ? "Paused · “\(name)”" : "Recording “\(name)”") + " · " + MeetingTranscript.clock(elapsed)
    }
}

@MainActor
enum CommandIcon {
    private static var cache: [String: NSImage] = [:]
    private static let size = NSSize(width: 32, height: 32)

    /// The Halo menthe mark at app-icon size, masked like macOS icons.
    static var brand: NSImage {
        if let cached = cache["brand"] { return cached }
        guard let mark = Theme.brandMark else { return image(for: "gearshape") }
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 2, dy: 2)
            NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.225, yRadius: inset.width * 0.225).addClip()
            mark.draw(in: inset)
            return true
        }
        cache["brand"] = image
        return image
    }

    /// SF Symbol on a soft rounded tile, sized like app icons.
    /// `tint`: the glyph's color and a wash of it on the tile (a pull
    /// request's group).
    static func image(for symbol: String, tint: NSColor? = nil) -> NSImage {
        let key = tint.map { "\(symbol)|\($0.description)" } ?? symbol
        if let cached = cache[key] { return cached }
        let glyph = Theme.symbol(symbol, pointSize: 15, weight: .medium)
        let image = NSImage(size: size, flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
            (tint?.withAlphaComponent(0.18) ?? NSColor.labelColor.withAlphaComponent(0.10)).setFill()
            tile.fill()
            if let glyph {
                let tinted = glyph.tinted(tint ?? .secondaryLabelColor)
                let glyphRect = NSRect(
                    x: rect.midX - tinted.size.width / 2,
                    y: rect.midY - tinted.size.height / 2,
                    width: tinted.size.width,
                    height: tinted.size.height
                )
                tinted.draw(in: glyphRect)
            }
            return true
        }
        cache[key] = image
        return image
    }

    /// Git Island's colors for the four groups.
    static func color(_ group: PullRequestGroup) -> NSColor {
        switch group {
        case .ready: NSColor(srgbRed: 0.43, green: 0.82, blue: 0.56, alpha: 1)
        case .blocked: NSColor(srgbRed: 0.98, green: 0.45, blue: 0.42, alpha: 1)
        case .waiting: NSColor(srgbRed: 0.91, green: 0.58, blue: 0.20, alpha: 1)
        case .testing: NSColor(srgbRed: 0.45, green: 0.67, blue: 0.95, alpha: 1)
        }
    }
}

extension NSImage {
    /// Template symbol drawn in `color` (resolved at draw time, so it follows
    /// the appearance).
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
