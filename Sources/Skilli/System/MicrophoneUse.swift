import AppKit
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
    /// Who runs it, by app (the recorder's moment).
    var holders: MicrophoneHolders = .none
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

    /// Self-test: who runs the microphone, instead of CoreAudio's.
    var standInHolders: MicrophoneHolders? {
        didSet { if standInHolders != oldValue { onChange?() } }
    }

    /// The apps running the microphone's input now, as last read (read
    /// once at once when not started).
    var holders: MicrophoneHolders {
        if let standInHolders { return standInHolders }
        return isStarted ? reading.holders : Self.read().holders
    }

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
        var holders = MicrophoneHolders()
        for id in ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride) {
            let input: UInt32 = value(id, kAudioProcessPropertyIsRunningInput) ?? 0
            guard input != 0, let pid: pid_t = value(id, kAudioProcessPropertyPID), pid != own else { continue }
            if let app = app(of: pid) {
                // skil.li's own child (a self-test's helper) is skil.li.
                if app.pid != own, !holders.apps.contains(where: { $0.pid == app.pid }) { holders.apps.append(app) }
            } else {
                holders.unnamed += 1
            }
        }
        return MicrophoneReading(inUse: !holders.isEmpty, hasInput: hasInput, holders: holders)
    }

    /// The app process `pid` belongs to: itself when it is an app the user
    /// sees (a Dock icon, or a menu bar app), else the first such among its
    /// parents: a browser's helper is its browser, an Electron app's helper
    /// the app. Nil when none is (a system service, as WebKit's for
    /// Safari, whose parent is launchd).
    nonisolated static func app(of pid: pid_t) -> MicrophoneApp? {
        var current = pid
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy != .prohibited {
                let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "An app"
                return MicrophoneApp(bundleID: app.bundleIdentifier ?? "", name: name, pid: app.processIdentifier)
            }
            guard let parent = parent(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    /// The process that started `pid` (the kernel's record).
    nonisolated static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// The app's front window on screen: its first normal window in the
    /// window list, front to back (no title read). Nil when it shows none.
    static func frontWindow(of pid: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return windows.first { window in
            (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid && (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }.flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
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
