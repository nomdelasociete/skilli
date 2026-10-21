import AppKit
import Observation
import ServiceManagement
import SkilliCore

enum GlassStyle: String, CaseIterable, Identifiable {
    case regular
    case clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "Regular"
        case .clear: "Clear"
        }
    }

    var effectStyle: NSGlassEffectView.Style {
        switch self {
        case .regular: .regular
        case .clear: .clear
        }
    }
}

/// When the next meeting shows in the menu bar, by minutes before it
/// starts.
enum MeetingMenuBar: String, CaseIterable, Identifiable {
    case never
    case atStart
    case fiveBefore
    case tenBefore
    case thirtyBefore
    case hourBefore
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .atStart: "When it starts"
        case .fiveBefore: "5 minutes before"
        case .tenBefore: "10 minutes before"
        case .thirtyBefore: "30 minutes before"
        case .hourBefore: "1 hour before"
        case .always: "Always, the next one"
        }
    }

    /// Minutes before the start; nil never, Int.max always.
    var lead: Int? {
        switch self {
        case .never: nil
        case .atStart: 0
        case .fiveBefore: 5
        case .tenBefore: 10
        case .thirtyBefore: 30
        case .hourBefore: 60
        case .always: Int.max
        }
    }
}

/// What the menu bar says of today's reminders.
enum RemindersMenuBar: String, CaseIterable, Identifiable {
    case never
    case count
    case countAndNext

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .count: "How many are due today"
        case .countAndNext: "How many, and the next one"
        }
    }
}

/// What happens when a meeting with a call starts.
/// What happens as a meeting with a call starts, beyond its alerts. The
/// card asking to join is an alert On time (Settings → Calendar).
enum MeetingAutoJoin: String, CaseIterable, Identifiable {
    case off
    case join

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Nothing more"
        case .join: "Join at once"
        }
    }
}

/// User preferences, persisted in `UserDefaults`. Observable so Settings
/// updates live; `onChange` lets AppKit components apply a change at once.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let showMenuBarIcon = "Preferences.showMenuBarIcon"
        static let glassStyle = "Preferences.glassStyle"
        static let hyperTapSendsEscape = "Preferences.hyperTapSendsEscape"
        static let aiEngineMode = "Preferences.aiEngineMode"
        /// Claude's model before any provider could write ("haiku",
        /// "sonnet"): read once into `writingModel`, kept for older builds.
        static let aiModel = "Preferences.aiModel"
        static let writingModel = "Preferences.writingModel"
        static let keepClaudeReady = "Preferences.keepClaudeReady"
        static let handoffTarget = "Preferences.handoffTarget"
        static let handoffTerminal = "Preferences.handoffTerminal"
        static let voiceLanguage = "Preferences.voiceLanguage"
        static let askUsesClaudeCodeSkills = "Preferences.askUsesClaudeCodeSkills"
        static let didCompleteSetup = "Preferences.didCompleteSetup"
        static let clipboardHistory = "Preferences.clipboardHistory"
        static let clipboardRetention = "Preferences.clipboardRetention"
        static let clipboardOCR = "Preferences.clipboardOCR"
        static let clipboardExcludedApps = "Preferences.clipboardExcludedApps"
        static let imageTagsClipboard = "Preferences.imageTagsClipboard"
        static let imageTagsFolder = "Preferences.imageTagsFolder"
        static let imageTagsFolderPath = "Preferences.imageTagsFolderPath"
        static let windowLayoutIgnoredApps = "Preferences.windowLayoutIgnoredApps"
        static let windowGap = "Preferences.windowGap"
        static let ignoredMonitors = "Preferences.ignoredMonitors"
        static let autoQuit = "Preferences.autoQuit"
        static let autoQuitMinutes = "Preferences.autoQuitMinutes"
        static let autoQuitNever = "Preferences.autoQuitNever"
        static let clipboardMeaningSearch = "Preferences.clipboardMeaningSearch"
        static let snippetExpansion = "Preferences.snippetExpansion"
        static let snippetExpansionMode = "Preferences.snippetExpansionMode"
        static let snippetExcludedApps = "Preferences.snippetExcludedApps"
        static let snippetMeaningSearch = "Preferences.snippetMeaningSearch"
        static let clipboardScreenshots = "Preferences.clipboardScreenshots"
        static let clipboardLinkPreviews = "Preferences.clipboardLinkPreviews"
        static let fileMeaningSearch = "Preferences.fileMeaningSearch"
        static let historyMeaningSearch = "Preferences.historyMeaningSearch"
        static let emojiSkinTone = "Preferences.emojiSkinTone"
        static let emojiMeaningSearch = "Preferences.emojiMeaningSearch"
        static let agendaHiddenCalendars = "Preferences.agendaHiddenCalendars"
        static let agendaLauncherMinutes = "Preferences.agendaLauncherMinutes"
        static let agendaMenuBar = "Preferences.agendaMenuBar"
        static let agendaMenuBarCallsOnly = "Preferences.agendaMenuBarCallsOnly"
        static let agendaHideAfter = "Preferences.agendaHideAfter"
        static let agendaCountdown = "Preferences.agendaCountdown"
        static let agendaNextDuringMeeting = "Preferences.agendaNextDuringMeeting"
        static let agendaAlertWithoutCall = "Preferences.agendaAlertWithoutCall"
        static let agendaAutoJoin = "Preferences.agendaAutoJoin"
        static let agendaAlerts = "Preferences.agendaAlerts"
        static let agendaApp = "Preferences.agendaApp"
        static let agendaMeetBrowser = "Preferences.agendaMeetBrowser"
        static let remindersMenuBar = "Preferences.remindersMenuBar"
        static let remindersDefaultList = "Preferences.remindersDefaultList"
        static let reminderPlaces = "Preferences.reminderPlaces"
        static let formProfiles = "Preferences.formProfiles"
        static let launcherAliases = "Preferences.launcherAliases"
        static let catalogOff = "Preferences.catalogOff"
        static let skilliesInMenuBar = "Preferences.skilliesInMenuBar"
        static let githubUnderSearch = "Preferences.githubUnderSearch"
        static let cleanShotTextLineBreaks = "Preferences.cleanShotTextLineBreaks"
        static let launcherPlace = "Preferences.launcherPlace"
        static let launcherScreen = "Preferences.launcherScreen"
        static let launcherReset = "Preferences.launcherReset"
        static let launcherPins = "Preferences.launcherPins"
        static let launcherEnglishInput = "Preferences.launcherEnglishInput"
        static let quicklinkReuseTab = "Preferences.quicklinkReuseTab"
        static let relayPublicURL = "Preferences.relayPublicURL"
        static let backupFolder = "Preferences.backupFolder"
        static let backupSchedule = "Preferences.backupSchedule"
        static let backupKeep = "Preferences.backupKeep"
        /// The clipboard history in backups: a switch until 2026-10-15,
        /// removed (backups never hold it). Forgotten on launch.
        static let backupClipboard = "Preferences.backupClipboard"
    }

    @ObservationIgnored var onChange: (@MainActor (Preferences) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    var showMenuBarIcon: Bool {
        didSet { save(showMenuBarIcon, Key.showMenuBarIcon) }
    }

    var glassStyle: GlassStyle {
        didSet { save(glassStyle.rawValue, Key.glassStyle) }
    }

    /// Only applies when skil.li receives the Hyper trigger itself; with
    /// Raycast's Hyper Key, Raycast's own setting decides.
    var hyperTapSendsEscape: Bool {
        didSet { save(hyperTapSendsEscape, Key.hyperTapSendsEscape) }
    }

    var aiEngineMode: AIEngineMode {
        didSet { save(aiEngineMode.rawValue, Key.aiEngineMode) }
    }

    /// What Ask and commands write with unless a command picks its own
    /// (`ModelChoice.id`).
    var writingModel: ModelChoice {
        didSet {
            // Older builds still find the Claude model they know.
            if let claude = AIModel(choice: writingModel) { defaults.set(claude.rawValue, forKey: Key.aiModel) }
            save(writingModel.id, Key.writingModel)
        }
    }

    /// A spare `claude` process, so answers start ~0.4 s sooner.
    var keepClaudeReady: Bool {
        didSet { save(keepClaudeReady, Key.keepClaudeReady) }
    }

    /// ⌘↩ in the card: the conversation goes on there, in that terminal.
    var handoffTarget: Handoff.Target {
        didSet { save(handoffTarget.rawValue, Key.handoffTarget) }
    }

    var handoffTerminal: Handoff.Terminal {
        didSet { save(handoffTerminal.rawValue, Key.handoffTerminal) }
    }

    /// A locale identifier for speech; empty follows the keyboard's language.
    var voiceLanguage: String {
        didSet { save(voiceLanguage, Key.voiceLanguage) }
    }

    /// Ask's agent also uses the skills in ~/.claude/skills (Settings → Ask
    /// → Skills); off: only skil.li's own folder.
    var askUsesClaudeCodeSkills: Bool {
        didSet { save(askUsesClaudeCodeSkills, Key.askUsesClaudeCodeSkills) }
    }

    /// The setup window was closed once (Done, Later or ✕): it no longer
    /// opens by itself (D7), only from Set Up skil.li….
    var didCompleteSetup: Bool {
        didSet { save(didCompleteSetup, Key.didCompleteSetup) }
    }

    /// Keep what is copied (Settings → Clipboard).
    var clipboardHistory: Bool {
        didSet { save(clipboardHistory, Key.clipboardHistory) }
    }

    /// How long copies stay: a day, a week, a month, always, or N days.
    var clipboardRetention: ClipboardRetention {
        didSet { save(clipboardRetention.rawValue, Key.clipboardRetention) }
    }

    /// Read the text in copied images, so search finds it.
    var clipboardOCR: Bool {
        didSet { save(clipboardOCR, Key.clipboardOCR) }
    }

    /// Bundle identifiers whose copies are never kept.
    var clipboardExcludedApps: [String] {
        didSet { save(clipboardExcludedApps, Key.clipboardExcludedApps) }
    }

    /// Bundle identifiers left out of every window layout taken from the
    /// windows open (shown unticked in the editor, to take once).
    var windowLayoutIgnoredApps: [String] {
        didSet { save(windowLayoutIgnoredApps, Key.windowLayoutIgnoredApps) }
    }

    /// Points between windows and at the screen's edges, for every place
    /// the front window is put in (halves, thirds, quarters, Maximize) and
    /// windows placed in the layout editor; 0 keeps them touching.
    var windowGap: Int {
        didSet { save(windowGap, Key.windowGap) }
    }

    /// The choices Settings → Windows offers, in points.
    static let windowGaps = [0, 4, 8, 12, 16]
    /// Auto Quit: the apps not used for `autoQuitMinutes` are quit, the
    /// ones in `autoQuitNever` (bundle ids) never. Off by default.
    var autoQuit: Bool {
        didSet { save(autoQuit, Key.autoQuit) }
    }

    var autoQuitMinutes: Int {
        didSet { save(autoQuitMinutes, Key.autoQuitMinutes) }
    }

    var autoQuitNever: [String] {
        didSet { save(autoQuitNever, Key.autoQuitNever) }
    }

    /// Monitors that never offer a layout when plugged in (Ignore This
    /// Monitor), known by who they are.
    var ignoredMonitors: [DisplayFingerprint] {
        didSet {
            if let data = try? JSONEncoder().encode(ignoredMonitors) { save(data, Key.ignoredMonitors) }
        }
    }

    /// ⇥ in the clipboard history asks Jev or OpenAI Decisions, with short
    /// excerpts of recent copies.
    var clipboardMeaningSearch: Bool {
        didSet { save(clipboardMeaningSearch, Key.clipboardMeaningSearch) }
    }

    /// Typing a snippet's keyword anywhere types the snippet.
    var snippetExpansion: Bool {
        didSet { save(snippetExpansion, Key.snippetExpansion) }
    }

    /// When a keyword becomes its snippet: as soon as it is typed (a
    /// letter keyword at its word's end), or only after a space or ↩, kept
    /// or left out.
    var snippetExpansionMode: SnippetExpansionMode {
        didSet { save(snippetExpansionMode.rawValue, Key.snippetExpansionMode) }
    }

    /// Bundle identifiers where keywords stay as typed (password managers
    /// out of the box; password fields never expand anyway).
    var snippetExcludedApps: [String] {
        didSet { save(snippetExcludedApps, Key.snippetExcludedApps) }
    }

    /// ⇥ in Search Snippets asks Jev or OpenAI Decisions, with each
    /// snippet's name, keyword and first words.
    var snippetMeaningSearch: Bool {
        didSet { save(snippetMeaningSearch, Key.snippetMeaningSearch) }
    }

    /// A copied link shown in the history's preview is opened to read its
    /// title, description, picture and icon (`ClipboardLinks`).
    var clipboardLinkPreviews: Bool {
        didSet { save(clipboardLinkPreviews, Key.clipboardLinkPreviews) }
    }

    /// New images in the screenshots folder (or the one chosen) join the
    /// history, read on this Mac; Jev looks at them only with
    /// `imageTagsFolder`.
    var clipboardScreenshots: Bool {
        didSet { save(clipboardScreenshots, Key.clipboardScreenshots) }
    }

    /// ⇥ in Search Files asks Jev or OpenAI Decisions, with the names,
    /// kinds, folders and dates of recent files.
    var fileMeaningSearch: Bool {
        didSet { save(fileMeaningSearch, Key.fileMeaningSearch) }
    }

    /// ⇥ in Search Browser History asks Jev or OpenAI Decisions, with the
    /// titles, sites and dates of the last pages visited.
    var historyMeaningSearch: Bool {
        didSet { save(historyMeaningSearch, Key.historyMeaningSearch) }
    }

    /// The skin tone emoji that come in tones are shown and typed in.
    var emojiSkinTone: EmojiSkinTone {
        didSet { save(emojiSkinTone.rawValue, Key.emojiSkinTone) }
    }

    /// ⇥ in Search Emoji, and no name fitting, ask the decision key.
    var emojiMeaningSearch: Bool {
        didSet { save(emojiMeaningSearch, Key.emojiMeaningSearch) }
    }

    /// Calendars left out of the agenda, the next meeting and Ask, by
    /// identifier (two accounts may each have a "Calendar"); names kept from
    /// before are turned into identifiers once the calendars can be read.
    var agendaHiddenCalendars: [String] {
        didSet { save(agendaHiddenCalendars, Key.agendaHiddenCalendars) }
    }

    /// The meeting is the empty launcher's first row from this many minutes
    /// before it starts to as many after.
    var agendaLauncherMinutes: Int {
        didSet { save(agendaLauncherMinutes, Key.agendaLauncherMinutes) }
    }

    var agendaMenuBar: MeetingMenuBar {
        didSet { save(agendaMenuBar.rawValue, Key.agendaMenuBar) }
    }

    /// Only meetings with a call in the menu bar (not all-day or a block).
    var agendaMenuBarCallsOnly: Bool {
        didSet { save(agendaMenuBarCallsOnly, Key.agendaMenuBarCallsOnly) }
    }

    /// Minutes after the start it leaves the menu bar; -1 at its end.
    var agendaHideAfter: Int {
        didSet { save(agendaHideAfter, Key.agendaHideAfter) }
    }

    /// During a meeting, the menu bar counts down to its end and keeps it
    /// until then (`agendaHideAfter` aside).
    var agendaCountdown: Bool {
        didSet { save(agendaCountdown, Key.agendaCountdown) }
    }

    /// During a meeting, the next one shows too once it is that close (the
    /// menu bar's own lead), in a short form.
    var agendaNextDuringMeeting: Bool {
        didSet { save(agendaNextDuringMeeting, Key.agendaNextDuringMeeting) }
    }

    /// As it starts, an event without a call is announced in the card too
    /// (with "Ask to join" or "Join at once"; off by default).
    var agendaAlertWithoutCall: Bool {
        didSet { save(agendaAlertWithoutCall, Key.agendaAlertWithoutCall) }
    }

    var agendaAutoJoin: MeetingAutoJoin {
        didSet { save(agendaAutoJoin.rawValue, Key.agendaAutoJoin) }
    }

    /// Alerts before a meeting: how long before, card or screens dark.
    var agendaAlerts: [MeetingAlert] {
        didSet { save((try? JSONEncoder().encode(agendaAlerts)) ?? Data(), Key.agendaAlerts) }
    }

    /// The app ⌘↩ opens an event in (bundle identifier).
    var agendaApp: String {
        didSet { save(agendaApp, Key.agendaApp) }
    }

    /// The browser Google Meet links open in (bundle identifier); empty for
    /// the default browser.
    var agendaMeetBrowser: String {
        didSet { save(agendaMeetBrowser, Key.agendaMeetBrowser) }
    }

    /// Where the user dragged the launcher, the same on every screen; nil
    /// opens it in the middle, its top 18 % down.
    var launcherPlace: LauncherPlace? {
        didSet {
            if let data = launcherPlace.flatMap({ try? JSONEncoder().encode($0) }) {
                save(data, Key.launcherPlace)
            } else {
                defaults.removeObject(forKey: Key.launcherPlace)
                onChange?(self)
            }
        }
    }

    /// Which screen the launcher opens on: the pointer's (as always), the
    /// window in front's, or the main display.
    var launcherScreen: LauncherScreen {
        didSet { save(launcherScreen.rawValue, Key.launcherScreen) }
    }

    /// When the launcher opens empty again: right away (as always), after a
    /// minute or five, or never (it keeps what was typed and the row).
    var launcherReset: LauncherReset {
        didSet { save(launcherReset.rawValue, Key.launcherReset) }
    }

    /// Launcher items pinned with ⌘K → Pin, by `LauncherItem.learningID`,
    /// in the order pinned: first in the empty launcher.
    var launcherPins: [String] {
        didSet { save(launcherPins, Key.launcherPins) }
    }

    /// While the launcher is open the keyboard types with the user's own
    /// English layout (ABC, U.S.), then theirs again as it closes
    /// (`EnglishTyping`). Off: the input source is never touched.
    var launcherEnglishInput: Bool {
        didSet { save(launcherEnglishInput, Key.launcherEnglishInput) }
    }

    /// A quicklink loads in a tab the default browser has open on the same
    /// site instead of a new one (`BrowserTabReuse`). Off: a new tab, as
    /// always; the page in that tab would be replaced.
    var quicklinkReuseTab: Bool {
        didSet { save(quicklinkReuseTab, Key.quicklinkReuseTab) }
    }

    /// The GitHub strip under the launcher's search field (pull requests by
    /// group, unread notifications), kept fresh in the background.
    var githubUnderSearch: Bool {
        didSet { save(githubUnderSearch, Key.githubUnderSearch) }
    }

    /// Relay origin. Empty leaves GitHub on its timer. `RELAY_PUBLIC_URL`
    /// overrides this while it is set.
    var relayPublicURL: String {
        didSet {
            let trimmed = relayPublicURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != relayPublicURL {
                relayPublicURL = trimmed
                return
            }
            save(relayPublicURL, Key.relayPublicURL)
        }
    }

    /// Today's reminders in the menu bar (hidden when there are none).
    var remindersMenuBar: RemindersMenuBar {
        didSet { save(remindersMenuBar.rawValue, Key.remindersMenuBar) }
    }

    /// Where a reminder said without "#list" goes; empty for the Reminders
    /// app's default list.
    var remindersDefaultList: String {
        didSet { save(remindersDefaultList, Key.remindersDefaultList) }
    }

    /// Places for "en arrivant au bureau", "when I leave home".
    var reminderPlaces: [SavedPlace] {
        didSet { save((try? JSONEncoder().encode(reminderPlaces)) ?? Data(), Key.reminderPlaces) }
    }

    /// Settings → Your Details: the user's fields beyond My Card, and the people
    /// and companies kept in skil.li. Sensitive values are in the Keychain
    /// (`FormSecrets`), never here.
    var formProfiles: FormProfiles {
        didSet { save((try? JSONEncoder().encode(formProfiles)) ?? Data(), Key.formProfiles) }
    }

    /// Settings → Clipboard → Images: Jev tags the images copied, and those
    /// saved in a folder (macOS's screenshots unless another is chosen:
    /// empty path), so ✦C finds "the invoice", "le graphique".
    var imageTagsClipboard: Bool {
        didSet { save(imageTagsClipboard, Key.imageTagsClipboard) }
    }

    var imageTagsFolder: Bool {
        didSet { save(imageTagsFolder, Key.imageTagsFolder) }
    }

    var imageTagsFolderPath: String {
        didSet { save(imageTagsFolderPath, Key.imageTagsFolderPath) }
    }

    /// The folder whose images go into the history, as chosen.
    var imageFolder: URL {
        imageTagsFolderPath.isEmpty ? ImageFolderWatcher.screenshotsFolder : URL(fileURLWithPath: imageTagsFolderPath, isDirectory: true)
    }

    /// The launcher's aliases ("e" + space: Emoji), set with ⌘K.
    var launcherAliases: [LauncherAlias] {
        didSet { save((try? JSONEncoder().encode(launcherAliases)) ?? Data(), Key.launcherAliases) }
    }

    /// Settings → Catalog: the entries turned off (`CatalogEntry.id`). Their
    /// rows leave the launcher's results; the "?" still lists them.
    var catalogOff: Set<String> {
        didSet { save(catalogOff.sorted(), Key.catalogOff) }
    }

    /// Settings → Apps: what CleanShot X's Capture Text does with line
    /// breaks when ⌘K does not say: as CleanShot is set, or one way.
    var cleanShotTextLineBreaks: CleanShot.TextLineBreaks {
        didSet { save(cleanShotTextLineBreaks.rawValue, Key.cleanShotTextLineBreaks) }
    }

    /// Settings → Skillies: the inline skillies shown in the menu bar, by
    /// path, in the order they were added.
    var skilliesInMenuBar: [String] {
        didSet { save(skilliesInMenuBar, Key.skilliesInMenuBar) }
    }

    /// Settings → Backup: the folder backups go to (a path; empty until
    /// the user picks one), how often, how many are kept (0 keeps all).
    var backupFolder: String {
        didSet { save(backupFolder, Key.backupFolder) }
    }

    var backupSchedule: BackupSchedule {
        didSet { save(backupSchedule.rawValue, Key.backupSchedule) }
    }

    var backupKeep: Int {
        didSet { save(backupKeep, Key.backupKeep) }
    }


    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        glassStyle = defaults.string(forKey: Key.glassStyle).flatMap(GlassStyle.init(rawValue:)) ?? .regular
        hyperTapSendsEscape = defaults.object(forKey: Key.hyperTapSendsEscape) as? Bool ?? true
        aiEngineMode = defaults.string(forKey: Key.aiEngineMode).flatMap(AIEngineMode.init(rawValue:)) ?? .auto
        writingModel = defaults.string(forKey: Key.writingModel).flatMap(ModelChoice.init(id:))
            ?? defaults.string(forKey: Key.aiModel).flatMap(AIModel.init(rawValue:)).map(\.choice)
            ?? .standard
        keepClaudeReady = defaults.object(forKey: Key.keepClaudeReady) as? Bool ?? true
        handoffTarget = defaults.string(forKey: Key.handoffTarget).flatMap(Handoff.Target.init(rawValue:)) ?? .claude
        handoffTerminal = defaults.string(forKey: Key.handoffTerminal).flatMap(Handoff.Terminal.init(rawValue:)) ?? .terminal
        voiceLanguage = defaults.string(forKey: Key.voiceLanguage) ?? ""
        askUsesClaudeCodeSkills = defaults.bool(forKey: Key.askUsesClaudeCodeSkills)
        didCompleteSetup = defaults.bool(forKey: Key.didCompleteSetup)
        clipboardHistory = defaults.object(forKey: Key.clipboardHistory) as? Bool ?? true
        clipboardRetention = defaults.string(forKey: Key.clipboardRetention).map(ClipboardRetention.init(rawValue:)) ?? .month
        clipboardOCR = defaults.object(forKey: Key.clipboardOCR) as? Bool ?? true
        clipboardExcludedApps = defaults.stringArray(forKey: Key.clipboardExcludedApps) ?? ClipboardPolicy.defaultExcludedApps
        imageTagsClipboard = defaults.object(forKey: Key.imageTagsClipboard) as? Bool ?? true
        imageTagsFolder = defaults.object(forKey: Key.imageTagsFolder) as? Bool ?? true
        imageTagsFolderPath = defaults.string(forKey: Key.imageTagsFolderPath) ?? ""
        windowLayoutIgnoredApps = defaults.stringArray(forKey: Key.windowLayoutIgnoredApps) ?? []
        windowGap = defaults.object(forKey: Key.windowGap) as? Int ?? 0
        autoQuit = defaults.bool(forKey: Key.autoQuit)
        autoQuitMinutes = defaults.object(forKey: Key.autoQuitMinutes) as? Int ?? AutoQuit.defaultDelay
        autoQuitNever = defaults.stringArray(forKey: Key.autoQuitNever) ?? []
        ignoredMonitors = defaults.data(forKey: Key.ignoredMonitors).flatMap { try? JSONDecoder().decode([DisplayFingerprint].self, from: $0) } ?? []
        clipboardMeaningSearch = defaults.object(forKey: Key.clipboardMeaningSearch) as? Bool ?? true
        snippetExpansion = defaults.object(forKey: Key.snippetExpansion) as? Bool ?? true
        snippetExpansionMode = defaults.string(forKey: Key.snippetExpansionMode).flatMap(SnippetExpansionMode.init(rawValue:)) ?? .immediately
        // Until 2026-10-15 keywords stayed as typed in the clipboard's excluded apps.
        snippetExcludedApps = defaults.stringArray(forKey: Key.snippetExcludedApps)
            ?? defaults.stringArray(forKey: Key.clipboardExcludedApps) ?? ClipboardPolicy.defaultExcludedApps
        snippetMeaningSearch = defaults.object(forKey: Key.snippetMeaningSearch) as? Bool ?? true
        // The folder was watched only with its images tagged: that choice
        // carries over.
        clipboardScreenshots = defaults.object(forKey: Key.clipboardScreenshots) as? Bool
            ?? defaults.object(forKey: Key.imageTagsFolder) as? Bool ?? true
        clipboardLinkPreviews = defaults.object(forKey: Key.clipboardLinkPreviews) as? Bool ?? true
        fileMeaningSearch = defaults.object(forKey: Key.fileMeaningSearch) as? Bool ?? true
        historyMeaningSearch = defaults.object(forKey: Key.historyMeaningSearch) as? Bool ?? true
        emojiSkinTone = defaults.string(forKey: Key.emojiSkinTone).flatMap(EmojiSkinTone.init(rawValue:)) ?? .standard
        emojiMeaningSearch = defaults.object(forKey: Key.emojiMeaningSearch) as? Bool ?? true
        agendaHiddenCalendars = defaults.stringArray(forKey: Key.agendaHiddenCalendars) ?? []
        agendaLauncherMinutes = defaults.object(forKey: Key.agendaLauncherMinutes) as? Int ?? 10
        agendaMenuBar = defaults.string(forKey: Key.agendaMenuBar).flatMap(MeetingMenuBar.init(rawValue:)) ?? .tenBefore
        agendaMenuBarCallsOnly = defaults.object(forKey: Key.agendaMenuBarCallsOnly) as? Bool ?? true
        agendaHideAfter = defaults.object(forKey: Key.agendaHideAfter) as? Int ?? 10
        agendaCountdown = defaults.object(forKey: Key.agendaCountdown) as? Bool ?? true
        agendaNextDuringMeeting = defaults.object(forKey: Key.agendaNextDuringMeeting) as? Bool ?? true
        agendaAlertWithoutCall = defaults.object(forKey: Key.agendaAlertWithoutCall) as? Bool ?? false
        // "Ask to join" (and its screens dark) was a choice as it starts:
        // now an alert On time.
        let joinAsSaved = defaults.string(forKey: Key.agendaAutoJoin)
        var alerts = defaults.data(forKey: Key.agendaAlerts).flatMap { try? JSONDecoder().decode([MeetingAlert].self, from: $0) } ?? []
        if joinAsSaved == "ask" || joinAsSaved == "askDark", !alerts.contains(where: { $0.minutes == 0 }) {
            alerts.insert(MeetingAlert(minutes: 0, style: joinAsSaved == "askDark" ? .dark : .card), at: 0)
            defaults.set((try? JSONEncoder().encode(alerts)) ?? Data(), forKey: Key.agendaAlerts)
        }
        agendaAutoJoin = joinAsSaved.flatMap(MeetingAutoJoin.init(rawValue:)) ?? .off
        agendaAlerts = alerts
        agendaApp = defaults.string(forKey: Key.agendaApp) ?? "com.apple.iCal"
        agendaMeetBrowser = defaults.string(forKey: Key.agendaMeetBrowser) ?? ""
        remindersMenuBar = defaults.string(forKey: Key.remindersMenuBar).flatMap(RemindersMenuBar.init(rawValue:)) ?? .never
        remindersDefaultList = defaults.string(forKey: Key.remindersDefaultList) ?? ""
        reminderPlaces = defaults.data(forKey: Key.reminderPlaces).flatMap { try? JSONDecoder().decode([SavedPlace].self, from: $0) } ?? []
        formProfiles = defaults.data(forKey: Key.formProfiles).flatMap { try? JSONDecoder().decode(FormProfiles.self, from: $0) } ?? FormProfiles()
        launcherAliases = defaults.data(forKey: Key.launcherAliases).flatMap { try? JSONDecoder().decode([LauncherAlias].self, from: $0) } ?? []
        catalogOff = Set(defaults.stringArray(forKey: Key.catalogOff) ?? [])
        skilliesInMenuBar = defaults.stringArray(forKey: Key.skilliesInMenuBar) ?? []
        githubUnderSearch = defaults.object(forKey: Key.githubUnderSearch) as? Bool ?? true
        cleanShotTextLineBreaks = defaults.string(forKey: Key.cleanShotTextLineBreaks).flatMap(CleanShot.TextLineBreaks.init(rawValue:)) ?? .asSet
        launcherPlace = defaults.data(forKey: Key.launcherPlace).flatMap { try? JSONDecoder().decode(LauncherPlace.self, from: $0) }
        launcherScreen = defaults.string(forKey: Key.launcherScreen).flatMap(LauncherScreen.init(rawValue:)) ?? .pointer
        launcherReset = defaults.string(forKey: Key.launcherReset).flatMap(LauncherReset.init(rawValue:)) ?? .immediately
        launcherPins = defaults.stringArray(forKey: Key.launcherPins) ?? []
        launcherEnglishInput = defaults.object(forKey: Key.launcherEnglishInput) as? Bool ?? false
        quicklinkReuseTab = defaults.object(forKey: Key.quicklinkReuseTab) as? Bool ?? false
        relayPublicURL = defaults.string(forKey: Key.relayPublicURL) ?? ""
        backupFolder = defaults.string(forKey: Key.backupFolder) ?? ""
        backupSchedule = defaults.string(forKey: Key.backupSchedule).flatMap(BackupSchedule.init(rawValue:)) ?? .weekly
        backupKeep = defaults.object(forKey: Key.backupKeep) as? Int ?? 10
        // Not in backups any more: the old switch would only ride along.
        defaults.removeObject(forKey: Key.backupClipboard)
    }

    /// Keys a backup leaves out: this Mac's own state (setup done with its
    /// permissions, its screens, where the launcher sits on them, where
    /// backups go).
    static let machineKeys: Set<String> = [Key.didCompleteSetup, Key.ignoredMonitors, Key.launcherPlace, Key.backupFolder, Key.imageTagsFolderPath]

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?(self)
    }
}

/// "Open at login" through `SMAppService`, which macOS lists under
/// System Settings → General → Login Items.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var error: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    /// System Settings → General → Login Items, where macOS waits for the
    /// user's OK.
    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
