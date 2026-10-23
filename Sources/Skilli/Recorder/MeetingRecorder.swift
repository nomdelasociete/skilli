import AppKit
import AVFoundation
import SkilliCore

/// The meeting recorder (docs/meeting-recorder.md, phase 1): the
/// microphone and the Mac's sound as two tracks, written as they come,
/// each by its own clock; pause, stop, then the transcript on this Mac.
/// Made the first time it is needed, never at launch.
@MainActor
final class MeetingRecorder {
    /// The live recording.
    enum Phase: Equatable {
        case idle
        /// The Record card is open: both sources run for its meters,
        /// nothing is written.
        case listening
        case recording
        case paused
        /// Stopped: its files being closed.
        case stopping
    }

    /// A transcript being made, for the menu bar.
    struct Transcribing: Equatable {
        let folder: URL
        let title: String
        var step: MeetingTranscriber.Step
    }

    let recordings: Recordings
    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onChange?() } }
    }
    private(set) var transcribing: Transcribing? {
        didSet { if transcribing != oldValue { onChange?() } }
    }
    /// The phase or a transcript changed: the menu bar, the launcher's row.
    var onChange: (() -> Void)?
    /// A transcript is done (or waits for a language): its window opens.
    var onFinished: ((URL) -> Void)?
    /// It stopped by itself (the disk full): said in the card.
    var onStoppedByItself: ((String) -> Void)?

    /// Room for 10 s of each source, made when first listened to.
    private lazy var micInbox = AudioInbox()
    private lazy var macInbox = AudioInbox()
    private(set) lazy var microphone = MicrophoneTrack(inbox: micInbox)
    private(set) lazy var macSound = MacSoundTap(inbox: macInbox)
    /// The Mac's sound could not be tapped at all, and why.
    private(set) var macSoundFailure: String?
    private var writers: [Speaker: TrackWriter] = [:]
    private(set) var folder: URL?
    private(set) var record: MeetingRecord?
    /// The host times (seconds) it started and its open pause began.
    private var start = 0.0
    private var pausedAt: Double?
    private var pausedTotal = 0.0
    private var activity: NSObjectProtocol?
    /// Transcripts wait their turn: one at a time.
    private var queue: [(URL, MeetingRecord)] = []

    init(recordings: Recordings) {
        self.recordings = recordings
    }

    var isRecording: Bool { phase == .recording || phase == .paused }
    var title: String { record?.title ?? "" }

    /// Seconds recorded, the pauses taken out.
    var elapsed: Double {
        guard isRecording || phase == .stopping else { return 0 }
        let now = pausedAt ?? HostClock.now
        return max(0, now - start - pausedTotal)
    }

    /// Each source's level now, 0…1.
    var levels: (mic: Double, mac: Double) {
        phase == .idle ? (0, 0) : (micInbox.level, macInbox.level)
    }

    /// Seconds the Mac's sound gave only digital silence (nil: nothing came).
    var macSilentFor: Double? { phase == .idle ? nil : macInbox.silentFor }

    // MARK: - The card

    /// The Record card opened: both sources run, their meters live, nothing
    /// kept. The microphone is asked for when macOS never asked.
    func listen() async {
        guard phase == .idle else { return }
        phase = .listening
        micInbox.keeping = false
        macInbox.keeping = false
        // The microphone first: skil.li then has an audio process the tap
        // can leave out.
        await microphone.start()
        do {
            try macSound.start()
            macSoundFailure = nil
        } catch {
            macSoundFailure = error.localizedDescription
            Log.actions.error("Recorder: \(error.localizedDescription, privacy: .public)")
        }
        // Closed while macOS asked.
        if phase != .listening, !isRecording { stopSources() }
    }

    /// The card closed without ↩.
    func stopListening() {
        guard phase == .listening else { return }
        stopSources()
        phase = .idle
    }

    private func stopSources() {
        microphone.stop()
        macSound.stop()
        micInbox.keeping = false
        macInbox.keeping = false
    }

    // MARK: - Recording

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// ↩ in the card: recording from now, in a new folder.
    func begin(title: String, language: String) throws {
        guard phase == .listening else { throw Failure(message: phase == .idle ? "The Record card is not open." : "A recording is on already.") }
        let started = Date.now
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = typed.isEmpty ? RecordingFolder.defaultTitle(at: started) : typed
        let folder = try recordings.makeFolder(title: named, started: started)
        let record = MeetingRecord(title: named, started: started, language: language, recorder: Recordings.ownProcess)
        try recordings.write(record, to: folder)
        start = HostClock.now
        micInbox.keeping = true
        macInbox.keeping = true
        do {
            for speaker in Speaker.allCases {
                let writer = try TrackWriter(url: folder.appendingPathComponent(speaker.file), inbox: speaker == .me ? micInbox : macInbox,
                                             start: start, label: speaker.rawValue)
                writer.onFailure = { [weak self] error in
                    let said = error.localizedDescription
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.stoppedByItself(said) } }
                }
                writers[speaker] = writer
            }
        } catch {
            writers.values.forEach { $0.cancel() }
            writers = [:]
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        self.folder = folder
        self.record = record
        pausedAt = nil
        pausedTotal = 0
        // A call keeps the Mac and its display awake; so does a recording,
        // and macOS never naps its audio (Measured).
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled, .idleDisplaySleepDisabled], reason: "Recording a meeting")
        phase = .recording
        Log.trace("Recorder: recording “\(record.title)” in \(folder.lastPathComponent)")
    }

    /// Nothing is written to any track until Resume; the clock stops.
    func pause() {
        guard phase == .recording, var record, let folder else { return }
        let now = HostClock.now
        writers.values.forEach { $0.pause(at: now) }
        pausedAt = now
        record.state = .paused
        record.pauses.append(.init(at: max(0, now - start - pausedTotal), seconds: 0))
        self.record = record
        try? recordings.write(record, to: folder)
        phase = .paused
    }

    func resume() {
        guard phase == .paused, var record, let folder, let pausedAt else { return }
        let now = HostClock.now
        writers.values.forEach { $0.resume(at: now) }
        pausedTotal += now - pausedAt
        self.pausedAt = nil
        if let last = record.pauses.indices.last { record.pauses[last].seconds = now - pausedAt }
        record.state = .recording
        self.record = record
        try? recordings.write(record, to: folder)
        phase = .recording
    }

    /// Stops: the files closed (both end at this moment), then the
    /// transcript.
    func stop() async {
        guard isRecording, var record, let folder else { return }
        let now = HostClock.now
        if let pausedAt, let last = record.pauses.indices.last { record.pauses[last].seconds = now - pausedAt }
        phase = .stopping
        var lengths: [Double] = []
        for speaker in Speaker.allCases {
            if let writer = writers[speaker] { lengths.append(await writer.finish(at: now)) }
        }
        writers = [:]
        stopSources()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        record.seconds = lengths.max() ?? 0
        record.state = .transcribing
        record.stopped = .now
        try? recordings.write(record, to: folder)
        self.record = nil
        self.folder = nil
        pausedAt = nil
        phase = .idle
        Log.trace("Recorder: “\(record.title)” stopped, \(Int(record.seconds)) s (me \(lengths.first ?? 0), them \(lengths.last ?? 0))")
        transcribe(folder, record: record)
    }

    /// A track could not be written (the disk full): what was recorded is
    /// kept, stopped as Stop would.
    private func stoppedByItself(_ reason: String) {
        guard isRecording else { return }
        onStoppedByItself?("Recording stopped: \(reason) What was recorded is kept.")
        Task { await stop() }
    }

    // MARK: - Transcripts

    /// Makes `folder`'s transcript (one at a time), then opens it. A
    /// language this Mac cannot transcribe, or a failure: kept without one
    /// (`pending`), its window says why.
    func transcribe(_ folder: URL, record: MeetingRecord) {
        queue.append((folder, record))
        guard transcribing == nil else { return }
        Task { await transcribeNext() }
    }

    private func transcribeNext() async {
        while !queue.isEmpty {
            let (folder, record) = queue.removeFirst()
            transcribing = Transcribing(folder: folder, title: record.title, step: .transcribing(0))
            var working = record
            working.state = .transcribing
            working.recorder = Recordings.ownProcess
            try? recordings.write(working, to: folder)
            do {
                let done = try await MeetingTranscriber.transcribe(folder, record: working) { [weak self] step in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, self.transcribing?.folder == folder else { return }
                            self.transcribing?.step = step
                        }
                    }
                }
                try recordings.write(done, to: folder)
            } catch {
                var pending = working
                pending.state = .pending
                pending.engine = nil
                pending.recorder = nil
                try? recordings.write(pending, to: folder)
                Log.actions.error("Recorder: no transcript for “\(record.title, privacy: .private)” (\(error.localizedDescription, privacy: .public))")
            }
            transcribing = nil
            onFinished?(folder)
        }
    }

    /// An unfinished recording (Save in its card): its length read from its
    /// files, then its transcript.
    func save(unfinished folder: URL, record: MeetingRecord) {
        transcribe(folder, record: Self.measured(folder, record: record))
    }

    /// A recording never stopped as its files say it: how long they play
    /// (written as they came, up to their last second), when they were last
    /// written.
    nonisolated static func measured(_ folder: URL, record: MeetingRecord) -> MeetingRecord {
        var record = record
        let lengths = Speaker.allCases.map { speaker in
            (try? AVAudioFile(forReading: folder.appendingPathComponent(speaker.file))).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        }
        record.seconds = max(record.seconds, lengths.max() ?? 0)
        if record.stopped == nil {
            record.stopped = Speaker.allCases.compactMap { speaker in
                (try? folder.appendingPathComponent(speaker.file).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }.max()
        }
        return record
    }

    #if SKILLI_SELFTEST
    /// Self-test: the Mac's sound leaves these processes out too, and a
    /// file stands in for the microphone (the test Mac has none).
    func standIn(microphone file: URL?, alsoLeaveOut pids: [pid_t]) {
        microphone.standIn = file
        macSound.alsoLeftOut = pids
    }
    #endif
}
