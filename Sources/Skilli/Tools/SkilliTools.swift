import AppKit
import ApplicationServices
import Carbon.HIToolbox
import EventKit
import SkilliCore

/// Families of skil.li tools a command can allow (`tools: [selection, apps]`).
enum ToolGroup: String, CaseIterable, Identifiable, Sendable {
    case selection
    case clipboard
    case apps
    case menus
    case commands
    case actions
    case reminders
    /// The user's calendars: events by day, the next meeting, free time.
    case calendar
    /// The user's contacts: found by anything known of them; a new mail.
    case contacts
    /// Messages in Slack or Discord, after the user confirms who.
    case messages
    /// The user's GitHub: pull requests by group, notifications.
    case github
    /// Mac commands: lock, sleep, dark mode, keep awake, Trash, restart.
    case system
    /// The user's own tools (webhooks), Settings → Tools.
    case personal
    /// The front window's buttons and fields, and keys.
    case screen
    /// skil.li's own settings: read them, change one after the user's OK.
    case settings
    /// The meeting recorder: the Record card, the recording on now.
    case recorder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: "Selection"
        case .clipboard: "Clipboard"
        case .apps: "Apps and Links"
        case .menus: "Menus"
        case .commands: "\(Brand.intelligence) Commands"
        case .actions: "skil.li Actions"
        case .reminders: "Reminders"
        case .calendar: "Calendar"
        case .contacts: "Contacts"
        case .messages: "Messages"
        case .github: "GitHub"
        case .system: "Mac Commands"
        case .personal: "Your Tools"
        case .screen: "Screen Controls"
        case .settings: "skil.li Settings"
        case .recorder: "Meeting Recorder"
        }
    }

    var detail: String {
        switch self {
        case .selection: "Read and change the selected text again between its steps. Without it, the command still gets your selection and its answer replaces it"
        case .clipboard: "Read what you copied and copy something for you"
        case .apps: "See the app in front, open apps and links"
        case .menus: "Find and choose items in the app's menus"
        case .commands: "Run your other commands on a text"
        case .actions: "CleanShot X, text case"
        case .reminders: "Read, add and change your reminders"
        case .calendar: "Read your calendars: meetings, a day, free time"
        case .contacts: "Find people by anything you know of them, write them a mail"
        case .messages: "Send in Slack or Discord, after you confirm who"
        case .github: "Your pull requests and notifications; merge, update a branch"
        case .system: "Lock, sleep, dark mode, Wi-Fi, Bluetooth, Trash, restart"
        case .personal: "Your webhooks, from Settings → Tools"
        case .screen: "Read the window in front, press its buttons, fill its fields, send keys"
        case .settings: "Read skil.li's settings; change one, an alias, a shortcut… each after your OK"
        case .recorder: "Open the Record card (you start it); pause, resume or stop the recording on now; list your recordings; a transcript, asked each time"
        }
    }

    var symbol: String {
        switch self {
        case .selection: "text.cursor"
        case .clipboard: "doc.on.clipboard"
        case .apps: "macwindow"
        case .menus: "filemenu.and.selection"
        case .commands: "wand.and.stars"
        case .actions: "bolt.fill"
        case .reminders: "checklist"
        case .calendar: "calendar"
        case .contacts: "person.crop.circle"
        case .messages: "bubble.left.and.text.bubble.right"
        case .github: "arrow.triangle.pull"
        case .system: "desktopcomputer"
        case .personal: "point.3.connected.trianglepath.dotted"
        case .screen: "cursorarrow.click.2"
        case .settings: "gearshape"
        case .recorder: "record.circle"
        }
    }
}

/// One skil.li tool as agents see it.
struct ToolDefinition: Sendable {
    struct Parameter: Sendable {
        let name: String
        let description: String
        var options: [String]? = nil
        var isArray = false
        var isRequired = true
    }

    let name: String
    /// For the approval card: "Replace the selection".
    let title: String
    let description: String
    /// nil: always there (talking to the user).
    let group: ToolGroup?
    let risk: ToolRisk
    var parameters: [Parameter] = []

    var inputSchema: [String: Any] {
        var properties: [String: Any] = [:]
        for parameter in parameters {
            var property: [String: Any] = ["description": parameter.description]
            if parameter.isArray {
                property["type"] = "array"
                property["items"] = ["type": "string"]
            } else {
                property["type"] = "string"
                if let options = parameter.options { property["enum"] = options }
            }
            properties[parameter.name] = property
        }
        return ["type": "object", "properties": properties, "required": parameters.filter(\.isRequired).map(\.name)]
    }

    var listing: [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": inputSchema,
            "annotations": ["readOnlyHint": risk == .read || risk == .none, "destructiveHint": risk == .changes, "title": title]
        ]
    }
}

/// An Act command in progress: which tools its agent may use, the
/// selection and app it started from.
@MainActor
final class AgentContext {
    let id = UUID().uuidString
    let title: String
    let groups: Set<ToolGroup>
    let read: SelectionService.Read?
    let targetPID: pid_t?
    /// Runs out of sight (an ask on a schedule): its questions and
    /// approvals take the card as an agent outside a command does.
    let background: Bool
    /// The user allowed a step on the screen in this run: its other steps
    /// there run without asking, except what may not be taken back
    /// (`SkilliTools.mayNotBeUndone`).
    var screenAllowed = false

    init(title: String, groups: Set<ToolGroup>, read: SelectionService.Read?, targetPID: pid_t?, background: Bool = false) {
        self.title = title
        self.groups = groups
        self.read = read
        self.targetPID = targetPID
        self.background = background
    }
}

/// What skil.li's MCP server offers, and the work behind each tool. Runs on
/// the main actor: Accessibility, the clipboard and the card live there.
@MainActor
final class SkilliTools {
    /// The longest Keep Awake an agent may ask for: a week, as typed in the
    /// launcher (`AwakeRequest`).
    static let longestAwakeMinutes = 7 * 24 * 60
    private let selection: SelectionService
    /// The front window's elements, for the screen tools.
    let ui = UIReader()
    /// Windows open now and saved layouts.
    var arranger: WindowArranger?
    /// Apps left out of every layout (Settings → Windows).
    var layoutIgnoredApps: () -> [String] = { [] }
    var timers: TimerCenter?
    /// The meeting recorder, made when a tool first needs it.
    var recorder: (() -> RecorderCenter?)?
    /// The editors' recent projects; the self-test records instead of opening.
    var projects: EditorProjects?
    var openProject: (EditorProject) -> Void = { EditorProjects.open($0, reveal: false) }
    /// Skillies.
    var scripts: ScriptLibrary?
    /// Where create_skill writes (Settings → Ask → Skills); the self-test's is scratch.
    var skillsFolder: URL?
    /// The browsers' histories; the self-test's are scratch.
    var historySource = BrowserHistory.Source()
    /// Homebrew (--dry-run in the self-test).
    var homebrew: Homebrew?
    /// Self-test hook: the user's decision keys for find_ui.
    var decisionKeysOverride: [DecisionProvider: String]?
    private let library: PromptLibrary
    private let ai: AIStore
    /// The user's reminders, for the Reminders tools.
    var reminders: ReminderBook?
    /// The user's GitHub (Settings → GitHub).
    var github: GitHubBook?
    /// skil.li actions (CleanShot, text case) run like a shortcut would.
    var performAction: ((SkilliAction) -> Void)?
    /// An app added (create_app_link): the launcher's rows follow.
    var appsChanged: (() -> Void)?
    /// Finds an installed app by name ("Notes", "Calculatrice").
    var findApp: ((String) -> URL?)?
    /// Installed apps whose name is close to a text, best first.
    var similarApps: ((String) -> [String])?
    /// Every installed app (the launcher's index).
    var installedApps: (() -> [(name: String, url: URL)])?
    /// A tool lacked a permission (Reminders).
    var onPermissionNeeded: ((Permission) -> Void)?
    var systemCommands: SystemCommands?
    /// The user's contacts, for search_contacts.
    var contacts: ContactBook?
    /// The user's calendars, for list_events.
    var calendar: CalendarBook?
    /// Opens a URL (a new mail): the self-test watches it instead.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The user's snippets, and typing one at the caret.
    var snippets: SnippetLibrary?
    var insertSnippet: ((Snippet) async -> Void)?
    /// "Do it here" toward a goal in the app `pid`, its steps in the card
    /// (`AIActionController.doItHere`); what it did, for the agent.
    var doItHere: ((_ goal: String, _ pid: pid_t, _ caller: String, _ run: AgentContext?) async -> AIActionController.ControlReport)?
    /// Asks the user in the card ("Send to “Thomas Martin” in Slack?").
    /// `alwaysMaySkip`: the user's Always for `tool` answers it; false when
    /// the ask belongs to what is run (a skillie's own "ask first").
    var confirm: ((_ title: String, _ detail: String, _ verb: String, _ tool: String, _ run: AgentContext?, _ alwaysMaySkip: Bool) async -> ToolApproval)?

    init(selection: SelectionService, library: PromptLibrary, ai: AIStore) {
        self.selection = selection
        self.library = library
        self.ai = ai
    }

    /// The tools that hand a recording's words to whoever calls them
    /// (docs/meeting-recorder.md, "Privacy and consent"): asked every time
    /// in the card, naming the recording; no Always, no right or mode makes
    /// them silent (`ToolSettings.asksEveryTime`).
    nonisolated static let recordingWords: Set<String> = ["get_transcript", "recording_followup"]

    nonisolated static let askUser = "ask_user"
    nonisolated static let approve = "approve"
    nonisolated static let doInApp = "do_in_app"

    /// run_action's ids, read each time: the linked apps' files can change.
    nonisolated static var actions: [String: SkilliAction] {
        var actions: [String: SkilliAction] = [
            "text.uppercase": .transformSelection(.uppercase),
            "text.lowercase": .transformSelection(.lowercase),
            "text.titlecase": .transformSelection(.capitalized)
        ]
        // "cleanshot.capture-area": each linked app's commands, by their id.
        for app in LinkedApp.all {
            for command in app.commands { actions[command.id] = .mac(.appLink(command, variant: nil)) }
        }
        return actions
    }

    /// What a linked app's command can be told more (run_action's
    /// `variant`): CleanShot's "copy", "pin", "autoscroll", a settings tab.
    nonisolated static var actionVariants: [String] {
        var seen = Set<String>()
        return LinkedApp.all.flatMap(\.commands).flatMap(\.variants).map(\.id).filter { seen.insert($0).inserted }
    }

    /// run_action as agents see it now: CleanShot X's commands, then those
    /// of the apps written in files that are on this Mac (`apps`, as last
    /// read by default), each "id (Title)".
    nonisolated static func runActionDefinition(apps: [LinkedApp]? = nil) -> ToolDefinition {
        let others = (apps ?? LinkedApps.installed().map(\.app)).filter { $0.id != LinkedApp.cleanShot.id }.map { app in
            "\(app.name): " + app.commands.map { "\($0.id) (\($0.title)" + ($0.variants.isEmpty ? "" : "; variants \($0.variants.map(\.id).joined(separator: ", "))") + ")" }
                .joined(separator: ", ")
        }
        return ToolDefinition(name: "run_action", title: "Run a skil.li action",
                              description: "Runs a skil.li action: CleanShot X's captures (an area, the front window, the screen, scrolling), recordings, text recognition, annotating or pinning an image (the latest screenshot, the one selected in Finder, or a file), Quick Access, desktop icons, its history; or changing the case of the selection. A CleanShot command takes a variant: what happens to a capture (copy, save, annotate, pin, upload: asked first, it leaves the Mac), scrolling's start or autoscroll, text with linebreaks or nolinebreaks, a settings tab. Annotating (cleanshot.open-annotate), pinning (cleanshot.pin) and text recognition (cleanshot.capture-text) take a PNG or JPEG file, Quick Access (cleanshot.quick-access) a PNG, JPEG or MP4."
                                + (others.isEmpty ? "" : " The other apps skil.li drives through their links: " + others.joined(separator: ". ") + "."),
                              group: .actions, risk: .changes,
                              parameters: [.init(name: "id", description: "The action.", options: actions.keys.sorted()),
                                           .init(name: "variant", description: "What the app's command does more; leave out for its plain run.",
                                                 options: actionVariants, isRequired: false),
                                           .init(name: "file", description: "The file's full path, for the commands that open one; instead of the Finder selection, the latest screenshot or CleanShot asking.",
                                                 isRequired: false)])
    }

    nonisolated static let definitions: [ToolDefinition] = [
        ToolDefinition(name: "get_selection", title: "Read the selection",
                       description: "The text the user selected in their app (when the command started). Empty if nothing is selected.",
                       group: .selection, risk: .read),
        ToolDefinition(name: "replace_selection", title: "Replace the selection",
                       description: "Replaces the user's selected text with new text (inserts it at the cursor if nothing is selected). The app's own Undo reverts it.",
                       group: .selection, risk: .changes,
                       parameters: [.init(name: "text", description: "The new text.")]),
        ToolDefinition(name: "get_clipboard", title: "Read the clipboard",
                       description: "The text on the clipboard.", group: .clipboard, risk: .read),
        ToolDefinition(name: "set_clipboard", title: "Copy to the clipboard",
                       description: "Puts text on the clipboard, replacing what is there.", group: .clipboard, risk: .changes,
                       parameters: [.init(name: "text", description: "The text to copy.")]),
        ToolDefinition(name: "get_frontmost_app", title: "See the app in front",
                       description: "The app the user is working in: name, bundle id and window title (JSON).",
                       group: .apps, risk: .read),
        ToolDefinition(name: "list_apps", title: "List your apps",
                       description: "The apps installed on this Mac, one per line with what kind they are. Use it before open_app when the user describes an app instead of naming it.",
                       group: .apps, risk: .read),
        ToolDefinition(name: "open_app", title: "Open an app",
                       description: "Opens or brings forward an installed app by name (\"Notes\") or bundle id.",
                       group: .apps, risk: .harmless,
                       parameters: [.init(name: "name", description: "App name or bundle id.")]),
        ToolDefinition(name: "open_url", title: "Open a link",
                       description: "Opens a URL in the default app: web pages, mailto:, or app links such as cleanshot://capture-area.",
                       group: .apps, risk: .harmless,
                       parameters: [.init(name: "url", description: "The URL to open.")]),
        ToolDefinition(name: "search_menus", title: "Search the app's menus",
                       description: "Menu items of the app in front whose path contains the query, as \"Menu > Item\" lines with their shortcut. Use an empty query to list everything (long).",
                       group: .menus, risk: .read,
                       parameters: [.init(name: "query", description: "Words to look for, e.g. \"export\".", isRequired: false)]),
        ToolDefinition(name: "press_menu", title: "Choose a menu item",
                       description: "Chooses a menu item of the app in front, by the path search_menus gave (\"File > Export as PDF…\").",
                       group: .menus, risk: .changes,
                       parameters: [.init(name: "path", description: "\"Menu > Item\" as search_menus lists it.")]),
        ToolDefinition(name: "list_commands", title: "List \(Brand.intelligence) Commands",
                       description: "The user's \(Brand.intelligence) Commands that work on text: id, name, first line of the prompt.",
                       group: .commands, risk: .read),
        ToolDefinition(name: "run_command", title: "Run an \(Brand.intelligence) Command",
                       description: "Runs one of the user's \(Brand.intelligence) Commands on a text and returns its answer (nothing is pasted). Questions take their defaults.",
                       group: .commands, risk: .harmless,
                       parameters: [.init(name: "id", description: "Command id from list_commands."),
                                    .init(name: "text", description: "The text to work on.")]),
        // Read again where agents get it (`live`): the apps' files change.
        runActionDefinition(apps: []),
        ToolDefinition(name: "update_app", title: "Update an app",
                       description: "Updates an app the right way: its own “Check for Updates…” menu item, else the App Store's Updates page, else Homebrew (brew upgrade --cask). Without a name: the app in front.",
                       group: .apps, risk: .changes,
                       parameters: [.init(name: "name", description: "The app; empty for the one in front.", isRequired: false)]),
        ToolDefinition(name: "send_message", title: "Send a message",
                       description: "Sends a message in Slack or Discord. skil.li opens the conversation with the person or channel, then the user confirms the conversation it found before it is sent. Write the text as the user would say it to them (\"dis à Thomas que j'arrive\" → \"J'arrive\").",
                       group: .messages, risk: .harmless,
                       parameters: [.init(name: "app", description: "Where to send it.", options: ["Slack", "Discord"]),
                                    .init(name: "to", description: "The person or channel, as the user named them."),
                                    .init(name: "text", description: "The message itself.")]),
        ToolDefinition(name: "list_snippets", title: "List snippets",
                       description: "The user's snippets: name, keyword and the start of the text.",
                       group: .personal, risk: .read, parameters: []),
        ToolDefinition(name: "insert_snippet", title: "Insert a snippet",
                       description: "Types one of the user's snippets (by name) at the caret of the app in front, with its date, clipboard and cursor filled.",
                       group: .personal, risk: .changes,
                       parameters: [.init(name: "name", description: "The snippet's name, as list_snippets gives it.")]),
        ToolDefinition(name: "list_ui", title: "Read the window in front",
                       description: "The buttons, checkboxes, fields, links and short texts of the app's front window, each with an id (e12) to use with press_ui and set_ui_value. Read again after anything changes the window.",
                       group: .screen, risk: .read, parameters: []),
        ToolDefinition(name: "find_ui", title: "Find an element",
                       description: "Finds the element of the front window that matches a description (“the box to stay signed in”, “Send”), and returns its id. Faster than reading everything.",
                       group: .screen, risk: .read,
                       parameters: [.init(name: "description", description: "What the element is or does, in the user's words.")]),
        ToolDefinition(name: "press_ui", title: "Press an element",
                       description: "Presses a button, ticks a checkbox or radio, follows a link, or focuses a field, by its id from list_ui or find_ui.",
                       group: .screen, risk: .changes,
                       parameters: [.init(name: "id", description: "The element's id, e.g. e12.")]),
        ToolDefinition(name: "set_ui_value", title: "Fill a field",
                       description: "Puts text in a field by its id (never a password field). Falls back to typing it when the app does not take the value directly.",
                       group: .screen, risk: .changes,
                       parameters: [.init(name: "id", description: "The field's id, e.g. e7."), .init(name: "text", description: "What goes in the field.")]),
        ToolDefinition(name: "press_keys", title: "Press keys",
                       description: "Sends a key or shortcut to the app in front: “cmd+s”, “return”, “tab”, “cmd+shift+n”, “escape”, arrows (left, right, up, down).",
                       group: .screen, risk: .changes,
                       parameters: [.init(name: "keys", description: "One key or shortcut, e.g. cmd+s.")]),
        ToolDefinition(name: doInApp, title: "Do it in an app",
                       description: "Hands a whole goal to skil.li's “do it here” and waits until it is done: it reads the app's window (Accessibility, its menus, the words and the picture on screen), then clicks, types and presses keys step by step, 12 at most, planning moves that need thinking. It asks the user before anything that sends, deletes, pays or overwrites, and never types a password. Prefer it to list_ui and press_ui for anything of more than one step in an app (export, fill a form, play a move); press_menu for a single menu item. Write the goal as the user would ask it, in their language, the exact text to type in quotes (« … »). Returns the steps done and whether it finished.",
                       group: .screen, risk: .changes,
                       parameters: [.init(name: "goal", description: "What to do there, as the user would ask it: “exporte en PDF dans mes documents”."),
                                    .init(name: "app", description: "The app to do it in, by name (“TextEdit”); it is brought forward, opened if needed. Empty: the app the user was in. Name it when you run outside skil.li (from a terminal).",
                                          isRequired: false)]),
        ToolDefinition(name: "start_timer", title: "Start a timer",
                       description: "Starts a timer that counts down in the menu bar and rings at the end.",
                       group: .actions, risk: .changes,
                       parameters: [.init(name: "duration", description: "How long: 10 min, 1h30, 90s, 1:30."),
                                    .init(name: "label", description: "What it is for, or empty.")]),
        ToolDefinition(name: "list_timers", title: "List timers",
                       description: "The running timers and what is left.",
                       group: .actions, risk: .read, parameters: []),
        ToolDefinition(name: "cancel_timer", title: "Cancel a timer",
                       description: "Cancels a running timer by its label (or the only one).",
                       group: .actions, risk: .changes,
                       parameters: [.init(name: "label", description: "Its label, or empty for the only one.")]),
        ToolDefinition(name: "record_meeting", title: "Record a meeting",
                       description: "Opens skil.li's Record card: the user's microphone and the Mac's sound as two tracks, transcribed on this Mac at the end (the webcam and the meeting's window too when the user turns them on). Nothing is recorded until the user presses Return in the card; this waits for it and says whether the recording started. Recording others needs their consent: never start one the user did not ask for.",
                       group: .recorder, risk: .harmless,
                       parameters: [.init(name: "title", description: "The recording's name, as the user said it (“Weekly sync”); empty: “Meeting 14:30”.", isRequired: false)]),
        ToolDefinition(name: "import_recording", title: "Import a recording",
                       description: "Makes a recording of a sound or video file (a voice memo, a call app's own recording): its sound copied into skil.li's recordings, transcribed on this Mac, the voices told apart; the file itself stays where it is. Returns the recording's folder once its sound is copied; the transcript follows (recording_status says when).",
                       group: .recorder, risk: .changes,
                       parameters: [.init(name: "path", description: "The file's full path (~ allowed).")]),
        ToolDefinition(name: "recording_status", title: "See the recording",
                       description: "Whether a meeting is being recorded now (its name, how long, paused or not, its folder), or its transcript made.",
                       group: .recorder, risk: .read, parameters: []),
        ToolDefinition(name: "pause_recording", title: "Pause the recording",
                       description: "Pauses the recording on now: nothing is written until it resumes.",
                       group: .recorder, risk: .changes, parameters: []),
        ToolDefinition(name: "resume_recording", title: "Resume the recording",
                       description: "Resumes the recording paused now.",
                       group: .recorder, risk: .changes, parameters: []),
        ToolDefinition(name: "stop_recording", title: "Stop the recording",
                       description: "Stops the recording on now; its transcript is then made on this Mac and its window opens. Says its folder (me.m4a, them.m4a, webcam.mp4 and screen.mp4 when on, slides.json, then transcript.md).",
                       group: .recorder, risk: .changes, parameters: []),
        ToolDefinition(name: "set_recording_source", title: "Turn a recording's source on or off",
                       description: "While the Record card is open or a meeting is recorded: turns the microphone, the Mac's sound, the webcam or the screen (the meeting's window) on or off from now on. Turned off, a track keeps its time (silence, a black picture).",
                       group: .recorder, risk: .changes,
                       parameters: [.init(name: "source", description: "Which one.", options: ["microphone", "mac_sound", "webcam", "screen"]),
                                    .init(name: "on", description: "true to turn it on, false off.", options: ["true", "false"])]),
        ToolDefinition(name: "list_recordings", title: "List the recordings",
                       description: "The meetings recorded or imported in skil.li, newest first: each its id (the folder's name), title, date, length, state, and whether it has a summary and chapters. No words: get_transcript gives a transcript, asked to the user each time.",
                       group: .recorder, risk: .read, parameters: []),
        ToolDefinition(name: "get_transcript", title: "Give a recording's transcript",
                       description: "One recording's transcript, as transcript.md has it (its title, when, each line with its speaker and time, its chapters). The user is asked every time, the recording named; never ask for one they did not want read.",
                       group: .recorder, risk: .read,
                       parameters: [.init(name: "recording", description: "Its id from list_recordings, or its title (the newest of that title); empty: the newest recording.", isRequired: false)]),
        ToolDefinition(name: "recording_followup", title: "Follow up a recording with your SI",
                       description: "Does what the recording's window does in ⌘K, with the user's own SI (Settings → SI Accounts) reading its transcript: summary (written to summary.md, returned), chapters (written, returned), action_items (each added to Reminders, returned), recap_mail (a new mail to the attendees opens in the user's mail app with the summary; the user sends it), ask (answers `question` from the transcript). The user is asked every time, the recording named.",
                       group: .recorder, risk: .changes,
                       parameters: [.init(name: "action", description: "What to do.", options: MeetingFollowUp.Action.allCases.map(\.rawValue)),
                                    .init(name: "recording", description: "Its id from list_recordings, or its title; empty: the newest recording.", isRequired: false),
                                    .init(name: "question", description: "For ask: the question, as the user said it.", isRequired: false)]),
        ToolDefinition(name: "rename_recording", title: "Rename a recording",
                       description: "Renames one recording, as Rename… in its window does: its title, its folder by the same rules (its date kept), transcript.md's heading. Not while it records or its transcript is made. Returns its new id.",
                       group: .recorder, risk: .changes,
                       parameters: [.init(name: "recording", description: "Its id from list_recordings, or its title (the newest of that title)."),
                                    .init(name: "title", description: "Its new title, up to 120 characters.")]),
        ToolDefinition(name: "list_tabs", title: "List browser tabs",
                       description: "The tabs open in Safari, Chrome, Arc, Brave, Edge and others: browser and title.",
                       group: .apps, risk: .read, parameters: []),
        ToolDefinition(name: "focus_tab", title: "Go to a browser tab",
                       description: "Brings the browser tab whose title matches to the front.",
                       group: .apps, risk: .changes,
                       parameters: [.init(name: "title", description: "Words of its title, as list_tabs gives it.")]),
        ToolDefinition(name: "brew_search", title: "Search Homebrew",
                       description: "Homebrew formulae and casks whose name fits, with what they are and whether they are installed or have an update. Empty: the installed ones.",
                       group: .system, risk: .read,
                       parameters: [.init(name: "query", description: "A name or part of it: ffmpeg, firefox.", isRequired: false)]),
        ToolDefinition(name: "brew_install", title: "Install with Homebrew",
                       description: "Installs a Homebrew formula or cask by its exact name (from brew_search).",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "name", description: "Its exact name."),
                                    .init(name: "cask", description: "true for a cask (an app).", options: ["false", "true"], isRequired: false)]),
        ToolDefinition(name: "brew_upgrade", title: "Upgrade with Homebrew",
                       description: "Upgrades one Homebrew package by its name, or every outdated one without a name.",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "name", description: "Its exact name; empty for all.", isRequired: false)]),
        ToolDefinition(name: "search_history", title: "Search browser history",
                       description: "Pages the user visited in Safari (once Full Disk Access is on), Chrome, Arc, Brave, Edge, Firefox or Zen whose title or address holds every word, most recent first: title, address, browser, when.",
                       group: .apps, risk: .read,
                       parameters: [.init(name: "query", description: "Words of the page's title or address; empty for the last pages.", isRequired: false)]),
        ToolDefinition(name: "list_projects", title: "List recent projects",
                       description: "Folders recently opened in Cursor, VS Code, Windsurf, Zed, Sublime Text or JetBrains IDEs: name, editor and path, most recent first.",
                       group: .apps, risk: .read, parameters: []),
        ToolDefinition(name: "open_project", title: "Open a project",
                       description: "Opens a recent project again in its editor (or in the editor named).",
                       group: .apps, risk: .changes,
                       parameters: [.init(name: "name", description: "Its name or path, as list_projects gives them."),
                                    .init(name: "editor", description: "Cursor, Zed… when it was opened in several.", isRequired: false)]),
        ToolDefinition(name: "list_skillies", title: "List skillies",
                       description: "The user's skillies, skil.li's own commands (scripts): title, package, what it does and its arguments.",
                       group: .actions, risk: .read, parameters: []),
        ToolDefinition(name: "run_skillie", title: "Run a skillie",
                       description: "Runs one of the user's skillies by its title, with its arguments in order; returns what it printed.",
                       group: .actions, risk: .changes,
                       parameters: [.init(name: "title", description: "Its title, as list_skillies gives it."),
                                    .init(name: "arguments", description: "Its arguments' values, in order.", isArray: true, isRequired: false)]),
        ToolDefinition(name: "list_shortcuts", title: "List shortcuts",
                       description: "The shortcuts the user made in Apple's Shortcuts app, one name per line. Through them you reach what any app lets Shortcuts do.",
                       group: .actions, risk: .read, parameters: []),
        ToolDefinition(name: "run_shortcut", title: "Run a shortcut",
                       description: "Runs one of the user's shortcuts (Apple's Shortcuts app) by its name, with a text as its input if it takes one (or the user's selected text); returns the text it gave back.",
                       group: .actions, risk: .changes,
                       parameters: [.init(name: "name", description: "Its name, as list_shortcuts gives it."),
                                    .init(name: "input", description: "The text it works on.", isRequired: false),
                                    .init(name: "selection", description: "true: the text selected in the user's app is its input (instead of input).",
                                          options: ["true", "false"], isRequired: false)]),
        ToolDefinition(name: "create_skillie", title: "Create a skillie",
                       description: "Writes a new skillie: a script the user then finds in skil.li's launcher by its title, Ask can run and you can run with run_skillie. Give the code without a shebang; it receives its arguments as $1, $2… (argv). To act in apps, it opens one skil.li link a step, done in order, each asked first: open \"skilli://do?app=TextEdit&goal=exporte%20en%20PDF%20dans%20mes%20documents\" (the goal as the user would ask it, percent-encoded; app optional). When what follows depends on whether a step worked, wait for it instead: \"$SKILLI_CLI\" call do_in_app app=TextEdit goal=\"exporte en PDF dans mes documents\" exits 0 when done, 1 otherwise, its first line saying how it ended (asked in the card like any agent's call). Keep it small and safe; it runs on the user's Mac.",
                       group: .actions, risk: .changes,
                       parameters: [.init(name: "title", description: "Short, as the user would type it: “Flush DNS”."),
                                    .init(name: "description", description: "What it does, one sentence.", isRequired: false),
                                    .init(name: "language", description: "What runs it.", options: ScriptCommand.Language.allCases.map(\.rawValue)),
                                    .init(name: "code", description: "The script's code."),
                                    .init(name: "mode", description: "silent: a short line; compact: the last line; fullOutput: all of it.",
                                          options: ["compact", "silent", "fullOutput"], isRequired: false),
                                    .init(name: "arguments", description: "Its text arguments' placeholders, in order (3 at most).", isArray: true, isRequired: false),
                                    .init(name: "needs_confirmation", description: "true when it changes or deletes things: skil.li asks first.",
                                          options: ["false", "true"], isRequired: false)]),
        ToolDefinition(name: "create_app_link", title: "Add an app's links",
                       description: "Adds an app skil.li drives through the links it documents itself (its URL scheme), as it drives CleanShot X: each command becomes a launcher row, a key, an Ask answer and a run_action id (\"<id>.<command id>\"). Only links the app's own documentation gives (pass its address), and only ones that work without the user's own ids (a team, channel or meeting number). The app must be on this Mac and open that scheme. Each command: {\"id\": \"new-window\" (lowercase, hyphens), \"path\": what follows scheme:// (\"action/new_window\"; one starting with / gives scheme:/…), \"title\": \"New Warp Window\", \"description\": one line, no period, \"words\": other words people type, in English and French, \"symbol\": an SF Symbol name, \"query\": [{\"name\": …, \"value\": …}] its fixed parameters in order, \"variants\": [{\"id\", \"title\", \"label\", \"query\"}] the same command saying more (⌘K lists them), \"asksFirst\": true when it sends, deletes, pays or calls someone (asked every time from links, Ask and agents), \"group\": its heading in Settings}. skil.li shows the user the whole app before adding it.",
                       group: .actions, risk: .changes,
                       parameters: [.init(name: "app", description: "The app as it is installed (list_apps): skil.li reads its bundle id."),
                                    .init(name: "scheme", description: "The URL scheme it documents, without “://”: “warp”."),
                                    .init(name: "documentation", description: "The https address of the app's own page that documents these links."),
                                    .init(name: "commands", description: "The commands, as a JSON array of objects (see the description)."),
                                    .init(name: "id", description: "Short, lowercase, hyphens: what its commands' ids start with. Default: from its name.", isRequired: false),
                                    .init(name: "minimum_version", description: "The oldest version of the app its links work on (“5.0”), when its documentation says.", isRequired: false),
                                    .init(name: "note", description: "What the app needs first for its links to work, one line, in the user's words.", isRequired: false)]),
        ToolDefinition(name: "create_skill", title: "Write a skill",
                       description: "Writes a skill for Ask's agent in the user's skills folder (~/Library/Application Support/skil.li/skills/<name>/SKILL.md): when to use it, then how the user wants that job done. Ask's agent then uses it when a request fits. Instructions only: it has no shell or files.",
                       group: .actions, risk: .changes,
                       parameters: [.init(name: "name", description: "Lowercase words joined by hyphens: weekly-report."),
                                    .init(name: "description", description: "When to use it, one sentence: “Use when the user asks for their weekly report.”"),
                                    .init(name: "instructions", description: "How, in Markdown: the steps, the format, what to leave out.")]),
        ToolDefinition(name: "list_windows", title: "List open windows",
                       description: "Every open window: app and title, and the saved window layouts.",
                       group: .apps, risk: .read, parameters: []),
        ToolDefinition(name: "focus_window", title: "Bring a window forward",
                       description: "Brings the window whose app or title matches to the front.",
                       group: .apps, risk: .harmless,
                       parameters: [.init(name: "window", description: "Its app or title, as list_windows gives them.")]),
        ToolDefinition(name: "save_window_layout", title: "Save the window layout",
                       description: "Saves where every window is now, under a name (the same name replaces it).",
                       group: .apps, risk: .changes,
                       parameters: [.init(name: "name", description: "The layout's name, e.g. Coding.")]),
        ToolDefinition(name: "apply_window_layout", title: "Put a window layout back",
                       description: "Puts every window of a saved layout back in its place, opening its apps if needed.",
                       group: .apps, risk: .changes,
                       parameters: [.init(name: "name", description: "The layout's name, as list_windows gives it.")]),
        ToolDefinition(name: "keep_awake", title: "Keep the Mac awake",
                       description: "Keeps the Mac and its display awake for some minutes, until a time of day, some minutes longer than now set, or until turned off; or turns Keep Awake off.",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "minutes", description: "How many minutes, or empty.", isRequired: false),
                                    .init(name: "more", description: "Minutes added to the time left (60: one hour longer), or empty.", isRequired: false),
                                    .init(name: "until", description: "A time of day, 24-hour HH:MM, or empty.", isRequired: false),
                                    .init(name: "sleep", description: "true to turn Keep Awake off: the Mac sleeps as usual.", options: ["false", "true"], isRequired: false)]),
        ToolDefinition(name: "set_volume", title: "Set the volume",
                       description: "Sets the Mac's output volume, 0 to 100.",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "percent", description: "0 to 100.")]),
        ToolDefinition(name: "list_audio_devices", title: "List sound devices",
                       description: "The sound outputs (speakers, headphones, AirPods, displays) and microphones connected, and which ones macOS uses now.",
                       group: .system, risk: .read, parameters: []),
        ToolDefinition(name: "set_audio_device", title: "Switch the sound device",
                       description: "Makes a sound output or microphone the one macOS uses, by its name or kind (\"AirPods\", \"speakers\", \"display\").",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "device", description: "Its name, as list_audio_devices gives it, or its kind."),
                                    .init(name: "kind", description: "output (default) or input.", options: ["output", "input"], isRequired: false)]),
        ToolDefinition(name: "list_bluetooth_devices", title: "List Bluetooth devices",
                       description: "The Bluetooth devices paired with this Mac (AirPods, keyboards, speakers…), their kind, and whether each is connected now.",
                       group: .system, risk: .read, parameters: []),
        ToolDefinition(name: "connect_bluetooth_device", title: "Connect a Bluetooth device",
                       description: "Connects or disconnects a Bluetooth device paired with this Mac, by its name or kind (\"AirPods\", \"keyboard\"). Turning Bluetooth itself on or off is not possible.",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "device", description: "Its name, as list_bluetooth_devices gives it, or its kind."),
                                    .init(name: "action", description: "connect (default) or disconnect.", options: ["connect", "disconnect"], isRequired: false)]),
        ToolDefinition(name: "system_info", title: "Read the Mac's state",
                       description: "Battery, free disk space, memory, load, Wi-Fi, IP address, uptime and macOS version.",
                       group: .system, risk: .read, parameters: []),
        ToolDefinition(name: "run_mac_command", title: "Run a Mac command",
                       description: "Runs a Mac command, or puts the front window somewhere (window.leftHalf, window.maximize, window.nextDisplay…). Emptying the Trash, restarting, shutting down and logging out are confirmed by the user first.",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "command", description: "The command.", options: MacAction.all.map(\.rawValue))]),
        ToolDefinition(name: "list_processes", title: "List running processes",
                       description: "Running processes, busiest first: pid, name, CPU and memory. With a port, what listens on it.",
                       group: .system, risk: .read,
                       parameters: [.init(name: "query", description: "A name to filter by, or a port number.", isRequired: false)]),
        ToolDefinition(name: "quit_process", title: "Quit a process",
                       description: "Quits a process by pid (apps get to save). force: true kills it at once.",
                       group: .system, risk: .changes,
                       parameters: [.init(name: "pid", description: "From list_processes."),
                                    .init(name: "force", description: "true to force quit.", options: ["false", "true"], isRequired: false)]),
        ToolDefinition(name: "list_reminders", title: "Read your reminders",
                       description: "Lists the user's reminders (every list in the Reminders app): not done by default, earliest due first, with id, list, due, priority, notes and link. Filter by list, words, or a due date before which they are due.",
                       group: .reminders, risk: .read,
                       parameters: [.init(name: "list", description: "A list's name.", isRequired: false),
                                    .init(name: "query", description: "Words in the title or notes.", isRequired: false),
                                    .init(name: "due_before", description: "ISO 8601: only those due before (\"2026-10-13\" for today and overdue).", isRequired: false),
                                    .init(name: "completed", description: "true for those done this week instead.", options: ["false", "true"], isRequired: false)]),
        ToolDefinition(name: "create_reminder", title: "Add a reminder",
                       description: "Adds a reminder to the user's Reminders app. Give the due time in ISO 8601 in the user's time zone (2026-10-11T21:00), or a day alone (2026-10-12). Put the text it is about in notes.",
                       group: .reminders, risk: .harmless,
                       parameters: [.init(name: "title", description: "Short, in the user's language: \"Relire le contrat\"."),
                                    .init(name: "due", description: "When: 2026-10-11T21:00, or a day 2026-10-12.", isRequired: false),
                                    .init(name: "notes", description: "Details or the text it is about.", isRequired: false),
                                    .init(name: "list", description: "A list's name (list_reminders shows them). Default: the user's default list.", isRequired: false),
                                    .init(name: "priority", description: "Priority.", options: ["none", "low", "medium", "high"], isRequired: false),
                                    .init(name: "repeat", description: "How it repeats (needs a due date).", options: ["daily", "weekly", "weekdays", "monthly", "yearly"], isRequired: false),
                                    .init(name: "url", description: "A link it is about.", isRequired: false)]),
        ToolDefinition(name: "update_reminder", title: "Change a reminder",
                       description: "Changes a reminder found with list_reminders (by its id): done or not, title, due, list, priority, notes. Only what is given changes.",
                       group: .reminders, risk: .changes,
                       parameters: [.init(name: "id", description: "The reminder's id from list_reminders."),
                                    .init(name: "done", description: "true when done, false to do again.", options: ["true", "false"], isRequired: false),
                                    .init(name: "title", description: "A new title.", isRequired: false),
                                    .init(name: "due", description: "A new due date, ISO 8601; \"none\" for no date.", isRequired: false),
                                    .init(name: "list", description: "Another list's name.", isRequired: false),
                                    .init(name: "priority", description: "Priority.", options: ["none", "low", "medium", "high"], isRequired: false),
                                    .init(name: "notes", description: "New notes.", isRequired: false)]),
        ToolDefinition(name: "delete_reminder", title: "Delete a reminder",
                       description: "Deletes a reminder found with list_reminders, by its id. Only when the user asked for it; marking it done is usually what is meant.",
                       group: .reminders, risk: .changes,
                       parameters: [.init(name: "id", description: "The reminder's id from list_reminders.")]),
        ToolDefinition(name: "list_pull_requests", title: "Read your pull requests",
                       description: "The user's open GitHub pull requests and those waiting for their review, by group: ready (to merge), blocked (CI failed, conflict, changes requested, draft), waiting (for a review; \"your review\" when it is theirs to give), testing (checks running). Each: group, repository#number, title, why, link. Filter by group or words.",
                       group: .github, risk: .read,
                       parameters: [.init(name: "group", description: "Only this group.", options: ["ready", "blocked", "waiting", "testing"], isRequired: false),
                                    .init(name: "query", description: "Words in the title or the repository.", isRequired: false)]),
        ToolDefinition(name: "list_github_notifications", title: "Read your GitHub notifications",
                       description: "The user's unread GitHub notifications, newest first: id, why (review requested, mentioned, CI…), repository, title, link.",
                       group: .github, risk: .read,
                       parameters: [.init(name: "query", description: "Words in the title or the repository.", isRequired: false)]),
        ToolDefinition(name: "merge_pull_request", title: "Merge a pull request",
                       description: "Merges one of the user's ready pull requests (list_pull_requests), with the repository's default method. Only when the user asked for it.",
                       group: .github, risk: .changes,
                       parameters: [.init(name: "pull_request", description: "repository#number, as list_pull_requests gives it: \"nomdelasociete/skilli#94\".")]),
        ToolDefinition(name: "update_pull_request_branch", title: "Update a pull request's branch",
                       description: "Brings a pull request's branch up to date with its base (list_pull_requests says \"Branch behind\").",
                       group: .github, risk: .changes,
                       parameters: [.init(name: "pull_request", description: "repository#number: \"nomdelasociete/skilli#94\".")]),
        ToolDefinition(name: "mark_github_notification_read", title: "Mark a GitHub notification read",
                       description: "Marks one of the user's notifications read, by its id from list_github_notifications.",
                       group: .github, risk: .harmless,
                       parameters: [.init(name: "id", description: "The notification's id.")]),
        ToolDefinition(name: "search_contacts", title: "Search your contacts",
                       description: "Finds the user's contacts by anything known of them: name, nickname, company, job, department, email, phone, city or address, related people (\"la femme de Paul\"), websites. Returns the best matches with their details, best first. Use it for \"who is…\" and before writing to someone.",
                       group: .contacts, risk: .read,
                       parameters: [.init(name: "query", description: "What is known of the person: \"Jean-François Lumière\", \"François Horizon\", \"06 12 34\".")]),
        ToolDefinition(name: "list_events", title: "Read your calendars",
                       description: "Lists the user's calendar events (every account in the Calendar app) between two dates, earliest first: time, title, calendar, video call link, location, attendees. Defaults to today and the next 6 days. Use it for \"what do I have…\", \"when is my next…\", \"am I free…\", or to find a meeting's link.",
                       group: .calendar, risk: .read,
                       parameters: [.init(name: "from", description: "Start, ISO 8601 in the user's time zone: \"2026-10-12\" or \"2026-10-12T14:00\". Default: today.", isRequired: false),
                                    .init(name: "to", description: "End, ISO 8601; a day alone includes that whole day. Default: 7 days after the start.", isRequired: false),
                                    .init(name: "query", description: "Only events whose title, location, notes or attendees contain these words.", isRequired: false)]),
        ToolDefinition(name: "create_event", title: "Add an event to your calendar",
                       description: "Adds an event to the user's calendar. Check list_events for conflicts first when it matters. Invitees cannot be added (Apple's calendars do not allow it): mention them in the title or notes.",
                       group: .calendar, risk: .changes,
                       parameters: [.init(name: "title", description: "What it is, in the user's language."),
                                    .init(name: "start", description: "ISO 8601 in the user's time zone: \"2026-10-13T14:00\"; a day alone (\"2026-10-13\") for an all-day event."),
                                    .init(name: "end", description: "ISO 8601. Default: an hour after the start (the next day for all-day).", isRequired: false),
                                    .init(name: "calendar", description: "A calendar's name, from list_events' first line. Default: the user's default calendar.", isRequired: false),
                                    .init(name: "location", description: "Where.", isRequired: false),
                                    .init(name: "notes", description: "Notes.", isRequired: false),
                                    .init(name: "url", description: "A link, such as a video call.", isRequired: false),
                                    .init(name: "alert_minutes", description: "An alert that many minutes before.", isRequired: false),
                                    .init(name: "repeat", description: "How it repeats.", options: ["daily", "weekly", "weekdays", "monthly", "yearly"], isRequired: false)]),
        ToolDefinition(name: "update_event", title: "Change an event",
                       description: "Changes an event found with list_events (by its id): title, times, place or notes. Only what is given changes; moving the start keeps the length unless an end is given. One occurrence of a repeating event.",
                       group: .calendar, risk: .changes,
                       parameters: [.init(name: "id", description: "The event's id from list_events."),
                                    .init(name: "title", description: "A new title.", isRequired: false),
                                    .init(name: "start", description: "A new start, ISO 8601.", isRequired: false),
                                    .init(name: "end", description: "A new end, ISO 8601.", isRequired: false),
                                    .init(name: "location", description: "A new place.", isRequired: false),
                                    .init(name: "notes", description: "New notes.", isRequired: false)]),
        ToolDefinition(name: "delete_event", title: "Delete an event",
                       description: "Deletes one event (one occurrence of a repeating one) found with list_events, by its id. Only when the user asked for it.",
                       group: .calendar, risk: .changes,
                       parameters: [.init(name: "id", description: "The event's id from list_events.")]),
        ToolDefinition(name: "compose_email", title: "Write a mail",
                       description: "Opens a new message in the user's mail app, addressed and filled in. Nothing is sent: the user reads it and sends it. Find the address with search_contacts first.",
                       group: .contacts, risk: .harmless,
                       parameters: [.init(name: "to", description: "Email addresses.", isArray: true),
                                    .init(name: "subject", description: "The subject.", isRequired: false),
                                    .init(name: "body", description: "The message, in the user's language.", isRequired: false)]),
        ToolDefinition(name: askUser, title: "Ask you",
                       description: "Asks the user a short question in skil.li's card and returns the answer. Give 2–6 options when the answer is a choice (the first is the default); none for a typed answer. Use only when you cannot decide yourself.",
                       group: nil, risk: .none,
                       parameters: [.init(name: "question", description: "One short question."),
                                    .init(name: "options", description: "Possible answers, best first.", isArray: true, isRequired: false)]),
        ToolDefinition(name: "notify", title: "Show a note",
                       description: "Shows a short note to the user in skil.li's card (progress, or what was done).",
                       group: nil, risk: .none,
                       parameters: [.init(name: "message", description: "One short sentence.")])
    ] + SettingTools.definitions

    /// Claude Code's permission prompt (`--permission-prompt-tool`): not for
    /// the model, Claude Code hides it.
    nonisolated static let approveDefinition = ToolDefinition(
        name: approve, title: "Approve a tool",
        description: "Permission prompt for tools of other servers.",
        group: nil, risk: .none,
        parameters: [.init(name: "tool_name", description: "Tool to approve."),
                     .init(name: "input", description: "Its arguments (JSON).")]
    )

    nonisolated static func definition(_ name: String) -> ToolDefinition? {
        name == approve ? approveDefinition : definitions.first { $0.name == name }.map(live)
    }

    /// A definition as it is now: run_action lists the linked apps' commands
    /// read last.
    nonisolated static func live(_ definition: ToolDefinition) -> ToolDefinition {
        definition.name == "run_action" ? runActionDefinition() : definition
    }

    /// Tools an agent may see: a run's groups, or everything outside a run.
    static func available(for run: AgentContext?) -> [ToolDefinition] {
        guard let run else { return definitions.map(live) }
        return definitions.filter { $0.group.map(run.groups.contains) ?? true }.map(live) + [approveDefinition]
    }

    /// `open_url` with an unusual scheme can do more than open a page.
    static func risk(of definition: ToolDefinition, arguments: [String: Any]) -> ToolRisk {
        if definition.name == "open_url", let url = (arguments["url"] as? String).flatMap(URL.init(string:)),
           !["http", "https", "mailto", "x-apple.systempreferences"].contains(url.scheme?.lowercased() ?? "") {
            return .changes
        }
        return definition.risk
    }

    /// What the approval card shows under the question.
    static func summary(of definition: ToolDefinition, arguments: [String: Any]) -> String {
        // An app's links, whole: each command with the very link it opens;
        // one too long to show whole is refused, never cut.
        if definition.name == "create_app_link" {
            guard let text = appLinkSummary(arguments) else { return "Not an app file skil.li can read: it will say why." }
            return text.count > LinkedAppFile.cardLimit ? "Too much to show whole here: skil.li will refuse it." : text
        }
        let values = definition.parameters.compactMap { parameter -> String? in
            guard let value = arguments[parameter.name] else { return nil }
            let text = (value as? String) ?? (value as? [String])?.joined(separator: ", ") ?? "\(value)"
            return definition.parameters.count == 1 ? text : "\(parameter.name): \(text)"
        }
        let text = values.joined(separator: "\n")
        return text.count > 400 ? String(text.prefix(400)) + "…" : text
    }

    /// What the card shows for a call: the screen tools' element by its
    /// name ("button “Desktop & Dock” in System Settings"), never its id.
    func cardSummary(of definition: ToolDefinition, arguments: [String: Any]) -> String {
        if Self.recordingWords.contains(definition.name) { return recordingSummary(definition, arguments: arguments) }
        guard ["press_ui", "set_ui_value"].contains(definition.name), let id = arguments["id"] as? String,
              let element = ui.describe(id) else {
            return Self.summary(of: definition, arguments: arguments)
        }
        let named = element.prefix(1).uppercased() + element.dropFirst()
        guard definition.name == "set_ui_value" else { return named }
        let text = (arguments["text"] as? String) ?? ""
        return named + "\n" + (text.count > 300 ? String(text.prefix(300)) + "…" : text)
    }

    /// The call's `recording` as the folder's name it resolves to now (an
    /// id, a title, empty for the newest), so the card and the call read
    /// the same one; why not when none is, before anything is asked.
    func pinningRecording(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
        let (folder, _) = try center.recordingForTool(arguments["recording"] as? String)
        var pinned = arguments
        pinned["recording"] = folder.lastPathComponent
        return pinned
    }

    /// A recording's words asked for: which recording, and where its words
    /// go ("“Weekly sync” · Wed 22 Oct, 14:00 · 32 min").
    private func recordingSummary(_ definition: ToolDefinition, arguments: [String: Any]) -> String {
        guard let center = recorder?(), let (_, record) = try? center.recordingForTool(arguments["recording"] as? String) else {
            return Self.summary(of: definition, arguments: arguments)
        }
        let named = "“\(record.title)” · \(record.started.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) · "
            + MeetingTranscriber.length(record.seconds)
        guard definition.name == "recording_followup" else { return named + "\nIts whole transcript goes to the agent asking, then to its provider." }
        let action = (arguments["action"] as? String).flatMap(MeetingFollowUp.Action.init(rawValue:))
        let question = (arguments["question"] as? String).map { "\n“\($0.prefix(200))”" } ?? ""
        let what: String = switch action {
        case .summary?: "Its summary"
        case .chapters?: "Its chapters"
        case .actionItems?: "Its action items, added to Reminders"
        case .recapMail?: "A recap mail, opened for you to send"
        case .ask?: "An answer" + question
        case nil: "A follow-up"
        }
        return named + "\n\(what): its transcript goes to \(center.followUps.provider), what comes back to the agent asking."
    }

    /// A step on the screen that may not be taken back: a button that
    /// sends, deletes, pays or overwrites (`ScreenControl.isRisky`), a field
    /// that has text (or cannot be read) filled over, or Return, Enter,
    /// Delete or ⌘S (a save over a file) pressed. It asks even once the run
    /// was allowed.
    func mayNotBeUndone(_ name: String, arguments: [String: Any]) -> Bool {
        let element = (arguments["id"] as? String).flatMap(ui.label)
        switch name {
        case "press_ui":
            return element.map { ScreenControl.isRisky($0.label) } ?? true
        case "set_ui_value":
            // A value that cannot be read may be text: it asks.
            return element.map { ScreenControl.isRisky($0.label) || $0.value?.isEmpty != true } ?? true
        case "press_keys":
            let keys = ((arguments["keys"] as? String) ?? "").lowercased()
            return ["return", "enter", "delete", "backspace", "cmd+s"].contains { keys.contains($0) }
        default:
            return false
        }
    }

    // MARK: - Running

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The tool's answer as text for the agent; throws a message it can read.
    /// `caller`: who asks ("Claude Code"), the card's title when it shows.
    func call(_ name: String, arguments: [String: Any], run: AgentContext?, caller: String = "An agent") async throws -> String {
        func text(_ key: String) throws -> String {
            guard let value = arguments[key] as? String else { throw Failure(message: "Missing “\(key)”.") }
            return value
        }
        switch name {
        case "get_selection":
            if let run { return run.read?.text ?? "" }
            return await selection.read()?.text ?? ""

        case "replace_selection":
            let value = try text("text")
            if let pid = run?.targetPID, NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                throw Failure(message: "The user switched apps; nothing was replaced. Offer the text instead.")
            }
            if selection.pasteTarget(after: run?.read) == .readOnly {
                throw Failure(message: "The selected text cannot be edited here; nothing was replaced.")
            }
            await selection.replace(with: value)
            return "Replaced."

        case "get_clipboard":
            return NSPasteboard.general.string(forType: .string) ?? ""

        case "set_clipboard":
            let value = try text("text")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            return "Copied."

        case "get_frontmost_app":
            let app = run?.targetPID.flatMap(NSRunningApplication.init(processIdentifier:)) ?? NSWorkspace.shared.frontmostApplication
            let info: [String: String] = [
                "name": app?.localizedName ?? "",
                "bundleID": app?.bundleIdentifier ?? "",
                "window": app.flatMap { AIActionController.focusedWindowTitle(pid: $0.processIdentifier) } ?? ""
            ]
            let data = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)

        case "open_app":
            let name = try text("name")
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) ?? findApp?(name) else {
                let close = similarApps?(name) ?? []
                throw Failure(message: "No app called “\(name)” is installed."
                    + (close.isEmpty ? "" : " Installed apps with close names: \(close.joined(separator: ", ")).")
                    + " Call list_apps to see every installed app instead of guessing.")
            }
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return "Opened \(FileManager.default.displayName(atPath: url.path))."

        case "list_apps":
            let entries = installedApps?() ?? []
            let apps = await Task.detached { AppCandidates.apps(entries) }.value
            return apps.map { $0.kind.isEmpty ? $0.name : "\($0.name) — \($0.kind)" }.joined(separator: "\n")

        case "open_url":
            let value = try text("url")
            guard let url = URL(string: value), url.scheme != nil, NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                throw Failure(message: "No app opens “\(value)”.")
            }
            if CleanShot.uploads(url) {
                try await askUpload(name, run)
            } else if let asked = LinkedApp.asksFirst(url) {
                try await askFirst(asked.command, variant: asked.variant, name, run)
            }
            openURL(url)
            return "Opened."

        case "search_menus":
            guard let pid = run?.targetPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                throw Failure(message: "No app in front.")
            }
            let query = (arguments["query"] as? String ?? "").lowercased()
            let items = MenuReader.items(pid: pid).filter { query.isEmpty || $0.path.lowercased().contains(query) }
            guard !items.isEmpty else { return "No menu item matches “\(query)”." }
            return items.prefix(60).map { item in
                item.path + (item.shortcut.map { "  (\($0))" } ?? "") + (item.isEnabled ? "" : "  [disabled]")
            }.joined(separator: "\n")

        case "press_menu":
            let path = try text("path")
            guard let pid = run?.targetPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                throw Failure(message: "No app in front.")
            }
            try MenuReader.press(path: path, pid: pid)
            return "Chose \(path)."

        case "list_commands":
            return library.all.filter { !$0.isAct }.map { command in
                "\(command.id): \(command.title) — \(command.prompt.split(separator: "\n").first.map(String.init) ?? "")"
            }.joined(separator: "\n")

        case "run_command":
            return try await runCommand(try text("id"), on: try text("text"))

        case "update_app":
            return try await updateApp(arguments["name"] as? String, run: run)

        case "send_message":
            return try await sendMessage(app: try text("app"), to: try text("to"), message: try text("text"), run: run)

        case "list_processes":
            let raw = (arguments["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let query = ProcessListing.query("kill " + raw) ?? .all
            let entries = await Processes.snapshot()
            var ports: [Int: [Processes.Row]] = [:]
            if case .port(let port) = query { ports[port] = await Processes.listening(on: port, among: entries) }
            let rows = Processes.rows(for: query, in: entries, ports: ports)
            guard !rows.isEmpty else { return "No process matches." }
            return rows.map { "\($0.entry.pid)  \($0.entry.name)  \(Processes.usage($0.entry))" + ($0.port.map { "  port \($0)" } ?? "") }
                .joined(separator: "\n")

        case "quit_process":
            guard let pid = Int32(try text("pid")) else { throw Failure(message: "“pid” must be a number.") }
            return try Processes.quit(pid, force: (arguments["force"] as? String) == "true")

        case "list_ui":
            guard let front = NSWorkspace.shared.frontmostApplication else { return "No app in front." }
            let screen = ui.read(pid: front.processIdentifier)
            guard !screen.elements.isEmpty else { return "\(screen.app) shows no window skil.li can read." }
            return "\(screen.app) — “\(screen.window)”\n" + screen.elements.map(\.line).joined(separator: "\n")

        case "find_ui":
            let description = try text("description")
            guard let front = NSWorkspace.shared.frontmostApplication else { return "No app in front." }
            let screen = ui.read(pid: front.processIdentifier)
            let candidates = screen.elements.filter { $0.role != "text" && !$0.label.isEmpty }
            guard !candidates.isEmpty else { return "\(screen.app) shows nothing to press or fill." }
            return await findElement(description, among: candidates)

        case "press_ui":
            return try ui.press(try text("id"))

        case "set_ui_value":
            let id = try text("id")
            let value = try text("text")
            if try ui.setValue(id, value) { return "Filled \(id)." }
            // The app took the focus but not the value: type it.
            await selection.replace(with: value)
            return "Typed into \(id)."

        case "press_keys":
            return try pressKeys(try text("keys"))

        case Self.doInApp:
            return try await doInApp(try text("goal"), app: arguments["app"] as? String, caller: caller, run: run)

        case "start_timer":
            let label = (arguments["label"] as? String) ?? ""
            guard let timers, let request = TimerRequest.parse("timer \(try text("duration")) \(label)") else {
                throw Failure(message: "“\((arguments["duration"] as? String) ?? "")” is not a duration (10 min, 1h30, 90s).")
            }
            let timer = timers.start(request)
            return "Started \(timer.title)."

        case "list_timers":
            let running = timers?.timers ?? []
            guard !running.isEmpty else { return "No timer running." }
            return running.map { "\($0.title): \(TimerRequest.clock(timers?.remaining($0) ?? 0)) left" }.joined(separator: "\n")

        case "cancel_timer":
            let label = ((arguments["label"] as? String) ?? "").lowercased()
            let running = timers?.timers ?? []
            guard let timer = label.isEmpty && running.count == 1 ? running.first : running.first(where: { $0.label.lowercased().contains(label) && !label.isEmpty }) else {
                throw Failure(message: running.isEmpty ? "No timer running." : "Which timer? \(running.map(\.title).joined(separator: ", ")).")
            }
            timers?.cancel(timer.id)
            return "Cancelled \(timer.title)."

        case "record_meeting":
            guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
            let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let said = await center.showCardAndWait(title: title?.isEmpty == false ? title : nil) else {
                throw Failure(message: "Not started: the Record card was closed without recording.")
            }
            return said

        case "import_recording":
            guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
            let path = (try text("path") as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { throw Failure(message: "No file at \(path).") }
            let folder = try await center.importForTool(URL(fileURLWithPath: path))
            return "Imported: \(folder.path)\nIts transcript is being made on this Mac."

        case "recording_status":
            return recorder?()?.status ?? "Not recording."

        case "set_recording_source":
            guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
            return try await center.setSource(try text("source"), on: try text("on") == "true")

        case "pause_recording", "resume_recording", "stop_recording":
            guard let center = recorder?(), center.recorder.isRecording else { throw Failure(message: "No recording is on.") }
            let title = center.recorder.title
            switch name {
            case "pause_recording":
                guard center.recorder.phase == .recording else { throw Failure(message: "“\(title)” is paused already.") }
                center.control(.pause)
                return "Paused “\(title)” at \(MeetingTranscript.clock(center.recorder.elapsed))."
            case "resume_recording":
                guard center.recorder.phase == .paused else { throw Failure(message: "“\(title)” is not paused.") }
                center.control(.resume)
                return "Resumed “\(title)”."
            default:
                let folder = center.recorder.folder
                let length = MeetingTranscript.clock(center.recorder.elapsed)
                center.control(.stop)
                return "Stopped “\(title)” (\(length)): its transcript is being made on this Mac."
                    + (folder.map { "\nFolder: \($0.path)" } ?? "")
            }

        case "list_recordings":
            guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
            return center.recordingsListed()

        case "get_transcript":
            guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
            let (folder, record) = try center.recordingForTool(arguments["recording"] as? String)
            guard let text = try? String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8), record.state == .done else {
                throw Failure(message: "“\(record.title)” has no transcript yet.")
            }
            return text

        case "recording_followup":
            guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
            guard let action = MeetingFollowUp.Action(rawValue: try text("action")) else {
                throw Failure(message: "action is one of: \(MeetingFollowUp.Action.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            let question = (arguments["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if action == .ask, question.isEmpty { throw Failure(message: "ask needs a question.") }
            let (folder, _) = try center.recordingForTool(arguments["recording"] as? String)
            return try await center.followUps.perform(action, on: folder, question: question)

        case "rename_recording":
            guard let center = recorder?() else { throw Failure(message: "The recorder is not available.") }
            let recording = try text("recording")
            let (folder, record) = try center.recordingForTool(recording)
            let moved = try center.renamed(folder, to: try text("title"))
            return "“\(record.title)” is now “\(center.recordings.read(moved)?.title ?? "")”, id \(moved.lastPathComponent)."

        case "list_tabs":
            let tabs = BrowserTabs.all()
            guard !tabs.isEmpty else { return "No browser tab open." }
            return tabs.map { "\($0.browser): \($0.title)\($0.selected ? " (showing)" : "")" }.joined(separator: "\n")

        case "focus_tab":
            let wanted = try text("title")
            let tabs = BrowserTabs.all()
            let query = FuzzyMatcher.Query(wanted)
            guard let tab = tabs.compactMap({ tab in FuzzyMatcher.score(query, FuzzyCandidate(tab.title)).map { (tab, $0) } })
                .max(by: { $0.1 < $1.1 })?.0 else {
                throw Failure(message: "No tab matches “\(wanted)”.")
            }
            BrowserTabs.focus(tab)
            return "Went to “\(tab.title)” in \(tab.browser)."

        case "list_windows":
            guard let arranger else { return "No windows." }
            let open = arranger.windows().map(\.line)
            let saved = arranger.layouts().map { "\($0.name): \($0.summary)" }
            return (open.isEmpty ? "No windows open." : "Open windows:\n" + open.joined(separator: "\n"))
                + (saved.isEmpty ? "" : "\nSaved layouts:\n" + saved.joined(separator: "\n"))

        case "focus_window":
            let wanted = try text("window")
            guard let arranger else { throw Failure(message: "No windows.") }
            let open = arranger.windows()
            let query = FuzzyMatcher.Query(wanted)
            guard let window = open.compactMap({ window in FuzzyMatcher.score(query, FuzzyCandidate(window.line)).map { (window, $0) } })
                .max(by: { $0.1 < $1.1 })?.0 else {
                throw Failure(message: "No open window matches “\(wanted)”. Open: \(open.map(\.line).joined(separator: "; ")).")
            }
            arranger.focus(window)
            return "Brought “\(window.line)” forward."

        case "save_window_layout":
            guard let arranger else { throw Failure(message: "No windows.") }
            let layout = try arranger.save(try text("name"), ignoring: Set(layoutIgnoredApps()))
            return "Saved “\(layout.name)”: \(layout.windows.count) windows (\(layout.summary))."

        case "apply_window_layout":
            let name = try text("name")
            guard let arranger, let layout = arranger.layout(named: name) else {
                throw Failure(message: "No layout named “\(name)”. Saved: \(arranger?.layouts().map(\.name).joined(separator: ", ") ?? "none").")
            }
            return await arranger.apply(layout).message

        case "keep_awake":
            guard let systemCommands else { throw Failure(message: "Mac commands are not available.") }
            if (arguments["sleep"] as? String) == "true" { return systemCommands.keepAwake(.allowSleep) }
            // A week at most, as typed in the launcher: never a length that
            // overflows once in seconds.
            func length(_ name: String) throws -> Int? {
                guard let value = (arguments[name] as? String).flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) ?? (arguments[name] as? Int),
                      value > 0 else { return nil }
                guard value <= Self.longestAwakeMinutes else { throw Failure(message: "“\(name)” is 1 to \(Self.longestAwakeMinutes) minutes (a week).") }
                return value
            }
            // One hour longer, as the launcher's ⌘K: from the end set, from
            // now when it is kept awake until turned off (or not at all).
            if let more = try length("more") {
                let left = systemCommands.awakeUntil.map { max(0, Int($0.timeIntervalSinceNow.rounded())) } ?? 0
                // Past a week: refused, the end set left as it is.
                let seconds = left + more * 60
                guard seconds <= Self.longestAwakeMinutes * 60 else {
                    throw Failure(message: "“more” would keep the Mac awake past a week (\(Self.longestAwakeMinutes) minutes): nothing changed.")
                }
                return systemCommands.keepAwake(.awake(seconds: seconds))
            }
            if let minutes = try length("minutes") {
                return systemCommands.keepAwake(.awake(seconds: minutes * 60))
            }
            if let until = arguments["until"] as? String, !until.isEmpty {
                let parts = until.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]),
                      let today = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) else {
                    throw Failure(message: "“until” is a time of day, HH:MM.")
                }
                let end = today > .now ? today : Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
                return systemCommands.keepAwake(.awake(seconds: Int(end.timeIntervalSinceNow.rounded())))
            }
            return systemCommands.isKeepingAwake ? "The Mac is already kept awake." : try await systemCommands.run(.system(.keepAwake))

        case "set_volume":
            guard let percent = MacReadings.percent(try text("percent")) else { throw Failure(message: "“percent” must be 0 to 100.") }
            return try SystemCommands.setVolume(percent)

        case "brew_search":
            guard let homebrew, homebrew.brew != nil else { return "Homebrew is not installed (brew.sh)." }
            let found = homebrew.search((try? text("query")) ?? "", outdated: await homebrew.outdated())
            guard !found.isEmpty else { return "No formula or cask fits." }
            let described = await homebrew.descriptions(Array(found.prefix(10)))
            return found.prefix(10).map { package in
                let what = described[package.name].flatMap { $0.isEmpty ? nil : $0 } ?? ""
                return "\(package.name) (\(package.isCask ? "cask" : "formula"))" + (what.isEmpty ? "" : ": \(what)")
                    + (package.installed != nil ? " — \(package.status)" : "")
            }.joined(separator: "\n")

        case "brew_install", "brew_upgrade":
            guard let homebrew else { throw Failure(message: "Homebrew is not available.") }
            let wanted = (try? text("name")).flatMap { $0.isEmpty ? nil : $0 }
            if name == "brew_install", wanted == nil { throw Failure(message: "Missing “name”.") }
            let (formulae, casks) = homebrew.allNames()
            var package: BrewPackage?
            if let wanted {
                let cask = (try? text("cask")) == "true" || (!formulae.contains(wanted) && casks.contains(wanted))
                guard (cask ? casks : formulae).contains(wanted) else { throw Failure(message: "No Homebrew \(cask ? "cask" : "formula") named “\(wanted)”: use brew_search.") }
                package = BrewPackage(name: wanted, isCask: cask)
            }
            return try await homebrew.run(name == "brew_install" ? .install : .upgrade, package)

        case "search_history":
            let visits = await BrowserHistory.search((try? text("query")) ?? "", limit: 30, source: historySource)
            guard !visits.isEmpty else { return "No page found in the browsers' history." }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = .current
            return visits.map { "\($0.shownTitle) — \($0.url) — \($0.browser)" + ($0.visited.map { " — \(formatter.string(from: $0))" } ?? "") }
                .joined(separator: "\n")

        case "list_skillies":
            let all = scripts?.all() ?? []
            guard !all.isEmpty else { return "No skillies yet (folder: ~/Library/Application Support/skil.li/skillies): create_skillie writes one." }
            return all.map { command in
                var line = command.title + (command.packageName.isEmpty ? "" : " (\(command.packageName))")
                if !command.description.isEmpty { line += ": \(command.description)" }
                if !command.arguments.isEmpty {
                    line += " — arguments: " + command.arguments.map { "\($0.placeholder)\($0.optional ? " (optional)" : "")"
                        + ($0.kind == .dropdown ? " [\($0.choices.map(\.value).joined(separator: ", "))]" : "") }.joined(separator: ", ")
                }
                return line
            }.joined(separator: "\n")

        case "create_skillie":
            guard let scripts else { throw Failure(message: "Skillies are not available.") }
            guard let language = ScriptCommand.Language(rawValue: try text("language")) else {
                throw Failure(message: "“language” must be one of \(ScriptCommand.Language.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            let placeholders = (arguments["arguments"] as? [String]) ?? []
            let command = try scripts.create(
                title: try text("title"), description: (try? text("description")) ?? "",
                mode: ((try? text("mode")).flatMap(ScriptCommand.Mode.init(rawValue:))).flatMap { $0 == .inline ? nil : $0 } ?? .compact,
                language: language, code: try text("code"),
                arguments: placeholders.map { ($0, false) }, needsConfirmation: (try? text("needs_confirmation")) == "true"
            )
            return "Created the skillie “\(command.title)” (\((command.path as NSString).lastPathComponent)): the user finds it in the launcher; run_skillie runs it."

        case "create_app_link":
            let name = try text("app")
            guard (arguments["documentation"] as? String)?.isEmpty == false else {
                throw Failure(message: "Give “documentation”: the address of the app's own page that documents these links. skil.li adds only those.")
            }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) ?? findApp?(name),
                  let bundleID = Bundle(url: url)?.bundleIdentifier else {
                throw Failure(message: "No app called “\(name)” is installed: skil.li adds the links of apps on this Mac. Call list_apps.")
            }
            let built = try Self.appFile(arguments, bundleID: bundleID)
            // What the card could not show whole is not added.
            if let shown = Self.appLinkSummary(arguments), shown.count > LinkedAppFile.cardLimit {
                throw Failure(message: "Too many links to show the user whole (\(shown.count) characters, \(LinkedAppFile.cardLimit) at most): add fewer commands at a time.")
            }
            do {
                let app = try LinkedApps.add(built.text)
                appsChanged?()
                return "Added \(app.name) (\(app.file ?? "")): \(app.commands.map { "\($0.id) “\($0.title)”" }.joined(separator: ", ")). The user finds them in the launcher and Settings → Apps; run_action runs them."
            } catch {
                throw Failure(message: error.localizedDescription)
            }

        case "create_skill":
            guard let folder = skillsFolder else { throw Failure(message: "Skills are not available.") }
            let name = AgentSkill.name(from: try text("name"))
            do {
                try AgentSkill.checkName(name)
            } catch {
                throw Failure(message: error.localizedDescription)
            }
            let skill = folder.appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: skill.path) else {
                throw Failure(message: "A skill named “\(name)” exists already: pick another name.")
            }
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            try AgentSkill.markdown(name: name, description: try text("description"), instructions: try text("instructions"))
                .write(to: skill.appendingPathComponent(AgentSkill.fileName), atomically: true, encoding: .utf8)
            return "Wrote the skill “\(name)” (skil.li/skills/\(name)/SKILL.md): Ask's agent uses it when a request fits."

        case "run_skillie":
            let title = try text("title")
            guard let scripts, let command = scripts.all().first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) else {
                throw Failure(message: "No skillie “\(title)”. Use list_skillies.")
            }
            let values = (arguments["arguments"] as? [String]) ?? (arguments["arguments"] as? String).map { [$0] } ?? []
            if let missing = command.arguments.enumerated().first(where: { !$0.element.optional && ($0.offset >= values.count || values[$0.offset].isEmpty) }) {
                throw Failure(message: "“\(command.title)” needs “\(missing.element.placeholder)”.")
            }
            // Its own "ask first" holds even when run_skillie is always allowed.
            if command.needsConfirmation, await confirm?("Run “\(command.title)”?", "Its script asks before it runs.", "Run", name, run, false) == .deny {
                throw Failure(message: "Not run: the user declined.")
            }
            // Its own tool calls stay within this command's run.
            let ran = try await scripts.run(command, arguments: values, agentRun: run)
            let output = ran.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ran.succeeded else { throw Failure(message: "“\(command.title)” failed (exit \(ran.status)): \(output.suffix(2_000))") }
            return output.isEmpty ? "Done." : String(output.suffix(8_000))

        case "list_shortcuts":
            let all = AppleShortcuts.all()
            guard !all.isEmpty else { return "No shortcuts in the Shortcuts app yet." }
            return all.map(\.name).joined(separator: "\n")

        case "run_shortcut":
            let wanted = try text("name")
            let all = AppleShortcuts.all()
            guard let shortcut = all.first(where: { $0.name.localizedCaseInsensitiveCompare(wanted) == .orderedSame }) ?? all.first(where: { $0.id == wanted }) else {
                throw Failure(message: "No shortcut “\(wanted)” in the Shortcuts app. Use list_shortcuts.")
            }
            var input = (try? text("input")).flatMap { $0.isEmpty ? nil : $0 }
            if (try? text("selection")) == "true" {
                // As get_selection reads it: the command's, else the app's now.
                var selected = run?.read?.text
                if selected == nil { selected = await selection.read()?.text }
                guard let selected, !selected.isEmpty else {
                    throw Failure(message: "Nothing is selected: “\(shortcut.name)” not run.")
                }
                input = selected
            }
            do {
                let output = try await AppleShortcuts.run(shortcut, input: input)
                return output.map { String($0.suffix(8_000)) } ?? "Done."
            } catch {
                throw Failure(message: error.localizedDescription)
            }

        case "list_projects":
            let all = projects?.all() ?? []
            guard !all.isEmpty else { return "No recent projects in Cursor, VS Code, Windsurf, Zed, Sublime Text or JetBrains IDEs." }
            return all.prefix(60).map { "\($0.name) — \($0.editor) — \($0.path)" }.joined(separator: "\n")

        case "open_project":
            let wanted = try text("name")
            let editor = (try? text("editor")).flatMap { $0.isEmpty ? nil : $0 }
            let all = projects?.all() ?? []
            let fits = all.filter { project in
                (project.path == wanted || project.name.localizedCaseInsensitiveCompare(wanted) == .orderedSame)
                    && (editor.map { project.editor.localizedCaseInsensitiveContains($0) } ?? true)
            }
            guard let project = fits.first else {
                throw Failure(message: "No recent project “\(wanted)”\(editor.map { " in \($0)" } ?? ""). Use list_projects.")
            }
            openProject(project)
            return "Opened “\(project.name)” in \(project.editor)."

        case "list_audio_devices":
            let lines = [true, false].flatMap { output -> [String] in
                let current = AudioDevices.current(output: output)?.uid
                return AudioDevices.devices(output: output).map { device in
                    "\(output ? "Output" : "Input"): \(device.name) (\(AudioRoute.kind(device.transport, output: output)))\(device.uid == current ? " · in use" : "")"
                }
            }
            return lines.isEmpty ? "No sound devices." : lines.joined(separator: "\n")

        case "set_audio_device":
            let output = (try? text("kind")) != "input"
            let wanted = try text("device")
            let devices = AudioDevices.devices(output: output)
            guard let index = AudioRoute.match(wanted, among: devices.map { ($0.name, $0.transport) }, output: output) else {
                throw Failure(message: "No single \(output ? "sound output" : "microphone") fits “\(wanted)”. Connected: \(devices.map(\.name).joined(separator: ", ")).")
            }
            let device = try AudioDevices.select(uid: devices[index].uid, output: output)
            return output ? "Sound on “\(device.name)”." : "Microphone: “\(device.name)”."

        case "list_bluetooth_devices":
            try bluetoothAllowed()
            let devices = BluetoothDevices.paired()
            guard !devices.isEmpty else { return "No Bluetooth device is paired with this Mac." }
            return devices.map { "\($0.name) (\($0.kind.spoken))\($0.connected ? " · connected" : "")" }.joined(separator: "\n")

        case "connect_bluetooth_device":
            try bluetoothAllowed()
            let action = (try? text("action")) ?? "connect"
            guard ["connect", "disconnect"].contains(action) else { throw Failure(message: "“action” is connect or disconnect.") }
            let connect = action == "connect"
            let wanted = try text("device")
            let devices = BluetoothDevices.paired()
            guard let index = BluetoothRoute.match(wanted, among: devices.map { ($0.name, $0.kind) }) else {
                throw Failure(message: "No single paired device fits “\(wanted)”. Paired: \(devices.map(\.name).joined(separator: ", ")).")
            }
            guard let systemCommands else { throw Failure(message: "Mac commands are not available.") }
            return try await systemCommands.run(.bluetooth(BluetoothTarget(devices[index]), connect: connect))

        case "system_info":
            return SystemCommands.systemInfo()

        case "list_snippets":
            let all = snippets?.all ?? []
            guard !all.isEmpty else { return "No snippets yet." }
            return all.map { "\($0.name)\($0.keyword.isEmpty ? "" : " (\($0.keyword))"): \(ClipboardSearch.title(of: $0.text, limit: 80))" }
                .joined(separator: "\n")

        case "insert_snippet":
            let name = try text("name")
            let all = snippets?.all ?? []
            guard let snippet = all.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
                ?? all.first(where: { $0.keyword == name || $0.id == name }) else {
                throw Failure(message: "No snippet named “\(name)”. Snippets: \(all.map(\.name).joined(separator: ", ")).")
            }
            await insertSnippet?(snippet)
            return "Inserted “\(snippet.name)”."

        case "run_mac_command":
            let id = try text("command")
            guard let command = MacAction(rawValue: id), let systemCommands else {
                throw Failure(message: "Unknown command “\(id)”.")
            }
            return try await systemCommands.run(command)

        case "list_reminders", "create_reminder", "update_reminder", "delete_reminder":
            guard let reminders else { throw Failure(message: "Reminders are not available.") }
            guard await reminders.allow() else {
                onPermissionNeeded?(.reminders)
                throw Failure(message: "skil.li may not use Reminders. The user can allow it in System Settings → Privacy & Security → Reminders, or from skil.li's launcher.")
            }
            return try await reminderTool(name, arguments: arguments, in: reminders, text: text)

        case "list_pull_requests", "list_github_notifications", "merge_pull_request", "update_pull_request_branch", "mark_github_notification_read":
            guard let github, github.isSignedIn else {
                throw Failure(message: "GitHub is not connected. The user signs in with GitHub in skil.li's Settings → GitHub.")
            }
            return try await githubTool(name, arguments: arguments, in: github, text: text)

        case "search_contacts":
            guard let contacts else { throw Failure(message: "Contacts are not available.") }
            // Never asked: macOS's own question, where it is needed (D7).
            guard await contacts.allow() else {
                onPermissionNeeded?(.contacts)
                throw Failure(message: "skil.li may not read Contacts. The user can allow it from skil.li's launcher (“@”) or in System Settings → Privacy & Security → Contacts.")
            }
            let matches = await contacts.search(try text("query"), limit: 5)
            guard !matches.isEmpty else { return "No contact fits." }
            return matches.map { $0.record.details }.joined(separator: "\n\n")

        case "list_events":
            guard let calendar else { throw Failure(message: "Calendars are not available.") }
            guard await calendar.allow() else {
                onPermissionNeeded?(.calendar)
                throw Failure(message: "skil.li may not read the calendars yet. The user can allow it from skil.li's launcher or in System Settings → Privacy & Security → Calendars.")
            }
            return listEvents(from: arguments["from"] as? String, to: arguments["to"] as? String, query: arguments["query"] as? String, in: calendar)

        case "create_event", "update_event", "delete_event":
            guard let calendar else { throw Failure(message: "Calendars are not available.") }
            guard await calendar.allow() else {
                onPermissionNeeded?(.calendar)
                throw Failure(message: "skil.li may not use the calendars yet. The user can allow it from skil.li's launcher or in System Settings → Privacy & Security → Calendars.")
            }
            return try changeEvent(name, arguments: arguments, in: calendar, text: text)

        case "compose_email":
            let to = (arguments["to"] as? [String]) ?? (arguments["to"] as? String).map { [$0] } ?? []
            let addresses = to.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("@") }
            guard !addresses.isEmpty else { throw Failure(message: "Give at least one email address in “to”.") }
            guard let url = ContactBook.mailURL(to: addresses, subject: arguments["subject"] as? String ?? "", body: arguments["body"] as? String ?? "") else {
                throw Failure(message: "Could not write that mail.")
            }
            openURL(url)
            return "A new mail to \(addresses.joined(separator: ", ")) is open in the mail app; the user sends it."

        case "run_action":
            let id = try text("id")
            guard var action = Self.actions[id] else { throw Failure(message: "Unknown action “\(id)”.") }
            // Left out: the plain run. Given, it is the file, never ignored
            // (an empty `file="$1"` would run on the Finder selection).
            var file: String?
            if let given = arguments["file"], !(given is NSNull) {
                guard let path = (given as? String)?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
                    throw Failure(message: "“file” is empty: give the file's full path, or leave it out.")
                }
                file = path
            }
            if let asked = (arguments["variant"] as? String)?.trimmingCharacters(in: .whitespaces), !asked.isEmpty {
                guard case .mac(.appLink(let command, nil)) = action else {
                    throw Failure(message: "“\(id)” takes no variant.")
                }
                guard let variant = command.variant(id: asked) else {
                    let known = command.variants.map(\.id).joined(separator: ", ")
                    throw Failure(message: known.isEmpty ? "“\(id)” takes no variant." : "“\(id)” has no variant “\(asked)”: \(known).")
                }
                action = .mac(.appLink(command, variant: variant.id))
            }
            // What its app's file says asks first, asked every time (CleanShot's upload).
            if case .mac(.appLink(let command, let variant)) = action, command.asksFirst(variant: variant.flatMap(command.variant(id:))) {
                let picked = variant.flatMap(command.variant(id:))
                if picked?.id == "upload", command.appID == LinkedApp.cleanShot.id {
                    try await askUpload(name, run)
                } else {
                    try await askFirst(command, variant: picked, name, run)
                }
            }
            if let path = file {
                // Opened here, so what does not fit is said to the agent.
                guard case .mac(.appLink(let command, let variant)) = action, command.files != nil else {
                    throw Failure(message: "“\(id)” takes no file.")
                }
                let expanded = (path as NSString).expandingTildeInPath
                guard expanded.hasPrefix("/") else { throw Failure(message: "Give the file's full path: “\(path)” is not one.") }
                guard let systemCommands else { throw Failure(message: "Mac commands are not available.") }
                try systemCommands.open(URL(fileURLWithPath: expanded), with: command, variant: variant.flatMap(command.variant(id:)))
                return "Opened “\((expanded as NSString).lastPathComponent)” in \(command.app?.name ?? "the app")."
            }
            performAction?(action)
            return "Done."

        default:
            throw Failure(message: "Unknown tool “\(name)”.")
        }
    }

    /// create_app_link's app as the approval card shows it, whole
    /// (`LinkedAppFile.card`); nil when it is not an app file.
    nonisolated static func appLinkSummary(_ arguments: [String: Any]) -> String? {
        guard let built = try? appFile(arguments, bundleID: nil), let app = try? LinkedAppFile.read(Data(built.text.utf8), file: "") else { return nil }
        return LinkedAppFile.card(app)
    }

    /// create_app_link's arguments as an app file (`LinkedAppFile`): its
    /// text, read back as any file is. `bundleID`: the installed app's; nil
    /// in the approval's summary, before it is looked up.
    nonisolated static func appFile(_ arguments: [String: Any], bundleID: String?) throws -> (text: String, object: [String: Any]) {
        func value(_ key: String) -> String? {
            (arguments[key] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let name = value("app") else { throw Failure(message: "Missing “app”.") }
        let commandsText = value("commands") ?? ""
        guard let commands = try? JSONSerialization.jsonObject(with: Data(commandsText.utf8)) as? [Any] else {
            throw Failure(message: "“commands” must be a JSON array of command objects.")
        }
        // "Visual Studio Code" → "visual-studio-code".
        let made = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
        var object: [String: Any] = [
            "id": value("id") ?? String(made.prefix(32)),
            "name": (name as NSString).deletingPathExtension,
            "bundleID": bundleID ?? "com.example.app",
            "scheme": (value("scheme") ?? "").replacingOccurrences(of: "://", with: "").replacingOccurrences(of: ":", with: ""),
            "commands": commands
        ]
        if let documentation = value("documentation") { object["documentation"] = documentation }
        if let minimum = value("minimum_version") { object["minimumVersion"] = minimum }
        if let note = value("note") { object["note"] = note }
        return (try LinkedAppFile.text(object), object)
    }

    /// A capture sent to CleanShot Cloud leaves the Mac: asked in the card
    /// every time, whatever the tool's rights (`run_action`'s upload,
    /// `open_url` with `action=upload`). Asked under its own name
    /// ("run_action.upload"): the tool just allowed in the card
    /// (`MCPService.justAllowed`) never answers for it.
    private func askUpload(_ tool: String, _ run: AgentContext?) async throws {
        let approval = await confirm?("Upload the capture to CleanShot Cloud?", "CleanShot X sends it to its cloud and copies its link.",
                                      "Upload", "\(tool).upload", run, false) ?? .deny
        guard approval != .deny else { throw Failure(message: "Not uploaded: the user declined.") }
    }

    /// A linked app's command its file says asks first: asked in the card
    /// every time, whatever the tool's rights, under its own name
    /// ("run_action.zoom.join"), as an upload is.
    private func askFirst(_ command: AppLinkCommand, variant: AppLinkCommand.Variant?, _ tool: String, _ run: AgentContext?) async throws {
        let title = variant?.title ?? command.title
        let app = command.app?.name ?? "its app"
        let approval = await confirm?("Run “\(title)” in \(app)?", "\(command.oneLine). Its app asks first.", "Run",
                                      "\(tool).\(command.id)", run, false) ?? .deny
        guard approval != .deny else { throw Failure(message: "Not run: the user declined.") }
    }

    /// Bluetooth may be used; never asked: macOS's own question now, as
    /// Ask does (D7), and the agent tries again once the user answered.
    private func bluetoothAllowed() throws {
        guard !BluetoothDevices.isAllowed else { return }
        onPermissionNeeded?(.bluetooth)
        if BluetoothDevices.authorization == .notDetermined {
            BluetoothDevices.requestAccess()
            throw Failure(message: "macOS is asking the user to let skil.li use Bluetooth: try again once they allowed it.")
        }
        throw Failure(message: "skil.li may not use Bluetooth. The user can allow it from skil.li's launcher (type “bluetooth”) or Settings → Privacy.")
    }

    // MARK: - Update an app

    private static let updateWords = ["check for update", "check for new version", "software update", "rechercher des mises à jour",
                                      "rechercher les mises à jour", "vérifier les mises à jour", "mise à jour", "mises à jour"]

    /// Its own update menu item, else the App Store, else Homebrew.
    private func updateApp(_ name: String?, run: AgentContext?) async throws -> String {
        let url: URL
        if let name, !name.isEmpty {
            guard let found = findApp?(name) else { throw Failure(message: "No app called “\(name)” is installed. Call list_apps.") }
            url = found
        } else {
            let pid = run?.targetPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard let pid, let found = NSRunningApplication(processIdentifier: pid)?.bundleURL else { throw Failure(message: "No app in front.") }
            url = found
        }
        let appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""

        // 1. The app's own "Check for Updates…" (Sparkle and most others);
        // its menu exists only while it runs.
        var running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let fromStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        if running == nil, !fromStore {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            running = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            try? await Task.sleep(for: .seconds(1.5))
        }
        if let running, running.processIdentifier != getpid() {
            // Off the main thread, never for skil.li itself: that deadlocks.
            let items = await Task.detached { MenuReader.items(pid: running.processIdentifier) }.value
            // Not "Automatically Check for Updates": a setting, not a check.
            let update = items.first { item in
                let path = item.path.lowercased()
                return item.isEnabled && !path.contains("automatic") && Self.updateWords.contains { path.contains($0) }
            }
            if let update {
                running.activate()
                guard AXUIElementPerformAction(update.element, kAXPressAction as CFString) == .success else {
                    throw Failure(message: "\(appName) did not open “\(update.path)”.")
                }
                return "Chose \(update.path.replacingOccurrences(of: " > ", with: " › ")) in \(appName)."
            }
        }
        // 2. The App Store.
        if fromStore {
            NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!)
            return "\(appName) comes from the App Store: opened its Updates page."
        }
        // 3. Homebrew.
        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile(atPath:)),
           let token = await Self.caskToken(for: url.lastPathComponent, brew: URL(fileURLWithPath: brew)) {
            let output = (try? await ClaudeCLI.run(URL(fileURLWithPath: brew), ["upgrade", "--cask", token], timeout: 600)) ?? ""
            let tail = output.split(separator: "\n").suffix(3).joined(separator: "\n")
            return "brew upgrade --cask \(token): " + (tail.isEmpty ? "done." : tail)
        }
        if url.path.hasPrefix("/System/") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
            return "\(appName) is part of macOS and updates with it: opened Software Update."
        }
        return "\(appName) has no update menu and is not from the App Store or Homebrew: its website may have a newer version."
    }

    /// The Homebrew cask that installed `appFile` ("VectorCraft.app").
    private static func caskToken(for appFile: String, brew: URL) async -> String? {
        guard let output = try? await ClaudeCLI.run(brew, ["info", "--cask", "--installed", "--json=v2"], timeout: 30),
              let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]]
        else { return nil }
        for cask in casks {
            let artifacts = cask["artifacts"] as? [Any] ?? []
            let apps = artifacts.compactMap { ($0 as? [String: Any])?["app"] as? [Any] }.flatMap { $0 }.compactMap { $0 as? String }
            if apps.contains(appFile) { return cask["token"] as? String }
        }
        return nil
    }

    // MARK: - Send a message

    /// Slack and Discord open any conversation with ⌘K.
    private static let quickSwitchers: [String: Character] = ["slack": "k", "discord": "k"]

    /// Opens the conversation, then asks the user with the conversation it
    /// actually found ("Thomas Martin") before pasting and sending.
    private func sendMessage(app: String, to recipient: String, message: String, run: AgentContext?) async throws -> String {
        guard let key = Self.quickSwitchers[app.lowercased()] else {
            throw Failure(message: "send_message works with Slack and Discord.")
        }
        guard let url = findApp?(app) else { throw Failure(message: "\(app) is not installed.") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let running = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        var front = false
        for _ in 0..<30 where !front {
            front = NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier
            if !front { try? await Task.sleep(for: .milliseconds(100)) }
        }
        guard front else { throw Failure(message: "\(app) did not come to the front.") }
        let pid = running.processIdentifier
        // Each step is checked through Accessibility (Slack and Discord
        // build it when asked): never typed or sent blind, and nothing is
        // sent before the user confirms the conversation actually found.
        guard selection.focusIsObservable(in: pid) else {
            throw Failure(message: "skil.li cannot see \(app)'s window (Accessibility), so it does not type there blind. Nothing was sent.")
        }
        func until(_ seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1_000))
            while ContinuousClock.now < deadline {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return condition()
        }
        let titleBefore = AIActionController.focusedWindowTitle(pid: pid) ?? ""
        // The search must take the focus away from where it was (the
        // message box, say): typing the name there and Return would send it.
        let focusBefore = selection.focusNow()
        selection.press(key, flags: .maskCommand)
        guard await until(2, { self.selection.focusMoved(from: focusBefore) && self.selection.focusIsTextInput() }) else {
            throw Failure(message: "\(app)'s ⌘K search did not open. Nothing was typed.")
        }
        await selection.replace(with: recipient)
        guard await until(2, { self.selection.focusedText()?.localizedCaseInsensitiveContains(recipient) == true }) else {
            selection.press(code: kVK_Escape)
            throw Failure(message: "The name did not reach \(app)'s search. Nothing was sent.")
        }
        // The matches come as the name is typed.
        try? await Task.sleep(for: .milliseconds(600))
        selection.press(code: kVK_Return)
        // A conversation opened: the window's title changed (or it already
        // was that conversation).
        let opened = await until(3) {
            let title = AIActionController.focusedWindowTitle(pid: pid) ?? ""
            return title != titleBefore || titleBefore.localizedCaseInsensitiveContains(recipient)
        }
        guard opened else {
            selection.press(code: kVK_Escape)
            throw Failure(message: "\(app) found no conversation for “\(recipient)”. Nothing was sent.")
        }
        // "Thomas Martin (DM) - Acme - Slack" → "Thomas Martin (DM)".
        let title = AIActionController.focusedWindowTitle(pid: pid)?
            .components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespaces) ?? recipient
        Log.trace("send_message opened “\(title)” in \(app) for “\(recipient)”")
        let approval = await confirm?("Send to \(title) in \(app)?", message, "Send", "send_message", run, true) ?? .deny
        guard approval != .deny else {
            return "Not sent: the user declined. The conversation “\(title)” is open in \(app)."
        }
        guard await until(2, { self.selection.focusIsTextInput() }) else {
            throw Failure(message: "\(app)'s message box did not take the focus. Nothing was sent.")
        }
        await selection.replace(with: message)
        let start = String(message.prefix(20))
        guard await until(2, { self.selection.focusedText()?.contains(start) == true }) else {
            throw Failure(message: "The message did not reach \(app)'s message box. Nothing was sent.")
        }
        selection.press(code: kVK_Return)
        return "Sent to \(title) in \(app)."
    }

    // MARK: - Calendar

    private func changeEvent(_ name: String, arguments: [String: Any], in calendar: CalendarBook, text: (String) throws -> String) throws -> String {
        func date(_ key: String) throws -> ReminderDate.Due? {
            guard let value = arguments[key] as? String, !value.isEmpty else { return nil }
            guard let parsed = ReminderDate.parse(value) else { throw Failure(message: "“\(value)” is not an ISO 8601 date.") }
            return parsed
        }
        switch name {
        case "create_event":
            guard let start = try date("start") else { throw Failure(message: "A start is needed.") }
            let clock = Calendar.current
            let isAllDay = !start.hasTime
            let begin = isAllDay ? clock.startOfDay(for: start.date) : start.date
            var end = try date("end")?.date ?? (isAllDay ? clock.date(byAdding: .day, value: 1, to: begin) ?? begin : begin.addingTimeInterval(3_600))
            if end <= begin { end = begin.addingTimeInterval(isAllDay ? 86_400 : 3_600) }
            let recurrence: SpokenRecurrence? = switch arguments["repeat"] as? String {
            case "daily": .init(.daily)
            case "weekly": .init(.weekly)
            case "weekdays": .init(.weekly, weekdays: [2, 3, 4, 5, 6])
            case "monthly": .init(.monthly)
            case "yearly": .init(.yearly)
            default: nil
            }
            let request = EventRequest(title: try text("title"), start: begin, end: end, isAllDay: isAllDay, calendar: arguments["calendar"] as? String,
                                       notes: arguments["notes"] as? String ?? "", url: arguments["url"] as? String,
                                       alertMinutes: (arguments["alert_minutes"] as? String).flatMap { Int($0) } ?? arguments["alert_minutes"] as? Int,
                                       recurrence: recurrence)
            var event = try calendar.create(request)
            if let location = arguments["location"] as? String, !location.isEmpty {
                event = try calendar.update(id: event.id, title: nil, start: nil, end: nil, location: location, notes: nil)
            }
            return "Added (id \(event.id)): \(Agenda.dayName(event.start, now: .now)) \(Agenda.span(event)) · \(event.title) · calendar \(event.calendar)"
        case "update_event":
            let event = try calendar.update(id: try text("id"), title: arguments["title"] as? String, start: try date("start")?.date,
                                            end: try date("end")?.date, location: arguments["location"] as? String, notes: arguments["notes"] as? String)
            return "Changed (id \(event.id)): \(Agenda.dayName(event.start, now: .now)) \(Agenda.span(event)) · \(event.title)"
        default:
            let title = try calendar.delete(id: try text("id"))
            return "Deleted “\(title)”."
        }
    }

    private func listEvents(from: String?, to: String?, query: String?, in calendar: CalendarBook) -> String {
        let clock = Calendar.current
        let start = from.flatMap { ReminderDate.parse($0)?.date } ?? clock.startOfDay(for: .now)
        var end = clock.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        if let to, let parsed = ReminderDate.parse(to) {
            // A day alone: all of it.
            end = parsed.hasTime ? parsed.date : clock.date(byAdding: .day, value: 1, to: parsed.date) ?? parsed.date
        }
        var events = calendar.events(from: start, to: end)
        let words = ContactSearch.words(query ?? "")
        if !words.isEmpty {
            events = events.filter { event in
                let text = ContactSearch.words([event.title, event.location, event.notes].joined(separator: " ")
                    + " " + event.attendees.map { "\($0.name) \($0.email ?? "")" }.joined(separator: " "))
                return words.allSatisfy { word in text.contains { $0.hasPrefix(word) } }
            }
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd EEE"
        let calendars = "Calendars: " + calendar.calendarNames().joined(separator: ", ")
        guard !events.isEmpty else { return "No events from \(day.string(from: start)) to \(day.string(from: end)).\n\(calendars)" }
        return calendars + "\n" + events.prefix(150).map { event in
            var parts = ["\(day.string(from: event.start)) \(Agenda.span(event))", event.title.isEmpty ? "Untitled" : event.title, "id \(event.id)"]
            if !event.calendar.isEmpty { parts.append("calendar \(event.calendar)") }
            if let meeting = event.meeting { parts.append("\(meeting.service) \(meeting.url.absoluteString)") }
            if !event.location.isEmpty, event.location != event.meeting?.url.absoluteString { parts.append("at \(event.location)") }
            if !event.attendees.isEmpty {
                parts.append("with " + event.attendees.prefix(12).map { person in person.email.map { "\(person.name) <\($0)>" } ?? person.name }
                    .joined(separator: ", "))
            }
            if event.declined { parts.append("declined") }
            return parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    // MARK: - Reminders

    private func githubTool(_ name: String, arguments: [String: Any], in github: GitHubBook, text: (String) throws -> String) async throws -> String {
        await github.refreshed()
        if let problem = github.problem, github.lastRefresh == nil { throw Failure(message: problem) }
        // A list that could not be read again says so: never an empty or
        // old list passed off as up to date.
        func stale(notifications: Bool) -> String {
            github.problem(notifications: notifications).map { "Not up to date: \($0)\n" } ?? ""
        }
        let words = (arguments["query"] as? String ?? "").lowercased().split(separator: " ").map(String.init)
        func fits(_ fields: [String]) -> Bool {
            let haystack = fields.joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        func pullRequest() throws -> PullRequest {
            let said = try text("pull_request").trimmingCharacters(in: .whitespaces)
            guard let found = github.pullRequests.first(where: { "\($0.repositoryFullName)#\($0.number)".caseInsensitiveCompare(said) == .orderedSame
                || "\($0.repository)#\($0.number)".caseInsensitiveCompare(said) == .orderedSame }) else {
                throw Failure(message: "No open pull request “\(said)” among the user's (list_pull_requests lists them).")
            }
            return found
        }
        switch name {
        case "list_pull_requests":
            let group = (arguments["group"] as? String).flatMap(PullRequestGroup.init(rawValue:))
            let shown = github.pullRequests.filter { (group == nil || $0.group == group) && fits([$0.title, $0.repositoryFullName, $0.reason]) }
            guard !shown.isEmpty else { return stale(notifications: false) + (github.pullRequests.isEmpty ? "No open pull request." : "No pull request fits.") }
            return stale(notifications: false) + shown.map { pullRequest in
                "\(pullRequest.group.rawValue) — \(pullRequest.repositoryFullName)#\(pullRequest.number) “\(pullRequest.title)” — \(pullRequest.reason)"
                    + (pullRequest.needsUserAction ? " (the user's turn)" : "") + (pullRequest.canMerge ? " — can merge" : "") + " — \(pullRequest.url.absoluteString)"
            }.joined(separator: "\n")
        case "list_github_notifications":
            let shown = github.unreadNotifications.filter { fits([$0.title, $0.repository, $0.reasonTitle]) }
            let more = github.notificationsComplete ? "" : "\nMore unread notifications than listed: https://github.com/notifications"
            guard !shown.isEmpty else {
                // A cut list cannot say there is none: only none among those read.
                let none = github.notificationsComplete ? "No unread notification." : "None among the unread notifications read; GitHub has more."
                return stale(notifications: true) + none + more
            }
            return stale(notifications: true) + shown.map { "\($0.id) — \($0.reasonTitle) — \($0.repository) “\($0.title)” — \($0.url.absoluteString)" }.joined(separator: "\n") + more
        case "merge_pull_request":
            let found = try pullRequest()
            guard found.canMerge else {
                throw Failure(message: found.defaultMergeMethod == nil && found.group == .ready ? "The user may not merge \(found.repositoryFullName)#\(found.number)."
                              : "\(found.repositoryFullName)#\(found.number) is not ready to merge: \(found.reason).")
            }
            try await github.merge(found)
            return "Merged \(found.repositoryFullName)#\(found.number)."
        case "update_pull_request_branch":
            let found = try pullRequest()
            guard found.canUpdateBranch else { throw Failure(message: "\(found.repositoryFullName)#\(found.number) is not behind its base branch.") }
            try await github.updateBranch(found)
            return "Updating the branch of \(found.repositoryFullName)#\(found.number)."
        default:
            let id = try text("id")
            guard let note = github.notifications.first(where: { $0.id == id }) else { throw Failure(message: "No notification \(id).") }
            try await github.markRead(note)
            return "Marked read."
        }
    }

    private func reminderTool(_ name: String, arguments: [String: Any], in reminders: ReminderBook, text: (String) throws -> String) async throws -> String {
        func due(_ key: String) throws -> ReminderDate.Due? {
            guard let value = arguments[key] as? String, !value.isEmpty, value.lowercased() != "none" else { return nil }
            guard let parsed = ReminderDate.parse(value) else { throw Failure(message: "“\(value)” is not a date; use 2026-10-11T21:00 or 2026-10-12.") }
            return parsed
        }
        func priority() -> Int? {
            switch arguments["priority"] as? String {
            case "none": 0
            case "low": 9
            case "medium": 5
            case "high": 1
            default: nil
            }
        }
        func line(_ item: ReminderItem) -> String {
            var parts = [item.title.isEmpty ? "Untitled" : item.title, "id \(item.id)", "list \(item.list)"]
            let when = Reminders.when(item, now: .now)
            if !when.isEmpty { parts.append("due \(when)") }
            if !item.marks.isEmpty { parts.append("priority \(item.marks)") }
            if item.repeats { parts.append("repeats") }
            if item.isCompleted { parts.append("done") }
            if let link = item.link { parts.append(link.absoluteString) }
            if !item.notes.isEmpty { parts.append("notes: \(item.notes.prefix(200))") }
            return parts.joined(separator: " · ")
        }
        switch name {
        case "list_reminders":
            let completed = (arguments["completed"] as? String) == "true"
            var items = await reminders.items().filter { $0.isCompleted == completed }
            if let list = arguments["list"] as? String, !list.isEmpty { items = items.filter { $0.list.localizedCaseInsensitiveCompare(list) == .orderedSame } }
            let words = ContactSearch.words(arguments["query"] as? String ?? "")
            if !words.isEmpty {
                items = items.filter { item in
                    let text = ContactSearch.words(item.title + " " + item.notes)
                    return words.allSatisfy { word in text.contains { $0.hasPrefix(word) } }
                }
            }
            if let before = try due("due_before") { items = items.filter { ($0.due ?? .distantFuture) < before.date } }
            let lists = "Lists: " + reminders.listNames().joined(separator: ", ")
            let ordered = Reminders.sections(items, now: .now).flatMap(\.items)
            guard !ordered.isEmpty else { return "No reminder fits.\n\(lists)" }
            return lists + "\n" + ordered.prefix(200).map(line).joined(separator: "\n")
        case "create_reminder":
            let when = try due("due")
            let recurrence: SpokenRecurrence? = switch arguments["repeat"] as? String {
            case "daily": .init(.daily)
            case "weekly": .init(.weekly)
            case "weekdays": .init(.weekly, weekdays: [2, 3, 4, 5, 6])
            case "monthly": .init(.monthly)
            case "yearly": .init(.yearly)
            default: nil
            }
            let request = ReminderRequest(title: try text("title"), due: when?.date, hasTime: when?.hasTime ?? false, list: arguments["list"] as? String,
                                          priority: priority() ?? 0, recurrence: when == nil ? nil : recurrence, notes: arguments["notes"] as? String ?? "",
                                          url: arguments["url"] as? String)
            let item = try await reminders.add(request)
            return "Added “\(item.title)” to \(item.list) (id \(item.id))" + (when == nil ? "." : ", due \(Reminders.when(item, now: .now)).")
        case "update_reminder":
            let id = try text("id")
            if let done = arguments["done"] as? String { try reminders.complete(id: id, done: done == "true") }
            if arguments["due"] != nil {
                let when = try due("due")
                try reminders.reschedule(id: id, due: when?.date, hasTime: when?.hasTime ?? false)
            }
            if let list = arguments["list"] as? String, !list.isEmpty { try reminders.move(id: id, to: list) }
            if let priority = priority() { try reminders.setPriority(id: id, priority) }
            if arguments["title"] != nil || arguments["notes"] != nil {
                try reminders.update(id: id, title: arguments["title"] as? String, notes: arguments["notes"] as? String)
            }
            let item = await reminders.items().first { $0.id == id }
            return item.map { "Changed: " + line($0) } ?? "Changed."
        default:
            let title = try reminders.delete(id: try text("id"))
            return "Deleted “\(title)”."
        }
    }

    // MARK: - The user's tools

    /// The user's webhook as agents see it.
    static func definition(for tool: CustomTool) -> ToolDefinition {
        let host = URLComponents(string: tool.url)?.host ?? tool.url
        return ToolDefinition(
            name: tool.name, title: tool.name.replacingOccurrences(of: "-", with: " ").capitalized,
            description: (tool.instructions.isEmpty ? "The user's tool." : tool.instructions) + " (Sends the text to \(host).)",
            group: .personal, risk: .changes,
            parameters: [.init(name: "text", description: "What to send."),
                         .init(name: "note", description: "Anything else the tool should know.", isRequired: false)]
        )
    }

    /// POSTs `{text, note, tool, app}` as JSON; the reply's text comes back.
    /// The element that fits a description: the decision model picks
    /// among the window's elements (~0.3 s), or names are compared when no
    /// decision key is saved.
    private func findElement(_ description: String, among candidates: [UIReader.Element]) async -> String {
        let options = candidates.prefix(254)
        let keys = decisionKeysOverride ?? AskRouter.keys(ai)
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let question = DecisionQuestion(
                name: "element",
                instructions: "Which element of this window does the user mean? Answer none when none fits.",
                options: options.map { .init(value: $0.id, description: "\($0.role) “\($0.label)”") }
                    + [.init(value: "none", description: "No element fits")]
            )
            guard let answer = try? await DecisionClient.decide([question], input: "The user means: \(description)", provider: provider, key: key)[question.name] else { continue }
            let ranked = answer.probabilities.filter { $0.key != "none" }.sorted { $0.value > $1.value }
            guard let best = ranked.first, best.value >= 0.3, let element = ui.element(best.key) else {
                return "No element fits “\(description)”. Read the window with list_ui."
            }
            let others = ranked.dropFirst().prefix(2).compactMap { ui.element($0.key)?.line }
            return "\(element.line) (\(Int(best.value * 100)) %)" + (others.isEmpty ? "" : "\nAlso possible:\n" + others.joined(separator: "\n"))
        }
        let query = FuzzyMatcher.Query(description)
        let ranked = options.compactMap { element in FuzzyMatcher.score(query, FuzzyCandidate(element.label)).map { (element, $0) } }
            .sorted { $0.1 > $1.1 }
        guard !ranked.isEmpty else { return "No element fits “\(description)”. Read the window with list_ui." }
        return ranked.prefix(3).map(\.0.line).joined(separator: "\n")
    }

    /// "cmd+s", "return", "cmd+shift+n": to the app in front.
    private func pressKeys(_ spec: String) throws -> String {
        guard let chord = try? Chord(parsing: spec.lowercased().replacingOccurrences(of: " ", with: "")) else {
            throw Failure(message: "“\(spec)” is not a key or shortcut (try cmd+s, return, tab).")
        }
        var flags: CGEventFlags = []
        if chord.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if chord.modifiers.contains(.control) { flags.insert(.maskControl) }
        if chord.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if chord.modifiers.contains(.shift) { flags.insert(.maskShift) }
        switch chord.key {
        case .character(let character):
            selection.press(character, flags: flags)
        case .named(let named):
            let codes: [NamedKey: Int] = [.space: 49, .return: 36, .tab: 48, .escape: 53, .delete: 51, .forwardDelete: 117,
                                          .left: 123, .right: 124, .down: 125, .up: 126, .home: 115, .end: 119, .pageUp: 116, .pageDown: 121]
            guard let code = codes[named] else { throw Failure(message: "skil.li cannot press “\(spec)”.") }
            selection.press(code: code, flags: flags)
        }
        return "Pressed \(chord.keycaps.joined())."
    }

    /// "Do it here" toward `goal` in the app named (brought forward), else
    /// the app the command started in, else the one in front; a stop is
    /// an error the agent reads, with why and the steps done.
    private func doInApp(_ goal: String, app name: String?, caller: String, run: AgentContext?) async throws -> String {
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure(message: "Missing “goal”.") }
        guard let doItHere else { throw Failure(message: "skil.li cannot act in apps now.") }
        let app: NSRunningApplication
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            do {
                app = try await ControlTarget.bringForward(name, findApp: { self.findApp?($0) })
            } catch {
                let close = similarApps?(name) ?? []
                throw Failure(message: error.localizedDescription + (close.isEmpty ? "" : " Installed apps with close names: \(close.joined(separator: ", ")).")
                    + " Call list_apps to see every installed app instead of guessing.")
            }
        } else {
            guard let front = ControlTarget.front(else: run?.targetPID) else {
                throw Failure(message: "No app to do it in: name it in “app”.")
            }
            app = front
        }
        let report = await doItHere(goal, app.processIdentifier, caller, run)
        guard report.outcome == .done else { throw Failure(message: report.said) }
        return report.said
    }

    func callWebhook(_ tool: CustomTool, arguments: [String: Any], token: String?) async throws -> String {
        guard CustomTool.isAllowed(tool.url), let url = URL(string: tool.url) else {
            throw Failure(message: "The tool's address is not allowed.")
        }
        guard let text = arguments["text"] as? String else { throw Failure(message: "Missing “text”.") }
        var body: [String: Any] = ["text": text, "tool": tool.name, "source": "skil.li",
                                   "app": NSWorkspace.shared.frontmostApplication?.localizedName ?? ""]
        if let note = arguments["note"] as? String, !note.isEmpty { body["note"] = note }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure(message: "\(tool.name) answered \(status).") }
        let reply = String(decoding: data.prefix(2000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return reply.isEmpty ? "Sent." : reply
    }

    /// One command on `text`, without the card: the answer comes back.
    private func runCommand(_ id: String, on text: String) async throws -> String {
        library.reload()
        guard let command = library.command(id), !command.isAct else {
            throw Failure(message: "No text command “\(id)”; see list_commands.")
        }
        guard let writer = ai.writer(for: command.model) else {
            throw Failure(message: ai.setupMessage(for: command.model))
        }
        let answers = Dictionary(command.questions.map { ($0.id, $0.defaultValue ?? $0.options.first ?? "") }, uniquingKeysWith: { first, _ in first })
        let app = NSWorkspace.shared.frontmostApplication
        let message = AIActionController.message(
            for: command,
            values: AIActionController.values(selection: text, clipboard: NSPasteboard.general.string(forType: .string) ?? "",
                                              app: app?.localizedName ?? "", window: "", profile: library.profile),
            answers: answers,
            selection: text,
            profile: library.profile
        )
        var result = ""
        for try await chunk in writer.engine.stream(AIRequest(message: message, model: writer.choice)) {
            result += chunk
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The menu bar of an app, through Accessibility.
enum MenuReader {
    /// `AXUIElement` is a CF reference, safe to hand between threads.
    struct Item: @unchecked Sendable {
        let path: String
        let components: [String]
        let isEnabled: Bool
        let shortcut: String?
        let element: AXUIElement
    }

    /// Enabled items that may be sent to a decision model
    /// (`MenuCandidates.isShareable`), one per path. Reads Accessibility: call
    /// it off the main thread.
    static func shareableItems(pid: pid_t) -> [Item] {
        var seen = Set<String>()
        return items(pid: pid).filter { item in
            item.isEnabled && MenuCandidates.isShareable(item.components) && seen.insert(item.path).inserted
        }
    }

    static func items(pid: pid_t) -> [Item] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return [] }
        var found: [Item] = []
        // An app slow to answer (a dialog changing folder): what was read in
        // 1.5 s.
        let deadline = ContinuousClock.now + .milliseconds(1_500)
        // The Apple menu (first) is the same in every app.
        for top in children(bar).dropFirst() where ContinuousClock.now < deadline {
            let title = (attribute(top, kAXTitleAttribute) as String?) ?? ""
            guard !title.isEmpty, let menu = children(top).first else { continue }
            collect(menu, path: [title], depth: 0, deadline: deadline, into: &found)
        }
        return found
    }

    private static func collect(_ menu: AXUIElement, path: [String], depth: Int, deadline: ContinuousClock.Instant, into found: inout [Item]) {
        guard depth < 3 else { return }
        for item in children(menu) where ContinuousClock.now < deadline {
            let title = (attribute(item, kAXTitleAttribute) as String?) ?? ""
            guard !title.isEmpty else { continue }
            let itemPath = path + [title]
            if let submenu = children(item).first {
                collect(submenu, path: itemPath, depth: depth + 1, deadline: deadline, into: &found)
                continue
            }
            let enabled = (attribute(item, kAXEnabledAttribute) as Bool?) ?? true
            found.append(Item(path: itemPath.joined(separator: " > "), components: itemPath, isEnabled: enabled, shortcut: shortcut(of: item), element: item))
        }
    }

    static func press(path: String, pid: pid_t) throws {
        let wanted = normalized(path)
        let all = items(pid: pid)
        let matches = all.filter { normalized($0.path) == wanted }
        let candidates = matches.isEmpty ? all.filter { normalized($0.path).hasSuffix(wanted) } : matches
        guard candidates.count == 1, let item = candidates.first else {
            throw SkilliTools.Failure(message: candidates.isEmpty
                ? "No menu item “\(path)”; use search_menus for the exact path."
                : "Several items match “\(path)”: \(candidates.prefix(5).map(\.path).joined(separator: "; ")).")
        }
        guard item.isEnabled else { throw SkilliTools.Failure(message: "“\(item.path)” is disabled right now.") }
        guard AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success else {
            throw SkilliTools.Failure(message: "The app did not choose “\(item.path)”.")
        }
    }

    private static func normalized(_ path: String) -> String {
        path.lowercased()
            .replacingOccurrences(of: "...", with: "…")
            .components(separatedBy: ">")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ">")
    }

    private static func shortcut(of item: AXUIElement) -> String? {
        guard let key: String = attribute(item, kAXMenuItemCmdCharAttribute), !key.isEmpty else { return nil }
        let modifiers = (attribute(item, kAXMenuItemCmdModifiersAttribute) as Int?) ?? 0
        // kAXMenuItemModifier bits: 1 shift, 2 option, 4 control, 8 no command.
        var text = ""
        if modifiers & 4 != 0 { text += "⌃" }
        if modifiers & 2 != 0 { text += "⌥" }
        if modifiers & 1 != 0 { text += "⇧" }
        if modifiers & 8 == 0 { text += "⌘" }
        return text + key
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self {
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (unsafeDowncast(value, to: AXUIElement.self) as! T)
        }
        return value as? T
    }
}
