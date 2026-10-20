import CoreGraphics

/// Posts key presses that look like the user's own (⌘C, ⌘V, Escape).
///
/// Events come from a private state source so physically held modifiers do
/// not leak into them, and carry `marker` so our own tap lets them through.
@MainActor
enum SyntheticKeys {
    /// "skilli" in ASCII.
    nonisolated static let marker: Int64 = 0x73_6B_69_6C_6C_69

    /// With `pid`, the event goes straight to that app's queue and skips every
    /// session event tap. A Hyper tool still tracking a held Caps Lock
    /// (Raycast's taps run before ours) would otherwise turn ⌘V into ✦V.
    static func press(_ code: CGKeyCode, flags: CGEventFlags = [], to pid: pid_t? = nil) {
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
