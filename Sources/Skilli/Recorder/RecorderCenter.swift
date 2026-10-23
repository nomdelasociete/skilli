import AppKit
import SkilliCore

/// The meeting recorder as skil.li shows it: the Record card, the menu bar
/// while recording, a recording's window, a recording never stopped found
/// at launch. The launcher, links, shortcuts and tools all come here.
/// Made the first time one of them is used, never at launch (idle memory):
/// only a look in the Recordings folder a few seconds after.
@MainActor
final class RecorderCenter {
    let recordings: Recordings
    let recorder: MeetingRecorder
    private let preferences: Preferences
    private let deletes: UndoableDeletes
    /// One line in the card (a failure, said once).
    var notify: (String) -> Void = { _ in }
    /// A permission's list in System Settings.
    var openPrivacy: (Permission) -> Void = { _ in }
    /// Something the launcher's row shows changed.
    var onChange: (() -> Void)?
    private lazy var card: RecordCard = {
        let card = RecordCard(recorder: recorder)
        card.onRecord = { [weak self] title, language in self?.begin(title: title, language: language) }
        card.onCancel = { [weak self] in self?.cancelled() }
        card.onSave = { [weak self] folder, record in self?.recorder.save(unfinished: folder, record: record) }
        card.onLater = { _, _ in }
        card.onDiscard = { [weak self] folder, record in self?.delete(folder, title: record.title) }
        card.onOpenPrivacy = { [weak self] permission in self?.openPrivacy(permission) }
        return card
    }()
    private lazy var indicator: RecorderIndicator = {
        let indicator = RecorderIndicator(recorder: recorder)
        indicator.onPause = { [weak self] in self?.control(.pause) }
        indicator.onResume = { [weak self] in self?.control(.resume) }
        indicator.onStop = { [weak self] in self?.control(.stop) }
        indicator.onShowFolder = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        return indicator
    }()
    private var windows: [URL: RecordingWindowController] = [:]
    /// A tool or a skillie waiting for ↩ or esc in the card.
    private var waiting: CheckedContinuation<String?, Never>?
    /// Recordings never stopped, offered one after another.
    private var unfinished: [(URL, MeetingRecord)] = []

    init(recordings: Recordings, preferences: Preferences, deletes: UndoableDeletes) {
        self.recordings = recordings
        self.preferences = preferences
        self.deletes = deletes
        recorder = MeetingRecorder(recordings: recordings)
        recorder.onChange = { [weak self] in self?.changed() }
        recorder.onFinished = { [weak self] folder in self?.finished(folder) }
        recorder.onStoppedByItself = { [weak self] line in self?.notify(line) }
    }

    /// Self-test hooks.
    var cardView: RecordCardView { card.view }
    var cardWindow: NSWindow? { card.window }
    var isCardVisible: Bool { card.isVisible }
    var menuBar: RecorderIndicator { indicator }
    func window(for folder: URL) -> RecordingWindowController? { windows[folder] }
    var openWindows: [RecordingWindowController] { Array(windows.values) }

    /// The launcher's row for the recording on now.
    var launcherRow: LauncherRecording? {
        guard recorder.isRecording else { return nil }
        return LauncherRecording(name: recorder.title, elapsed: recorder.elapsed, paused: recorder.phase == .paused)
    }

    // MARK: - Starting

    /// The Record card (the launcher's Record Meeting, `rec …`, a key, a
    /// link). One recording at a time: while one records, the card is not
    /// shown, one line says so.
    func showCard(title: String?) {
        guard !recorder.isRecording else {
            notify("Already recording “\(recorder.title)” (\(MeetingTranscript.clock(recorder.elapsed))): stop it from the menu bar first.")
            return
        }
        guard recorder.phase == .idle else { return }
        card.showRecord(title: title, askedLanguage: preferences.voiceLanguage, consent: !preferences.recorderConsentShown)
    }

    /// A tool or a skillie (`record_meeting`): the card, then what the user
    /// did with it. Nil: closed without recording.
    func showCardAndWait(title: String?) async -> String? {
        if recorder.isRecording { return "Already recording “\(recorder.title)” (\(MeetingTranscript.clock(recorder.elapsed)))." }
        waiting?.resume(returning: nil)
        return await withCheckedContinuation { continuation in
            waiting = continuation
            showCard(title: title)
            if !card.isVisible {
                waiting = nil
                continuation.resume(returning: nil)
            }
        }
    }

    private func begin(title: String, language: String) {
        do {
            try recorder.begin(title: title, language: language)
            preferences.recorderConsentShown = true
            let started = "Recording “\(recorder.title)” started."
            waiting?.resume(returning: started)
            waiting = nil
        } catch {
            recorder.stopListening()
            notify("The recording could not start: \(error.localizedDescription)")
            waiting?.resume(returning: nil)
            waiting = nil
        }
    }

    private func cancelled() {
        recorder.stopListening()
        waiting?.resume(returning: nil)
        waiting = nil
    }

    // MARK: - While recording

    /// The menu bar, the launcher's row, a link or a tool: pause, resume,
    /// stop. Seen in the menu bar: nothing said.
    func control(_ control: SkilliLink.RecordingControl) {
        switch control {
        case .pause: recorder.pause()
        case .resume: recorder.resume()
        case .stop: Task { await recorder.stop() }
        }
    }

    /// What a tool says of the recorder now.
    var status: String {
        if recorder.isRecording {
            let state = recorder.phase == .paused ? "Paused" : "Recording"
            return "\(state) “\(recorder.title)” · \(MeetingTranscript.clock(recorder.elapsed))"
                + (recorder.folder.map { "\nFolder: \($0.path)" } ?? "")
        }
        if let transcribing = recorder.transcribing {
            let progress: String = switch transcribing.step {
            case .downloading(let language): "downloading the \(language) speech model"
            case .transcribing(let done): "\(Int((done * 100).rounded())) %"
            }
            return "Not recording. Transcribing “\(transcribing.title)”: \(progress).\nFolder: \(transcribing.folder.path)"
        }
        return "Not recording."
    }

    func showFolder() {
        if let folder = recorder.folder ?? recorder.transcribing?.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
    }

    private func changed() {
        indicator.update()
        onChange?()
        // The window open while its transcript is made follows it.
        if let transcribing = recorder.transcribing, let window = windows[transcribing.folder], let record = recordings.read(transcribing.folder) {
            window.show(record, transcript: nil, transcribing: transcribing.step)
        }
    }

    // MARK: - Done

    /// A transcript made (or kept waiting for a language): its window.
    private func finished(_ folder: URL) {
        open(folder)
    }

    /// A recording's window, opened (or brought forward and shown afresh).
    func open(_ folder: URL) {
        guard let record = recordings.read(folder) else { return }
        let transcript = recordings.transcript(folder)
        if let window = windows[folder] {
            window.show(record, transcript: transcript)
            window.present()
            return
        }
        let window = RecordingWindowController(folder: folder, record: record, transcript: transcript)
        window.onClose = { [weak self] controller in self?.windows[controller.folder] = nil }
        window.onShowFolder = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        window.onDelete = { [weak self] folder, record in
            self?.windows[folder]?.close()
            self?.delete(folder, title: record.title)
        }
        window.onTranscribe = { [weak self] folder, record in
            guard let self else { return }
            try? self.recordings.write(record, to: folder)
            self.recorder.transcribe(folder, record: record)
        }
        windows[folder] = window
        window.present()
    }

    private func delete(_ folder: URL, title: String) {
        do {
            try deletes.recording(folder, title: title)
        } catch {
            notify("“\(title)” was not moved to the Trash: \(error.localizedDescription)")
        }
    }

    // MARK: - Never stopped

    /// At launch, a few seconds in: the recordings never stopped in
    /// `root`, read off the main thread (a few small files), as their
    /// files say them. Nothing is made when there are none.
    nonisolated static func unfinished(in root: URL) async -> [(URL, MeetingRecord)] {
        await Task.detached(priority: .utility) {
            Recordings(root: root).unfinished().map { ($0.folder, MeetingRecorder.measured($0.folder, record: $0.record)) }
        }.value
    }

    /// Offered one at a time (Save, Later, Discard).
    func offer(_ found: [(URL, MeetingRecord)]) {
        guard !found.isEmpty else { return }
        unfinished = found
        offerNext()
    }

    private func offerNext() {
        guard !card.isVisible, !recorder.isRecording, !unfinished.isEmpty else { return }
        let (folder, record) = unfinished.removeFirst()
        Log.trace("Recorder: “\(record.title)” was never stopped: offered")
        card.onLater = { [weak self] _, _ in self?.offerNext() }
        card.showUnfinished(folder, record: record)
    }

    #if SKILLI_SELFTEST
    /// Self-test: the found ones offered now, without the wait.
    func offerUnfinishedNow() -> Int {
        unfinished = recordings.unfinished().map { ($0.folder, MeetingRecorder.measured($0.folder, record: $0.record)) }
        let count = unfinished.count
        offerNext()
        return count
    }

    #endif
}
