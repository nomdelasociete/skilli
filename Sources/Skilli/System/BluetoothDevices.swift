import CoreBluetooth
import Foundation
import IOBluetooth
import Synchronization
import SkilliCore

/// The Bluetooth devices paired with this Mac (AirPods, a keyboard, a
/// speaker) through IOBluetooth, Apple's public framework: listed,
/// connected and disconnected as the Bluetooth menu does. macOS asks the
/// user once (Bluetooth in Privacy & Security): nothing is read before
/// they allowed it.
///
/// Turning Bluetooth itself on or off is not offered: IOBluetooth only
/// reads the controller's power state (`IOBluetoothHostController.powerState`);
/// the setter tools use (`IOBluetoothPreferenceSetControllerPowerState`) is
/// private and undocumented.
enum BluetoothDevices {
    struct Device: Equatable, Sendable {
        /// "a4-83-e7-11-22-33", stable across connections.
        let address: String
        let name: String
        let kind: BluetoothRoute.Kind
        let connected: Bool
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// macOS's answer for skil.li, read without asking.
    static var authorization: CBManagerAuthorization { CBManager.authorization }
    static var isAllowed: Bool { authorization == .allowedAlways }

    /// What the last read found; the launcher shows it (a key never asks
    /// IOBluetooth), read again in the background as it opens and when a
    /// device connects or disconnects.
    private static let known = Mutex<(devices: [Device], read: Date?)>(([], nil))

    static var cached: [Device] { known.withLock { $0.devices } }

    /// The devices paired with this Mac, by name, read now; nothing when
    /// skil.li may not use Bluetooth. Safe off the main thread.
    @discardableResult
    static func paired() -> [Device] {
        guard isAllowed else {
            known.withLock { $0 = ([], .now) }
            return []
        }
        let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
            .compactMap(device)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        known.withLock { $0 = (devices, .now) }
        return devices
    }

    /// Read again off the main thread when the last read is older than
    /// `age` seconds (the launcher, as it opens).
    static func refreshInBackground(olderThan age: TimeInterval = 5) {
        let last = known.withLock { $0.read }
        if let last, Date.now.timeIntervalSince(last) < age { return }
        Task.detached(priority: .utility) { _ = paired() }
    }

    private static func device(_ device: IOBluetoothDevice) -> Device? {
        guard let address = device.addressString, !address.isEmpty else { return nil }
        let name = device.nameOrAddress ?? address
        return Device(address: address, name: name, kind: BluetoothRoute.Kind(major: device.deviceClassMajor, minor: device.deviceClassMinor, name: name),
                      connected: device.isConnected())
    }

    /// Connects a paired device, as choosing it in the Bluetooth menu does
    /// (headphones then take the sound if macOS gives it to them). Waits for
    /// IOBluetooth's answer: 15 s at most.
    @MainActor
    static func connect(address: String) async throws -> Device {
        guard isAllowed else { throw Failure(message: "skil.li may not use Bluetooth yet: allow it in Settings → Privacy.") }
        guard let device = IOBluetoothDevice(addressString: address), device.isPaired() else {
            throw Failure(message: "That device is not paired with this Mac any more.")
        }
        let name = device.nameOrAddress ?? address
        if device.isConnected() { throw Failure(message: "“\(name)” is already connected.") }
        let waiter = ConnectWaiter()
        let status: IOReturn = await withCheckedContinuation { continuation in
            waiter.start(continuation)
            let started = device.openConnection(waiter)
            if started != kIOReturnSuccess { waiter.finish(started) }
            Task {
                try? await Task.sleep(for: .seconds(15))
                waiter.finish(ConnectWaiter.timedOut)
            }
        }
        paired()
        guard status == kIOReturnSuccess, device.isConnected() else {
            throw Failure(message: "“\(name)” did not connect: is it on and nearby?")
        }
        Log.trace("Bluetooth connected: \(name)")
        return Device(address: address, name: name, kind: BluetoothRoute.Kind(major: device.deviceClassMajor, minor: device.deviceClassMinor, name: name),
                      connected: true)
    }

    /// Disconnects it, as the Bluetooth menu does.
    @MainActor
    static func disconnect(address: String) throws -> Device {
        guard isAllowed else { throw Failure(message: "skil.li may not use Bluetooth yet: allow it in Settings → Privacy.") }
        guard let device = IOBluetoothDevice(addressString: address) else { throw Failure(message: "That device is not paired with this Mac any more.") }
        let name = device.nameOrAddress ?? address
        guard device.isConnected() else { throw Failure(message: "“\(name)” is not connected.") }
        let status = device.closeConnection()
        paired()
        guard status == kIOReturnSuccess else { throw Failure(message: "macOS did not disconnect “\(name)” (\(status)).") }
        Log.trace("Bluetooth disconnected: \(name)")
        return Device(address: address, name: name, kind: BluetoothRoute.Kind(major: device.deviceClassMajor, minor: device.deviceClassMinor, name: name),
                      connected: false)
    }

    // MARK: - Asking

    /// macOS's own question for Bluetooth, asked by starting CoreBluetooth
    /// once (what its documentation says triggers it); the answer is read
    /// again by `PermissionCenter`.
    @MainActor
    static func requestAccess() {
        guard authorization == .notDetermined, asker == nil else { return }
        asker = AccessAsker()
    }

    @MainActor private static var asker: AccessAsker?
}

/// Receives IOBluetooth's -connectionComplete:status: (on whichever thread
/// it calls): the first answer, or the time limit, ends the wait.
private final class ConnectWaiter: NSObject, @unchecked Sendable {
    /// IOKit's kIOReturnTimeout (its macro is not imported).
    static let timedOut = IOReturn(bitPattern: 0xE000_02D6)
    private let continuation = Mutex<CheckedContinuation<IOReturn, Never>?>(nil)

    func start(_ continuation: CheckedContinuation<IOReturn, Never>) {
        self.continuation.withLock { $0 = continuation }
    }

    func finish(_ status: IOReturn) {
        let waiting = continuation.withLock { value -> CheckedContinuation<IOReturn, Never>? in
            defer { value = nil }
            return value
        }
        waiting?.resume(returning: status)
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice?, status: IOReturn) {
        finish(status)
    }
}

/// Holds a CBCentralManager while macOS asks; its state callbacks come on a
/// queue of its own and change nothing here.
private final class AccessAsker: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private var manager: CBCentralManager?

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "skilli.bluetooth.access"))
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {}
}
