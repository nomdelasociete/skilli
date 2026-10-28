import AppKit
import AVFoundation
import CoreAudio
import Foundation
import os

/// The host clock in seconds (`mach_absolute_time`'s ticks): the one clock
/// both tracks, the pauses and the stop are told in.
enum HostClock {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1e9
    }()

    static func seconds(_ ticks: UInt64) -> Double { Double(ticks) * secondsPerTick }
    static func ticks(_ seconds: Double) -> UInt64 { UInt64(max(0, seconds) / secondsPerTick) }
    static var now: Double { seconds(mach_absolute_time()) }
}

/// What an audio thread hands to its track's writer: the samples, as one
/// channel, and where each buffer is on the device's and the host's
/// clocks. Room is made once: Core Audio's real-time thread never waits on
/// a memory allocation, only, for a few microseconds, on the writer taking
/// what came. Full (the writer stuck for 10 s), buffers are left out: the
/// sample time then says how much is missing, written as silence.
final class AudioInbox: @unchecked Sendable {
    struct Chunk: Sendable {
        /// The device's sample time of its first frame, and the host's.
        var sampleTime: Double
        var hostTime: UInt64
        var rate: Double
        var offset: Int
        var frames: Int
        /// The source started again before it: a sample time of its own.
        var restarted: Bool
    }

    private let capacity: Int
    private static let chunkCapacity = 8192
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private let samples: UnsafeMutablePointer<Float>
    private let chunks: UnsafeMutablePointer<Chunk>
    private var count = 0
    private var chunkCount = 0
    private var restartNext = false
    /// When the source last started again (host ticks).
    private var restartedAt: UInt64 = 0
    /// The last buffer's level (root mean square), for the meters.
    private var lastLevel: Float = 0
    private var lastPut: UInt64 = 0
    private var firstPut: UInt64 = 0
    /// The last buffer that held more than digital silence.
    private var lastSound: UInt64 = 0
    private var droppedFrames = 0
    private var keepsSamples = false

    init(seconds: Double = 10, rate: Double = 48000) {
        capacity = Int(seconds * rate)
        samples = .allocate(capacity: capacity)
        chunks = .allocate(capacity: Self.chunkCapacity)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        samples.deallocate()
        chunks.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Whether the samples are kept for a writer; off, only the level is
    /// (the Record card's meters, nothing written).
    var keeping: Bool {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return keepsSamples
        }
        set {
            os_unfair_lock_lock(lock)
            keepsSamples = newValue
            if !newValue {
                count = 0
                chunkCount = 0
            }
            os_unfair_lock_unlock(lock)
        }
    }

    /// Listened to afresh (the card opened again): the meters start over.
    func resetMeters() {
        os_unfair_lock_lock(lock)
        (lastLevel, lastPut, firstPut, lastSound) = (0, 0, 0, 0)
        os_unfair_lock_unlock(lock)
    }

    /// The source started again (a change of the audio setup): its next
    /// buffer is placed by the host clock.
    func markRestart() {
        os_unfair_lock_lock(lock)
        restartNext = true
        restartedAt = mach_absolute_time()
        os_unfair_lock_unlock(lock)
    }

    /// Audio thread: `frames` frames of `list`, its last `channels`
    /// channels averaged into one (an aggregate device puts its taps after
    /// its devices' own streams), interleaved or one buffer a channel.
    func put(_ list: UnsafePointer<AudioBufferList>, channels wanted: Int, frames given: Int? = nil, sampleTime: Double, hostTime: UInt64, rate: Double) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard wanted > 0, buffers.count > 0, rate > 0 else { return }
        withUnsafeTemporaryAllocation(of: (pointer: UnsafePointer<Float>, stride: Int).self, capacity: 8) { picked in
            var found = 0
            var frames = Int.max
            // The last channels first: the source's own.
            for index in stride(from: buffers.count - 1, through: 0, by: -1) where found < min(wanted, 8) {
                let buffer = buffers[index]
                guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
                let step = Int(buffer.mNumberChannels)
                frames = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / step)
                let floats = UnsafePointer(data.assumingMemoryBound(to: Float.self))
                for channel in stride(from: step - 1, through: 0, by: -1) where found < min(wanted, 8) {
                    picked[found] = (floats + channel, step)
                    found += 1
                }
            }
            guard found > 0 else { return }
            if let given { frames = min(frames, given) }
            guard frames > 0, frames != .max else { return }
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            lastPut = mach_absolute_time()
            if firstPut == 0 { firstPut = lastPut }
            defer { if lastLevel > 0 { lastSound = lastPut } }
            let scale = 1 / Float(found)
            guard keepsSamples else {
                // The meters only.
                var power: Float = 0
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<found { sum += picked[channel].pointer[frame * picked[channel].stride] }
                    power += sum * scale * sum * scale
                }
                lastLevel = (power / Float(frames)).squareRoot()
                return
            }
            guard count + frames <= capacity, chunkCount < Self.chunkCapacity else {
                droppedFrames += frames
                return
            }
            var power: Float = 0
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<found { sum += picked[channel].pointer[frame * picked[channel].stride] }
                let value = sum * scale
                samples[count + frame] = value
                power += value * value
            }
            lastLevel = (power / Float(frames)).squareRoot()
            chunks[chunkCount] = Chunk(sampleTime: sampleTime, hostTime: hostTime, rate: rate, offset: count, frames: frames, restarted: restartNext)
            restartNext = false
            chunkCount += 1
            count += frames
        }
    }

    /// The writer's queue: everything that came since it last took.
    func take() -> (samples: [Float], chunks: [Chunk]) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let taken = Array(UnsafeBufferPointer(start: samples, count: count))
        let list = Array(UnsafeBufferPointer(start: chunks, count: chunkCount))
        count = 0
        chunkCount = 0
        return (taken, list)
    }

    /// The level now, 0…1 (-50 dBFS to 0, as the meeting check's meter);
    /// nothing for half a second: 0.
    var level: Double {
        os_unfair_lock_lock(lock)
        let (rms, last) = (lastLevel, lastPut)
        os_unfair_lock_unlock(lock)
        guard last > 0, HostClock.seconds(mach_absolute_time() - last) < 0.5, rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(max((decibels + 50) / 50, 0), 1)
    }

    /// How long only digital silence came (seconds), since the last sound
    /// or the first buffer; nil before any buffer. A tap macOS does not
    /// allow gives zeros, every call succeeding (Measured), where a quiet
    /// room still gives noise.
    var silentFor: Double? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard firstPut > 0 else { return nil }
        return HostClock.seconds(mach_absolute_time() - max(lastSound, firstPut))
    }

    /// When the last buffer came, the last one holding more than digital
    /// silence, and the source last started again (host seconds; nil:
    /// never): whether the track records anything (`SilentTrack`).
    var times: (buffer: Double?, sound: Double?, restarted: Double?) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        func seconds(_ ticks: UInt64) -> Double? { ticks == 0 ? nil : HostClock.seconds(ticks) }
        return (seconds(lastPut), seconds(lastSound), seconds(restartedAt))
    }

    var dropped: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return droppedFrames
    }
}

/// The Mac's sound: one Core Audio process tap on every process but
/// skil.li's (docs/meeting-recorder.md, "The Mac's sound"), on a private
/// aggregate device whose clock is the default output. Its IO block runs on
/// Core Audio's real-time thread (no queue): on a dispatch queue macOS let
/// it fall behind with the display off (Measured: 23 minutes missing in an
/// hour). The default output changing (headphones, a display) rebuilds the
/// aggregate on the new one, and so does the same output changing its rate
/// (a Bluetooth headset going to 24 kHz once a microphone is in use: its
/// buffers, still called 48 kHz, put 22 minutes of a call in 11); the tap's
/// next buffer is placed by the host clock. macOS asks once, the first time
/// (System Audio Recording, even with Screen Recording allowed, on the test
/// Mac); not allowed, the tap records silence, every call succeeding
/// (`AudioInbox.silentFor`).
final class MacSoundTap: @unchecked Sendable {
    struct Failure: LocalizedError {
        let call: String
        let status: OSStatus
        var errorDescription: String? { "The Mac's sound could not be recorded (\(call): \(status))." }
    }

    let inbox: AudioInbox
    private let queue = DispatchQueue(label: "com.nomdelasociete.Skilli.recorder.tap")
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var tapID = UUID()
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var channels = 2
    private var rate = 48000.0
    private var listening = false
    /// The output under the aggregate, whose rate is listened to with the
    /// aggregate's and the tap's format.
    private var output = AudioObjectID(kAudioObjectUnknown)
    /// One block, so that it can be removed (a closure passed again would
    /// be another block).
    private lazy var formatListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.followFormat() }
    /// Rebuilds that failed in a row (a device in the middle of a change):
    /// tried again a second later, three times.
    private var failedRebuilds = 0
    /// The output its clock comes from, by name (the card says "every app").
    private(set) var outputName = ""
    /// Self-test: processes left out too (the self-test's other skil.li).
    var alsoLeftOut: [pid_t] = []

    init(inbox: AudioInbox) {
        self.inbox = inbox
    }

    func start() throws {
        try queue.sync {
            try makeTap()
            try makeAggregate()
            if !listening {
                listening = true
                listenToOutput()
            }
        }
    }

    func stop() {
        queue.sync {
            destroyAggregate()
            if tap != kAudioObjectUnknown {
                Self.listen(tap, kAudioTapPropertyFormat, formatListener, on: queue, add: false)
                AudioHardwareDestroyProcessTap(tap)
            }
            tap = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Start Again (the card): the tap and its aggregate made afresh.
    func restart() throws {
        stop()
        inbox.markRestart()
        try start()
    }

    #if SKILLI_SELFTEST
    /// Self-test: the rate the IO block calls its buffers, and the rebuilds.
    var calledRate: Double { queue.sync { rate } }
    private(set) var rebuilds = 0
    /// Self-test: the rates now of the tap's format, the aggregate and the
    /// output under it.
    var formats: (tap: Double, aggregate: Double, output: Double) {
        queue.sync {
            var format = AudioStreamBasicDescription()
            var aggregateRate = 0.0, outputRate = 0.0
            Self.read(tap, kAudioTapPropertyFormat, &format)
            Self.read(aggregate, kAudioDevicePropertyNominalSampleRate, &aggregateRate)
            Self.read(Self.defaultOutput(), kAudioDevicePropertyNominalSampleRate, &outputRate)
            return (format.mSampleRate, aggregateRate, outputRate)
        }
    }
    #endif

    private func makeTap() throws {
        guard tap == kAudioObjectUnknown else { return }
        let leftOut = ([getpid()] + alsoLeftOut).compactMap(Self.processObject)
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: leftOut)
        tapID = UUID()
        description.uuid = tapID
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.name = "skil.li recorder"
        var made = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &made)
        guard status == noErr else { throw Failure(call: "AudioHardwareCreateProcessTap", status: status) }
        tap = made
        Self.listen(tap, kAudioTapPropertyFormat, formatListener, on: queue, add: true)
    }

    private func makeAggregate() throws {
        // The tap's format follows the output it is on.
        var format = AudioStreamBasicDescription()
        if Self.read(tap, kAudioTapPropertyFormat, &format) {
            channels = max(1, Int(format.mChannelsPerFrame))
            if format.mSampleRate > 0 { rate = format.mSampleRate }
        }
        let output = Self.defaultOutput()
        self.output = output
        let uid = Self.string(output, kAudioDevicePropertyDeviceUID) ?? ""
        outputName = Self.string(output, kAudioObjectPropertyName) ?? ""
        var settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "skil.li recorder",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapID.uuidString]],
        ]
        if !uid.isEmpty {
            settings[kAudioAggregateDeviceMainSubDeviceKey] = uid
            settings[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: uid]]
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &device)
        guard status == noErr else { throw Failure(call: "AudioHardwareCreateAggregateDevice", status: status) }
        aggregate = device
        // Its buffers come at the aggregate's rate: the one they are called.
        var nominal = 0.0
        if Self.read(device, kAudioDevicePropertyNominalSampleRate, &nominal), nominal > 0 { rate = nominal }
        for object in [device, output] where object != kAudioObjectUnknown {
            Self.listen(object, kAudioDevicePropertyNominalSampleRate, formatListener, on: queue, add: true)
        }
        var made: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&made, device, nil, Self.ioBlock(inbox, channels: channels, rate: rate))
        guard status == noErr, let made else {
            destroyAggregate()
            throw Failure(call: "AudioDeviceCreateIOProcIDWithBlock", status: status)
        }
        proc = made
        status = AudioDeviceStart(device, made)
        guard status == noErr else {
            destroyAggregate()
            throw Failure(call: "AudioDeviceStart", status: status)
        }
    }

    private func destroyAggregate() {
        for object in [aggregate, output] where object != kAudioObjectUnknown {
            Self.listen(object, kAudioDevicePropertyNominalSampleRate, formatListener, on: queue, add: false)
        }
        output = AudioObjectID(kAudioObjectUnknown)
        if aggregate != kAudioObjectUnknown, let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        aggregate = AudioObjectID(kAudioObjectUnknown)
        proc = nil
    }

    /// Core Audio's real-time thread: the samples into the inbox, nothing
    /// else. Made here, outside any actor.
    private static func ioBlock(_ inbox: AudioInbox, channels: Int, rate: Double) -> AudioDeviceIOBlock {
        { _, input, inputTime, _, _ in
            let time = inputTime.pointee
            let host = time.mFlags.contains(.hostTimeValid) ? time.mHostTime : mach_absolute_time()
            inbox.put(input, channels: channels, sampleTime: time.mSampleTime, hostTime: host, rate: rate)
        }
    }

    /// The default output changed: the aggregate again on the new one.
    private func listenToOutput() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue) { [weak self] _, _ in
            // Started (a tap made), even when its last rebuild failed.
            guard let self, self.tap != kAudioObjectUnknown else { return }
            self.rebuild()
        }
    }

    /// The output's, the aggregate's or the tap's rate or channels changed
    /// (a headset going to its call mode): the aggregate again, its buffers
    /// called by the rate they come at. A change that leaves them as they
    /// are rebuilds nothing.
    private func followFormat() {
        guard tap != kAudioObjectUnknown else { return }
        guard aggregate != kAudioObjectUnknown else { return rebuild() }
        var format = AudioStreamBasicDescription()
        var nominal = 0.0
        let channels = Self.read(tap, kAudioTapPropertyFormat, &format) ? max(1, Int(format.mChannelsPerFrame)) : self.channels
        let rate = Self.read(aggregate, kAudioDevicePropertyNominalSampleRate, &nominal) && nominal > 0 ? nominal
            : format.mSampleRate > 0 ? format.mSampleRate : self.rate
        guard rate != self.rate || channels != self.channels else { return }
        Log.trace("Recorder: the Mac's sound now \(Int(rate)) Hz, \(channels) channels (was \(Int(self.rate)) Hz, \(self.channels))")
        rebuild()
    }

    /// The aggregate made again (on the queue); its next buffer placed by
    /// the host clock. Failed (a device in the middle of a change), tried
    /// again a second later, three times; then the track says it records
    /// nothing (`SilentTrack`).
    private func rebuild() {
        destroyAggregate()
        inbox.markRestart()
        #if SKILLI_SELFTEST
        rebuilds += 1
        #endif
        do {
            try makeAggregate()
            failedRebuilds = 0
            Log.trace("Recorder: the Mac's sound on \(outputName) now, \(Int(rate)) Hz")
        } catch {
            failedRebuilds += 1
            Log.actions.error("Recorder: the Mac's sound lost (\(error.localizedDescription, privacy: .public))")
            guard failedRebuilds < 3 else { return }
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.tap != kAudioObjectUnknown, self.aggregate == kAudioObjectUnknown else { return }
                self.rebuild()
            }
        }
    }

    /// `block` on `selector` of `object` added (or removed), on `queue`.
    private static func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ block: @escaping AudioObjectPropertyListenerBlock,
                               on queue: DispatchQueue, add: Bool) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if add {
            AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        } else {
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
    }

    // MARK: - Core Audio

    static func processObject(_ pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid,
                                                &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    /// The app playing sound now that is not skil.li, by name: the card
    /// says which one it does not hear.
    static func playing() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return nil }
        for id in ids {
            var running: UInt32 = 0
            guard read(id, kAudioProcessPropertyIsRunningOutput, &running), running != 0 else { continue }
            var pid: pid_t = 0
            guard read(id, kAudioProcessPropertyPID, &pid), pid != getpid() else { continue }
            if let app = NSRunningApplication(processIdentifier: pid)?.localizedName { return app }
            if let bundle = string(id, kAudioProcessPropertyBundleID), !bundle.isEmpty {
                // A helper (Chrome's sound is its helper's): its app's name.
                let main = bundle.components(separatedBy: ".helper").first ?? bundle
                return NSRunningApplication.runningApplications(withBundleIdentifier: main).first?.localizedName ?? "an app"
            }
            return "an app"
        }
        return nil
    }

    private static func defaultOutput() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        _ = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, &device)
        return device
    }

    @discardableResult
    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) } == noErr
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
