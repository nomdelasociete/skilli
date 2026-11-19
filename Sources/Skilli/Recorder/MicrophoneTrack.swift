import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Synchronization

/// The microphone, the user's side: a chosen Core Audio input, or the
/// system default through `AVAudioEngine`. A change of the audio setup (a device plugged, the
/// default input chosen again, a rate changed) stops an engine and nothing
/// starts it again (Measured: it stopped after 62 s): a new engine is
/// started at once, its next buffer placed by the host clock, so the track
/// keeps its time. Never the same engine again: it keeps its input's
/// format from before the change, and a Bluetooth headset gone to 24 kHz
/// for a call had AVAudioEngine refuse the tap at 48 kHz ("Failed to create
/// tap, config change pending!"), tell the caller nothing and run on
/// without it: nothing reached the track for the rest of a 22-minute call.
/// An engine that gives no buffer 2 s after it started is replaced too.
@MainActor
final class MicrophoneTrack {
    enum State: Equatable {
        case off
        /// Not allowed in Privacy & Security.
        case denied
        /// No input on this Mac.
        case none
        case on(String)
    }

    let inbox: AudioInbox
    private(set) var state: State = .off
    private(set) var restarts = 0
    private(set) var selectedInputUID: String?
    private var hasTap = false
    private var deviceCapture: (id: AudioObjectID, proc: AudioDeviceIOProcID)?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    /// Whether the engine started last gives buffers, checked 2 s after;
    /// engines started in a row that gave none (a fourth is not tried:
    /// the track then says it records nothing, `SilentTrack`).
    private var expecting: Task<Void, Never>?
    private var startsGivingNothing = 0
    #if SKILLI_SELFTEST
    /// Self-test: a file plays as the microphone (the test Mac has none),
    /// through the same engine and tap, from `playStandIn`.
    var activeInputID: UInt32? { deviceCapture?.id ?? engine?.inputNode.auAudioUnit.deviceID }
    var standIn: URL?
    private var player: AVAudioPlayerNode?
    #endif

    init(inbox: AudioInbox) {
        self.inbox = inbox
    }

    /// Runs the microphone when it is allowed; macOS asks once when it
    /// never did.
    func start() async {
        #if SKILLI_SELFTEST
        if standIn != nil {
            startEngine()
            return
        }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        guard selectedInputUID != nil || AVCaptureDevice.default(for: .audio) != nil else {
            state = .none
            return
        }
        startEngine()
    }

    func stop() {
        #if SKILLI_SELFTEST
        standInPlaying = false
        #endif
        startsGivingNothing = 0
        dropEngine()
        if case .on = state { state = .off }
    }

    /// The engine, its tap, its observer and its buffers' check let go.
    private func dropEngine() {
        expecting?.cancel()
        expecting = nil
        if let capture = deviceCapture {
            deviceCapture = nil
            if let listener = deviceListener {
                for var property in Self.inputProperties {
                    AudioObjectRemovePropertyListenerBlock(capture.id, &property, .main, listener)
                }
            }
            deviceListener = nil
            AudioDeviceStop(capture.id, capture.proc)
            AudioDeviceDestroyIOProcID(capture.id, capture.proc)
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let engine, hasTap { removeTap(from: engine) }
        hasTap = false
        #if SKILLI_SELFTEST
        // The stand-in's player belongs to that engine.
        player?.stop()
        player = nil
        #endif
        engine?.stop()
        engine = nil
    }

    /// A new engine on the default input as it is now. `again`: after one
    /// before it (its failure logged so, the state kept).
    private var usesStandIn: Bool {
        #if SKILLI_SELFTEST
        return standIn != nil
        #else
        return false
        #endif
    }

    private func startEngine(again: Bool = false) {
        let started = HostClock.now
        if let uid = selectedInputUID, !usesStandIn {
            do {
                try startDevice(uid)
            } catch {
                state = .none
                Log.actions.error("Recorder: could not start selected microphone (\(error.localizedDescription, privacy: .public))")
            }
            expectBuffers(since: started)
            return
        }
        let engine = AVAudioEngine()
        self.engine = engine
        do {
            try install(on: engine)
            hasTap = true
            // Device selection can itself change the configuration. Observe
            // changes only after the input and tap have been configured.
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] notification in
                guard let changed = notification.object as? AVAudioEngine else { return }
                let identity = ObjectIdentifier(changed)
                MainActor.assumeIsolated {
                    guard let self, let engine = self.engine, ObjectIdentifier(engine) == identity else { return }
                    self.startAgain()
                }
            }
            engine.prepare()
            try engine.start()
        } catch {
            Log.actions.error("Recorder: the microphone did not start\(again ? " again" : "") (\(error.localizedDescription, privacy: .public))")
            state = .none
            expectBuffers(since: started)
            return
        }
        state = .on(deviceName)
        expectBuffers(since: started)
    }

    /// 2 s after an engine started: no buffer from it (its tap refused, its
    /// device in the middle of a change) and a new one is started.
    private func expectBuffers(since started: Double) {
        expecting?.cancel()
        #if SKILLI_SELFTEST
        // The stand-in gives buffers only once a check plays it.
        if standIn != nil { return }
        #endif
        expecting = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.engine != nil || self.deviceCapture != nil else { return }
            if let last = self.inbox.times.buffer, last >= started {
                self.startsGivingNothing = 0
                return
            }
            self.startsGivingNothing += 1
            guard self.startsGivingNothing <= 3 else { return }
            Log.actions.error("Recorder: the microphone gave nothing 2 s after it started: a new engine (\(self.startsGivingNothing))")
            self.startAgain()
        }
    }

    // A named device has its own Core Audio stream. Routing the default
    // AVAudioEngine to a different device can trigger a configuration
    // notification every time it starts.
    private func startDevice(_ uid: String) throws {
        guard let device = AudioDevices.devices(output: false).first(where: { $0.uid == uid }) else {
            throw AudioDevices.Failure(message: "That microphone is no longer connected.")
        }
        var address = Self.inputProperties[0]
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let queried = AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &rate)
        guard queried == noErr, rate > 0 else {
            throw AudioDevices.Failure(message: "Could not read the microphone's sample rate.")
        }
        var proc: AudioDeviceIOProcID?
        let added = AudioDeviceCreateIOProcIDWithBlock(&proc, device.id, nil, Self.deviceInput(inbox, rate: rate))
        guard added == noErr, let proc else {
            throw AudioDevices.Failure(message: "Could not open the microphone (\(added)).")
        }
        let started = AudioDeviceStart(device.id, proc)
        guard started == noErr else {
            AudioDeviceDestroyIOProcID(device.id, proc)
            throw AudioDevices.Failure(message: "Could not start the microphone (\(started)).")
        }
        deviceCapture = (device.id, proc)
        state = .on(device.name)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.deviceCapture?.id == device.id else { return }
                self.startAgain()
            }
        }
        deviceListener = listener
        for var property in Self.inputProperties {
            AudioObjectAddPropertyListenerBlock(device.id, &property, .main, listener)
        }
    }

    private static let inputProperties = [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive].map {
        AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private nonisolated static func deviceInput(_ inbox: AudioInbox, rate: Double) -> AudioDeviceIOBlock {
        { _, input, timestamp, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
            let stamp = timestamp.pointee
            let host = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : mach_absolute_time()
            let sample = stamp.mFlags.contains(.sampleTimeValid) ? stamp.mSampleTime : HostClock.seconds(host) * rate
            inbox.put(input, channels: channels, sampleTime: sample, hostTime: host, rate: rate)
        }
    }

    private func install(on engine: AVAudioEngine) throws {
        #if SKILLI_SELFTEST
        if let standIn {
            let file = try AVAudioFile(forReading: standIn)
            let player = player ?? AVAudioPlayerNode()
            if self.player == nil {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
                // Heard by the tap only: nothing out of the speakers.
                engine.mainMixerNode.outputVolume = 0
                self.player = player
            }
            player.installTap(onBus: 0, bufferSize: 1024, format: file.processingFormat, block: Self.standInTap(inbox, player: player))
            return
        }
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioDevices.Failure(message: "The microphone has no active input channels.")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(inbox))
    }

    /// The selected input's name, as the card shows it (the self-test's
    /// stand-in: a common one, never the test Mac's own devices).
    private var deviceName: String {
        #if SKILLI_SELFTEST
        if standIn != nil { return "MacBook Pro Microphone" }
        #endif
        if let uid = selectedInputUID, let device = AudioDevices.devices(output: false).first(where: { $0.uid == uid }) {
            return device.name
        }
        return AVCaptureDevice.default(for: .audio)?.localizedName ?? "Microphone"
    }

    /// The tap off its node (the stand-in's player, else the input, which
    /// is never touched otherwise: made, it may ask for the microphone).
    private func removeTap(from engine: AVAudioEngine) {
        #if SKILLI_SELFTEST
        if standIn != nil {
            player?.removeTap(onBus: 0)
            return
        }
        #endif
        engine.inputNode.removeTap(onBus: 0)
    }

    /// The audio setup changed: the engine stopped; a new one on what the
    /// setup is now.
    private func startAgain() {
        guard engine != nil || deviceCapture != nil else { return }
        rebuildInput()
    }

    private func rebuildInput() {
        restarts += 1
        inbox.markRestart()
        dropEngine()
        startEngine(again: true)
        #if SKILLI_SELFTEST
        if standInPlaying { resumeStandIn() }
        #endif
        Log.trace("Recorder: the microphone started again (\(restarts))")
    }

    /// Route this engine alone. If a new input cannot start, restore the
    /// previous choice and leave the recording's writer running.
    func selectInput(_ uid: String?) throws {
        if let uid, !AudioDevices.devices(output: false).contains(where: { $0.uid == uid }) {
            throw AudioDevices.Failure(message: "That microphone is no longer connected.")
        }
        guard uid != selectedInputUID else { return }
        let previous = selectedInputUID
        selectedInputUID = uid
        guard engine != nil || deviceCapture != nil else { return }
        startsGivingNothing = 0
        rebuildInput()
        if case .on = state { return }
        selectedInputUID = previous
        rebuildInput()
        if case .on = state {
            throw AudioDevices.Failure(message: "Could not switch microphones. The previous input was restored.")
        }
        throw AudioDevices.Failure(message: "Could not start either microphone. Choose an available input.")
    }

    /// Start Again (the card): a new engine, or the microphone started when
    /// none runs.
    func restart() async {
        startsGivingNothing = 0
        if engine != nil || deviceCapture != nil {
            startAgain()
        } else {
            inbox.markRestart()
            await start()
        }
    }

    #if SKILLI_SELFTEST
    private var standInPlaying = false

    /// Self-test: the stand-in file plays from its start, the call's clock
    /// starting at the host time `at` (what played before is dropped), its
    /// clock `ppm` fast or slow. Played at once, never at a time: then the
    /// player's own time counts from that time and its frames come later
    /// (by 26 to 31 ms on the test Mac), where at once its time is the
    /// frame it plays.
    func playStandIn(at hostTicks: UInt64, ppm: Double = 0) throws {
        guard let standIn, let player else { return }
        let file = try AVAudioFile(forReading: standIn)
        player.stop()
        player.scheduleFile(file, at: nil)
        StandInClock.start(at: hostTicks, ppm: ppm)
        player.play()
        standInPlaying = true
    }

    /// Self-test: the engine as a change of the audio setup leaves it.
    func simulateConfigurationChange() {
        startAgain()
    }

    /// Self-test: the stand-in stops giving buffers, as an engine whose tap
    /// was refused; started again, it goes on where the call is.
    func silenceStandIn() {
        player?.stop()
    }

    /// The engine started again: an engine reset drops what its player had
    /// scheduled. The stand-in goes on where the call is now by its clock,
    /// as a microphone deaf for the moment the engine took: that moment
    /// lost, what follows in its place.
    private func resumeStandIn() {
        guard let standIn, let player, let file = try? AVAudioFile(forReading: standIn) else { return }
        player.stop()
        let from = StandInClock.rebase(at: mach_absolute_time(), rate: file.processingFormat.sampleRate)
        if from < file.length {
            player.scheduleSegment(file, startingFrame: from, frameCount: AVAudioFrameCount(file.length - from), at: nil)
        }
        player.play()
    }
    #endif

    #if SKILLI_SELFTEST
    /// The stand-in's buffers, timed as a microphone's are, by its own
    /// clock: each one's sample time the file's frame (where the player
    /// started in the file, plus its own time since: measured equal to the
    /// frame it plays), its host time that frame by the call's clock,
    /// `StandInClock.ppm` fast or slow against the host's. Nothing before
    /// the player's start.
    private nonisolated static func standInTap(_ inbox: AudioInbox, player: AVAudioPlayerNode) -> AVAudioNodeTapBlock {
        { buffer, time in
            // Before the player's start (a buffer of the schedule it
            // stopped, read after it started again): not the file's.
            guard let played = player.playerTime(forNodeTime: time), played.isSampleTimeValid, played.sampleTime >= 0 else { return }
            let rate = buffer.format.sampleRate
            let playerFrame = Int64((Double(played.sampleTime) * rate / played.sampleRate).rounded())
            guard let (host, given) = StandInClock.take(at: playerFrame, rate: rate) else { return }
            inbox.put(buffer.audioBufferList, channels: Int(buffer.format.channelCount), frames: Int(buffer.frameLength),
                      sampleTime: Double(given), hostTime: host, rate: rate)
        }
    }
    #endif

    /// AVFoundation's audio queue: the buffer into the inbox. Made outside
    /// the main actor (AGENTS.md, "Blocks macOS calls on its own queues").
    private nonisolated static func tap(_ inbox: AudioInbox) -> AVAudioNodeTapBlock {
        { buffer, time in
            let host = time.isHostTimeValid ? time.hostTime : mach_absolute_time()
            let sample = time.isSampleTimeValid ? Double(time.sampleTime) : HostClock.seconds(host) * buffer.format.sampleRate
            inbox.put(buffer.audioBufferList, channels: Int(buffer.format.channelCount), frames: Int(buffer.frameLength), sampleTime: sample,
                      hostTime: host, rate: buffer.format.sampleRate)
        }
    }
}

#if SKILLI_SELFTEST
/// The self-test's stand-in microphone's clock: when the call started
/// (host ticks), how fast the microphone runs against the host's, the
/// file's frame the player started at.
enum StandInClock {
    private struct State {
        var started: UInt64?
        var ppm = 0.0
        var from: Int64 = 0
    }

    private static let state = Mutex(State())

    static func start(at ticks: UInt64, ppm: Double) {
        state.withLock { $0 = State(started: ticks, ppm: ppm) }
    }

    /// The player starts again at `ticks` (stopped before): from where the
    /// call is by the clock, the moment it took lost. That frame.
    static func rebase(at ticks: UInt64, rate: Double) -> Int64 {
        state.withLock { clock in
            guard let started = clock.started else { return 0 }
            let elapsed = HostClock.seconds(ticks > started ? ticks - started : 0)
            clock.from = Int64((elapsed * rate * (1 + clock.ppm * 1e-6)).rounded())
            return clock.from
        }
    }

    /// The host time of the buffer at the player's own frame `player`, and
    /// the device's sample time of it: the file's frame (frames the tap
    /// missed, a gap).
    static func take(at player: Int64, rate: Double) -> (UInt64, Int64)? {
        state.withLock { clock in
            guard let started = clock.started else { return nil }
            let frame = clock.from + player
            let seconds = Double(frame) / (rate * (1 + clock.ppm * 1e-6))
            return (started + HostClock.ticks(seconds), frame)
        }
    }
}
#endif
