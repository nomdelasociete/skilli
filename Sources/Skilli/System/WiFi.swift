import CoreWLAN
import Foundation
import Synchronization
import SkilliCore

/// The Mac's Wi-Fi through CoreWLAN, Apple's public framework: on or off
/// (`CWInterface.setPower`, what the Wi-Fi menu's switch does), and what it
/// is connected to for System Info. The network's name needs Location
/// Services (CoreWLAN hides it otherwise): skil.li does not ask for it, so
/// it is said only when macOS gives it.
enum WiFi {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static var interface: CWInterface? { CWWiFiClient.shared().interface() }

    /// On or off, read now; nil on a Mac without Wi-Fi. Safe off the main
    /// thread.
    static func isOn() -> Bool? {
        guard let interface else {
            known.withLock { $0 = (nil, .now) }
            return nil
        }
        let on = interface.powerOn()
        known.withLock { $0 = (on, .now) }
        return on
    }

    /// What the last read found (the launcher: a key never asks CoreWLAN).
    private static let known = Mutex<(on: Bool?, read: Date?)>((nil, nil))
    static var cachedIsOn: Bool? { known.withLock { $0.on } }

    /// Read again off the main thread when older than `age` seconds.
    static func refreshInBackground(olderThan age: TimeInterval = 5) {
        let last = known.withLock { $0.read }
        if let last, Date.now.timeIntervalSince(last) < age { return }
        Task.detached(priority: .utility) { _ = isOn() }
    }

    /// Turns it on or off, as the Wi-Fi menu's switch does. Already so:
    /// nothing changes.
    static func setPower(_ on: Bool) throws {
        guard let interface else { throw Failure(message: "This Mac has no Wi-Fi.") }
        do {
            try interface.setPower(on)
        } catch {
            throw Failure(message: "macOS did not turn Wi-Fi \(on ? "on" : "off"): \(error.localizedDescription)")
        }
        known.withLock { $0 = (on, .now) }
        Log.trace("Wi-Fi \(on ? "on" : "off")")
    }

    /// "Wi-Fi: Freebox-12 · signal good · 866 Mbps", "Wi-Fi: on, not
    /// connected", "Wi-Fi: off"; nil without Wi-Fi.
    static func summary() -> String? {
        guard let interface else { return nil }
        guard interface.powerOn() else { return "Wi-Fi: off" }
        let rssi = interface.rssiValue()
        // No signal: not joined to a network.
        guard rssi != 0 else { return "Wi-Fi: on, not connected" }
        let name = interface.ssid().map { "Wi-Fi: \($0)" } ?? "Wi-Fi: connected"
        let rate = interface.transmitRate()
        return "\(name) · signal \(MacReadings.signal(rssi: rssi))" + (rate > 0 ? " · \(Int(rate.rounded())) Mbps" : "")
    }
}
