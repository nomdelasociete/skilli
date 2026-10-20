import AppKit
import Observation
import SkilliCore

/// The welcome's state: which step shows, and what the person did in the
/// live ones (docs/onboarding.md). Every step is something they do: held
/// Caps Lock, opened the launcher, fixed a sentence. The app reports what
/// happened (`hyperChanged`, `launcherShown`, `launcherClosed`); the
/// practice field reports its text.
@MainActor
@Observable
final class WelcomeModel {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, accessibility, hyperKey, launcher, intelligence, practice, ready
        var id: Int { rawValue }
        /// Needs the key tap: shown only once Accessibility is on.
        var needsKeys: Bool { [.hyperKey, .launcher, .practice].contains(self) }
    }

    /// What Caps Lock does for this person (`HyperKeyRemapper.plan`).
    enum HyperKeyState: Equatable {
        /// skil.li maps Caps Lock: the live test.
        case own
        /// Another Hyper Key app maps it (Raycast): both work, live test too.
        case shared
        /// Custom key mappings: left alone, nothing to test.
        case custom
    }

    enum Practice: Equatable {
        /// The sentence as given, selected.
        case waiting
        /// Replaced by the command.
        case fixed(String)
        /// Brought back with ⌘Z: the whole idea, done.
        case undone
    }

    /// Invented, as all test and demo text in this public repository.
    static let practiceSentence = "i has wrote this sentense to quick, it need fixing"

    let permissions: PermissionCenter
    let ai: AIStore
    let preferences: Preferences
    let loginItem = LoginItem()

    private(set) var step: Step = .welcome
    /// +1 going forward, -1 back: which way the stage slides.
    private(set) var direction = 1
    var hyperKey: HyperKeyState = .own
    /// The keys each action has now, as keycaps per chord (`hyper+k g` →
    /// [["✦", "K"], ["G"]]); the defaults on a first launch.
    var keys: (SkilliAction) -> [[String]] = { _ in [] }

    /// The ways the welcome offers to open skil.li, recommended first (JB,
    /// 2026-10-19: "recommend ⌘Space, then Hyper Key Space or custom"):
    /// Spotlight's key, whose own shortcut skil.li then turns off
    /// (`SpotlightKey`), and the Hyper Key's; the person's own keys after.
    static let launcherChoices: [(spec: String, keys: [String], name: String)] = [
        ("cmd+space", ["⌘", "Space"], "Instead of Spotlight"),
        ("hyper+space", ["✦", "Space"], "With your Hyper Key")
    ]
    /// The app's shortcuts: the launcher's keys are changed, recorded and
    /// refused (macOS's own, another shortcut's) as in Settings → Keys.
    var shortcuts: ShortcutStore?
    private(set) var launcherError: String?

    /// The launcher's keys now (`Chord.spec`).
    var launcherKeys: String? { shortcuts?.launcherEntry?.keys }
    /// The launcher's keys as keycaps, chord by chord.
    var launcherKeycaps: [[String]] { shortcuts?.launcherEntry?.chords.map { $0.map(\.keycaps) } ?? [] }
    /// Recording the person's own keys for the launcher now.
    var recordsLauncher: Bool { shortcuts?.recordingID != nil && shortcuts?.recordingID == shortcuts?.launcherEntry?.id }

    private(set) var hyperHeld = false
    private(set) var hyperFelt = false
    private(set) var launcherOpen = false
    private(set) var launcherTried = false
    private(set) var practice: Practice = .waiting
    /// Start's "Open skil.li at login": on by default (manifesto 10, right
    /// by default), applied when the welcome ends.
    var openAtLogin = true
    /// The key typed in the SI step, before Verify.
    var pastedKey = ""
    private(set) var keyTest: AIStore.TestResult?
    /// The TypeSafe Jev key typed in the SI step's Chooses, before Verify.
    var pastedDecisionKey = ""
    private(set) var decisionTest: AIStore.DecisionTest?

    /// Shown, so the app tells it what the keys do.
    var isActive = false
    /// A done live step moves on by itself; the self-test's drawings keep
    /// it still.
    @ObservationIgnored var advancesByItself = true
    /// The welcome is done: the window closes.
    var onFinish: (() -> Void)?
    /// Asked to show the guide at System Settings' switch.
    var onGrantAccessibility: (() -> Void)?

    init(permissions: PermissionCenter, ai: AIStore, preferences: Preferences) {
        self.permissions = permissions
        self.ai = ai
        self.preferences = preferences
    }

    // MARK: - Steps

    var accessibilityOn: Bool { permissions.state(.accessibility) == .granted }

    /// Gone past the Accessibility step without it (Later).
    private(set) var leftWithoutAccessibility = false

    /// The steps for this person: once they went on without Accessibility,
    /// those that need the key tap are left out (docs/onboarding.md, step
    /// 2's Later); until then all seven show.
    var steps: [Step] {
        Step.allCases.filter { !$0.needsKeys || accessibilityOn || !leftWithoutAccessibility }
    }

    var position: Int { steps.firstIndex(of: step) ?? 0 }

    /// Opens on `step` (the menu bar's Set Up skil.li… opens on Accessibility).
    func start(at step: Step = .welcome) {
        self.step = step
        direction = 1
        leftWithoutAccessibility = false
        hyperFelt = false
        launcherTried = false
        practice = .waiting
        keyTest = nil
        pastedKey = ""
        decisionTest = nil
        pastedDecisionKey = ""
        loginItem.refresh()
        openAtLogin = loginItem.isEnabled || !preferences.didCompleteSetup
    }

    func next() {
        if step == .ready { return complete() }
        if step == .accessibility, !accessibilityOn, permissions.state(.accessibility) == .notAsked {
            // Continue asks macOS; the step waits for the switch.
            return grantAccessibility()
        }
        move(by: 1)
    }

    func back() {
        if let tapped = hyperTappedAt, ContinuousClock.now - tapped < .milliseconds(400) { return }
        guard position > 0 else { return finish() }
        move(by: -1)
    }

    /// Skip: on, without doing it.
    func skip() {
        move(by: 1)
    }

    private func move(by offset: Int) {
        if step == .accessibility, offset > 0, !accessibilityOn { leftWithoutAccessibility = true }
        let list = steps
        let index = min(max((list.firstIndex(of: step) ?? 0) + offset, 0), list.count - 1)
        direction = offset >= 0 ? 1 : -1
        step = list[index]
    }

    /// Start, on the last step: its choices apply, then it closes.
    func complete() {
        if openAtLogin != loginItem.isEnabled { loginItem.setEnabled(openAtLogin) }
        onFinish?()
    }

    /// Later, esc on the first step, ✕: closed, nothing changed.
    func finish() {
        onFinish?()
    }

    // MARK: - Accessibility

    func grantAccessibility() {
        permissions.grant(.accessibility)
        onGrantAccessibility?()
    }

    /// The switch turned on while the step shows: a beat to see it lock,
    /// then on by itself.
    func accessibilityChanged() {
        guard step == .accessibility, accessibilityOn, advancesByItself else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            if step == .accessibility { move(by: 1) }
        }
    }

    // MARK: - What the keys did

    /// When Caps Lock was last tapped alone: it sends Escape, which is the
    /// Hyper Key's, not the welcome's Back.
    @ObservationIgnored private var hyperTappedAt: ContinuousClock.Instant?

    func hyperChanged(held: Bool, tapped: Bool = false) {
        guard isActive else { return }
        hyperHeld = held
        if tapped { hyperTappedAt = .now }
        if held, step == .hyperKey { hyperFelt = true }
    }

    /// One of `launcherChoices` chosen: the launcher opens with it from now
    /// on, Settings → Keys says so; refused keys say why.
    func chooseLauncher(_ spec: String) {
        guard let shortcuts, let id = shortcuts.launcherEntry?.id else { return }
        shortcuts.cancelRecording()
        do {
            try shortcuts.setKeys(try Chord.sequence(spec), for: id)
            launcherError = nil
        } catch {
            launcherError = error.localizedDescription
        }
    }

    /// "Your own": the next keys pressed become the launcher's, or say why
    /// not (`ShortcutNote`).
    func recordLauncher() {
        guard let shortcuts, let id = shortcuts.launcherEntry?.id else { return }
        launcherError = nil
        shortcuts.beginRecording(id)
    }

    func launcherShown() {
        guard isActive else { return }
        launcherOpen = true
    }

    func launcherClosed() {
        guard isActive else { return }
        let wasOpen = launcherOpen
        launcherOpen = false
        guard wasOpen, step == .launcher else { return }
        launcherTried = true
        guard advancesByItself else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            if step == .launcher { move(by: 1) }
        }
    }

    /// The practice field's text after each change.
    func practiceText(_ text: String) {
        switch practice {
        case .waiting where text != Self.practiceSentence && !text.isEmpty:
            practice = .fixed(text)
        case .fixed where text == Self.practiceSentence:
            practice = .undone
        default:
            break
        }
    }

    /// Self-test hook: a live step drawn as if the keys had done it.
    func freeze(hyperHeld: Bool = false, hyperFelt: Bool = false, launcherOpen: Bool = false, launcherTried: Bool = false,
                practice: Practice = .waiting) {
        self.hyperHeld = hyperHeld
        self.hyperFelt = hyperFelt
        self.launcherOpen = launcherOpen
        self.launcherTried = launcherTried
        self.practice = practice
    }

    // MARK: - Your SI

    /// Someone can write now: Claude (subscription or key) or ChatGPT.
    var intelligenceReady: Bool {
        ai.availability(.claude) == .ready || ai.availability(.chatGPT) == .ready
    }

    /// Writes with the first provider ready when the chosen one cannot
    /// (only ChatGPT signed in: commands must not wait for Claude).
    func chooseReadyWriter() {
        guard ai.availability(preferences.writingModel.provider) != .ready else { return }
        if ai.availability(.claude) == .ready {
            preferences.writingModel = .standard
        } else if ai.availability(.chatGPT) == .ready, let offer = ai.models(.chatGPT).first {
            preferences.writingModel = ModelChoice(provider: .chatGPT, model: offer.id, effort: .low)
        }
    }

    /// Verify: saves the pasted Claude key and runs Settings' own test.
    func verifyKey() async {
        let key = pastedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyTest = .running
        do {
            try ai.saveAPIKey(key)
        } catch {
            keyTest = .failed(error.localizedDescription)
            return
        }
        keyTest = await ai.test(.apiKey)
        if case .passed = keyTest { chooseReadyWriter() }
    }

    /// A decision model can choose: TypeSafe Jev, or the OpenAI key. Without
    /// one, Do It Here stops, nothing is found by meaning, and Ask waits for
    /// Claude Code or Codex to choose (docs/onboarding.md, step 5).
    var choosingReady: Bool { chooser != nil }

    /// Who chooses: a saved key whose last test did not fail (a key pasted
    /// here counts once Verify passed; one saved before, as Settings has it).
    var chooser: DecisionProvider? {
        [DecisionProvider.typeSafe, .openAI].first { provider in
            guard ai.decisionKeys.contains(provider) else { return false }
            if case .failed? = ai.decisionTests[provider] { return false }
            if provider == .typeSafe, decisionTest != nil, !decisionPassed { return false }
            return true
        }
    }

    /// The key pasted here passed Verify.
    var decisionPassed: Bool {
        if case .passed? = decisionTest { return true }
        return false
    }

    /// Verify in Chooses: saves the pasted Jev key, then Settings' own test.
    func verifyDecisionKey() async {
        let key = pastedDecisionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        decisionTest = .running
        do {
            try ai.saveDecisionKey(key, for: .typeSafe)
        } catch {
            decisionTest = .failed(error.localizedDescription)
            return
        }
        decisionTest = await ai.testDecision(.typeSafe)
    }

    /// What the welcome set up, for its last step: each thing on, or
    /// missing and where it is set (docs/onboarding.md, step 7).
    struct SetUpItem: Identifiable {
        let id: String
        let title: String
        /// What it is now: "On", "⌘ Space", "Claude"; or what is missing.
        let state: String
        let done: Bool
        /// Where to set it when it is missing.
        let fix: String?
    }

    var setUp: [SetUpItem] {
        let writer: String? = ai.availability(preferences.writingModel.provider) == .ready ? preferences.writingModel.provider.title
            : intelligenceReady ? "Claude or ChatGPT" : nil
        let chooser: String? = switch self.chooser {
        case .typeSafe?: "TypeSafe Jev"
        case .openAI?: "OpenAI"
        case nil: nil
        }
        let launcher = launcherKeycaps.map { $0.joined(separator: " ") }.joined(separator: " › ")
        return [
            SetUpItem(id: "accessibility", title: "Accessibility", state: accessibilityOn ? "On" : "Off", done: accessibilityOn,
                      fix: accessibilityOn ? nil : "Menu bar → Set Up skil.li…"),
            SetUpItem(id: "hyper", title: "Hyper Key", state: hyperKey == .custom ? "Your own mapping" : "Caps Lock",
                      done: hyperKey != .custom, fix: hyperKey == .custom ? "Settings → Keys" : nil),
            SetUpItem(id: "launcher", title: "Open skil.li", state: launcher.isEmpty ? "No keys" : launcher, done: !launcher.isEmpty,
                      fix: launcher.isEmpty ? "Settings → Keys" : nil),
            SetUpItem(id: "writes", title: "\(Brand.intelligence) that writes", state: writer ?? "Not connected", done: writer != nil,
                      fix: writer == nil ? "Settings → SI Accounts" : nil),
            SetUpItem(id: "chooses", title: "\(Brand.intelligence) that chooses",
                      state: chooser ?? (decisionTest.map { if case .failed = $0 { "Key not working" } else { "No key" } } ?? "No key"),
                      done: chooser != nil,
                      fix: chooser == nil ? "Settings → SI Accounts" : nil)
        ]
    }

    /// The practice uses Fix Spelling & Grammar when someone can write,
    /// else UPPERCASE, which needs no SI.
    var practiceAction: SkilliAction {
        intelligenceReady ? .aiPrompt("fix") : .transformSelection(.uppercase)
    }
}
