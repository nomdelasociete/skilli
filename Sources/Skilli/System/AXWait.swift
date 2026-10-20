import ApplicationServices
import Foundation

/// Waits on another app through Accessibility notifications (a window
/// created, moved, resized, out of the Dock…) until a condition holds or
/// the time is up: each notification checks the condition again, nothing
/// sleeps a fixed time. An app still starting cannot be observed yet: it
/// is checked again every 200 ms until it can.
@MainActor
enum AXWait {
    static func until(pid: pid_t, element: AXUIElement, notifications: [String], timeout: Duration,
                      _ done: @MainActor () -> Bool) async -> Bool {
        if done() { return true }
        let deadline = ContinuousClock.now + timeout
        let signal = AXSignal()
        var observer: AXObserver?
        defer {
            if let observer {
                for name in notifications { AXObserverRemoveNotification(observer, element, name as CFString) }
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            }
        }
        while ContinuousClock.now < deadline {
            if observer == nil { observer = Self.observe(pid: pid, element: element, notifications: notifications, signal: signal) }
            await signal.next(before: observer == nil ? min(deadline, .now + .milliseconds(200)) : deadline)
            if done() { return true }
        }
        return done()
    }

    /// An observer for `notifications` on the main run loop; nil while the
    /// app does not answer them yet.
    private static func observe(pid: pid_t, element: AXUIElement, notifications: [String], signal: AXSignal) -> AXObserver? {
        var created: AXObserver?
        guard AXObserverCreate(pid, axWaitCallback, &created) == .success, let observer = created else { return nil }
        let refcon = Unmanaged.passUnretained(signal).toOpaque()
        let added = notifications.filter { AXObserverAddNotification(observer, element, $0 as CFString, refcon) == .success }
        guard !added.isEmpty else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return observer
    }
}

/// Wakes the waiting check: on a notification, or at the deadline.
@MainActor
final class AXSignal {
    private var waiter: CheckedContinuation<Void, Never>?
    private var pending = false

    func fire() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            pending = true
        }
    }

    func next(before deadline: ContinuousClock.Instant) async {
        if pending {
            pending = false
            return
        }
        let timer = Task { [weak self] in
            try? await Task.sleep(until: deadline)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
        await withCheckedContinuation { waiter = $0 }
        timer.cancel()
    }
}

/// Accessibility calls it on the main run loop, where the observer's source
/// was added. A free function: a closure written in main-actor code would
/// be isolated to it.
private func axWaitCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    // The signal's address, Sendable, into the main actor.
    let address = UInt(bitPattern: refcon)
    guard address != 0 else { return }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<AXSignal>.fromOpaque(pointer).takeUnretainedValue().fire()
    }
}
