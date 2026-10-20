import AppKit
import SkilliCore

/// Tells when a display is plugged in: AppKit's screen changes, minus the
/// displays coming back after the Mac or its screens slept
/// (`DisplayArrival`). Event-driven: nothing is polled.
@MainActor
final class DisplayWatch {
    /// The displays just plugged in (never the built-in one).
    var onPlugged: (([DisplayFingerprint]) -> Void)?
    /// A display went away (to close what was asked on it).
    var onUnplugged: (([DisplayFingerprint]) -> Void)?
    private var arrival: DisplayArrival
    private var observers: [NSObjectProtocol] = []

    init() {
        arrival = DisplayArrival(present: Displays.current().map(\.fingerprint))
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.arrival.sleep() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.arrival.wake(at: .now) }
            })
        }
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func screensChanged() {
        let before = arrival.present
        let now = Displays.current().map(\.fingerprint)
        let plugged = arrival.update(now, at: .now)
        let gone = before.filter { old in !now.contains { $0.isSameDisplay(as: old) } }
        if !gone.isEmpty {
            Log.trace("Displays: \(gone.map(\.name).joined(separator: ", ")) unplugged")
            onUnplugged?(gone)
        }
        if !plugged.isEmpty {
            Log.trace("Displays: \(plugged.map(\.name).joined(separator: ", ")) plugged in")
            onPlugged?(plugged)
        }
    }
}
