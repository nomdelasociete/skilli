import AudioToolbox
import CoreAudio
import Foundation
import Synchronization
import SkilliCore

/// The Mac's sound outputs and microphones through CoreAudio, and which one
/// macOS uses: what Sound settings shows, switched without opening it. No
/// permission needed.
enum AudioDevices {
    struct Device: Equatable, Sendable {
        let id: AudioObjectID
        let uid: String
        let name: String
        let transport: AudioRoute.Transport
        let hasOutput: Bool
        let hasInput: Bool
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Every visible device, outputs and inputs, by name. Read once, then
    /// again only when CoreAudio says devices came or went: the launcher
    /// asks on every key.
    static func all() -> [Device] {
        let watched = watchChanges()
        let (cached, generation) = known.withLock { ($0.devices, $0.generation) }
        if watched, let cached { return cached }
        guard let ids: [AudioObjectID] = array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) else { return [] }
        let devices = ids.compactMap(device).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Kept unless CoreAudio said something changed meanwhile.
        if watched { known.withLock { if $0.generation == generation { $0.devices = devices } } }
        return devices
    }

    /// What CoreAudio last said: the devices, the default output (`true`)
    /// and input; `generation` counts its changes.
    private struct Known {
        var devices: [Device]?
        var defaults: [Bool: AudioObjectID] = [:]
        var generation = 0
    }

    private static let known = Mutex(Known())
    /// Whether CoreAudio tells skil.li about changes; nil until asked.
    private static let watching = Mutex<Bool?>(nil)

    /// Devices plugged or unplugged, another output or microphone chosen:
    /// what was read is read again on the next ask. When CoreAudio cannot
    /// tell, nothing is kept.
    @discardableResult
    private static func watchChanges() -> Bool {
        watching.withLock { watched in
            if let watched { return watched }
            let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice]
            var all = true
            for selector in selectors {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil) { _, _ in
                    known.withLock { $0 = Known(generation: $0.generation + 1) }
                }
                if status != noErr {
                    all = false
                    Log.actions.error("Sound changes not watched (\(status, privacy: .public))")
                }
            }
            watched = all
            return all
        }
    }

    static func devices(output: Bool) -> [Device] {
        all().filter { output ? $0.hasOutput : $0.hasInput }
    }

    /// The device macOS plays through (or records from) now.
    static func current(output: Bool) -> Device? {
        let watched = watchChanges()
        let id: AudioObjectID
        let (remembered, generation) = known.withLock { ($0.defaults[output], $0.generation) }
        if watched, let remembered {
            id = remembered
        } else {
            let selector = output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
            guard let read: AudioObjectID = value(AudioObjectID(kAudioObjectSystemObject), selector) else { return nil }
            if watched { known.withLock { if $0.generation == generation { $0.defaults[output] = read } } }
            id = read
        }
        return all().first { $0.id == id } ?? device(id)
    }

    /// Makes it macOS's output (or microphone), like choosing it in Sound
    /// settings. Alerts follow when Sound settings plays them "through the
    /// selected output", the default.
    static func select(uid: String, output: Bool) throws -> Device {
        guard let device = all().first(where: { $0.uid == uid && (output ? $0.hasOutput : $0.hasInput) }) else {
            throw Failure(message: "That \(output ? "sound output" : "microphone") is not connected.")
        }
        var address = AudioObjectPropertyAddress(
            mSelector: output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var id = device.id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        guard status == noErr else { throw Failure(message: "macOS did not switch to “\(device.name)” (error \(status)).") }
        known.withLock { $0.defaults[output] = device.id }
        Log.trace("Sound \(output ? "output" : "input"): \(device.name)")
        return device
    }

    // MARK: - CoreAudio

    /// The device as Sound settings shows it; nil for a hidden one, one
    /// without streams, or an aggregate private to skil.li. Internal for the
    /// self-test.
    static func device(_ id: AudioObjectID) -> Device? {
        if let hidden: UInt32 = value(id, kAudioDevicePropertyIsHidden), hidden != 0 { return nil }
        guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
        let code: UInt32 = value(id, kAudioDevicePropertyTransportType) ?? 0
        // Ask by Voice's AVAudioEngine leaves CoreAudio's own aggregate of
        // the default input and output in skil.li ("CADefaultDeviceAggregate-
        // <pid>-<n>", rebuilt at each change) until it quits: private to
        // skil.li, never in Sound settings, it was listed as an output and a
        // microphone.
        if code == kAudioDeviceTransportTypeAggregate, isPrivateAggregate(id) { return nil }
        let transport = AudioRoute.Transport(code: code)
        let hasOutput = hasStreams(id, scope: kAudioObjectPropertyScopeOutput)
        let hasInput = hasStreams(id, scope: kAudioObjectPropertyScopeInput)
        guard hasOutput || hasInput else { return nil }
        return Device(id: id, uid: uid, name: name, transport: transport, hasOutput: hasOutput, hasInput: hasInput)
    }

    /// An aggregate device only the process that made it sees
    /// (`kAudioAggregateDeviceIsPrivateKey` in its composition).
    private static func isPrivateAggregate(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioAggregateDevicePropertyComposition, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        var composition: Unmanaged<CFDictionary>?
        let status = withUnsafeMutablePointer(to: &composition) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        guard status == noErr, let composition else { return false }
        let dictionary = composition.takeRetainedValue() as NSDictionary
        return (dictionary[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue == true
    }

    private static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    /// The default output's volume, 0…100, as the menu bar shows it; nil
    /// when the device has none (HDMI, some USB).
    static var outputVolume: Int? {
        guard let id = current(output: true)?.id else { return nil }
        var address = volumeAddress
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Int((volume * 100).rounded())
    }

    static func setOutputVolume(_ percent: Int) throws {
        guard let id = current(output: true)?.id else { throw Failure(message: "No sound output.") }
        var address = volumeAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &address), AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue else {
            throw Failure(message: "This output's volume is set on the device itself.")
        }
        var volume = Float32(min(max(percent, 0), 100)) / 100
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        guard status == noErr else { throw Failure(message: "macOS did not change the volume (\(status)).") }
    }

    /// Whether the default microphone is muted: its own mute, or its
    /// volume at 0; nil without a microphone.
    static var inputMuted: Bool? {
        guard let device = current(output: false) else { return nil }
        var mute = inputMuteAddress
        if AudioObjectHasProperty(device.id, &mute) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device.id, &mute, 0, nil, &size, &value) == noErr { return value != 0 }
        }
        var address = inputVolumeAddress
        var volume: Float32 = 1
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume == 0
    }

    /// The default microphone muted, or back on: its own mute when macOS
    /// can set it, else its level to 0 and back to where it was. True when
    /// muted now.
    static func toggleInputMute() throws -> Bool {
        guard let device = current(output: false) else { throw Failure(message: "No microphone on this Mac.") }
        var settable: DarwinBoolean = false
        var mute = inputMuteAddress
        if AudioObjectHasProperty(device.id, &mute), AudioObjectIsPropertySettable(device.id, &mute, &settable) == noErr, settable.boolValue {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(device.id, &mute, 0, nil, &size, &value)
            var next: UInt32 = value == 0 ? 1 : 0
            let status = AudioObjectSetPropertyData(device.id, &mute, 0, nil, size, &next)
            guard status == noErr else { throw Failure(message: "macOS did not mute “\(device.name)” (\(status)).") }
            return next == 1
        }
        var address = inputVolumeAddress
        settable = false
        guard AudioObjectHasProperty(device.id, &address), AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr, settable.boolValue else {
            throw Failure(message: "“\(device.name)” cannot be muted from the Mac: mute it in the call.")
        }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        _ = AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &volume)
        let key = "AudioDevices.levelBeforeMute.\(device.uid)"
        var next: Float32 = 0
        if volume == 0 { next = Float32(UserDefaults.standard.object(forKey: key) as? Double ?? 0.75) } else { UserDefaults.standard.set(Double(volume), forKey: key) }
        let status = AudioObjectSetPropertyData(device.id, &address, 0, nil, size, &next)
        guard status == noErr else { throw Failure(message: "macOS did not change “\(device.name)” (\(status)).") }
        return next == 0
    }

    private static var inputMuteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    private static var inputVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// The volume macOS shows for the whole device, all channels.
    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func array<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [T]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return Array(UnsafeBufferPointer(start: pointer, count: Int(size) / MemoryLayout<T>.stride))
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var text: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &text) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        guard status == noErr, let text else { return nil }
        return text.takeRetainedValue() as String
    }
}
