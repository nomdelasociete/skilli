import CoreGraphics
import SkilliCore

/// Session-level keyboard event tap on the main run loop.
///
/// The callback runs for every key press system-wide, so the handler must stay
/// tiny: decide, maybe edit flags, return. Anything slower is dispatched.
/// macOS disables taps whose callbacks are slow; we re-enable on the spot.
@MainActor
final class EventTap {
    enum Verdict {
        case pass
        case swallow
    }

    typealias Handler = @MainActor (CGEventType, CGEvent) -> Verdict

    private let handler: Handler
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Made and not stopped, running or disabled by macOS.
    var isInstalled: Bool { port != nil }

    /// How many times macOS disabled the tap because skil.li answered too
    /// late (the main thread busy): the key in flight then went past it.
    private(set) var timeouts = 0

    /// Accessibility gone while the tap runs (a tap-disabled event and no
    /// permission behind it): the owner stops it and says so.
    var onAccessLost: (() -> Void)?

    /// Whether macOS lets skil.li tap the keyboard now: a tap made and
    /// dropped at once, listening to nothing. WindowServer asks tccd each
    /// time, so the answer is current; `AXIsProcessTrusted` answers from an
    /// in-process cache that can keep the old value after a change (AltTab,
    /// measured on macOS 27). Without Accessibility it is nil (checked over
    /// SSH, 2026-11-04).
    static func isPermitted() -> Bool {
        guard let probe = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: 0,
            callback: skilliProbeCallback,
            userInfo: nil
        ) else { return false }
        CGEvent.tapEnable(tap: probe, enable: false)
        CFMachPortInvalidate(probe)
        return true
    }

    /// Returns `false` until the user grants Accessibility.
    func start() -> Bool {
        if port != nil { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: skilliEventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    /// Removed from the run loop and invalidated: a tap left in place after
    /// Accessibility is gone can hang every app's keyboard and mouse
    /// (Apple Developer Forums 844416, macOS 15 to 27).
    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    /// Returns `true` to swallow the event.
    fileprivate func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Without Accessibility macOS keeps disabling it: re-enabled only
            // while the permission is there, else stopped, out of the callback.
            guard Self.isPermitted() else {
                Log.input.error("Event tap was disabled (\(type.rawValue)) and Accessibility is gone")
                DispatchQueue.main.async { [weak self] in self?.onAccessLost?() }
                return false
            }
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            if type == .tapDisabledByTimeout { timeouts += 1 }
            Log.input.error("Event tap was disabled (\(type.rawValue)); re-enabled")
            return false
        default:
            break
        }

        // Our own synthetic ⌘C / ⌘V / Escape must reach the target app as-is.
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticKeys.marker {
            return false
        }
        return handler(type, event) == .swallow
    }
}

private func skilliEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    nonisolated(unsafe) let event = event
    let swallow = MainActor.assumeIsolated {
        tap.process(type, event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// The permission probe's: it listens to nothing and is dropped at once.
private func skilliProbeCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    Unmanaged.passUnretained(event)
}

extension Modifiers {
    init(_ flags: CGEventFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        self = modifiers
    }
}

extension CGEventFlags {
    static let hyper: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
}
