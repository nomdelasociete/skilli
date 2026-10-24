import Foundation

/// One choice a setting offers: what tools say ("weekly") and what the
/// pane shows ("Every week").
public struct SettingOption: Equatable, Hashable, Sendable {
    public let value: String
    public let title: String

    public init(_ value: String, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// A setting's value as tools read and write it.
public enum SettingValue: Equatable, Sendable {
    case bool(Bool)
    /// A choice's value, a folder, a text.
    case text(String)
    /// A list's items, as the pane shows them.
    case list([String])
}

/// One setting as a Settings pane shows it and skil.li's tools name it.
public struct SettingEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// On or off.
        case toggle
        /// One of these.
        case choice([SettingOption])
        /// One of what this Mac has (apps installed, lists, models): the
        /// app gives the choices.
        case choiceOnThisMac
        /// One of these, or a number in the range ("Custom": 14 days),
        /// written "<unit>:<number>".
        case choiceOrNumber([SettingOption], ClosedRange<Int>, unit: String)
        /// Free text, up to this many characters.
        case text(maxLength: Int)
        /// A folder that exists on this Mac; `empty`: what no folder means
        /// (nil: one is needed).
        case folder(empty: String?)
        /// Only back to its default ("default"); read as moved or not.
        case reset(moved: String, standard: String)
        /// Many of something, one added or removed at a time; `item` says
        /// what one is, `adds` whether tools can add one.
        case list(item: String, adds: Bool)
    }

    /// Who changes it.
    public enum Access: Equatable, Sendable {
        /// These tools, after the user's OK in the card.
        case tools([String])
        /// Read by agents, changed only by the user in the pane: why.
        case paneOnly(String)
    }

    /// The pane's id (`SettingsPane`'s raw value).
    public let pane: String
    /// What tools call it; the `Preferences` property's name when it is one.
    public let key: String
    /// As the pane shows it.
    public let name: String
    public let kind: Kind
    public let access: Access
    /// The `Preferences` property behind it; nil when it lives elsewhere (a
    /// file, macOS, the Keychain, the tools' settings).
    public let preference: String?
    /// A secret (a key, a token): reported only as set or not set.
    public let secret: Bool
    /// Its value is the user's own content (About You, a field's value, a
    /// snippet's text, an address, a name): get_settings reports it only
    /// as set or not set (`SettingsReport`).
    public let personal: Bool
    /// What to know: when the pane shows it, what it does.
    public let note: String?

    public var isSettable: Bool {
        if case .tools = access { return true }
        return false
    }

    /// Changed with set_setting (not with tools of its own).
    public var usesSetSetting: Bool { access == .tools([SettingsTable.Tool.setSetting]) }
}

/// Every setting Settings shows, mapped to the tool that changes it (rule 11
/// of the Settings plan: "Anything a pane sets, an agent can set through
/// skil.li's tools under the same name, after your OK in the card. A
/// setting with no tool is not finished."). The app binds each key to what
/// it changes (`SettingTools`); the self-test and the unit tests check that
/// every `Preferences` property is here or in `notInPanes`.
public enum SettingsTable {
    public enum Tool {
        public static let getSettings = "get_settings"
        public static let setSetting = "set_setting"
        public static let setAlias = "set_alias"
        public static let removeAlias = "remove_alias"
        public static let createQuicklink = "create_quicklink"
        public static let updateQuicklink = "update_quicklink"
        public static let deleteQuicklink = "delete_quicklink"
        public static let createSnippet = "create_snippet"
        public static let updateSnippet = "update_snippet"
        public static let deleteSnippet = "delete_snippet"
        public static let addShortcut = "add_shortcut"
        public static let changeShortcut = "change_shortcut"
        public static let removeShortcut = "remove_shortcut"
        public static let listScheduledAsks = "list_scheduled_asks"
        public static let addScheduledAsk = "add_scheduled_ask"
        public static let pauseScheduledAsk = "pause_scheduled_ask"
        public static let removeScheduledAsk = "remove_scheduled_ask"

        /// The tools this table names, in the order agents see them.
        public static let all = [getSettings, setSetting, setAlias, removeAlias, createQuicklink, updateQuicklink, deleteQuicklink,
                                 createSnippet, updateSnippet, deleteSnippet, addShortcut, changeShortcut, removeShortcut,
                                 listScheduledAsks, addScheduledAsk, pauseScheduledAsk, removeScheduledAsk]

        /// The ones that only read: no card for them.
        public static let reads: Set<String> = [getSettings, listScheduledAsks]

        /// The ones that change something: each asks the user every time
        /// in the card (no Always; no right or mode makes it silent).
        public static let changes = Set(all).subtracting(reads)
    }

    public struct Problem: LocalizedError, Equatable, Sendable {
        public let message: String

        public init(_ message: String) {
            self.message = message
        }

        public var errorDescription: String? { message }
    }

    /// The panes, by id, in the sidebar's order (`SettingsPane`).
    public static let panes = ["general", "keys", "privacy", "backup", "launcher", "clipboard", "snippets", "emoji", "gifs", "windows", "calendar",
                               "reminders", "github", "apps", "yourDetails", "ask", "commands", "tools", "skillies", "aiAccounts", "catalog", "about"]

    /// `Preferences` properties no pane shows, and why.
    public static let notInPanes: [String: String] = [
        "didCompleteSetup": "The setup window's own state: closed once (Done, Later or ✕), it no longer opens by itself.",
        "recorderConsentShown": "The Record card's own state: it said once that the others in a call must agree to be recorded.",
        "launcherPins": "Pinned in the launcher itself (⌘K → Pin, Unpin), not in a pane; the user's own list: no tool reads or changes it."
    ]

    /// Why the user alone changes these, in the tools' words.
    public enum Why {
        public static let secret = "A key or a token: the user pastes it in the pane; tools only say whether one is set."
        public static let rights = "What agents may do is the user's alone: an agent never widens its own rights."
        public static let macOS = "macOS owns permissions: the user turns them on in System Settings (Settings → Privacy opens the right list)."
        public static let signIn = "Signing in is the user's, in the app's own sign-in: skil.li never handles it."
        public static let relay = "It says where skil.li sends the relay's stream token: the user sets it in the pane."
    }

    private static let set = SettingEntry.Access.tools([Tool.setSetting])

    private static func setting(_ pane: String, _ key: String, _ name: String, _ kind: SettingEntry.Kind,
                                access: SettingEntry.Access = set, preference: String?? = .none, secret: Bool = false,
                                personal: Bool = false, note: String? = nil) -> SettingEntry {
        // Not given: the Preferences property of the same name; nil: none.
        let property: String? = switch preference {
        case .none: key
        case .some(let named): named
        }
        return SettingEntry(pane: pane, key: key, name: name, kind: kind, access: access, preference: property, secret: secret,
                            personal: personal, note: note)
    }

    private static func minutes(_ values: [Int], _ title: (Int) -> String) -> [SettingOption] {
        values.map { SettingOption(String($0), title($0)) }
    }

    /// Every setting, pane by pane, in the panes' order.
    public static let entries: [SettingEntry] = [
        // General
        setting("general", "openAtLogin", "Open skil.li at login", .toggle, preference: .some(nil),
                note: "A login item macOS lists in System Settings → General → Login Items; it may ask the user to allow it there."),
        setting("general", "showMenuBarIcon", "Show in menu bar", .toggle),
        setting("general", "glassStyle", "Glass", .choice([SettingOption("regular", "Regular"), SettingOption("clear", "Clear")]),
                note: "The launcher, the card and the key hints are drawn in this glass."),
        setting("general", "launcherPlace", "Launcher position",
                .reset(moved: "Where the user dragged it", standard: "In the middle, its usual height"),
                note: "Under Advanced. Only back to its default (Reset Position): where it goes otherwise is dragged by hand."),

        // Keys
        setting("keys", "hyperTapSendsEscape", "Tap Caps Lock alone to send Escape", .toggle,
                note: "Under Advanced. Only when skil.li handles Caps Lock itself (not with Raycast's Hyper Key)."),
        setting("keys", "shortcuts", "Shortcuts",
                .list(item: "keys (hyper+y, cmd+shift+k, a chain hyper+k y) and what they run", adds: true),
                access: .tools([Tool.addShortcut, Tool.changeShortcut, Tool.removeShortcut]), preference: .some(nil),
                note: "Every global shortcut, in shortcuts.json. The first key needs ✦ (hyper, Caps Lock), ⌘, ⌃ or ⌥; no shortcut may equal or start another. Also shown in Launcher, Clipboard, Ask and Windows."),

        // Privacy
        setting("privacy", "permissions", "Permissions", .list(item: "a permission and its state", adds: false),
                access: .paneOnly(Why.macOS), preference: .some(nil)),

        // Backup
        setting("backup", "backupFolder", "Back up to", .folder(empty: nil),
                note: "A folder that exists on this Mac; in iCloud Drive a backup also brings skil.li to a new Mac."),
        setting("backup", "backupSchedule", "How often", .choice(BackupSchedule.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "Every day, week or month from the last backup; no day of the week."),
        setting("backup", "backupKeep", "Keep",
                .choice([SettingOption("5", "The last 5"), SettingOption("10", "The last 10"), SettingOption("30", "The last 30"),
                         SettingOption("0", "All of them")])),

        // Launcher
        setting("launcher", "launcherScreen", "Opens on", .choice(LauncherScreen.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "Which screen the launcher shows on; on that screen, where the user last dragged it (General → Launcher position)."),
        setting("launcher", "launcherReset", "Starts again empty", .choice(LauncherReset.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "Opened again before then, it shows what was typed, its mode and the row selected. ↑ in the empty field brings back recent searches either way."),
        setting("launcher", "historyMeaningSearch", "Search browser history by meaning with ⇥", .toggle,
                note: "On ⇥ only, the last pages' titles, sites and dates go to the user's TypeSafe Jev or OpenAI Decisions key."),
        setting("launcher", "fileMeaningSearch", "Search files by meaning with ⇥", .toggle,
                note: "On ⇥ only, names, kinds, folders and dates of recent files go to the user's TypeSafe Jev or OpenAI Decisions key."),
        setting("launcher", "launcherEnglishInput", "Type in English while open", .toggle,
                note: "Under Advanced. While the launcher is open the keyboard types with the user's own English layout (ABC, else U.S.), then theirs again; shortcuts keep their keys. Does nothing when no English layout is turned on in System Settings → Keyboard."),

        // Clipboard
        setting("clipboard", "clipboardHistory", "Keep clipboard history", .toggle),
        setting("clipboard", "clipboardRetention", "Keep copies for",
                .choiceOrNumber([SettingOption("day", "1 day"), SettingOption("week", "1 week"), SettingOption("month", "1 month"),
                                 SettingOption("unlimited", "Unlimited")], 1...3650, unit: "days"),
                note: "Or a number of days (Custom). Changing it removes nothing at once: older copies go on the next hourly pass, and the pane says how many first."),
        setting("clipboard", "clipboardScreenshots", "Keep screenshots too", .toggle,
                note: "New images in macOS's screenshots folder (or the folder chosen) join the history as if copied; their words are read on this Mac."),
        setting("clipboard", "clipboardMeaningSearch", "Search by meaning with ⇥", .toggle,
                note: "Under Advanced. On ⇥ only, short excerpts of the last copies go to the user's TypeSafe Jev or OpenAI Decisions key."),
        setting("clipboard", "clipboardLinkPreviews", "Show link previews", .toggle,
                note: "Under Advanced. A copied link shown in the history's preview is opened by skil.li, without cookies or sign-ins, to read its title, description, picture and icon, kept with the copy; never for copies not looked at."),
        setting("clipboard", "clipboardOCR", "Read text in images", .toggle,
                note: "Under Advanced. Vision reads the words of copied images and screenshots on this Mac, so search finds them."),
        setting("clipboard", "imageTagsClipboard", "Images you copy, by what they show", .toggle,
                note: "Under Advanced, images by what they show: Jev looks once at a small copy of each (the user's TypeSafe key)."),
        setting("clipboard", "imageTagsFolder", "Screenshots, by what they show", .toggle,
                note: "Under Advanced: Jev looks once at a small copy of each new image of the folder. Only while Keep screenshots too is on."),
        setting("clipboard", "imageTagsFolderPath", "Folder", .folder(empty: "macOS's screenshots folder"),
                note: "Shown when Keep screenshots too is on; “default” for macOS's screenshots folder."),
        setting("clipboard", "clipboardExcludedApps", "Never keep copies from", .list(item: "an app, by its name or bundle id", adds: true)),

        // Snippets
        setting("snippets", "snippetExpansion", "Expand keywords as you type", .toggle),
        setting("snippets", "snippetExpansionMode", "Expand",
                .choice(SnippetExpansionMode.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "Shown when Expand keywords as you type is on. As soon as it is typed: a keyword with a symbol (;addr) at once, one made of letters once its word ends. After a space or ↩: every keyword waits for one, which stays after the snippet or is left out."),
        setting("snippets", "snippetMeaningSearch", "Find snippets by meaning with ⇥", .toggle,
                note: "On ⇥ only in Search Snippets, each snippet's name, keyword and first \(SnippetMeaning.previewLength) characters go to the user's TypeSafe Jev or OpenAI Decisions key."),
        setting("snippets", "snippets", "Snippets", .list(item: "a name, a keyword and its text", adds: true),
                access: .tools([Tool.createSnippet, Tool.updateSnippet, Tool.deleteSnippet]), preference: .some(nil), personal: true,
                note: "Placeholders: {cursor} where the caret ends, {clipboard}, {date}, {time}, {day}, {name}."),
        setting("snippets", "snippetExcludedApps", "Keywords stay as typed in", .list(item: "an app, by its name or bundle id", adds: true),
                note: "Password fields never expand, whatever the app."),

        // Emoji
        setting("emoji", "emojiSkinTone", "Skin tone", .choice(EmojiSkinTone.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "Search Emoji shows and types the emoji that come in tones (👍, 👋, 🙏) in this one; “default” is the yellow one. A family or people holding hands stay as they are."),
        setting("emoji", "emojiMeaningSearch", "Find emoji by feeling with ⇥", .toggle,
                note: "On ⇥, or by itself when no emoji's name fits, what was typed goes with emoji names to the user's TypeSafe Jev or OpenAI Decisions key. An emoji picked then is found by the same words next time, on this Mac."),

        // GIFs
        setting("gifs", "klipyKey", "Klipy key", .text(maxLength: 0), access: .paneOnly(Why.secret), preference: .some(nil), secret: true,
                note: "The user's own Klipy key, when set: Search GIFs asks Klipy with it instead of skil.li's."),

        // Windows
        setting("windows", "windowGap", "Space between windows",
                .choice([SettingOption("0", "None"), SettingOption("4", "4 points"), SettingOption("8", "8 points"),
                         SettingOption("12", "12 points"), SettingOption("16", "16 points")]),
                note: "Between windows side by side and at the screen's edges, for every place ✦W, the launcher or Ask puts the front window in (halves, thirds, quarters, Maximize), and for windows placed in the layout editor."),
        setting("windows", "autoQuit", "Quit apps you stopped using", .toggle,
                note: "Off by default. Never the app in front, one with unsaved work, sound or a call going on, or one busy; with a deciding key, Jev reads the windows' titles first."),
        setting("windows", "autoQuitMinutes", "Unused for",
                .choice(AutoQuit.delays.map { SettingOption(String($0), AutoQuit.spoken(minutes: $0)) }),
                note: "Shown when Quit apps you stopped using is on: how long an app goes unused before it is quit."),
        setting("windows", "autoQuitNever", "Never quit", .list(item: "an app, by its name or bundle id", adds: true),
                note: "Shown when Quit apps you stopped using is on."),
        setting("windows", "windowLayoutIgnoredApps", "Always leave out of layouts", .list(item: "an app, by its name or bundle id", adds: true)),
        setting("windows", "ignoredMonitors", "Monitors ignored when plugged in", .list(item: "a monitor, by its name", adds: false),
                note: "A monitor is ignored from the question shown when it is plugged in (Ignore This Monitor); tools only take one off."),
        setting("windows", "windowLayouts", "Layouts", .list(item: "a saved window layout", adds: false),
                access: .paneOnly("Layouts are looked over in the layout editor before they are saved; agents save and apply them with save_window_layout and apply_window_layout."),
                preference: .some(nil)),

        // Calendar
        setting("calendar", "agendaMenuBar", "Next meeting in the menu bar",
                .choice([SettingOption("never", "Never"), SettingOption("atStart", "When it starts"),
                         SettingOption("fiveBefore", "5 minutes before"), SettingOption("tenBefore", "10 minutes before"),
                         SettingOption("thirtyBefore", "30 minutes before"), SettingOption("hourBefore", "1 hour before"),
                         SettingOption("always", "Always, the next one")])),
        setting("calendar", "agendaAlerts", "Alerts",
                .list(item: "when and how: “on time”, “5 min before”, “1 hour before, screens dark”", adds: true),
                note: "Each a card in the middle of the screen, or the card with every screen dark around it. When: on time, 1, 2, 5, 10, 15, 30 min or 1 hour before. Adding one at the same time changes its style."),
        setting("calendar", "agendaAutoJoin", "When a meeting starts",
                .choice([SettingOption("off", "Nothing more"), SettingOption("join", "Join at once")])),
        setting("calendar", "agendaLauncherMinutes", "Before you type, the meeting shows",
                .choice(minutes([2, 5, 10, 15, 30]) { "From \($0) minutes before" }), note: "Under Advanced."),
        setting("calendar", "agendaMenuBarCallsOnly", "Only meetings with a call in the menu bar", .toggle,
                note: "Under Advanced, when the next meeting is in the menu bar."),
        setting("calendar", "agendaCountdown", "Count down to its end", .toggle,
                note: "Under Advanced, when the next meeting is in the menu bar."),
        setting("calendar", "agendaHideAfter", "Leaves the menu bar",
                .choice(minutes([5, 10, 15]) { "\($0) minutes after it starts" } + [SettingOption("-1", "When it ends")]),
                note: "Under Advanced, when Count down to its end is off."),
        setting("calendar", "agendaNextDuringMeeting", "The next one too, during a meeting", .toggle,
                note: "Under Advanced, when the next meeting is in the menu bar."),
        setting("calendar", "agendaAlertWithoutCall", "Alerts for events without a call too", .toggle,
                note: "Under Advanced, when there is an alert."),
        setting("calendar", "agendaApp", "Open events in", .choiceOnThisMac, note: "Under Advanced."),
        setting("calendar", "agendaMeetBrowser", "Google Meet opens in", .choiceOnThisMac, note: "Under Advanced."),
        setting("calendar", "agendaHiddenCalendars", "Calendars turned off", .list(item: "a calendar, by its name (and account)", adds: true),
                note: "The pane shows every calendar with a switch; one turned off stays out of the agenda, the next meeting and Ask. Remove one to turn it on again."),

        // Reminders
        setting("reminders", "remindersDefaultList", "Said reminders go to", .choiceOnThisMac),
        setting("reminders", "remindersMenuBar", "Today's reminders in the menu bar",
                .choice([SettingOption("never", "Never"), SettingOption("count", "How many are due today"),
                         SettingOption("countAndNext", "How many, and the next one")])),
        setting("reminders", "reminderPlaces", "Places", .list(item: "“Name: address”, found with Apple Maps", adds: true), personal: true,
                note: "For “remind me when I get home”: maison and home, bureau and work are the same place."),

        // GitHub
        setting("github", "githubUnderSearch", "Show under the search field", .toggle),
        setting("github", "relayPublicURL", "Live updates from", .text(maxLength: 300), access: .paneOnly(Why.relay),
                note: "Under Advanced. The address of the user's own relay, which says when a pull request changes; empty reads GitHub on a timer."),
        setting("github", "githubAccount", "GitHub", .text(maxLength: 0), access: .paneOnly(Why.signIn), preference: .some(nil)),
        setting("github", "relayToken", "Live updates token", .text(maxLength: 0), access: .paneOnly(Why.secret), preference: .some(nil),
                secret: true, note: "Under Advanced, with Live updates from."),

        // Apps
        setting("apps", "cleanShotTextLineBreaks", "Line breaks in Capture Text",
                .choice(CleanShot.TextLineBreaks.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "CleanShot X's Capture Text from its row, a shortcut or Ask (⌘K on its row offers both); shown while CleanShot X is installed."),
        setting("apps", "appFiles", "Your app files", .list(item: "an app and the links it documents", adds: true), access: .tools(["create_app_link"]),
                preference: .some(nil),
                note: "Files in ~/Library/Application Support/skil.li/Apps, each an app the list then shows with its commands; run_action runs them. A file left out is said in the pane, with why."),

        // Your Details
        setting("yourDetails", "otherDetails", "Your other details", .list(item: "“Field: value”, a SIRET, a VAT number…", adds: true),
                preference: "formProfiles", personal: true,
                note: "get_settings says which fields there are, not their values. Values in the Keychain (IBAN, social security number…) are typed by the user in the pane."),
        setting("yourDetails", "people", "People and companies", .list(item: "a person's or a company's name", adds: true),
                preference: "formProfiles", personal: true, note: "Their own fields are set in the pane."),
        setting("yourDetails", "aboutYou", "About You", .text(maxLength: 4000), preference: .some(nil), personal: true,
                note: "Sent with the commands that include it; saved in about-you.md."),

        // Ask
        setting("ask", "approvalMode", "Approvals",
                .choice([SettingOption("ask", "Ask Every Time"), SettingOption("auto", "Ask Before Changes"), SettingOption("always", "Always Allow")]),
                access: .paneOnly(Why.rights), preference: .some(nil)),
        setting("ask", "approvalRules", "Your rules",
                .list(item: "a rule in the user's words and what it does: Allow, Ask First or Never", adds: false),
                access: .paneOnly(Why.rights), preference: .some(nil),
                note: "Read as “Ask First: Ask before anything that sends a message”. Checked before an agent's step with the user's TypeSafe Jev or OpenAI key; a blocked tool and a change to skil.li's settings are never put to them."),
        setting("ask", "keepClaudeReady", "Keep Claude ready", .toggle,
                note: "Under Advanced. A spare Claude Code waits outside skil.li (about 230 MB, no tokens): answers start sooner."),
        setting("ask", "voiceLanguage", "Voice language", .choiceOnThisMac,
                note: "Under Advanced. Ask by Voice and Dictate; Automatic follows the keyboard's language."),
        setting("ask", "handoffTarget", "Continue in", .choice(Handoff.Target.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "Under Advanced. Also Tools → Help Me Choose's “With”."),
        setting("ask", "handoffTerminal", "Terminal", .choice(Handoff.Terminal.allCases.map { SettingOption($0.rawValue, $0.title) }),
                note: "Under Advanced, with Continue in."),
        setting("ask", "askUsesClaudeCodeSkills", "Use Claude Code's skills too", .toggle,
                note: "Under Advanced. Ask's agent also uses the skills in ~/.claude/skills; one of skil.li's own with the same name comes first."),
        setting("ask", "skills", "Skills", .list(item: "a skill: a folder holding a SKILL.md", adds: true), access: .tools(["create_skill"]),
                preference: .some(nil),
                note: "Under Advanced. Folders in ~/Library/Application Support/skil.li/skills, each with a SKILL.md saying when to use it and how; Ask's agent uses one when it fits."),
        setting("ask", "scheduledAsks", "On a Schedule", .list(item: "when, then what to ask: “every Monday at 9:00: sum up my pull requests”", adds: true),
                access: .tools([Tool.addScheduledAsk, Tool.pauseScheduledAsk, Tool.removeScheduledAsk]), preference: .some(nil), personal: true,
                note: "Last in the pane. Each runs at its time as Ask would, and its answer shows in the card; one missed while the Mac slept runs once when it wakes. list_scheduled_asks lists them; a last answer is the user's own: only whether there is one."),

        // Commands
        setting("commands", "commands", "Commands", .list(item: "a command", adds: false),
                access: .paneOnly("Commands are written and edited in the pane's editor; agents list and run them with list_commands and run_command."),
                preference: .some(nil)),

        // Tools
        setting("tools", "toolRights", "skil.li Tools", .list(item: "a tool and its right", adds: false),
                access: .paneOnly(Why.rights + " Help Me Choose opens the user's own agent with list_tool_rights and set_tool_rights, each change confirmed."),
                preference: .some(nil)),
        setting("tools", "servers", "Connected Servers", .list(item: "an MCP server", adds: false),
                access: .paneOnly("A server gives agents new tools, and sign-ins go to it: only the user adds one."), preference: .some(nil)),
        setting("tools", "customTools", "Your Tools", .list(item: "a webhook", adds: false),
                access: .paneOnly("A tool of the user's sends text to an address: only the user adds one."), preference: .some(nil)),

        // Skillies
        setting("skillies", "skillies", "Your Skillies", .list(item: "a skillie", adds: true), access: .tools(["create_skillie"]),
                preference: .some(nil), note: "Scripts in ~/Library/Application Support/skil.li/skillies; list_skillies and run_skillie too."),
        setting("skillies", "skilliesInMenuBar", "In the menu bar", .list(item: "an inline skillie with no argument, by its title", adds: true),
                note: "Its last line shows in the menu bar, read again at its own refresh time (10 s at least, a minute when it says none)."),

        // SI Accounts
        setting("aiAccounts", "writingModel", "Model", .choiceOnThisMac,
                note: "Writing: Ask and every command write with it. OpenAI's models take an effort: “chatgpt/gpt-6-luna@medium”."),
        setting("aiAccounts", "aiEngineMode", "Pay for Claude with",
                .choice([SettingOption("auto", "Subscription, else API key"), SettingOption("subscription", "Subscription"),
                         SettingOption("apiKey", "API key")]),
                note: "Under Advanced. Claude: the subscription through Claude Code, or the API key; “Subscription, else API key” takes the subscription when it is signed in."),
        setting("aiAccounts", "claudeSubscription", "Claude subscription", .text(maxLength: 0), access: .paneOnly(Why.signIn), preference: .some(nil)),
        setting("aiAccounts", "claudeAPIKey", "Claude API key", .text(maxLength: 0), access: .paneOnly(Why.secret), preference: .some(nil), secret: true),
        setting("aiAccounts", "chatGPTSubscription", "ChatGPT subscription", .text(maxLength: 0), access: .paneOnly(Why.signIn), preference: .some(nil)),
        setting("aiAccounts", "openAIKey", "OpenAI API key", .text(maxLength: 0), access: .paneOnly(Why.secret), preference: .some(nil), secret: true),
        setting("aiAccounts", "typeSafeKey", "TypeSafe Jev key", .text(maxLength: 0), access: .paneOnly(Why.secret), preference: .some(nil), secret: true),

        // Catalog
        setting("catalog", "catalogOff", "Show in search", .list(item: "an entry of the Catalog, by its name", adds: true),
                note: "Per entry. The list holds the entries turned off: add one to take it out of the launcher's results (“?” still lists it; its prefix, alias and shortcut still work), remove it to show it again."),
        setting("catalog", "quicklinks", "Quicklinks", .list(item: "a name, a keyword and an address with {query}", adds: true),
                access: .tools([Tool.createQuicklink, Tool.updateQuicklink, Tool.deleteQuicklink]), preference: .some(nil), personal: true,
                note: "“g skilli” opens Google's results: {query} in the address takes what is typed after the keyword."),
        setting("catalog", "quicklinkReuseTab", "Reuse an open tab", .toggle,
                note: "A quicklink loads in a tab the default browser (Safari, Chrome, Brave, Edge, Vivaldi) already has on that site, replacing its page, instead of a new tab. macOS asks once to let skil.li control the browser."),
        setting("catalog", "launcherAliases", "Aliases", .list(item: "an alias (one word, 12 letters at most) and the item it opens", adds: true),
                access: .tools([Tool.setAlias, Tool.removeAlias]),
                note: "An alias then a space opens its item at once: “e ” the emoji, “gh skilli” a quicklink with its query."),
        setting("catalog", "trustedLinks", "Trusted Links", .list(item: "an entry skilli:// links run without asking", adds: false),
                access: .paneOnly(Why.rights + " Always in a link's card adds an entry; the pane removes it."), preference: .some(nil),
                note: "What asks first from a link (Lock Screen, a snippet, a skillie…) runs at once once trusted. Never Empty Trash, Restart, Shut Down, Log Out, Quit All Apps, Quit Other Apps, settings, nor pastes of the user's copies.")
    ]

    /// The `Preferences` properties the table covers.
    public static var preferences: Set<String> { Set(entries.compactMap(\.preference)) }

    // MARK: - Finding a setting

    /// Lowercased, accents and spaces around ignored, inner spaces single,
    /// quotes and a final period dropped.
    public static func folded(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for quote in ["“", "”", "\"", "'", "«", "»", "‘", "’"] where text.hasPrefix(quote) || text.hasSuffix(quote) {
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: quote))
        }
        if text.hasSuffix("."), !text.hasSuffix("..") { text.removeLast() }
        return text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The pane `name` names (its id or title), nil when none.
    public static func pane(_ name: String, title: (String) -> String) -> String? {
        let wanted = folded(name)
        return panes.first { folded($0) == wanted || folded(title($0)) == wanted }
    }

    /// The entry `setting` names (its key or its name), in `pane` (its id
    /// or title) or, without one, in the only pane that has it.
    public static func entry(pane name: String?, setting: String, title: (String) -> String) throws -> SettingEntry {
        let wanted = folded(setting)
        func matches(_ entry: SettingEntry) -> Bool { folded(entry.key) == wanted || folded(entry.name) == wanted }
        let paneName = name.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        guard let paneName else {
            let found = entries.filter(matches)
            if found.count == 1 { return found[0] }
            if found.isEmpty { throw Problem("No setting is named “\(setting)”. get_settings lists them, pane by pane.") }
            throw Problem("“\(setting)” is in several panes: \(found.map { title($0.pane) }.joined(separator: ", ")). Say which pane.")
        }
        guard let pane = pane(paneName, title: title) else {
            throw Problem("No pane is named “\(paneName)”. Panes: \(panes.map(title).joined(separator: ", ")).")
        }
        let inPane = entries.filter { $0.pane == pane }
        if let entry = inPane.first(where: matches) { return entry }
        if inPane.isEmpty { throw Problem("\(title(pane)) has no setting tools can change.") }
        throw Problem("\(title(pane)) has no setting “\(setting)”. Its settings: \(inPane.map(\.name).joined(separator: ", ")).")
    }

    // MARK: - Values

    /// The choices a setting offers by itself (`choiceOnThisMac`: none here).
    public static func options(of entry: SettingEntry) -> [SettingOption] {
        switch entry.kind {
        case .choice(let options), .choiceOrNumber(let options, _, _): options
        default: []
        }
    }

    /// The option `input` names: its value or its title; else the only one
    /// whose title or value holds those words.
    public static func match(_ input: String, among options: [SettingOption]) -> SettingOption? {
        let wanted = folded(input)
        guard !wanted.isEmpty else { return options.first { $0.value.isEmpty } }
        if let exact = options.first(where: { folded($0.value) == wanted || folded($0.title) == wanted }) { return exact }
        let words = wanted.split(separator: " ")
        let close = options.filter { option in
            let title = folded(option.title).split(separator: " ")
            return words.allSatisfy { word in title.contains { $0.hasPrefix(word) } } || folded(option.value).hasPrefix(wanted)
        }
        return close.count == 1 ? close[0] : nil
    }

    /// "off (Only when I ask), daily (Every day)…", the first `limit`.
    public static func valid(_ options: [SettingOption], limit: Int = 40) -> String {
        let shown = options.prefix(limit).map { option in
            option.value.isEmpty ? "“” (\(option.title))" : option.value == option.title ? option.value : "\(option.value) (\(option.title))"
        }
        return shown.joined(separator: ", ") + (options.count > limit ? ", +\(options.count - limit) more" : "")
    }

    private static let yes: Set<String> = ["true", "on", "yes", "1", "enabled", "enable", "oui", "active", "activé", "activer"]
    private static let no: Set<String> = ["false", "off", "no", "0", "disabled", "disable", "non", "desactive", "désactivé", "desactiver"]

    /// What `input` sets `entry` to, checked against the values the pane
    /// offers (`options` for the choices this Mac has); `isFolder` says
    /// whether a path is a folder here.
    public static func parse(_ input: String, for entry: SettingEntry, options: [SettingOption] = [],
                             paneTitle: String, isFolder: (String) -> Bool = { _ in true }) throws -> SettingValue {
        let label = "\(paneTitle) → \(entry.name)"
        switch entry.kind {
        case .toggle:
            let word = folded(input)
            if yes.contains(word) { return .bool(true) }
            if no.contains(word) { return .bool(false) }
            throw Problem("\(label) is on or off: true or false.")
        case .choice(let fixed):
            guard let option = match(input, among: fixed) else {
                throw Problem("“\(input)” is not a value of \(label). Valid: \(valid(fixed)).")
            }
            return .text(option.value)
        case .choiceOnThisMac:
            guard let option = match(input, among: options) else {
                throw Problem(options.isEmpty ? "\(label) has nothing to choose from on this Mac now."
                                              : "“\(input)” is not a value of \(label). Valid: \(valid(options)).")
            }
            return .text(option.value)
        case .choiceOrNumber(let fixed, let range, let unit):
            if let option = match(input, among: fixed) { return .text(option.value) }
            var words = folded(input).replacingOccurrences(of: "\(unit):", with: "").split(separator: " ").map(String.init)
            if words.count == 2, [unit, String(unit.dropLast()), "jours", "jour", "j"].contains(words[1]) { words.removeLast() }
            guard words.count == 1, let number = Int(words[0]) else {
                throw Problem("“\(input)” is not a value of \(label). Valid: \(valid(fixed)), or a number of \(unit) from \(range.lowerBound) to \(range.upperBound).")
            }
            guard range.contains(number) else {
                throw Problem("\(label) takes from \(range.lowerBound) to \(range.upperBound) \(unit), or \(valid(fixed)).")
            }
            return .text("\(unit):\(number)")
        case .text(let maxLength):
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= maxLength else { throw Problem("\(label) takes \(maxLength) characters at most.") }
            return .text(text)
        case .folder(let empty):
            var path = input.trimmingCharacters(in: .whitespacesAndNewlines)
            for quote in ["\"", "'", "“", "”"] { path = path.trimmingCharacters(in: CharacterSet(charactersIn: quote)) }
            if path.isEmpty || ["default", "none", "reset"].contains(folded(path)) {
                guard empty != nil else { throw Problem("\(label) needs a folder: a path on this Mac, like ~/Documents/Backups.") }
                return .text("")
            }
            path = (path as NSString).expandingTildeInPath
            guard path.hasPrefix("/") else { throw Problem("\(label) takes a full path, like ~/Documents/Backups.") }
            path = (path as NSString).standardizingPath
            guard isFolder(path) else { throw Problem("No folder at “\(shownPath(path))”: \(label) takes a folder that exists on this Mac.") }
            return .text(path)
        case .reset:
            guard ["default", "reset", "middle", "center", "centre", "standard", "usual"].contains(folded(input)) else {
                throw Problem("\(label) only goes back to its default: value “default”.")
            }
            return .text("default")
        case .list:
            throw Problem("\(label) is a list: change “add” or “remove” with one item.")
        }
    }

    /// `path` with `~` for the home folder.
    public static func shownPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// A value in the pane's words: "On", "Every week", "~/Backups", "14 days".
    public static func shown(_ value: SettingValue, for entry: SettingEntry, options: [SettingOption] = []) -> String {
        switch (value, entry.kind) {
        case (.bool(let on), _):
            return on ? "On" : "Off"
        case (.text(let text), .choice(let fixed)):
            return fixed.first { $0.value == text }?.title ?? text
        case (.text(let text), .choiceOnThisMac):
            return options.first { $0.value == text }?.title ?? (text.isEmpty ? "Default" : text)
        case (.text(let text), .choiceOrNumber(let fixed, _, let unit)):
            if let option = fixed.first(where: { $0.value == text }) { return option.title }
            let number = text.replacingOccurrences(of: "\(unit):", with: "")
            return number == "1" ? "1 \(unit.dropLast())" : "\(number) \(unit)"
        case (.text(let text), .folder(let empty)):
            return text.isEmpty ? (empty ?? "None yet") : shownPath(text)
        case (.text(let text), .reset(let moved, let standard)):
            return text == "default" ? standard : moved
        case (.text(let text), .text):
            guard !text.isEmpty else { return "empty" }
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            let cut = line.count > 80 || line.count < text.count
            return "“\(line.prefix(80))\(cut ? "…" : "")”"
        case (.text(let text), _):
            return text
        case (.list(let items), _):
            return items.isEmpty ? "none" : items.joined(separator: ", ")
        }
    }

    /// What the card says: "Backup: How often → Every week".
    public static func change(_ entry: SettingEntry, paneTitle: String, to shown: String) -> String {
        "\(paneTitle): \(entry.name) → \(shown)"
    }

    /// What the card says for a list: "Clipboard: Never keep copies from + 1Password".
    public static func listChange(_ entry: SettingEntry, paneTitle: String, adding: Bool, item: String) -> String {
        "\(paneTitle): \(entry.name) \(adding ? "+" : "−") \(item)"
    }

    /// The type agents read in get_settings.
    public static func type(of entry: SettingEntry) -> String {
        switch entry.kind {
        case .toggle: "on/off"
        case .choice, .choiceOnThisMac: "choice"
        case .choiceOrNumber(_, _, let unit): "choice or a number of \(unit)"
        case .text: entry.secret ? "secret" : "text"
        case .folder: "folder"
        case .reset: "reset"
        case .list: "list"
        }
    }
}

extension MeetingAlert {
    /// "On time · Card", "5 min before · Card, screens dark".
    public var spoken: String { "\(Self.spoken(minutes)) · \(style.title)" }

    /// The alert a text names: "on time", "5 min before", "1 hour", "10
    /// screens dark", "5 min before · Card, screens dark". Nil when its
    /// time is not one of `choices`.
    public static func parse(_ text: String) -> MeetingAlert? {
        let words = SettingsTable.folded(text)
        let dark = ["dark", "noir", "sombre", "screens", "ecrans"].contains { words.contains($0) }
        let minutes: Int?
        if words.contains("on time") || words.contains("a l'heure") || words.hasPrefix("0") || words.contains("when it starts") {
            minutes = 0
        } else if let number = words.split(whereSeparator: { !$0.isNumber }).first.flatMap({ Int($0) }) {
            let hours = words.contains("hour") || words.contains("heure") || words.range(of: #"\d\s*h\b"#, options: .regularExpression) != nil
            minutes = hours ? number * 60 : number
        } else if words.contains("hour") || words.contains("heure") {
            minutes = 60
        } else {
            minutes = nil
        }
        guard let minutes, choices.contains(minutes) else { return nil }
        return MeetingAlert(minutes: minutes, style: dark ? .dark : .card)
    }
}

extension Chord {
    /// Keys as people write them: "hyper+y", "✦Y", "⌘⇧K", "✦K then Y",
    /// "✦ K › U", "caps lock+y".
    public static func sequence(said text: String) throws -> [Chord] {
        var spec = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" then ", " puis ", "›", " > "] {
            spec = spec.replacingOccurrences(of: separator, with: " ", options: .caseInsensitive)
        }
        for (said, word) in [("caps lock", "hyper"), ("capslock", "hyper"), ("super", "hyper")] {
            spec = spec.replacingOccurrences(of: said, with: word, options: .caseInsensitive)
        }
        // A modifier glyph then a space or a key: "✦ K", "⌘K" → "✦+K", "⌘+K".
        var joined = ""
        for character in spec {
            if let last = joined.last, "✦⌘⌃⌥⇧".contains(last), character != "+" {
                if character == " " { continue }
                joined.append("+")
            }
            joined.append(character)
        }
        // "hyper + k": spaces around the plus.
        joined = joined.replacingOccurrences(of: #"\s*\+\s*"#, with: "+", options: .regularExpression)
        return try sequence(joined)
    }
}
