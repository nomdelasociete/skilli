import AppKit
import AVFoundation
import SkilliCore

/// The meeting recorder (docs/meeting-recorder.md, phase 1): the
/// microphone and the Mac's sound as two tracks, written as they come,
/// each by its own clock; pause, stop, then the transcript on this Mac.
/// The webcam and the screen (phase 3, `RecorderPictures`) by the same
/// moments. Made the first time it is needed, never at launch.
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

    /// What a recording starts with: its name and language, its sources,
    /// and the meeting it is of (docs/meeting-recorder-views.md, phase 2).
    struct Start {
        var title: String
        var language: String
        var sources: MeetingMoment.Sources = .both
        var kind: MeetingMoment.Kind = .nothing
        var event: MeetingRecord.EventLink?
        var attendees: [String] = []
        /// Their mail addresses, from the event: the recap mail's (phase 5).
        var addresses: [String] = []
        /// The call's app, by name.
        var app: String?
        var place: String?
        /// The screen's window, when the screen is on (the meeting's).
        var screen: ScreenWindow?
    }

    /// A transcript being made, for the menu bar.
    struct Transcribing: Equatable {
        let folder: URL
        let title: String
        var step: MeetingTranscriber.Step
        /// Made again (Transcribe Again), a transcript there before.
        var again = false
    }

    let recordings: Recordings
    private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            onChange?()
            // The meeting's files closed: the transcripts that waited for it.
            if phase == .idle { startTranscribing() }
        }
    }
    private(set) var transcribing: Transcribing? {
        didSet { if transcribing != oldValue { onChange?() } }
    }
    /// The one being made again: its record before, put back if skil.li
    /// quits meanwhile.
    private var transcribingBefore: MeetingRecord?
    /// And what it was asked with, made at the next launch then.
    private var transcribingAgain: (language: String, engine: TranscriptEngine)?
    /// The phase or a transcript changed: the menu bar, the launcher's row.
    var onChange: (() -> Void)?
    /// A transcript is done (or waits for a language): its window opens.
    var onFinished: ((URL) -> Void)?
    /// It stopped by itself (the disk full): said in the card.
    var onStoppedByItself: ((String) -> Void)?
    /// A transcript that could not be made again (the one before kept):
    /// said in the card.
    var onTranscriptFailed: ((String) -> Void)?
    /// A Stop could not finish its files: no transcript, the recording as
    /// it was (offered as never stopped, at once).
    var onLeftUnfinished: ((URL, MeetingRecord) -> Void)?

    /// Room for 10 s of each source, made when first listened to.
    private lazy var micInbox = AudioInbox()
    private lazy var macInbox = AudioInbox()
    private(set) lazy var microphone = MicrophoneTrack(inbox: micInbox)
    private(set) lazy var macSound = MacSoundTap(inbox: macInbox)
    /// The Mac's sound could not be tapped at all, and why.
    private(set) var macSoundFailure: String?
    /// Both sources started (or failed to) since the card opened: until
    /// then the Mac's sound does not count for Record.
    private(set) var sourcesStarted = false
    /// The sources on now (the card's rows, the red dot's menu).
    private(set) var sources = MeetingMoment.Sources.both
    /// The tracks on at some moment of the recording on now.
    private var everOn: Set<Speaker> = []
    /// The webcam and the screen, made the first time one is on.
    private var madePictures: RecorderPictures?
    private var writers: [Speaker: TrackWriter] = [:]
    private(set) var folder: URL?
    private(set) var record: MeetingRecord?
    /// The host times (seconds) it started and its open pause began.
    private var start = 0.0
    private var pausedAt: Double?
    private var pausedTotal = 0.0
    private var activity: NSObjectProtocol?
    /// The last recording's runs after each pause: how far each track
    /// moved to its place (seconds), its own slip from the host clock.
    private(set) var resumeJumps: [Speaker: [Double]] = [:]
    /// Transcripts wait their turn: one at a time.
    /// Transcripts waiting their turn; `again`: Transcribe Again, the
    /// transcript before kept when it fails; `engine`: the one picked.
    private var queue: [(URL, MeetingRecord, again: Bool, engine: TranscriptEngine?)] = []
    /// The default engine, whether Better transcription is downloaded,
    /// the contacts' names for its prompt: read as each transcript starts.
    var transcriptSetup: () async -> MeetingTranscriber.Setup = { MeetingTranscriber.Setup() }
    /// The transcripts' one worker, while there is one.
    private var worker: Task<Void, Never>?
    /// What a stop under way closes: the moment it stops at, the
    /// recording, its folder.
    private struct Stopping {
        let at: Double
        var record: MeetingRecord
        let folder: URL
    }

    private var stopping: Stopping?
    /// skil.li quits: nothing starts any more, every transcript not made
    /// is left for the next launch.
    private(set) var quitting = false

    init(recordings: Recordings) {
        self.recordings = recordings
    }

    var isRecording: Bool { phase == .recording || phase == .paused }

    /// The webcam and the screen (phase 3): made when first asked for.
    var pictures: RecorderPictures {
        if let madePictures { return madePictures }
        let made = RecorderPictures()
        made.onChange = { [weak self] in self?.onChange?() }
        made.onFailure = { [weak self] said in self?.stoppedByItself(said) }
        madePictures = made
        return made
    }
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

    /// The Record card opened (or ⌘R pressed): the sources on run, their
    /// meters live (the webcam's and the screen's pictures), nothing kept.
    /// The microphone is asked for when macOS never asked. A source off is
    /// not started (in person, the Mac's sound: no tap, no question); the
    /// screen is on only with a window to record.
    func listen(sources: MeetingMoment.Sources = .both, screen window: ScreenWindow? = nil) async {
        guard phase == .idle else { return }
        phase = .listening
        sourcesStarted = false
        self.sources = sources
        // The screen with a window to record, or off (one picked later).
        self.sources.screen = sources.screen && window != nil
        for inbox in [micInbox, macInbox] {
            inbox.keeping = false
            inbox.resetMeters()
        }
        // The microphone first: skil.li then has an audio process the tap
        // can leave out.
        if sources.microphone { await microphone.start() }
        if sources.macSound { startMacSound() }
        // As they are now: one turned off meanwhile stays off, a window
        // picked meanwhile stays picked.
        let screen = self.sources.screen && madePictures?.screen.window == nil ? window : nil
        if self.sources.webcam || screen != nil {
            await pictures.listen(webcam: self.sources.webcam, screen: screen)
        }
        sourcesStarted = true
        // Closed while macOS asked.
        if phase != .listening, !isRecording { stopSources() }
    }

    private func startMacSound() {
        do {
            try macSound.start()
            macSoundFailure = nil
        } catch {
            macSoundFailure = error.localizedDescription
            Log.actions.error("Recorder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A source turned on or off: in the card, or from the red dot's menu
    /// for the rest of the recording (a track off writes silence for that
    /// time, both keeping their time). Off, the microphone is released and
    /// the tap stopped.
    func setSource(_ speaker: Speaker, on: Bool) async {
        guard phase == .listening || isRecording else { return }
        let inbox = speaker == .me ? micInbox : macInbox
        switch (speaker, on) {
        case (.me, true) where !sources.microphone:
            sources.microphone = true
            inbox.markRestart()
            await microphone.start()
        case (.me, false) where sources.microphone:
            sources.microphone = false
            microphone.stop()
        case (.them, true) where !sources.macSound:
            sources.macSound = true
            inbox.markRestart()
            startMacSound()
        case (.them, false) where sources.macSound:
            sources.macSound = false
            macSound.stop()
        default:
            return
        }
        if on, isRecording { everOn.insert(speaker) }
        onChange?()
    }

    /// The webcam on or off, in the card or the red dot's menu: for the
    /// rest of the recording (off: black in its file from then on).
    func setWebcam(_ on: Bool) async {
        guard phase == .listening || isRecording, on != sources.webcam else { return }
        sources.webcam = on
        await pictures.setWebcam(on)
        onChange?()
    }

    /// The screen's window (nil: off), in the card or the red dot's menu:
    /// another one goes on in the same file.
    func setScreen(_ window: ScreenWindow?) async {
        guard phase == .listening || isRecording else { return }
        guard window != nil || sources.screen else { return }
        sources.screen = window != nil
        await pictures.setScreen(window)
        onChange?()
    }

    /// The card closed without ↩.
    func stopListening() {
        guard phase == .listening else { return }
        stopSources()
        phase = .idle
    }

    private func stopSources() {
        sourcesStarted = false
        microphone.stop()
        macSound.stop()
        madePictures?.stopAll()
        micInbox.keeping = false
        macInbox.keeping = false
    }

    // MARK: - Recording

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// ⌘R on a meeting: its sources started, then recorded from now, no
    /// card in between.
    func record(_ starting: Start) async throws {
        guard phase == .idle else { throw Failure(message: isRecording ? "A recording is on already." : "The Record card is open.") }
        await listen(sources: starting.sources, screen: starting.screen)
        guard phase == .listening else { throw Failure(message: "The recording was stopped before it started.") }
        do {
            try begin(starting)
        } catch {
            stopListening()
            throw error
        }
    }

    /// ↩ in the card: recording from now, in a new folder.
    func begin(title: String, language: String) throws {
        try begin(Start(title: title, language: language, sources: sources))
    }

    func begin(_ starting: Start) throws {
        guard !quitting else { throw Failure(message: "skil.li is quitting.") }
        guard phase == .listening else { throw Failure(message: phase == .idle ? "The Record card is not open." : "A recording is on already.") }
        let started = Date.now
        let typed = starting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = typed.isEmpty ? RecordingFolder.defaultTitle(at: started) : typed
        let folder = try recordings.makeFolder(title: named, started: started)
        var record = MeetingRecord(title: named, started: started, language: starting.language, recorder: Recordings.ownProcess)
        record.kind = starting.kind
        record.event = starting.event
        record.attendees = starting.attendees
        record.addresses = starting.addresses.isEmpty ? nil : starting.addresses
        record.app = starting.app
        record.place = starting.place
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
                #if SKILLI_SELFTEST
                writer.stalls = stalls
                #endif
                writers[speaker] = writer
            }
            try pictures.begin(folder: folder, start: start, webcam: sources.webcam, screen: sources.screen)
        } catch {
            writers.values.forEach { $0.cancel() }
            writers = [:]
            madePictures?.cancel()
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        self.folder = folder
        self.record = record
        everOn = Set(Speaker.allCases.filter { $0 == .me ? sources.microphone : sources.macSound })
        pausedAt = nil
        pausedTotal = 0
        // A call keeps the Mac and its display awake; so does a recording,
        // and macOS never naps its audio (Measured).
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled, .idleDisplaySleepDisabled], reason: "Recording a meeting")
        phase = .recording
        Log.trace("Recorder: recording “\(record.title)” in \(folder.lastPathComponent)")
    }

    /// The call's app picked from the red dot's menu (nil: none), kept in
    /// `meeting.json`.
    func setApp(_ name: String?) {
        guard isRecording, var record, let folder else { return }
        record.app = name
        self.record = record
        try? recordings.write(record, to: folder)
        onChange?()
    }

    /// Nothing is written to any track until Resume; the clock stops.
    func pause() {
        guard phase == .recording, var record, let folder else { return }
        let now = HostClock.now
        writers.values.forEach { $0.pause(at: now) }
        madePictures?.pause(at: now)
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
        madePictures?.resume(at: now)
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
        guard let stopping = beginStopping() else { return }
        // The pictures stop at this moment too, none placed past it; they
        // close by the sound's deadline.
        let picturesCloseBy = DispatchTime.now() + 1 + TrackWriter.closingTime
        let picturesClosed = madePictures.map { pictures in Task { await pictures.finish(at: stopping.at, closeBy: picturesCloseBy) } }
        #if SKILLI_SELFTEST
        // Self-test: its files take that long to close.
        if closingDelay > .zero { try? await Task.sleep(for: closingDelay) }
        #endif
        var lengths: [Double] = []
        var complete = true
        // One deadline for both tracks: their last buffers, then closing.
        let closeBy = DispatchTime.now() + 1 + TrackWriter.closingTime
        for speaker in Speaker.allCases {
            guard let writer = writers[speaker] else { continue }
            let closed = await writer.finish(at: stopping.at, waitingForSource: isOn(speaker), closeBy: closeBy)
            lengths.append(closed.seconds)
            complete = complete && closed.complete
        }
        // The pictures end at the same moment (none written: no file); a
        // picture file not whole leaves the recording as a sound file does.
        if let pictures = await picturesClosed?.value {
            complete = complete && pictures.complete
            if pictures.webcam > 0 || pictures.screen > 0 {
                Log.trace("Recorder: pictures closed, webcam \(Int(pictures.webcam)) s, screen \(Int(pictures.screen)) s, \(pictures.slides) slides")
            }
        }
        // skil.li quit meanwhile: closed there already.
        guard self.stopping?.folder == stopping.folder else { return }
        guard complete else {
            // A file not finished within the deadline (the encoder or the
            // disk stuck): never transcribed as if whole. `meeting.json` stays
            // as it was, the recording offered as never stopped.
            Log.actions.error("Recorder: a track was not finished at Stop; offered as never stopped")
            abandon()
            onLeftUnfinished?(stopping.folder, stopping.record)
            return
        }
        endStopping(lengths: lengths)
    }

    private func isOn(_ speaker: Speaker) -> Bool {
        speaker == .me ? sources.microphone : sources.macSound
    }

    /// The stop's moment, the clock stopped: nil when nothing records.
    private func beginStopping() -> Stopping? {
        guard isRecording, var record, let folder else { return nil }
        let now = HostClock.now
        if let pausedAt, let last = record.pauses.indices.last { record.pauses[last].seconds = now - pausedAt }
        let stopping = Stopping(at: now, record: record, folder: folder)
        self.stopping = stopping
        phase = .stopping
        return stopping
    }

    /// Both files closed (`lengths`, seconds): the sources released,
    /// `meeting.json` written, then the transcript.
    private func endStopping(lengths: [Double]) {
        guard let stopping else { return }
        self.stopping = nil
        var record = stopping.record
        let folder = stopping.folder
        var jumps: [Speaker: [Double]] = [:]
        for (speaker, writer) in writers { jumps[speaker] = writer.resumeJumps }
        // A track never on (in person, the Mac's sound): no lane, nothing
        // transcribed; the microphone then holds the whole room.
        let unused = Speaker.allCases.filter { !everOn.contains($0) }
        record.unused = unused.isEmpty ? nil : unused
        if unused == [.them], record.kind == .inPerson { record.speakers[Speaker.me.rawValue] = "Room" }
        resumeJumps = jumps
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
        Log.trace("Recorder: “\(record.title)” stopped, \(Int(record.seconds)) s (me \(lengths.first ?? 0), them \(lengths.last ?? 0))")
        // Its transcript first: an import made while it recorded waits.
        transcribe(folder, record: record, first: true)
        phase = .idle
    }

    /// Stops as `stop()` does (a stop under way too), holding the main
    /// thread until both files are closed: the sources' last buffers (a
    /// second at most), what is left encoded and the files finished, 5 s at
    /// most for all of it (the encoder or the disk may never answer). A file not whole and finished by then: `meeting.json` stays
    /// as it was while recording (`recording` or `paused`), no transcript,
    /// so the next launch offers it as never stopped (Save, Later, Discard;
    /// its length read from its files) instead of transcribing a file that
    /// may lack its end.
    private func stopNow() {
        guard let stopping = self.stopping ?? beginStopping() else { return }
        // One deadline for all of it: the last buffers, what is left to
        // encode, the files finished.
        let deadline = DispatchTime.now() + TrackWriter.closingTime
        let tracks = Speaker.allCases.compactMap { speaker in writers[speaker].map { (speaker, $0) } }
        for (_, writer) in tracks { writer.markStop(at: stopping.at) }
        madePictures?.markStop(at: stopping.at)
        let arrival = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < arrival, !tracks.allSatisfy({ !isOn($0.0) || $0.1.hasArrived(upTo: stopping.at, until: deadline) }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let lengths = tracks.map { $0.1.closeNow(until: deadline) }
        let pictured = madePictures?.finishNow(at: stopping.at, until: deadline) ?? true
        guard lengths.allSatisfy({ $0 != nil }), pictured else {
            Log.actions.error("Recorder: a track was not finished as skil.li quit; offered at the next launch")
            abandon()
            return
        }
        endStopping(lengths: lengths.compactMap { $0 })
    }

    /// The recording let go as it is, `meeting.json` untouched: found at
    /// the next launch as one never stopped.
    private func abandon() {
        stopping = nil
        writers = [:]
        stopSources()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        record = nil
        folder = nil
        pausedAt = nil
        phase = .idle
    }

    // MARK: - Quitting

    /// skil.li quits (docs/meeting-recorder.md, "Quit and sleep"), from
    /// `applicationShouldTerminate`: a recording on, or a stop under way,
    /// is closed as Stop closes it, both files whole, before it answers
    /// (about a second, the main thread held: the quit may come from a job
    /// of the main queue, where a close waiting for another job would never
    /// run); every transcript not made yet is left `stopped` for the next
    /// launch. Nothing asked.
    func closeForQuit() {
        quitting = true
        if phase == .listening { stopListening() }
        if isRecording || phase == .stopping { stopNow() }
        // The one being made and those waiting their turn (one finishing
        // meanwhile is written done). One to be made again keeps its
        // transcript as it was (waiting, nothing of it was written; being
        // made, its record before is put back) and is made again at the
        // next launch, as asked.
        var left = queue.filter { !$0.again }.map(\.0)
        let again = queue.filter(\.again)
        queue = []
        if let transcribing {
            if let before = transcribingBefore {
                try? recordings.write(before.keepingRuns(of: recordings.read(transcribing.folder)), to: transcribing.folder)
                if let asked = transcribingAgain { leaveAgain(transcribing.folder, asked.language, asked.engine) }
            } else {
                left.insert(transcribing.folder, at: 0)
            }
        }
        for folder in left {
            if let record = recordings.read(folder) { leave(folder, record: record) }
        }
        for job in again {
            leaveAgain(job.0, job.1.language, job.engine ?? TranscriptEngine(stored: job.1.engine) ?? .macOS)
        }
    }

    /// A Transcribe Again kept for the next launch: its transcript as it
    /// is, what was asked noted (`madeAgain`).
    private func leaveAgain(_ folder: URL, _ language: String, _ engine: TranscriptEngine) {
        guard var record = recordings.read(folder) else { return }
        record.madeAgain = MeetingRecord.MadeAgain(language: language, engine: engine.rawValue)
        try? recordings.write(record, to: folder)
        Log.trace("Recorder: “\(record.title)” left to be transcribed again at the next launch")
    }

    /// Kept for the next launch's transcript: `stopped`, nobody's.
    private func leave(_ folder: URL, record: MeetingRecord) {
        var record = record
        record.state = .stopped
        record.recorder = nil
        try? recordings.write(record, to: folder)
        Log.trace("Recorder: “\(record.title)” left for the next launch's transcript")
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
    /// (`pending`), its window says why. While a meeting records, it waits
    /// for that meeting's transcript (docs/meeting-recorder-views.md,
    /// "Import"); `first`: that meeting's, ahead of them.
    func transcribe(_ folder: URL, record: MeetingRecord, again: Bool = false, engine: TranscriptEngine? = nil, first: Bool = false) {
        guard !quitting else { return leave(folder, record: record) }
        let job = (folder, record, again: again, engine: engine)
        if first { queue.insert(job, at: 0) } else { queue.append(job) }
        startTranscribing()
    }

    /// One worker for them all: several asked at once (the launch's) wait
    /// their turn; none while a meeting records or its files close.
    private func startTranscribing() {
        guard worker == nil, !queue.isEmpty, phase == .idle || phase == .listening else { return }
        worker = Task {
            await transcribeNext()
            worker = nil
        }
    }

    /// Whether `folder`'s transcript waits its turn (another being made).
    func waits(_ folder: URL) -> Bool {
        let key = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return queue.contains { $0.0.resolvingSymlinksInPath().standardizedFileURL.path == key }
    }

    /// Whether `folder`'s transcript is being made again, or waits its turn
    /// to be (Transcribe Again): the one there now is to be replaced.
    func makesAgain(_ folder: URL) -> Bool {
        let key = folder.resolvingSymlinksInPath().standardizedFileURL.path
        if let transcribing, transcribing.again, transcribing.folder.resolvingSymlinksInPath().standardizedFileURL.path == key { return true }
        return queue.contains { $0.again && $0.0.resolvingSymlinksInPath().standardizedFileURL.path == key }
    }

    private func transcribeNext() async {
        // A meeting starting meanwhile: the next waits for its transcript.
        while !queue.isEmpty, !quitting, phase == .idle || phase == .listening {
            let (folder, record, again, engine) = queue.removeFirst()
            // The job is this one before anything is awaited: another asked
            // meanwhile waits in the queue.
            transcribing = Transcribing(folder: folder, title: record.title, step: .transcribing(0), again: again)
            // Made again: the record as it is before, put back if it fails.
            let before = again ? recordings.read(folder).map { record in
                var before = record
                before.madeAgain = nil
                return before
            } : nil
            transcribingBefore = before?.state == .done ? before : nil
            transcribingAgain = again ? (record.language, engine ?? TranscriptEngine(stored: record.engine) ?? .macOS) : nil
            let setup = await transcriptSetup()
            // Quit meanwhile: closeForQuit left it as it should be.
            if quitting {
                transcribing = nil
                transcribingBefore = nil
                transcribingAgain = nil
                break
            }
            // Each write keeps the skillies' runs as they are on disk: one
            // may finish while the transcript is made. Made again: from the
            // record as it is now (chapters, a summary written while it
            // waited its turn), in the language picked.
            var working = record.keepingRuns(of: recordings.read(folder))
            if again, var now = recordings.read(folder) {
                now.language = record.language
                // Made now: not again at the next launch, whatever comes of it.
                now.madeAgain = nil
                working = now
            }
            working.state = .transcribing
            working.recorder = Recordings.ownProcess
            try? recordings.write(working, to: folder)
            do {
                let done = try await MeetingTranscriber.transcribe(folder, record: working, picked: engine, setup: setup) { [weak self] step in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, self.transcribing?.folder == folder else { return }
                            self.transcribing?.step = step
                        }
                    }
                }
                try recordings.write(done.keepingRuns(of: recordings.read(folder)), to: folder)
            } catch where before?.state == .done && recordings.transcript(folder) != nil {
                // Transcribe Again that failed: the transcript before stays.
                if let before { try? recordings.write(before.keepingRuns(of: recordings.read(folder)), to: folder) }
                onTranscriptFailed?("The transcript was not made again: \(error.localizedDescription) The one before is kept.")
                Log.actions.error("Recorder: “\(record.title, privacy: .private)” not transcribed again (\(error.localizedDescription, privacy: .public))")
            } catch {
                var pending = working
                pending.state = .pending
                pending.engine = nil
                pending.recorder = nil
                try? recordings.write(pending.keepingRuns(of: recordings.read(folder)), to: folder)
                Log.actions.error("Recorder: no transcript for “\(record.title, privacy: .private)” (\(error.localizedDescription, privacy: .public))")
            }
            transcribing = nil
            transcribingBefore = nil
            transcribingAgain = nil
            // Quitting: its window is not opened as skil.li goes.
            if !quitting { onFinished?(folder) }
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
    /// Self-test: Stop takes this long to close the files (⌘R pressed
    /// meanwhile).
    var closingDelay: Duration = .zero
    /// Self-test: what gets stuck as the next recording's files close.
    var stalls: TrackWriter.Stall?

    /// Self-test: the Mac's sound leaves these processes out too, and a
    /// file stands in for the microphone (the test Mac has none).
    func standIn(microphone file: URL?, alsoLeaveOut pids: [pid_t]) {
        microphone.standIn = file
        macSound.alsoLeftOut = pids
    }

    /// Self-test: a camera drawn here stands in for one (nil: the real one).
    func standIn(camera: StandInCamera?) {
        pictures.webcam.standIn = camera
    }
    #endif
}
