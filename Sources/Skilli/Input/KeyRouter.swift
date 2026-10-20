import AppKit
import Carbon.HIToolbox
import SkilliCore

/// Turns raw key events into Hyper state, chords, and binding outcomes.
///
/// Swallowed key-downs remember their key code so the matching key-up (and
/// any auto-repeat) is swallowed too; apps never see half a key press.
@MainActor
final class KeyRouter {
    typealias ActionHandler = @MainActor (SkilliAction, ContinuousClock.Instant) -> Void

    private var engine: BindingEngine<SkilliAction>
    private var hyper = HyperKeyMachine()
    private let triggerKeyCodes: Set<CGKeyCode>
    private let layout: KeyboardLayout
    private let overlay: LeaderOverlay
    private let onAction: ActionHandler
    private var swallowedKeyCodes: Set<CGKeyCode> = []
    private var expiryTimer: Timer?
    private lazy var tap = EventTap { [unowned self] type, event in
        self.handle(type, event)
    }

    init(
        engine: BindingEngine<SkilliAction>,
        triggerKeyCodes: Set<CGKeyCode>,
        layout: KeyboardLayout,
        overlay: LeaderOverlay,
        onAction: @escaping ActionHandler
    ) {
        self.engine = engine
        self.triggerKeyCodes = triggerKeyCodes
        self.layout = layout
        self.overlay = overlay
        self.onAction = onAction
    }

    func start() -> Bool {
        tap.start()
    }

    var isRunning: Bool {
        tap.isRunning
    }

    /// Trigger keys our tap has actually seen. When another Hyper tool's tap
    /// runs first (Raycast), the trigger never reaches us and Hyper arrives
    /// as ⌘⌃⌥⇧ flags instead; tap-for-Escape is then that tool's job.
    private var seenTriggers: Set<CGKeyCode> = []

    func receivesTrigger(_ keyCode: CGKeyCode) -> Bool {
        seenTriggers.contains(keyCode)
    }

    /// Tap the Hyper trigger alone to send Escape (Settings → Keys).
    var tapSendsEscape = true

    /// Our Hyper trigger pressed (true) or released (false; `tapped` when
    /// alone, which sends Escape): the welcome's live Hyper Key step.
    var onHyperChange: ((_ held: Bool, _ tapped: Bool) -> Void)?

    /// While Settings records a shortcut, every key goes to the recorder
    /// (Hyper applied) instead of the bindings, so existing shortcuts — ours
    /// or other apps' global hotkeys — can be typed and re-recorded.
    var isRecording = false {
        didSet { if isRecording { engine.cancel(); endSequence() } }
    }
    var recordHandler: ((CGEvent) -> Bool)?

    /// Swaps in bindings edited in Settings.
    func replaceEngine(_ engine: BindingEngine<SkilliAction>) {
        self.engine = engine
        endSequence()
    }

    /// Hands a key event to the launcher; returns `false` when it is hidden.
    ///
    /// While the launcher is visible every unbound key goes to it through
    /// here. The launcher opens from a hotkey our tap consumed, so macOS
    /// never sees skil.li receive input and may keep keyboard focus on the
    /// previous app; typing must not depend on that.
    var forwardToLauncher: ((CGEvent) -> Bool)?

    /// Keys for the AI card while it is up (Return, Esc, ⌘C, answers to its
    /// questions); `true` when used. Runs before the bindings, which then
    /// see every other key.
    var interceptForAI: ((Key?, Modifiers, CGKeyCode, CGEvent) -> Bool)?

    /// A held key the AI card took repeating (← or ⌫ held in its answer
    /// line): `true` when it used it. The repeat is swallowed either way.
    var repeatForAI: ((CGEvent) -> Bool)?

    /// Keys going on to the app in front, typed without Hyper: snippets
    /// watch them for their keywords. True holds the key back (↩ that
    /// ends a keyword: a chat would send it first).
    var onTypedKey: ((CGEvent) -> Bool)?

    /// While Secure Input is on (a password field, a terminal's Secure
    /// Keyboard Entry) the tap sees no key at all, so the trigger's release
    /// can be missed and Hyper would stay held. Watched while Hyper is
    /// held: once Secure Input has been on, Hyper is released when it ends
    /// (pressing the trigger again holds it again). The self-test swaps it.
    var secureInputEnabled: () -> Bool = { IsSecureEventInputEnabled() }
    private var secureWatch: Timer?
    private var secureInputSeen = false

    private func handle(_ type: CGEventType, _ event: CGEvent) -> EventTap.Verdict {
        let now = ContinuousClock.now
        let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            return keyDown(keyCode, event, now)
        case .keyUp:
            return keyUp(keyCode, event, now)
        default:
            return .pass
        }
    }

    private func keyDown(_ keyCode: CGKeyCode, _ event: CGEvent, _ now: ContinuousClock.Instant) -> EventTap.Verdict {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if triggerKeyCodes.contains(keyCode) {
            seenTriggers.insert(keyCode)
            if !isRepeat {
                hyper.triggerDown(at: now)
                watchSecureInput()
                onHyperChange?(true, false)
            }
            return .swallow
        }
        hyper.noteKeyWhileHeld()

        if isRecording {
            if hyper.isHeld { event.flags.formUnion(.hyper) }
            if recordHandler?(event) == true {
                swallowedKeyCodes.insert(keyCode)
                return .swallow
            }
            return .pass
        }

        if isRepeat {
            if swallowedKeyCodes.contains(keyCode) || engine.isPending {
                if !engine.isPending { _ = repeatForAI?(event) }
                return .swallow
            }
            // Held keys repeat in the launcher (⌫ held), not in the app behind it.
            if forwardToLauncher?(event) == true { return .swallow }
            if !hyper.isHeld, onTypedKey?(event) == true { return .swallow }
            return passWithHyper(event)
        }
        // A fresh press means any earlier swallowed press of this key is over,
        // even if its key-up never reached us (tap briefly disabled).
        swallowedKeyCodes.remove(keyCode)

        var modifiers = Modifiers(event.flags)
        if hyper.isHeld { modifiers.formUnion(.hyper) }
        // Inside a sequence the engine drops what is still held from its
        // first chord (`Chord.inChain`): ✦K then ✦U is ✦K then U, ⌘Space
        // then ⌘Space is ⌘Space then Space.

        if !engine.isPending, interceptForAI?(layout.key(for: keyCode), modifiers, keyCode, event) == true {
            swallowedKeyCodes.insert(keyCode)
            return .swallow
        }

        guard let key = layout.key(for: keyCode) else {
            // A key bindings cannot name (F5, media keys…) ends a sequence.
            if engine.isPending {
                engine.cancel()
                swallowedKeyCodes.insert(keyCode)
                endSequence()
                return .swallow
            }
            if !hyper.isHeld, onTypedKey?(event) == true {
                swallowedKeyCodes.insert(keyCode)
                return .swallow
            }
            return passWithHyper(event)
        }

        switch engine.handle(Chord(key, modifiers), at: now) {
        case .passThrough:
            if forwardToLauncher?(event) == true { return .swallow }
            if !hyper.isHeld, onTypedKey?(event) == true {
                swallowedKeyCodes.insert(keyCode)
                return .swallow
            }
            return passWithHyper(event)
        case .fire(let action):
            swallowedKeyCodes.insert(keyCode)
            endSequence()
            if action.runsInline {
                onAction(action, now)
            } else {
                // Leave the tap callback first; actions may take a while.
                Task { @MainActor [onAction] in
                    onAction(action, now)
                }
            }
            return .swallow
        case .pending(let prefix, let title, let hints):
            swallowedKeyCodes.insert(keyCode)
            overlay.show(prefix: prefix, title: title, hints: hints.map(LeaderOverlay.Row.init))
            scheduleExpiry()
            return .swallow
        case .cancelled:
            swallowedKeyCodes.insert(keyCode)
            endSequence()
            return .swallow
        }
    }

    private func keyUp(_ keyCode: CGKeyCode, _ event: CGEvent, _ now: ContinuousClock.Instant) -> EventTap.Verdict {
        if triggerKeyCodes.contains(keyCode) {
            stopWatchingSecureInput()
            let tapped = hyper.triggerUp(at: now)
            onHyperChange?(false, tapped)
            if tapped {
                if engine.isPending {
                    // Tapping Hyper is the natural "never mind" mid-sequence.
                    engine.cancel()
                    endSequence()
                } else if tapSendsEscape {
                    Task { @MainActor in
                        SyntheticKeys.press(CGKeyCode(kVK_Escape))
                    }
                }
            }
            return .swallow
        }
        if swallowedKeyCodes.remove(keyCode) != nil {
            return .swallow
        }
        if isRecording {
            return passWithHyper(event)
        }
        if forwardToLauncher?(event) == true { return .swallow }
        return passWithHyper(event)
    }

    /// Unbound keys pressed with our Hyper still reach apps as ⌘⌃⌥⇧+key, so
    /// Hyper shortcuts defined in other apps keep working.
    private func passWithHyper(_ event: CGEvent) -> EventTap.Verdict {
        if hyper.isHeld {
            event.flags.formUnion(.hyper)
        }
        return .pass
    }

    private func watchSecureInput() {
        stopWatchingSecureInput()
        secureWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSecureInput() }
        }
    }

    private func stopWatchingSecureInput() {
        secureWatch?.invalidate()
        secureWatch = nil
        secureInputSeen = false
    }

    private func checkSecureInput() {
        guard hyper.isHeld else { return stopWatchingSecureInput() }
        if secureInputEnabled() {
            secureInputSeen = true
        } else if secureInputSeen {
            hyper.release()
            stopWatchingSecureInput()
            onHyperChange?(false, false)
            Log.input.notice("Hyper released: Secure Input may have hidden the trigger's release")
        }
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: engine.timeout.milliseconds / 1_000, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.engine.expireIfNeeded(at: .now) {
                    self.overlay.hide()
                }
            }
        }
    }

    private func endSequence() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        overlay.hide()
    }
}
