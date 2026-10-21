import Foundation

/// One thing skil.li can do, as the Catalog lists it: its name, one line in
/// the user's words, what the user wants it for (its group), what is typed
/// to reach it, and what Return does. The launcher's "?" shows them, and
/// Settings → Catalog lists the same entries.
public struct CatalogEntry: Identifiable, Equatable, Sendable {
    /// What the user wants, in the Catalog's order.
    public enum Group: String, CaseIterable, Sendable {
        case find, act, write, stayOnTop, apps, yours, skilli

        public var title: String {
            switch self {
            case .find: "Find"
            case .act: "Do"
            case .write: "Write"
            case .stayOnTop: "Stay on Top"
            case .apps: "In Your Apps"
            case .yours: "Yours"
            case .skilli: "skil.li"
            }
        }
    }

    /// What Return does: what the same row does in the launcher, or, for
    /// what needs words first, the start of them in the search field.
    public enum Run: Hashable, Sendable {
        /// A launcher command: the mode it opens, or what it does.
        case command(LauncherCommand.ID)
        case system(SystemCommand)
        /// A place for the front window.
        case window(WindowLayout)
        /// `text` in the search field, read as if typed, for the user to go
        /// on ("timer "); `hint` stands in the field while it is empty.
        case type(String, hint: String?)
        /// Ask, asked in the card.
        case ask
        case askByVoice
        /// What the user says, typed at the caret.
        case dictate
        /// Changes the case of the selected text.
        case transform(TextTransform)
        /// One of the user's commands, by its id.
        case prompt(String)
        case snippet(String)
        /// A skillie, by its path.
        case skillie(String)
        case quicklink(UUID)
        case layout(String)
        /// A linked app's command, by its id ("cleanshot.capture-area").
        case appLink(String)
        /// A pane of skil.li's Settings ("snippets"), and a part of it
        /// after a slash ("catalog/quicklinks"): where the first one is
        /// made.
        case settings(String)
    }

    /// The launcher row's own id when it has one (`LauncherItem.learningID`:
    /// "cmd:emoji", "system:lockScreen"), so its alias is the same;
    /// "catalog.…" otherwise.
    public let id: String
    public let title: String
    /// What it does, in one line of the user's words.
    public let oneLine: String
    public let group: Group
    /// An SF Symbol.
    public let symbol: String
    /// Typed first to reach it ("kill ", ":", "@", "timer "): the same
    /// string its parser reads. Shown as a keycap.
    public let prefix: String?
    public let run: Run
    /// Words matched by the filter, folded (case, accents): the title's,
    /// the prefix and other words people type, the one line's.
    let titleWords: [String]
    let otherWords: [String]
    let lineWords: [String]

    public init(id: String, title: String, oneLine: String, group: Group, symbol: String, prefix: String? = nil, run: Run,
                keywords: [String] = []) {
        self.id = id
        self.title = title
        self.oneLine = oneLine
        self.group = group
        self.symbol = symbol
        self.prefix = prefix
        self.run = run
        titleWords = Self.words(title)
        // "@" and ":" are words of their own: "? @" finds the contacts.
        let typed = prefix.map { Self.fold($0).trimmingCharacters(in: .whitespaces) }.map { [$0] + Self.words($0) } ?? []
        otherWords = typed + keywords.flatMap(Self.words)
        lineWords = Self.words(oneLine)
    }

    /// An alias reaches it: it is a launcher row of its own (its id is the
    /// row's), one the launcher finds again by id.
    public var takesAlias: Bool {
        guard !id.hasPrefix("catalog.") else { return false }
        switch run {
        case .command, .system, .window, .ask, .prompt, .snippet, .skillie, .quicklink, .layout, .appLink: return true
        case .type, .askByVoice, .dictate, .transform, .settings: return false
        }
    }

    /// Off takes something out of the launcher's results: its own row, or
    /// the rows made from what is typed ("12 × 4", "timer 10 min") or
    /// found by it (a contact in any search). Ask by Voice, Dictate, Do It
    /// Here and the case changes have no row there: no switch for them.
    public var canBeOff: Bool {
        !id.hasPrefix("catalog.") || FeatureCatalog.rowOwners.contains { $0.entry == id }
    }

    /// How well it fits the words typed (`FeatureCatalog.words`): each must
    /// start a word of it, the title's best, then its prefix and other
    /// words, then its line. Nil when one starts none.
    func score(_ typed: [String]) -> Int? {
        var score = 0
        for word in typed {
            if let found = titleWords.first(where: { $0.hasPrefix(word) }) {
                score += found == word ? 4 : 3
            } else if let found = otherWords.first(where: { $0.hasPrefix(word) }) {
                score += found == word ? 3 : 2
            } else if lineWords.contains(where: { $0.hasPrefix(word) }) {
                score += 1
            } else {
                return nil
            }
        }
        // "lock": Lock Screen before what only says it.
        if let first = typed.first, titleWords.first?.hasPrefix(first) == true { score += 2 }
        return score
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Letters and digits in a row, folded.
    static func words(_ text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// Everything skil.li can do, in one list: the built-in features, then what
/// the user made (their commands, snippets, skillies, quicklinks, layouts).
/// Lines the user reads say "SI", never "AI" (the brand's label).
public enum FeatureCatalog {
    /// One of the user's commands: its line is theirs to give.
    public struct Command: Sendable {
        public let id: String
        public let title: String
        public let oneLine: String

        public init(id: String, title: String, oneLine: String) {
            self.id = id
            self.title = title
            self.oneLine = oneLine
        }
    }

    /// What the user made, read once when the Catalog opens.
    public struct Input: Sendable {
        public var commands: [Command]
        public var snippets: [Snippet]
        public var skillies: [ScriptCommand]
        public var quicklinks: [Quicklink]
        public var layouts: [SavedWindowLayout]
        /// The commands of the linked apps installed (CleanShot X), that
        /// their versions take.
        public var appLinks: [AppLinkCommand]
        /// The word for AI the user reads (`Brand.intelligence`).
        public var intelligence: String

        public init(commands: [Command] = [], snippets: [Snippet] = [], skillies: [ScriptCommand] = [], quicklinks: [Quicklink] = [],
                    layouts: [SavedWindowLayout] = [], appLinks: [AppLinkCommand] = [], intelligence: String = "SI") {
            self.commands = commands
            self.snippets = snippets
            self.skillies = skillies
            self.quicklinks = quicklinks
            self.layouts = layouts
            self.appLinks = appLinks
            self.intelligence = intelligence
        }
    }

    /// Every entry, group by group in `Group.allCases`' order.
    public static func entries(_ input: Input = Input()) -> [CatalogEntry] {
        find + act(input) + write(input) + stayOnTop + apps(input) + yours(input) + skilli
    }

    /// The entries that fit what is typed after "?", best first: every
    /// word typed starts one of theirs ("kill", "win left"), not letters
    /// scattered ("kill" is not in "skil.li"). A group stays together, the
    /// one with the best match first. Nothing typed: all, in their order.
    public static func filter(_ entries: [CatalogEntry], _ text: String) -> [CatalogEntry] {
        let typed = words(text)
        guard !typed.isEmpty else { return entries }
        let scored = entries.enumerated().compactMap { index, entry in entry.score(typed).map { (entry, $0, index) } }
        var best: [CatalogEntry.Group: Int] = [:]
        for (entry, score, _) in scored { best[entry.group] = max(best[entry.group] ?? .min, score) }
        let order = Dictionary(uniqueKeysWithValues: CatalogEntry.Group.allCases.enumerated().map { ($1, $0) })
        return scored.sorted { lhs, rhs in
            let (left, right) = (lhs.0.group, rhs.0.group)
            if left != right {
                let (leftBest, rightBest) = (best[left] ?? 0, best[right] ?? 0)
                return leftBest != rightBest ? leftBest > rightBest : order[left, default: 0] < order[right, default: 0]
            }
            return lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.2 < rhs.2
        }.map(\.0)
    }

    /// What is typed, as the filter reads it: words of letters and digits,
    /// folded; a symbol typed alone ("@", ":") is a word too.
    static func words(_ text: String) -> [String] {
        CatalogEntry.fold(text).split(whereSeparator: \.isWhitespace).flatMap { token -> [String] in
            let words = CatalogEntry.words(String(token))
            return words.isEmpty ? [String(token)] : words
        }
    }

    /// The entries as shown: each run of one group under its header.
    public static func sections(_ entries: [CatalogEntry]) -> [(group: CatalogEntry.Group, entries: [CatalogEntry])] {
        var sections: [(group: CatalogEntry.Group, entries: [CatalogEntry])] = []
        for entry in entries {
            if sections.last?.group == entry.group {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append((entry.group, [entry]))
            }
        }
        return sections
    }

    // MARK: - Off

    /// Launcher rows that are not an entry's own row, by the entry they
    /// belong to: `row` is the row's `learningID`, whole or its start.
    static let rowOwners: [(row: String, whole: Bool, entry: String)] = [
        ("calculation", true, "catalog.calculator"),
        ("start-timer", true, "catalog.timer"),
        ("timer:", false, "catalog.timer"),
        ("keep-awake-for", true, "catalog.awake"),
        ("create-event", true, "catalog.event"),
        ("add-reminder", true, "catalog.remind"),
        ("system:sound.output.", false, "catalog.soundOutput"),
        ("system:sound.input.", false, "catalog.microphone"),
        ("system:bluetooth.", false, "catalog.bluetooth"),
        ("system:volume.", false, "catalog.volume"),
        ("system:settings:", false, "catalog.settingsPanes"),
        // Ask "…", the last row of any search.
        ("ask", true, "si:ask"),
        // What a mode finds, shown in any search too: the best contacts,
        // the editors' projects, the meeting about to start.
        ("contact:", false, "cmd:searchContacts"),
        ("project:", false, "cmd:searchProjects"),
        ("event", true, "cmd:agenda"),
        ("save-layout", true, "cmd:newWindowLayout")
    ]

    /// The entry a launcher row belongs to, by the row's `learningID`: its
    /// own ("cmd:emoji"), or the one it comes from ("calculation" →
    /// "catalog.calculator"). An app's row belongs to none: its own id.
    public static func entryID(ofRow row: String) -> String {
        for owner in rowOwners where owner.whole ? row == owner.row : row.hasPrefix(owner.row) {
            return owner.entry
        }
        return row
    }

    /// Whether the launcher's results show the row `row` (a `learningID`)
    /// with the entries `off` turned off in Settings → Catalog. Nothing
    /// off: nothing to look up.
    public static func shows(row: String, off: Set<String>) -> Bool {
        off.isEmpty || !off.contains(entryID(ofRow: row))
    }

    /// A command's line from its prompt: the first sentence, without its
    /// `{variables}`. Empty when nothing is left.
    public static func firstSentence(ofPrompt prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).lazy
            .map { $0.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression) }
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { !$0.isEmpty } ?? ""
        // "Translate into English. Keep the tone." → "Translate into English"
        let sentence = line.range(of: #"[.!?:](\s|$)"#, options: .regularExpression).map { String(line[..<$0.lowerBound]) } ?? line
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 90 ? String(trimmed.prefix(89)) + "…" : trimmed
    }

    // MARK: - The list

    private static func command(_ id: LauncherCommand.ID, _ group: CatalogEntry.Group, _ oneLine: String) -> CatalogEntry {
        let command = LauncherCommand.all.first { $0.id == id }
        return CatalogEntry(id: "cmd:\(id.rawValue)", title: command?.title ?? id.rawValue, oneLine: oneLine, group: group,
                            symbol: command?.symbol ?? "command", prefix: LauncherPrefix.shown(for: id), run: .command(id),
                            keywords: command?.keywords ?? [])
    }

    private static func system(_ command: SystemCommand) -> CatalogEntry {
        CatalogEntry(id: "system:\(command.rawValue)", title: command.title, oneLine: oneLine(command), group: .act, symbol: command.symbol,
                     run: .system(command), keywords: command.keywords)
    }

    private static func window(_ layout: WindowLayout) -> CatalogEntry {
        CatalogEntry(id: "system:window.\(layout.rawValue)", title: layout.title, oneLine: oneLine(layout), group: .act, symbol: layout.symbol,
                     run: .window(layout), keywords: layout.keywords)
    }

    private static var find: [CatalogEntry] {
        [
            command(.searchFiles, .find, "Finds a file by its name, or by what it was about with ⇥"),
            command(.clipboardHistory, .find, "Finds what you copied, text and images, and pastes it again"),
            command(.searchTabs, .find, "Goes to any tab open in Safari, Chrome, Arc or another browser"),
            command(.searchHistory, .find, "Reopens a page you visited, by its words or what it was about"),
            command(.searchContacts, .find, "Finds someone by name, company, email, number or city"),
            command(.emoji, .find, "Types an emoji or a symbol (⌘, →, \u{F8FF}) found by its name, or by a feeling with ⇥"),
            command(.searchGIFs, .find, "Pastes a GIF from Klipy or from this Mac, animated"),
            command(.searchProjects, .find, "Reopens a recent folder in Cursor, VS Code, Zed or JetBrains"),
            command(.homebrew, .find, "Installs, upgrades or removes tools and apps with Homebrew"),
            CatalogEntry(id: "catalog.calculator", title: "Calculator", oneLine: "Answers math, units and time zones: “12 × 4”, “10 km in miles”",
                         group: .find, symbol: "equal", run: .type("", hint: "12 × 4 · 10 km in miles · time in Tokyo"),
                         keywords: ["calculator", "calculatrice", "math", "units", "convert", "conversion", "time zone", "heure", "fuseau"])
        ]
    }

    private static func act(_ input: Input) -> [CatalogEntry] {
        let si = input.intelligence
        let first: [CatalogEntry] = [
            command(.killProcess, .act, "Quits an app and all its helpers, or what listens on a port"),
            CatalogEntry(id: "si:ask", title: "Ask", oneLine: "Lets \(si) answer, rewrite the selection or act: say what you want",
                         group: .act, symbol: "sparkle.magnifyingglass", run: .ask, keywords: [si, "ai", "question", "assistant", "demander"]),
            CatalogEntry(id: "catalog.voice", title: "Ask by Voice", oneLine: "Asks \(si) out loud: say it, and it takes it from there",
                         group: .act, symbol: "mic", run: .askByVoice, keywords: [si, "voice", "speak", "voix", "parler"]),
            CatalogEntry(id: "catalog.doItHere", title: "Do It Here", oneLine: "Clicks and types for you in the window in front: “fill this form”",
                         group: .act, symbol: "cursorarrow.click.2", run: .ask,
                         keywords: [si, "fill", "form", "click", "automate", "agent", "remplir", "formulaire", "fais-le"]),
            CatalogEntry(id: "catalog.askSchedule", title: "Ask on a Schedule",
                         oneLine: "Asks \(si) at the time you say: “every Monday at 9am sum up my PRs”",
                         group: .act, symbol: "calendar.badge.clock", run: .ask,
                         keywords: [si, "schedule", "every", "recurring", "routine", "cron", "chaque", "tous les", "planifier", "programmer"]),
            CatalogEntry(id: "catalog.timer", title: "Timer", oneLine: "Counts down in the menu bar: “timer 10 min tea”, “timer 1:30”",
                         group: .act, symbol: "timer", prefix: TimerRequest.word + " ", run: .type(TimerRequest.word + " ", hint: nil),
                         keywords: ["minuteur", "countdown", "chrono", "pomodoro"]),
            system(.keepAwake),
            CatalogEntry(id: "catalog.awake", title: "Keep Awake for a While", oneLine: "Keeps the Mac awake for a time: “awake 2h”, “awake until 6pm”",
                         group: .act, symbol: "cup.and.saucer", prefix: AwakeRequest.word + " ", run: .type(AwakeRequest.word + " ", hint: nil),
                         keywords: ["caffeinate", "sleep", "veille", "éveillé"])
        ]
        let mac = SystemCommand.allCases.filter { $0 != .keepAwake }.map(system)
        let sound: [CatalogEntry] = [
            CatalogEntry(id: "catalog.soundOutput", title: "Sound Output", oneLine: "Switches where sound plays: speakers, AirPods, a display…",
                         group: .act, symbol: "hifispeaker", run: .type(AudioRoute.title(name: "", output: true), hint: nil),
                         keywords: AudioRoute.keywords(transport: .bluetooth, output: true)),
            CatalogEntry(id: "catalog.microphone", title: "Microphone", oneLine: "Switches the microphone in use: built-in, AirPods, a headset…",
                         group: .act, symbol: "mic.fill", run: .type(AudioRoute.title(name: "", output: false), hint: nil),
                         keywords: AudioRoute.keywords(transport: .bluetooth, output: false)),
            CatalogEntry(id: "catalog.volume", title: "Set Volume", oneLine: "Sets the sound to a level: “volume 30”, “mets le son à 30 %”",
                         group: .act, symbol: "speaker.wave.2.fill", prefix: VolumeRequest.word + " ",
                         run: .type(VolumeRequest.word + " ", hint: nil), keywords: ["sound", "level", "son", "niveau", "percent"]),
            CatalogEntry(id: "catalog.bluetooth", title: "Bluetooth Devices",
                         oneLine: "Connects or disconnects AirPods, a keyboard, a speaker paired with this Mac",
                         group: .act, symbol: "dot.radiowaves.left.and.right", run: .type("bluetooth ", hint: nil),
                         keywords: ["bluetooth", "connect", "disconnect", "airpods", "connecter", "casque", "enceinte"]),
            CatalogEntry(id: "catalog.autoQuit", title: "Auto Quit", oneLine: "Quits the apps you stopped using, after a delay you choose",
                         group: .act, symbol: "moon.zzz", run: .settings("windows"),
                         keywords: ["quit", "idle", "unused", "memory", "quitter", "inutilisées", "mémoire"]),
            CatalogEntry(id: "catalog.settingsPanes", title: "System Settings Panes",
                         oneLine: "Opens a pane of System Settings: type its name, “displays”, “bluetooth”…",
                         group: .act, symbol: "gearshape.2", run: .type("", hint: "A pane of System Settings: Displays, Bluetooth, Wi-Fi…"),
                         keywords: ["system settings", "preferences", "réglages système", "pane", "displays", "bluetooth", "wi-fi"])
        ]
        let windows = [command(.switchWindow, .act, "Brings any open window forward, by its title or its app"),
                       command(.searchMenus, .act, "Chooses any menu item of the app in front, found by its name")]
            + WindowLayout.allCases.map(window)
            + [command(.newWindowLayout, .act, "Saves where every window is, to put them all back in one go"),
               command(.newEmptyWindowLayout, .act, "Builds a window layout app by app, from an empty screen")]
        return first + mac + sound + windows
    }

    private static func write(_ input: Input) -> [CatalogEntry] {
        let commands = input.commands.map { command in
            CatalogEntry(id: "si:\(command.id)", title: command.title,
                         oneLine: command.oneLine.isEmpty ? "Your own \(input.intelligence) command" : command.oneLine,
                         group: .write, symbol: "sparkles", run: .prompt(command.id), keywords: [input.intelligence, "command"])
        }
        let dictate = CatalogEntry(id: "catalog.dictate", title: "Dictate", oneLine: "Types what you say into any app, on this Mac, knowing your contacts’ names",
                                   group: .write, symbol: "waveform.and.mic", run: .dictate,
                                   keywords: ["dictation", "voice", "speech", "speak", "dictée", "dicter", "voix", "parler"])
        let transforms = TextTransform.allCases.map { transform in
            CatalogEntry(id: "catalog.text.\(transform.rawValue)", title: transform.title, oneLine: oneLine(transform), group: .write,
                         symbol: "textformat", run: .transform(transform),
                         keywords: ["case", "capitals", "casse", "majuscules", "minuscules"])
        }
        let snippets = input.snippets.isEmpty
            ? [CatalogEntry(id: "catalog.snippets", title: "Snippets", oneLine: "Saves a text once; its keyword types it anywhere",
                            group: .write, symbol: "text.quote", run: .settings("snippets"), keywords: ["snippet", "text", "texte", "keyword"])]
            : input.snippets.map { snippet in
                let line = snippet.text.split(whereSeparator: \.isNewline).first.map { "Types “\($0.trimmingCharacters(in: .whitespaces))”" }
                return CatalogEntry(id: "snippet:\(snippet.id)", title: snippet.name, oneLine: line ?? "Your snippet", group: .write,
                                    symbol: "text.quote", prefix: snippet.keyword.isEmpty ? nil : snippet.keyword, run: .snippet(snippet.id))
            }
        let search = [command(.searchSnippets, .write, "Types a snippet found by its name, or by what you need with ⇥"),
                      command(.pasteInSequence, .write, "Pastes your last copies one after another, a key each, newest first")]
        // After what the user made, as Settings puts its Add button.
        let newCommand = command(.newCommand, .write, "Starts a new \(input.intelligence) command in Settings, to run on the text you select")
        let newSnippet = command(.newSnippet, .write, "Starts a new snippet in Settings: a text its keyword types anywhere")
        return commands + [newCommand, dictate] + transforms + search + snippets + [newSnippet]
    }

    private static var stayOnTop: [CatalogEntry] {
        [
            command(.agenda, .stayOnTop, "Lists your coming events and joins their calls"),
            CatalogEntry(id: "catalog.event", title: "Add an Event", oneLine: "Adds an event said in one line: “event lunch with Paul tomorrow 1pm”",
                         group: .stayOnTop, symbol: "calendar.badge.plus", prefix: EventRequest.word + " ",
                         run: .type(EventRequest.word + " ", hint: nil), keywords: ["calendar", "meeting", "rdv", "rendez-vous", "événement"]),
            command(.copyAvailability, .stayOnTop, "Copies your free time in the next five working days"),
            command(.reminders, .stayOnTop, "Lists what you have to do, and checks it off"),
            CatalogEntry(id: "catalog.remind", title: "Remind Me", oneLine: "Adds a reminder said in one line: “remind me to call Paul at 9am”",
                         group: .stayOnTop, symbol: "checklist", prefix: ReminderRequest.word + " ", run: .type(ReminderRequest.word + " ", hint: nil),
                         keywords: ["reminder", "todo", "task", "rappel", "rappelle-moi"]),
            command(.github, .stayOnTop, "Shows your pull requests and unread GitHub notifications")
        ]
    }

    /// The linked apps' commands, each its launcher row's id
    /// ("system:link:cleanshot.capture-area").
    private static func apps(_ input: Input) -> [CatalogEntry] {
        input.appLinks.map { command in
            let app = command.app?.name ?? ""
            return CatalogEntry(id: appLinkEntryID(command.id), title: command.title, oneLine: "\(command.oneLine), in \(app)", group: .apps,
                                symbol: command.symbol, run: .appLink(command.id), keywords: command.keywords + [app])
        }
    }

    /// The Catalog entry, and launcher row, of a linked app's command.
    public static func appLinkEntryID(_ command: String) -> String {
        "system:link:\(command)"
    }

    private static func yours(_ input: Input) -> [CatalogEntry] {
        let skillies = input.skillies.isEmpty
            ? [CatalogEntry(id: "catalog.skillies", title: "Skillies", oneLine: "Turns your own scripts into commands you run from here",
                            group: .yours, symbol: "terminal", run: .settings("skillies"), keywords: ["scripts", "skillie", "raycast"])]
            : input.skillies.map { skillie in
                CatalogEntry(id: "script:\(skillie.path)", title: skillie.title,
                             oneLine: skillie.description.isEmpty ? "Your skillie" : skillie.description, group: .yours, symbol: "terminal",
                             run: .skillie(skillie.path), keywords: [skillie.packageName])
            }
        let links = input.quicklinks.isEmpty
            ? [CatalogEntry(id: "catalog.quicklinks", title: "Quicklinks", oneLine: "Searches a site from here: its keyword, then what to find",
                            group: .yours, symbol: "link", run: .settings("catalog/quicklinks"), keywords: ["quicklink", "web", "search", "lien"])]
            : input.quicklinks.map { link in
                let host = URL(string: link.url.replacingOccurrences(of: Quicklink.queryToken, with: ""))?.host() ?? link.url
                let typed = link.takesQuery && !link.keyword.isEmpty
                return CatalogEntry(id: "quicklink:\(link.id.uuidString)", title: link.name,
                                    oneLine: typed ? "Searches \(link.name): “\(link.keyword) what you look for”" : "Opens \(host)",
                                    group: .yours, symbol: "link", prefix: typed ? link.keyword + " " : nil, run: .quicklink(link.id))
            }
        let layouts = input.layouts.map { layout in
            CatalogEntry(id: "layout:\(layout.id)", title: layout.name, oneLine: "Puts back \(layout.summary)", group: .yours,
                         symbol: "rectangle.3.group", run: .layout(layout.id))
        }
        let newQuicklink = command(.newQuicklink, .yours, "Starts a new quicklink in Settings: a site searched from its keyword")
        return skillies + links + [newQuicklink] + layouts
    }

    private static var skilli: [CatalogEntry] {
        [
            command(.openSettings, .skilli, "Opens every option, shortcut and account"),
            command(.catalog, .skilli, "Lists everything skil.li does, and how to reach it"),
            command(.welcome, .skilli, "Shows the first launch's welcome again: the Hyper Key, the launcher, your SI"),
            command(.backUpNow, .skilli, "Saves your settings and files to the folder of Settings → Backup"),
            command(.resetLauncherPosition, .skilli, "Puts the launcher back in the middle of the screen"),
            command(.quit, .skilli, "Quits skil.li; its shortcuts stop until you open it again")
        ]
    }

    // MARK: - Lines

    private static func oneLine(_ command: SystemCommand) -> String {
        switch command {
        case .lockScreen: "Locks the screen at once"
        case .sleep: "Puts the Mac to sleep"
        case .sleepDisplays: "Turns the displays off; the Mac keeps running"
        case .toggleDarkMode: "Switches between dark and light appearance"
        case .keepAwake: "Keeps the Mac awake until you run it again"
        case .toggleHiddenFiles: "Shows or hides hidden files in Finder"
        case .ejectDisks: "Ejects every external and network disk"
        case .emptyTrash: "Empties the Trash, once you confirm"
        case .restart: "Restarts the Mac, once you confirm"
        case .shutDown: "Shuts the Mac down, once you confirm"
        case .logOut: "Logs out of this account, once you confirm"
        case .playPause: "Plays or pauses what is playing: Music, Spotify, a video"
        case .nextTrack: "Skips to the next song"
        case .previousTrack: "Goes back to the previous song"
        case .volumeUp: "Turns the sound up a step"
        case .volumeDown: "Turns the sound down a step"
        case .mute: "Mutes the sound, or turns it back on"
        case .speedTest: "Measures your internet speed, down and up"
        case .pickColor: "Picks a color anywhere on screen and copies its hex code"
        case .pasteLatestScreenshot: "Pastes your last screenshot in the app in front"
        case .systemInfo: "Shows battery, free disk, memory, Wi-Fi, IP address and uptime"
        case .cleanKeyboard: "Turns the keyboard off for a minute so you can wipe it"
        case .quitAllApps: "Quits every open app; each asks to save first"
        case .quitOtherApps: "Quits every app but the one in front"
        case .hideOtherApps: "Hides every app but the one in front"
        case .showAllApps: "Shows every hidden app again"
        case .toggleMicrophone: "Mutes the microphone, or turns it back on"
        case .wifiOn: "Turns Wi-Fi on"
        case .wifiOff: "Turns Wi-Fi off; a cable keeps the Mac online"
        case .showDesktop: "Moves every window aside to show the desktop; again brings them back"
        }
    }

    private static func oneLine(_ layout: WindowLayout) -> String {
        switch layout {
        case .leftHalf: "Puts the front window on the left half; again for ⅔, then ⅓"
        case .rightHalf: "Puts the front window on the right half; again for ⅔, then ⅓"
        case .topHalf: "Puts the front window on the top half; again for ⅔, then ⅓"
        case .bottomHalf: "Puts the front window on the bottom half; again for ⅔, then ⅓"
        case .topLeft: "Puts the front window in the top left quarter"
        case .topRight: "Puts the front window in the top right quarter"
        case .bottomLeft: "Puts the front window in the bottom left quarter"
        case .bottomRight: "Puts the front window in the bottom right quarter"
        case .leftThird: "Puts the front window on the left third"
        case .centerThird: "Puts the front window on the middle third; again for ½, then ⅔"
        case .rightThird: "Puts the front window on the right third"
        case .leftTwoThirds: "Puts the front window on the left two thirds"
        case .rightTwoThirds: "Puts the front window on the right two thirds"
        case .maximize: "Makes the front window fill the screen; again puts it back"
        case .almostMaximize: "Makes the front window almost fill the screen, centered"
        case .center: "Centers the front window on its screen, same size"
        case .nextDisplay: "Moves the front window to the next display, in the same place"
        case .previousDisplay: "Moves the front window to the previous display, in the same place"
        case .restore: "Puts the front window back where it was before skil.li moved it"
        }
    }

    private static func oneLine(_ transform: TextTransform) -> String {
        switch transform {
        case .uppercase: "Puts the selected text in capitals"
        case .lowercase: "Puts the selected text in lowercase"
        case .capitalized: "Capitalizes each word of the selected text"
        }
    }
}
