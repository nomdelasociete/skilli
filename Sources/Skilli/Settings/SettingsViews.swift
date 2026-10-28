import Observation
import SkilliCore
import SwiftUI

/// What Settings needs from the running app, without depending on it.
@MainActor
struct SettingsContext {
    let hyperStatus: () -> String
    let hyperIsActive: () -> Bool
    let receivesTrigger: () -> Bool
    let accessibilityGranted: () -> Bool
    let shortcutsActive: () -> Bool
    let openAccessibilitySettings: () -> Void
    let shortcuts: ShortcutStore
    let chooseApp: () -> URL?
    let ai: AIStore
    let aiCommands: AICommandsModel
    let toolSettings: ToolSettings
    let clipboard: ClipboardHistory
    let permissions: PermissionCenter
    let snippets: SnippetLibrary
    let windowLayouts: () -> [SavedWindowLayout]
    let quicklinks: QuicklinkStore
    /// The editors' recent projects, for Add Shortcut.
    var recentProjects: () -> [EditorProject] = { [] }
    /// Every skillie (Settings → Skillies); the ones a shortcut can run (no
    /// argument needed); Raycast's Script Commands turned into skillies.
    var skillies: () -> [ScriptCommand] = { [] }
    /// Every calendar by account, for Settings → Calendar.
    var calendarAccounts: () -> [CalendarAccount] = { [] }
    /// The reminder lists, for Settings → Reminders.
    var reminderLists: () -> [String] = { [] }
    /// The user's own card in Contacts (Settings → Your Details).
    var myCard: @MainActor () async -> ContactRecord? = { nil }
    /// The Contacts card a name ("Margot Martin") points to.
    var contactNamed: @MainActor ([String]) async -> ContactRecord? = { _ in nil }
    var scriptCommands: () -> [ScriptCommand] = { [] }
    /// The user's AIs that can help set tool rights (Claude Code, Codex:
    /// those installed); opening the one chosen on one server or all.
    var rightsHelpers: @MainActor () -> [Handoff.Target] = { [] }
    /// The user's GitHub, for Settings → GitHub.
    var github: GitHubBook?
    /// A decision key can check the user's rules (Settings → Ask).
    var canCheckRules: @MainActor () -> Bool = { false }
    /// Asks on a schedule, the user's skills, a last answer shown in the
    /// card (Settings → Ask).
    var scheduler: AskScheduler?
    var agentSkills: () -> [AgentSkill] = { [] }
    var showScheduledAnswer: (ScheduledAsk) -> Void = { _ in }
    var openRightsHelper: @MainActor (_ server: String?) throws -> Void = { _ in }
    /// The saved window layouts (Settings → Windows), and what can be done
    /// with one: `editLayout(nil)` takes a new one from the windows open.
    var arranger: WindowArranger?
    /// Settings → Calendar's Try: the alert, now, on a sample meeting.
    var tryMeetingAlert: @MainActor (MeetingAlert) -> Void = { _ in }
    /// Settings → Backup.
    var backup: BackupCenter?
    /// The emoji picker's library: the words learned from picks.
    var emoji: EmojiLibrary?
    var gifs: GIFLibrary?
    /// A TypeSafe key is there: images can be tagged.
    var hasImageKey: @MainActor () -> Bool = { false }
    /// skil.li quits and opens again (after a restore).
    var reopen: @MainActor () -> Void = {}
    var editLayout: @MainActor (SavedWindowLayout?) -> Void = { _ in }
    var updateLayout: @MainActor (SavedWindowLayout) -> Void = { _ in }
    var newEmptyLayout: @MainActor () -> Void = {}
    var setLayoutAutomatic: @MainActor (SavedWindowLayout, SavedWindowLayout.Automatic) -> Void = { _, _ in }
    var applyLayout: @MainActor (SavedWindowLayout) -> Void = { _ in }
    var deleteLayout: @MainActor (SavedWindowLayout) -> Void = { _ in }
    /// Settings → Windows → Forget What skil.li Learned (⌘Z for 10 s).
    var forgetPlacements: @MainActor () -> Void = {}
    /// Every delete of the user's data: at once, Undo ⌘Z in the card for
    /// 10 s (rule 2). Without the app (previews): no card.
    var deletes = UndoableDeletes { _, _, _ in }
    /// What the user made, for Settings → Catalog: the launcher's "?"
    /// reads the same.
    var catalogInput: @MainActor () -> FeatureCatalog.Input = { FeatureCatalog.Input() }
    /// The setup window (Settings → General's Set Up skil.li…, while
    /// Accessibility is off).
    var showSetup: @MainActor () -> Void = {}
    /// Settings → Recorder: the recordings made, one's window, the folder
    /// moved (nil, or why it was refused), one to the Trash (⌘Z).
    var recordings: RecordingLibrary?
    var openRecording: @MainActor (String) -> Void = { _ in }
    var moveRecordings: @MainActor (URL) async -> String? = { _ in nil }
    var deleteRecording: @MainActor (RecordingSummary) -> Void = { _ in }
    /// Better transcription's download, made when the pane shows.
    var betterTranscription: @MainActor () -> BetterTranscription? = { nil }
}

/// The panes, named by what they do for the user, in the sidebar's order.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case keys
    case privacy
    case backup
    case launcher
    case clipboard
    case snippets
    case emoji
    case gifs
    case windows
    case calendar
    case recorder
    case reminders
    case github
    case apps
    case yourDetails
    case ask
    case commands
    case tools
    case skillies
    case aiAccounts
    case catalog
    case about

    /// The sidebar: blocks split by a gap, no headers, as in System
    /// Settings. Every pane is in exactly one, in `allCases`' order.
    static let blocks: [[SettingsPane]] = [
        [.general, .keys, .privacy, .backup],
        [.launcher, .clipboard, .snippets, .emoji, .gifs, .windows],
        [.calendar, .recorder, .reminders, .github, .apps, .yourDetails],
        [.ask, .commands, .tools, .skillies, .aiAccounts],
        [.catalog, .about]
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .keys: "Keys"
        case .privacy: "Privacy"
        case .backup: "Backup"
        case .launcher: "Launcher"
        case .clipboard: "Clipboard"
        case .snippets: "Snippets"
        case .emoji: "Emoji"
        case .gifs: "GIFs"
        case .windows: "Windows"
        case .calendar: "Calendar"
        case .recorder: "Recorder"
        case .reminders: "Reminders"
        case .github: "GitHub"
        case .apps: "Apps"
        case .yourDetails: "Your Details"
        case .ask: "Ask"
        case .commands: "Commands"
        case .tools: "Tools"
        case .skillies: "Skillies"
        case .aiAccounts: "\(Brand.intelligence) Accounts"
        case .catalog: "Catalog"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Ready as soon as you log in, in the glass you like."
        case .keys: "Caps Lock becomes your Hyper Key, ✦, and every shortcut is yours to change."
        case .privacy: "What skil.li may use on this Mac, and all it sends out: what, when, where."
        case .backup: "A copy of everything skil.li keeps, in a folder you choose."
        case .launcher: "The search panel you open from anywhere."
        case .clipboard: "Everything you copy, and your screenshots, ready to paste again."
        case .snippets: "Text you type often, from a keyword or the launcher."
        case .emoji: "Every emoji, by its name or by how you feel, typed where you are."
        case .gifs: "A GIF where you are, animated: from Klipy, or from the ones on this Mac."
        case .windows: "Where your windows go, the layouts you saved, and the apps you stopped using."
        case .calendar: "Your next meeting, one key away, in the launcher and the menu bar."
        case .recorder: "Your meetings recorded on this Mac, both sides, then written out."
        case .reminders: "What you have to do, said in one sentence."
        case .github: "Your pull requests and notifications in the launcher: what is ready, what waits for you."
        case .apps: "The apps skil.li drives: their commands in the launcher, on a key, in Ask."
        case .yourDetails: "Forms filled in for you and your people, and commands that know who you are."
        case .ask: "Say what you want, in any app: skil.li answers, or does it for you."
        case .commands: "Your prompts, on any text, from any app."
        case .tools: "What commands and agents may do on your Mac."
        case .skillies: "Your own scripts, run from the launcher like any command."
        case .aiAccounts: "skil.li writes with your own Claude or ChatGPT, already paid for."
        case .catalog: "Everything skil.li can do, and how you reach each one."
        case .about: "Whether each part of skil.li works now, and where to fix it."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .keys: "keyboard.fill"
        case .privacy: "hand.raised.fill"
        case .backup: "clock.arrow.circlepath"
        case .launcher: "magnifyingglass"
        case .clipboard: "doc.on.clipboard.fill"
        case .snippets: "text.quote"
        case .emoji: "face.smiling.inverse"
        case .gifs: "photo.on.rectangle.angled"
        case .windows: "macwindow.on.rectangle"
        case .calendar: "calendar"
        case .recorder: "record.circle.fill"
        case .reminders: "checklist"
        case .github: "arrow.triangle.pull"
        case .apps: "app.connected.to.app.below.fill"
        case .yourDetails: "person.text.rectangle.fill"
        case .ask: "sparkles"
        case .commands: "wand.and.stars"
        case .tools: "wrench.and.screwdriver.fill"
        case .skillies: "terminal.fill"
        case .aiAccounts: "person.badge.key.fill"
        case .catalog: "square.grid.2x2.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .keys: .indigo
        case .privacy: .blue
        case .backup: .green
        case .launcher: .blue
        case .clipboard: .cyan
        case .snippets: .brown
        // The launcher's Emoji chip is orange.
        case .emoji: .orange
        // The launcher's GIFs chip is mint.
        case .gifs: .mint
        case .windows: .teal
        case .calendar: .red
        // The red dot of a recording in the menu bar.
        case .recorder: .pink
        case .reminders: .orange
        case .github: .gray
        // The Catalog's "In Your Apps" group is indigo.
        case .apps: .indigo
        case .yourDetails: .yellow
        case .ask: .purple
        case .commands: .mint
        case .tools: .pink
        case .skillies: .orange
        case .aiAccounts: .blue
        case .catalog: .indigo
        case .about: .teal
        }
    }
}

/// What the launcher's New Snippet, New Quicklink and New Command make:
/// the pane that makes it opens its editor on a new one.
enum SettingsNew: Equatable {
    case snippet, quicklink, command
}

/// Selected pane, shared with AppKit so menus can deep-link.
@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane? = .general
    /// Asked from the launcher, until the pane that makes it takes it.
    var new: SettingsNew?

    /// The pane that makes `item`, as it shows or when asked while it is
    /// shown: true once, the request then gone.
    func take(_ item: SettingsNew) -> Bool {
        guard new == item else { return false }
        new = nil
        return true
    }
}

// MARK: - Root

/// System Settings layout: glass sidebar of tinted icon tiles, one pane per
/// row, each pane a grouped form under a centered header.
struct SettingsRootView: View {
    @Bindable var preferences: Preferences
    @Bindable var navigation: SettingsNavigation
    let context: SettingsContext
    let markTilt: MarkTilt
    let catalog: CatalogPaneModel
    let apps: AppsPaneModel
    let skillies: SkilliesPaneModel
    /// The search atop the sidebar; the panes' rows find it in the
    /// environment (`settingAnchor`).
    let search: SettingsSearchModel

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(navigation: navigation, search: search)
                .navigationSplitViewColumnWidth(196)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollViewReader { proxy in
                detail
                    .onChange(of: search.scrollRequest) {
                        if let target = search.scrollTarget { proxy.scrollTo(target, anchor: .center) }
                    }
            }
        }
        .environment(search)
        // The panes that make what the launcher's New … asks for read it.
        .environment(navigation)
        .frame(width: 760, height: 680)
    }

    @ViewBuilder
    private var detail: some View {
        let pane = navigation.pane ?? .general
        Group {
            switch pane {
            case .general: GeneralPane(preferences: preferences, tilt: markTilt, shortcuts: context.shortcuts, permissions: context.permissions,
                                       showSetup: context.showSetup)
            case .keys: KeysPane(preferences: preferences, context: context)
            case .privacy: PrivacyPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .backup:
                if let backup = context.backup {
                    BackupPane(preferences: preferences, backup: backup, context: context, open: { navigation.pane = $0 })
                }
            case .launcher: LauncherPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .clipboard: ClipboardPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .snippets: SnippetsPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .emoji: EmojiPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .gifs: GIFsPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .windows: WindowsPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .calendar: AgendaPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .recorder: RecorderPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .reminders: RemindersPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .github: GitHubPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .apps: AppsPane(preferences: preferences, context: context, model: apps)
            case .yourDetails: FormsPane(preferences: preferences, context: context, aiCommands: context.aiCommands,
                                         open: { navigation.pane = $0 })
            case .ask: AskPane(preferences: preferences, context: context, shortcuts: context.shortcuts, toolSettings: context.toolSettings,
                               open: { navigation.pane = $0 })
            case .commands: AICommandsPane(model: context.aiCommands,
                                           leaves: PrivacyMap.line(for: SettingsPane.commands.rawValue, .current(preferences, context)),
                                           open: { navigation.pane = $0 })
            case .tools: ToolsPane(settings: context.toolSettings, preferences: preferences, deletes: context.deletes, helpers: context.rightsHelpers(),
                                   openHelper: context.openRightsHelper,
                                   askChords: context.shortcuts.config.shortcuts.first { $0.action == .aiPrompt("ask") }?.chords?.map(\.keycaps) ?? [],
                                   leaves: PrivacyMap.line(for: SettingsPane.tools.rawValue, .current(preferences, context)),
                                   open: { navigation.pane = $0 })
            case .skillies: SkilliesPane(skillies: context.skillies, preferences: preferences, context: context, model: skillies,
                                            open: { navigation.pane = $0 })
            case .aiAccounts: AIAccountsPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            case .catalog: CatalogPane(preferences: preferences, context: context, model: catalog)
            case .about: AboutPane(preferences: preferences, context: context, open: { navigation.pane = $0 })
            }
        }
        // An app's page in Apps: its name, the way back beside it.
        .navigationTitle(pane == .apps ? apps.title ?? pane.title : pane.title)
    }
}

/// Big centered icon, title and one line of explanation, like the top of a
/// System Settings pane.
struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(spacing: 8) {
            IconTile(symbol: pane.symbol, tint: pane.tint, size: 56)
            SIText(pane.title, alignment: .center)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(pane.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .textCase(nil)
    }
}

/// Rule 3 of the Settings plan: what most people never change, in the
/// section that closes the pane's settings (only a long list follows it:
/// Keys' shortcuts), behind a native disclosure closed each time the pane
/// opens. Closed, its label says what is inside, so nobody opens it to
/// find out; open, the rows follow it in the same group, each with its
/// separator, and the footer explains them.
struct AdvancedSection<Content: View>: View {
    /// "Keep Claude ready, voice language, where a conversation continues".
    let summary: String
    var footer: String?
    /// The search anchors of the rows inside (`settingAnchor`): looking for
    /// one opens it.
    let anchors: [String]
    @ViewBuilder let content: Content
    @State private var expanded = Advanced.startsOpen
    @Environment(SettingsSearchModel.self) private var search: SettingsSearchModel?

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
            } label: {
                if expanded {
                    Text("Advanced")
                } else {
                    LabelDetail("Advanced", summary)
                }
            }
            if expanded {
                content
            }
        } footer: {
            if expanded, let footer {
                SIText(footer)
            }
        }
        .onAppear {
            if let revealing = search?.revealing, anchors.contains(revealing) {
                expanded = true
            } else if !expanded {
                search?.advancedClosed(anchors)
            }
        }
        .onDisappear { if !expanded { search?.advancedOpened(anchors) } }
        .onChange(of: search?.revealing) { _, revealing in
            if let revealing, anchors.contains(revealing) { expanded = true }
        }
        .onChange(of: expanded) { _, open in
            if open { search?.advancedOpened(anchors) } else { search?.advancedClosed(anchors) }
        }
    }
}

@MainActor
enum Advanced {
    /// Self-test hook: panes open with Advanced open, for its captures.
    static var startsOpen = false
}

/// A row's name and, under it, one or two lines that explain it.
struct LabelDetail: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SIText(title)
            SIText(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Rule 2 of the Settings plan: how the pane's feature is reached, at its
/// top, as keycaps (a launcher prefix, an alias, ⇥, the keys of Ask), lined
/// up with the shortcut recorders' keys (their field's padding, then the
/// room of their ⓧ), as Ask's "From the launcher ⇥". Read-only: keys are
/// changed where they live (Keys, Catalog).
struct ReachRow: View {
    let title: String
    let detail: String
    /// Each its own keycap: "pr", an alias.
    var keys: [String] = []
    /// A shortcut's chords: ✦ A.
    var chords: [Chord]?

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(keys, id: \.self) { KeycapLabel($0) }
                    if let chords, !chords.isEmpty {
                        ShortcutView(chords: chords.map(\.keycaps))
                    }
                }
                .padding(.horizontal, 8)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .hidden()
            }
        } label: {
            LabelDetail(title, detail)
        }
    }
}

/// White SF Symbol on a tinted, softly lit rounded square.
struct IconTile: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - General

/// Settings → General, in the order of the Settings plan's rules: the
/// launcher's keys first, when skil.li is there (at login, in the menu
/// bar; macOS's OK beside it only while it waits), how it looks (the glass,
/// each choice drawn in it), then under Advanced, closed, where the
/// launcher opens.
struct GeneralPane: View {
    @Bindable var preferences: Preferences
    let tilt: MarkTilt
    /// The launcher's keys, its first row (2026-10-16: the most
    /// important command is never buried).
    let shortcuts: ShortcutStore
    /// Accessibility, read alone while it is off (Set Up skil.li…).
    let permissions: PermissionCenter
    let showSetup: @MainActor () -> Void
    @State private var loginItem = LoginItem()

    var body: some View {
        Form {
            Section {
                LauncherShortcutRow(store: shortcuts, detail: LauncherShortcutRow.detail)
                // D7: the setup closed with ✕ or Later stays here until
                // Accessibility is on (and in the menu bar).
                if permissions.state(.accessibility) != .granted {
                    LabeledContent {
                        Button("Set Up skil.li…") { showSetup() }
                    } label: {
                        LabelDetail("Accessibility is off", "Shortcuts, the text you select and snippets wait for it.")
                    }
                }
                Toggle("Open skil.li at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .settingAnchor("openAtLogin")
                if loginItem.needsApproval {
                    LabeledContent {
                        Button("Open Settings") { loginItem.openSettings() }
                    } label: {
                        LabelDetail("Waiting for your OK", "Allow skil.li in System Settings → General → Login Items.")
                    }
                }
                Toggle("Show in menu bar", isOn: $preferences.showMenuBarIcon)
                    .settingAnchor("showMenuBarIcon")
            } header: {
                BrandHeader(tilt: tilt)
            } footer: {
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text(preferences.showMenuBarIcon
                         ? "Settings, status and Quit live in the menu bar icon."
                         : "Settings stay one keystroke away: open the launcher and type “settings”, or press ⌘,.")
                }
            }

            Section {
                HStack(spacing: 18) {
                    Spacer(minLength: 0)
                    ForEach(GlassStyle.allCases) { style in
                        GlassStyleCard(style: style, isSelected: preferences.glassStyle == style) {
                            preferences.glassStyle = style
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .settingAnchor("glassStyle")
            } header: {
                Text("Glass")
            } footer: {
                Text("The launcher, the card and the key hints are drawn in this glass.")
            }

            AdvancedSection(summary: "Where the launcher opens",
                            footer: "Drag the launcher by any empty part of its glass to put it anywhere; near the middle of the screen or its usual height it snaps into line. It opens there again, at the same place on every screen.",
                            anchors: ["launcherPlace"]) {
                LabeledContent("Launcher position") {
                    Button("Reset Position") { preferences.launcherPlace = nil }
                        .disabled(preferences.launcherPlace == nil)
                }
                .settingAnchor("launcherPlace")
            }
        }
        .formStyle(.grouped)
        // The glass S turns toward the pointer anywhere over the pane.
        .coordinateSpace(.named(MarkTilt.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tilt.paneSize = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): tilt.pointer(at: location)
            case .ended: tilt.pointer(at: nil)
            }
        }
        .onDisappear { tilt.pointer(at: nil) }
        .onAppear {
            loginItem.refresh()
            shortcuts.refreshWarnings()
        }
        // Only Accessibility, and only while it is off: the switch turned
        // on in System Settings takes the row away.
        .task {
            permissions.refresh([.accessibility])
            while !Task.isCancelled, permissions.state(.accessibility) != .granted {
                try? await Task.sleep(for: .seconds(0.5))
                permissions.refresh([.accessibility])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingTools.changed)) { _ in loginItem.refresh() }
    }
}

// MARK: - Launcher

/// Settings → Launcher, in the order of the Settings plan's rules: its
/// keys first, then search by meaning (the pages and files ⇥ finds) and
/// what that sends off the Mac; the screen it opens on, when it starts
/// again empty and typing in English under Advanced, closed.
struct LauncherPane: View {
    /// ⌘, in the launcher, as its row names it (and Settings' search).
    static let openSettingsTitle = "Open Settings from the launcher"

    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void

    var body: some View {
        Form {
            Section {
                LauncherShortcutRow(store: context.shortcuts)
                ShortcutRow(
                    store: context.shortcuts,
                    id: ShortcutStore.launcherOpenSettingsID,
                    title: Self.openSettingsTitle,
                    chords: context.shortcuts.launcherOpenSettingsChord.map { [$0] }
                )
            } header: {
                PaneHeader(pane: .launcher)
            } footer: {
                Text("Click a shortcut, then press the new keys. How the launcher looks and its place on the screen: General. Quicklinks, aliases and what shows in its results: Catalog.")
            }

            Section {
                Toggle(isOn: $preferences.historyMeaningSearch) {
                    LabelDetail("Search browser history by meaning with ⇥",
                                "In Search Browser History (“history impôts”), describe a page, then ⇥: it is found among the last ones you visited.")
                }
                .settingAnchor("historyMeaningSearch")
                Toggle(isOn: $preferences.fileMeaningSearch) {
                    LabelDetail("Search files by meaning",
                                "In Search Files (“f mon bail”), describe a file: when no file is named so, it is found by meaning on its own, and ⇥ does it at once. Among those named with your words, opened lately or changed this week.")
                }
                .settingAnchor("fileMeaningSearch")
            } footer: {
                Text("Your TypeSafe Jev or OpenAI Decisions key picks it, in SI Accounts.")
            }

            if let line = PrivacyMap.line(for: SettingsPane.launcher.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            AdvancedSection(summary: "The screen it opens on, when it starts again empty, typing in English",
                            anchors: ["launcherScreen", "launcherReset", "launcherEnglishInput"]) {
                Picker(selection: $preferences.launcherScreen) {
                    ForEach(LauncherScreen.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    LabelDetail("Opens on", "On that screen, it opens where you last dragged it.")
                }
                .settingAnchor("launcherScreen")
                Picker(selection: $preferences.launcherReset) {
                    ForEach(LauncherReset.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    LabelDetail("Starts again empty", "Opened again sooner, it shows what you typed and the row you were on. Your last searches come back with ↑ in the empty field.")
                }
                .settingAnchor("launcherReset")
                Toggle(isOn: $preferences.launcherEnglishInput) {
                    LabelDetail("Type in English while open", englishDetail)
                }
                .settingAnchor("launcherEnglishInput")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            english = EnglishTyping.english()?.info.name
            context.shortcuts.refreshWarnings()
        }
    }

    /// The user's English layout's name ("ABC"), read as the pane opens.
    @State private var english: String?

    private var englishDetail: String {
        guard let english else {
            return "No English keyboard is turned on: add ABC in System Settings → Keyboard → Text Input → Edit. Until then this does nothing."
        }
        return "While the launcher is open your keyboard types as \(english), letters and digits where it puts them; yours comes back as it closes. Your shortcuts keep their keys."
    }
}

/// A miniature launcher on a colorful wallpaper, rendered in the real
/// Liquid Glass style it stands for. Selected like macOS Appearance.
struct GlassStyleCard: View {
    let style: GlassStyle
    let isSelected: Bool
    let select: () -> Void

    private var glass: Glass {
        style == .clear ? .clear : .regular
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                ZStack {
                    Wallpaper()
                    VStack(spacing: 0) {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 7, weight: .semibold))
                            RoundedRectangle(cornerRadius: 1.5)
                                .frame(width: 34, height: 3)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary.opacity(0.6))
                        .padding(.horizontal, 8)
                        .frame(height: 18)

                        Rectangle()
                            .fill(.primary.opacity(0.12))
                            .frame(height: 0.5)
                            .padding(.horizontal, 6)

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(0..<3, id: \.self) { row in
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.primary.opacity(0.35))
                                        .frame(width: 7, height: 7)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(.primary.opacity(row == 0 ? 0.55 : 0.3))
                                        .frame(width: [42, 30, 36][row], height: 3)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .glassEffect(glass, in: .rect(cornerRadius: 9))
                    .padding(12)
                }
                .frame(width: 156, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 3 : 1)
                )

                Text(style.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title) glass")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Abstract wallpaper with enough color and contrast for glass to refract.
private struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.36), Color(red: 0.86, green: 0.32, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color(red: 0.32, green: 0.45, blue: 0.98))
                .frame(width: 52)
                .offset(x: 52, y: 30)
                .blur(radius: 10)
            Circle()
                .fill(Color(red: 1.0, green: 0.86, blue: 0.36))
                .frame(width: 30)
                .offset(x: -58, y: -34)
                .blur(radius: 6)
        }
    }
}

// MARK: - Keys

/// Settings → Keys, in the order of the Settings plan's rules: the
/// launcher's keys first, then the Hyper Key (Caps Lock is ✦, drawn as
/// keys, and whether it works; the permission it needs beside it, only
/// while missing), what most never change under Advanced, closed, then the
/// long list: every other shortcut, grouped by how it is typed.
struct KeysPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext

    var body: some View {
        Form {
            Section {
                HyperDiagram()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                LabeledContent("Caps Lock") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.hyperIsActive() ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(context.hyperStatus())
                            .foregroundStyle(.secondary)
                    }
                }
                missing(.accessibility)
                // Input Monitoring only when Accessibility alone is not enough.
                if context.permissions.state(.accessibility) == .granted, !context.shortcutsActive() {
                    missing(.inputMonitoring)
                }
            } header: {
                VStack(spacing: 0) {
                    PaneHeader(pane: .keys)
                    Text("Hyper Key")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // As far from the sentence as a section from the one above.
                        .padding(.top, 10)
                        .settingAnchor("section.superKey")
                }
            } footer: {
                Text("Hold Caps Lock and press a key: shortcuts written with ✦ use it.")
            }

            AdvancedSection(summary: "Caps Lock tapped alone, what other apps see",
                            footer: (context.receivesTrigger()
                                     ? "skil.li handles Caps Lock itself. "
                                     : "Another app, such as Raycast's Hyper Key, handles Caps Lock first, so its own tap setting applies. ")
                                + "Keys skil.li does not use reach the app in front as ⌃⌥⇧⌘ and the key, so its own shortcuts keep working.",
                            anchors: ["hyperTapSendsEscape"]) {
                Toggle("Tap Caps Lock alone to send Escape", isOn: $preferences.hyperTapSendsEscape)
                    .disabled(!context.receivesTrigger())
                    .settingAnchor("hyperTapSendsEscape")
            }

            ShortcutSections(context: context)
        }
        .formStyle(.grouped)
        .onAppear {
            context.permissions.startWatching()
            context.shortcuts.refreshWarnings()
        }
        .onDisappear { context.permissions.stopWatching() }
    }

    /// Rule 6: a permission the Hyper Key needs, only while it is not
    /// granted.
    @ViewBuilder
    private func missing(_ permission: Permission) -> some View {
        let state = context.permissions.state(permission)
        if state != .granted {
            PermissionRow(permission: permission, state: state, notNeeded: false) {
                context.permissions.grant(permission)
            }
        }
    }
}

/// ⇪ → ✦: Caps Lock is the Hyper Key, drawn as real keys.
struct HyperDiagram: View {
    var body: some View {
        HStack(spacing: 16) {
            KeyGlyph(symbol: "⇪", caption: "caps lock", width: 96)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tertiary)
            KeyGlyph(symbol: "✦", caption: "hyper key", width: 96)
        }
    }
}

/// A keyboard key: glyph on top, lowercase label below, like Apple's keys.
struct KeyGlyph: View {
    let symbol: String
    let caption: String
    var width: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(symbol)
                .font(.system(size: 15, weight: .regular))
            Spacer(minLength: 0)
            Text(caption)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(width: width, height: 50, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 0, y: 1.5)
    }
}

// MARK: - Shortcuts

/// Every shortcut, direct ones first then one section per chain (✦K,
/// ✦W), and Add Shortcut: the sections of Keys under the Hyper Key.
struct ShortcutSections: View {
    let context: SettingsContext
    @State private var confirmRestore = false
    @State private var adding = false
    /// The row Add Shortcut… made last: left without keys, it goes when
    /// another is added or Keys closes (docs/adding-a-shortcut.md).
    @State private var added: String?
    @Environment(SettingsSearchModel.self) private var search: SettingsSearchModel?

    private var store: ShortcutStore { context.shortcuts }

    /// Entries outside any group first, then one section per group prefix.
    private var sections: [(id: String, title: String, entries: [ShortcutConfig.Entry])] {
        var global: [ShortcutConfig.Entry] = []
        var grouped: [String: (title: String, entries: [ShortcutConfig.Entry])] = [:]
        var order: [String] = []
        // The launcher's row first in the list, under its name: one row
        // among the shortcuts here (asked: not a second block above the Super
        // Key); General and Launcher show it first on their own.
        let launcher = store.launcherEntry?.id
        let entries = store.config.shortcuts.filter { $0.id == launcher } + store.config.shortcuts.filter { $0.id != launcher }
        for entry in entries {
            if let chords = entry.chords, let group = store.group(containing: chords) {
                let key = Chord.spec(group.prefix)
                if grouped[key] == nil {
                    order.append(key)
                    // "✦K, then a key"; "Windows: ✦W, then a key". The ✦K
                    // group's name in shortcuts.json, "Leader", is an
                    // engineering word: its chain says it.
                    let chain = group.prefix.map(\.description).joined(separator: " ") + ", then a key"
                    grouped[key] = (group.label == "Leader" ? chain : "\(group.label): \(chain)", [])
                }
                grouped[key]?.entries.append(entry)
            } else {
                global.append(entry)
            }
        }
        return [("global", "Shortcuts", global)] + order.compactMap { key in
            grouped[key].map { (key, $0.title, $0.entries) }
        }
    }

    var body: some View {
        Group {
            ForEach(sections, id: \.id) { section in
                Section {
                    ForEach(section.entries) { entry in
                        ShortcutRow(store: store, id: entry.id, title: store.title(of: entry), chords: entry.chords)
                    }
                } header: {
                    if section.id == "global" {
                        Text(section.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .settingAnchor("shortcuts")
                    } else {
                        Text(section.title)
                    }
                }
            }

            Section {
                HStack {
                    Button {
                        adding = true
                    } label: {
                        Label("Add Shortcut…", systemImage: "plus")
                    }
                    .fixedSize()
                    .sheet(isPresented: $adding) {
                        AddShortcutSheet(load: { ShortcutChoice.all(context) }, pick: add)
                    }
                    Spacer()
                    // One click used to erase every custom shortcut: it
                    // asks first, saying what goes.
                    let restoreMessage = store.restoreDefaultsMessage
                    Button("Restore Defaults", role: .destructive) { confirmRestore = true }
                        .disabled(restoreMessage == nil)
                        .confirmationDialog(RestoreDefaults.title, isPresented: $confirmRestore) {
                            Button("Restore Defaults", role: .destructive) { store.resetAll() }
                        } message: {
                            Text(restoreMessage ?? "")
                        }
                }
                .settingAnchor("section.addShortcut")
            } footer: {
                Text("Click a shortcut, then press the new keys: one chord (✦G) or a chain (✦K then G). ⓧ removes it. Add Shortcut… finds any command by name; a command can have several shortcuts. Saved in ~/Library/Application Support/skil.li/shortcuts.json.")
            }
        }
        .onDisappear { dropAddedWithoutKeys() }
    }

    /// Picked in the sheet: its row, without keys, shown where it is in
    /// Keys (scrolled to, glowing). Open App… asks for the app first.
    private func add(_ choice: ShortcutChoice) {
        let action: SkilliAction
        switch choice.kind {
        case .action(let picked): action = picked
        case .chooseApp:
            guard let url = context.chooseApp() else { return }
            action = .openApp(url.path)
        }
        dropAddedWithoutKeys()
        let id = store.add(action)
        added = id
        search?.reveal(SettingsSearch.shortcutAnchor(id), in: .keys, drawing: true)
    }

    private func dropAddedWithoutKeys() {
        guard let id = added else { return }
        added = nil
        if store.recordingID == id { store.cancelRecording() }
        if store.config.shortcuts.first(where: { $0.id == id })?.keys == nil { store.remove(id) }
    }
}

/// One shortcut: its name, the keys as keycaps, click to record new ones.
struct ShortcutRow: View {
    @Bindable var store: ShortcutStore
    let id: String
    let title: String
    let chords: [Chord]?
    /// One line under the name, in the secondary color.
    var detail: String?

    var body: some View {
        LabeledContent {
            ShortcutField(store: store, id: id, chords: chords)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ShortcutNote(store: store, id: id)
                    .font(.caption)
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.recordingID == id)
        .contextMenu {
            if store.isModified(id) {
                Button("Reset to Default") { store.reset(id) }
            }
            if chords != nil {
                Button("Remove Shortcut") {
                    if let deletes = store.deletes { deletes.shortcut(id, in: store) } else { try? store.setKeys(nil, for: id) }
                }
            }
            if store.isCustom(id) {
                Button("Delete", role: .destructive) {
                    if let deletes = store.deletes { deletes.shortcut(id, in: store, deleting: true) } else { store.remove(id) }
                }
            }
        }
        // Keys' rows are found by their names (Settings' search).
        .settingAnchor(SettingsSearch.shortcutAnchor(id))
    }
}

/// The launcher's keys: the first row of General and of Launcher (in Keys,
/// the first of the shortcuts' list). One entry of the store everywhere (`launcherEntry`), so it is
/// one setting shown in three places, never a copy.
struct LauncherShortcutRow: View {
    @Bindable var store: ShortcutStore
    var detail: String?

    static let detail = "The launcher, from any app."

    var body: some View {
        if let entry = store.launcherEntry {
            ShortcutRow(store: store, id: entry.id, title: ShortcutStore.launcherTitle, chords: entry.chords, detail: detail)
        }
    }
}

/// System Settings → Keyboard, where Keyboard Shortcuts… frees a key macOS
/// has. skil.li changes no macOS setting itself but Spotlight's ⌘Space,
/// once the launcher takes it (`SpotlightKey`).
@MainActor
enum KeyboardSettings {
    static let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    static func open() {
        NSWorkspace.shared.open(url)
    }
}

/// Under a shortcut's name: what to press while it records, why the keys
/// were refused (red), what is wrong with a hand-edited one or what it
/// shares with macOS or the launcher (orange; Open Keyboard Settings when
/// macOS has the keys), or the macOS key it replaces on purpose (grey).
/// Nothing otherwise. Settings → General, Keys, Launcher and Catalog.
struct ShortcutNote: View {
    @Bindable var store: ShortcutStore
    let id: String

    /// Whether it says something now.
    static func shows(_ store: ShortcutStore, _ id: String) -> Bool {
        store.recordingID == id || store.lastError?.id == id || store.problems[id] != nil || store.warnings[id] != nil
    }

    var body: some View {
        if store.recordingID == id {
            Text(recordingHint).foregroundStyle(.secondary)
        } else if let error = store.lastError, error.id == id {
            said(error.message, .red, freedIn: error.keyboardSection)
        } else if let problem = store.problems[id] {
            Text(problem).foregroundStyle(.orange)
        } else if let warning = store.warnings[id] {
            if warning.isNote {
                Text(warning.message).foregroundStyle(.secondary)
            } else {
                said(warning.message, .orange, freedIn: warning.keyboardSection)
            }
        }
    }

    /// The message, and when macOS has the keys, the way to its settings.
    @ViewBuilder
    private func said(_ message: String, _ color: Color, freedIn section: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            if section != nil {
                Button("Open Keyboard Settings") { KeyboardSettings.open() }
                    .buttonStyle(.link)
            }
        }
    }

    /// What to press now: a direct shortcut, or the next key of a chain.
    private var recordingHint: String {
        if id == ShortcutStore.launcherOpenSettingsID {
            return "Press the shortcut. ⎋ cancels."
        }
        return store.recordedChords.isEmpty
            ? "Press a shortcut, like ✦G. For a chain, press its first key, like ✦K."
            : "Press another key to chain it, or wait (↩ saves now). ⎋ cancels."
    }
}

/// Time left before recording saves what was typed.
struct CountdownRing: View {
    let deadline: Date
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation) { context in
            let left = max(0, deadline.timeIntervalSince(context.date)) / duration
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
        }
    }
}

/// The keycaps of a shortcut; click to record. While recording it shows
/// what has been typed so far.
struct ShortcutField: View {
    @Bindable var store: ShortcutStore
    let id: String
    let chords: [Chord]?
    var minWidth: CGFloat = 132
    var minHeight: CGFloat = 28
    /// Where the keys sit in it: at its end beside a name (Keys), at its
    /// start under a field (Catalog's popover).
    var alignment: Alignment = .trailing
    /// What a click does instead of recording `id`: a Catalog row whose
    /// action has no shortcut yet adds one first.
    var begin: (() -> Void)?

    private var isRecording: Bool { store.recordingID == id }
    private var hasKeys: Bool { !(chords ?? []).isEmpty }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isRecording {
                    store.cancelRecording()
                } else if let begin {
                    begin()
                } else {
                    store.beginRecording(id)
                }
            } label: {
                HStack(spacing: 6) {
                    if isRecording {
                        if store.recordedChords.isEmpty {
                            Text("Type shortcut…")
                                .foregroundStyle(.secondary)
                        } else {
                            ShortcutView(chords: store.recordedChords.map(\.keycaps))
                            // Waiting for the next key of a chain, or saving.
                            if let deadline = store.recordingDeadline {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                Text("…").foregroundStyle(.secondary)
                                CountdownRing(deadline: deadline, duration: ShortcutStore.sequencePause)
                            }
                        }
                    } else if let chords, !chords.isEmpty {
                        ShortcutView(chords: chords.map(\.keycaps))
                    } else {
                        Text("Record Shortcut")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .frame(minWidth: minWidth, minHeight: minHeight, alignment: alignment)
                .background(
                    isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.0001),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : .clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Press the new shortcut, ⎋ to cancel" : "Click to change")

            // Always visible: removing a shortcut must not hide behind a
            // right-click or ⌫ while recording.
            // At once; ⌘Z in the card gives the keys back (rule 2).
            Button {
                if let deletes = store.deletes { deletes.shortcut(id, in: store) } else { store.clear(id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove this shortcut")
            .accessibilityLabel("Remove Shortcut")
            .opacity(hasKeys && !isRecording ? 1 : 0)
            .disabled(!hasKeys || isRecording)
        }
        .animation(.easeOut(duration: 0.15), value: isRecording)
    }
}

// MARK: - About

struct AboutPane: View {
    let preferences: Preferences
    let context: SettingsContext
    let open: (SettingsPane) -> Void
    @State private var copied = false

    /// "0.1.0 (1290)": the version, then the build (the commit count,
    /// `script/stamp_build.sh`).
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// "bc6863b · built 16 Oct 2026 at 08:45": which commit, and when it
    /// was built (a "+" after the commit: changes not committed yet).
    private static var buildLine: String? {
        let info = Bundle.main.infoDictionary
        guard let commit = info?["SkilliCommit"] as? String else { return nil }
        guard let stamp = info?["SkilliBuildDate"] as? String, let date = ISO8601DateFormatter().date(from: stamp) else { return commit }
        return "\(commit) · built \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// The version, the build, the commit and its date, for Copy Diagnostics.
    private static var fullVersion: String {
        [version, buildLine].compactMap { $0 }.joined(separator: ", ")
    }

    /// What the app knows now, for `Health.lines`; also the self-test's.
    @MainActor
    static func facts(preferences: Preferences, context: SettingsContext) -> Health.Facts {
        var facts = Health.Facts()
        facts.accessibility = context.accessibilityGranted()
        facts.superKeyActive = context.hyperIsActive()
        facts.superKeyStatus = context.hyperStatus()
        facts.shortcutsActive = context.shortcutsActive()
        facts.secureInputApp = AppDelegate.secureInputHolder()
        facts.writer = context.ai.writer(for: nil)?.label
        facts.writerProblem = WritingProvider.allCases.compactMap { context.ai.availability($0).line }.first
        facts.deciders = [DecisionProvider.typeSafe, .openAI].filter { context.ai.decisionKey(for: $0) != nil }.map(\.title)
        facts.clipboardHistory = preferences.clipboardHistory
        facts.clipboardAsksEachTime = !context.clipboard.mayRead
        facts.calendarAccess = context.permissions.state(.calendar) == .granted
        facts.screenRecording = context.permissions.state(.screenRecording) == .granted
        facts.githubSignedIn = context.github?.isSignedIn == true
        facts.githubProblem = context.github?.problem
        facts.githubUpdated = context.github?.lastRefresh
        facts.backupFolderSet = !preferences.backupFolder.isEmpty
        facts.lastBackup = context.backup?.backups().map(\.date).max()
        facts.backupProblem = context.backup?.lastError
        return facts
    }

    var body: some View {
        // Permissions, sign-ins and Secure Input change while this is open.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let lines = Health.lines(Self.facts(preferences: preferences, context: context))
            Form {
                Section {
                    VStack(spacing: 10) {
                        AppMark(size: 84)
                        Text("skil.li")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        VStack(spacing: 2) {
                            Text("Version \(Self.version)")
                            if let line = Self.buildLine {
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        Text(SettingsPane.about.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }

                Section {
                    ForEach(lines, id: \.feature) { line in
                        HealthRow(line: line, open: { title in
                            if let pane = SettingsPane.allCases.first(where: { $0.title == title }) { open(pane) }
                        })
                    }
                } header: {
                    Text("Health")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingAnchor("section.health")
                }

                Section {
                    HStack {
                        Button("Copy Diagnostics") {
                            let system = "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Health.diagnostics(lines, version: Self.fullVersion, system: system), forType: .string)
                            copied = true
                        }
                        if copied {
                            Text("Copied").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .settingAnchor("section.copyDiagnostics")
                } footer: {
                    Text("The version, macOS and the lines above, to paste in a message when something does not work. Nothing of yours is in it.")
                }

                Section {
                } footer: {
                    Text("Made by NomDeLaSociete.")
                        .frame(maxWidth: .infinity)
                }
            }
            .formStyle(.grouped)
        }
        // Calendar and Screen Recording read while this shows, as the
        // other panes do: launch reads only what it needs.
        .onAppear { context.permissions.startWatching() }
        .onDisappear { context.permissions.stopWatching() }
    }
}

/// One feature: a state mark, its name, what it does now; where to fix it.
private struct HealthRow: View {
    let line: Health.Line
    let open: (String) -> Void

    var body: some View {
        LabeledContent {
            if let pane = line.pane {
                Button {
                    open(pane)
                } label: {
                    HStack(spacing: 4) {
                        Text(pane)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    SIText(line.feature)
                    SIText(line.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .font(.system(size: 15))
            }
        }
    }

    private var symbol: String {
        switch line.state {
        case .ok: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .off: "minus.circle"
        }
    }

    private var tint: Color {
        switch line.state {
        case .ok: .green
        case .attention: .orange
        case .off: .secondary
        }
    }
}

/// The Halo menthe mark from the brand kit, masked and lit like an app icon.
/// Its background is opaque by design: never place text over it.
struct AppMark: View {
    let size: CGFloat

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.22), radius: size * 0.1, y: size * 0.05)
            .accessibilityLabel("skil.li")
    }
}

struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Keycaps

/// Chords drawn as keycaps, chords separated by a chevron: ✦ K › U.
struct ShortcutView: View {
    let chords: [[String]]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(chords.enumerated()), id: \.offset) { index, keys in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 3) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        KeycapLabel(key)
                    }
                }
            }
        }
    }
}

/// SwiftUI twin of `KeycapView`: soft fill, hairline edge, raised by 1 pt.
struct KeycapLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 20)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 0, y: 1)
    }
}
