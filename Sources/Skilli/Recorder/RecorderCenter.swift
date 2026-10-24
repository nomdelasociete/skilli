import AppKit
import SkilliCore

/// The meeting recorder as skil.li shows it: the Record card, the menu bar
/// while recording, a recording's window, a recording never stopped found
/// at launch. The launcher, links, shortcuts and tools all come here, and
/// the meeting's Record keys (docs/meeting-recorder-views.md, phase 2):
/// the case read from the meeting and the microphone, recorded at once,
/// the call watched for its end. Made the first time one of them is used,
/// never at launch (idle memory): only a look in the Recordings folder a
/// few seconds after.
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
    /// The meeting a Record key is for now (on now, or starting within 10
    /// minutes); nil: none.
    var currentMeeting: () -> AgendaEvent? = { nil }
    /// The app a meeting's call opens in when skil.li joins it.
    var appJoining: (AgendaEvent) -> (bundleID: String, name: String)? = { _ in nil }
    /// Joins a meeting's call (the calendar's Join).
    var join: (AgendaEvent) -> Void = { _ in }
    /// Whether the user is in that meeting's call already.
    var inCall: (AgendaEvent) -> Bool = { _ in false }
    /// Who runs the microphone, followed by Core Audio's changes once a
    /// recording started (its listeners cost nothing until a device or a
    /// process changes).
    private let microphoneUse = MicrophoneUse()
    /// The call's end, watched while recording.
    private var watch = CallEndWatch()
    private var watchTimer: Timer?
    /// The moment the recording on now was started from.
    private(set) var reading: MeetingMoment.Reading?
    /// The call's app watched (the red dot's menu picks another); its pid
    /// is 0 until the app runs (a link not joined yet).
    private(set) var callApp: MicrophoneApp?
    /// The call's window: phase 3 records it; the self-test checks it.
    private(set) var callWindow: CGWindowID?
    /// Self-test: the call's end comes sooner.
    var watchTimings = (appGrace: 5.0, quietFor: 60.0)
    private lazy var card: RecordCard = {
        let card = RecordCard(recorder: recorder)
        card.onRecord = { [weak self] title, language, meeting in self?.begin(title: title, language: language, meeting: meeting) }
        card.onCancel = { [weak self] in self?.cancelled() }
        card.onStopCall = { [weak self] in self?.control(.stop) }
        card.onKeepRecording = { [weak self] reason in self?.watch.kept(reason) }
        card.onToggleSource = { [weak self] speaker in self?.toggle(speaker) }
        // An unfinished one answered (Save, Later, Discard): the next.
        card.onSave = { [weak self] folder, record in
            self?.recorder.save(unfinished: folder, record: record)
            self?.offerNext()
        }
        card.onLater = { [weak self] _, _ in self?.offerNext() }
        card.onDiscard = { [weak self] folder, record in
            self?.delete(folder, title: record.title)
            self?.offerNext()
        }
        card.onOpenPrivacy = { [weak self] permission in self?.openPrivacy(permission) }
        return card
    }()
    private lazy var indicator: RecorderIndicator = {
        let indicator = RecorderIndicator(recorder: recorder)
        indicator.onPause = { [weak self] in self?.control(.pause) }
        indicator.onResume = { [weak self] in self?.control(.resume) }
        indicator.onStop = { [weak self] in self?.control(.stop) }
        indicator.onShowFolder = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        indicator.onToggleSource = { [weak self] speaker in self?.toggle(speaker) }
        indicator.onPickApp = { [weak self] app in self?.setCallApp(app, picked: true) }
        indicator.calls = { [weak self] in
            guard let self else { return ([], nil) }
            return (self.microphoneHolders().apps, self.callApp)
        }
        return indicator
    }()
    /// Open windows by their folder's path, however the URL was written
    /// (`/var/…` or `/private/var/…`, a trailing slash or not).
    private var windows: [String: RecordingWindowController] = [:]

    private static func key(_ folder: URL) -> String {
        folder.resolvingSymlinksInPath().standardizedFileURL.path
    }
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
    func window(for folder: URL) -> RecordingWindowController? { windows[Self.key(folder)] }
    var openWindows: [RecordingWindowController] { Array(windows.values) }

    /// The launcher's row for the recording on now.
    var launcherRow: LauncherRecording? {
        guard recorder.isRecording else { return nil }
        return LauncherRecording(name: recorder.title, elapsed: recorder.elapsed, paused: recorder.phase == .paused)
    }

    // MARK: - Starting

    /// The Record card (the launcher's Record Meeting, `rec …`, a key, a
    /// link). One recording at a time: while one records, the card is not
    /// shown, one line says so. `fromOutside` (a link, a tool): opened
    /// while the user types elsewhere, it leaves the keyboard alone. While
    /// a meeting is on (or a call app runs the microphone), the card is
    /// that meeting's: its title unless one was given, its attendees, its
    /// case's sources.
    func showCard(title: String?, fromOutside: Bool = false) {
        guard !recorder.isRecording else {
            notify("Already recording “\(recorder.title)” (\(MeetingTranscript.clock(recorder.elapsed))): stop it from the menu bar first.")
            return
        }
        guard recorder.phase == .idle else { return }
        let reading = moment(for: currentMeeting())
        showCard(reading: reading, title: title, joining: false, fromOutside: fromOutside)
    }

    private func showCard(reading: MeetingMoment.Reading, title: String?, joining: Bool, fromOutside: Bool) {
        let meeting = RecordCard.Meeting(reading: reading, joins: joining)
        let name = title ?? reading.title ?? (reading.kind == .callWithoutEvent ? reading.app.map { MeetingMoment.callTitle($0, at: .now) } : nil)
        card.showRecord(title: name, askedLanguage: askedLanguage, consent: !preferences.recorderConsentShown, fromOutside: fromOutside, meeting: meeting)
    }

    /// The language a recording starts in: Settings → Recorder's, else
    /// Ask's (then the keyboard's, `MeetingTranscriber.defaultLanguage`).
    private var askedLanguage: String {
        preferences.recorderLanguage.isEmpty ? preferences.voiceLanguage : preferences.recorderLanguage
    }

    // MARK: - The moment

    /// The case now, for `event` (docs/meeting-recorder-views.md, "The
    /// five cases"): the meeting, the apps on the microphone, the app its
    /// call opens in.
    func moment(for event: AgendaEvent?) -> MeetingMoment.Reading {
        let opensIn = event.flatMap(appJoining).map { joining in
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: joining.bundleID).first
            return MicrophoneApp(bundleID: joining.bundleID, name: running?.localizedName ?? joining.name, pid: running?.processIdentifier ?? 0)
        }
        return MeetingMoment.read(event: event, microphone: microphoneHolders(), linkOpensIn: opensIn,
                                  defaults: MeetingMoment.Sources(microphone: preferences.recorderMicrophone, macSound: preferences.recorderMacSound))
    }

    /// Who runs the microphone now, read at once.
    func microphoneHolders() -> MicrophoneHolders {
        microphoneUse.holders
    }

    /// ⌘R on a meeting (its card, the launcher's row, the menu bar):
    /// recorded at once with its case's sources, then its call joined when
    /// `joining`. The first recording, before any card said that the others
    /// must agree, opens the Record card instead (`consentSaid`: the
    /// meeting card's line has just said it).
    func recordMeeting(_ event: AgendaEvent, joining: Bool, consentSaid: Bool = false) {
        guard !recorder.isRecording else {
            notify("Already recording “\(recorder.title)” (\(MeetingTranscript.clock(recorder.elapsed))): stop it from the menu bar first.")
            return
        }
        guard recorder.phase == .idle else { return }
        let reading = moment(for: event)
        guard consentSaid || preferences.recorderConsentShown else {
            showCard(reading: reading, title: nil, joining: joining, fromOutside: false)
            return
        }
        Log.trace("Recorder: ⌘R on a meeting (\(reading.kind.rawValue))\(joining ? ", joining its call" : "")")
        Task { [weak self] in
            guard let self else { return }
            let language = await MeetingTranscriber.defaultLanguage(asked: self.askedLanguage)
            self.start(reading, title: reading.title ?? "", language: language, sources: reading.sources, joining: joining)
        }
    }

    private func start(_ reading: MeetingMoment.Reading, title: String, language: String, sources: MeetingMoment.Sources, joining: Bool) {
        let start = Self.start(reading, title: title, language: language, sources: sources)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.recorder.record(start)
            } catch {
                self.notify("The recording could not start: \(error.localizedDescription)")
                return
            }
            self.preferences.recorderConsentShown = true
            self.began(reading)
            if joining, let event = reading.event { self.join(event) }
        }
    }

    /// What `reading` starts a recording with.
    private static func start(_ reading: MeetingMoment.Reading, title: String, language: String, sources: MeetingMoment.Sources) -> MeetingRecorder.Start {
        let named = title.isEmpty && reading.kind == .callWithoutEvent ? reading.app.map { MeetingMoment.callTitle($0, at: .now) } ?? "" : title
        return MeetingRecorder.Start(title: named, language: language, sources: sources, kind: reading.kind,
                                     event: reading.event.map { MeetingRecord.EventLink(id: $0.id, start: $0.start, end: $0.end) },
                                     attendees: reading.attendees, app: reading.kind == .inPerson ? nil : reading.app?.name, place: reading.place)
    }

    /// A recording started from `reading`: its call watched for its end.
    private func began(_ reading: MeetingMoment.Reading) {
        self.reading = reading
        watch = CallEndWatch(appGrace: watchTimings.appGrace, quietFor: watchTimings.quietFor)
        callApp = nil
        callWindow = nil
        if reading.kind != .inPerson, let app = reading.app { setCallApp(app, picked: false) }
        if !microphoneUse.isStarted {
            microphoneUse.onChange = { [weak self] in self?.tickWatch() }
            microphoneUse.start()
        }
        watchTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickWatch() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        reading = nil
    }

    /// Once a second while recording, from memory (the levels, what Core
    /// Audio last said): the call's app found once it runs the microphone,
    /// then the call's end.
    private func tickWatch() {
        guard recorder.isRecording, let reading else { return }
        let holders = microphoneUse.lastHolders
        // No app known yet (joining, or nothing to go on): the first on the
        // microphone is the call; the one the link opens in, once it runs.
        if reading.kind != .inPerson, callApp == nil || callApp?.pid == 0 {
            let found = callApp.flatMap { expected in holders.apps.first { $0.bundleID == expected.bundleID } }
                ?? (callApp == nil ? holders.apps.first : nil)
            if let found { setCallApp(found, picked: false) }
        }
        let levels = recorder.levels
        let sources = recorder.sources
        // The other side is the Mac's sound; in person, the microphone.
        let quiet = sources.macSound ? levels.mac < 0.02 : levels.mic < 0.02
        let app = callApp.flatMap { $0.pid == 0 ? nil : (name: $0.name, onMicrophone: holders.runs($0.pid)) }
        let end = recorder.record?.event?.end
        if let reason = watch.update(now: .now, app: app, quiet: quiet, eventEnd: end) {
            offerStop(reason)
        } else if case .callEnded(let reason)? = card.content, !watch.stillTrue(reason) {
            // The call back (a reconnect): the offer goes.
            card.dismiss()
        }
    }

    /// The call's app (nil: none), picked from the red dot's menu or found;
    /// its front window kept.
    func setCallApp(_ app: MicrophoneApp?, picked: Bool) {
        callApp = app
        callWindow = app.flatMap { $0.pid == 0 ? nil : MicrophoneUse.frontWindow(of: $0.pid) }
        watch.appChanged()
        if picked || app?.pid != 0 { recorder.setApp(app?.name) }
    }

    /// The call ended: a card offers Stop (never taking the keys from the
    /// app the user types in).
    private func offerStop(_ reason: CallEndWatch.Reason) {
        guard recorder.isRecording, !card.isVisible else { return }
        Log.trace("Recorder: the call ended (\(CallEndWatch.line(reason))): Stop offered")
        card.showCallEnded(title: recorder.title, elapsed: recorder.elapsed, line: CallEndWatch.line(reason), reason: reason)
    }

    /// A source on or off, in the card or the red dot's menu.
    private func toggle(_ speaker: Speaker) {
        let on = speaker == .me ? recorder.sources.microphone : recorder.sources.macSound
        Task { await recorder.setSource(speaker, on: !on) }
    }

    /// A tool or a skillie (`record_meeting`): the card, then what the user
    /// did with it. Nil: closed without recording.
    func showCardAndWait(title: String?) async -> String? {
        if recorder.isRecording { return "Already recording “\(recorder.title)” (\(MeetingTranscript.clock(recorder.elapsed)))." }
        waiting?.resume(returning: nil)
        return await withCheckedContinuation { continuation in
            waiting = continuation
            showCard(title: title, fromOutside: true)
            if !card.isVisible {
                waiting = nil
                continuation.resume(returning: nil)
            }
        }
    }

    private func begin(title: String, language: String, meeting: RecordCard.Meeting?) {
        do {
            let reading = meeting?.reading ?? MeetingMoment.Reading(kind: .nothing, event: nil, app: nil, sources: recorder.sources, title: nil)
            try recorder.begin(Self.start(reading, title: title, language: language, sources: recorder.sources))
            preferences.recorderConsentShown = true
            began(reading)
            if meeting?.joins == true, let event = reading.event { join(event) }
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
        if !recorder.isRecording {
            stopWatching()
            if case .callEnded? = card.content { card.dismiss() }
        }
        onChange?()
        // The window open while its transcript is made follows it.
        if let transcribing = recorder.transcribing, let window = windows[Self.key(transcribing.folder)], let record = recordings.read(transcribing.folder) {
            window.show(record, transcript: nil, transcribing: transcribing.step)
        }
    }

    // MARK: - Done

    /// A transcript made (or kept waiting for a language): its window.
    private func finished(_ folder: URL) {
        NotificationCenter.default.post(name: Recordings.changed, object: nil)
        open(folder)
    }

    /// A recording's window, opened (or brought forward and shown afresh).
    func open(_ folder: URL) {
        guard let record = recordings.read(folder) else { return }
        let transcript = recordings.transcript(folder)
        if let window = windows[Self.key(folder)] {
            window.show(record, transcript: transcript)
            window.present()
            return
        }
        let window = RecordingWindowController(folder: folder, record: record, transcript: transcript)
        window.onClose = { [weak self] controller in self?.windows[Self.key(controller.folder)] = nil }
        window.onShowFolder = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        window.onDelete = { [weak self] folder, record in
            self?.windows[Self.key(folder)]?.close()
            self?.delete(folder, title: record.title)
        }
        window.onTranscribe = { [weak self] folder, record in
            guard let self else { return }
            try? self.recordings.write(record, to: folder)
            self.recorder.transcribe(folder, record: record)
        }
        windows[Self.key(folder)] = window
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
        card.showUnfinished(folder, record: record)
    }

    #if SKILLI_SELFTEST
    /// Self-test: the card closed as esc would, without a key.
    func closeCardWithoutKeys() {
        card.closeWithoutKeys()
    }

    /// Self-test: who runs the microphone, instead of Core Audio's (nil:
    /// Core Audio again).
    func standInMicrophone(_ holders: MicrophoneHolders?) {
        microphoneUse.standInHolders = holders
    }

    /// Self-test: what the card shows now.
    var cardContent: RecordCard.Content? { card.content }

    /// Self-test: the found ones offered now, without the wait.
    func offerUnfinishedNow() -> Int {
        unfinished = recordings.unfinished().map { ($0.folder, MeetingRecorder.measured($0.folder, record: $0.record)) }
        let count = unfinished.count
        offerNext()
        return count
    }

    #endif
}
