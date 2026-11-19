import AppKit
import Carbon.HIToolbox
import SkilliCore

/// Only the launcher's direct shortcuts, only while Secure Input hides keys
/// from the session tap. The normal router keeps sequences and remapping.
/// macOS reports these specific hotkeys without exposing password typing.
@MainActor
final class SecureInputHotKeys {
    private struct HotKey: Hashable {
        let code: CGKeyCode
        let modifiers: UInt32
    }

    private enum Role { case launcher, trigger }
    private struct Registration {
        let id: UInt32
        let reference: EventHotKeyRef
        let role: Role
    }

    private static let signature: OSType = 0x536B5369
    private let layout: KeyboardLayout
    private let triggers: Set<CGKeyCode>
    private let onLauncher: (CGKeyCode) -> Void
    private let onHyper: (Bool) -> Void
    private let hyperIsHeld: () -> Bool
    private var chords: [Chord] = []
    private var handler: EventHandlerRef?
    private var timer: Timer?
    private var registrations: [HotKey: Registration] = [:]
    private var failed: Set<HotKey> = []
    private var pressed: Set<UInt32> = []
    private var nextID: UInt32 = 0
    private var secure = false
    private var held = false

    var isRecording = false { didSet { refresh() } }

    init(layout: KeyboardLayout, triggers: Set<CGKeyCode>, hyperIsHeld: @escaping () -> Bool,
         onHyper: @escaping (Bool) -> Void, onLauncher: @escaping (CGKeyCode) -> Void) {
        self.layout = layout
        self.triggers = triggers
        self.hyperIsHeld = hyperIsHeld
        self.onHyper = onHyper
        self.onLauncher = onLauncher
    }

    func start() {
        guard handler == nil else { return }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let status = InstallEventHandler(GetApplicationEventTarget(), skilliSecureHotKeyCallback, types.count, &types,
                                        Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            Log.input.error("Secure Input hotkey handler failed: \(status)")
            return
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.025
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        clear()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    func replaceChords(_ chords: [Chord]) {
        self.chords = chords
        failed.removeAll()
        refresh()
    }

    /// The tap has received a new trigger event after Secure Input ended.
    /// Its press now belongs to the tap, not the fallback's earlier hold.
    func triggerReturnedToTap() -> Bool {
        let earlierHold = held
        held = false
        refresh()
        return earlierHold
    }

    private func clear() {
        for value in registrations.values { UnregisterEventHotKey(value.reference) }
        registrations.removeAll()
        failed.removeAll()
        pressed.removeAll()
        secure = false
        if held { held = false; onHyper(false) }
    }

    /// There is no public notification for Secure Input. Outside it this
    /// reads just the flag; layout resolution and registration happen inside.
    private func refresh() {
        guard handler != nil, !isRecording, IsSecureEventInputEnabled() else {
            if secure { clear() }
            return
        }
        if !secure {
            secure = true
            held = hyperIsHeld()
        }
        var wanted: [HotKey: Role] = [:]
        for chord in chords {
            guard let code = layout.keyCode(for: chord.key) else { continue }
            wanted[HotKey(code: code, modifiers: Self.carbon(chord.modifiers))] = .launcher
            if chord.modifiers == .hyper {
                for trigger in triggers { wanted[HotKey(code: trigger, modifiers: 0)] = .trigger }
                // The tap cannot turn our F-key into modifier flags here.
                // Reserve only the configured launcher key, only while held.
                if held { wanted[HotKey(code: code, modifiers: 0)] = .launcher }
            }
        }
        // A held launcher key still owns its repeats and release after
        // Hyper is let go. Do not return half a key press to the field.
        for (key, value) in registrations where value.role == .launcher && pressed.contains(value.id) {
            wanted[key] = .launcher
        }
        for (key, value) in registrations where wanted[key] == nil {
            UnregisterEventHotKey(value.reference)
            pressed.remove(value.id)
            registrations.removeValue(forKey: key)
        }
        failed = failed.intersection(wanted.keys)
        for (key, role) in wanted where registrations[key] == nil && !failed.contains(key) {
            nextID &+= 1
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key.code), key.modifiers,
                                            EventHotKeyID(signature: Self.signature, id: nextID),
                                            GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registrations[key] = Registration(id: nextID, reference: reference, role: role)
            } else {
                failed.insert(key)
                Log.input.error("Secure Input launcher hotkey registration failed: \(status)")
            }
        }
    }

    fileprivate func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
              id.signature == Self.signature,
              let entry = registrations.first(where: { $0.value.id == id.id }) else { return OSStatus(eventNotHandledErr) }
        let registration = entry.value
        let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        if down {
            guard pressed.insert(id.id).inserted else { return noErr }
        } else {
            pressed.remove(id.id)
        }
        switch registration.role {
        case .trigger:
            held = down
            onHyper(down)
            refresh()
        case .launcher:
            if down { onLauncher(entry.key.code) } else { refresh() }
        }
        return noErr
    }

    private static func carbon(_ modifiers: Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

private func skilliSecureHotKeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    let hotKeys = Unmanaged<SecureInputHotKeys>.fromOpaque(context).takeUnretainedValue()
    // Application event handlers run on the main event loop.
    nonisolated(unsafe) let mainEvent = event
    return MainActor.assumeIsolated {
        hotKeys.handle(mainEvent)
    }
}
