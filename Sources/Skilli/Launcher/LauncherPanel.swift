import AppKit
import SkilliCore

/// Borderless, non-activating panel: it takes keyboard focus without
/// activating skil.li, so the app the user was in stays frontmost — needed to
/// paste into it and to read its selection.
final class LauncherPanel: NSPanel {
    /// ⌘W, and the Open Settings key: the launcher closes.
    var onCancel: (() -> Void)?
    /// esc: one step back (`LauncherController.escape`).
    var onEscape: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var openSettingsChord: Chord?
    var resolveKey: ((UInt16) -> Key?)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        // Moved only by its own drag (`LauncherController.drag`), which
        // pulls it onto guides.
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        // No window shadow: macOS traces it from the glass views' rectangular
        // frames, not their rounded shapes, which draws a dark square outline
        // around the capsule and card. Liquid Glass renders its own edge.
        hasShadow = false
        // No fade: the panel must appear on the next frame.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        (onEscape ?? onCancel)?()
    }

    /// An accessory app has no Edit menu, so ⌘X/C/V/A/Z would do nothing in
    /// the search field. Route them to the first responder ourselves.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only the four modifiers matter: events can carry extra device bits.
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, let openSettingsChord, let key = resolveKey?(event.keyCode),
           Chord(key, Modifiers(flags)) == openSettingsChord {
            // Open before hiding, so Settings keeps the focus.
            onOpenSettings?()
            onCancel?()
            return true
        }
        if event.type == .keyDown, flags == .command, let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "w":
                onCancel?()
                return true
            default:
                break
            }
            let action: Selector? = switch characters {
            case "x": #selector(NSText.cut(_:))
            case "c": #selector(NSText.copy(_:))
            case "v": #selector(NSText.paste(_:))
            case "a": #selector(NSText.selectAll(_:))
            case "z": Selector(("undo:"))
            default: nil
            }
            // Straight to our first responder: the panel may not be the
            // app's key window when the launcher opened over another app.
            if let action, let responder = firstResponder, responder.tryToPerform(action, with: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
