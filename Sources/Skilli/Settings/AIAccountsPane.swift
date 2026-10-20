import AppKit
import SkilliCore
import SwiftUI

/// Settings → SI Accounts, in the order of the Settings plan's rules: who
/// writes (the default model, Ask and every command) and the account it
/// needs, right under it; who chooses in a split second (TypeSafe Jev, else
/// the OpenAI key); what leaves the Mac and to whom; then, under Advanced,
/// closed, how Claude is paid and every other account and key. A key a
/// chosen provider needs is never there: it shows beside that provider.
/// Every account says where it stands and can be tested with one real
/// request.
struct AIAccountsPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy).
    let open: (SettingsPane) -> Void
    @State private var keyDraft = ""
    @State private var keyError: String?
    @State private var decisionDrafts: [DecisionProvider: String] = [:]
    /// The last key that could not be saved, and why.
    @State private var decisionError: (provider: DecisionProvider, message: String)?

    private var ai: AIStore { context.ai }

    /// Each account the pane shows, once: under Writing when the default
    /// model needs it, under Choosing when it chooses, else under Advanced.
    enum Account: CaseIterable {
        case claudeSubscription, claudeKey, chatGPT, openAI, typeSafe

        /// For Advanced's label.
        var name: String {
            switch self {
            case .claudeSubscription: "Claude subscription"
            case .claudeKey: "Claude API key"
            case .chatGPT: "ChatGPT"
            case .openAI: "OpenAI API key"
            case .typeSafe: "TypeSafe Jev"
            }
        }

        /// Its row's anchor for Settings' search: its `SettingsTable` key.
        var anchor: String {
            switch self {
            case .claudeSubscription: "claudeSubscription"
            case .claudeKey: "claudeAPIKey"
            case .chatGPT: "chatGPTSubscription"
            case .openAI: "openAIKey"
            case .typeSafe: "typeSafeKey"
            }
        }
    }

    var body: some View {
        let writing = writingAccounts
        let deciding = decidingAccount
        let advanced = Account.allCases.filter { !writing.contains($0) && $0 != deciding }
        Form {
            Section {
                ModelPicker(ai: ai, choice: Binding(
                    get: { preferences.writingModel },
                    set: { if let choice = $0 { preferences.writingModel = choice } }
                ), saysHow: false)
                .settingAnchor("writingModel")
                ForEach(writing, id: \.self) { account in
                    rows(account, writes: true, decides: false)
                }
            } header: {
                VStack(spacing: 0) {
                    PaneHeader(pane: .aiAccounts)
                    Text("Writing")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingAnchor("section.writing")
                }
            } footer: {
                footer(writingFooter, errors: writing)
            }

            Section {
                if writing.contains(deciding) {
                    // The OpenAI key above writes and chooses: its choice test.
                    DecisionTestRow(result: ai.decisionTests[.openAI]) {
                        Task { await ai.testDecision(.openAI) }
                    }
                } else {
                    // The OpenAI key chooses, and writes for the commands set to it.
                    rows(deciding, writes: deciding == .openAI, decides: true)
                }
            } header: {
                Text("Choosing")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingAnchor("section.choosing")
            } footer: {
                footer(decidingFooter, errors: writing.contains(deciding) ? [] : [deciding])
            }

            if let line = PrivacyMap.line(for: SettingsPane.aiAccounts.rawValue, .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            AdvancedSection(summary: (["How Claude is paid"] + advanced.map(\.name)).joined(separator: ", "), footer: Self.keysNote,
                            anchors: ["aiEngineMode"] + advanced.map(\.anchor)) {
                Picker(selection: $preferences.aiEngineMode) {
                    ForEach(AIEngineMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    LabelDetail("Pay for Claude with", "Your Claude plan, through Claude Code, or a key billed per use by Anthropic.")
                }
                .settingAnchor("aiEngineMode")
                ForEach(advanced, id: \.self) { account in
                    rows(account, writes: true, decides: true)
                    if let message = error(for: account) {
                        Text(message).font(.callout).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await ai.refresh() }
        .onAppear { context.aiCommands.refresh() }
        // Back from signing in, in Terminal and the browser.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await ai.refresh() }
        }
    }

    // MARK: - Where each account goes

    /// What the default model needs to write.
    private var writingAccounts: [Account] {
        switch preferences.writingModel.provider {
        case .claude: claudeAccounts
        case .chatGPT: [.chatGPT]
        case .openAI: [.openAI]
        }
    }

    /// Claude's way in use; both ways while neither works (sign in, or
    /// paste a key: either one makes Claude write).
    private var claudeAccounts: [Account] {
        switch preferences.aiEngineMode {
        case .subscription: return [.claudeSubscription]
        case .apiKey: return [.claudeKey]
        case .auto:
            // Still asking Claude Code: its row, unless a key already writes.
            if ai.isSignedIn || (ai.claudeStatus == nil && !ai.hasAPIKey) { return [.claudeSubscription] }
            return ai.hasAPIKey ? [.claudeKey] : [.claudeSubscription, .claudeKey]
        }
    }

    /// Who chooses: Jev when its key is saved, else the OpenAI key, else
    /// Jev's field (the fastest).
    private var decidingAccount: Account {
        if ai.decisionKeys.contains(.typeSafe) { return .typeSafe }
        return ai.hasOpenAIKey ? .openAI : .typeSafe
    }

    // MARK: - Rows

    /// An account's row (its state, Sign In, its key or its field), then its
    /// tests: writing a sample sentence, choosing for a sample request.
    @ViewBuilder
    private func rows(_ account: Account, writes: Bool, decides: Bool) -> some View {
        switch account {
        case .claudeSubscription:
            LabeledContent {
                subscriptionControl
            } label: {
                RowLabel(title: "Claude subscription", detail: "Your Claude plan, through Claude Code on this Mac", symbol: "person.crop.circle.fill",
                         tint: .orange)
            }
            .settingAnchor("claudeSubscription")
            if ai.isSignedIn {
                TestRow(result: ai.tests[.subscription], name: "Claude") {
                    Task { await ai.test(.subscription) }
                }
            }
        case .claudeKey:
            LabeledContent {
                if ai.hasAPIKey {
                    savedControl { context.deletes.apiKey(in: ai) }
                }
            } label: {
                RowLabel(title: "Claude API key", detail: "Billed per use by Anthropic", symbol: "key.fill", tint: .gray)
            }
            .settingAnchor("claudeAPIKey")
            if ai.hasAPIKey {
                TestRow(result: ai.tests[.apiKey], name: "Claude") {
                    Task { await ai.test(.apiKey) }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("Claude API key", text: $keyDraft, prompt: Text("Paste a key: sk-ant-…"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        case .chatGPT:
            LabeledContent {
                codexControl
            } label: {
                RowLabel(title: "ChatGPT subscription", detail: "Your ChatGPT plan, through Codex on this Mac", symbol: "bubble.left.and.bubble.right.fill",
                         tint: .teal)
            }
            .settingAnchor("chatGPTSubscription")
            if case .signedIn = ai.codexStatus {
                TestRow(result: ai.tests[.codex], name: "ChatGPT") {
                    Task { await ai.test(.codex) }
                }
            }
        case .openAI:
            decisionKeyRow(.openAI, title: "OpenAI API key", detail: "Billed per use by OpenAI: writes with its models, and chooses", tint: .blue)
            if ai.hasOpenAIKey {
                if writes {
                    TestRow(result: ai.tests[.openAI], name: "OpenAI") {
                        Task { await ai.test(.openAI) }
                    }
                }
                if decides {
                    DecisionTestRow(result: ai.decisionTests[.openAI]) {
                        Task { await ai.testDecision(.openAI) }
                    }
                }
            }
        case .typeSafe:
            decisionKeyRow(.typeSafe, title: DecisionProvider.typeSafe.title, detail: "Billed per use by TypeSafe: a fraction of a cent a choice",
                           tint: .orange)
            if ai.decisionKeys.contains(.typeSafe) {
                DecisionTestRow(result: ai.decisionTests[.typeSafe]) {
                    Task { await ai.testDecision(.typeSafe) }
                }
            }
        }
    }

    /// "Saved" and Remove: a key kept in the Keychain. Removed at once;
    /// ⌘Z in the card saves it again (rule 2).
    private func savedControl(remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            StatusPill(text: "Saved", tint: .green)
            Button("Remove", role: .destructive, action: remove)
        }
    }

    /// A deciding key: saved (Remove) or a field to paste it.
    @ViewBuilder
    private func decisionKeyRow(_ provider: DecisionProvider, title: String, detail: String, tint: Color) -> some View {
        LabeledContent {
            if ai.decisionKeys.contains(provider) {
                savedControl { context.deletes.decisionKey(provider, in: ai) }
            }
        } label: {
            RowLabel(title: title, detail: detail, symbol: provider == .openAI ? "key.fill" : "arrow.triangle.branch", tint: tint)
        }
        .settingAnchor(provider == .openAI ? "openAIKey" : "typeSafeKey")
        if !ai.decisionKeys.contains(provider) {
            HStack(spacing: 8) {
                SecureField(provider.title, text: Binding(
                    get: { decisionDrafts[provider] ?? "" },
                    set: { decisionDrafts[provider] = $0 }
                ), prompt: Text(provider.keyPrompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveDecisionKey(provider) }
                Button("Save") { saveDecisionKey(provider) }
                    .disabled((decisionDrafts[provider] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var subscriptionControl: some View {
        switch ai.claudeStatus {
        case nil:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Button("Install Claude Code…") {
                NSWorkspace.shared.open(URL(string: "https://claude.com/claude-code")!)
            }
        case .signedOut:
            Button("Sign In…") { ai.signIn() }
        case .signedIn(let plan):
            StatusPill(text: plan.map { "Connected · \($0.capitalized)" } ?? "Connected", tint: .green)
        }
    }

    @ViewBuilder
    private var codexControl: some View {
        switch ai.codexStatus {
        case nil:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Button("Install Codex…") {
                NSWorkspace.shared.open(URL(string: "https://learn.chatgpt.com/docs/codex/cli")!)
            }
        case .signedOut:
            Button("Sign In…") { ai.signInToChatGPT() }
        case .signedIn(let apiKey):
            StatusPill(text: apiKey ? "Connected · API key" : "Connected · ChatGPT", tint: .green)
        }
    }

    // MARK: - What the footers say

    /// A key that could not be saved (red), else `text`.
    @ViewBuilder
    private func footer(_ text: String, errors accounts: [Account]) -> some View {
        if let message = accounts.lazy.compactMap(error(for:)).first {
            Text(message).foregroundStyle(.red)
        } else {
            Text(text)
        }
    }

    /// Why the last key typed for `account` was not saved.
    private func error(for account: Account) -> String? {
        switch account {
        case .claudeKey: keyError
        case .openAI: decisionError.flatMap { $0.provider == .openAI ? $0.message : nil }
        case .typeSafe: decisionError.flatMap { $0.provider == .typeSafe ? $0.message : nil }
        case .claudeSubscription, .chatGPT: nil
        }
    }

    /// What writes now and how a command picks another; while the account
    /// is not ready, how to make it so.
    private var writingFooter: String {
        let choice = preferences.writingModel
        var text = "Ask and every command write with this; a command can pick its own in Commands."
        if case .unavailable(let why, _) = ai.availability(choice.provider) {
            // Said here, beside the rows that fix it: not "go to SI Accounts".
            text += " \(choice.provider.title) can’t write yet: \(why.prefix(1).lowercased() + why.dropFirst()). \(missingStep)"
        } else if choice.provider == .claude, let active = ai.activeEngine {
            text += active == .subscription ? " Now through your Claude subscription." : " Now through your Claude API key."
        }
        return text
    }

    /// What to do in the rows above for the default model to write.
    private var missingStep: String {
        let signIn = "Sign In opens its own sign-in in Terminal and your browser; come back here when it’s done."
        switch preferences.writingModel.provider {
        case .claude:
            if claudeAccounts == [.claudeKey] { return "Paste a key above." }
            if case .notInstalled? = ai.claudeStatus {
                return claudeAccounts.contains(.claudeKey) ? "Install Claude Code and sign in, or paste a key." : "Install Claude Code, then sign in."
            }
            return claudeAccounts.contains(.claudeKey) ? "Sign in, or paste a key. " + signIn : signIn
        case .chatGPT:
            if case .notInstalled? = ai.codexStatus { return "Install Codex, then sign in." }
            return signIn
        case .openAI:
            return "Paste a key above."
        }
    }

    private var decidingFooter: String {
        let what = "Chooses in a split second: the way Ask goes, the item to click, a file or a copy by meaning."
        return ai.decisionKeys.isEmpty ? what + " Optional: without a key, Claude Code decides, more slowly." : what
    }

    /// Under Advanced: where keys live and who chooses first.
    static let keysNote = "Keys stay in your Keychain on this Mac and are never shown again; create them at console.anthropic.com, "
        + "platform.openai.com or typesafe.ai. TypeSafe Jev chooses first, else the OpenAI key. skil.li runs your own Claude Code "
        + "and Codex with their own sign-in: it never sees your password or tokens. Codex starts for each answer, about 3 s."

    private func saveDecisionKey(_ provider: DecisionProvider) {
        do {
            try ai.saveDecisionKey(decisionDrafts[provider] ?? "", for: provider)
            decisionDrafts[provider] = nil
            decisionError = nil
        } catch {
            decisionError = (provider, error.localizedDescription)
        }
    }

    private func saveKey() {
        do {
            try ai.saveAPIKey(keyDraft)
            keyDraft = ""
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }
}

/// Title, one line of detail and a tinted icon tile, like System Settings rows.
struct RowLabel: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            IconTile(symbol: symbol, tint: tint, size: 22)
        }
    }
}

/// One real request on a sample sentence: the answer and how fast it came.
private struct TestRow: View {
    let result: AIStore.TestResult?
    /// Who answers: "Claude", "ChatGPT".
    var name = "Claude"
    let run: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                switch result {
                case nil:
                    Text("Fixes a sample sentence to check that it works.")
                        .foregroundStyle(.secondary)
                case .running:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Asking \(name)…").foregroundStyle(.secondary)
                    }
                case .passed(let text, let firstWord, let total):
                    VStack(alignment: .leading, spacing: 2) {
                        Label("“\(text)”", systemImage: "checkmark.circle.fill")
                            .labelStyle(TintedIconLabelStyle(tint: .green))
                        Text("First word in \(Self.seconds(firstWord)), done in \(Self.seconds(total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(TintedIconLabelStyle(tint: .orange))
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Test", action: run)
                .disabled(result == .running)
        }
    }

    private static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.1f s", value)
    }
}

/// One real decision on a sample request: the pick, how sure, how fast.
private struct DecisionTestRow: View {
    let result: AIStore.DecisionTest?
    let run: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                switch result {
                case nil:
                    Text("Picks the action for “\(DecisionQuestion.sampleInput)” to check that it works.")
                        .foregroundStyle(.secondary)
                case .running:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Choosing…").foregroundStyle(.secondary)
                    }
                case .passed(let answer, let latency):
                    VStack(alignment: .leading, spacing: 2) {
                        Label("→ \(answer.choice)", systemImage: "checkmark.circle.fill")
                            .labelStyle(TintedIconLabelStyle(tint: .green))
                        Text("\(Int((answer.confidence * 100).rounded())) % confident, in \(String(format: "%.2f s", Double(latency.components.seconds) + Double(latency.components.attoseconds) / 1e18))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(TintedIconLabelStyle(tint: .orange))
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Test", action: run)
                .disabled(result == .running)
        }
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
