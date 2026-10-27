import AppKit
import Observation
import SkilliCore

/// Who writes for AI actions: Claude (the subscription through the user's
/// `claude` binary, or an API key, chosen by `Preferences.aiEngineMode`),
/// ChatGPT (the user's own `codex`), or the OpenAI API (the key kept for
/// Decisions). Owns the engines, the spare process, the model lists, and
/// what Settings shows about them.
@MainActor
@Observable
final class AIStore {
    enum Engine: Sendable {
        case subscription
        case apiKey
        case codex
        case openAI
    }

    enum TestResult: Equatable {
        case running
        case passed(text: String, firstWord: Duration, total: Duration)
        case failed(String)
    }

    /// Whether a provider can write now; `unavailable` says why ("Not
    /// signed in") and how ("run codex login in a terminal").
    enum Availability: Equatable {
        case checking
        case ready
        case unavailable(why: String, how: String)

        /// "Not signed in: run codex login in a terminal".
        var line: String? {
            if case .unavailable(let why, let how) = self { return "\(why): \(how)" }
            return nil
        }
    }

    /// The engine and model a request goes to.
    struct Writer {
        let engine: TextEngine
        let choice: ModelChoice
        /// "Claude · Haiku", "ChatGPT · GPT-6 Luna Low"; "Claude API · …"
        /// on the API key.
        let label: String
        /// The command's own choice that could not write now ("ChatGPT is
        /// not signed in"), when the default stood in for it.
        var note: String?
    }

    /// nil while checking.
    private(set) var claudeStatus: ClaudeCLI.Status?
    private(set) var claudeBinary: URL?
    private(set) var hasAPIKey: Bool
    private(set) var tests: [Engine: TestResult] = [:]
    /// nil while checking.
    private(set) var codexStatus: CodexCLI.Status?
    private(set) var codexBinary: URL?
    /// What Codex lists for the user's plan, newest of each family.
    private(set) var codexModels = ModelCatalog.verified
    /// What the OpenAI key may use, newest of each family.
    private(set) var openAIModels = ModelCatalog.verified

    enum DecisionTest: Equatable {
        case running
        case passed(DecisionResult, latency: Duration)
        case failed(String)
    }

    /// Decision providers with a key saved.
    private(set) var decisionKeys: Set<DecisionProvider> = []
    private(set) var decisionTests: [DecisionProvider: DecisionTest] = [:]

    @ObservationIgnored let subscription = ClaudeSubscriptionEngine()
    @ObservationIgnored let codex = CodexEngine()
    /// Self-test hook: replaces every writer for AI actions (no tokens).
    @ObservationIgnored var testEngine: TextEngine?
    /// Self-test hook: what the card says writes, while `testEngine` does.
    @ObservationIgnored var testEngineLabel = "Test"
    @ObservationIgnored private(set) var api: ClaudeAPIEngine!
    @ObservationIgnored private(set) var openAI: OpenAIEngine!
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let keyAccount: String
    @ObservationIgnored private let decisionKeyPrefix: String
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// When the OpenAI list was last read: at most once an hour.
    @ObservationIgnored private var openAIModelsRead: ContinuousClock.Instant?
    /// The Codex whose models were read: again only for another one (an
    /// update moves Homebrew's binary).
    @ObservationIgnored private var codexRead: URL?

    static let apiKeyAccount = "anthropic-api-key"

    /// `keyAccount` names the Claude key's Keychain item and
    /// `decisionKeyPrefix` prefixes the decision keys' items (the OpenAI
    /// one also writes); the self-test uses its own.
    init(preferences: Preferences, keyAccount: String = AIStore.apiKeyAccount, decisionKeyPrefix: String = "") {
        self.preferences = preferences
        self.keyAccount = keyAccount
        self.decisionKeyPrefix = decisionKeyPrefix
        hasAPIKey = Keychain.read(account: keyAccount) != nil
        decisionKeys = Set(DecisionProvider.allCases.filter { Keychain.read(account: decisionKeyPrefix + $0.keychainAccount) != nil })
        api = ClaudeAPIEngine { [keyAccount] in Keychain.read(account: keyAccount) }
        openAI = OpenAIEngine { [decisionKeyPrefix] in Keychain.read(account: decisionKeyPrefix + DecisionProvider.openAI.keychainAccount) }
        observeSleep()
    }

    /// What Ask and commands write with unless a command picks its own.
    var defaultModel: ModelChoice { preferences.writingModel }

    /// Claude's model where only Claude can run (Act commands, the spare):
    /// the default's when it is Claude, else Haiku.
    var claudeModel: AIModel { AIModel(choice: preferences.writingModel) ?? .haiku }

    /// Speech language for Ask by Voice; empty follows the keyboard.
    var voiceLanguage: String { preferences.voiceLanguage }

    var isSignedIn: Bool {
        if case .signedIn = claudeStatus { return true }
        return false
    }

    var hasOpenAIKey: Bool { decisionKeys.contains(.openAI) }

    /// The Claude engine the user's choice resolves to right now.
    var activeEngine: Engine? {
        switch preferences.aiEngineMode {
        case .subscription: isSignedIn ? .subscription : nil
        case .apiKey: hasAPIKey ? .apiKey : nil
        case .auto: isSignedIn ? .subscription : (hasAPIKey ? .apiKey : nil)
        }
    }

    func engine(_ engine: Engine) -> TextEngine {
        switch engine {
        case .subscription: subscription
        case .apiKey: api
        case .codex: codex
        case .openAI: openAI
        }
    }

    // MARK: - Writers

    func availability(_ provider: WritingProvider) -> Availability {
        switch provider {
        case .claude:
            if activeEngine != nil { return .ready }
            if claudeStatus == nil, !hasAPIKey { return .checking }
            return preferences.aiEngineMode == .apiKey
                ? .unavailable(why: "No API key", how: "add one in Settings → SI Accounts")
                : .unavailable(why: "Not set up", how: "sign in to Claude Code in Settings → SI Accounts")
        case .chatGPT:
            switch codexStatus {
            case nil: return codexBinary == nil ? .checking : .ready
            case .signedIn: return .ready
            case .signedOut: return .unavailable(why: "Not signed in", how: "run codex login in a terminal")
            case .notInstalled: return .unavailable(why: "Codex is not installed", how: "install it, then run codex login")
            }
        case .openAI:
            return hasOpenAIKey ? .ready : .unavailable(why: "No key", how: "add one in Settings → SI Accounts")
        }
    }

    /// The models offered for `provider`, newest first.
    func models(_ provider: WritingProvider) -> [ModelOffer] {
        switch provider {
        case .claude: ModelCatalog.claude
        case .chatGPT: codexModels
        case .openAI: openAIModels
        }
    }

    /// Who writes `choice` (nil: the default). A command's own choice that
    /// cannot write now gives way to the default, said in `note`; nil when
    /// nothing can write.
    func writer(for choice: ModelChoice?) -> Writer? {
        let wanted = choice ?? defaultModel
        if let testEngine { return Writer(engine: testEngine, choice: wanted, label: testEngineLabel) }
        if let writer = ready(wanted) { return writer }
        guard choice != nil, var writer = ready(defaultModel) else { return nil }
        if case .unavailable(let why, _) = availability(wanted.provider) {
            writer.note = "\(wanted.provider.title): \(why.lowercased())"
        }
        return writer
    }

    /// What the card says when nothing can write `choice` (nil: the
    /// default).
    func setupMessage(for choice: ModelChoice?) -> String {
        let provider = (choice ?? defaultModel).provider
        guard provider != .claude, let line = availability(provider).line else { return "Claude is not set up yet." }
        return "\(provider.title) can’t write yet. \(line)."
    }

    private func ready(_ choice: ModelChoice) -> Writer? {
        // Statuses not read yet (a self-test, the first second after launch):
        // a found binary is tried; its own error says what is wrong.
        guard availability(choice.provider) == .ready || (choice.provider == .chatGPT && codexStatus == nil) else { return nil }
        switch choice.provider {
        case .claude:
            guard let active = activeEngine, let model = AIModel(choice: choice) else { return nil }
            return Writer(engine: engine(active), choice: choice,
                          label: (active == .apiKey ? "Claude API · " : "Claude · ") + model.title)
        case .chatGPT:
            guard codexBinary != nil || codexStatus == nil else { return nil }
            return Writer(engine: codex, choice: choice, label: choice.label)
        case .openAI:
            return Writer(engine: openAI, choice: choice, label: choice.label)
        }
    }

    // MARK: - Subscription

    /// Keeps the last known status while checking, so Settings never
    /// flickers back to a spinner. Claude and Codex are asked side by side.
    func refresh() async {
        async let codexCheck: Void = refreshCodex()
        async let openAICheck: Void = refreshOpenAIModels()
        let binary = await ClaudeCLI.locate()
        claudeBinary = binary
        claudeStatus = if let binary { await ClaudeCLI.status(binary: binary) } else { .notInstalled }
        apply()
        _ = await (codexCheck, openAICheck)
    }

    func signIn() {
        guard let claudeBinary else { return }
        try? ClaudeCLI.openSignIn(binary: claudeBinary)
    }

    // MARK: - ChatGPT

    /// Codex's status, and once per binary its models for the user's plan.
    func refreshCodex() async {
        let binary = await CodexCLI.locate()
        codexBinary = binary
        codex.binary = binary
        guard let binary else {
            codexStatus = .notInstalled
            return
        }
        let status = await CodexCLI.status(binary: binary)
        codexStatus = status
        guard case .signedIn = status, codexRead != binary.resolvingSymlinksInPath() else { return }
        // Asked again next time if Codex could not say.
        guard let offers = await CodexCLI.models(binary: binary) else { return }
        codexModels = ModelCatalog.current(offers)
        codexRead = binary.resolvingSymlinksInPath()
    }

    func signInToChatGPT() {
        guard let codexBinary else { return }
        try? CodexCLI.openSignIn(binary: codexBinary)
    }

    /// `GET /v1/models` with the OpenAI key, at most once an hour.
    func refreshOpenAIModels(force: Bool = false) async {
        guard let key = decisionKey(for: .openAI) else { return }
        if !force, let read = openAIModelsRead, ContinuousClock.now - read < .seconds(3600) { return }
        openAIModelsRead = .now
        if let models = await OpenAIEngine.models(key: key) { openAIModels = ModelCatalog.current(models) }
    }

    // MARK: - API key

    func saveAPIKey(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        try Keychain.save(key, account: keyAccount)
        hasAPIKey = true
        tests[.apiKey] = nil
        apply()
    }

    /// Returns the key removed, kept in memory only while ⌘Z can save it
    /// again (`UndoableDeletes.apiKey`); never logged.
    @discardableResult
    func removeAPIKey() -> String? {
        let removed = Keychain.read(account: keyAccount)
        Keychain.delete(account: keyAccount)
        hasAPIKey = false
        tests[.apiKey] = nil
        apply()
        return removed
    }

    // MARK: - Decision keys

    func decisionKey(for provider: DecisionProvider) -> String? {
        Keychain.read(account: decisionKeyPrefix + provider.keychainAccount)
    }

    func saveDecisionKey(_ key: String, for provider: DecisionProvider) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        try Keychain.save(key, account: decisionKeyPrefix + provider.keychainAccount)
        decisionKeys.insert(provider)
        decisionTests[provider] = nil
        if provider == .openAI {
            tests[.openAI] = nil
            Task { await refreshOpenAIModels(force: true) }
        }
    }

    /// Returns the key removed, as `removeAPIKey` does.
    @discardableResult
    func removeDecisionKey(for provider: DecisionProvider) -> String? {
        let removed = decisionKey(for: provider)
        Keychain.delete(account: decisionKeyPrefix + provider.keychainAccount)
        decisionKeys.remove(provider)
        decisionTests[provider] = nil
        if provider == .openAI {
            tests[.openAI] = nil
            openAIModels = ModelCatalog.verified
            openAIModelsRead = nil
        }
        return removed
    }

    /// One real decision on `DecisionQuestion.sample`.
    @discardableResult
    func testDecision(_ provider: DecisionProvider) async -> DecisionTest {
        guard let key = decisionKey(for: provider) else {
            decisionTests[provider] = .failed("No key saved.")
            return .failed("No key saved.")
        }
        decisionTests[provider] = .running
        let start = ContinuousClock.now
        let result: DecisionTest
        do {
            let answer = try await DecisionClient.decide(.sample, input: DecisionQuestion.sampleInput, provider: provider, key: key)
            result = .passed(answer, latency: .now - start)
        } catch {
            result = .failed(error.localizedDescription)
            Log.actions.error("Decision test on \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        decisionTests[provider] = result
        return result
    }

    // MARK: - Test

    /// The model a Test button writes with: the default when it is this
    /// engine's provider, else its fastest.
    func testModel(_ engine: Engine) -> ModelChoice? {
        let provider: WritingProvider = switch engine {
        case .subscription, .apiKey: .claude
        case .codex: .chatGPT
        case .openAI: .openAI
        }
        if defaultModel.provider == provider { return defaultModel }
        if provider == .claude { return nil }
        let models = models(provider)
        return ModelChoice(provider: provider, model: (models.last { $0.id.contains("luna") } ?? models.last)?.id ?? "gpt-6-luna", effort: .low)
    }

    /// Runs `AIPrompt.sample` on `engine` and keeps the result for Settings.
    @discardableResult
    func test(_ engine: Engine) async -> TestResult {
        tests[engine] = .running
        let start = ContinuousClock.now
        var firstWord: Duration?
        var text = ""
        let result: TestResult
        var request = AIPrompt.sample
        request.model = testModel(engine)
        do {
            for try await chunk in self.engine(engine).stream(request) {
                firstWord = firstWord ?? .now - start
                text += chunk
            }
            let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
            result = answer.isEmpty
                ? .failed("\(engine == .codex ? "ChatGPT" : engine == .openAI ? "OpenAI" : "Claude") answered nothing.")
                : .passed(text: answer, firstWord: firstWord ?? .zero, total: .now - start)
        } catch {
            result = .failed(error.localizedDescription)
            Log.actions.error("AI test on \(String(describing: engine), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        tests[engine] = result
        return result
    }

    // MARK: - Preferences, spare

    /// Applies models and "Keep Claude ready"; called on every change.
    func apply() {
        subscription.model = claudeModel
        api.model = claudeModel
        if defaultModel.provider == .chatGPT { codex.model = defaultModel }
        if defaultModel.provider == .openAI { openAI.model = defaultModel }
        subscription.binary = isSignedIn ? claudeBinary : nil
        subscription.keepReady = preferences.keepClaudeReady && activeEngine == .subscription
    }

    /// No spare while the Mac sleeps or the screen is locked; a new one on
    /// return (its connection would be stale anyway).
    private func observeSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let drop: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.subscription.dropSpare() }
        }
        let restore: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.subscription.ensureSpare() }
        }
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: drop),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: restore),
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: drop),
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: restore)
        ]
    }
}
