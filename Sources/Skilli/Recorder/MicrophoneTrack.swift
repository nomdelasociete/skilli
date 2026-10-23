import AVFoundation
import Foundation
import Synchronization

/// The microphone, the user's side: macOS's default input through
/// `AVAudioEngine`. A change of the audio setup (a device plugged, the
/// default input chosen again, a rate changed) stops an engine and nothing
/// starts it again (Measured: it stopped after 62 s): it is started again
/// at once, its next buffer placed by the host clock, so the track keeps
/// its time.
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
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    #if SKILLI_SELFTEST
    /// Self-test: a file plays as the microphone (the test Mac has none),
    /// through the same engine and tap, from `playStandIn`.
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
        guard AVCaptureDevice.default(for: .audio) != nil else {
            state = .none
            return
        }
        startEngine()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let engine { removeTap(from: engine) }
        #if SKILLI_SELFTEST
        player?.stop()
        player = nil
        #endif
        engine?.stop()
        engine = nil
        if case .on = state { state = .off }
    }

    private func startEngine() {
        let engine = AVAudioEngine()
        self.engine = engine
        do {
            try install(on: engine)
            engine.prepare()
            try engine.start()
        } catch {
            Log.actions.error("Recorder: the microphone did not start (\(error.localizedDescription, privacy: .public))")
            state = .none
            return
        }
        state = .on(AVCaptureDevice.default(for: .audio)?.localizedName ?? "Microphone")
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startAgain() }
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
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(inbox))
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

    /// The audio setup changed: the engine stopped; started again on what
    /// the setup is now.
    private func startAgain() {
        guard let engine else { return }
        restarts += 1
        inbox.markRestart()
        removeTap(from: engine)
        do {
            try install(on: engine)
            try engine.start()
            #if SKILLI_SELFTEST
            if standInPlaying { player?.play() }
            #endif
            state = .on(AVCaptureDevice.default(for: .audio)?.localizedName ?? "Microphone")
            Log.trace("Recorder: the microphone started again (\(restarts))")
        } catch {
            Log.actions.error("Recorder: the microphone did not start again (\(error.localizedDescription, privacy: .public))")
        }
    }

    #if SKILLI_SELFTEST
    private var standInPlaying = false

    /// Self-test: the stand-in file plays from its start at the host time
    /// `at` (what played before is dropped), its clock `ppm` fast or slow.
    func playStandIn(at hostTicks: UInt64, ppm: Double = 0) throws {
        guard let standIn, let player else { return }
        let file = try AVAudioFile(forReading: standIn)
        player.stop()
        player.scheduleFile(file, at: nil)
        StandInClock.start(at: hostTicks, ppm: ppm)
        player.play(at: AVAudioTime(hostTime: hostTicks))
        standInPlaying = true
    }

    /// Self-test: the engine as a change of the audio setup leaves it.
    func simulateConfigurationChange() {
        startAgain()
    }
    #endif

    #if SKILLI_SELFTEST
    /// The stand-in's buffers, timed as a microphone's are, by its own
    /// clock: the frames it gave since it started (and those its tap missed
    /// while the engine started again, by the player's own time), each
    /// `StandInClock.ppm` fast or slow against the host's. A player node's
    /// tap says when its buffers will come out of the speakers, and its
    /// player time alone ran 0.5 % slow on the test Mac. Nothing before it
    /// plays.
    private nonisolated static func standInTap(_ inbox: AudioInbox, player: AVAudioPlayerNode) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let player = player
        return { buffer, time in
            guard let played = player.playerTime(forNodeTime: time), played.isSampleTimeValid else { return }
            let rate = buffer.format.sampleRate
            let playerFrame = Int64((Double(played.sampleTime) * rate / played.sampleRate).rounded())
            guard let (host, given) = StandInClock.take(Int64(buffer.frameLength), at: playerFrame, rate: rate) else { return }
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
/// The self-test's stand-in microphone's clock: when it started playing
/// (host ticks), how fast it runs against the host's, the frames it gave.
enum StandInClock {
    private struct State {
        var started: UInt64?
        var ppm = 0.0
        var given: Int64 = 0
        /// The player's own frame the next buffer should start at.
        var expected: Int64?
    }

    private static let state = Mutex(State())

    static func start(at ticks: UInt64, ppm: Double) {
        state.withLock { $0 = State(started: ticks, ppm: ppm) }
    }

    /// The host time of a buffer of `frames` the player gave at its frame
    /// `player`, and the device's sample time of it.
    static func take(_ frames: Int64, at player: Int64, rate: Double) -> (UInt64, Int64)? {
        state.withLock { clock in
            guard let started = clock.started else { return nil }
            // Frames played while the tap was off (the engine started
            // again): counted, so the track places them as a gap.
            if let expected = clock.expected, player > expected + 1 { clock.given += player - expected }
            defer {
                clock.given += frames
                clock.expected = player + frames
            }
            let seconds = Double(clock.given) / (rate * (1 + clock.ppm * 1e-6))
            return (started + HostClock.ticks(seconds), clock.given)
        }
    }
}
#endif
