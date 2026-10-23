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
        standInPlaying = false
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
        state = .on(deviceName)
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

    /// The default input's name, as the card shows it (the self-test's
    /// stand-in: a common one, never the test Mac's own devices).
    private var deviceName: String {
        #if SKILLI_SELFTEST
        if standIn != nil { return "MacBook Pro Microphone" }
        #endif
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
            if standInPlaying { resumeStandIn() }
            #endif
            state = .on(deviceName)
            Log.trace("Recorder: the microphone started again (\(restarts))")
        } catch {
            Log.actions.error("Recorder: the microphone did not start again (\(error.localizedDescription, privacy: .public))")
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
