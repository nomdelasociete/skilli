import AppKit
import Carbon.HIToolbox
import ImageIO
import SkilliCore

/// The launcher: one Liquid Glass block, search on top and results below a
/// hairline, inside a clear margin that leaves room for the glass shadow.
///
/// Built once at launch and kept off screen. Showing it is a reposition +
/// order front; nothing is allocated on the hot path. Layout uses fixed frames
/// so showing never triggers an Auto Layout pass.
@MainActor
final class LauncherController: NSObject {
    private enum Layout {
        static let width: CGFloat = 700
        static let searchHeight: CGFloat = 60
        static let headerHeight: CGFloat = 34
        static let rowHeight: CGFloat = 46
        static let visibleRows = 8
        static let footerHeight: CGFloat = 44
        static let listBottomPadding: CGFloat = 6
        /// The GitHub strip under the search field, when it shows.
        static let stripHeight: CGFloat = 32
        static let resultLimit = 50
        /// The list beside a preview (Clipboard History, Search Snippets).
        static let splitListWidth: CGFloat = 290

        static var listHeight: CGFloat { CGFloat(visibleRows) * rowHeight }
        static var cardHeight: CGFloat { headerHeight + listHeight + listBottomPadding + 1 + footerHeight }
        static var height: CGFloat { cardHeight + 1 + searchHeight }
        static var windowSize: NSSize {
            NSSize(width: width + 2 * Theme.glassMargin, height: height + 2 * Theme.glassMargin)
        }
    }

    let index: AppIndex
    private let usage: UsageStore
    private let learning: LearningStore
    private let panel = LauncherPanel(size: Layout.windowSize)
    private let searchField = NSTextField()
    let tableView = NSTableView()
    private let sectionHeader = NSTextField(labelWithString: "")
    /// "Selected: “…” · ⇥ asks about it": what Tab will work on.
    private let selectionLabel = NSTextField(labelWithString: "")
    /// Self-test hook: the selection the launcher shows.
    private(set) var shownSelection: String? {
        // Made once: quicklink rows read it on every key.
        didSet { selectionQuery = Quicklink.query(fromSelection: shownSelection) }
    }
    /// The selection as a quicklink's query (`Quicklink.query(fromSelection:)`).
    private var selectionQuery: String?
    /// Counts the shows: a selection read for an earlier one is dropped.
    private var selectionShow = 0
    private let emptyState = NSTextField(labelWithString: "No results")
    /// Beside the empty line while ⇥ searches the history by meaning.
    private let meaningSpinner = NSProgressIndicator()
    private let hints = HintBar()
    /// One line in the footer's place: what failed and what to do (rule 6:
    /// never a bare beep), until the next key.
    private let footerNote = NSTextField(labelWithString: "")
    private(set) var results: [LauncherItem] = []
    private var glassViews: [NSGlassEffectView] = []
    /// Clicks in other apps close the launcher, like losing focus would.
    private var outsideClickMonitor: Any?

    /// Runs a built-in command picked in the launcher (it hides right after).
    var onCommand: ((LauncherCommand.ID) -> Void)?
    /// Kill Process: the last `ps`, and what listens on ports asked about.
    private var processes: [ProcessListing.Entry] = []
    private var portRows: [Int: [Processes.Row]] = [:]
    /// A mode's name sits as a chip before the field, which then holds only
    /// the filter: Kill (a name or a port), Clipboard (words).
    enum Mode {
        case kill
        case clipboard
        case emoji
        /// Search GIFs ("gif "): Klipy's and the ones on this Mac, a grid.
        case gifs
        case windows
        case tabs
        case files
        case projects
        /// Filling a skillie's arguments, one after the other.
        case script
        case history
        case brew
        case contacts
        case agenda
        case reminders
        case github
        /// Everything skil.li does ("?").
        case catalog
        /// The user's snippets ("snip "): by name, or by meaning with ⇥.
        case snippets
        /// The menu items of the app in front ("m "), by name.
        case menus
        /// The recordings made ("recs "): by title, date, attendees, then
        /// the words said.
        case recordings
    }

    private(set) var mode: Mode?
    /// What esc puts back as it leaves the mode: the field as it was
    /// before it. Nil when the mode was opened straight (✦C, the menu bar,
    /// a link): back is the app, esc closes.
    private var modeBack: String?
    /// The field's words outside the modes, as the last search read them:
    /// `modeBack` when a prefix or an alias turns them into a mode.
    private var rootQuery = ""
    private var killMode: Bool { mode == .kill }
    private var clipboardMode: Bool { mode == .clipboard }
    /// The app unfolded with Tab: its processes one by one.
    private var unfolded: String?
    private let modeChip = ModeChip(title: "Kill", color: .systemRed)
    /// The cup and the time left at the right of the empty field while the
    /// Mac is kept awake.
    private let awakeChip = AwakeChipView()
    /// While it shows and the Mac is kept awake for a while: the time left
    /// counted down on the chip and the running row.
    private var awakeTicks: Timer?
    private var fieldFrame: NSRect = .zero
    /// Self-test hooks.
    var isKilling: Bool { killMode }
    var isInClipboard: Bool { clipboardMode }
    /// Clipboard history: the rows for a filter, newest first.
    var clipboardItems: ((String) -> [ClipboardStore.Item])?
    /// Pastes, pastes as plain text or copies a row, after the launcher hid.
    var onClip: ((ClipboardStore.Item, ClipboardHistory.Use) -> Void)?
    /// ⌘⌫ (or ⌘K → Forget) on a copy: gone at once, ⌘Z brings it back.
    var onDeleteClip: ((ClipboardStore.Item) -> Void)?
    /// Why the history shows nothing ("off in Settings"), when it is not
    /// just empty.
    var clipboardStatus: (() -> String?)?
    /// Snippets, found by name, keyword or words; Return types one in the
    /// app in front, ⌘Return copies it.
    var snippets: (() -> [Snippet])?
    var onSnippet: ((Snippet, _ copy: Bool) -> Void)?
    /// Search Snippets: ⇥ asks the decision model which snippet fits what
    /// is typed ("my iban"); whether it can (Settings → Snippets, a key).
    /// `maybe`: none fits, but "none" narrowly won over that snippet.
    var snippetMeaningAvailable: (() -> Bool)?
    var snippetMeaning: ((String) async -> (snippets: [Snippet], maybe: Snippet?, label: String)?)?
    /// Search Snippets' preview: the snippet as the expander would type it
    /// now, and the variables it cannot fill without asking.
    var snippetPreviewPieces: ((Snippet) -> (pieces: [Snippet.Piece], unfilled: Set<PromptTemplate.Variable>))?
    /// When keywords expand now, said in the preview ("After a space or
    /// ↩", "Off", "Not in 1Password"); read as the mode opens.
    var snippetExpands: (() -> String)?
    /// A snippet file's date, as the library last read its folder.
    var snippetModified: ((Snippet) -> Date?)?
    private var snippetList: [Snippet] = []
    private let snippetPreview = SnippetPreviewView()
    /// As the mode opened: the Expands line, the snippets' shortcuts.
    private var snippetExpandsLine: String?
    private var snippetShortcuts: [String: [Chord]] = [:]
    /// Search Menu Items: the app in front as the mode opened, its enabled
    /// items once read (nil while reading), prepared for every key.
    private var menuApp: NSRunningApplication?
    private var menuItems: [MenuReader.Item] = []
    private var menuCandidates: [MenuSearch.Candidate]?
    private var menuTask: Task<Void, Never>?
    private var snippetMeaningOn = false
    private var snippetFound: (query: String, snippets: [Snippet], maybe: Snippet?, label: String)?
    private var snippetMeaningPending: String?
    private var snippetMeaningTask: Task<Void, Never>?
    /// Self-test hooks.
    var isInSnippets: Bool { mode == .snippets }
    var snippetsPreview: SnippetPreviewView { snippetPreview }
    var isShowingSnippetMeaning: Bool { snippetFound?.query == searchField.stringValue }
    /// Nothing picked by meaning, one dimmed "maybe?" row instead: never
    /// selected by itself (↓ selects it, ↩ then types it).
    var isShowingSnippetMaybe: Bool {
        mode == .snippets && isShowingSnippetMeaning && snippetFound?.snippets.isEmpty == true && snippetFound?.maybe != nil
    }
    /// The "maybe?" row's place: after the "Allow …" rows, which stay
    /// as they are (the first of them selected, as always).
    private var snippetMaybeRow: Int? {
        guard isShowingSnippetMaybe, let maybe = snippetFound?.maybe else { return nil }
        return results.firstIndex { if case .snippet(let snippet) = $0 { snippet.id == maybe.id } else { false } }
    }
    /// The calculator's answer: typed in the app in front (↩, like a clip,
    /// a snippet or an emoji: D4) or copied (⌘↩, ⌘C).
    var onCalculation: ((Calculator.Result, _ paste: Bool) -> Void)?
    /// What currencies convert with; nil while Convert Currencies is off.
    var currency: () -> CurrencyContext? = { nil }
    /// Emoji: found by name, or by feeling (the decision model); Return
    /// types one in the app in front, ⌘Return copies it.
    var emojiSearch: ((String) -> EmojiList)?
    var emojiByFeeling: ((String) async -> (emoji: [Emoji], label: String)?)?
    /// `saidAs`: the words it was found by meaning with, when it was.
    var onEmoji: ((Emoji, _ copy: Bool, _ saidAs: String?) -> Void)?
    /// The skin tone emoji are shown and typed in (Settings → Launcher).
    var emojiTone: () -> EmojiSkinTone = { .standard }
    /// The keys that type a symbol on the user's own layout ("⌥⇧K" for the
    /// Apple logo on U.S.), said beside its name: next time, no picker.
    var typingKeys: ((String) -> String?)?
    /// Search GIFs: Klipy asked from this Mac, Recently Used, the GIFs on
    /// this Mac by name; Return pastes one in the app in front.
    var gifLibrary: GIFLibrary?
    /// `query`: the words that found it (Klipy counts a share with them).
    var onGIF: ((GIF, GIFUse, _ query: String) -> Void)?
    /// The editors' bundle ids: a Klipy GIF goes there as Markdown.
    var gifEditors: Set<String> = []
    /// Where "On this Mac" looks: the home folder; the self-test's own.
    var gifFolder: URL?
    /// Saved window layouts, found by name; "save layout X" saves one.
    var windowLayouts: (() -> [SavedWindowLayout])?
    var onLayout: ((SavedWindowLayout) -> Void)?
    var onSaveLayout: ((String) -> Void)?
    /// ⌘K on a layout: open it in the editor, take it anew from the
    /// windows open, delete it (the card asks first).
    var onEditLayout: ((SavedWindowLayout) -> Void)?
    var onUpdateLayout: ((SavedWindowLayout) -> Void)?
    var onDeleteLayout: ((SavedWindowLayout) -> Void)?
    /// Every window open now (Switch Window), and bringing one forward.
    var openWindows: (() -> [WindowArranger.OpenWindow])?
    var onFocusWindow: ((WindowArranger.OpenWindow) -> Void)?
    private var windowList: [WindowArranger.OpenWindow] = []
    private var tabList: [BrowserTabs.Tab] = []
    var isInTabs: Bool { mode == .tabs }
    /// The editors' recent projects; Return opens one, ⌘Return shows it.
    var projects: (() -> [EditorProject])?
    var onOpenProject: ((EditorProject, _ reveal: Bool) -> Void)?
    private var projectList: [EditorProject] = []
    var isInProjects: Bool { mode == .projects }
    /// Skillies: listed by name, run with their arguments.
    var scripts: (() -> [ScriptCommand])?
    var scriptInline: ((ScriptCommand) -> String?)?
    var refreshInlineScripts: ((@escaping @MainActor () -> Void) -> Void)?
    var onRunScript: ((ScriptCommand, [String]) -> Void)?
    private(set) var scriptInput: (command: ScriptCommand, values: [String])?
    var isInScript: Bool { mode == .script }
    /// Search Browser History: words in titles and addresses as you type;
    /// ⇥ by meaning. Return opens the page in its browser, ⌘Return copies.
    var historySource = BrowserHistory.Source()
    /// Safari is here but its history is behind Full Disk Access: the
    /// History mode offers to turn it on (read once as the mode opens).
    private var historyNeedsDiskAccess = false
    var historyByMeaningAvailable: (() -> Bool)?
    var historyDecisionKeys: (() -> [DecisionProvider: String])?
    var onOpenVisit: ((HistoryVisit, _ copy: Bool) -> Void)?
    private var historyTask: Task<Void, Never>?
    private var historyResults: (query: String, visits: [HistoryVisit])?
    private var historyMeaning: (query: String, visits: [HistoryVisit], label: String)?
    private var historyMeaningPending: String?
    private var historyMeaningTask: Task<Void, Never>?
    private var historyMeaningOn = false
    var isInHistory: Bool { mode == .history }
    /// Homebrew: names as you type, installed ones with their updates.
    var homebrew: Homebrew?
    /// The user's contacts ("@jean", and the best ones in any search).
    var contacts: ContactBook?
    /// Return on a contact: its card; ⌘Return: the Contacts app.
    var onShowContact: ((ContactRecord) -> Void)?
    private var contactResults: (query: String, matches: [ContactSearch.Match])?
    private var contactTask: Task<Void, Never>?
    /// The user's calendars: the next meeting first when it is about to
    /// start, the Agenda mode.
    var calendar: CalendarBook?
    /// The next meeting, a day, or free time in the card.
    var onShowAgenda: ((AgendaRequest) -> Void)?
    /// An event in the card, with what can be done with it (⇥ in Agenda).
    var onShowEvent: ((AgendaEvent) -> Void)?
    /// Adds a said event, then the card shows it (⌘Z takes it back).
    var onCreateEvent: ((EventRequest) -> Void)?
    /// Asks in the card before deleting an event (⌘⌫ in Agenda).
    var onDeleteEvent: ((AgendaEvent) -> Void)?
    /// The user's reminders: quick add in any search, the Reminders mode.
    var reminders: ReminderBook?
    /// Adds a said reminder, then the card shows it (⌘Z takes it back).
    var onAddReminder: ((ReminderRequest) -> Void)?
    /// The user's GitHub: the GitHub mode and the strip under the field.
    var github: GitHubBook?
    /// Shows the strip under the field (Settings → GitHub), once signed in.
    var showsGitHubStrip: () -> Bool = { false }
    /// A pull request's action picked in ⌘K that the card carries out
    /// ("Squash and Merge" asks again, "Update Branch", "Checks").
    var onPullRequestAction: ((PullRequest, String) -> Void)?
    /// Settings → GitHub (signing in).
    var onGitHubSettings: (() -> Void)?
    /// The GitHub mode shows only this group (a click on it in the strip).
    private var githubGroup: PullRequestGroup?
    private let githubStrip = GitHubStripView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.stripHeight))
    private let stripHairline = HairlineView(frame: NSRect(x: 16, y: 0, width: Layout.width - 32, height: 1))
    private var stripShown = false
    private var glassContent: NSView?
    private var searchBar: NSView?
    /// Where the user dragged the launcher; nil until then (or once put
    /// back), and it opens in the middle.
    var savedPlace: () -> LauncherPlace? = { nil }
    /// The user dragged it somewhere else; nil when back on its standard
    /// place.
    var onPlaceChange: ((LauncherPlace?) -> Void)?
    /// The lines a drag pulls the glass onto.
    private let guides = LauncherGuides()
    /// Self-test hook: the guides on screen while it is dragged.
    var shownGuides: [LauncherGuide] { guides.shown }
    /// A reminder's action picked in ⌘K that the card carries out
    /// ("Tomorrow", "Pick a Date…" asks when…).
    var onReminderAction: ((ReminderItem, String) -> Void)?
    /// A short line once something is done out of sight, or failed.
    var onNotice: ((String) -> Void)?
    /// A reminder changed where it is: an undo card still up (a delete)
    /// goes, ⌘Z is the launcher's.
    var onChangedInPlace: (() -> Void)?
    /// ⌘K → Move to Trash on a file, done: where it was, where the Trash
    /// keeps it (the undo card's ⌘Z moves it back).
    var onMovedToTrash: ((_ original: URL, _ trashed: URL) -> Void)?
    /// What failed once the launcher is gone, in one line, long enough to
    /// read ("TextEdit did not choose File › Export as PDF…").
    var onFailure: ((String) -> Void)?
    /// ⌘K → Uninstall… on an app: the card lists it and its leftovers.
    var onUninstall: ((URL) -> Void)?
    /// ⌘K → Set Shortcut… on an app: its keys recorded at once (the
    /// action, the app's name).
    var onSetShortcut: ((SkilliAction, String) -> Void)?
    /// The user's aliases ("e" + space: Emoji); set with ⌘K → Set Alias….
    var aliases: () -> [LauncherAlias] = { [] }
    /// An alias set for an item ("" removes it): its id, its title, the alias.
    var onSetAlias: ((_ id: String, _ title: String, _ alias: String) -> Void)?
    /// Item id → alias, read once per search for the rows.
    private var aliasByID: [String: String] = [:]
    /// Items pinned with ⌘K → Pin (`LauncherItem.learningID`), in the
    /// order pinned: first in the empty field, a boost when they fit what is
    /// typed.
    var pins: () -> [String] = { [] }
    /// The pins changed: one pinned or unpinned, or gone for good.
    var onPinsChange: (([String]) -> Void)?
    /// The pins for this show, read once: a key only looks them up.
    private var pinsAsShown: (list: [String], ids: Set<String>)?
    private var pinsNow: (list: [String], ids: Set<String>) {
        if let pinsAsShown { return pinsAsShown }
        let list = pins()
        let read = (list, Set(list))
        pinsAsShown = read
        return read
    }
    /// Pinned items the last catalog read found (Mac commands, System
    /// Settings panes, skillies, quicklinks, layouts, snippets, the user's
    /// commands): the empty field shows them at once, from memory.
    private var pinnedFound: [String: LauncherItem] = [:]
    /// What ↑ brings back in the empty field: the searches acted on.
    let recentSearches: RecentSearchStore
    /// The recent search ↑ put in the field, while it is left as it is.
    private var recalled: Int?
    /// Settings → Launcher: which screen it opens on, and when it opens
    /// empty again.
    var screenChoice: () -> LauncherScreen = { .pointer }
    var resetChoice: () -> LauncherReset = { .immediately }
    /// The launcher as it closed: the words, the mode (a skillie's
    /// arguments so far), the row selected.
    private struct Kept {
        let mode: Mode?
        /// Where esc goes from that mode (`modeBack`).
        let back: String?
        let text: String
        let script: (command: ScriptCommand, values: [String])?
        let row: Int
        let rowID: String?
        let rowTitle: String?
        var closedAt: ContinuousClock.Instant
    }

    private var kept: Kept?
    /// Self-test hook: the alias each row shows.
    var shownAliases: [String?] { results.map { aliasByID[$0.learningID] } }
    /// The keycaps at the rows' right edge as drawn (a snippet's keyword),
    /// and the alias keycaps after their names.
    var shownTrailingKeycaps: [String?] {
        results.indices.map { (tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? ResultCellView)?.trailingText }
    }
    var shownAliasCaps: [String?] {
        results.indices.map { (tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? ResultCellView)?.aliasText }
    }
    var shownMaybeMarks: [Bool] {
        results.indices.map { (tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? ResultCellView)?.isMaybe ?? false }
    }
    /// Where ⌘K's links go (Messages, Phone, mail); self-tests keep them.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// ⌘K's list over the results.
    private let actionPanel = ActionPanelView()
    /// The footer under the results, put back as ⌘K's list closes.
    private var footerBeforeActions: [(label: String, key: String)]?
    /// The row ⌘K's list is for (⌘C there copies its title when it has
    /// nothing else to copy).
    private var actionsItem: LauncherItem?
    /// Asks in the card before deleting a reminder (⌘⌫).
    var onDeleteReminder: ((ReminderItem) -> Void)?
    /// Reminders: open ones and those done this week, each prepared for
    /// matching (title, list, notes).
    private var reminderEntries: [(item: ReminderItem, candidates: [FuzzyCandidate])]?
    /// The reminder as it was before Tomorrow or Next Week, and when: ⌘Z
    /// puts it back for 10 s, while the launcher is open.
    private var reminderUndo: (item: ReminderItem, at: ContinuousClock.Instant)?
    /// Agenda: the coming three months, read when it opens, each with its
    /// title, calendar, place and invitees prepared for matching.
    private var agendaEvents: [(event: AgendaEvent, candidates: [FuzzyCandidate])]?
    var onBrew: ((Homebrew.Action, BrewPackage?) -> Void)?
    private var brewOutdated: [String: (installed: String, current: String)] = [:]
    private var brewTask: Task<Void, Never>?
    var isInBrew: Bool { mode == .brew }
    var isShowingHistoryMeaning: Bool { historyMeaning?.query == searchField.stringValue }
    /// Search Files: Spotlight by name as you type; ⇥ by meaning.
    private var fileSearchTask: Task<Void, Never>?
    private var fileResults: (query: String, files: [FileSearch.File])?
    private var fileMeaning: (query: String, files: [FileSearch.File], label: String)?
    private var fileMeaningPending: String?
    private var fileMeaningTask: Task<Void, Never>?
    var filesByMeaningAvailable: (() -> Bool)?
    var fileDecisionKeys: (() -> [DecisionProvider: String])?
    private var fileMeaningOn = false
    private var fileIcons: [String: NSImage] = [:]
    var isInFiles: Bool { mode == .files }
    var isInRecordings: Bool { mode == .recordings }
    var isShowingFileMeaning: Bool { fileMeaning?.query == searchField.stringValue }
    private var appIconsByPath: [String: NSImage] = [:]
    var isInWindows: Bool { mode == .windows }
    /// Timers: "timer 10 min pâtes" starts one; running ones show when
    /// "timer" is typed, and Return cancels.
    var runningTimers: (() -> [TimerCenter.Running])?
    var timerRemaining: ((TimerCenter.Running) -> Int)?
    var onStartTimer: ((TimerRequest) -> Void)?
    /// "awake 1 hour": keeps the Mac awake for that long.
    var onKeepAwake: ((AwakeRequest) -> Void)?
    /// Whether the Mac is kept awake now, and until when (nil: until let
    /// sleep): the chip in the empty field, the running row for "awake".
    var awakeState: () -> (awake: Bool, until: Date?) = { (false, nil) }
    var onCancelTimer: ((TimerCenter.Running) -> Void)?
    /// "rec Weekly sync": the Record card with that name.
    var onRecord: ((String) -> Void)?
    /// The recording on now, for its row ("rec", "recording…").
    var recordingState: () -> LauncherRecording? = { nil }
    /// Its row's ↩ and ⌘K: stop, pause, resume; its folder.
    var onRecordingControl: ((SkilliLink.RecordingControl) -> Void)?
    var onShowRecordingFolder: (() -> Void)?
    /// ⌘R on a meeting's row (on now or starting soon): its label ("Record",
    /// "Record (in person)"), nil when not offered (a recording on); and
    /// what it does (records, and joins its call when not joined yet).
    var recordLabel: (AgendaEvent) -> String? = { _ in nil }
    var onRecordMeeting: ((AgendaEvent) -> Void)?
    /// The recordings made, from memory (titles, dates, attendees), newest
    /// first; the words said, searched off the main thread.
    var recordingSummaries: (() -> [RecordingSummary])?
    var searchRecordingWords: ((String) async -> [(folder: String, snippet: String)])?
    /// Search Recordings opened: the list read again.
    var onRecordingsMode: (() -> Void)?
    /// A recording's window, its folder in Finder, its transcript copied,
    /// it to the Trash (⌘Z), by its folder's name.
    var onOpenRecording: ((String) -> Void)?
    var onShowRecordingFolderNamed: ((String) -> Void)?
    var onCopyRecordingTranscript: ((String) -> Void)?
    var onDeleteRecording: ((RecordingSummary) -> Void)?
    /// Ask about a meeting (phase 5): its folder's name and the question,
    /// answered in the card by `recordingProvider` ("Claude").
    var onAskAboutRecording: ((String, String) -> Void)?
    /// A recording's row → Rename Recording…: its folder's name, the title typed.
    var onRenameRecording: ((String, String) -> Void)?
    var recordingProvider: () -> String = { WritingProvider.claude.title }
    /// Search Recordings' words said, for the text typed.
    private var recordingWords: (query: String, found: [(folder: String, snippet: String)])?
    private var recordingWordsTask: Task<Void, Never>?
    /// Quicklinks: "g skilli" opens Google's results.
    var quicklinks: (() -> [Quicklink])?
    var onOpenURL: ((URL) -> Void)?
    /// The launcher is up, after its first frame (Type in English while
    /// open switches the input source then), and it closed.
    var onOpened: (() -> Void)?
    var onClosed: (() -> Void)?
    /// A key with ⌘ or ⌃ as the user's own layout reads it, while the
    /// launcher types in English (`EnglishTyping.chordEvent`).
    var chordEvent: ((NSEvent) -> NSEvent)?
    /// A skillie's place in its folder, for its link ("tools/deploy.sh").
    var skilliePath: (String) -> String = { ($0 as NSString).lastPathComponent }
    /// A decision key is saved: ⇥ can find emoji by feeling.
    var emojiByFeelingAvailable: (() -> Bool)?
    private var feelingAvailable = false
    private var feeling: (query: String, emoji: [Emoji], label: String)?
    private var feelingPending: String?
    private var feelingTask: Task<Void, Never>?
    private var emojiImages: [String: NSImage] = [:]
    /// Self-test hooks.
    var isInEmoji: Bool { mode == .emoji }
    var isShowingFeeling: Bool { feeling != nil && feeling?.query == searchField.stringValue }
    /// Clipboard mode opened: the history may need its permission.
    var onClipboardMode: (() -> Void)?
    var clipboardImageURL: ((ClipboardStore.Item) -> URL?)?
    /// ⇥ in the history: the copies a decision model finds for what was
    /// typed, as a person would describe it. Nil: no key, or it failed.
    var clipboardMeaning: ((String) async -> ClipboardHistory.MeaningResult?)?
    /// Whether ⇥ can search by meaning (Settings → Clipboard, and a key).
    var clipboardMeaningAvailable: (() -> Bool)?
    private var meaningAvailable = false
    /// What ⇥ found, for the text it was asked about.
    private var meaning: (query: String, result: ClipboardHistory.MeaningResult)?
    private var meaningTask: Task<Void, Never>?
    private var meaningPending: String?
    /// While ⇥ waits, the list is one line, "Searching by meaning…", with
    /// a spinner: the copies found by the words are not the answer.
    private var isSearchingClipboardMeaning: Bool {
        clipboardMode && meaningPending != nil && meaningPending == searchField.stringValue
    }
    private let clipPreview = ClipboardPreviewView()
    /// The emoji picker, eight across, in the list's place.
    private let emojiGrid = EmojiGridView(frame: NSRect(x: 0, y: Layout.footerHeight + 1 + Layout.listBottomPadding,
                                                        width: Layout.width, height: Layout.listHeight))
    /// Browsing emoji: the groups' runs (Recently Used, Unicode's groups).
    private var emojiSections: [EmojiList.Section] = []
    /// The selected emoji's name, right of the header, in the picker.
    private let emojiName = NSTextField(labelWithString: "")
    /// Self-test hooks: the grid as shown.
    var isShowingEmojiGrid: Bool { !emojiGrid.isHidden }
    /// The selected one's names and keys, right of the picker's header.
    var emojiNameText: String { emojiName.stringValue }
    var emojiGridView: EmojiGridView { emojiGrid }
    /// Search GIFs, four across, in the list's place.
    private let gifGrid = GIFGridView(frame: NSRect(x: 0, y: Layout.footerHeight + 1 + Layout.listBottomPadding,
                                                    width: Layout.width, height: Layout.listHeight))
    private var gifSections: [EmojiList.Section] = []
    /// Nothing typed: Recently Used and Klipy's Trending; nil while read.
    private var gifBrowse: (recent: [GIF], trending: [GIF], klipyFailed: Bool)?
    /// What each search found, for the mode's life: backspacing shows the
    /// earlier words' GIFs again, nothing asked.
    private var gifFound: [String: (klipy: [GIF], mac: [GIF], klipyFailed: Bool)] = [:]
    private var gifPending: String?
    private var gifTask: Task<Void, Never>?
    private var gifBrowseTask: Task<Void, Never>?
    /// The app in front as the mode opened: a terminal or an editor takes
    /// Klipy's GIFs as Markdown.
    private(set) var gifFrontApp: String?
    /// Self-test hooks.
    var isInGIFs: Bool { mode == .gifs }
    var isShowingGIFGrid: Bool { !gifGrid.isHidden }
    var gifGridView: GIFGridView { gifGrid }
    /// The words a GIF was found with (Klipy counts a share with them).
    var gifQuery: String { searchField.stringValue.trimmingCharacters(in: .whitespaces) }
    var isSearchingGIFs: Bool { gifPending != nil || (mode == .gifs && gifBrowse == nil) }
    private var listScroll: NSScrollView?
    /// Self-test hooks: the preview, and whether rows came by meaning.
    var clipboardPreview: ClipboardPreviewView { clipPreview }
    var isShowingMeaning: Bool { meaning != nil && meaning?.query == searchField.stringValue }
    var isShowingMeaningSpinner: Bool { !meaningSpinner.isHidden }
    var emptyStateText: String? { emptyState.isHidden ? nil : emptyState.stringValue }
    private var thumbnails: [Int64: NSImage] = [:]
    private var appIcons: [String: NSImage] = [:]
    private var processRefresh: Task<Void, Never>?
    /// Mac commands with their title now ("Turn Off Keep Awake" while kept
    /// awake).
    var systemCommands: (() -> [(command: MacAction, title: String)])?
    var onSystemCommand: ((MacAction) -> Void)?
    /// ⌘K on a shortcut's row: run with the text selected where the
    /// launcher opened; its editor in Shortcuts.
    var onRunShortcut: ((AppleShortcut, ShortcutInput) -> Void)?
    var onEditShortcut: ((AppleShortcut) -> Void)?
    /// ⌘K on a clipboard image or a file found: a linked app's command on
    /// it (Pin in CleanShot), under the action's title.
    var onOpenFile: ((URL, AppLinkCommand, String) -> Void)?
    /// The launcher opens: what its rows come from may be read again, off
    /// the main thread (Wi-Fi, Bluetooth).
    var onShow: (() -> Void)?
    /// Bluetooth may not be used yet and macOS can still be asked: typing
    /// about it offers to allow it. Read once per show.
    var bluetoothAskable: (() -> Bool)?
    /// Permissions to show first, under the search field, until granted.
    var missingPermissions: (() -> [Permission])?
    /// Read once per show: macOS's permission checks (and a folder) are
    /// never asked on a key.
    private var missingAsShown: [Permission]?
    private var missingNow: [Permission] {
        if let missingAsShown { return missingAsShown }
        let read = missingPermissions?() ?? []
        missingAsShown = read
        return read
    }
    /// Calendar allowed, or never asked (events can be added): read once
    /// per show, not on every key.
    private var calendarAsShown: Bool?
    private var calendarUsable: Bool {
        if let calendarAsShown { return calendarAsShown }
        let read = calendar.map { $0.isAllowed || $0.canAsk } ?? false
        calendarAsShown = read
        return read
    }
    /// Quits an app with its processes (or one process), after the card
    /// confirms; `force` is ⇧Return.
    var onQuitProcess: ((ProcessListing.Group, Bool) -> Void)?
    /// An "Allow …" row: the setup window for Accessibility, else asked
    /// right there (`Permission.askedFrom`), once the launcher hid.
    var onSetup: ((Permission) -> Void)?
    /// What the user made, for the Catalog ("?"): read as it opens.
    var catalogInput: (() -> FeatureCatalog.Input)?
    /// Each action's first shortcut, by the action's id (`SkilliAction.id`):
    /// the Catalog's keycaps, read as it opens.
    var shortcutKeys: (() -> [String: [Chord]])?
    /// Runs a shortcut's action after the launcher hid (a text transform,
    /// Ask by Voice or Dictate from the Catalog).
    var onAction: ((SkilliAction) -> Void)?
    /// Opens a pane of Settings (⌘K → Set Shortcut… opens Keys), at one of
    /// its parts when named ("quicklinks").
    var onSettingsPane: ((SettingsPane, _ section: String?) -> Void)?
    /// The Catalog's entries turned off in Settings → Catalog: their rows
    /// leave the results, the "?" lists them dimmed. Read once per show.
    var catalogOff: () -> Set<String> = { [] }
    private var offAsShown: Set<String>?
    /// What is off for this show.
    private var off: Set<String> {
        if let offAsShown { return offAsShown }
        let read = catalogOff()
        offAsShown = read
        return read
    }
    /// The Catalog as it opened: every entry, what the user made, each
    /// entry's launcher row and the shortcuts.
    private var catalogEntries: [CatalogEntry] = []
    private var catalogMade = FeatureCatalog.Input()
    private var catalogItems: [String: LauncherItem] = [:]
    private var catalogShortcuts: [String: [Chord]] = [:]
    /// Each row's keycaps, built once per Catalog and moved between the
    /// cells that show it; rebuilt when its keys change (an alias set).
    private var catalogCaps: [String: (keys: [[String]], caps: [[KeycapView]])] = [:]
    /// The list shows group headers: their rows are shorter.
    private var listHasHeaders = false
    var isInCatalog: Bool { mode == .catalog }
    /// The user's commands to list (re-read on each search: they are files).
    var siCommands: (() -> [LauncherSICommand])?
    /// Runs one of the user's commands on the app that was in front, after
    /// the launcher hid; Ask gets the typed text as its instruction.
    var onSICommand: ((_ id: String, _ instruction: String?) -> Void)?

    /// Where the time of the last `show` went, for the benchmark.
    struct ShowPhases {
        let results: Duration
        let order: Duration
        let draw: Duration
    }

    private(set) var lastShowDuration: Duration?
    private(set) var lastShowPhases: ShowPhases?
    private(set) var lastSearchDuration: Duration?
    /// Where the last search's time went (self-test, perf log).
    private(set) var lastSearchLaps = Laps()

    /// Learned picks below this bonus do not surface non-matching results.
    private static let learnedOnlyThreshold = 18

    init(index: AppIndex, usage: UsageStore, learning: LearningStore, recentSearches: RecentSearchStore) {
        self.index = index
        self.usage = usage
        self.learning = learning
        self.recentSearches = recentSearches
        super.init()
        buildViews()
    }

    var isVisible: Bool { panel.isVisible }
    var topResultName: String? { results.first?.title }
    /// Self-test hook: the icon the top result row shows.
    var topResultIcon: NSImage? {
        guard case .app(let entry) = results.first else { return nil }
        return index.icon(for: entry)
    }
    var query: String { searchField.stringValue }
    /// Self-test hook: the last row's title (Ask “…” when text is typed).
    var lastResultTitle: String? { results.last?.title }
    /// Self-test hook: the selected row's title.
    var selectedResultTitle: String? {
        results.indices.contains(tableView.selectedRow) ? results[tableView.selectedRow].title : nil
    }
    /// Self-test hooks: the selected row's id, which rows drawn show the
    /// pin, and a launcher closed that long ago (Starts again empty).
    var selectedResultID: String? {
        results.indices.contains(tableView.selectedRow) ? results[tableView.selectedRow].learningID : nil
    }
    var shownPinned: [Bool] {
        (0..<tableView.numberOfRows).map { (tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? ResultCellView)?.isPinned ?? false }
    }
    func pretendClosed(for duration: Duration) {
        kept?.closedAt = .now - duration
    }
    /// Self-test hook: the field's caret, or what is selected in it.
    var fieldSelection: NSRange? { searchField.currentEditor()?.selectedRange }
    /// Self-test hook: the field's words all selected (kept ones are).
    var fieldTextSelected: Bool {
        !searchField.stringValue.isEmpty && searchField.currentEditor()?.selectedRange == NSRange(location: 0, length: (searchField.stringValue as NSString).length)
    }

    /// Forces window server backing and first layout so the first real show
    /// is as fast as every later one.
    func prewarm() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        // A first search too, so the first key typed pays for nothing new.
        updateResults(query: "s")
        panel.displayIfNeeded()
        updateResults(query: "")
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func toggle(triggeredAt: ContinuousClock.Instant) {
        if isVisible {
            hide()
        } else {
            show(triggeredAt: triggeredAt)
        }
    }

    /// GitHub straight away, one group only when `group` is set (a click
    /// in the strip).
    func openGitHub(group: PullRequestGroup? = nil) {
        if !isVisible { show(triggeredAt: .now, keeping: { $0 == .github }) }
        if mode == .github {
            githubGroup = group
            searchField.stringValue = ""
            updateResults(query: "")
        } else {
            enterMode(.github, filter: "")
            // Opened straight: esc goes back to the app.
            modeBack = nil
            githubGroup = group
            updateResults(query: "")
        }
    }

    /// The reminders straight away (the menu bar's reminders).
    func openReminders() {
        if !isVisible {
            show(triggeredAt: .now, keeping: { $0 == .reminders })
            // Opened again on them, as kept.
            if mode == .reminders { return }
        }
        enterMode(.reminders, filter: "")
        modeBack = nil
    }

    /// The agenda straight away (the menu bar's next meeting).
    func openAgenda() {
        if !isVisible {
            show(triggeredAt: .now, keeping: { $0 == .agenda })
            if mode == .agenda { return }
        }
        enterMode(.agenda, filter: "")
        modeBack = nil
    }

    /// A shortcut straight into a mode: ✦C the clipboard history, ⌃⌘Space
    /// the emoji picker. Again closes it.
    func toggle(into next: Mode, triggeredAt: ContinuousClock.Instant) {
        if isVisible, mode == next {
            hide()
            return
        }
        if !isVisible {
            show(triggeredAt: triggeredAt, keeping: { $0 == next })
            if mode == next { return }
        }
        enterMode(next, filter: "")
        // Opened straight: esc goes back to the app.
        modeBack = nil
    }

    /// A quicklink's shortcut: the launcher with its keyword typed, as its
    /// row picked by name puts it; the text selected, once read, is its
    /// query (its row says so, ↩ searches). One that takes no query opens
    /// its page. Again closes it.
    func toggle(into link: Quicklink, triggeredAt: ContinuousClock.Instant) {
        guard link.takesQuery, !link.keyword.isEmpty else {
            if isVisible { hide() }
            // Out of the event tap: opening may ask the browser for its tabs.
            DispatchQueue.main.async { [weak self] in
                if let url = link.address(for: "") { self?.onOpenURL?(url) }
            }
            return
        }
        let typed = link.keyword + " "
        if isVisible, mode == nil, searchField.stringValue == typed {
            hide()
            return
        }
        if !isVisible { show(triggeredAt: triggeredAt, keeping: { _ in false }) }
        leaveMode(update: false)
        searchField.stringValue = typed
        searchField.currentEditor()?.selectedRange = NSRange(location: (typed as NSString).length, length: 0)
        updateResults(query: typed)
    }

    /// `keeping`: whether what it held when it closed may come back (Settings
    /// → Launcher → Starts again empty), by its mode: a shortcut straight
    /// into a mode takes back only that mode.
    func show(triggeredAt: ContinuousClock.Instant, keeping: (Mode?) -> Bool = { _ in true }) {
        // The GitHub strip as GitHub said last; read again if it is older
        // than 15 s (the answer redraws it).
        let strip = showsGitHubStrip() && github?.isSignedIn == true
        layoutStrip(strip)
        if strip {
            updateGitHubStrip()
            github?.refresh()
        }
        position()
        // What it held as it closed, when Settings → Launcher keeps it that
        // long; else it starts empty, as always.
        let restoring = keptSearch(keeping)
        kept = nil
        recalled = nil
        pinsAsShown = nil
        searchField.stringValue = ""
        offAsShown = nil
        missingAsShown = nil
        calendarAsShown = nil
        // Read again for this show, once the panel is up: the first key
        // does not wait for it. Words kept are found again first with the
        // last read (nothing read on the show path), then it is read anew.
        if restoring == nil { catalog = nil }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            _ = self.currentCatalog()
        }
        onShow?()
        let resultsStart = ContinuousClock.now
        if let restoring {
            restore(restoring)
            catalog = nil
        } else {
            updateResults(query: "")
        }
        // Inline skillies read again when their line is old.
        refreshInlineScripts? { [weak self] in
            guard let self, self.panel.isVisible, self.mode == nil else { return }
            self.updateResults(query: self.searchField.stringValue)
        }
        // Before the panel takes the focus: afterwards Accessibility would
        // point at the search field, not at the user's selection.
        let focused = onSICommand == nil ? nil : SelectionService.focusedElementNow()
        let orderStart = ContinuousClock.now
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        // Words kept: selected, so typing replaces them (as Spotlight does).
        if restoring != nil { searchField.currentEditor()?.selectAll(nil) }
        let drawStart = ContinuousClock.now
        panel.displayIfNeeded()
        let end = ContinuousClock.now

        installOutsideClickMonitor()
        showSelectionPreview(from: focused)
        // Off the show path: once the panel is up.
        DispatchQueue.main.async { [weak self] in self?.countAwakeDown() }
        if onOpened != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.onOpened?()
            }
        }
        lastShowPhases = ShowPhases(results: orderStart - resultsStart, order: drawStart - orderStart, draw: end - drawStart)
        lastShowDuration = end - triggeredAt
        Log.perf.info("Launcher shown in \((end - triggeredAt).compact, privacy: .public)")
        index.reloadIfStale(usage: usage)
    }

    /// The selection when it is an amount of money ("$1,299", "49,90 €"),
    /// converted; nil for anything else.
    private func selectedPrice(off: Set<String>) -> Calculator.Result? {
        guard let selected = shownSelection, selected.count <= 40, !selected.contains(where: \.isNewline),
              FeatureCatalog.shows(row: "calculation", off: off), !off.contains("catalog.currency"), let context = currency()
        else { return nil }
        // An amount of money, or its row while the day's rates load.
        return Calculator.answers(selected, currency: context).first { $0.currency != nil || $0.isWaiting }
    }

    /// What a quicklink searches: what was typed for it, else the text
    /// selected where the launcher opened (its rows say so).
    func quicklinkQuery(_ link: Quicklink, typed: String) -> String {
        guard typed.isEmpty, link.takesQuery else { return typed }
        return selectionQuery ?? ""
    }

    /// After the panel is up, off the main thread: the launcher's own
    /// show time does not pay for Accessibility.
    private func showSelectionPreview(from focused: SelectionService.FocusedElement?) {
        selectionLabel.stringValue = ""
        shownSelection = nil
        selectionShow &+= 1
        guard let focused else { return }
        let show = selectionShow
        Task { [weak self] in
            let text = focused.isOwn
                ? SelectionService.selectedText(in: focused)
                : await Task.detached(priority: .userInitiated) { SelectionService.selectedText(in: focused) }.value
            // Closed and opened again meanwhile: that selection is not this show's.
            guard let self, self.panel.isVisible, show == self.selectionShow, let text else { return }
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            self.shownSelection = text
            self.selectionLabel.stringValue = "Selected “\(line.count > 40 ? String(line.prefix(40)) + "…" : line)” · ⇥ asks about it"
            // Quicklinks shown with nothing typed search it: they say so.
            if self.results.contains(where: { if case .quicklink(_, "", _) = $0 { true } else { false } }) { self.showRows() }
            // "$1,299" selected: its conversion comes first.
            if self.mode == nil, self.searchField.stringValue.isEmpty, self.selectedPrice(off: self.off) != nil {
                self.updateResults(query: "")
            }
        }
    }

    /// What the rows come from changed while it is open (a device
    /// connected): read again, the rows redrawn.
    func reloadSources() {
        catalog = nil
        guard panel.isVisible, mode == nil else { return }
        updateResults(query: searchField.stringValue)
    }

    /// The recordings read again (one renamed, deleted, made): the rows
    /// that name them, at the root and in `recs`, redrawn.
    func recordingsChanged() {
        catalog = nil
        guard panel.isVisible, mode == nil || mode == .recordings else { return }
        updateResults(query: searchField.stringValue)
    }

    func hide() {
        let wasVisible = panel.isVisible
        if wasVisible { keep() }
        closeActions()
        clearNote()
        panel.orderOut(nil)
        awakeTicks?.invalidate()
        awakeTicks = nil
        if wasVisible { onClosed?() }
        leaveMode(update: false)
        // A hint the Catalog left in the field ("12 × 4 · …") goes with it.
        searchField.placeholderString = "Search"
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    // MARK: - Starts again empty

    /// What it holds as it closes, for Settings → Launcher → Starts again
    /// empty: a few values, nothing read.
    private func keep() {
        let row = tableView.selectedRow
        let item = results.indices.contains(row) ? results[row] : nil
        kept = Kept(mode: mode, back: modeBack, text: searchField.stringValue, script: scriptInput, row: row, rowID: item?.learningID,
                    rowTitle: item?.title, closedAt: .now)
    }

    /// What it held, when there was something, `keeping` takes its mode and
    /// the setting keeps it that long.
    private func keptSearch(_ keeping: (Mode?) -> Bool) -> Kept? {
        guard let kept, !kept.text.isEmpty || kept.mode != nil, keeping(kept.mode),
              resetChoice().keepsSearch(closedFor: .now - kept.closedAt) else { return nil }
        return kept
    }

    /// Opens with what it held: the mode and its words (its rows found
    /// again), else the words; then the same row, found by what it is, else
    /// where it was.
    private func restore(_ kept: Kept) {
        if let mode = kept.mode {
            if mode == .script { scriptInput = kept.script }
            guard mode != .script || scriptInput != nil else {
                updateResults(query: "")
                return
            }
            enterMode(mode, filter: kept.text)
            modeBack = kept.back
        } else {
            searchField.stringValue = kept.text
            updateResults(query: kept.text)
        }
        let same = results.indices.first { results[$0].learningID == kept.rowID && results[$0].title == kept.rowTitle }
        guard let row = same ?? (results.indices.contains(kept.row) ? kept.row : nil), row > 0,
              tableView(tableView, shouldSelectRow: row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see events for other apps, so any click here
        // is outside the launcher.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
    }

    /// Delivers a key event straight to the search field's editor, whether
    /// or not the window server made the panel key. Returns `false` when the
    /// launcher is hidden. Key-ups are consumed: the editor acts on key-down.
    func deliver(_ event: CGEvent) -> Bool {
        guard panel.isVisible else { return false }
        guard let typed = NSEvent(cgEvent: event), typed.type == .keyDown else { return true }
        // A line said for the last key goes with the next one.
        clearNote()
        // Typing in English: ⌘ and ⌃ keys as the user's own layout reads them.
        let keyEvent = chordEvent?(typed) ?? typed
        // ⌘K's list takes every key while it is open; ⌘K opens it.
        if !actionPanel.isHidden {
            actionPanelKey(keyEvent)
            return true
        }
        // ⌃N and ⌃P: ↓ and ↑, in every list (an input method composing
        // keeps its own).
        if let step = Self.controlStep(keyEvent), (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            if step < 0 {
                if !recallOlder() { moveSelection(by: -1) }
            } else if !recallNewer() {
                moveSelection(by: 1)
            }
            return true
        }
        if keyEvent.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           keyEvent.charactersIgnoringModifiers?.lowercased() == "k" {
            showActions()
            return true
        }
        // Return (36) or Enter (76) with its modifiers: ⇧ and ⌘ change what
        // it does. An input method composing text keeps its Return.
        if [36, 76].contains(keyEvent.keyCode), (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            launchSelected(flags: keyEvent.modifierFlags)
            return true
        }
        // ⌘C and ⇧⌘C copy from the selected row, unless text is selected in
        // the field: then ⌘C copies that text.
        if let key = LauncherAction.Key(keyEvent), key == .copy || key == .copySecond,
           (searchField.currentEditor()?.selectedRange.length ?? 0) == 0, runSelectedAction(key) {
            return true
        }
        // ⌘⌫ in a mode removes the selected row (the card asks first where
        // it cannot be undone). Outside the modes it edits the field.
        if mode != nil, LauncherAction.Key(keyEvent) == .delete, runSelectedAction(.delete) {
            return true
        }
        // ⌘R records the selected meeting (on now or starting soon).
        if LauncherAction.Key(keyEvent) == .record, runSelectedAction(.record) {
            return true
        }
        // ⌘Z just after Tomorrow or Next Week puts the reminder back.
        if mode == .reminders, keyEvent.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           keyEvent.charactersIgnoringModifiers?.lowercased() == "z", undoReminderMove() {
            return true
        }
        if keyEvent.modifierFlags.contains(.command), panel.performKeyEquivalent(with: keyEvent) {
            return true
        }
        if searchField.currentEditor() == nil {
            panel.makeFirstResponder(searchField)
        }
        // ⌘ with an arrow or ⌫: the command macOS's key bindings name (⌘←
        // to the start, ⇧⌘→ selects to the end, ⌘⌫ erases to the start),
        // run by the editor, through `control(_:textView:doCommandBy:)` as
        // the other keys. Its keyDown, handed the tap's event, ran none of
        // them. An input method composing keeps its keys.
        if keyEvent.modifierFlags.contains(.command), let editor = searchField.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            let commands = KeyBindings.commands(for: keyEvent)
            if !commands.isEmpty {
                commands.forEach { editor.doCommand(by: $0) }
                return true
            }
        }
        // Arrows, Return and Escape come back through
        // `control(_:textView:doCommandBy:)`; characters are inserted.
        searchField.currentEditor()?.keyDown(with: keyEvent)
        return true
    }

    /// ⌃N (+1) or ⌃P (−1), the Emacs keys macOS's own lists know: N and P
    /// by what they type, by their place on a layout without Latin letters.
    static func controlStep(_ event: NSEvent) -> Int? {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .control,
              let typed = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        let latin = typed.unicodeScalars.allSatisfy { $0.isASCII }
        if typed == "n" || (!latin && Int(event.keyCode) == kVK_ANSI_N) { return 1 }
        if typed == "p" || (!latin && Int(event.keyCode) == kVK_ANSI_P) { return -1 }
        return nil
    }

    /// Benchmark hook: type a query as if from the keyboard and return the
    /// time until the list is redrawn.
    func simulateTyping(_ query: String) -> Duration {
        let start = ContinuousClock.now
        searchField.stringValue = query
        updateResults(query: query)
        panel.displayIfNeeded()
        lastSearchLaps.lap("drawn")
        return .now - start
    }

    /// Benchmark hook: the launcher's window, for window-server captures.
    var window: NSWindow { panel }

    /// Benchmark hook: PNG of the launcher as currently laid out.
    func snapshotPNG(appearance: NSAppearance? = nil) -> Data? {
        guard let glass = glassViews.first else { return nil }
        let previous = panel.appearance
        panel.appearance = appearance
        defer { panel.appearance = previous }
        glass.displayIfNeeded()
        return Snapshot.png(of: glass)
    }

    // MARK: - Results

    /// What the launcher finds besides apps, read once per show with every
    /// name prepared for matching: a key then only compares.
    private struct Catalog {
        struct Entry {
            /// Its names first (`nameCount` of them), then its keywords.
            let candidates: [FuzzyCandidate]
            let item: LauncherItem
            /// How many of `candidates` are names: typed whole, they rank
            /// the row before rows the words only describe (`LauncherRank`).
            var nameCount = 1
            /// Long phrases that count only when the query is made of their
            /// words' starts (`FuzzyMatcher.matchesWordStarts`): System
            /// Settings' sections.
            var strict: [FuzzyCandidate] = []
            /// A System Settings pane: matched on what follows "réglages"
            /// too (`SystemSettingsPane.paneQuery`).
            var isPane = false
        }

        var entries: [Entry] = []
        /// The built-in commands, without those turned off.
        var commands = LauncherCommand.all
        var projects: [(candidate: FuzzyCandidate, item: LauncherItem)] = []
        /// The recordings by title and attendees, for any search.
        var recordings: [(candidate: FuzzyCandidate, item: LauncherItem)] = []
        /// Bluetooth may be allowed from here (`bluetoothAskable`).
        var bluetoothAskable = false
        var links: [Quicklink] = []
        var siCommands: [LauncherSICommand] = []
        /// The entries turned off in Settings → Catalog.
        var off: Set<String> = []

        /// Whether rows of the Catalog entry `entry` show: a set lookup,
        /// nothing when none is off.
        func shows(_ entry: String) -> Bool { off.isEmpty || !off.contains(entry) }
    }

    private var catalog: Catalog? {
        didSet { catalogNarrowing.reset() }
    }
    /// The catalog's entries the last key let through, for the next key
    /// typed on (`SearchNarrowing`); read anew with the catalog.
    private var catalogNarrowing = SearchNarrowing()
    /// What a match on a section costs against one on a name.
    private static let sectionPenalty = 30

    private func currentCatalog() -> Catalog {
        if let catalog { return catalog }
        var made = Catalog()
        for (command, title) in systemCommands?() ?? [] {
            let isPane = if case .settings = command { true } else { false }
            // Its title as shown, and its own: "Turn Off Keep Awake" is still
            // named Keep Awake, the current sound device without "(current)".
            var names = [title]
            for name in command.names where !names.contains(name) { names.append(name) }
            made.entries.append(.init(candidates: (names + command.keywords).map(FuzzyCandidate.init), item: .system(command, title: title),
                                      nameCount: names.count, strict: command.sectionKeywords.map(FuzzyCandidate.init), isPane: isPane))
        }
        for command in scripts?() ?? [] {
            made.entries.append(.init(candidates: [command.title, command.packageName + " " + command.title].map(FuzzyCandidate.init),
                                      item: .script(command, inline: nil)))
        }
        made.links = quicklinks?() ?? []
        for link in made.links {
            made.entries.append(.init(candidates: [link.name, link.keyword].filter { !$0.isEmpty }.map(FuzzyCandidate.init),
                                      item: .quicklink(link, query: ""), nameCount: link.name.isEmpty ? 0 : 1))
        }
        for layout in windowLayouts?() ?? [] {
            made.entries.append(.init(candidates: [layout.name, "\(layout.name) layout", "disposition \(layout.name)"].map(FuzzyCandidate.init),
                                      item: .layout(layout)))
        }
        for snippet in snippets?() ?? [] {
            made.entries.append(.init(candidates: [snippet.name, snippet.keyword, String(snippet.text.prefix(80))].filter { !$0.isEmpty }
                                        .map(FuzzyCandidate.init), item: .snippet(snippet), nameCount: snippet.name.isEmpty ? 0 : 1))
        }
        made.projects = (projects?() ?? []).map { (FuzzyCandidate($0.name), LauncherItem.project($0)) }
        made.recordings = (recordingSummaries?() ?? []).filter { $0.state == .done || $0.state == .pending }.map { summary in
            (FuzzyCandidate(([summary.title] + summary.attendees).joined(separator: " ")), LauncherItem.recorded(LauncherRecorded(summary: summary)))
        }
        made.siCommands = siCommands?() ?? []
        made.bluetoothAskable = bluetoothAskable?() ?? false
        // What is turned off leaves here, once per show: a key never looks.
        made.off = off
        if !made.off.isEmpty {
            let off = made.off
            made.entries.removeAll { !FeatureCatalog.shows(row: $0.item.learningID, off: off) }
            made.commands.removeAll { off.contains(LauncherItem.command($0).learningID) }
            made.siCommands.removeAll { off.contains(LauncherItem.siCommand($0).learningID) }
            if off.contains("cmd:searchProjects") { made.projects = [] }
            if off.contains("cmd:searchRecordings") { made.recordings = [] }
        }
        catalog = made
        refreshPinned(from: made)
        return made
    }

    private func updateResults(query text: String) {
        let start = ContinuousClock.now
        var laps = Laps()
        let query = FuzzyMatcher.Query(text)
        if mode == nil { rootQuery = text }
        updateAwakeChip(empty: text.isEmpty)
        if mode == .catalog {
            // Filtered in memory: the entries were read as it opened.
            results = Self.catalogRows(FeatureCatalog.filter(catalogEntries, text))
        } else if killMode {
            // Kill Process: rows from the last snapshot now, fresh ones soon.
            let kill = Self.killQuery(text)
            results = killRows(kill, entries: processes)
            refreshProcesses(for: kill, text: text)
        } else if mode == .files {
            if let fileMeaning, fileMeaning.query == text {
                results = fileMeaning.files.map(LauncherItem.file)
            } else {
                fileMeaning = nil
                // The last rows stay while Spotlight looks for the new text.
                results = (fileResults?.files ?? []).map(LauncherItem.file)
                if fileResults?.query != text { searchFiles(text) }
            }
        } else if mode == .contacts {
            if contacts?.isAllowed == false {
                results = [.setup(.contacts)]
            } else {
                results = (contactResults?.matches ?? []).map(LauncherItem.contact)
                if contactResults?.query != text { searchContacts(text) }
            }
        } else if mode == .reminders {
            if let reminderEntries {
                let filter = FuzzyMatcher.Query(text)
                results = (text.isEmpty ? reminderEntries : reminderEntries.filter { entry in
                    entry.candidates.contains { FuzzyMatcher.score(filter, $0) != nil }
                }).prefix(Layout.resultLimit).map { LauncherItem.reminder($0.item) }
                // What is typed can be added: last, or first when nothing fits.
                if !text.trimmingCharacters(in: .whitespaces).isEmpty,
                   let request = ReminderRequest.parse("rappel " + text, lists: reminders?.listNames() ?? []) {
                    if results.isEmpty { results = [.addReminder(request)] } else { results.append(.addReminder(request)) }
                }
            } else {
                results = reminders?.isAllowed == false && reminders?.canAsk == false ? [.setup(.reminders)] : []
            }
        } else if mode == .github {
            results = githubResults(text)
        } else if mode == .agenda {
            if let agendaEvents {
                let filter = FuzzyMatcher.Query(text)
                results = (text.isEmpty ? agendaEvents : agendaEvents.filter { entry in
                    entry.candidates.contains { FuzzyMatcher.score(filter, $0) != nil }
                }).prefix(Layout.resultLimit).map { LauncherItem.event($0.event) }
            } else {
                results = calendar?.isAllowed == false && calendar?.canAsk == false ? [.setup(.calendar)] : []
            }
        } else if mode == .brew, let homebrew {
            let packages = homebrew.search(text, outdated: brewOutdated)
            let updates = packages.filter { $0.update != nil }.count
            results = (text.isEmpty && updates > 1 ? [LauncherItem.brewUpgradeAll(updates)] : []) + packages.prefix(Layout.resultLimit).map(LauncherItem.brew)
            describeBrew(packages.prefix(12).filter { $0.description == nil }, text: text)
        } else if mode == .history {
            if let historyMeaning, historyMeaning.query == text {
                results = historyMeaning.visits.map(LauncherItem.visit)
            } else {
                historyMeaning = nil
                // The last rows stay while the histories are read again.
                results = (historyResults?.visits ?? []).map(LauncherItem.visit)
                if historyResults?.query != text { searchHistory(text) }
            }
            if historyNeedsDiskAccess { results.insert(.setup(.fullDiskAccess), at: 0) }
        } else if mode == .script, let input = scriptInput {
            let argument = input.command.arguments[input.values.count]
            if argument.kind == .dropdown {
                let filter = FuzzyMatcher.Query(text)
                results = argument.choices.filter { text.isEmpty || FuzzyMatcher.score(filter, FuzzyCandidate($0.title)) != nil }
                    .map { LauncherItem.scriptChoice(title: $0.title, value: $0.value) }
            } else {
                results = [.scriptArgument(input.command, index: input.values.count, text: text)]
            }
        } else if mode == .recordings {
            results = recordingRows(text)
        } else if mode == .projects {
            let filter = FuzzyMatcher.Query(text)
            results = (text.isEmpty ? projectList : projectList.filter { project in
                [project.name, project.name + " " + project.editor, project.path].contains { FuzzyMatcher.score(filter, FuzzyCandidate($0)) != nil }
            }).map(LauncherItem.project)
        } else if mode == .tabs {
            let filter = FuzzyMatcher.Query(text)
            results = (text.isEmpty ? tabList : tabList.filter { FuzzyMatcher.score(filter, FuzzyCandidate($0.title + " " + $0.browser)) != nil })
                .map(LauncherItem.browserTab)
        } else if mode == .windows {
            let filter = FuzzyMatcher.Query(text)
            results = (text.isEmpty ? windowList : windowList.filter { FuzzyMatcher.score(filter, FuzzyCandidate($0.line)) != nil })
                .map(LauncherItem.openWindow)
        } else if mode == .snippets {
            if let snippetFound, snippetFound.query == text {
                results = (snippetFound.snippets.isEmpty ? snippetFound.maybe.map { [$0] } ?? [] : snippetFound.snippets).map(LauncherItem.snippet)
            } else {
                snippetFound = nil
                // By name, keyword or first words, in memory: the best first.
                let filter = FuzzyMatcher.Query(text)
                results = text.trimmingCharacters(in: .whitespaces).isEmpty ? snippetList.map(LauncherItem.snippet)
                    : snippetList.compactMap { snippet -> (Snippet, Int)? in
                        [snippet.name, snippet.keyword, String(snippet.text.prefix(80))].filter { !$0.isEmpty }
                            .compactMap { FuzzyMatcher.score(filter, FuzzyCandidate($0)) }.max().map { (snippet, $0) }
                    }
                    .sorted { $0.1 > $1.1 }
                    .map { LauncherItem.snippet($0.0) }
            }
        } else if mode == .menus {
            let items = menuItems
            results = MenuSearch.search(text, in: menuCandidates ?? []).compactMap { entry in
                items.indices.contains(entry.index) ? LauncherItem.menuItem(entry, items[entry.index]) : nil
            }
        } else if mode == .emoji {
            if let feeling, feeling.query == text {
                results = feeling.emoji.map(LauncherItem.emoji)
                emojiSections = []
            } else {
                feeling = nil
                let list = emojiSearch?(text) ?? EmojiList(emoji: [])
                results = list.emoji.map(LauncherItem.emoji)
                emojiSections = list.sections
                // Nothing by name: say it by feeling, after a short pause.
                if results.isEmpty, text.count >= 3 { searchEmojiByFeeling(after: .milliseconds(350)) }
            }
        } else if mode == .gifs {
            results = gifRows(text).map(LauncherItem.gif)
        } else if clipboardMode {
            // Typed on: the search asked about other words stops.
            if let pending = meaningPending, pending != text {
                meaningTask?.cancel()
                meaningPending = nil
            }
            if meaningPending == text, !text.isEmpty {
                results = []
            } else if let meaning, meaning.query == text {
                results = meaning.result.items.map(LauncherItem.clip)
            } else {
                // SQLite FTS5 on this Mac: well under a millisecond.
                meaning = nil
                results = (clipboardItems?(text) ?? []).map(LauncherItem.clip)
            }
        } else if query.isEmpty {
            let apps = index.search("", usage: usage, limit: Layout.resultLimit).map(LauncherItem.app)
            // What the user pinned first, in the order pinned (⌘K → Pin).
            let pinned = pinnedItems()
            results = pinned.isEmpty ? apps : Array(LauncherPins.first(pinned, then: apps, id: \.learningID).prefix(Layout.resultLimit))
            // The meeting about to start (or just started): first, ↩ joins.
            if FeatureCatalog.shows(row: "event", off: off), let meeting = calendar?.meetingNow() { results.insert(.event(meeting), at: 0) }
            // A price selected where the launcher opened: converted, first.
            if let selected = selectedPrice(off: off) { results.insert(.calculation(selected), at: 0) }
        } else {
            // Fuzzy score + usage + what was picked before for this text,
            // and a boost for what the user pinned.
            let pinned = pinsNow.ids
            func boost(_ id: String) -> Int {
                learning.boost(query: text, item: id) + (pinned.isEmpty || !pinned.contains(id) ? 0 : LauncherPins.boost)
            }
            var scored: [(item: LauncherItem, score: Int)] = index.scored(query, usage: usage).map {
                (.app($0.entry), $0.score + boost(LauncherItem.app($0.entry).learningID))
            }
            laps.lap("apps")
            let catalog = currentCatalog()
            laps.lap("catalog")
            for command in catalog.commands {
                if let score = command.score(query) {
                    let item = LauncherItem.command(command)
                    scored.append((item, score + boost(item.learningID)))
                }
            }
            laps.lap("commands")
            // "réglages bluetooth": the panes are matched on "bluetooth" too.
            let paneQuery = SystemSettingsPane.paneQuery(text).map(FuzzyMatcher.Query.init)
            // "réglages bluetooth", "bluetooth settings": the pane named so is
            // the one asked for.
            let askedPane = SystemSettingsPane.asked(text).map(FuzzyMatcher.Query.init)
            var panesAsked: [String] = []
            // Typed on, a key looks only at the entries the key before let
            // through (`SearchNarrowing`); "réglages …" matches the panes on
            // other words than the query: every entry then.
            let looked = paneQuery == nil ? catalogNarrowing.rows(for: query, count: catalog.entries.count) : Array(catalog.entries.indices)
            var possible: [Int] = []
            for index in looked {
                let entry = catalog.entries[index]
                // A section ("Display" in Accessibility) ranks under a name
                // that fits as well ("Displays"). `possible`: the query typed
                // on may still match the entry.
                func scores(_ query: FuzzyMatcher.Query) -> (found: [Int], possible: Bool) {
                    var found = entry.candidates.compactMap { FuzzyMatcher.score(query, $0) }
                    var possible = !found.isEmpty
                    for section in entry.strict where FuzzyMatcher.matchesWordStarts(query, section) {
                        possible = true
                        if let score = FuzzyMatcher.score(query, section), FuzzyMatcher.isStrong(score, for: query) {
                            found.append(score - Self.sectionPenalty)
                        }
                    }
                    return (found, possible)
                }
                let typed = scores(query)
                if typed.possible { possible.append(index) }
                guard var score = (typed.found + (entry.isPane ? paneQuery.map { scores($0).found } ?? [] : [])).max() else { continue }
                var item = entry.item
                // A name typed whole comes before what the words only
                // describe ("display": Displays before Move to Next Display).
                let names = entry.candidates.prefix(entry.nameCount)
                let asked = entry.isPane && askedPane.map { LauncherRank.names($0, names) } == true
                if asked || LauncherRank.names(query, names) { score += LauncherRank.namedBoost }
                if asked { panesAsked.append(item.learningID) }
                if case .script(let command, _) = item, command.mode == .inline { item = .script(command, inline: scriptInline?(command)) }
                scored.append((item, score + boost(item.learningID)))
            }
            if paneQuery == nil { catalogNarrowing.keep(possible, for: query) } else { catalogNarrowing.reset() }
            laps.lap("mac, skillies, links, snippets")
            // The editors' recent projects by name: the four that fit best.
            let projectRows = catalog.projects.compactMap { project -> (item: LauncherItem, score: Int)? in
                guard let score = FuzzyMatcher.score(query, project.candidate) else { return nil }
                let named = FuzzyMatcher.names(query, project.candidate) ? LauncherRank.namedBoost : 0
                return (project.item, score + named + learning.boost(query: text, item: project.item.learningID))
            }
            scored += projectRows.sorted { $0.score > $1.score }.prefix(4)
            laps.lap("projects")
            // The recordings whose title or attendees the words start, in
            // order: the two that fit best, from three letters (from memory).
            if text.count >= 3 {
                let recordingRows = catalog.recordings.compactMap { recording -> (item: LauncherItem, score: Int)? in
                    guard FuzzyMatcher.matchesWordStarts(query, recording.candidate), let score = FuzzyMatcher.score(query, recording.candidate)
                    else { return nil }
                    return (recording.item, score + learning.boost(query: text, item: recording.item.learningID))
                }
                scored += recordingRows.sorted { $0.score > $1.score }.prefix(2)
            }
            laps.lap("recordings")
            let links = catalog.links
            for command in catalog.siCommands {
                if let score = command.score(query) {
                    let item = LauncherItem.siCommand(command)
                    scored.append((item, score + boost(item.learningID)))
                }
            }
            laps.lap("si")
            // Learned picks win even when the text does not match the name
            // ("smid" → Transmit once you picked it for "smid").
            let present = Set(scored.map(\.item.learningID))
            for learned in learning.learnedItems(query: text)
            where learned.boost >= Self.learnedOnlyThreshold && !present.contains(learned.item) && FeatureCatalog.shows(row: learned.item, off: catalog.off) {
                if let item = resolve(learnedID: learned.item) {
                    scored.append((item, learned.boost))
                }
            }
            // Even scores: a device's output before its microphone ("airpods":
            // where the sound plays is what is asked for most), then the
            // shorter title.
            func outputFirst(_ item: LauncherItem) -> Int {
                if case .system(.sound(let target), _) = item { return target.output ? 0 : 1 }
                return 0
            }
            // Each row's tie-breaks worked out once, not at every comparison:
            // one letter ties hundreds of rows.
            var ranked = scored.map { (item: $0.item, score: $0.score, output: outputFirst($0.item), length: $0.item.title.count) }
            ranked.sort { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.output != rhs.output { return lhs.output < rhs.output }
                return lhs.length < rhs.length
            }
            results = ranked.prefix(Layout.resultLimit - 1).map(\.item)
            laps.lap("ranking")
            // A calculation answers first: "12,5 × 4", "10 km en miles",
            // "800 TRY in €" (one row per currency asked).
            if catalog.shows("catalog.calculator") {
                let answers = Calculator.answers(text, currency: catalog.shows("catalog.currency") ? currency() : nil)
                results.insert(contentsOf: answers.map(LauncherItem.calculation), at: 0)
                // "100 usd in eur, gbp, chf": the answers push the last rows out.
                if answers.count > 1, results.count > Layout.resultLimit { results.removeLast(results.count - Layout.resultLimit) }
            }
            if catalog.shows("cmd:newWindowLayout"), let name = WindowLayoutPlan.saveName(text), !name.isEmpty, onSaveLayout != nil {
                results.insert(.saveLayout(name), at: 0)
            }
            let lower = text.lowercased()
            // Running timers (↩ cancels one) only once the word is typed out,
            // and never first: "c", "t" or "m" + ↩ opens Chrome, Terminal or
            // Mail, it does not cancel a timer.
            if catalog.shows("catalog.timer"), ["timer", "minuteur", "chrono"].contains(where: { lower.hasPrefix($0) }) {
                let running = (runningTimers?() ?? []).map(LauncherItem.runningTimer)
                results.insert(contentsOf: running, at: min(1, results.count))
            }
            if catalog.shows("catalog.timer"), let request = TimerRequest.parse(text), onStartTimer != nil {
                results.insert(.startTimer(request), at: 0)
            }
            let awakeRequest = catalog.shows("catalog.awake") && onKeepAwake != nil ? AwakeRequest.parse(text) : nil
            if let awakeRequest { results.insert(.keepAwake(awakeRequest), at: 0) }
            // Kept awake now: the words about it ("awake", "keep awake")
            // show it running, ↩ lets it sleep; after a length typed, the
            // new one first. It stands for Keep Awake's own row, "Turn Off
            // Keep Awake" while awake; "turn off awake" typed is that row
            // already.
            let awake = awakeState()
            if awake.awake, catalog.shows("catalog.awake"), onKeepAwake != nil, AwakeRequest.mentions(text) {
                // One "Turn Off Keep Awake" row, never two alike.
                results.removeAll { if case .system(.system(.keepAwake), _) = $0 { true } else { false } }
                if awakeRequest != .allowSleep { results.insert(.keptAwake(until: awake.until), at: awakeRequest == nil ? 0 : 1) }
            }
            // "rec Weekly sync": the Record card with that name, first. While
            // one records, the words about it show it, ↩ stops it; it stands
            // for Record Meeting's own row (no second recording at once).
            if catalog.shows("cmd:recordMeeting"), onRecord != nil {
                if let live = recordingState(), RecordRequest.mentions(text) {
                    results.removeAll { if case .command(let command) = $0 { command.id == .recordMeeting } else { false } }
                    results.insert(.recording(live), at: 0)
                } else if let name = RecordRequest.name(text) {
                    results.insert(.recordNamed(name), at: 0)
                }
            }
            // "volume 30", "mets le son à 30 %": the level, first.
            if catalog.shows("catalog.volume"), let level = VolumeRequest.parse(text), onSystemCommand != nil {
                results.insert(.system(.volume(level), title: VolumeRequest.title(level)), at: 0)
            }
            // "connecte mes AirPods" before Bluetooth is allowed: the one
            // thing to do first is to allow it; "réglages bluetooth" asks
            // for the pane: it stays first, the offer next.
            if catalog.bluetoothAskable, BluetoothRoute.mentions(text) {
                let place = LauncherRank.offerPlace(asksForSettings: askedPane != nil,
                                                    named: panesAsked.isEmpty ? [] : results.map { panesAsked.contains($0.learningID) })
                results.insert(.setup(.bluetooth), at: place)
            }
            laps.lap("parsers")
            // The best contacts, when they really fit (a name, a company):
            // from memory, never waited for.
            if let contacts, text.count >= 3, catalog.shows("cmd:searchContacts") {
                results += contacts.cachedMatches(text, limit: 2).filter { $0.score >= 7.5 }.map(LauncherItem.contact)
            }
            laps.lap("contacts")
            // "rappelle-moi d'appeler Paul demain 9h": offered first.
            if catalog.shows("catalog.remind"), Self.mayAskForReminder(text), let reminders, reminders.isAllowed || reminders.canAsk,
               let request = ReminderRequest.parse(text, lists: reminders.listNames()) {
                results.insert(.addReminder(request), at: 0)
            }
            // "rdv demain 14h point budget": offered first, Return adds it.
            if catalog.shows("catalog.event"), let calendar, calendarUsable,
               let request = EventRequest.parse(text, calendars: calendar.calendarNames(), nounFirst: true) {
                results.insert(.createEvent(request), at: 0)
            }
            // "join", "réunion", "prochaine réunion": the next meeting first.
            if catalog.shows("cmd:agenda"), Self.asksForMeeting(text), let calendar, calendar.isAllowed, let next = calendar.nextMeeting() {
                results.insert(.event(next), at: 0)
            }
            laps.lap("agenda")
            // A keyword typed is a prefix: it works even when its row is off.
            if let (link, typed) = Quicklink.match(text, in: links) {
                results.insert(.quicklink(link, query: typed), at: 0)
            } else if results.isEmpty, let web = links.first(where: { $0.takesQuery && catalog.shows("quicklink:\($0.id.uuidString)") }) {
                // Nothing on this Mac: the web.
                results.append(.quicklink(web, query: text.trimmingCharacters(in: .whitespaces), fallback: true))
            }
            // Whatever was typed, skil.li can be asked to do it.
            if onSICommand != nil, catalog.shows("si:ask") {
                results.append(.ask(text.trimmingCharacters(in: .whitespaces)))
            }
        }
        // What is missing comes first, whatever was typed.
        laps.lap("found")
        // The item an alias names comes first ("e", "e " or "ql query").
        aliasByID = Dictionary(aliases().map { ($0.id, $0.alias) }, uniquingKeysWith: { first, _ in first })
        if mode == nil, let aliased = aliasedItem(text) {
            results.removeAll { $0.learningID == aliased.learningID }
            results.insert(aliased, at: 0)
        }
        results = missingNow.map(LauncherItem.setup) + results
        laps.lap("permissions")
        lastSearchDuration = .now - start
        if let took = lastSearchDuration, took > .milliseconds(30) {
            Log.perf.notice("Launcher results for \(text.count) characters took \(took.compact, privacy: .public): \(laps.summary, privacy: .public)")
        }

        switch mode {
        case .kill:
            let open = unfolded.flatMap { key in ProcessListing.groups(processes).first { $0.key == key } }
            sectionHeader.stringValue = open.map { "\($0.name) — \($0.entries.count) processes" } ?? "Apps and processes"
            emptyState.stringValue = "No results"
        case .clipboard:
            if meaningPending == text, !text.isEmpty {
                sectionHeader.stringValue = "By meaning"
            } else if let meaning, meaning.query == text {
                sectionHeader.stringValue = meaning.result.unanswered == nil ? "By meaning · \(meaning.result.label)" : "By meaning"
            } else {
                sectionHeader.stringValue = query.isEmpty ? "Copied recently" : "Copied"
            }
            if meaningPending == text, !text.isEmpty {
                emptyState.stringValue = "Searching by meaning…"
            } else if let meaning, meaning.query == text {
                emptyState.stringValue = meaning.result.unanswered.map { "\($0): ⇥ tries again" } ?? "No copy fits “\(text)”"
            } else {
                emptyState.stringValue = clipboardStatus?() ?? (query.isEmpty ? "Nothing copied yet" : (meaningAvailable ? "No words match: ⇥ searches by meaning" : "No results"))
            }
        case .files:
            if fileMeaningPending == text, !text.isEmpty {
                sectionHeader.stringValue = "Searching by meaning…"
            } else if let fileMeaning, fileMeaning.query == text {
                sectionHeader.stringValue = fileMeaning.label.isEmpty ? "By meaning" : "By meaning · \(fileMeaning.label)"
            } else {
                sectionHeader.stringValue = text.isEmpty ? "Files" : "Files named like “\(text)”"
            }
            emptyState.stringValue = text.isEmpty ? "Type a file's name"
                : isShowingFileMeaning ? "No recent file fits “\(text)”"
                : fileMeaningOn ? "No file named so: ⇥ searches by meaning" : "No file named “\(text)”"
        case .brew:
            let installed = results.filter { if case .brew(let package) = $0 { package.installed != nil } else { false } }.count
            let updates = results.filter { if case .brew(let package) = $0 { package.update != nil } else { false } }.count
            sectionHeader.stringValue = homebrew?.brew == nil ? "Homebrew is not installed"
                : text.isEmpty ? (updates > 0 ? "\(updates) update\(updates == 1 ? "" : "s") · \(installed) installed" : "\(installed) installed")
                : "Homebrew · \(results.count) found"
            emptyState.stringValue = homebrew?.brew == nil ? "Install Homebrew from brew.sh" : text.isEmpty ? "Nothing installed with Homebrew" : "No formula or cask named “\(text)”"
        case .history:
            if historyMeaningPending == text, !text.isEmpty {
                sectionHeader.stringValue = "Searching by meaning…"
            } else if let historyMeaning, historyMeaning.query == text {
                sectionHeader.stringValue = historyMeaning.label.isEmpty ? "By meaning" : "By meaning · \(historyMeaning.label)"
            } else {
                sectionHeader.stringValue = text.isEmpty ? "Recently visited" : "Pages with “\(text)”"
            }
            emptyState.stringValue = text.isEmpty ? "No history in Safari, Chrome, Arc, Brave, Edge, Firefox or Zen"
                : isShowingHistoryMeaning ? "No recent page fits “\(text)”"
                : historyMeaningOn ? "No page with these words: ⇥ searches by meaning" : "No page with “\(text)”"
        case .script:
            guard let input = scriptInput else { break }
            let index = input.values.count
            let argument = input.command.arguments[index]
            let total = input.command.arguments.count
            sectionHeader.stringValue = "\(input.command.title) · \(argument.placeholder)" + (total > 1 ? " (\(index + 1) of \(total))" : "")
            emptyState.stringValue = "No choice matches “\(text)”"
        case .reminders:
            let open = reminderEntries?.filter { !$0.item.isCompleted }.count ?? 0
            sectionHeader.stringValue = reminderEntries == nil ? "Reminders" : text.isEmpty ? "\(open) to do" : "Reminders with “\(text)”"
            emptyState.stringValue = reminderEntries == nil ? "" : text.isEmpty ? "Nothing to do" : "No reminder with “\(text)”"
        case .github:
            let shown = results.filter { if case .pullRequest = $0 { true } else { false } }.count
            sectionHeader.stringValue = github?.isSignedIn != true ? "GitHub"
                : githubGroup.map { "\($0.title) · \(shown)" } ?? (text.isEmpty ? "Pull requests and notifications" : "GitHub with “\(text)”")
            emptyState.stringValue = github?.isSignedIn != true ? "Sign in with GitHub in Settings → GitHub"
                : github?.lastRefresh == nil ? (github?.problem ?? "Reading GitHub…")
                : text.isEmpty ? githubGroup.map { "Nothing \($0.title.lowercased())" }
                    ?? (github?.notificationsRead == true ? "No open pull request, no unread notification" : "No open pull request")
                : "Nothing with “\(text)”"
        case .agenda:
            sectionHeader.stringValue = agendaEvents == nil ? "Calendar" : text.isEmpty ? "Coming up" : "Events with “\(text)”"
            emptyState.stringValue = agendaEvents == nil ? "" : text.isEmpty ? "Nothing in the next three months" : "No event with “\(text)”"
        case .contacts:
            sectionHeader.stringValue = text.isEmpty ? "Contacts" : "Contacts for “\(text)”"
            emptyState.stringValue = text.isEmpty ? "A name, a company, an email, a number, a city…" : "No contact for “\(text)”"
        case .recordings:
            let count = recordingSummaries?().count ?? 0
            sectionHeader.stringValue = text.isEmpty ? "\(count) recording\(count == 1 ? "" : "s")" : "Recordings with “\(text)”"
            emptyState.stringValue = count == 0 ? "No recording yet: ⌘R on a meeting's card records it" : "No recording with “\(text)”"
        case .projects:
            sectionHeader.stringValue = "\(projectList.count) recent project\(projectList.count == 1 ? "" : "s")"
            emptyState.stringValue = projectList.isEmpty ? "No recent projects in Cursor, VS Code, Zed, Sublime Text or JetBrains" : "No project matches “\(text)”"
        case .tabs:
            sectionHeader.stringValue = "\(tabList.count) tab\(tabList.count == 1 ? "" : "s") open"
            emptyState.stringValue = tabList.isEmpty ? "No browser open" : "No tab matches “\(text)”"
        case .menus:
            let app = menuApp?.localizedName ?? "The app in front"
            if let menuCandidates {
                sectionHeader.stringValue = query.isEmpty ? "\(app)'s menus" : "Menu items like “\(text)”"
                emptyState.stringValue = menuCandidates.isEmpty ? "\(app) shows no menu skil.li can read" : "No menu item named “\(text)”"
            } else {
                sectionHeader.stringValue = "Reading \(app)'s menus…"
                emptyState.stringValue = ""
            }
        case .windows:
            sectionHeader.stringValue = "\(windowList.count) window\(windowList.count == 1 ? "" : "s") open"
            emptyState.stringValue = windowList.isEmpty ? "No windows open" : "No window matches “\(text)”"
        case .snippets:
            if snippetMeaningPending == text, !text.isEmpty {
                sectionHeader.stringValue = "Searching by meaning…"
            } else if let snippetFound, snippetFound.query == text {
                sectionHeader.stringValue = snippetFound.label.isEmpty ? "By meaning" : "By meaning · \(snippetFound.label)"
            } else {
                sectionHeader.stringValue = text.isEmpty ? "\(snippetList.count) snippet\(snippetList.count == 1 ? "" : "s")" : "Snippets like “\(text)”"
            }
            emptyState.stringValue = snippetList.isEmpty ? "No snippet yet: add one in Settings → Snippets"
                : snippetMeaningPending == text ? ""
                : isShowingSnippetMeaning ? "No snippet fits “\(text)”"
                : snippetMeaningOn ? "No snippet named so: ⇥ searches by meaning" : "No snippet named “\(text)”"
        case .emoji:
            if feelingPending == text, !text.isEmpty {
                sectionHeader.stringValue = "Finding the feeling…"
            } else if let feeling, feeling.query == text {
                sectionHeader.stringValue = "By feeling · \(feeling.label)"
            } else {
                // Browsing: the group at the top, as the grid scrolls.
                sectionHeader.stringValue = query.isEmpty ? emojiSections.first?.name ?? "Emoji" : "By name"
            }
            emptyState.stringValue = feelingPending == text ? "" : "No emoji or symbol for “\(text)”"
        case .gifs:
            let words = text.trimmingCharacters(in: .whitespaces)
            sectionHeader.stringValue = gifSections.first?.name ?? (words.isEmpty ? "GIFs" : "Searching…")
            emptyState.stringValue = gifEmptyLine(words)
        case .catalog:
            // The group at the top of the list; `listScrolled` follows it.
            sectionHeader.stringValue = catalogGroup(atRow: 0)?.title ?? "What skil.li can do"
            emptyState.stringValue = "Nothing skil.li does matches “\(text.trimmingCharacters(in: .whitespaces))”"
        case nil:
            // A search ↑ put back says which: ↓ goes forward, not down the rows.
            if let recalled, recentSearches.entries.indices.contains(recalled), recentSearches.entries[recalled] == text {
                sectionHeader.stringValue = "Recent search · \(recalled + 1) of \(recentSearches.entries.count)"
            } else {
                sectionHeader.stringValue = query.isEmpty ? "Suggestions" : "Results"
            }
            emptyState.stringValue = "No results"
        }
        // The selection is what Tab asks about, outside the modes.
        selectionLabel.isHidden = mode != nil
        emptyState.isHidden = !results.isEmpty
        if results.isEmpty, beside != nil { placeEmptyState() }
        // Setup rows fill the list: the search's line goes in the header.
        if clipboardMode, !results.isEmpty, meaningPending == text || (meaning?.query == text && meaning?.result.unanswered != nil) {
            sectionHeader.stringValue = emptyState.stringValue
        }
        showMeaningSpinner(isSearchingClipboardMeaning && results.isEmpty)
        laps.lap("labels")
        showRows()
        laps.lap("rows")
        if snippetMaybeRow == 0 {
            tableView.deselectAll(nil)
        } else if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        // The selected row's own keys (the selection may not have moved).
        updateFooter()
        showEmojiGrid()
        updatePreview()
        laps.lap("list")
        lastSearchLaps = laps
    }

    /// In the picker, the grid in the list's place, drawing the rows the
    /// table holds (the table stays the selection every action reads).
    private func showEmojiGrid() {
        let grid = mode == .emoji
        let gifs = mode == .gifs
        emojiGrid.isHidden = !grid
        gifGrid.isHidden = !gifs
        emojiName.isHidden = !grid && !gifs
        listScroll?.isHidden = grid || gifs
        if gifs {
            gifGrid.show(results.compactMap { if case .gif(let gif) = $0 { gif } else { nil } }, sections: gifSections)
            showGIFSelection()
            return
        }
        guard grid else { return }
        let tone = emojiTone()
        let tiles = results.compactMap { item -> (character: String, name: String)? in
            guard case .emoji(let emoji) = item else { return nil }
            return (emoji.character(in: tone), emoji.name)
        }
        emojiGrid.show(tiles, sections: emojiSections)
        showEmojiSelection()
    }

    /// The selected emoji: chosen in the grid, its names right of the header.
    private func showEmojiSelection() {
        let row = tableView.selectedRow
        emojiGrid.select(row)
        guard results.indices.contains(row), case .emoji(let emoji) = results[row] else {
            emojiName.stringValue = ""
            return
        }
        let name = emoji.name.prefix(1).uppercased() + emoji.name.dropFirst()
        // Its keys before the English name, which the right edge cuts first.
        let keys = emoji.kind == .emoji ? nil : typingKeys?(emoji.character)
        let english = emoji.english.isEmpty || emoji.english == emoji.name ? nil : emoji.english
        emojiName.stringValue = [name, keys, english].compactMap(\.self).joined(separator: " · ")
    }

    /// The selected GIF plays; its name and where it is from, right of
    /// the header.
    private func showGIFSelection() {
        let row = tableView.selectedRow
        gifGrid.select(row)
        guard results.indices.contains(row), case .gif(let gif) = results[row] else {
            emojiName.stringValue = ""
            return
        }
        if case .klipy = gif { emojiName.stringValue = gif.title.isEmpty ? "Klipy" : "\(gif.title) · Klipy" } else { emojiName.stringValue = "\(gif.title) · On this Mac" }
    }

    /// ←→↑↓ in the grid: the tile beside, above or below.
    private func moveInGrid(_ direction: EmojiGridView.Direction) {
        let start = max(tableView.selectedRow, 0)
        guard let next = mode == .gifs ? gifGrid.neighbor(of: start, direction) : emojiGrid.neighbor(of: start, direction) else { return }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
    }

    /// The selected row in the preview beside the list: a copy in the
    /// clipboard history, a snippet in Search Snippets.
    private func updatePreview() {
        let row = tableView.selectedRow
        let item = results.indices.contains(row) ? results[row] : nil
        if clipboardMode {
            guard case .clip(let clip) = item else {
                clipPreview.show(nil, imageURL: nil)
                return
            }
            clipPreview.show(clip, imageURL: clip.kind == .image ? clipboardImageURL?(clip) : nil)
        } else if mode == .snippets {
            guard case .snippet(let snippet) = item else {
                snippetPreview.show(nil, preview: nil, details: .init())
                return
            }
            let details = SnippetPreviewView.Details(
                expands: snippetExpandsLine, alias: aliasByID[LauncherItem.snippet(snippet).learningID],
                shortcut: snippetShortcuts[SkilliAction.snippet(snippet.id).id].map { $0.map { $0.keycaps.joined() }.joined(separator: " ") },
                modified: snippetModified?(snippet))
            snippetPreview.show(snippet, preview: snippetPreviewPieces?(snippet) ?? (snippet.expansion([:]), []), details: details)
        }
    }

    /// What sits beside the narrowed list.
    private enum Beside { case clipboard, snippets }
    private var beside: Beside?

    /// The list narrows beside a preview (the clipboard history, Search
    /// Snippets), and takes the whole card again outside them.
    private func setSplit(_ beside: Beside?) {
        self.beside = beside
        let width = beside == nil ? Layout.width : Layout.splitListWidth
        listScroll?.frame.size.width = width
        tableView.tableColumns.first?.width = width
        tableView.frame.size.width = width
        emptyState.cell?.wraps = beside != nil
        emptyState.lineBreakMode = beside == nil ? .byClipping : .byWordWrapping
        emptyState.maximumNumberOfLines = beside == nil ? 1 : 2
        placeEmptyState()
        clipPreview.isHidden = beside != .clipboard
        snippetPreview.isHidden = beside != .snippets
        if beside == .clipboard { clipPreview.prepare() } else { clipPreview.release() }
        if beside != .snippets { snippetPreview.release() }
    }

    /// The list's empty line, centred in it; beside a preview it wraps on
    /// two lines ("No snippet yet: add one in Settings → Snippets").
    private func placeEmptyState() {
        let middle = Layout.footerHeight + 1 + Layout.listBottomPadding + Layout.listHeight / 2
        guard beside != nil else {
            emptyState.frame = NSRect(x: 0, y: middle - 10, width: Layout.width, height: 20)
            return
        }
        let width = Layout.splitListWidth - 40
        let height = min(ceil(emptyState.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 100)).height ?? 20), 40)
        emptyState.frame = NSRect(x: 20, y: (middle - height / 2).rounded(), width: width, height: height)
    }

    /// The spinner on the empty line, left of its words, the pair centred.
    private func showMeaningSpinner(_ shown: Bool) {
        guard shown else {
            meaningSpinner.stopAnimation(nil)
            meaningSpinner.isHidden = true
            return
        }
        let size: CGFloat = 16, gap: CGFloat = 8
        let words = ceil(emptyState.attributedStringValue.size().width)
        let line = emptyState.frame
        // The words move right by half the spinner and its gap: centred, the
        // pair is.
        emptyState.frame = line.offsetBy(dx: (size + gap) / 2, dy: 0)
        let x = (line.midX - (words + size + gap) / 2).rounded()
        meaningSpinner.frame = NSRect(x: x, y: (line.midY - size / 2).rounded(), width: size, height: size)
        meaningSpinner.isHidden = false
        meaningSpinner.startAnimation(nil)
    }

    /// "trop content mais crevé": the decision model picks the emoji.
    private func searchEmojiByFeeling(after delay: Duration) {
        let text = searchField.stringValue
        guard mode == .emoji, feelingAvailable, !text.trimmingCharacters(in: .whitespaces).isEmpty, let emojiByFeeling,
              feelingPending != text, feeling?.query != text else { return }
        feelingTask?.cancel()
        feelingTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled, self.mode == .emoji, self.searchField.stringValue == text else { return }
            self.feelingPending = text
            self.updateHeaderOnly()
            let found = await emojiByFeeling(text)
            guard !Task.isCancelled, self.mode == .emoji, self.searchField.stringValue == text else { return }
            self.feelingPending = nil
            if let found { self.feeling = (text, found.emoji, found.label) }
            self.updateResults(query: text)
        }
    }

    /// The header says the decision model is at work, rows unchanged.
    private func updateHeaderOnly() {
        sectionHeader.stringValue = "Finding the feeling…"
        if results.isEmpty { emptyState.stringValue = "" }
    }

    // MARK: - Search GIFs

    /// The grid's rows and sections. Nothing typed: Recently Used, then
    /// Klipy's Trending. Typed: Klipy's GIFs in Klipy's order (its rule:
    /// nothing added, moved or left out), then the ones on this Mac. A
    /// search under way keeps the rows of the words before it.
    private func gifRows(_ text: String) -> [GIF] {
        let words = text.trimmingCharacters(in: .whitespaces)
        var sections: [(String, [GIF])] = []
        if words.isEmpty {
            gifTask?.cancel()
            gifPending = nil
            if let browse = gifBrowse {
                sections = [("Recently Used", browse.recent), ("Trending on Klipy", browse.trending)]
            }
        } else {
            if gifFound[words] == nil, gifPending != words { searchGIFs(words) }
            if let found = gifFound[words] ?? gifShownSearch {
                sections = [("Klipy", found.klipy), ("On this Mac", found.mac)]
            }
        }
        sections.removeAll { $0.1.isEmpty }
        gifSections = sections.map { EmojiList.Section(name: $0.0, count: $0.1.count) }
        return sections.flatMap(\.1)
    }

    /// The search shown last, while the next one is read.
    private var gifShownSearch: (klipy: [GIF], mac: [GIF], klipyFailed: Bool)?

    /// Why the grid is empty, in a line; nothing while Klipy is asked.
    private func gifEmptyLine(_ words: String) -> String {
        let klipy = gifLibrary?.canSearchKlipy == true
        if words.isEmpty {
            guard let browse = gifBrowse else { return "" }
            if !klipy { return "Type a GIF's name to find it on this Mac. Klipy needs a key: Settings → GIFs." }
            return browse.klipyFailed ? "Klipy did not answer: type a name to find a GIF on this Mac." : "Type what the GIF should say"
        }
        if gifPending == words { return "" }
        if !klipy { return "No GIF named “\(words)” on this Mac. Klipy needs a key: Settings → GIFs." }
        if gifFound[words]?.klipyFailed == true { return "Klipy did not answer, and no GIF on this Mac is named “\(words)”." }
        return "No GIF for “\(words)”"
    }

    /// Recently Used (Klipy's read back by slug) and Trending, in one go
    /// as the mode opens.
    private func loadGIFBrowse() {
        guard let gifLibrary else {
            gifBrowse = ([], [], false)
            return
        }
        gifBrowseTask?.cancel()
        gifBrowseTask = Task { [weak self] in
            async let recent = gifLibrary.recentGIFs()
            var trending: [GIF] = []
            var failed = false
            if gifLibrary.canSearchKlipy {
                do {
                    trending = try await gifLibrary.trending().gifs.map(GIF.klipy)
                } catch {
                    failed = true
                }
            }
            let recentGIFs = await recent
            guard let self, !Task.isCancelled, self.mode == .gifs else { return }
            self.gifBrowse = (recentGIFs, trending, failed)
            if self.searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                self.updateResults(query: self.searchField.stringValue)
            }
        }
    }

    /// Klipy and Spotlight once typing pauses (250 ms): one request for
    /// the words that stay, the one before cancelled.
    private func searchGIFs(_ words: String) {
        guard let gifLibrary else { return }
        gifTask?.cancel()
        gifPending = words
        let folder = gifFolder
        gifTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            async let mac = FileSearch.gifs(words, in: folder)
            var klipy: [GIF] = []
            var failed = false
            if gifLibrary.canSearchKlipy {
                do {
                    klipy = try await gifLibrary.search(words).gifs.map(GIF.klipy)
                } catch {
                    failed = true
                }
            }
            let macGIFs = await mac.map(GIF.file)
            guard let self, !Task.isCancelled, self.mode == .gifs else { return }
            let found = (klipy: klipy, mac: macGIFs, klipyFailed: failed)
            self.gifFound[words] = found
            self.gifShownSearch = found
            if self.gifPending == words { self.gifPending = nil }
            if self.searchField.stringValue.trimmingCharacters(in: .whitespaces) == words {
                self.updateResults(query: self.searchField.stringValue)
            }
        }
    }

    /// Search Recordings: by title, date and attendees at once (from
    /// memory), then by the words said once typing pauses (100 ms); those
    /// rows show the words around the match.
    private func recordingRows(_ text: String) -> [LauncherItem] {
        let all = recordingSummaries?() ?? []
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return all.map { .recorded(LauncherRecorded(summary: $0)) } }
        let named = all.compactMap { summary in RecordingSearch.score(typed, summary).map { (summary: summary, score: $0) } }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.summary.started > $1.summary.started }
            .map(\.summary)
        var rows = named.map { LauncherItem.recorded(LauncherRecorded(summary: $0)) }
        if let recordingWords, recordingWords.query == typed {
            let shown = Set(named.map(\.folder))
            let byFolder = Dictionary(all.map { ($0.folder, $0) }, uniquingKeysWith: { first, _ in first })
            rows += recordingWords.found.compactMap { found in
                guard !shown.contains(found.folder), let summary = byFolder[found.folder] else { return nil }
                return .recorded(LauncherRecorded(summary: summary, said: found.snippet))
            }
        } else {
            findRecordingWords(typed)
        }
        return rows
    }

    private func findRecordingWords(_ text: String) {
        recordingWordsTask?.cancel()
        guard let search = searchRecordingWords else { return }
        recordingWordsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let found = await search(text)
            guard let self, !Task.isCancelled, self.mode == .recordings,
                  self.searchField.stringValue.trimmingCharacters(in: .whitespaces) == text else { return }
            self.recordingWords = (text, found)
            self.updateResults(query: self.searchField.stringValue)
        }
    }

    /// Spotlight by name once typing pauses (100 ms); the rows come back a
    /// moment later.
    private func searchFiles(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            fileResults = (text, [])
            return
        }
        fileSearchTask?.cancel()
        fileSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let files = await FileSearch.search(text)
            guard let self, !Task.isCancelled, self.mode == .files, self.searchField.stringValue == text else { return }
            self.fileResults = (text, files)
            self.updateResults(query: text)
        }
    }

    /// The coming three months, asking for the calendars the first time
    /// (macOS's prompt).
    private func loadAgenda() {
        guard let calendar else { return }
        Task { [weak self] in
            guard await calendar.allow() else {
                self?.updateResults(query: self?.searchField.stringValue ?? "")
                return
            }
            guard let self, self.mode == .agenda else { return }
            let now = Date.now
            let end = Calendar.current.date(byAdding: .month, value: 3, to: now) ?? now.addingTimeInterval(92 * 86_400)
            // In the order of Agenda.sections: today, tomorrow, this week…
            self.agendaEvents = Agenda.sections(calendar.events(from: Calendar.current.startOfDay(for: now), to: end), now: now)
                .flatMap(\.events)
                .map { event in
                    let names = event.attendees.map(\.name).joined(separator: " ")
                    return (event, [event.title, event.calendar, event.location, names].filter { !$0.isEmpty }.map(FuzzyCandidate.init))
                }
            self.updateResults(query: self.searchField.stringValue)
        }
    }

    /// "now", "12m", "3h", "2d", "5w": how long since.
    static func githubAge(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        let days = Int(seconds / 86_400)
        return days < 14 ? "\(days)d" : "\(max(1, days / 7))w"
    }

    /// The pull requests (ready, blocked, waiting, testing; one group after a
    /// click in the strip), then the unread notifications; every word typed
    /// in the title, the repository, the number or the status.
    private func githubResults(_ text: String) -> [LauncherItem] {
        guard let github, github.isSignedIn else { return [] }
        let words = text.lowercased().split(separator: " ").map(String.init)
        func fits(_ fields: [String]) -> Bool {
            let haystack = fields.joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        let pullRequests = github.pullRequests.filter { pullRequest in
            (githubGroup == nil || pullRequest.group == githubGroup)
                && fits([pullRequest.title, pullRequest.repositoryFullName, "#\(pullRequest.number)", pullRequest.reason, pullRequest.statusLabel,
                         pullRequest.group.title])
        }
        let notifications = githubGroup != nil ? [] : github.unreadNotifications.filter { note in
            fits([note.title, note.repository, note.reasonTitle, note.type])
        }
        return (pullRequests.map(LauncherItem.pullRequest) + notifications.map(LauncherItem.githubNotification)).prefix(Layout.resultLimit).map { $0 }
    }

    /// Open reminders and the ones done this week, in Raycast's order,
    /// asking for Reminders the first time (macOS's prompt).
    private func loadReminders() {
        guard let reminders else { return }
        Task { [weak self] in
            guard await reminders.allow() else {
                self?.updateResults(query: self?.searchField.stringValue ?? "")
                return
            }
            let items = await reminders.items()
            guard let self, self.mode == .reminders else { return }
            self.reminderEntries = Reminders.sections(items, now: .now).flatMap(\.items).map { item in
                (item, [item.title, item.list, item.notes].filter { !$0.isEmpty }.map(FuzzyCandidate.init))
            }
            self.updateResults(query: self.searchField.stringValue)
        }
    }

    /// ⌘K → Tomorrow or Next Week: changed where it is, the row goes to
    /// its new day and stays selected; nothing said (the row shows it), ⌘Z
    /// puts it back.
    func moveReminder(_ item: ReminderItem, nextWeek: Bool) {
        let due = Reminders.moved(item, nextWeek: nextWeek, now: .now)
        do {
            try reminders?.reschedule(id: item.id, due: due, hasTime: item.hasTime)
        } catch {
            onNotice?("“\(item.title)” was not moved: \(error.localizedDescription)")
            return
        }
        var changed = item
        changed.due = due
        replaceReminder(changed)
        onChangedInPlace?()
        reminderUndo = (item, .now)
    }

    /// ⌘Z after Tomorrow or Next Week: the reminder's day as it was.
    private func undoReminderMove() -> Bool {
        guard let (before, at) = reminderUndo, ContinuousClock.now - at < .seconds(10) else { return false }
        reminderUndo = nil
        do {
            try reminders?.reschedule(id: before.id, due: before.due, hasTime: before.hasTime)
        } catch {
            onNotice?("“\(before.title)” was not put back: \(error.localizedDescription)")
            return true
        }
        replaceReminder(before)
        return true
    }

    /// The reminder changed in the list, sorted again (its day's section),
    /// still selected.
    private func replaceReminder(_ changed: ReminderItem) {
        guard var items = reminderEntries?.map(\.item), let index = items.firstIndex(where: { $0.id == changed.id }) else { return }
        items[index] = changed
        reminderEntries = Reminders.sections(items, now: .now).flatMap(\.items).map { item in
            (item, [item.title, item.list, item.notes].filter { !$0.isEmpty }.map(FuzzyCandidate.init))
        }
        updateResults(query: searchField.stringValue)
        let row = results.firstIndex { if case .reminder(let shown) = $0 { shown.id == changed.id } else { false } }
        if let row { tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    /// Checked off (or on again) where it is: the row stays, its circle fills.
    private func toggleReminder(_ item: ReminderItem, row: Int) {
        do {
            try reminders?.complete(id: item.id, done: !item.isCompleted)
        } catch {
            Log.actions.error("Reminder not changed: \(error.localizedDescription, privacy: .public)")
            say("“\(item.title)” was not \(item.isCompleted ? "opened again" : "checked off"): Reminders refused it. Try again, or ⌘↩ opens Reminders.")
            return
        }
        onChangedInPlace?()
        reminderUndo = nil
        var changed = item
        changed.isCompleted.toggle()
        changed.completedAt = changed.isCompleted ? .now : nil
        if let index = reminderEntries?.firstIndex(where: { $0.item.id == item.id }) { reminderEntries?[index].item = changed }
        updateResults(query: searchField.stringValue)
        if results.indices.contains(row) { tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    /// Only the words a reminder starts with are read as one (the rest
    /// costs nothing per key).
    static func mayAskForReminder(_ text: String) -> Bool {
        let first = text.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(separator: " ").first.map(String.init) ?? ""
        return ["rappelle-moi", "rappelle", "rappel", "todo", "to-do", "tache", "remind", "reminder", "task", "ajoute", "add", "create", "new",
                "set", "cree", "creer", "nouveau", "nouvel", "mets", "met", "n'oublie", "n’oublie", "pense", "a"].contains(first)
    }

    /// "join", "rejoindre", "réunion", "prochaine réunion", "meeting":
    /// what is typed is (the start of) a word for the next meeting.
    static func asksForMeeting(_ text: String) -> Bool {
        let typed = text.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
        guard typed.count >= 3 else { return false }
        if case .next = AgendaRequest.parse(text) { return true }
        let words = ["join", "rejoindre", "rejoins", "meeting", "next meeting", "reunion", "prochaine reunion", "visio", "call"]
        return words.contains { $0.hasPrefix(typed) }
    }

    /// The contacts for `text`, from memory once read (the first time takes
    /// a moment).
    private func searchContacts(_ text: String) {
        guard let contacts else { return }
        contactTask?.cancel()
        contactTask = Task { [weak self] in
            let matches = await contacts.search(text, limit: Layout.resultLimit)
            guard let self, !Task.isCancelled, self.mode == .contacts, self.searchField.stringValue == text else { return }
            self.contactResults = (text, matches)
            self.updateResults(query: text)
        }
    }

    /// The top rows' descriptions from `brew desc`, once typing pauses.
    private func describeBrew(_ packages: [BrewPackage], text: String) {
        guard !packages.isEmpty, let homebrew else { return }
        brewTask?.cancel()
        brewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            _ = await homebrew.descriptions(packages)
            guard let self, !Task.isCancelled, self.mode == .brew, self.searchField.stringValue == text else { return }
            self.updateResults(query: text)
        }
    }

    /// ⌘⌫ in Homebrew: the selected package uninstalled, after a yes.
    func uninstallSelectedBrew() {
        let row = tableView.selectedRow
        guard results.indices.contains(row), case .brew(let package) = results[row], package.installed != nil else {
            say("Nothing to uninstall here: select an installed formula or cask, then ⌘⌫.")
            return
        }
        hide()
        onBrew?(.uninstall, package)
    }

    /// The histories by words once typing pauses (100 ms).
    private func searchHistory(_ text: String) {
        historyTask?.cancel()
        let source = historySource
        historyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let visits = await BrowserHistory.search(text, source: source)
            guard let self, !Task.isCancelled, self.mode == .history, self.searchField.stringValue == text else { return }
            self.historyResults = (text, visits)
            self.updateResults(query: text)
        }
    }

    /// ⇥: the decision model picks among the last pages visited.
    private func searchHistoryByMeaning() {
        let text = searchField.stringValue
        guard historyMeaningOn, !text.trimmingCharacters(in: .whitespaces).isEmpty, let keys = historyDecisionKeys?() else { return }
        historyMeaningTask?.cancel()
        historyMeaningPending = text
        sectionHeader.stringValue = "Searching by meaning…"
        let source = historySource
        historyMeaningTask = Task { [weak self] in
            let found = await BrowserHistory.searchByMeaning(text, keys: keys, source: source)
            guard let self, !Task.isCancelled, self.mode == .history, self.searchField.stringValue == text else { return }
            self.historyMeaningPending = nil
            if let found {
                self.historyMeaning = (text, found.visits, found.label)
                self.updateResults(query: text)
            } else {
                self.sectionHeader.stringValue = "Search by meaning did not answer"
            }
        }
    }

    /// ⇥: the decision model picks among the user's snippets.
    private func searchSnippetsByMeaning() {
        let text = searchField.stringValue
        guard snippetMeaningOn, !text.trimmingCharacters(in: .whitespaces).isEmpty, let snippetMeaning, !snippetList.isEmpty else { return }
        snippetMeaningTask?.cancel()
        snippetMeaningPending = text
        updateResults(query: text)
        snippetMeaningTask = Task { [weak self] in
            let found = await snippetMeaning(text)
            guard let self, !Task.isCancelled, self.mode == .snippets, self.searchField.stringValue == text else { return }
            self.snippetMeaningPending = nil
            if let found {
                self.snippetFound = (text, found.snippets, found.maybe, found.label)
                self.updateResults(query: text)
            } else {
                self.updateResults(query: text)
                self.sectionHeader.stringValue = "Search by meaning did not answer"
            }
        }
    }

    /// ⇥: the decision model picks among recent files.
    private func searchFilesByMeaning() {
        let text = searchField.stringValue
        guard fileMeaningOn, !text.trimmingCharacters(in: .whitespaces).isEmpty, let keys = fileDecisionKeys?() else { return }
        fileMeaningTask?.cancel()
        fileMeaningPending = text
        sectionHeader.stringValue = "Searching by meaning…"
        fileMeaningTask = Task { [weak self] in
            guard let self else { return }
            let found = await FileSearch.searchByMeaning(text, keys: keys)
            guard !Task.isCancelled, self.mode == .files, self.searchField.stringValue == text else { return }
            self.fileMeaningPending = nil
            if let found {
                self.fileMeaning = (text, found.files, found.label)
                self.updateResults(query: text)
            } else {
                self.sectionHeader.stringValue = "Search by meaning did not answer"
            }
        }
    }

    private func fileIcon(_ url: URL) -> NSImage {
        let key = url.pathExtension.isEmpty ? url.path : url.pathExtension
        if let cached = fileIcons[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        if fileIcons.count > 200 { fileIcons.removeAll() }
        fileIcons[key] = image
        return image
    }

    /// A running app's icon at row size, cached.
    private func appIcon(_ app: NSRunningApplication) -> NSImage {
        let path = app.bundleURL?.path ?? ""
        if let cached = appIconsByPath[path] { return cached }
        let image = app.icon ?? CommandIcon.image(for: "macwindow")
        image.size = NSSize(width: 32, height: 32)
        appIconsByPath[path] = image
        return image
    }

    /// A skillie's icon: its emoji, its image file, else a terminal.
    private func scriptIcon(_ command: ScriptCommand) -> NSImage {
        if let emoji = command.emojiIcon { return emojiImage(emoji) }
        if let path = command.iconImagePath {
            if let cached = appIconsByPath[path] { return cached }
            if let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 32, height: 32)
                appIconsByPath[path] = image
                return image
            }
        }
        return CommandIcon.image(for: "terminal")
    }

    /// An installed app's icon at row size, by bundle id, cached.
    private func appIcon(bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return CommandIcon.image(for: "folder") }
        if let cached = appIconsByPath[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        appIconsByPath[url.path] = image
        return image
    }

    /// An emoji drawn at icon size, cached.
    private func emojiImage(_ character: String) -> NSImage {
        if let cached = emojiImages[character] { return cached }
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            let text = NSAttributedString(string: character, attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.labelColor])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
        if emojiImages.count > 400 { emojiImages.removeAll() }
        emojiImages[character] = image
        return image
    }

    /// ⇥ in the history: ask by meaning about what is typed.
    private func searchClipboardByMeaning() {
        let text = searchField.stringValue
        guard meaningAvailable, !text.trimmingCharacters(in: .whitespaces).isEmpty, let clipboardMeaning else { return }
        meaningTask?.cancel()
        meaningPending = text
        updateResults(query: text)
        meaningTask = Task { [weak self] in
            let found = await clipboardMeaning(text)
            guard let self, !Task.isCancelled, self.clipboardMode, self.searchField.stringValue == text else { return }
            self.meaningPending = nil
            self.meaning = found.map { (text, $0) }
            self.updateResults(query: text)
        }
    }

    // MARK: - Pins

    /// The items pinned (⌘K → Pin) that show now, in the order pinned: apps
    /// and built-in commands looked up now, the rest as the last catalog
    /// read found them (nothing read on the show path). Turned off in
    /// Settings → Catalog, or not there: left out.
    private func pinnedItems() -> [LauncherItem] {
        let pins = pinsNow.list
        guard !pins.isEmpty else { return [] }
        return pins.compactMap { id -> LauncherItem? in
            guard FeatureCatalog.shows(row: id, off: off) else { return nil }
            if id.hasPrefix("app:") || id.hasPrefix("cmd:") { return resolve(learnedID: id) }
            guard let item = pinnedFound[id] else { return nil }
            if case .script(let command, _) = item, command.mode == .inline { return .script(command, inline: scriptInline?(command)) }
            return item
        }
    }

    /// After each catalog read (once the panel is up): the pinned items it
    /// holds, kept for the next show; pins whose item is gone for good
    /// dropped; the empty field drawn again if what it shows changed.
    private func refreshPinned(from made: Catalog) {
        let pins = pins()
        guard !pins.isEmpty || !pinnedFound.isEmpty else { return }
        let wanted = Set(pins)
        var found: [String: LauncherItem] = [:]
        for entry in made.entries where wanted.contains(entry.item.learningID) { found[entry.item.learningID] = entry.item }
        for command in made.siCommands {
            let item = LauncherItem.siCommand(command)
            if wanted.contains(item.learningID) { found[item.learningID] = item }
        }
        let changed = found.mapValues(\.title) != pinnedFound.mapValues(\.title)
        pinnedFound = found
        let kept = LauncherPins.kept(pins) { id in
            // Off in Settings → Catalog is not gone.
            guard FeatureCatalog.shows(row: id, off: made.off) else { return false }
            if id.hasPrefix("app:") { return !FileManager.default.fileExists(atPath: String(id.dropFirst(4))) }
            if id.hasPrefix("cmd:") { return !LauncherCommand.all.contains { "cmd:\($0.id.rawValue)" == id } }
            // A sound device away, a pane macOS no longer lists: may come back.
            if id.hasPrefix("system:") { return MacAction(rawValue: String(id.dropFirst(7))) == nil }
            return found[id] == nil
        }
        if kept != pins {
            onPinsChange?(kept)
            pinsAsShown = nil
        }
        if changed || kept != pins, panel.isVisible, mode == nil, searchField.stringValue.isEmpty, tableView.selectedRow <= 0 {
            updateResults(query: "")
        }
    }

    /// Items a pin can hold: what the launcher finds again by id.
    func takesPin(_ item: LauncherItem) -> Bool {
        takesAlias(item)
    }

    /// ⌘K → Pin / Unpin: first in the empty field, or not any more. Seen
    /// done (the row moves, its pin shows): nothing said.
    func pinAction(for item: LauncherItem) -> LauncherAction {
        let id = item.learningID
        let pinned = pinsNow.ids.contains(id)
        return LauncherAction(title: pinned ? "Unpin" : "Pin", symbol: pinned ? "pin.slash" : "pin") { [weak self] in
            guard let self else { return }
            let pins = self.pins()
            self.onPinsChange?(pinned ? LauncherPins.unpinning(id, in: pins) : LauncherPins.pinning(id, in: pins))
            self.pinsAsShown = nil
            // Shown at once in the empty field, as the catalog lists it.
            if !pinned, !id.hasPrefix("app:"), !id.hasPrefix("cmd:") {
                if case .quicklink(let link, _, _) = item { self.pinnedFound[id] = .quicklink(link, query: "") } else { self.pinnedFound[id] = item }
            }
            self.closeActions()
            self.refreshResults()
        }
    }

    private func resolve(learnedID: String) -> LauncherItem? {
        if learnedID.hasPrefix("app:") {
            return index.entry(path: String(learnedID.dropFirst(4))).map(LauncherItem.app)
        }
        if learnedID.hasPrefix("cmd:") {
            return LauncherCommand.all.first { $0.id.rawValue == learnedID.dropFirst(4) }.map(LauncherItem.command)
        }
        if learnedID.hasPrefix("system:"), let command = MacAction(rawValue: String(learnedID.dropFirst(7))) {
            return (systemCommands?() ?? []).first { $0.command == command }.map { LauncherItem.system($0.command, title: $0.title) }
        }
        if learnedID.hasPrefix("quicklink:") {
            return (quicklinks?() ?? []).first { $0.id.uuidString == learnedID.dropFirst(10) }.map { LauncherItem.quicklink($0, query: "") }
        }
        if learnedID.hasPrefix("layout:") {
            return (windowLayouts?() ?? []).first { $0.id == learnedID.dropFirst(7) }.map(LauncherItem.layout)
        }
        if learnedID.hasPrefix("snippet:") {
            return (snippets?() ?? []).first { $0.id == learnedID.dropFirst(8) }.map(LauncherItem.snippet)
        }
        if learnedID.hasPrefix("si:") {
            return (siCommands?() ?? []).first { $0.id == learnedID.dropFirst(3) }.map(LauncherItem.siCommand)
        }
        if learnedID.hasPrefix("script:") {
            return (scripts?() ?? []).first { $0.path == learnedID.dropFirst(7) }.map { LauncherItem.script($0, inline: nil) }
        }
        return nil
    }

    /// In Kill mode the field holds a port ("3000", ":3000"), a name, or
    /// nothing (everything, busiest first).
    private static func killQuery(_ text: String) -> ProcessListing.Query {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let port = Int(text.hasPrefix(":") ? String(text.dropFirst()) : text), (1...65535).contains(port) { return .port(port) }
        return text.isEmpty ? .all : .name(text)
    }

    /// Apps with all their processes (one row each), or the unfolded app's
    /// processes, or what listens on a port.
    private func killRows(_ kill: ProcessListing.Query, entries: [ProcessListing.Entry]) -> [LauncherItem] {
        switch kill {
        case .port(let port):
            return (portRows[port] ?? []).map { .process(ProcessListing.Group(single: $0.entry), port: port) }
        case .all, .name:
            if let unfolded, let group = ProcessListing.groups(entries).first(where: { $0.key == unfolded }) {
                return group.entries.map { .process(ProcessListing.Group(single: $0), port: nil) }
            }
            let filter = if case .name(let name) = kill { name } else { "" }
            return ProcessListing.groups(entries, matching: filter).prefix(30).map { .process($0, port: nil) }
        }
    }

    private func enterMode(_ next: Mode, filter: String) {
        // From the root search: esc comes back to what was typed there.
        if mode == nil { modeBack = rootQuery }
        mode = next
        unfolded = nil
        switch next {
        case .kill:
            modeChip.set(title: "Kill", color: .systemRed)
            searchField.placeholderString = "App, process or port"
        case .files:
            modeChip.set(title: "Files", color: .systemGreen)
            searchField.placeholderString = "A file's name, or what it is then ⇥"
            fileResults = nil
            fileMeaning = nil
            fileMeaningOn = filesByMeaningAvailable?() ?? false
        case .brew:
            modeChip.set(title: "Brew", color: .systemYellow)
            searchField.placeholderString = "A formula or cask to install"
            brewTask?.cancel()
            brewTask = Task { [weak self] in
                guard let homebrew = self?.homebrew else { return }
                let outdated = await homebrew.outdated()
                guard let self, !Task.isCancelled, self.mode == .brew else { return }
                self.brewOutdated = outdated
                self.updateResults(query: self.searchField.stringValue)
            }
        case .history:
            modeChip.set(title: "History", color: .systemCyan)
            historyNeedsDiskAccess = BrowserHistory.safariNeedsAccess(historySource)
            searchField.placeholderString = "Words of a page, or what it was then ⇥"
            historyResults = nil
            historyMeaning = nil
            historyMeaningOn = historyByMeaningAvailable?() ?? false
        case .script:
            modeChip.set(title: "Skillie", color: .systemBrown)
            if let input = scriptInput {
                let argument = input.command.arguments[input.values.count]
                searchField.placeholderString = argument.placeholder + (argument.optional ? " (optional)" : "")
            }
        case .projects:
            modeChip.set(title: "Projects", color: .systemPurple)
            searchField.placeholderString = "A project's name or editor"
            projectList = projects?() ?? []
        case .recordings:
            modeChip.set(title: "Recordings", color: .systemRed)
            searchField.placeholderString = "A title, a name, a date, or what was said"
            recordingWords = nil
            onRecordingsMode?()
        case .tabs:
            modeChip.set(title: "Tabs", color: .systemIndigo)
            searchField.placeholderString = "A tab's title"
            tabList = BrowserTabs.all()
        case .contacts:
            modeChip.set(title: "Contacts", color: .systemBrown)
            searchField.placeholderString = "A name, a company, an email, a number…"
            contactResults = nil
        case .reminders:
            modeChip.set(title: "Reminders", color: .systemOrange)
            searchField.placeholderString = "A reminder, a list"
            reminderEntries = nil
            loadReminders()
        case .github:
            modeChip.set(title: "GitHub", color: .systemGray)
            searchField.placeholderString = "A pull request, a repository, a notification"
            githubGroup = nil
            github?.showsGitHub = true
            github?.refresh()
        case .agenda:
            modeChip.set(title: "Calendar", color: .systemRed)
            searchField.placeholderString = "An event, a calendar, someone invited"
            agendaEvents = nil
            loadAgenda()
        case .windows:
            modeChip.set(title: "Windows", color: .systemTeal)
            searchField.placeholderString = "A window's title or app"
            windowList = openWindows?() ?? []
        case .menus:
            // The panel never activates skil.li: the app in front is still
            // the one the user was in.
            let app = NSWorkspace.shared.frontmostApplication
            menuApp = app
            menuItems = []
            menuCandidates = nil
            modeChip.set(title: "Menus", color: .systemIndigo)
            searchField.placeholderString = "A menu item of \(app?.localizedName ?? "the app in front")"
            menuTask?.cancel()
            if let pid = app?.processIdentifier {
                menuTask = Task { [weak self] in
                    // Accessibility off the main thread: an app slow to
                    // answer holds only this (1.5 s at most).
                    let items = await Task.detached { MenuReader.items(pid: pid).filter(\.isEnabled) }.value
                    guard let self, !Task.isCancelled, self.mode == .menus else { return }
                    self.menuItems = items
                    self.menuCandidates = items.enumerated().map { index, item in
                        MenuSearch.Candidate(.init(index: index, title: item.components.last ?? item.path,
                                                   parents: Array(item.components.dropLast()), shortcut: item.shortcut))
                    }
                    self.updateResults(query: self.searchField.stringValue)
                }
            } else {
                menuCandidates = []
            }
        case .snippets:
            modeChip.set(title: "Snippets", color: .systemPink)
            searchField.placeholderString = "A snippet's name, or what you need then ⇥"
            snippetList = snippets?() ?? []
            snippetFound = nil
            snippetMeaningOn = snippetMeaningAvailable?() ?? false
            snippetExpandsLine = snippetExpands?()
            snippetShortcuts = shortcutKeys?() ?? [:]
            setSplit(.snippets)
        case .emoji:
            modeChip.set(title: "Emoji", color: .systemOrange)
            searchField.placeholderString = "A name, or a feeling then ⇥"
            feeling = nil
            feelingAvailable = emojiByFeelingAvailable?() ?? false
        case .gifs:
            modeChip.set(title: "GIFs", color: .systemMint)
            // Klipy asks for these words in the field (its attribution).
            searchField.placeholderString = gifLibrary?.canSearchKlipy == true ? "Search KLIPY" : "A GIF on this Mac, by its name"
            gifFrontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            gifFound = [:]
            gifShownSearch = nil
            gifBrowse = nil
            loadGIFBrowse()
        case .clipboard:
            modeChip.set(title: "Clipboard", color: .systemBlue)
            searchField.placeholderString = "Search what you copied"
            meaning = nil
            meaningAvailable = clipboardMeaningAvailable?() ?? false
            setSplit(.clipboard)
            onClipboardMode?()
        case .catalog:
            modeChip.set(title: "Catalog", color: .controlAccentColor)
            searchField.placeholderString = "Anything skil.li does: kill, timer, emoji, window…"
            loadCatalog()
        }
        modeChip.isHidden = false
        let shift = modeChip.frame.width + 10
        searchField.frame = NSRect(x: fieldFrame.minX + shift, y: fieldFrame.minY, width: fieldFrame.width - shift, height: fieldFrame.height)
        searchField.stringValue = filter
        searchField.currentEditor()?.selectedRange = NSRange(location: (filter as NSString).length, length: 0)
        updateResults(query: filter)
    }

    private func leaveMode(update: Bool = true) {
        guard mode != nil else { return }
        reminderUndo = nil
        if mode == .windows { windowList = [] }
        if mode == .tabs { tabList = [] }
        if mode == .projects { projectList = [] }
        if mode == .recordings {
            recordingWordsTask?.cancel()
            recordingWords = nil
        }
        if mode == .script { scriptInput = nil }
        if mode == .brew { brewTask?.cancel() }
        if mode == .history {
            historyTask?.cancel()
            historyMeaningTask?.cancel()
            historyMeaningPending = nil
            historyResults = nil
            historyMeaning = nil
        }
        if mode == .contacts {
            contactTask?.cancel()
            contactResults = nil
        }
        if mode == .agenda { agendaEvents = nil }
        if mode == .reminders { reminderEntries = nil }
        if mode == .github {
            githubGroup = nil
            github?.showsGitHub = false
        }
        if mode == .files {
            fileSearchTask?.cancel()
            fileMeaningTask?.cancel()
            fileMeaningPending = nil
            fileResults = nil
            fileMeaning = nil
        }
        if mode == .emoji {
            feelingTask?.cancel()
            feelingPending = nil
            feeling = nil
        }
        if mode == .gifs {
            gifTask?.cancel()
            gifBrowseTask?.cancel()
            gifPending = nil
            gifFound = [:]
            gifShownSearch = nil
            gifBrowse = nil
            gifSections = []
            gifGrid.release()
        }
        if mode == .snippets {
            snippetMeaningTask?.cancel()
            snippetMeaningPending = nil
            snippetFound = nil
            snippetList = []
            snippetShortcuts = [:]
            setSplit(nil)
        }
        if mode == .clipboard {
            setSplit(nil)
            meaningTask?.cancel()
            meaningPending = nil
            meaning = nil
        }
        if mode == .catalog {
            catalogEntries = []
            catalogMade = FeatureCatalog.Input()
            catalogItems = [:]
            catalogShortcuts = [:]
            catalogCaps = [:]
        }
        mode = nil
        modeBack = nil
        unfolded = nil
        processRefresh?.cancel()
        // The list back in the grid's place, even when nothing is redrawn.
        showEmojiGrid()
        modeChip.isHidden = true
        searchField.frame = fieldFrame
        searchField.placeholderString = "Search"
        if update { updateResults(query: searchField.stringValue) }
    }

    /// `ps` (and `lsof` for a port) off the main thread, then the rows again
    /// if the text did not change meanwhile.
    private func refreshProcesses(for kill: ProcessListing.Query, text: String) {
        processRefresh?.cancel()
        processRefresh = Task { [weak self] in
            let entries = await Processes.snapshot()
            var ports: [Int: [Processes.Row]] = [:]
            if case .port(let port) = kill { ports[port] = await Processes.listening(on: port, among: entries) }
            guard let self, !Task.isCancelled, self.killMode, self.searchField.stringValue == text else { return }
            self.processes = entries
            self.portRows.merge(ports) { _, new in new }
            let selected = self.tableView.selectedRow
            self.results = self.killRows(kill, entries: entries)
            self.emptyState.isHidden = !self.results.isEmpty
            self.tableView.reloadData()
            if !self.results.isEmpty {
                self.tableView.selectRowIndexes(IndexSet(integer: min(max(selected, 0), self.results.count - 1)), byExtendingSelection: false)
            }
            self.updateFooter()
        }
    }

    /// Self-test hook: the rows, top first.
    var resultTitles: [String] { results.map(\.title) }

    /// Self-test hook: a row's accessory as drawn, and its place on screen.
    func accessoryShown(row: Int) -> (text: String, frame: NSRect?)? {
        (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultCellView)?.accessoryShown
    }

    /// Self-test hook: the detail at the right of each row drawn.
    var resultAccessories: [String] {
        (0..<tableView.numberOfRows).map { (tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? ResultCellView)?.accessoryText ?? "" }
    }

    private func askWithQuery() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let onSICommand else { return }
        rememberSearch()
        hide()
        onSICommand(PromptLibrary.askID, text)
    }

    // MARK: - Recent searches (↑)

    /// What is typed outside the modes, kept for ↑ once acted on (a row
    /// run, Ask). Never a mode's filter: the clipboard's, the files', a
    /// skillie's argument.
    private func rememberSearch() {
        guard mode == nil else { return }
        recentSearches.record(searchField.stringValue)
    }

    /// ↑ in the empty field, or on a search ↑ put back with its first row
    /// selected: the search before. False: ↑ moves the selection, as ever.
    private func recallOlder() -> Bool {
        guard mode == nil, tableView.selectedRow <= 0 else { return false }
        let entries = recentSearches.entries
        let walking = recalled.map { entries.indices.contains($0) && entries[$0] == searchField.stringValue } ?? false
        guard walking || searchField.stringValue.isEmpty else { return false }
        // The oldest shown already: ↑ stays on it.
        guard let older = recentSearches.searches.older(than: walking ? recalled : nil) else { return walking }
        putBack(older)
        return true
    }

    /// ↓ on a search ↑ put back: the one after, then the empty field, as
    /// in a shell. False: ↓ moves the selection.
    private func recallNewer() -> Bool {
        guard mode == nil, let recalled, tableView.selectedRow <= 0 else { return false }
        let entries = recentSearches.entries
        guard entries.indices.contains(recalled), entries[recalled] == searchField.stringValue else { return false }
        putBack(recentSearches.searches.newer(than: recalled))
        return true
    }

    /// The recent search at `index` in the field (nil: empty again), its
    /// rows below.
    private func putBack(_ index: Int?) {
        let text = index.map { recentSearches.entries[$0] } ?? ""
        searchField.stringValue = text
        searchField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        recalled = index
        updateResults(query: text)
    }

    /// ⌘⌫ on the selected event (the card asks first only when others are
    /// invited).
    func deleteSelectedEvent() {
        let row = tableView.selectedRow
        guard results.indices.contains(row), case .event(let event) = results[row] else { return }
        hide()
        onDeleteEvent?(event)
    }

    /// ⌘⌫ in the clipboard history: the row goes, the next one is
    /// selected; the undo card shows under the launcher (⌘Z).
    func forgetSelectedClip() {
        let row = tableView.selectedRow
        guard results.indices.contains(row), case .clip(let item) = results[row] else { return }
        onDeleteClip?(item)
        thumbnails[item.id] = nil
        updateResults(query: searchField.stringValue)
        moveSelection(by: row)
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        var next = min(max(current + delta, 0), results.count - 1)
        // Over a group's name in the Catalog, to the row after it.
        let step = delta < 0 ? -1 : 1
        while results.indices.contains(next), case .catalogHeader = results[next] { next += step }
        guard results.indices.contains(next) else { return }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        // Going up to a group's first row shows its name too.
        if step < 0, next > 0, case .catalogHeader = results[next - 1] { tableView.scrollRowToVisible(next - 1) }
        tableView.scrollRowToVisible(next)
    }

    /// Opens the selected row. `flags` are Return's modifiers (⇧ force
    /// quits or pastes plain text, ⌘ copies); a click reads the event's.
    func launchSelected(flags: NSEvent.ModifierFlags? = nil) {
        let flags = flags ?? NSApp.currentEvent?.modifierFlags ?? []
        let row = tableView.selectedRow
        // GitHub before signing in: Return goes to Settings → GitHub.
        if mode == .github, github?.isSignedIn != true {
            hide()
            onGitHubSettings?()
            return
        }
        guard results.indices.contains(row) else { return }
        // The day's rates not here yet: nothing runs, nothing is remembered.
        if case .calculation(let result) = results[row], result.isWaiting { return }
        rememberSearch()
        if case .catalog(let entry) = results[row] {
            runCatalog(entry, flags: flags)
            return
        }
        launch(results[row], row: row, flags: flags)
    }

    /// What Return does on `picked`: the row `row`, or the row a Catalog
    /// entry stands for.
    private func launch(_ picked: LauncherItem, row: Int, flags: NSEvent.ModifierFlags) {
        if case .setup(let permission) = picked {
            hide()
            onSetup?(permission)
            return
        }
        if case .command(let command) = picked, command.id == .killProcess {
            enterMode(.kill, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .catalog {
            enterMode(.catalog, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .clipboardHistory {
            enterMode(.clipboard, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .emoji {
            enterMode(.emoji, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .searchGIFs {
            enterMode(.gifs, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .searchSnippets {
            enterMode(.snippets, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .switchWindow {
            enterMode(.windows, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .searchMenus {
            enterMode(.menus, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .searchProjects {
            enterMode(.projects, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .searchRecordings {
            enterMode(.recordings, filter: "")
            return
        }
        if case .recorded(let found) = picked {
            hide()
            if flags.contains(.command) { onShowRecordingFolderNamed?(found.summary.folder) } else { onOpenRecording?(found.summary.folder) }
            return
        }
        if case .command(let command) = picked, command.id == .homebrew {
            enterMode(.brew, filter: "")
            return
        }
        if case .brewUpgradeAll = picked {
            hide()
            onBrew?(.upgrade, nil)
            return
        }
        if case .brew(let package) = picked {
            hide()
            if flags.contains(.command) || (package.installed != nil && package.update == nil) {
                // Its page: what it is, or that it is already there.
                NSWorkspace.shared.open(package.page)
            } else {
                onBrew?(package.installed == nil ? .install : .upgrade, package)
            }
            return
        }
        if case .command(let command) = picked, command.id == .searchHistory {
            enterMode(.history, filter: "")
            return
        }
        if case .visit(let visit) = picked {
            hide()
            onOpenVisit?(visit, flags.contains(.command))
            return
        }
        if case .script(let command, _) = picked {
            if command.arguments.isEmpty {
                hide()
                onRunScript?(command, [])
            } else {
                scriptInput = (command, [])
                enterMode(.script, filter: "")
            }
            return
        }
        if mode == .script, var input = scriptInput {
            let argument = input.command.arguments[input.values.count]
            if case .scriptChoice(_, let value) = picked {
                input.values.append(value)
            } else {
                let text = searchField.stringValue
                guard !text.isEmpty || argument.optional else {
                    say("\(input.command.title) needs “\(argument.placeholder)”: type it, then ↩.")
                    return
                }
                input.values.append(text)
            }
            if input.values.count == input.command.arguments.count {
                hide()
                onRunScript?(input.command, input.values)
            } else {
                scriptInput = input
                enterMode(.script, filter: "")
            }
            return
        }
        if case .project(let project) = picked {
            hide()
            onOpenProject?(project, flags.contains(.command))
            return
        }
        if case .command(let command) = picked, command.id == .searchTabs {
            enterMode(.tabs, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .searchFiles {
            enterMode(.files, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .searchContacts {
            enterMode(.contacts, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .agenda {
            enterMode(.agenda, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .reminders {
            enterMode(.reminders, filter: "")
            return
        }
        if case .command(let command) = picked, command.id == .github {
            enterMode(.github, filter: "")
            return
        }
        if case .addReminder(let request) = picked {
            hide()
            onAddReminder?(request)
            return
        }
        if case .pullRequest(let pullRequest) = picked {
            learning.record(query: query, item: picked.learningID)
            hide()
            if flags.contains(.command) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string)
            } else {
                github?.open(pullRequest.url)
            }
            return
        }
        if case .githubNotification(let notification) = picked {
            hide()
            if flags.contains(.command) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(notification.url.absoluteString, forType: .string)
            } else if let github {
                // Read once opened, as on github.com.
                github.open(notification.url)
                Task { try? await github.markRead(notification) }
            }
            return
        }
        if case .reminder(let item) = picked {
            if flags.contains(.command) {
                hide()
                reminders?.openReminders()
            } else if flags.contains(.shift) {
                if let link = item.link {
                    hide()
                    reminders?.openURL(link)
                } else {
                    say("“\(item.title)” has no link to open: ⌘K shows what it can do.")
                }
            } else {
                toggleReminder(item, row: row)
            }
            return
        }
        if case .command(let command) = picked, command.id == .copyAvailability {
            learning.record(query: query, item: picked.learningID)
            hide()
            onShowAgenda?(.availability)
            return
        }
        if case .createEvent(let request) = picked {
            hide()
            onCreateEvent?(request)
            return
        }
        if case .event(let event) = picked {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { learning.record(query: query, item: picked.learningID) }
            hide()
            if flags.contains(.command) {
                calendar?.openInCalendar(event)
            } else if flags.contains(.shift) {
                if calendar?.mailAttendees(event) != true { onShowEvent?(event) }
            } else {
                calendar?.join(event)
            }
            return
        }
        if case .contact(let match) = picked {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { learning.record(query: query, item: picked.learningID) }
            hide()
            if flags.contains(.command) {
                ContactBook.openInContacts(match.record.id)
            } else {
                onShowContact?(match.record)
            }
            return
        }
        if case .file(let file) = picked {
            hide()
            if flags.contains(.command) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } else {
                NSWorkspace.shared.open(file.url)
            }
            Log.trace("File \(flags.contains(.command) ? "shown in Finder" : "opened")")
            return
        }
        if case .browserTab(let tab) = picked {
            hide()
            BrowserTabs.focus(tab)
            return
        }
        if case .openWindow(let window) = picked {
            hide()
            onFocusWindow?(window)
            return
        }
        if case .layout(let layout) = picked {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { learning.record(query: query, item: picked.learningID) }
            hide()
            onLayout?(layout)
            return
        }
        if case .saveLayout(let name) = picked {
            hide()
            onSaveLayout?(name)
            return
        }
        if case .quicklink(let link, let typed, _) = picked {
            // Nothing typed for it: the selected text, when there is some.
            let wanted = quicklinkQuery(link, typed: typed)
            // Picked by name: its keyword in the field, the query to type.
            if wanted.isEmpty, link.takesQuery, !link.keyword.isEmpty {
                searchField.stringValue = link.keyword + " "
                searchField.currentEditor()?.selectedRange = NSRange(location: (searchField.stringValue as NSString).length, length: 0)
                updateResults(query: searchField.stringValue)
                return
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { learning.record(query: query, item: picked.learningID) }
            hide()
            if let url = link.address(for: wanted) { onOpenURL?(url) }
            return
        }
        if case .startTimer(let request) = picked {
            hide()
            onStartTimer?(request)
            return
        }
        if case .keepAwake(let request) = picked {
            hide()
            onKeepAwake?(request)
            return
        }
        if case .runningTimer(let timer) = picked {
            hide()
            onCancelTimer?(timer)
            return
        }
        if case .keptAwake = picked {
            hide()
            onKeepAwake?(.allowSleep)
            return
        }
        if case .recordNamed(let name) = picked {
            hide()
            onRecord?(name)
            return
        }
        if case .recording = picked {
            hide()
            onRecordingControl?(.stop)
            return
        }
        if case .emoji(let emoji) = picked {
            // Found by meaning: those words find it by name next time.
            let saidAs = isShowingFeeling ? feeling?.query : nil
            hide()
            onEmoji?(emoji, flags.contains(.command), saidAs)
            return
        }
        if case .gif(let gif) = picked {
            let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
            hide()
            onGIF?(gif, flags.contains(.command) ? .copy : .paste, query)
            return
        }
        if case .menuItem(_, let item) = picked {
            let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "The app"
            hide()
            // Pressed once the launcher is gone and out of this key's
            // handling, as Ask does: an app slow to answer Accessibility
            // never holds the keys. Refused: said, with its keys.
            DispatchQueue.main.async { [weak self] in
                let pressed = AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
                Log.actions.notice("Menu item chosen from the launcher: \(pressed ? "done" : "refused", privacy: .public)")
                guard !pressed else { return }
                let place = MenuCandidates.display(item.components)
                MainActor.assumeIsolated {
                    self?.onFailure?("\(app) did not choose \(place): choose it in its menu\(item.shortcut.map { " or press \($0)" } ?? "").")
                }
            }
            return
        }
        if case .process(let group, _) = picked {
            // The launcher closes; the card confirms, then says it is done.
            hide()
            onQuitProcess?(group, flags.contains(.shift))
            return
        }
        if case .calculation(let result) = picked {
            hide()
            onCalculation?(result, !flags.contains(.command))
            return
        }
        if case .snippet(let snippet) = picked {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                learning.record(query: query, item: picked.learningID)
            }
            // Hide first: it goes to the app that was in front.
            hide()
            onSnippet?(snippet, flags.contains(.command))
            return
        }
        if case .clip(let item) = picked {
            // Hide first: the paste goes to the app that was in front.
            hide()
            onClip?(item, flags.contains(.command) ? .copy : flags.contains(.shift) ? .pastePlain : .paste)
            return
        }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty, case .ask = picked {
            // Asking is not a pick to learn.
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            learning.record(query: query, item: picked.learningID)
        }
        let entry: AppIndex.Entry
        switch picked {
        case .app(let app):
            entry = app
        case .command(let command):
            // Run first: hiding the key panel hands focus back to the previous
            // app, which would otherwise win over a window the command opens.
            onCommand?(command.id)
            hide()
            return
        case .siCommand(let command):
            // Hide first: the command works on the app that was in front.
            hide()
            onSICommand?(command.id, nil)
            return
        case .ask(let text):
            hide()
            onSICommand?(PromptLibrary.askID, text)
            return
        case .setup:
            return
        case .system(let command, _):
            hide()
            onSystemCommand?(command)
            return
        case .process, .clip, .snippet, .calculation, .emoji, .gif, .layout, .saveLayout, .openWindow, .startTimer, .keepAwake, .runningTimer, .keptAwake,
             .recordNamed, .recording, .recorded, .quicklink, .browserTab, .file, .contact, .event, .createEvent, .reminder, .addReminder, .project, .script, .scriptArgument, .scriptChoice, .visit, .brew, .brewUpgradeAll,
             .pullRequest, .githubNotification, .catalog, .catalogHeader, .menuItem:
            return
        }
        hide()
        usage.recordLaunch(of: entry.url)
        NSWorkspace.shared.openApplication(at: entry.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.actions.error("Launch failed for \(entry.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc private func rowDoubleClicked() {
        // A group's name is not a row to run.
        if results.indices.contains(tableView.clickedRow), case .catalogHeader = results[tableView.clickedRow] { return }
        launchSelected()
    }

    // MARK: - Aliases

    /// The mode a command turns the launcher into, if it does. Read in
    /// the event tap too: a shortcut into a mode runs inline
    /// (`SkilliAction.runsInline`).
    nonisolated static func mode(for id: LauncherCommand.ID) -> Mode? {
        switch id {
        case .killProcess: .kill
        case .clipboardHistory: .clipboard
        case .emoji: .emoji
        case .searchGIFs: .gifs
        case .switchWindow: .windows
        case .searchMenus: .menus
        case .searchTabs: .tabs
        case .searchProjects: .projects
        case .searchRecordings: .recordings
        case .searchHistory: .history
        case .homebrew: .brew
        case .searchFiles: .files
        case .searchContacts: .contacts
        case .agenda: .agenda
        case .reminders: .reminders
        case .github: .github
        case .catalog: .catalog
        case .searchSnippets: .snippets
        default: nil
        }
    }

    /// "e smile": the aliased command's mode with "smile", a skillie's first
    /// argument, a quicklink's query. False when the alias opens nothing
    /// (an app, a plain command): it then only comes first.
    private func openAlias(_ text: String) -> Bool {
        guard mode == nil, let (alias, rest) = LauncherAliases.split(text, among: aliases()), let item = resolve(learnedID: alias.id) else { return false }
        switch item {
        case .command(let command):
            guard let next = Self.mode(for: command.id) else { return false }
            enterMode(next, filter: rest)
            return true
        case .script(let command, _) where !command.arguments.isEmpty:
            scriptInput = (command, [])
            enterMode(.script, filter: rest)
            return true
        default:
            return false
        }
    }

    /// The item the text's alias names: alone ("e") or with a space and
    /// more ("g rust": a quicklink with its query).
    private func aliasedItem(_ text: String) -> LauncherItem? {
        if let alias = LauncherAliases.exact(text, among: aliases()) { return resolve(learnedID: alias.id) }
        guard let (alias, rest) = LauncherAliases.split(text, among: aliases()), let item = resolve(learnedID: alias.id) else { return nil }
        if case .quicklink(let link, _, _) = item { return .quicklink(link, query: rest) }
        return item
    }

    /// The items an alias can open: what the launcher finds again by id.
    func takesAlias(_ item: LauncherItem) -> Bool {
        switch item {
        case .app, .command, .siCommand, .script, .quicklink, .layout, .snippet, .system: true
        default: false
        }
    }

    /// The results again for what is typed (an alias changed).
    func refreshResults() {
        updateResults(query: searchField.stringValue)
    }

    /// ⌘K → Ask About This Meeting…: the list becomes a field; ↩ sends the
    /// question (empty: nothing), the answer comes in the card.
    func askAboutRecording(_ summary: RecordingSummary) {
        actionPanel.ask("Ask about “\(summary.title)”", initial: "", placeholder: "What did they decide about…?",
                        line: "Type your question, ↩ asks \(recordingProvider()), esc goes back") { [weak self] typed in
            guard let self else { return }
            let question = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            self.closeActions()
            guard !question.isEmpty else { return }
            self.hide()
            self.onAskAboutRecording?(summary.folder, question)
        }
    }

    /// ⌘K → Rename Recording…: the list becomes a field, its title in it;
    /// ↩ renames it (its folder too), empty or unchanged: nothing.
    func renameRecording(_ summary: RecordingSummary) {
        actionPanel.ask("Rename “\(summary.title)”", initial: summary.title, placeholder: "Title",
                        line: "Type its name, ↩ renames it and its folder, esc goes back") { [weak self] typed in
            guard let self else { return }
            let title = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            self.closeActions()
            guard !title.isEmpty, title != summary.title else { return }
            // Its rows follow once the recordings are read again.
            self.onRenameRecording?(summary.folder, title)
        }
    }

    /// ⌘K → Set Alias…: the list becomes a field; ↩ saves (empty removes).
    /// One not taken asks again, with what was typed.
    func askAlias(for item: LauncherItem, retry typed: String? = nil) {
        let id = item.learningID
        let title = item.title
        let header = typed == nil ? "Alias for \(title)" : "Alias for \(title): one word, 12 letters at most"
        actionPanel.ask(header, initial: typed ?? aliasByID[id] ?? "") { [weak self] typed in
            guard let self else { return }
            let alias = LauncherAliases.normalized(typed)
            // Asked again, the list's header saying what an alias is.
            guard alias.isEmpty || LauncherAliases.isValid(alias) else {
                self.askAlias(for: item, retry: String(alias.filter { !$0.isWhitespace }.prefix(12)))
                return
            }
            self.onSetAlias?(id, title, alias)
            self.closeActions()
            self.updateResults(query: self.searchField.stringValue)
        }
    }

    // MARK: - Catalog ("?")

    /// Everything skil.li does, read once as the Catalog opens: what the
    /// user made, the launcher row each entry stands for, the shortcuts.
    /// A key then only filters in memory.
    private func loadCatalog() {
        catalogMade = catalogInput?() ?? FeatureCatalog.Input()
        catalogEntries = FeatureCatalog.entries(catalogMade)
        catalogShortcuts = shortcutKeys?() ?? [:]
        catalogCaps = [:]
        var items: [String: LauncherItem] = [:]
        for entry in catalogEntries {
            if let item = launcherItem(for: entry) { items[entry.id] = item }
        }
        catalogItems = items
    }

    /// Each group's entries under its name. The first group has no row of
    /// its own: its name is the header above the list.
    private static func catalogRows(_ entries: [CatalogEntry]) -> [LauncherItem] {
        var rows: [LauncherItem] = []
        for (index, section) in FeatureCatalog.sections(entries).enumerated() {
            if index > 0 { rows.append(.catalogHeader(section.group)) }
            rows += section.entries.map(LauncherItem.catalog)
        }
        return rows
    }

    /// The launcher row `entry` stands for, when it has one: Return then
    /// does exactly what that row does.
    private func launcherItem(for entry: CatalogEntry) -> LauncherItem? {
        switch entry.run {
        case .command(let id): LauncherCommand.all.first { $0.id == id }.map(LauncherItem.command)
        case .system(let command): .system(.system(command), title: command.title)
        case .window(let layout): .system(.window(layout), title: layout.title)
        case .ask: .siCommand(LauncherSICommand(id: PromptLibrary.askID, title: "Ask"))
        case .prompt(let id): .siCommand(LauncherSICommand(id: id, title: entry.title))
        case .snippet(let id): catalogMade.snippets.first { $0.id == id }.map(LauncherItem.snippet)
        case .skillie(let path): catalogMade.skillies.first { $0.path == path }.map { LauncherItem.script($0, inline: nil) }
        case .quicklink(let id): catalogMade.quicklinks.first { $0.id == id }.map { LauncherItem.quicklink($0, query: "") }
        case .layout(let id): catalogMade.layouts.first { $0.id == id }.map(LauncherItem.layout)
        case .appLink(let id): catalogMade.appLinks.first { $0.id == id }.map { LauncherItem.system(.appLink($0, variant: nil), title: $0.title) }
        case .shortcut(let id):
            catalogMade.shortcuts.first { $0.id == id }.map { LauncherItem.system(.shortcut($0, withSelection: false), title: $0.name) }
        case .type, .askByVoice, .dictate, .transform, .settings: nil
        }
    }

    /// Return on an entry: what its launcher row does, or the start of
    /// what to type in the field.
    private func runCatalog(_ entry: CatalogEntry, flags: NSEvent.ModifierFlags) {
        switch entry.run {
        case .type(let text, let hint):
            leaveMode(update: false)
            searchField.placeholderString = hint ?? "Search"
            searchField.stringValue = text
            searchField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            // Read as typed: "timer " then the user's words.
            controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        case .askByVoice:
            // Hide first: Ask works on the app that was in front.
            hide()
            onAction?(.askByVoice)
        case .dictate:
            // Hide first: the words go to the app that was in front.
            hide()
            onAction?(.dictate)
        case .transform(let transform):
            hide()
            onAction?(.transformSelection(transform))
        case .settings(let place):
            // Open first: hiding hands the focus back to the previous app.
            // "catalog/quicklinks": the pane, then the part of it.
            let parts = place.split(separator: "/", maxSplits: 1).map(String.init)
            if let pane = parts.first.flatMap(SettingsPane.init(rawValue:)) { onSettingsPane?(pane, parts.dropFirst().first) }
            hide()
        default:
            guard let item = catalogItems[entry.id] else {
                say("“\(entry.title)” is no longer there: it was removed meanwhile. Type ? again to see what is.")
                return
            }
            // Out of the Catalog first: a mode, a skillie's arguments or a
            // quicklink's query take the field.
            leaveMode(update: false)
            launch(item, row: tableView.selectedRow, flags: flags)
        }
    }

    /// A `skilli://` link to `entry` opened (`LinkRunner`, after the card
    /// asked when it must), or a key bound to a skillie that asks
    /// arguments (`ActionRunner`): what Return on it in the "?" does. What needs
    /// the launcher (a mode, words to go on with, a quicklink's query, a
    /// skillie's arguments) opens it first; the rest runs without it.
    func run(fromLink entry: CatalogEntry) {
        loadCatalog()
        // Closed: what was typed last is not what the link asks for (a
        // pick to learn). What it held stays kept for the next show.
        if !isVisible { searchField.stringValue = "" }
        let needsLauncher: Bool = switch entry.run {
        case .command(let id): Self.mode(for: id) != nil
        case .type, .quicklink: true
        case .skillie(let path): catalogMade.skillies.first { $0.path == path }.map { !$0.arguments.isEmpty } ?? false
        default: false
        }
        let wasVisible = isVisible
        if needsLauncher, !isVisible { show(triggeredAt: .now, keeping: { _ in false }) }
        runCatalog(entry, flags: [])
        // Opened for the link: esc goes back to the app.
        if !wasVisible, mode != nil { modeBack = nil }
    }

    /// The group of the entry at `row`, or of the first one after it.
    private func catalogGroup(atRow row: Int) -> CatalogEntry.Group? {
        guard row >= 0, row < results.count else { return nil }
        for item in results[row...] {
            if case .catalog(let entry) = item { return entry.group }
            if case .catalogHeader(let group) = item { return group }
        }
        return nil
    }

    /// The header above the list names the group at its top, as the rows
    /// scroll: a group's own name still in sight names it itself.
    @objc private func listScrolled() {
        guard mode == .catalog else { return }
        var row = tableView.row(at: NSPoint(x: 1, y: tableView.visibleRect.minY + 0.5))
        if results.indices.contains(row), case .catalogHeader = results[row] { row -= 1 }
        if let group = catalogGroup(atRow: max(row, 0)) { sectionHeader.stringValue = group.title }
    }

    /// What Return does on `entry`, in one word for the footer and ⌘K.
    func catalogReturnTitle(_ entry: CatalogEntry) -> String {
        switch entry.run {
        case .command(let id): Self.returnTitle(id)
        case .type, .settings, .ask, .askByVoice, .dictate, .quicklink: "Open"
        case .snippet: "Paste"
        case .layout: "Apply"
        case .system, .window, .transform, .prompt, .skillie, .appLink, .shortcut: "Run"
        }
    }

    /// The action a shortcut runs for `entry`, when one can: the same as
    /// Settings → Catalog records (`CatalogEntry.shortcutAction`).
    private func catalogAction(_ entry: CatalogEntry) -> SkilliAction? {
        entry.shortcutAction(skillies: catalogMade.skillies)
    }

    /// Its shortcut from Settings → Keys; skil.li Settings also has the
    /// launcher's own ⌘,.
    private func catalogShortcut(_ entry: CatalogEntry) -> [Chord]? {
        guard let action = catalogAction(entry) else { return nil }
        if let chords = catalogShortcuts[action.id] { return chords }
        return action == .openSettings ? openSettingsChord.map { [$0] } : nil
    }

    /// How to reach `entry`, one array of keycaps per way: the prefix, the
    /// user's alias (only on an entry that is a launcher row of its own),
    /// the shortcut.
    private func catalogKeys(_ entry: CatalogEntry) -> [[String]] {
        var ways: [[String]] = []
        if let prefix = entry.prefix?.trimmingCharacters(in: .whitespaces), !prefix.isEmpty { ways.append([prefix]) }
        if catalogItems[entry.id]?.learningID == entry.id, let alias = aliasByID[entry.id] { ways.append([alias]) }
        if let chords = catalogShortcut(entry) { ways.append(chords.map(\.description)) }
        return ways
    }

    /// The keycaps of `entry`, made once and kept until its keys change.
    private func catalogKeycaps(_ entry: CatalogEntry) -> (keys: [[String]], caps: [[KeycapView]]) {
        let keys = catalogKeys(entry)
        if let cached = catalogCaps[entry.id], cached.keys == keys { return cached }
        let made = (keys: keys, caps: keys.map { $0.map(KeycapView.init) })
        catalogCaps[entry.id] = made
        return made
    }

    private func configureCatalog(_ cell: CatalogCellView, _ entry: CatalogEntry) {
        // skil.li's own Settings wear its icon, as in the launcher.
        let icon = entry.run == .command(.openSettings) ? CommandIcon.brand : CommandIcon.image(for: entry.symbol)
        let keycaps = catalogKeycaps(entry)
        // Off in Settings → Catalog: dimmed, still there to run.
        cell.configure(title: entry.title, oneLine: entry.oneLine, icon: icon, keys: keycaps.keys, caps: keycaps.caps,
                       off: entry.canBeOff && off.contains(entry.id))
    }

    /// ⌘K on an entry: run it; its alias when it is a launcher row of its
    /// own; its shortcut, set in Settings → Keys.
    func catalogActions(_ entry: CatalogEntry) -> [LauncherAction] {
        var list = [LauncherAction(title: catalogReturnTitle(entry), symbol: "return", key: .open) { [weak self] in
            self?.launchSelected(flags: [])
        }]
        if let item = catalogItems[entry.id], item.learningID == entry.id, takesAlias(item) {
            list += aliasActions(for: item)
            if takesPin(item) { list.append(pinAction(for: item)) }
        }
        if let action = catalogAction(entry) {
            // Its keys, recorded right away and said in the card, as on
            // an app's row.
            list.append(LauncherAction(title: catalogShortcut(entry) == nil ? "Set Shortcut…" : "Change Shortcut…", symbol: "keyboard") { [weak self] in
                self?.hide()
                self?.onSetShortcut?(action, entry.title)
            })
        }
        // Its link: another app, Shortcuts or a Stream Deck runs it.
        list.append(copyLinkAction(SkilliLink.link(for: entry, quicklinks: catalogMade.quicklinks, skilliePath: skilliePath)))
        return list
    }

    /// Self-test hooks: the Catalog's groups as listed, the header above
    /// the list, and each drawn row's keycaps by its title.
    var shownCatalogGroups: [String] {
        FeatureCatalog.sections(results.compactMap { if case .catalog(let entry) = $0 { entry } else { nil } }).map(\.group.title)
    }

    var headerText: String { sectionHeader.stringValue }

    /// Self-test hook: every Catalog row drawn in the list (the views the
    /// table holds, by the row it says they are at) that shows another
    /// entry than the list has there.
    var catalogCellMismatches: [String] {
        var found: [String] = []
        for case let rowView as NSTableRowView in tableView.subviews {
            let row = tableView.row(for: rowView)
            for case let cell as CatalogCellView in rowView.subviews {
                let expected = results.indices.contains(row) ? results[row].title : "nothing"
                if cell.shownTitle != expected { found.append("row \(row) at y \(Int(rowView.frame.minY)): \(cell.shownTitle), not \(expected)") }
            }
        }
        return found
    }

    /// Entries that say they are a launcher row ("cmd:…", "system:…") but
    /// are not that row: their alias would be another item's.
    var catalogRowMismatches: [String] {
        catalogEntries.filter { !$0.id.hasPrefix("catalog.") && catalogItems[$0.id]?.learningID != $0.id }.map(\.id)
    }

    /// Self-test hook: the Catalog rows drawn dimmed, "Off".
    var shownCatalogOff: [String] {
        (0..<tableView.numberOfRows).compactMap { row in
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? CatalogCellView).flatMap { $0.isOff ? $0.shownTitle : nil }
        }
    }

    var shownCatalogKeys: [String: [[String]]] {
        var keys: [String: [[String]]] = [:]
        for row in 0..<tableView.numberOfRows {
            guard case .catalog(let entry) = results[row],
                  let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? CatalogCellView else { continue }
            keys[entry.title] = cell.shownKeys
        }
        return keys
    }

    // MARK: - Actions (⌘K)

    /// ⌘K: the selected row's actions over the list.
    func showActions() {
        let row = tableView.selectedRow
        guard results.indices.contains(row) else {
            say("No row to act on: type until one is listed, then ⌘K.")
            return
        }
        actionsItem = results[row]
        actionPanel.show(actions(for: results[row]), for: results[row].title)
        footerBeforeActions = hints.shown
        hints.setHints([("Run", "↩"), ("Back", "esc")])
    }

    func closeActions() {
        guard !actionPanel.isHidden else { return }
        actionPanel.isHidden = true
        actionsItem = nil
        if let footerBeforeActions { hints.setHints(footerBeforeActions) }
        footerBeforeActions = nil
    }

    private func runAction(_ action: LauncherAction) {
        let searched = mode == nil ? searchField.stringValue : nil
        if !action.keepsOpen { closeActions() }
        action.run()
        // Acted on: the launcher closed for it.
        if let searched, !panel.isVisible { recentSearches.record(searched) }
    }

    /// The action `key` runs in `list` for `item`: ⌘C falls back to its
    /// first copy (⌘↩ where that copies), then to its title.
    private func action(_ key: LauncherAction.Key, in list: [LauncherAction], for item: LauncherItem) -> LauncherAction? {
        // The day's rates not here yet: ⌘C has nothing to copy either.
        if case .calculation(let result) = item, result.isWaiting { return nil }
        return LauncherAction.find(key, in: list) ?? (key == .copy ? copyTitleAction(item) : nil)
    }

    /// The selected row's action for `key`, run.
    private func runSelectedAction(_ key: LauncherAction.Key) -> Bool {
        let row = tableView.selectedRow
        guard results.indices.contains(row), let action = action(key, in: actions(for: results[row]), for: results[row]) else { return false }
        let searched = mode == nil ? searchField.stringValue : nil
        action.run()
        if let searched, !panel.isVisible { recentSearches.record(searched) }
        return true
    }

    /// A key while ⌘K's list is open: arrows move, ↩ runs the selected
    /// action, an action's own key runs it, letters filter, esc or ⌘K go
    /// back to the results. A key that does nothing here says so in the list.
    private func actionPanelKey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        // Typing an alias in the list: ↩ saves it.
        if actionPanel.isPrompting, flags.isEmpty, code == kVK_Return || code == kVK_ANSI_KeypadEnter {
            actionPanel.submit()
            return
        }
        // ⌘A selects its text again, ← or → keeps it to edit.
        if actionPanel.isPrompting, flags == .command, event.charactersIgnoringModifiers?.lowercased() == "a" {
            actionPanel.selectAll()
            return
        }
        if actionPanel.isPrompting, code == kVK_LeftArrow || code == kVK_RightArrow {
            actionPanel.keepText()
            return
        }
        if code == kVK_Escape || (flags == .command && event.charactersIgnoringModifiers?.lowercased() == "k") {
            closeActions()
        } else if code == kVK_UpArrow {
            actionPanel.move(by: -1, wraps: !event.isARepeat)
        } else if code == kVK_DownArrow {
            actionPanel.move(by: 1, wraps: !event.isARepeat)
        } else if let step = Self.controlStep(event) {
            actionPanel.move(by: step, wraps: !event.isARepeat)
        } else if let key = LauncherAction.Key(event) {
            let found = key == .open ? actionPanel.selectedAction
                : actionsItem.flatMap { action(key, in: actionPanel.actions, for: $0) } ?? LauncherAction.find(key, in: actionPanel.actions)
            if let found {
                runAction(found)
            } else if key == .open {
                actionPanel.say("No action matches “\(actionPanel.filter)”: ⌫ shows them again.")
            } else {
                actionPanel.say("Nothing on \(key.label) here: pick an action in the list.")
            }
        } else if code == kVK_Delete, flags.isEmpty || flags == .option {
            actionPanel.deleteBackward()
        } else if flags.isDisjoint(with: [.command, .control]), let text = event.characters, !text.isEmpty,
                  text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .privateUse }) {
            actionPanel.type(text)
        }
    }

    // MARK: - Footer, ⇥, esc

    /// The selected row's own keys: its ↩ as ⌘K lists it, ⇥ where it does
    /// something, ⌘K. On every key and selection: a switch and a lookup.
    private func updateFooter() {
        let row = tableView.selectedRow
        let item = results.indices.contains(row) ? results[row] : nil
        let footer = mode == .github && github?.isSignedIn != true
            ? [(label: "Settings", key: "↩")]
            // The "maybe?" row, not selected: ↓ reaches it.
            : isShowingSnippetMaybe && item == nil ? [(label: "Maybe", key: "↓")]
            : LauncherFooter.hints(main: item.flatMap { mainAction(for: $0)?.title }, tab: tab(for: item))
        // Under ⌘K's list: put back as it closes.
        if actionPanel.isHidden { hints.setHints(footer) } else { footerBeforeActions = footer }
    }

    /// What ⇥ does now on `item` (the selected row): Ask outside the
    /// modes, a mode's own, else the row's actions. Never Ask in a mode.
    private func tab(for item: LauncherItem?) -> LauncherTab {
        LauncherTab.of(inMode: mode != nil, own: ownTab(item), hasRow: item != nil,
                       typed: !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty, canAsk: onSICommand != nil)
    }

    /// A mode's own ⇥, as the footer names it, when it does something now.
    private func ownTab(_ item: LauncherItem?) -> String? {
        let typed = !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        switch mode {
        case .kill:
            if unfolded == nil, case .process(let group, nil)? = item, group.entries.count > 1 { return "Processes" }
            return nil
        // Not while it searches; not answered: ⇥ asks again.
        case .clipboard:
            return meaningAvailable && typed && !isSearchingClipboardMeaning
                && (!isShowingMeaning || meaning?.result.unanswered != nil) ? "By Meaning" : nil
        case .files: return fileMeaningOn && typed && !isShowingFileMeaning ? "By Meaning" : nil
        case .history: return historyMeaningOn && typed && !isShowingHistoryMeaning ? "By Meaning" : nil
        case .snippets: return snippetMeaningOn && typed && !isShowingSnippetMeaning && !snippetList.isEmpty ? "By Meaning" : nil
        case .emoji: return feelingAvailable && typed && !isShowingFeeling ? "By Feeling" : nil
        case .agenda:
            if case .event? = item { return "Details" }
            return nil
        default: return nil
        }
    }

    /// ⇥: what the footer says it does.
    private func pressTab() {
        let row = tableView.selectedRow
        let item = results.indices.contains(row) ? results[row] : nil
        switch tab(for: item) {
        case .ask:
            // Select something anywhere, open skil.li, type, Tab: Ask does it.
            askWithQuery()
        case .actions:
            showActions()
        case .nothing:
            break
        case .own:
            switch mode {
            case .kill:
                // Unfold an app into its processes, to stop just one.
                if case .process(let group, _)? = item {
                    unfolded = group.key
                    updateResults(query: searchField.stringValue)
                }
            case .clipboard: searchClipboardByMeaning()
            case .emoji: searchEmojiByFeeling(after: .zero)
            case .snippets: searchSnippetsByMeaning()
            case .files: searchFilesByMeaning()
            case .history: searchHistoryByMeaning()
            case .agenda:
                if case .event(let event)? = item {
                    hide()
                    onShowEvent?(event)
                }
            default: showActions()
            }
        }
    }

    /// esc, one step back: ⌘K's list closes, an app unfolded folds, a mode
    /// goes back to the root search as it was before it, then the
    /// launcher closes. A mode opened straight (✦C) closes at once.
    func escape() {
        switch LauncherEscape.of(showingActions: !actionPanel.isHidden, unfolded: unfolded != nil, inMode: mode != nil, back: modeBack) {
        case .closeActions:
            closeActions()
        case .fold:
            unfolded = nil
            updateResults(query: searchField.stringValue)
        case .root(let text):
            leaveMode(update: false)
            searchField.stringValue = text
            searchField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            updateResults(query: text)
        case .close:
            hide()
        }
    }

    /// What failed and what to do, in one line (rule 6: never a bare
    /// beep): in the footer's place while the launcher is open, until the
    /// next key; once it closed, in the card.
    func say(_ line: String) {
        guard panel.isVisible else {
            onFailure?(line)
            return
        }
        footerNote.stringValue = line
        footerNote.toolTip = line
        footerNote.isHidden = false
        hints.isHidden = true
    }

    private func clearNote() {
        guard !footerNote.isHidden else { return }
        footerNote.isHidden = true
        hints.isHidden = false
    }

    /// Self-test hooks: the footer as shown (its note when one is said),
    /// and the note in ⌘K's list.
    var shownFooter: [String] {
        footerNote.isHidden ? hints.shown.map { "\($0.label) \($0.key)" } : [footerNote.stringValue]
    }
    var shownNote: String? { footerNote.isHidden ? nil : footerNote.stringValue }
    var shownActionsNote: String? { actionPanel.note }

    /// Self-test hooks: ⌘K's list as shown, each action with its key.
    var isShowingActions: Bool { !actionPanel.isHidden }
    var shownActions: [(title: String, key: String?)] { actionPanel.shown.map { ($0.title, $0.key?.label) } }
    var selectedActionTitle: String? { actionPanel.selectedAction?.title }

    // MARK: - Kept awake

    /// The chip shown, with the time left now, or hidden: outside the
    /// modes with nothing typed, while the Mac is kept awake. Nothing read
    /// once words are typed.
    private func updateAwakeChip(empty: Bool) {
        let awake = mode == nil && empty ? awakeState() : (awake: false, until: nil)
        if awake.awake { awakeChip.show(left: awake.until.map { AwakeStatus.left(until: $0) } ?? "") }
        if awakeChip.isHidden == awake.awake { awakeChip.isHidden = !awake.awake }
    }

    /// Keep Awake changed while the launcher shows (it ended, turned off
    /// from the chip or the menu bar): the rows read again, since Keep
    /// Awake's own row is titled by it ("Turn Off Keep Awake" while awake,
    /// pinned in the empty field too), and the chip with them.
    func awakeChanged() {
        countAwakeDown()
        reloadSources()
    }

    /// A tick every 20 s while it shows and Keep Awake has an end (as the
    /// menu bar's cup counts); none otherwise, gone as it hides.
    private func countAwakeDown() {
        guard panel.isVisible, awakeState().until != nil else {
            awakeTicks?.invalidate()
            awakeTicks = nil
            return
        }
        guard awakeTicks == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.awakeTick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        awakeTicks = timer
    }

    /// The time left again: on the chip, or on the running row (redrawn in
    /// place, the selection kept).
    private func awakeTick() {
        guard panel.isVisible, mode == nil else { return }
        updateAwakeChip(empty: searchField.stringValue.isEmpty)
        if results.contains(where: { if case .keptAwake = $0 { true } else { false } }) { showRows() }
    }

    /// Self-test hooks: the time left the chip says ("" for the cup alone,
    /// nil while hidden), the words drawn now, and where it is on screen.
    var awakeChipText: String? { awakeChip.isHidden ? nil : awakeChip.shownText }
    var awakeChipDrawn: String? { awakeChip.isHidden ? nil : awakeChip.drawnText }
    var awakeChipTip: String? { awakeChip.isHidden ? nil : awakeChip.toolTip }
    var awakeChipScreenFrame: NSRect? {
        guard !awakeChip.isHidden, let window = awakeChip.window else { return nil }
        return window.convertToScreen(awakeChip.convert(awakeChip.bounds, to: nil))
    }

    // MARK: - Layout

    private func position() {
        // The glass, not the window, sits in its place.
        let glass = restingGlassFrame()
        panel.setFrameOrigin(NSPoint(x: glass.minX - Theme.glassMargin, y: glass.minY - Theme.glassMargin))
    }

    /// The glass's height: taller by the GitHub strip while it shows.
    private var glassHeight: CGFloat { Layout.height + (stripShown ? Layout.stripHeight + 1 : 0) }

    /// The GitHub strip under the search field, or not: the glass grows
    /// down by it, the field stays where it was. Only when that changes.
    private func layoutStrip(_ visible: Bool) {
        guard visible != stripShown, let glassContent, let searchBar, let glass = glassViews.first, let root = panel.contentView else { return }
        let top = panel.frame.maxY
        stripShown = visible
        githubStrip.isHidden = !visible
        stripHairline.isHidden = !visible
        let height = glassHeight
        glassContent.setFrameSize(NSSize(width: Layout.width, height: height))
        searchBar.frame.origin.y = Layout.cardHeight + 1 + (visible ? Layout.stripHeight + 1 : 0)
        glass.setFrameSize(NSSize(width: Layout.width, height: height))
        let size = NSSize(width: Layout.width + 2 * Theme.glassMargin, height: height + 2 * Theme.glassMargin)
        root.setFrameSize(size)
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: false)
    }

    /// Self-test hook: what the GitHub strip says, nil while it is hidden.
    var gitHubStripText: String? { stripShown ? githubStrip.shownText : nil }

    /// The strip's counts, from what GitHub said last.
    func updateGitHubStrip() {
        guard let github else { return }
        githubStrip.show(pullRequests: github.pullRequests, unread: github.unreadNotifications.count,
                         problem: github.problem, reading: github.lastRefresh == nil && github.problem == nil)
        if isVisible, mode == .github { updateResults(query: searchField.stringValue) }
    }

    /// Where the launcher's glass shows on its screen (Settings → Launcher →
    /// Opens on: the pointer's by default): where the user dragged it, or
    /// centered with its top 18 % down. The AI card's place when the text's
    /// is unknown.
    func restingGlassFrame() -> NSRect {
        guard let visible = openingScreen()?.visibleFrame else { return .zero }
        let size = NSSize(width: Layout.width, height: glassHeight)
        return (savedPlace() ?? .standard(size: size, in: visible)).frame(size: size, in: visible)
    }

    /// The screen it opens on: the pointer's (as always), the one showing
    /// most of the window in front, or the main display.
    private func openingScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let pointer = screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) }
        let choice = screenChoice()
        let front = choice == .frontWindow ? Self.frontWindowFrame() : nil
        let picked = choice.pick(screens: screens.map(\.frame), pointerScreen: pointer, frontWindow: front)
        return picked.map { screens[$0] } ?? NSScreen.main
    }

    /// The frame of the app in front's front window, in AppKit's
    /// coordinates: the window server's list, front to back (no
    /// Accessibility call that a busy app could hold up, no permission for
    /// frames). Nil when that app shows no window.
    static func frontWindowFrame() -> NSRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let mainHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 1, frame.height > 1
            else { continue }
            return LauncherScreen.appKitFrame(fromTopLeft: frame, mainHeight: mainHeight)
        }
        return nil
    }

    /// Follows the mouse from a click on the glass, pulling the glass onto
    /// the screen's middles and its standard height (a guide shows on each),
    /// then keeps where it was left. The window server's own drag
    /// (`performDrag`) could not be pulled.
    private func drag() {
        let start = NSEvent.mouseLocation
        let startGlass = glassFrame
        var sitsOn: [LauncherGuide] = []
        var moved = false
        panel.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event, event.type == .leftMouseDragged else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? panel.screen else { return }
            let pulled = LauncherPlace.snap(startGlass.offsetBy(dx: mouse.x - start.x, dy: mouse.y - start.y), in: screen.visibleFrame)
            panel.setFrameOrigin(NSPoint(x: pulled.frame.minX - Theme.glassMargin, y: pulled.frame.minY - Theme.glassMargin))
            guides.show(pulled.guides, glass: pulled.frame, in: screen.visibleFrame, below: panel)
            sitsOn = pulled.guides
            moved = true
        }
        guides.hide()
        guard moved, let visible = panel.screen?.visibleFrame else { return }
        if sitsOn.contains(.centerX), sitsOn.contains(.standardTop) {
            // Back on its standard place: it follows the standard again.
            onPlaceChange?(nil)
            return
        }
        var place = LauncherPlace(glass: glassFrame, in: visible)
        if sitsOn.contains(.centerX) { place.across = 0.5 }
        if sitsOn.contains(.centerY) { place.down = 0.5 }
        onPlaceChange?(place)
    }

    /// Its glass on screen, shown or just hidden: the place of the card of a
    /// command it started.
    var glassFrame: NSRect {
        panel.frame.insetBy(dx: Theme.glassMargin, dy: Theme.glassMargin)
    }

    func applyGlassStyle(_ style: NSGlassEffectView.Style) {
        glassViews.forEach { $0.style = style }
    }

    var glassStyles: [NSGlassEffectView.Style] { glassViews.map(\.style) }

    /// ⌘, in the launcher (or whatever Settings → Keys says).
    var onOpenSettings: (() -> Void)? {
        get { panel.onOpenSettings }
        set { panel.onOpenSettings = newValue }
    }

    var openSettingsChord: Chord? {
        get { panel.openSettingsChord }
        set { panel.openSettingsChord = newValue }
    }

    var resolveKey: ((UInt16) -> Key?)? {
        get { panel.resolveKey }
        set { panel.resolveKey = newValue }
    }

    private func buildViews() {
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onEscape = { [weak self] in self?.escape() }
        panel.delegate = self

        // One block: search on top, results below a hairline. Two separate
        // shapes leave a gap where the background and the glass shadow show.
        let content = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        content.addSubview(buildCard())
        content.addSubview(HairlineView(frame: NSRect(x: 16, y: Layout.cardHeight, width: Layout.width - 32, height: 1)))
        // The GitHub strip goes between the results and the search field
        // when it shows (`layoutStrip`).
        githubStrip.frame.origin.y = Layout.cardHeight + 1
        githubStrip.isHidden = true
        githubStrip.onOpen = { [weak self] group in self?.openGitHub(group: group) }
        content.addSubview(githubStrip)
        stripHairline.frame.origin.y = Layout.cardHeight + 1 + Layout.stripHeight
        stripHairline.isHidden = true
        content.addSubview(stripHairline)
        let bar = buildSearchBar()
        bar.frame.origin.y = Layout.cardHeight + 1
        content.addSubview(bar)
        // ⌘K's list, over the results; a click beside it closes it.
        actionPanel.frame = NSRect(x: 0, y: 0, width: Layout.width, height: Layout.cardHeight)
        actionPanel.bottom = Layout.footerHeight + 4
        actionPanel.isHidden = true
        actionPanel.onRun = { [weak self] action in self?.runAction(action) }
        actionPanel.onDismiss = { [weak self] in self?.closeActions() }
        content.addSubview(actionPanel)
        glassContent = content
        searchBar = bar

        let glass = Theme.glass(cornerRadius: Theme.Radius.card, content: content)
        glass.frame.origin = NSPoint(x: Theme.glassMargin, y: Theme.glassMargin)
        glassViews = [glass]

        let root = LauncherMargin(frame: NSRect(origin: .zero, size: Layout.windowSize))
        root.onClick = { [weak self] in self?.hide() }
        root.onDrag = { [weak self] in self?.drag() }
        root.addSubview(glass)
        panel.contentView = root
    }

    private func buildSearchBar() -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.searchHeight))

        // The glass S where Spotlight puts its magnifier: skil.li's own
        // field. In the rows' columns: the S over their icons (28 pt, like
        // the icons' tiles), the text over their titles.
        let logo = NSImageView(frame: NSRect(x: 24, y: (Layout.searchHeight - 28) / 2, width: 28, height: 28))
        logo.image = Theme.brandGlass
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityLabel("skil.li")
        bar.addSubview(logo)

        let fieldHeight: CGFloat = 30
        let fieldX: CGFloat = 66
        searchField.frame = NSRect(
            x: fieldX,
            y: (Layout.searchHeight - fieldHeight) / 2,
            width: Layout.width - 24 - fieldX,
            height: fieldHeight
        )
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = Theme.Font.search
        searchField.placeholderString = "Search"
        searchField.cell?.isScrollable = true
        searchField.cell?.wraps = false
        searchField.delegate = self
        bar.addSubview(searchField)
        fieldFrame = searchField.frame

        // "Kill" before the field while in Kill mode, centered on the
        // field's line.
        modeChip.frame.origin = NSPoint(x: fieldX, y: ((Layout.searchHeight - modeChip.frame.height) / 2).rounded())
        modeChip.isHidden = true
        bar.addSubview(modeChip)

        // The cup at the field's right end, on its line; only while the
        // field is empty, so it never sits over words.
        awakeChip.frame = NSRect(x: Layout.width - 24, y: ((Layout.searchHeight - AwakeChipView.height) / 2).rounded(), width: 0, height: AwakeChipView.height)
        awakeChip.isHidden = true
        awakeChip.onTurnOff = { [weak self] in self?.onKeepAwake?(.allowSleep) }
        bar.addSubview(awakeChip)
        return bar
    }

    private func buildCard() -> NSView {
        let card = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.cardHeight))

        // Footer: keyboard hints on the right.
        hints.frame = NSRect(x: 20, y: 0, width: Layout.width - 40, height: Layout.footerHeight)
        hints.setHints([("Open", "↩"), LauncherFooter.actions])
        card.addSubview(hints)
        // A failure said in the footer's place, until the next key.
        footerNote.font = Theme.Font.hint
        footerNote.textColor = .secondaryLabelColor
        footerNote.lineBreakMode = .byTruncatingTail
        footerNote.frame = NSRect(x: 24, y: (Layout.footerHeight - 16) / 2, width: Layout.width - 48, height: 16)
        footerNote.isHidden = true
        card.addSubview(footerNote)

        let hairline = HairlineView(frame: NSRect(x: 16, y: Layout.footerHeight, width: Layout.width - 32, height: 1))
        card.addSubview(hairline)

        // Result list.
        let listFrame = NSRect(
            x: 0,
            y: Layout.footerHeight + 1 + Layout.listBottomPadding,
            width: Layout.width,
            height: Layout.listHeight
        )
        let scrollView = NSScrollView(frame: listFrame)
        listScroll = scrollView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.width = Layout.width
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Layout.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.refusesFirstResponder = true
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        scrollView.documentView = tableView
        card.addSubview(scrollView)
        // The Catalog's header follows the group at the top of the list.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(listScrolled), name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)

        emptyState.font = Theme.Font.rowTitle
        emptyState.textColor = .tertiaryLabelColor
        emptyState.alignment = .center
        emptyState.frame = NSRect(x: 0, y: listFrame.midY - 10, width: Layout.width, height: 20)

        // The previews right of the narrowed list: the clipboard history's,
        // Search Snippets'.
        for preview in [clipPreview, snippetPreview] as [NSView] {
            preview.frame = NSRect(x: Layout.splitListWidth, y: Layout.footerHeight + 1,
                                   width: Layout.width - Layout.splitListWidth, height: Layout.cardHeight - Layout.footerHeight - 1)
            preview.isHidden = true
            card.addSubview(preview)
        }
        emptyState.isHidden = true
        // The emoji picker's grid, in the list's place.
        emojiGrid.isHidden = true
        emojiGrid.onSelect = { [weak self] index in
            self?.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        emojiGrid.onOpen = { [weak self] _ in self?.launchSelected() }
        emojiGrid.onTopSection = { [weak self] name in
            guard let self, self.mode == .emoji, let name else { return }
            self.sectionHeader.stringValue = name
        }
        card.addSubview(emojiGrid)
        gifGrid.isHidden = true
        gifGrid.onSelect = { [weak self] index in
            self?.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        gifGrid.onOpen = { [weak self] _ in self?.launchSelected() }
        gifGrid.onTopSection = { [weak self] name in
            guard let self, self.mode == .gifs, let name else { return }
            self.sectionHeader.stringValue = name
        }
        card.addSubview(gifGrid)
        card.addSubview(emptyState)
        meaningSpinner.style = .spinning
        meaningSpinner.controlSize = .small
        meaningSpinner.isDisplayedWhenStopped = false
        meaningSpinner.isHidden = true
        card.addSubview(meaningSpinner)

        // Section header (top).
        sectionHeader.font = Theme.Font.sectionHeader
        sectionHeader.textColor = .secondaryLabelColor
        sectionHeader.frame = NSRect(x: 24, y: Layout.cardHeight - Layout.headerHeight + 8, width: 300, height: 16)
        card.addSubview(sectionHeader)
        selectionLabel.font = Theme.Font.sectionHeader
        selectionLabel.textColor = .tertiaryLabelColor
        selectionLabel.alignment = .right
        selectionLabel.lineBreakMode = .byTruncatingMiddle
        selectionLabel.frame = NSRect(x: 140, y: sectionHeader.frame.minY, width: Layout.width - 164, height: 16)
        card.addSubview(selectionLabel)
        emojiName.font = Theme.Font.sectionHeader
        emojiName.textColor = .secondaryLabelColor
        emojiName.alignment = .right
        emojiName.lineBreakMode = .byTruncatingTail
        emojiName.frame = selectionLabel.frame
        emojiName.isHidden = true
        card.addSubview(emojiName)
        return card
    }
}

/// One-point divider in the label color at low alpha; reads on glass where
/// `NSBox` separators look heavy.
final class HairlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.hairline.setFill()
        bounds.fill()
    }
}

/// The launcher window's content: the glass plus the clear margin around it.
/// A click in the margin is a click outside the launcher.
private final class LauncherMargin: NSView {
    var onClick: (() -> Void)?
    var onDrag: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Clicks on the glass that no control took bubble up to here too:
        // they drag the launcher, like a window's title bar.
        let point = convert(event.locationInWindow, from: nil)
        if subviews.contains(where: { $0.frame.contains(point) }) {
            onDrag?()
        } else {
            onClick?()
        }
    }
}

extension LauncherController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        let text = searchField.stringValue
        // Typed: no longer a recent search ↑ put back.
        recalled = nil
        // "e smile": an alias, then a space, opens its item's mode.
        if openAlias(text) { return }
        // "kill gather" becomes the Kill chip and "gather"; "@jean" the
        // contacts, ":" the emoji, "?" the Catalog (`LauncherPrefix`).
        if mode == nil, let (command, rest) = LauncherPrefix.mode(of: text), let next = Self.mode(for: command) {
            // The history's words without the spaces typed around them.
            enterMode(next, filter: next == .clipboard ? rest.trimmingCharacters(in: .whitespaces) : rest)
            return
        }
        unfolded = nil
        updateResults(query: text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        // The emoji grid: the arrows move in it, as in Raycast's and Apple's.
        case #selector(NSResponder.moveLeft(_:)) where (mode == .emoji || mode == .gifs) && !results.isEmpty:
            moveInGrid(.left)
        case #selector(NSResponder.moveRight(_:)) where (mode == .emoji || mode == .gifs) && !results.isEmpty:
            moveInGrid(.right)
        case #selector(NSResponder.moveUp(_:)) where mode == .emoji || mode == .gifs:
            moveInGrid(.up)
        case #selector(NSResponder.moveDown(_:)) where mode == .emoji || mode == .gifs:
            moveInGrid(.down)
        case #selector(NSResponder.moveUp(_:)):
            if !recallOlder() { moveSelection(by: -1) }
        case #selector(NSResponder.moveDown(_:)):
            if !recallNewer() { moveSelection(by: 1) }
        case #selector(NSResponder.insertNewline(_:)):
            launchSelected()
        case #selector(NSResponder.insertTab(_:)):
            // Ask outside the modes; in one, its own (by meaning, its
            // processes, an event's details) or the row's actions.
            pressTab()
        case #selector(NSResponder.deleteBackward(_:)) where mode != nil && searchField.stringValue.isEmpty:
            // ⌫ on nothing: back to the launcher (or out of the unfolded app).
            if unfolded != nil {
                unfolded = nil
                updateResults(query: "")
            } else {
                leaveMode()
            }
        case #selector(NSResponder.deleteToBeginningOfLine(_:)) where clipboardMode:
            forgetSelectedClip()
        case #selector(NSResponder.deleteToBeginningOfLine(_:)) where mode == .agenda:
            deleteSelectedEvent()
        case #selector(NSResponder.cancelOperation(_:)):
            escape()
        default:
            return false
        }
        return true
    }
}

extension LauncherController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view: NSView = switch results[row] {
        case .catalog: tableView.makeView(withIdentifier: CatalogCellView.identifier, owner: nil) as? CatalogCellView ?? CatalogCellView()
        case .catalogHeader: tableView.makeView(withIdentifier: CatalogHeaderView.identifier, owner: nil) as? CatalogHeaderView ?? CatalogHeaderView()
        default: tableView.makeView(withIdentifier: ResultCellView.identifier, owner: nil) as? ResultCellView ?? ResultCellView()
        }
        fill(view, row: row)
        return view
    }

    /// The row's item in `view`, in place; false when the view is made for
    /// another kind of row (a Catalog row where a result was).
    @discardableResult
    private func fill(_ view: NSView, row: Int) -> Bool {
        switch results[row] {
        case .catalog(let entry):
            guard let cell = view as? CatalogCellView else { return false }
            configureCatalog(cell, entry)
        case .catalogHeader(let group):
            guard let header = view as? CatalogHeaderView else { return false }
            header.title = group.title
        default:
            guard let cell = view as? ResultCellView else { return false }
            configure(cell, for: results[row])
            let id = results[row].learningID
            // Beside a preview a row is its name (and a snippet's keyword):
            // the preview says the alias, the name needs the room.
            cell.setAlias(beside == nil ? aliasByID[id] : nil)
            cell.setPinned(mode == nil && pinsNow.ids.contains(id))
            cell.setTrailingKeycap(mode == .snippets ? Self.keywordCap(results[row]) : nil)
            cell.setMaybe(row == snippetMaybeRow)
        }
        return true
    }

    /// Group names are shorter rows: the launcher's header band.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard results.indices.contains(row), case .catalogHeader = results[row] else { return Layout.rowHeight }
        return CatalogHeaderView.height
    }

    /// A group's name is never picked, by key or by click.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard results.indices.contains(row), case .catalogHeader = results[row] else { return true }
        return false
    }

    /// The new results in the rows already there, filled in place; only
    /// the rows added or gone change. `reloadData` threw every row away
    /// and built them again: most of a key's time.
    fileprivate func showRows() {
        // The Catalog's group names change rows' heights and kinds: never
        // animated there (the table slides and fades them by default).
        let headers = mode == .catalog && results.contains { if case .catalogHeader = $0 { true } else { false } }
        let still = headers || listHasHeaders
        if still {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.allowsImplicitAnimation = false
        }
        defer {
            if still { NSAnimationContext.endGrouping() }
            listHasHeaders = headers
        }
        let shown = tableView.numberOfRows
        let count = results.count
        if count < shown {
            tableView.removeRows(at: IndexSet(count..<shown), withAnimation: [])
        } else if count > shown {
            tableView.insertRows(at: IndexSet(shown..<count), withAnimation: [])
        }
        if still { tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<count)) }
        var stale = IndexSet()
        for row in 0..<min(count, shown) {
            if let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false), !fill(view, row: row) { stale.insert(row) }
        }
        // Another kind of row there (the Catalog opened or closed): its own
        // view, put in place without a fade. Not by removing and inserting
        // the rows: in between, the table asked for rows the list no longer
        // had there, and a row off screen kept another one's name.
        if !stale.isEmpty {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.allowsImplicitAnimation = false
            tableView.reloadData(forRowIndexes: stale, columnIndexes: IndexSet(integer: 0))
            NSAnimationContext.endGrouping()
        }
    }

    /// A snippet's keyword as its row's keycap in Search Snippets; a long
    /// one cut (the preview says it whole).
    private static func keywordCap(_ item: LauncherItem) -> String? {
        guard case .snippet(let snippet) = item, !snippet.keyword.isEmpty else { return nil }
        return snippet.keyword.count > 12 ? snippet.keyword.prefix(11) + "…" : snippet.keyword
    }

    private func configure(_ cell: ResultCellView, for item: LauncherItem) {
        switch item {
        case .app(let entry):
            cell.configure(title: entry.name, accessory: Self.kind(of: entry.url) + (index.isRunning(entry) ? " · running" : ""), icon: index.icon(for: entry))
        case .command(let command):
            // skil.li's own commands wear its icon, like any app's.
            let icon = command.id == .openSettings ? CommandIcon.brand : CommandIcon.image(for: command.symbol)
            cell.configure(title: command.title, accessory: "Command", icon: icon)
        case .siCommand(let command):
            cell.configure(title: command.title, accessory: "\(Brand.intelligence) Command", icon: CommandIcon.image(for: "sparkles"))
        case .ask(let text):
            cell.configure(title: "Ask “\(text)”", accessory: Brand.intelligence, icon: CommandIcon.image(for: "sparkle.magnifyingglass"))
        case .system(.settings(let pane), let title):
            cell.configure(title: title, accessory: MacAction.settings(pane).kind, icon: SystemSettingsPanes.icon(for: pane))
        // The app's own icon: its command runs there.
        case .system(.appLink(let command, let variant), let title):
            let action = MacAction.appLink(command, variant: variant)
            cell.configure(title: title, accessory: action.kind, icon: LinkedApps.icon(for: command.appID) ?? CommandIcon.image(for: action.symbol))
        // Shortcuts' icon: each one runs there.
        case .system(.shortcut(let shortcut, let withSelection), let title):
            let action = MacAction.shortcut(shortcut, withSelection: withSelection)
            cell.configure(title: title, accessory: action.kind, icon: AppleShortcuts.icon ?? CommandIcon.image(for: action.symbol))
        case .system(let command, let title):
            cell.configure(title: title, accessory: command.kind, icon: CommandIcon.image(for: command.symbol))
        case .process(let group, let port):
            let icon = group.appPath.map { path -> NSImage in
                let image = NSWorkspace.shared.icon(forFile: path)
                image.size = NSSize(width: 32, height: 32)
                return image
            } ?? CommandIcon.image(for: "gearshape.2")
            cell.configure(title: "Quit \(group.name)", accessory: (port.map { "port \($0) · " } ?? "") + Processes.usage(group), icon: icon)
        case .quicklink(let link, let typed, _):
            let kind = link.keyword.isEmpty ? "Quicklink" : "Quicklink · \(link.keyword)"
            // Nothing typed for it: the selected text is its query.
            let selected = typed.isEmpty && link.takesQuery ? selectionQuery : nil
            let title = selected.map { "\(link.name) · \($0.count > 60 ? String($0.prefix(59)) + "…" : $0)" } ?? item.title
            cell.configure(title: title, accessory: selected == nil ? kind : "Quicklink · selection", icon: CommandIcon.image(for: "link"))
        case .startTimer(let request):
            cell.configure(title: (request.label.isEmpty ? "Timer" : request.label) + " · " + TimerRequest.spoken(request.seconds),
                           accessory: "Start Timer", icon: CommandIcon.image(for: "timer"))
        case .keepAwake(let request):
            cell.configure(title: LauncherItem.awakeTitle(request), accessory: "Keep Awake",
                           icon: CommandIcon.image(for: request == .allowSleep ? "moon.zzz.fill" : "cup.and.saucer.fill"))
        case .runningTimer(let timer):
            cell.configure(title: (timer.label.isEmpty ? "Timer" : timer.label) + " · " + TimerRequest.clock(timerRemaining?(timer) ?? 0) + " left",
                           accessory: "Cancel Timer", icon: CommandIcon.image(for: "timer"))
        case .keptAwake:
            cell.configure(title: item.title, accessory: AwakeStatus.turnOff, icon: CommandIcon.image(for: "cup.and.saucer.fill"))
        case .recordNamed:
            cell.configure(title: item.title, accessory: "Record Meeting", icon: CommandIcon.image(for: "record.circle"))
        case .recording(let live):
            cell.configure(title: item.title, accessory: live.paused ? "Paused" : "Stop and Transcribe",
                           icon: CommandIcon.image(for: "record.circle.fill", tint: .systemRed))
        case .recorded(let found):
            cell.configure(title: item.title,
                           accessory: found.said ?? RecordingSearch.detail(found.summary, length: MeetingTranscriber.length(found.summary.seconds)),
                           icon: CommandIcon.image(for: "waveform"))
        case .layout(let layout):
            cell.configure(title: layout.name, accessory: "Layout · \(layout.summary)", icon: CommandIcon.image(for: "rectangle.3.group"))
        case .saveLayout(let name):
            cell.configure(title: "Save Window Layout “\(name)”", accessory: "Window Layout", icon: CommandIcon.image(for: "square.and.arrow.down"))
        case .file(let file):
            cell.configure(title: file.name, accessory: file.folder.isEmpty ? "Home" : file.folder, icon: fileIcon(file.url))
        case .brew(let package):
            let accessory = package.installed != nil ? package.status : (package.description ?? package.status)
            cell.configure(title: package.name, accessory: accessory,
                           icon: CommandIcon.image(for: package.update != nil ? "arrow.up.circle" : package.isCask ? "macwindow" : "shippingbox"))
        case .brewUpgradeAll(let count):
            cell.configure(title: "Upgrade All (\(count))", accessory: "Homebrew", icon: CommandIcon.image(for: "arrow.up.circle.fill"))
        case .reminder(let reminder):
            let details = [reminder.marks, Reminders.when(reminder, now: .now), reminder.list].filter { !$0.isEmpty }.joined(separator: " · ")
            cell.configure(title: item.title, accessory: details,
                           icon: CommandIcon.image(for: reminder.isCompleted ? "checkmark.circle.fill" : "circle"))
        case .addReminder(let request):
            let due = request.due.map { Reminders.when(ReminderItem(id: "", title: "", due: $0, hasTime: request.hasTime), now: .now) } ?? "No date"
            let details = [request.priority == 1 ? "!!!" : request.priority == 5 ? "!!" : request.priority == 9 ? "!" : "", due, request.list ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            cell.configure(title: item.title, accessory: details, icon: CommandIcon.image(for: "checklist"))
        case .createEvent(let request):
            let day = Agenda.dayName(request.start, now: .now)
            let when = request.isAllDay ? "\(day), all day" : "\(day) \(Agenda.span(AgendaEvent(id: "", title: "", start: request.start, end: request.end)))"
            cell.configure(title: item.title, accessory: when + (request.calendar.map { " · \($0)" } ?? ""), icon: CommandIcon.image(for: "calendar.badge.plus"))
        case .pullRequest(let pullRequest):
            let age = Self.githubAge(pullRequest.updatedAt)
            cell.configure(title: item.title, accessory: "\(pullRequest.repository) #\(pullRequest.number) · \(pullRequest.reason) · \(age)",
                           icon: CommandIcon.image(for: pullRequest.group.symbol, tint: CommandIcon.color(pullRequest.group)))
        case .githubNotification(let notification):
            cell.configure(title: item.title, accessory: "\(notification.repository) · \(notification.reasonTitle) · \(Self.githubAge(notification.updatedAt))",
                           icon: CommandIcon.image(for: "bell"))
        case .event(let event):
            let call = event.meeting.map { " · \($0.service)" } ?? (event.location.isEmpty ? "" : " · \(event.location)")
            cell.configure(title: item.title, accessory: Agenda.when(event, now: .now) + call,
                           icon: CommandIcon.image(for: event.meeting == nil ? "calendar" : "video.fill"))
        case .contact(let match):
            let found = match.field.isEmpty || match.field == "Name" ? "" : "\(match.field) · "
            cell.configure(title: match.record.name, accessory: found + match.record.subtitle, icon: CommandIcon.image(for: "person.crop.circle.fill"))
        case .visit(let visit):
            let when = visit.visited.map { HistoryMeaning.shortWhen($0) } ?? ""
            cell.configure(title: visit.shownTitle, accessory: [visit.domain, when].filter { !$0.isEmpty }.joined(separator: " · "),
                           icon: appIcon(bundleID: visit.bundleID))
        case .script(let command, let inline):
            let kind = command.packageName.isEmpty ? "Skillie" : "\(command.packageName) · Skillie"
            cell.configure(title: command.title, accessory: inline ?? kind, icon: scriptIcon(command))
        case .scriptArgument(let command, let index, _):
            let argument = command.arguments[index]
            let last = index == command.arguments.count - 1
            cell.configure(title: LauncherItem.scriptArgument(command, index: index, text: searchField.stringValue).title,
                           accessory: last ? "Run" : "Then: \(command.arguments[index + 1].placeholder)",
                           icon: argument.kind == .password ? CommandIcon.image(for: "key") : scriptIcon(command))
        case .scriptChoice(let title, _):
            cell.configure(title: title, accessory: scriptInput?.command.title ?? "", icon: CommandIcon.image(for: "list.bullet"))
        case .project(let project):
            cell.configure(title: project.name, accessory: "\(project.editor) · \(project.folder())", icon: appIcon(bundleID: project.bundleID))
        case .browserTab(let tab):
            cell.configure(title: tab.title, accessory: tab.selected ? "\(tab.browser) · showing" : tab.browser, icon: appIcon(tab.app))
        case .openWindow(let window):
            cell.configure(title: window.title.isEmpty ? window.appName : window.title, accessory: window.appName, icon: appIcon(window.app))
        case .menuItem(let entry, _):
            // Where it is, and its keys: Edit › Transformations · ⇧⌘U.
            let accessory = entry.shortcut.map { entry.parents.isEmpty ? $0 : "\(entry.place)  ·  \($0)" } ?? entry.place
            cell.configure(title: entry.title, accessory: accessory,
                           icon: menuApp.map(appIcon) ?? CommandIcon.image(for: "filemenu.and.selection"))
        case .emoji(let emoji):
            cell.configure(title: emoji.name.prefix(1).uppercased() + emoji.name.dropFirst(), accessory: emoji.english == emoji.name ? "" : emoji.english,
                           icon: emojiImage(emoji.character(in: emojiTone())))
        case .gif(let gif):
            // Hidden behind the grid: the table only holds the selection.
            cell.configure(title: gif.title, accessory: "", icon: CommandIcon.image(for: "photo.on.rectangle.angled"))
        case .calculation(let result):
            cell.configure(title: result.display, accessory: result.detail, icon: CommandIcon.image(for: "equal"))
        case .snippet(let snippet):
            // In Search Snippets, beside the preview: the name, its keyword
            // a keycap at the right edge (`fill`).
            cell.configure(title: snippet.name, accessory: mode == .snippets ? "" : snippet.keyword.isEmpty ? "Snippet" : "Snippet · \(snippet.keyword)",
                           icon: CommandIcon.image(for: "text.quote"))
        case .clip(let item):
            // Beside the preview, which says the rest.
            cell.configure(title: item.title, accessory: "", icon: icon(for: item))
        case .setup(let permission):
            // Only Accessibility's opens the setup window; the others ask
            // right here (D7).
            cell.configure(title: "Allow \(permission.title) — \(permission.isRequired ? "needed for" : "for") \(permission.feature)",
                           accessory: permission.askedFrom == .setup ? "Set Up" : "Privacy", icon: CommandIcon.image(for: permission.symbol))
        case .catalog, .catalogHeader:
            // Their own views (`CatalogCellView`, `CatalogHeaderView`).
            break
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if mode == .emoji { showEmojiSelection() }
        if mode == .gifs { showGIFSelection() }
        updatePreview()
        updateFooter()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.makeView(withIdentifier: ResultRowView.identifier, owner: nil) as? ResultRowView
            ?? ResultRowView()
    }

    /// An image's thumbnail, the app a text came from, a file's icon.
    private func icon(for item: ClipboardStore.Item) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        switch item.kind {
        case .image:
            if let cached = thumbnails[item.id] { return cached }
            guard let url = (clipboardImageURL?(item)),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 64
                  ] as CFDictionary)
            else { return CommandIcon.image(for: "photo") }
            if thumbnails.count > 300 { thumbnails.removeAll() }
            let image = NSImage(cgImage: thumbnail, size: .zero)
            let fitted = NSImage(size: size, flipped: false) { rect in
                let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                let frame = NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
                NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).addClip()
                image.draw(in: frame)
                return true
            }
            thumbnails[item.id] = fitted
            return fitted
        case .files:
            let path = item.text.split(separator: "\n").first.map(String.init) ?? ""
            guard FileManager.default.fileExists(atPath: path) else { return CommandIcon.image(for: "doc") }
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = size
            return image
        case .text:
            // A copied color shows itself (a short parse: a few µs a row).
            if let color = CopiedColor.parse(item.text) { return Self.swatch(color) }
            guard let app = item.app else { return CommandIcon.image(for: "doc.text") }
            if let cached = appIcons[app] { return cached }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return CommandIcon.image(for: "doc.text") }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = size
            appIcons[app] = image
            return image
        }
    }

    private static var swatches: [String: NSImage] = [:]

    /// A copied color's row icon: the color on a rounded square, drawn
    /// when shown so its edge follows the appearance.
    private static func swatch(_ color: CopiedColor) -> NSImage {
        if let cached = swatches[color.hex] { return cached }
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            let square = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 6, yRadius: 6)
            if color.alpha < 1 {
                NSColor.white.setFill()
                square.fill()
            }
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
            square.fill()
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            square.lineWidth = 1
            square.stroke()
            return true
        }
        if swatches.count > 200 { swatches.removeAll() }
        swatches[color.hex] = image
        return image
    }

    /// Short kind label, Spotlight-style, instead of a raw path.
    private static func kind(of url: URL) -> String {
        let path = url.path
        if path.hasPrefix("/System/") { return "System" }
        if path.hasPrefix(NSHomeDirectory()) { return "User App" }
        if path.contains("/Utilities/") { return "Utility" }
        return "Application"
    }
}

extension LauncherController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

/// A mode's name before the search field ("Kill"): a filled capsule with
/// its title centered both ways.
final class ModeChip: NSView {
    private let label = NSTextField(labelWithString: "")
    private var color: NSColor

    init(title: String, color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        set(title: title, color: color)
    }

    /// Another mode: its name and color; the width follows the name.
    func set(title: String, color: NSColor) {
        self.color = color
        label.stringValue = title
        label.sizeToFit()
        let height: CGFloat = 26
        setFrameSize(NSSize(width: ceil(label.frame.width) + 22, height: height))
        // A label's frame includes leading above the cap height: center the
        // text's own height.
        label.frame = NSRect(x: 0, y: ((height - label.frame.height) / 2).rounded(), width: frame.width, height: label.frame.height)
        applyColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    private func applyColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.withAlphaComponent(0.9).cgColor
        }
    }
}
