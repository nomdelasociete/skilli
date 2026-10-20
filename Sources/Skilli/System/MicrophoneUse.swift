import CoreAudio
import Foundation
import SkilliCore
import Synchronization

/// Whether a call is on on this Mac, from what macOS itself shows: another
/// app recording from a microphone (its orange dot). Read from CoreAudio's
/// process objects (macOS 14; no permission, nothing recorded, skil.li's
/// own Ask by Voice and camera check left out). CoreAudio says when an
/// input device starts or stops, and when devices or processes come and
/// go: read again then, never polled. The menu bar's meeting tells
/// "joined" from "started" by it (`MeetingBar.Presence`).
/// What CoreAudio says of the microphones.
struct MicrophoneReading: Equatable, Sendable {
    /// nil: CoreAudio could not say.
    var inUse: Bool?
    /// A microphone is connected (Sound settings lists an input).
    var hasInput: Bool
}

@MainActor
final class MicrophoneUse {
    /// The reading changed.
    var onChange: (() -> Void)?
    /// Self-test: read instead of CoreAudio's.
    var standIn: MeetingBar.Presence.Microphone? {
        didSet { if standIn != oldValue { onChange?() } }
    }
    /// What CoreAudio said last; nothing is known before `start`.
    private(set) var reading = MicrophoneReading(inUse: nil, hasInput: false)
    /// When skil.li saw the call begin (or, already on, when it first
    /// looked).
    private var since: Date?
    private var listener: MicrophoneListener?

    var microphone: MeetingBar.Presence.Microphone {
        if let standIn { return standIn }
        guard reading.hasInput, let inUse = reading.inUse else { return .unknown }
        guard inUse, let since else { return .idle }
        return .inUse(since: since)
    }

    var isStarted: Bool { listener != nil }

    /// Reads once, then follows CoreAudio's changes. Once; the listeners
    /// cost nothing until a device or a process changes.
    func start() {
        guard listener == nil else { return }
        apply(Self.read())
        let listener = Self.listener(for: self)
        self.listener = listener
        listener.begin()
    }

    private func apply(_ new: MicrophoneReading) {
        let wasInUse = reading.inUse == true
        let changed = new != reading
        reading = new
        if new.inUse == true {
            if !wasInUse || since == nil { since = .now }
        } else {
            since = nil
        }
        if changed, standIn == nil { onChange?() }
    }

    /// Built outside the main actor: CoreAudio calls its blocks on the
    /// listener's queue, and the reading hops to the main actor.
    nonisolated private static func listener(for watch: MicrophoneUse) -> MicrophoneListener {
        MicrophoneListener { [weak watch] reading in
            let target = watch
            DispatchQueue.main.async {
                MainActor.assumeIsolated { target?.apply(reading) }
            }
        }
    }

    /// Whether an app other than skil.li records now, and whether this Mac
    /// has a microphone at all.
    nonisolated static func read() -> MicrophoneReading {
        let hasInput = !AudioDevices.devices(output: false).isEmpty
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return MicrophoneReading(inUse: nil, hasInput: hasInput) }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        if !ids.isEmpty, AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) != noErr {
            return MicrophoneReading(inUse: nil, hasInput: hasInput)
        }
        let own = ProcessInfo.processInfo.processIdentifier
        let inUse = ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride).contains { id in
            let input: UInt32 = value(id, kAudioProcessPropertyIsRunningInput) ?? 0
            guard input != 0 else { return false }
            let pid: pid_t? = value(id, kAudioProcessPropertyPID)
            return pid != own
        }
        return MicrophoneReading(inUse: inUse, hasInput: hasInput)
    }

    nonisolated private static func value<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }
}

/// CoreAudio's listeners, on a queue of their own: the devices and the
/// processes CoreAudio knows, and each microphone's "running somewhere"
/// (one added as each new input appears).
final class MicrophoneListener: Sendable {
    private let queue = DispatchQueue(label: "com.nomdelasociete.Skilli.microphone")
    private let watched = Mutex<Set<AudioObjectID>>([])
    private let deliver: @Sendable (MicrophoneReading) -> Void

    init(deliver: @escaping @Sendable (MicrophoneReading) -> Void) {
        self.deliver = deliver
    }

    func begin() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyProcessObjectList] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue) { [self] _, _ in changed() }
            if status != noErr { Log.actions.error("Microphone use not watched (\(status, privacy: .public))") }
        }
        queue.async { [self] in changed() }
    }

    private func changed() {
        for device in AudioDevices.devices(output: false) where watched.withLock({ $0.insert(device.id).inserted }) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(device.id, &address, queue) { [self] _, _ in deliver(MicrophoneUse.read()) }
        }
        deliver(MicrophoneUse.read())
    }
}
