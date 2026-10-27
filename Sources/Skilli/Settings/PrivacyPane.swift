import AppKit
import SkilliCore
import SwiftUI

/// Settings → Privacy: what skil.li may use on this Mac, then everything
/// it sends out. First each permission with what it turns on, its state
/// read live and its one button, and the apps it sends commands to; last,
/// the long list: by where it goes (`PrivacyMap`), what goes and when, each
/// row pointing to the pane where its switch or account lives. Nothing here
/// asks macOS for anything by itself, and no setting is repeated here.
struct PrivacyPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane: where a row's switch lives.
    let open: (SettingsPane) -> Void
    @State private var automation: [String: AutomationAccess.State] = [:]
    /// Self-test hook: drawn as if this were set up (every place in use).
    @MainActor static var sample: PrivacyMap.Setup?

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    PermissionRow(permission: permission, state: context.permissions.state(permission),
                                  notNeeded: permission == .inputMonitoring && context.shortcutsActive()) {
                        context.permissions.grant(permission)
                    }
                    .settingAnchor(SettingsSearch.permissionAnchor(permission.rawValue))
                }
            } header: {
                VStack(spacing: 0) {
                    PaneHeader(pane: .privacy)
                    Text("Permissions")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingAnchor("permissions")
                }
            } footer: {
                Text("Accessibility is the one skil.li needs; each other one turns on what it lists. Nothing here asks by itself: Allow asks macOS, Open Settings opens the list where only you can turn it on.")
            }

            Section {
                ForEach(AutomationAccess.targets(reusingTabs: preferences.quicklinkReuseTab)) { target in
                    AutomationRow(target: target, state: automation[target.bundleID])
                }
            } header: {
                Text("Apps skil.li Sends Commands To")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("section.automation")
            } footer: {
                Text("macOS asks the first time skil.li sends an app a command, and says whether it may only while that app is open. Your answers are in System Settings → Privacy & Security → Automation.")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PrivacyMap.statement)
                            .fontWeight(.medium)
                        Text(PrivacyMap.staysHere)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("What Leaves This Mac")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("section.whatLeaves")
                    .padding(.top, 10)
            } footer: {
                Text(PrivacyMap.syncs)
            }

            ForEach(PrivacyMap.sections(for: setup)) { section in
                Section {
                    DestinationRow(section: section, open: open)
                    ForEach(section.rows) { row in
                        FlowRow(row: row, open: open)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            context.permissions.startWatching()
            context.aiCommands.refresh()
        }
        .onDisappear { context.permissions.stopWatching() }
        // macOS answers for an app only while it is open: read again now
        // and then while the pane shows (four quick questions, no prompt).
        .task {
            while !Task.isCancelled {
                let states = await AutomationAccess.states(of: AutomationAccess.targets(reusingTabs: preferences.quicklinkReuseTab))
                if states != automation { automation = states }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var setup: PrivacyMap.Setup {
        Self.sample ?? .current(preferences, context)
    }
}

extension PrivacyMap.Setup {
    /// What is set up now, for `PrivacyMap`: who writes Ask and each
    /// command (`AIStore.writer(for:)`, as a run would pick), the keys, the
    /// switches, GitHub, servers and webhooks, the backup folder. Settings
    /// → Privacy, and the line each pane says (Ask, SI Accounts, GitHub,
    /// Backup, Your Details).
    @MainActor
    static func current(_ preferences: Preferences, _ context: SettingsContext) -> PrivacyMap.Setup {
        let ai = context.ai
        var setup = PrivacyMap.Setup()
        setup.claude = switch ai.activeEngine {
        case .subscription?: .claudeCode
        case .apiKey?: .apiKey
        default: nil
        }
        if case .signedIn = ai.codexStatus { setup.chatGPT = true }
        setup.openAIKey = ai.hasOpenAIKey
        setup.typeSafeKey = ai.decisionKeys.contains(.typeSafe)
        // Ask with tools and commands that act need Claude Code signed in.
        setup.claudeCode = ai.isSignedIn && ai.claudeBinary != nil
        let commands = context.aiCommands.commands
        setup.askWriter = ai.writer(for: commands.first(where: \.isAsk)?.model)?.choice.provider
        setup.commands = commands.filter { !$0.isAsk }.map { command in
            .init(title: command.title, writer: command.isAct ? nil : ai.writer(for: command.model)?.choice.provider, acts: command.isAct,
                  aboutYou: command.includeProfile || command.template.uses(.profile))
        }
        // The same choice as the card's ⌘↩ and Help Me Choose: the one in
        // Settings → Ask, else the other one found.
        let found = context.rightsHelpers()
        if let target = found.contains(preferences.handoffTarget) ? preferences.handoffTarget : found.first {
            setup.continueIn = target == .claude ? .claude : .chatGPT
        }
        setup.scheduledAsks = context.scheduler?.asks.filter(\.isOn).map(\.schedule.spoken) ?? []
        setup.fileMeaning = preferences.fileMeaningSearch
        setup.historyMeaning = preferences.historyMeaningSearch
        setup.clipboardMeaning = preferences.clipboardMeaningSearch
        setup.snippetMeaning = preferences.snippetMeaningSearch
        setup.emojiMeaning = preferences.emojiMeaningSearch
        setup.clipboardHistory = preferences.clipboardHistory
        setup.screenshots = preferences.clipboardScreenshots
        setup.imagesCopied = preferences.imageTagsClipboard
        setup.imagesFolder = preferences.imageTagsFolder
        setup.linkPreviews = preferences.clipboardLinkPreviews
        setup.gifSearch = context.gifs?.canSearchKlipy == true && !preferences.catalogOff.contains("cmd:\(LauncherCommand.ID.searchGIFs.rawValue)")
        setup.currencyRates = !preferences.catalogOff.contains("catalog.currency")
        setup.autoQuit = preferences.autoQuit
        setup.imageFolder = FileManager.default.displayName(atPath: preferences.imageFolder.path)
        if let github = context.github, github.isSignedIn {
            setup.githubLogin = github.login ?? ""
            let environment = (ProcessInfo.processInfo.environment["RELAY_PUBLIC_URL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if github.hasRelayToken || github.relayDevice.canRevoke, let origin = RelayAddress.origin(environment.isEmpty ? preferences.relayPublicURL : environment) {
                setup.relayHost = origin.host() ?? origin.absoluteString
            }
            setup.githubServerSync = preferences.githubServerSync
        }
        setup.servers = context.toolSettings.servers.map(\.name)
        setup.webhooks = context.toolSettings.customTools.map(\.name)
        setup.rules = !ApprovalRules.active(context.toolSettings.rules).isEmpty
        // Where backups go, and whether that folder syncs: by its place,
        // else macOS says (Desktop and Documents in iCloud).
        if !preferences.backupFolder.isEmpty {
            let folder = URL(fileURLWithPath: preferences.backupFolder, isDirectory: true)
            setup.backupFolder = BackupPane.shown(folder)
            setup.backupSyncs = BackupPlan.syncService(ofPath: folder.path)
                ?? (FileManager.default.isUbiquitousItem(at: folder) ? "iCloud" : nil)
        }
        return setup
    }
}

// MARK: - Permissions

/// One permission: what it turns on, its state, its one button. Also beside
/// the feature that needs it (Ask by Voice, doing it here), only while it
/// is not granted.
struct PermissionRow: View {
    let permission: Permission
    let state: PermissionCenter.State
    /// Input Monitoring while shortcuts already work.
    let notNeeded: Bool
    let grant: () -> Void

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(permission.title)
                        if permission.isRequired {
                            Text("Required")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(state == .waiting ? permission.waitingHint : permission.turnsOn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                IconTile(symbol: permission.symbol, tint: permission.tint, size: 22)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .granted:
            OnLabel()
        case _ where notNeeded:
            Text("Not needed")
                .foregroundStyle(.secondary)
                .help("Shortcuts work with Accessibility alone on this Mac.")
        case .notAsked:
            Button("Allow", action: grant)
        case .waiting, .denied:
            Button("Open Settings", action: grant)
        }
    }
}

/// "✓ On", in green: granted.
private struct OnLabel: View {
    var body: some View {
        Label("On", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .fontWeight(.medium)
    }
}

/// An app skil.li sends commands to, and whether macOS lets it.
private struct AutomationRow: View {
    let target: AutomationAccess.Target
    let state: AutomationAccess.State?

    var body: some View {
        LabeledContent {
            switch state {
            case .granted:
                OnLabel()
            case .denied:
                Button("Open Settings") { NSWorkspace.shared.open(AutomationAccess.settingsURL) }
            case .notAsked:
                Text("Not asked yet")
                    .foregroundStyle(.secondary)
                    .help("macOS asks the first time skil.li sends \(target.name) a command.")
            case .unknown, nil:
                Text("Not open")
                    .foregroundStyle(.secondary)
                    .help("macOS says whether skil.li may send \(target.name) commands only while it is open.")
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                    Text(target.uses)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                AppIcon(bundleID: target.bundleID)
            }
        }
    }
}

/// The app's own icon, 22 pt, like the tiles beside it.
private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        // System Events' own icon is a blank grid: a gear says it better.
        if bundleID == "com.apple.systemevents" {
            IconTile(symbol: "gearshape.2.fill", tint: .gray, size: 22)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            IconTile(symbol: "app", tint: .gray, size: 22)
        }
    }
}

// MARK: - What leaves this Mac

/// Where it goes: who, how it is reached (or that nothing goes there), and
/// where to set it up when nothing does.
private struct DestinationRow: View {
    let section: PrivacyMap.Section
    let open: (SettingsPane) -> Void

    var body: some View {
        LabeledContent {
            if !section.inUse, let pane = setupPane {
                PaneLink(pane: pane, open: open)
            }
        } label: {
            RowLabel(title: section.destination.title, detail: section.status, symbol: symbol, tint: tint)
                .opacity(section.inUse ? 1 : 0.75)
        }
    }

    /// Where an account or a key is added.
    private var setupPane: SettingsPane? {
        switch section.destination {
        case .claude, .chatGPT, .openAI, .typeSafe: .aiAccounts
        case .github: .github
        case .klipy: .gifs
        case .huggingFace: .recorder
        case .exchangeRates: .catalog
        case .websites, .yours, .apple: nil
        }
    }

    // The same tiles as Settings → SI Accounts and the panes.
    private var symbol: String {
        switch section.destination {
        case .claude: "person.crop.circle.fill"
        case .chatGPT: "bubble.left.and.bubble.right.fill"
        case .openAI: "key.fill"
        case .typeSafe: "arrow.triangle.branch"
        case .github: SettingsPane.github.symbol
        case .klipy: SettingsPane.gifs.symbol
        case .huggingFace: "arrow.down.circle.fill"
        case .exchangeRates: "dollarsign.arrow.circlepath"
        case .websites: "globe"
        case .yours: SettingsPane.tools.symbol
        case .apple: "apple.logo"
        }
    }

    private var tint: Color {
        switch section.destination {
        case .claude: .orange
        case .chatGPT: .teal
        case .openAI: .blue
        case .typeSafe: .orange
        case .github: .gray
        case .klipy: SettingsPane.gifs.tint
        case .huggingFace: SettingsPane.recorder.tint
        case .exchangeRates: .green
        case .websites: .blue
        case .yours: SettingsPane.tools.tint
        case .apple: .gray
        }
    }
}

/// One feature that sends: what, when, what it applies to, whether its
/// switch is on, and the pane where that switch lives.
private struct FlowRow: View {
    let row: PrivacyMap.Row
    let open: (SettingsPane) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                SIText(row.flow.title)
                if let note = row.note {
                    SIText(note)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                SIText(row.flow.sends)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Label {
                    SIText(row.flow.when)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if let isOn = row.isOn {
                    StatusPill(text: isOn ? "On" : "Off", tint: isOn ? .green : .secondary)
                        .help(row.flow.toggle.map { "“\($0)”" } ?? "")
                }
                if let pane = row.flow.pane.flatMap(SettingsPane.init(rawValue:)) {
                    PaneLink(pane: pane, open: open)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// "Clipboard ›": shows the pane where the switch or the account lives.
/// Gray, as System Settings draws the way to another pane.
struct PaneLink: View {
    let pane: SettingsPane
    let open: (SettingsPane) -> Void
    @State private var hovering = false

    var body: some View {
        Button { open(pane) } label: {
            HStack(spacing: 3) {
                SIText(pane.title)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(hovering ? .primary : .secondary)
        .onHover { hovering = $0 }
        .help("Open \(pane.title)")
    }
}

/// Rule 7 of the Settings plan, in a pane: what its features send off the
/// Mac and to whom, in one sentence (`PrivacyMap.line(for:)`, from what is
/// set up), and the way to the whole list in Privacy (or to SI Accounts
/// when an account is needed first).
struct LeavesMacRow: View {
    let line: PrivacyMap.PaneLine
    let open: (SettingsPane) -> Void

    var body: some View {
        LabeledContent {
            if let pane = SettingsPane(rawValue: line.more) {
                PaneLink(pane: pane, open: open)
            }
        } label: {
            Label {
                LabelDetail("What leaves this Mac", line.text)
            } icon: {
                IconTile(symbol: SettingsPane.privacy.symbol, tint: SettingsPane.privacy.tint, size: 22)
            }
        }
    }
}

extension Permission {
    /// Its tile's color in Settings → Privacy.
    var tint: Color {
        switch self {
        case .accessibility: .blue
        case .inputMonitoring: .indigo
        case .screenRecording: .purple
        case .microphone: .orange
        case .calendar: .pink
        case .reminders: .red
        case .contacts: .brown
        case .pasteboard: .cyan
        case .fullDiskAccess: .gray
        case .camera: .green
        case .bluetooth: .blue
        }
    }
}
