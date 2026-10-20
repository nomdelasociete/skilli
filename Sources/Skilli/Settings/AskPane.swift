import AppKit
import SkilliCore
import Speech
import SwiftUI

/// Settings → Ask, in the order of the Settings plan's rules: how to reach
/// it first, as keys (✦A, ✦V, ⇥ in the launcher) that are also its first
/// settings; then what may run without asking when it acts, and the
/// user's rules in their words; what leaves the Mac when you ask, and to
/// whom; the rest (Claude kept ready, the voice's language, where a
/// conversation continues) under Advanced, closed. A permission shows only
/// while the feature beside it lacks it.
struct AskPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    @Bindable var shortcuts: ShortcutStore
    @Bindable var toolSettings: ToolSettings
    /// Shows another pane (Privacy, SI Accounts, Tools).
    let open: (SettingsPane) -> Void
    @State private var voiceLocales: [String] = []

    var body: some View {
        Form {
            Section {
                if let entry = shortcuts.config.shortcuts.first(where: { $0.action == .aiPrompt("ask") }) {
                    ShortcutRow(store: shortcuts, id: entry.id, title: "Ask", chords: entry.chords)
                }
                if let entry = shortcuts.config.shortcuts.first(where: { $0.action == .askByVoice }) {
                    ShortcutRow(store: shortcuts, id: entry.id, title: "Ask by Voice", chords: entry.chords)
                }
                missing(.microphone)
                LabeledContent {
                    // Lined up with the shortcuts' keys above (their field's
                    // padding, then the room of their ⓧ).
                    HStack(spacing: 4) {
                        KeycapLabel("⇥")
                            .padding(.horizontal, 8)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .hidden()
                    }
                } label: {
                    LabelDetail("From the launcher", "Type what you want, then ⇥.")
                }
            } header: {
                PaneHeader(pane: .ask)
            } footer: {
                Text("skil.li answers in the card, rewrites the selection, finds the menu item, opens the app, or does it for you in the window in front.")
            }

            Section {
                Picker("Approvals", selection: $toolSettings.mode) {
                    Text("Ask Every Time").tag(ApprovalMode.ask)
                    Text("Ask Before Changes").tag(ApprovalMode.auto)
                    Text("Always Allow").tag(ApprovalMode.always)
                }
                .settingAnchor("approvalMode")
                missing(.screenRecording)
            } header: {
                Text("When It Acts")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("section.whenItActs")
            } footer: {
                Text(approvalFooter + " What each tool may do: Tools.")
            }

            RulesSection(settings: toolSettings, deletes: context.deletes, canCheck: context.canCheckRules(), open: open)

            if let line = PrivacyMap.line(for: SettingsPane.ask.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            AdvancedSection(summary: "Keep Claude ready, voice language, where a conversation continues, skills",
                            anchors: ["keepClaudeReady", "voiceLanguage", "handoffTarget", "handoffTerminal", "skills", "askUsesClaudeCodeSkills"]) {
                Toggle(isOn: $preferences.keepClaudeReady) {
                    LabelDetail("Keep Claude ready",
                                "The next answer starts in about 0.6 s instead of 1 s: a spare Claude Code waits outside skil.li, using about 230 MB and no tokens.")
                }
                .settingAnchor("keepClaudeReady")
                Picker(selection: $preferences.voiceLanguage) {
                    Text("Automatic (\(Self.languageName(VoiceInput.keyboardLanguage)))").tag("")
                    ForEach(voiceLocales, id: \.self) { identifier in
                        Text(Self.languageName(identifier)).tag(identifier)
                    }
                } label: {
                    LabelDetail("Voice language", "What you say to Ask by Voice and Dictate becomes text on this Mac; macOS downloads each language once.")
                }
                .settingAnchor("voiceLanguage")
                .task {
                    voiceLocales = await SpeechTranscriber.supportedLocales.map(\.identifier)
                        .sorted { Self.languageName($0) < Self.languageName($1) }
                }
                Picker(selection: $preferences.handoffTarget) {
                    ForEach(Handoff.Target.allCases, id: \.self) { target in
                        Text(installed(target) ? target.title : "\(target.title) (not installed)").tag(target)
                    }
                } label: {
                    LabelDetail("Continue in",
                                "After an answer, ⌘↩ opens a new \(preferences.handoffTarget.title) session that already has the conversation. skil.li keeps nothing of it.")
                }
                .settingAnchor("handoffTarget")
                Picker("Terminal", selection: $preferences.handoffTerminal) {
                    ForEach(HandoffLauncher.terminals, id: \.self) { Text($0.title).tag($0) }
                }
                .settingAnchor("handoffTerminal")
                AskSkillsRows(preferences: preferences, skills: context.agentSkills)
            }

            // The long list, last.
            if let scheduler = context.scheduler {
                ScheduledAsksSection(scheduler: scheduler, deletes: context.deletes, showAnswer: context.showScheduledAnswer)
            }
        }
        .formStyle(.grouped)
        .task { await context.ai.refresh() }
        .onAppear {
            context.permissions.startWatching()
            context.aiCommands.refresh()
        }
        .onDisappear {
            context.permissions.stopWatching()
            // A rule added and left without words goes.
            toolSettings.removeEmptyRules()
        }
    }

    /// Rule 6: a permission the feature beside it needs, only while it is
    /// not granted.
    @ViewBuilder
    private func missing(_ permission: Permission) -> some View {
        let state = context.permissions.state(permission)
        if state != .granted {
            PermissionRow(permission: permission, state: state, notNeeded: false) {
                context.permissions.grant(permission)
            }
        }
    }

    /// What waits for the user's OK in the mode chosen.
    private var approvalFooter: String {
        switch toolSettings.mode {
        case .ask: "Every step that reads or acts waits for your OK in the card: Allow ↩, Always ⌘↩, Deny esc."
        case .auto: "Reading the selection, the clipboard or the menus and opening apps run at once; replacing text, copying, choosing menus wait for your OK."
        case .always: "Steps run without asking, unless one of your rules below says otherwise. Commands still only get the tools you turn on for them."
        }
    }

    private func installed(_ target: Handoff.Target) -> Bool {
        switch target {
        case .claude: context.ai.claudeBinary != nil
        case .codex: HandoffLauncher.codexPaths.contains(where: FileManager.default.isExecutableFile(atPath:))
        }
    }

    private static func languageName(_ identifier: String?) -> String {
        guard let identifier else { return "keyboard" }
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}

/// Your Rules: sentences in the user's words, each Allow, Ask First or
/// Never, checked before an agent's step by the decision model
/// (`ApprovalRules`, `RuleJudge`). Written only here: no tool writes them.
private struct RulesSection: View {
    @Bindable var settings: ToolSettings
    /// − removes a rule at once; ⌘Z in the card puts it back.
    let deletes: UndoableDeletes
    /// A TypeSafe or OpenAI key can check them.
    let canCheck: Bool
    let open: (SettingsPane) -> Void
    @FocusState private var focused: String?

    var body: some View {
        Section {
            if settings.rules.isEmpty {
                Text("None yet: the approvals above decide alone.")
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.rules) { rule in
                HStack(spacing: 8) {
                    TextField("Rule", text: Binding(get: { rule.text }, set: { settings.updateRule(rule.id, text: $0) }),
                              prompt: Text("In your words: Ask before anything that sends a message"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...3)
                        .focused($focused, equals: rule.id)
                    Picker("Effect", selection: Binding(get: { rule.effect }, set: { settings.updateRule(rule.id, effect: $0) })) {
                        ForEach(ApprovalRule.Effect.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        deletes.rule(rule.id, in: settings)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this rule")
                }
            }
            Menu {
                ForEach(suggestions) { suggestion in
                    Button("\(suggestion.effect.title): \(suggestion.text)") {
                        settings.addRule(suggestion.text, effect: suggestion.effect)
                    }
                }
            } label: {
                Label("Add Rule", systemImage: "plus")
            } primaryAction: {
                let id = settings.addRule()
                DispatchQueue.main.async { focused = id }
            }
            .fixedSize()
            .help("A new rule in your words; the arrow offers examples.")
            if !canCheck {
                LabeledContent {
                    PaneLink(pane: .aiAccounts, open: open)
                } label: {
                    LabelDetail("Not applied yet", "Your rules need a TypeSafe Jev or OpenAI key to check each step against them.")
                }
            }
        } header: {
            Text("Your Rules")
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingAnchor("approvalRules")
        } footer: {
            Text("Before an agent's step, your TypeSafe Jev or OpenAI key checks it against your rules in a split second, and the card says which rule decided. A rule never allows a tool you block in Tools, and changes to skil.li's settings always ask.")
        }
    }

    /// The examples not written yet.
    private var suggestions: [ApprovalRule] {
        let written = Set(settings.rules.map { SettingsTable.folded($0.said) })
        return ApprovalRules.suggestions.filter { !written.contains(SettingsTable.folded($0.said)) }
    }
}
