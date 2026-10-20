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

    /// Returns `true` to swallow the event.
    fileprivate func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
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
