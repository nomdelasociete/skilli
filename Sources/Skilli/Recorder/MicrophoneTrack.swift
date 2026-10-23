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
    /// `at` (what played before is dropped).
    func playStandIn(at hostTicks: UInt64) throws {
        guard let standIn, let player else { return }
        let file = try AVAudioFile(forReading: standIn)
        player.stop()
        player.scheduleFile(file, at: nil)
        StandInClock.started.withLock { $0 = hostTicks }
        player.play(at: AVAudioTime(hostTime: hostTicks))
        standInPlaying = true
    }

    /// Self-test: the engine as a change of the audio setup leaves it.
    func simulateConfigurationChange() {
        startAgain()
    }
    #endif

    #if SKILLI_SELFTEST
    /// The stand-in's buffers, timed as a microphone's are: when they were
    /// heard, from the player's own timeline (a player node's tap says when
    /// they will come out of the speakers). Nothing before it plays.
    private nonisolated static func standInTap(_ inbox: AudioInbox, player: AVAudioPlayerNode) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let player = player
        return { buffer, time in
            guard let played = player.playerTime(forNodeTime: time), played.isSampleTimeValid, let started = StandInClock.started.withLock({ $0 })
            else { return }
            let host = started + HostClock.ticks(Double(played.sampleTime) / played.sampleRate)
            inbox.put(buffer.audioBufferList, channels: Int(buffer.format.channelCount), frames: Int(buffer.frameLength),
                      sampleTime: Double(played.sampleTime), hostTime: host, rate: buffer.format.sampleRate)
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
/// When the self-test's stand-in started playing (host ticks).
enum StandInClock {
    static let started = Mutex<UInt64?>(nil)
}
#endif
