import AppKit
import AVFoundation
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
    /// The recordings moving to another folder now (Settings → Recorder),
    /// how far: no recording starts meanwhile (its folder would be left
    /// behind).
    var recordingsMoving: () -> (done: Int, of: Int)? = { nil }
    /// The user's own name (My Card in Contacts, when allowed): offered
    /// first for Me in a recording's window.
    var ownName: () async -> String? = { nil }
    /// The contacts' names in Dictate's order: Better transcription's
    /// prompt after the attendees (never sent anywhere).
    var contactNames: () async -> [String] = { [] }
    /// A pane of Settings (Better transcription's line in a window).
    var openSettings: (SettingsPane) -> Void = { _ in }
    /// What the user does with a recording once written out (phase 5): the
    /// summary, chapters, action items, the recap mail.
    private(set) lazy var followUps: RecordingFollowUps = {
        let followUps = RecordingFollowUps(recordings: recordings, deletes: deletes)
        followUps.window = { [weak self] folder in self?.window(for: folder) }
        followUps.reshow = { [weak self] folder in self?.reshow(folder) }
        followUps.isBeingMade = { [weak self] folder in self?.recorder.makesAgain(folder) ?? false }
        followUps.notify = { [weak self] line in self?.notify(line) }
        return followUps
    }()

    /// Why a recording cannot start now, said: nil when it can.
    private var notNow: String? {
        if recorder.isRecording {
            return "Already recording “\(recorder.title)” (\(MeetingTranscript.clock(recorder.elapsed))): stop it from the menu bar first."
        }
        if let moving = recordingsMoving() {
            return "Your recordings are moving to another folder (\(moving.done) of \(moving.of)): record once they have moved."
        }
        return nil
    }
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
    /// What was asked while the last recording still closed its files (⌘R,
    /// the Record card): done once they are closed, never dropped.
    private var afterClosing: [() -> Void] = []
    /// ⌘R's recording is being started (its language read, its sources
    /// started): another ⌘R meanwhile asks the same.
    private var starting = false {
        didSet {
            holdMenuBar()
            // Started or failed to: one never stopped, asked meanwhile, is
            // offered once nothing records (`offerNext` checks).
            if !starting { offerNext() }
        }
    }
    private lazy var card: RecordCard = {
        let card = RecordCard(recorder: recorder)
        card.onRecord = { [weak self] title, language, meeting in self?.begin(title: title, language: language, meeting: meeting) }
        card.onCancel = { [weak self] in self?.cancelled() }
        card.onStop = { [weak self] in self?.control(.stop) }
        card.onResume = { [weak self] in self?.control(.resume) }
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
        card.pictures = recorder.pictures
        card.onTogglePicture = { [weak self] source in self?.togglePicture(source) }
        card.onPickWindow = { [weak self] window in self?.pickWindow(window) }
        card.windows = { [weak self] in (self?.meetingWindow, ScreenWindows.list()) }
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
        indicator.pictures = recorder.pictures
        indicator.onTogglePicture = { [weak self] source in self?.togglePicture(source) }
        indicator.onPickWindow = { [weak self] window in self?.pickWindow(window) }
        indicator.windows = { [weak self] in (self?.meetingWindow, ScreenWindows.list()) }
        return indicator
    }()
    /// The meeting's window for the screen (phase 3), once found: the
    /// call's app's, in a browser the one holding the meeting's tab.
    private(set) var meetingWindow: ScreenWindow?
    /// The meeting's tab, when it can be brought forward as recording
    /// starts (a browser that skil.li scripts).
    private var meetingTab: (tab: Quicklink.OpenTab, bundleID: String)?
    /// Each Record card shown: a window lookup answering for an earlier
    /// card (or another recording) gives up.
    private var cardSession = 0

    /// What a window lookup found: the window, the card's line, whether
    /// ⌘↩ opens Automation, the meeting's tab when it can come forward.
    private struct FoundWindow {
        var window: ScreenWindow?
        var note: String?
        var automation = false
        var tab: (tab: Quicklink.OpenTab, bundleID: String)?
    }

    /// The card and the recording a lookup is for, as it starts.
    private var lookupMoment: (card: Int, folder: URL?) { (cardSession, recorder.folder) }

    /// Whether the card and the recording are still those `moment` named.
    private func still(_ moment: (card: Int, folder: URL?)) -> Bool {
        moment.card == cardSession && moment.folder == recorder.folder
    }

    /// A lookup's answer, for the card or the recording on now.
    private func use(_ found: FoundWindow) {
        meetingWindow = found.window
        meetingTab = found.tab
    }
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
    /// Transcripts made at launch for recordings closed as skil.li quit:
    /// no window opens when done (nobody asked for it then).
    private var madeQuietly: Set<String> = []
    /// Transcripts made again (Transcribe Again): the skillie marked does
    /// not run on them again.
    private var madeAgain: Set<String> = []
    /// When the Mac went to sleep, the recording on paused for it; nil when
    /// it did not pause one (none on, or already paused by the user).
    private(set) var pausedForSleep: Date?
    private var observers: [NSObjectProtocol] = []

    init(recordings: Recordings, preferences: Preferences, deletes: UndoableDeletes) {
        self.recordings = recordings
        self.preferences = preferences
        self.deletes = deletes
        recorder = MeetingRecorder(recordings: recordings)
        recorder.onChange = { [weak self] in self?.changed() }
        recorder.onFinished = { [weak self] folder in self?.finished(folder) }
        recorder.onStoppedByItself = { [weak self] line in self?.notify(line) }
        recorder.onTranscriptFailed = { [weak self] line in self?.notify(line) }
        recorder.transcriptSetup = { [weak self] in
            guard let self else { return MeetingTranscriber.Setup() }
            let ready = BetterTranscription.isReady()
            return MeetingTranscriber.Setup(standard: TranscriptEngine.standard(preferred: TranscriptEngine(stored: self.preferences.recorderEngine),
                                                                                whisperReady: ready),
                                            whisperReady: ready, contacts: ready ? await self.contactNames() : [])
        }
        recorder.onLeftUnfinished = { [weak self] folder, record in self?.offerAtOnce(folder, record: record) }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.macWillSleep() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.macDidWake() }
        })
    }

    // MARK: - Sleep

    /// The Mac goes to sleep (the lid closed, Sleep, the battery out): the
    /// recording on is paused as Pause does, both tracks at that moment
    /// (docs/meeting-recorder.md, "Quit and sleep"). One the user paused
    /// stays as it is.
    private func macWillSleep() {
        guard recorder.phase == .recording else { return }
        recorder.pause()
        pausedForSleep = .now
        Log.trace("Recorder: “\(recorder.title)” paused as the Mac goes to sleep")
    }

    /// Awake: never resumed by itself (whoever is in the room now has not
    /// agreed); the card offers Resume ↩, Stop ⌘↩, Keep Paused esc. It
    /// takes the place of a call's end card left from before the sleep
    /// (offered again if the call is still over).
    private func macDidWake() {
        guard let asleep = pausedForSleep else { return }
        pausedForSleep = nil
        guard recorder.phase == .paused else { return }
        // A call's end card it replaces: offered again once this one is
        // answered and the recording goes on, if the call is still over.
        watch.offerAgain()
        card.showSlept(title: recorder.title, elapsed: recorder.elapsed,
                       line: "The Mac went to sleep at \(asleep.formatted(date: .omitted, time: .shortened)).")
    }

    /// Self-test hooks.
    var cardView: RecordCardView { card.view }
    var cardWindow: NSWindow? { card.window }
    var isCardVisible: Bool { card.isVisible }
    var menuBar: RecorderIndicator { indicator }
    func window(for folder: URL) -> RecordingWindowController? { windows[Self.key(folder)] }

    /// Better transcription downloaded: no window offers it any more.
    func betterTranscriptionReady() {
        for window in windows.values { window.hideBetterHint() }
    }
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
        if let notNow {
            notify(notNow)
            return
        }
        // The last one still closing its files: the card once they are.
        if recorder.phase == .stopping {
            whenClosed { [weak self] in self?.showCard(title: title, fromOutside: fromOutside) }
            return
        }
        guard recorder.phase == .idle, !starting else { return }
        let reading = moment(for: currentMeeting())
        showCard(reading: reading, title: title, joining: false, fromOutside: fromOutside)
    }

    private func showCard(reading: MeetingMoment.Reading, title: String?, joining: Bool, fromOutside: Bool) {
        let meeting = RecordCard.Meeting(reading: reading, joins: joining)
        let name = title ?? reading.title ?? (reading.kind == .callWithoutEvent ? reading.app.map { MeetingMoment.callTitle($0, at: .now) } : nil)
        meetingWindow = nil
        meetingTab = nil
        cardSession += 1
        card.showRecord(title: name, askedLanguage: askedLanguage, consent: !preferences.recorderConsentShown, fromOutside: fromOutside, meeting: meeting)
        startScreenForCard(reading)
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
                                  defaults: MeetingMoment.Sources(microphone: preferences.recorderMicrophone, macSound: preferences.recorderMacSound,
                                                                  webcam: preferences.recorderWebcam, screen: preferences.recorderScreen))
    }

    // MARK: - The pictures (phase 3)

    /// The meeting's window and what the card says of it: the call's
    /// app's front window, in a browser the window holding the meeting's
    /// tab (`MeetingTabSelect`; macOS's question for Automation, never
    /// asked, comes now). Nil: no window known (in person, nothing to go
    /// on, an app not running yet).
    /// Nothing is changed here: the caller applies the answer (`use`)
    /// once it knows it is still for the same card and recording.
    private func findMeetingWindow(_ reading: MeetingMoment.Reading) async -> FoundWindow {
        #if SKILLI_SELFTEST
        if let standIn = standInMeetingWindow {
            try? await Task.sleep(for: standIn.after)
            return FoundWindow(window: standIn.window)
        }
        #endif
        guard reading.kind != .inPerson, let app = reading.app, app.pid != 0 else { return FoundWindow() }
        let front = MicrophoneUse.frontWindow(of: app.pid).flatMap(ScreenWindows.window)
        guard MeetingTabSelect.isBrowser(app.bundleID), let link = reading.event?.meeting?.url else {
            return FoundWindow(window: front, note: front == nil ? nil : "Keep the call's window in sight: a minimized or hidden window gives no picture.")
        }
        let asks = BrowserTabReuse.browsers[app.bundleID] != nil && AutomationAccess.state(of: app.bundleID) == .notAsked
        let plan = await card.whileMacOSAsks(asks && card.isVisible) { await MeetingTabSelect.plan(for: link, in: app) }
        switch plan {
        case .tab(let tab, let id):
            return FoundWindow(window: id.flatMap(ScreenWindows.window) ?? front,
                               note: "The meeting's tab comes forward as recording starts; a tab you pick later is recorded instead. Keep its window in sight.",
                               tab: (tab, app.bundleID))
        case .cannot(let line, let automation):
            return FoundWindow(window: front, note: line, automation: automation)
        }
    }

    /// The webcam's or the screen's row clicked, or its item in the red
    /// dot's menu: on or off. The screen on records the meeting's window,
    /// else the card's list opens to pick one.
    private func togglePicture(_ source: PictureSource) {
        switch source {
        case .webcam:
            let on = !recorder.sources.webcam
            Log.trace("Recorder: the webcam turned \(on ? "on" : "off")")
            let asks = on && AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
                && (AVCaptureDevice.systemPreferredCamera ?? AVCaptureDevice.default(for: .video)) != nil
            Task { await card.whileMacOSAsks(asks && card.isVisible) { await recorder.setWebcam(on) } }
        case .screen:
            guard !recorder.sources.screen else {
                Task {
                    await recorder.setScreen(nil)
                    card.setScreenNote(nil, automation: false)
                }
                return
            }
            Task {
                let asked = lookupMoment
                let found = await findMeetingWindow(card.meetingReading ?? self.reading ?? moment(for: nil))
                guard still(asked) else { return }
                use(found)
                if let window = found.window {
                    await card.whileMacOSAsks(!ScreenTrack.isAllowed && card.isVisible) { await recorder.setScreen(window) }
                    card.setScreenNote(found.note, automation: found.automation)
                } else if card.isVisible, card.content == .record {
                    card.showWindows()
                }
            }
        }
    }

    /// `set_recording_source` (a tool, a skillie): a source on or off while
    /// the card is open or a recording is on; the screen on records the
    /// meeting's window, said when none is known.
    func setSource(_ source: String, on: Bool) async throws -> String {
        guard recorder.isRecording || recorder.phase == .listening else { throw MeetingRecorder.Failure(message: "No recording is on, and the Record card is not open.") }
        let sources = recorder.sources
        switch source {
        case "microphone":
            if sources.microphone != on { await recorder.setSource(.me, on: on) }
        case "mac_sound":
            if sources.macSound != on { await recorder.setSource(.them, on: on) }
        case "webcam":
            // macOS's question for the camera over the card, never under it.
            let asks = on && card.isVisible && AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
                && (AVCaptureDevice.systemPreferredCamera ?? AVCaptureDevice.default(for: .video)) != nil
            await card.whileMacOSAsks(asks) { await recorder.setWebcam(on) }
        case "screen":
            if !on {
                await recorder.setScreen(nil)
            } else if !sources.screen {
                let asked = lookupMoment
                let found = await findMeetingWindow(card.meetingReading ?? reading ?? moment(for: nil))
                guard still(asked) else { throw MeetingRecorder.Failure(message: "The recording changed while its window was looked for: nothing turned on.") }
                use(found)
                guard let window = found.window else {
                    throw MeetingRecorder.Failure(message: "No meeting's window is known: pick one in the Record card or the red dot's menu (Screen).")
                }
                await card.whileMacOSAsks(!ScreenTrack.isAllowed && card.isVisible) { await recorder.setScreen(window) }
                card.setScreenNote(found.note, automation: found.automation)
            }
        default:
            throw MeetingRecorder.Failure(message: "No source “\(source)”: microphone, mac_sound, webcam or screen.")
        }
        let now = recorder.sources
        let (named, state): (String, Bool) = switch source {
        case "microphone": ("The microphone", now.microphone)
        case "mac_sound": ("The Mac's sound", now.macSound)
        case "webcam": ("The webcam", now.webcam)
        default: ("The screen", now.screen)
        }
        return "\(named) \(state ? "on" : "off")."
    }

    /// A window picked for the screen (the card's list, the red dot's
    /// menu): recorded from now on.
    private func pickWindow(_ window: ScreenWindow) {
        Task {
            await card.whileMacOSAsks(!ScreenTrack.isAllowed && card.isVisible) { await recorder.setScreen(window) }
            // Another window than the meeting's: its tab is not this one's.
            if window.id != meetingWindow?.id {
                meetingTab = nil
                card.setScreenNote(nil, automation: false)
            }
        }
    }

    /// The card opened with the screen on (Settings → Recorder): the
    /// meeting's window found, then recorded; none known, the screen stays
    /// off for a click.
    private func startScreenForCard(_ reading: MeetingMoment.Reading) {
        guard reading.sources.screen else { return }
        // This card's, taken now (before another card can open).
        let asked = lookupMoment
        Task {
            let found = await findMeetingWindow(reading)
            // Another card opened meanwhile (this one closed): not its window.
            guard still(asked) else { return }
            use(found)
            guard let window = found.window, recorder.phase == .listening, card.content == .record else { return }
            await card.whileMacOSAsks(!ScreenTrack.isAllowed) { await recorder.setScreen(window) }
            card.setScreenNote(found.note, automation: found.automation)
        }
    }

    /// The meeting's tab in front of its window, as recording starts:
    /// selected, never reloaded, the browser left where it is.
    private func bringMeetingTabForward() {
        guard let meetingTab, recorder.sources.screen, recorder.pictures.screen.window?.id == meetingWindow?.id else { return }
        _ = MeetingTabSelect.select(meetingTab.tab, in: meetingTab.bundleID)
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
        if let notNow {
            notify(notNow)
            return
        }
        // The last one still closing its files (a second or so): this one
        // records once they are closed, the dot staying meanwhile.
        if recorder.phase == .stopping {
            Log.trace("Recorder: ⌘R while the last recording closes: recorded once it is closed")
            whenClosed { [weak self] in self?.recordMeeting(event, joining: joining, consentSaid: consentSaid) }
            return
        }
        // The Record card open: ⌘R on the meeting is that recording.
        if recorder.phase == .listening, card.content == .record {
            card.dismiss()
            cancelled()
        }
        // Pressed twice: the first is being started.
        guard recorder.phase == .idle, !starting else { return }
        let reading = moment(for: event)
        guard consentSaid || preferences.recorderConsentShown else {
            showCard(reading: reading, title: nil, joining: joining, fromOutside: false)
            return
        }
        Log.trace("Recorder: ⌘R on a meeting (\(reading.kind.rawValue))\(joining ? ", joining its call" : "")")
        starting = true
        Task { [weak self] in
            guard let self else { return }
            let language = await MeetingTranscriber.defaultLanguage(asked: self.askedLanguage)
            #if SKILLI_SELFTEST
            if self.startDelay > .zero { try? await Task.sleep(for: self.startDelay) }
            #endif
            self.start(reading, title: reading.title ?? "", language: language, sources: reading.sources, joining: joining)
        }
    }

    private func start(_ reading: MeetingMoment.Reading, title: String, language: String, sources: MeetingMoment.Sources, joining: Bool) {
        let start = Self.start(reading, title: title, language: language, sources: sources)
        Task { [weak self] in
            guard let self else { return }
            // The sound from the key on; the meeting's window looked for
            // after (Automation's question, a browser slow to answer: seconds
            // the call would lose), the screen joining once it is found.
            do {
                #if SKILLI_SELFTEST
                if self.startFails {
                    self.startFails = false
                    throw MeetingRecorder.Failure(message: "the self-test's start failed.")
                }
                #endif
                try await self.recorder.record(start)
            } catch {
                self.starting = false
                self.notify("The recording could not start: \(error.localizedDescription)")
                return
            }
            self.starting = false
            self.preferences.recorderConsentShown = true
            self.began(reading)
            if joining, let event = reading.event { self.join(event) }
            if sources.screen { await self.addMeetingScreen(reading) }
        }
    }

    /// The screen on for a recording ⌘R started: the meeting's window,
    /// once found, recorded from then on, its tab brought forward.
    private func addMeetingScreen(_ reading: MeetingMoment.Reading) async {
        // The recording this window is for: another one started meanwhile
        // never gets it.
        let asked = lookupMoment
        let found = await findMeetingWindow(reading)
        guard asked.folder != nil, still(asked) else { return }
        use(found)
        guard let window = found.window, recorder.isRecording, !recorder.sources.screen else { return }
        await recorder.setScreen(window)
        bringMeetingTabForward()
    }

    /// What `reading` starts a recording with.
    private static func start(_ reading: MeetingMoment.Reading, title: String, language: String, sources: MeetingMoment.Sources) -> MeetingRecorder.Start {
        let named = title.isEmpty && reading.kind == .callWithoutEvent ? reading.app.map { MeetingMoment.callTitle($0, at: .now) } ?? "" : title
        return MeetingRecorder.Start(title: named, language: language, sources: sources, kind: reading.kind,
                                     event: reading.event.map { MeetingRecord.EventLink(id: $0.id, start: $0.start, end: $0.end) },
                                     attendees: reading.attendees, addresses: reading.event?.attendees.compactMap(\.email) ?? [],
                                     app: reading.kind == .inPerson ? nil : reading.app?.name, place: reading.place)
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

    /// `run` once the last recording's files are closed.
    private func whenClosed(_ run: @escaping () -> Void) {
        afterClosing.append(run)
        holdMenuBar()
    }

    /// The menu bar keeps its dot between a recording closing and the one
    /// asked for meanwhile starting.
    private func holdMenuBar() {
        indicator.holding = starting || !afterClosing.isEmpty
        indicator.update()
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
        if let notNow { return notNow }
        // The last one still closing its files: the card once they are.
        if recorder.phase == .stopping {
            await withCheckedContinuation { (closed: CheckedContinuation<Void, Never>) in whenClosed { closed.resume() } }
        }
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
            // Recording from ↩: the tab then (a browser slow to answer
            // never delays the start).
            bringMeetingTabForward()
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
        // Resumed or stopped from the menu bar: the card at wake goes.
        if card.content == .slept, recorder.phase != .paused { card.dismiss() }
        // Closed: what was asked meanwhile, in order.
        if recorder.phase == .idle, !afterClosing.isEmpty {
            let asked = afterClosing
            afterClosing = []
            asked.forEach { $0() }
            holdMenuBar()
        }
        // One never stopped, asked while another recorded: offered now.
        if recorder.phase == .idle, !starting, !unfinished.isEmpty { offerNext() }
        onChange?()
        // The window open while its transcript is made follows it.
        if let transcribing = recorder.transcribing, let window = windows[Self.key(transcribing.folder)], let record = recordings.read(transcribing.folder) {
            window.show(record, transcript: nil, transcribing: transcribing.step)
        }
    }

    // MARK: - Done

    /// A transcript made (or kept waiting for a language): its window. One
    /// made at launch for a recording closed as skil.li quit opens none:
    /// the lists have it; a window already open on it shows it.
    private func finished(_ folder: URL) {
        NotificationCenter.default.post(name: Recordings.changed, object: nil)
        // A first transcript: the skillie marked runs on it (phase 5).
        if madeAgain.remove(Self.key(folder)) == nil { followUps.transcriptDone(folder) }
        if madeQuietly.remove(Self.key(folder)) != nil {
            if let window = windows[Self.key(folder)], let record = recordings.read(folder) {
                window.show(record, transcript: recordings.transcript(folder))
            }
            return
        }
        open(folder)
    }

    /// A recording's window, opened (or brought forward and shown afresh);
    /// `at` seconds in, playing from the line said then.
    func open(_ folder: URL, at: Double? = nil) {
        guard let record = recordings.read(folder) else { return }
        let window: RecordingWindowController
        if let open = windows[Self.key(folder)] {
            window = open
            show(window, record, folder)
        } else {
            window = makeWindow(folder, record: record, transcript: recordings.transcript(folder))
            if isBeingMade(folder) { show(window, record, folder) }
        }
        window.present()
        if let at { window.play(from: at) }
    }

    /// An open window shows its recording as it is now (`reshow`: after a
    /// follow-up, Transcribe Again asked).
    private func reshow(_ folder: URL) {
        guard let window = windows[Self.key(folder)], let record = recordings.read(folder) else { return }
        show(window, record, folder)
    }

    /// The transcript on disk; while one is made again, or waits its turn,
    /// where that is: never the transcript before, to be edited and then
    /// replaced.
    private func show(_ window: RecordingWindowController, _ record: MeetingRecord, _ folder: URL) {
        if let transcribing = recorder.transcribing, Self.key(transcribing.folder) == Self.key(folder) {
            window.show(record, transcript: nil, transcribing: transcribing.step)
        } else if recorder.waits(folder) {
            window.show(record, transcript: nil, waiting: true)
        } else {
            window.show(record, transcript: recordings.transcript(folder))
        }
    }

    /// Its transcript being made, or waiting its turn.
    private func isBeingMade(_ folder: URL) -> Bool {
        recorder.transcribing.map { Self.key($0.folder) == Self.key(folder) } == true || recorder.waits(folder)
    }

    /// `skilli://record/open` (a reminder's link back to its meeting): by its
    /// folder's name, else the newest of that title; false when none is.
    func open(named name: String, at: Double?) -> Bool {
        guard let folder = recording(named: name) else { return false }
        open(folder, at: at)
        return true
    }

    /// A link's follow-up, once allowed: a question answered in the card;
    /// the rest in its window, opened for it.
    func followUp(_ action: MeetingFollowUp.Action, on name: String, question: String?) {
        guard let (folder, _) = try? recordingForTool(name) else { return }
        if action == .ask {
            followUps.ask(question ?? "", about: folder)
            return
        }
        open(folder)
        Task { await followUps.run(action, on: folder) }
    }

    /// Rename… (the window's ⌘K, a recording's row in the launcher): its
    /// title, and its folder by the same rules (docs/meeting-recorder.md,
    /// "Where it lives"), `transcript.md`'s heading too; its window opened
    /// again on the folder it is in now. Not while it records or its
    /// transcript is made: said why.
    func rename(_ folder: URL, to typed: String) {
        do {
            try renamed(folder, to: typed)
        } catch {
            notify(error.localizedDescription)
        }
    }

    /// Rename's work, for a tool too: the folder it is in now; why not.
    @discardableResult
    func renamed(_ folder: URL, to typed: String) throws -> URL {
        let title = String(typed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard var record = recordings.read(folder) else { throw RecordingFollowUps.Failure(message: "The recording is gone.") }
        guard !title.isEmpty, title != record.title else { return folder }
        if recorder.folder.map(Self.key) == Self.key(folder) || isBeingMade(folder) {
            let doing = recorder.folder.map(Self.key) == Self.key(folder) ? "recorded" : "transcribed"
            throw RecordingFollowUps.Failure(message: "“\(record.title)” was not renamed: it is being \(doing). Rename it once it is done.")
        }
        let open = windows[Self.key(folder)]
        let frame = open?.nsWindow.frame
        let moved: URL
        do {
            moved = try recordings.rename(folder, to: title, started: record.started)
            record.title = title
            try recordings.write(record, to: moved)
        } catch {
            throw RecordingFollowUps.Failure(message: "“\(record.title)” was not renamed: \(error.localizedDescription)")
        }
        if let lines = recordings.transcript(moved)?.lines {
            try? MeetingTranscriber.markdown(record, lines: lines).write(to: moved.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        }
        Log.trace("Recorder: renamed “\(title)” (\(moved.lastPathComponent))")
        NotificationCenter.default.post(name: Recordings.changed, object: nil)
        if let open {
            // Asked from that window (a key in its ⌘K): closed once the key
            // is handled, never freed under its own event.
            DispatchQueue.main.async { [weak self] in
                open.close()
                self?.open(moved)
                if let frame { self?.windows[Self.key(moved)]?.nsWindow.setFrame(frame, display: true) }
            }
        }
        return moved
    }

    /// Ask about a meeting from the launcher's row: answered in the card.
    func ask(_ question: String, about folder: URL) {
        followUps.ask(question, about: folder)
    }

    /// `list_recordings`: newest first, a line each, no words.
    func recordingsListed() -> String {
        let all = allRecordings()
        guard !all.isEmpty else { return "No recordings." }
        return all.map { folder, record in
            var made: [String] = []
            if record.summarized != nil { made.append("summary") }
            if !record.chapters.isEmpty { made.append("\(record.chapters.count) chapters") }
            let when = record.started.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute())
            return "\(folder.lastPathComponent) · “\(record.title)” · \(when) · \(MeetingTranscriber.length(record.seconds)) · \(record.state.rawValue)"
                + (made.isEmpty ? "" : " · " + made.joined(separator: ", "))
        }.joined(separator: "\n")
    }

    /// The recording a tool names (its id or title; empty: the newest),
    /// or why none is.
    func recordingForTool(_ name: String?) throws -> (URL, MeetingRecord) {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let folder = name.isEmpty ? allRecordings().first?.0 : recording(named: name)
        guard let folder, let record = recordings.read(folder) else {
            throw RecordingFollowUps.Failure(message: name.isEmpty ? "No recordings." : "No recording “\(name)”: list_recordings gives their ids.")
        }
        return (folder, record)
    }

    /// Every recording with its record, newest first.
    private func allRecordings() -> [(URL, MeetingRecord)] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: recordings.root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder in recordings.read(folder).map { (folder, $0) } }.sorted { $0.1.started > $1.1.started }
    }

    /// A recording by its folder's name, else the newest whose title is
    /// `name` (case and accents aside).
    func recording(named name: String) -> URL? {
        let root = recordings.root
        // A folder's name never holds a slash nor starts with a dot: a link
        // never reaches outside the recordings.
        if !name.contains("/"), !name.hasPrefix(".") {
            let exact = root.appendingPathComponent(name, isDirectory: true)
            if recordings.read(exact) != nil { return exact }
        }
        return allRecordings().first { MeetingVoices.sameName($0.1.title, name) }?.0
    }

    /// A recording's window, its actions wired: delete, the folder, a
    /// transcript made (again), a line deleted (the undo card), a file
    /// dropped (imported).
    private func makeWindow(_ folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File?) -> RecordingWindowController {
        let window = RecordingWindowController(folder: folder, record: record, transcript: transcript, ownName: ownName)
        window.onClose = { [weak self] controller in self?.windows[Self.key(controller.folder)] = nil }
        window.onShowFolder = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        window.onDelete = { [weak self] folder, record in
            // From its own ⌘K (a key there): closed once the key is handled.
            let open = self?.windows[Self.key(folder)]
            DispatchQueue.main.async { open?.close() }
            self?.delete(folder, title: record.title)
        }
        window.onTranscribe = { [weak self] folder, record, engine in
            guard let self else { return }
            try? self.recordings.write(record, to: folder)
            self.recorder.transcribe(folder, record: record, engine: engine)
        }
        window.onTranscribeAgain = { [weak self] folder, record, engine in
            self?.transcribeAgain(folder, record: record, engine: engine)
        }
        window.onDeleteLine = { [weak self] words, undo in
            self?.deletes.transcriptLine(words, undo: undo)
        }
        window.onEdited = { _ in NotificationCenter.default.post(name: Recordings.changed, object: nil) }
        window.onImport = { [weak self] files in self?.importFiles(files) }
        window.engines = {
            [(.macOS, nil), (.whisper, BetterTranscription.isReady() ? nil : "Better transcription isn't downloaded: Settings → Recorder offers it.")]
        }
        window.languages = { engine in await MeetingTranscriber.languages(for: engine) }
        window.onOpenSettings = { [weak self] in self?.openSettings(.recorder) }
        // Phase 5: ⌘K's AI actions, done here; the window told what to show.
        window.onFollowUp = { [weak self] folder, action in
            guard let self else { return }
            Task { await self.followUps.run(action, on: folder) }
        }
        window.onRemoveChapters = { [weak self] folder, _ in self?.followUps.removeChapters(in: folder) }
        window.onAsk = { [weak self] folder, question in self?.followUps.ask(question, about: folder) }
        window.onRename = { [weak self] folder, title in self?.rename(folder, to: title) }
        window.skillies = { [weak self] in self?.followUps.recordingSkillies() ?? [] }
        window.markedSkillie = { [weak self] in self?.followUps.marked() ?? "" }
        window.onRunSkillie = { [weak self] folder, skillie in self?.followUps.run(skillie, on: folder) }
        window.provider = { [weak self] in self?.followUps.provider ?? WritingProvider.claude.title }
        if let work = followUps.work(for: folder) { window.showWork(work) }
        window.betterHint = { [weak self] record in
            // Taught once (docs/meeting-recorder-views.md, phase 4): the first
            // window on a transcript macOS's engine made, Better
            // transcription not downloaded; then never again.
            guard let self, !self.preferences.recorderBetterHintShown, TranscriptEngine(stored: record.engine) == .macOS,
                  !BetterTranscription.isReady() else { return false }
            self.preferences.recorderBetterHintShown = true
            return true
        }
        // Pending: shown again now that its engines are known, for their menu.
        if transcript == nil, record.state == .pending { window.show(record, transcript: nil) }
        windows[Self.key(folder)] = window
        return window
    }

    /// Transcribe Again (phase 4): the language and the engine as picked;
    /// the transcript before stays until the new one is written.
    private func transcribeAgain(_ folder: URL, record: MeetingRecord, engine: TranscriptEngine) {
        madeAgain.insert(Self.key(folder))
        recorder.transcribe(folder, record: record, again: true, engine: engine)
        // Another being made first: it waits, its lines no longer editable.
        reshow(folder)
    }

    // MARK: - Import (phase 4)

    /// Import Recording… (the launcher, a link): the open panel, sound and
    /// video files; `selecting` a file a link named, chosen only with the
    /// user's ↩.
    func importRecording(selecting file: URL? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = RecordingImport.types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.message = "Each file becomes a recording, transcribed on this Mac. The file itself stays where it is."
        if let file {
            panel.directoryURL = file.deletingLastPathComponent()
            panel.nameFieldStringValue = file.lastPathComponent
        }
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    /// Each file a recording of its own, in order: its window opens at once
    /// ("Importing… 30 %", then its transcript), voices told apart. One
    /// that cannot be made says why in the card.
    func importFiles(_ files: [URL]) {
        let files = files.filter(RecordingImport.isImportable)
        guard !files.isEmpty else { return }
        Task {
            let language = await MeetingTranscriber.defaultLanguage(asked: askedLanguage)
            for file in files {
                do {
                    _ = try await importFile(file, language: language)
                } catch {
                    notify(error.localizedDescription)
                }
            }
        }
    }

    /// `import_recording` (an agent, a skillie): one file, its recording's
    /// folder once its sound is copied (the transcript follows).
    func importForTool(_ file: URL) async throws -> URL {
        guard RecordingImport.isImportable(file) else {
            throw RecordingImport.Failure(message: "“\(file.lastPathComponent)” is not a sound or video file.")
        }
        return try await importFile(file, language: await MeetingTranscriber.defaultLanguage(asked: askedLanguage))
    }

    private func importFile(_ file: URL, language: String) async throws -> URL {
        let made = try await RecordingImport.prepare(file, in: recordings, language: language)
        let window = makeWindow(made.folder, record: made.record, transcript: nil)
        window.showImporting(0)
        window.present()
        do {
            let record = try await RecordingImport.copy(file, into: made.folder, record: made.record) { done in
                DispatchQueue.main.async { MainActor.assumeIsolated { [weak window] in window?.showImporting(done) } }
            }
            Log.trace("Recorder: “\(file.lastPathComponent)” imported, \(Int(record.seconds)) s")
            NotificationCenter.default.post(name: Recordings.changed, object: nil)
            window.show(record, transcript: nil)
            recorder.transcribe(made.folder, record: record)
            return made.folder
        } catch {
            window.close()
            throw RecordingImport.Failure(message: "“\(file.lastPathComponent)” was not imported: \(error.localizedDescription)")
        }
    }

    private func delete(_ folder: URL, title: String) {
        do {
            try deletes.recording(folder, title: title)
        } catch {
            notify("“\(title)” was not moved to the Trash: \(error.localizedDescription)")
        }
    }

    // MARK: - Never stopped, or closed as skil.li quit

    /// What a launch finds in the Recordings folder: the recordings never
    /// stopped (a crash, a power cut) as their files say them, and those
    /// closed as skil.li quit, whose transcript waits.
    struct Left {
        var unfinished: [(URL, MeetingRecord)] = []
        var toTranscribe: [(URL, MeetingRecord)] = []
        /// Transcribe Again asked and not made as skil.li quit.
        var toMakeAgain: [(URL, MeetingRecord)] = []
        var isEmpty: Bool { unfinished.isEmpty && toTranscribe.isEmpty && toMakeAgain.isEmpty }
    }

    /// At launch, a few seconds in: what `root` holds that was left,
    /// read off the main thread (a few small files). Nothing is made when
    /// there is none.
    nonisolated static func left(in root: URL) async -> Left {
        await Task.detached(priority: .utility) {
            let recordings = Recordings(root: root)
            return Left(unfinished: recordings.unfinished().map { ($0.folder, MeetingRecorder.measured($0.folder, record: $0.record)) },
                        toTranscribe: recordings.stopped().map { ($0.folder, $0.record) },
                        toMakeAgain: recordings.madeAgainLeft().map { ($0.folder, $0.record) })
        }.value
    }

    /// The transcripts left at the quit made now, oldest first, without
    /// asking and without opening their windows (the menu bar's ring shows
    /// them being made); the ones never stopped offered one at a time
    /// (Save, Later, Discard).
    func pickUp(_ left: Left) {
        for (folder, record) in left.toTranscribe.reversed() {
            madeQuietly.insert(Self.key(folder))
            recorder.transcribe(folder, record: record)
        }
        // Then those asked again before the quit, as asked (their transcript
        // stays until the new one is written).
        for (folder, record) in left.toMakeAgain {
            guard let asked = record.madeAgain else { continue }
            var record = record
            record.language = asked.language
            madeQuietly.insert(Self.key(folder))
            madeAgain.insert(Self.key(folder))
            recorder.transcribe(folder, record: record, again: true, engine: TranscriptEngine(stored: asked.engine) ?? .macOS)
        }
        guard !left.unfinished.isEmpty else { return }
        unfinished = left.unfinished
        offerNext()
    }

    /// A Stop that could not finish its files: offered now, first, as one
    /// never stopped (its length read from its files, off the main thread).
    private func offerAtOnce(_ folder: URL, record: MeetingRecord) {
        Task { [weak self] in
            let measured = await Task.detached(priority: .userInitiated) { MeetingRecorder.measured(folder, record: record) }.value
            guard let self else { return }
            self.unfinished.insert((folder, measured), at: 0)
            self.offerNext()
        }
    }

    /// The next one never stopped, in the card: only while nothing records
    /// or starts to (a ⌘R start under way included); else `changed()`
    /// offers it once the recorder is idle.
    private func offerNext() {
        guard !card.isVisible, recorder.phase == .idle, !starting, !unfinished.isEmpty else { return }
        let (folder, record) = unfinished.removeFirst()
        Log.trace("Recorder: “\(record.title)” was never stopped: offered")
        card.showUnfinished(folder, record: record)
    }

    #if SKILLI_SELFTEST
    /// Self-test: the meeting's window, found only `after` that long (a
    /// browser slow to answer, Automation's question).
    var standInMeetingWindow: (window: ScreenWindow, after: Duration)?

    /// Self-test: recorded at once as ⌘R records (the sources as Settings
    /// sets them), `screen` the window recorded.
    func recordForTest(screen: ScreenWindow?) {
        guard recorder.phase == .idle, !starting else { return }
        let reading = moment(for: nil)
        starting = true
        Task {
            let language = await MeetingTranscriber.defaultLanguage(asked: askedLanguage)
            var start = Self.start(reading, title: "Pictures check", language: language, sources: reading.sources)
            start.screen = screen
            do {
                try await recorder.record(start)
            } catch {
                starting = false
                notify("The recording could not start: \(error.localizedDescription)")
                return
            }
            starting = false
            began(reading)
        }
    }

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

    /// Self-test: the call's end offered now, as its watch offers it.
    func showCallEndedForTest(app: String) {
        let reason = CallEndWatch.Reason.appLeft(app)
        card.showCallEnded(title: recorder.title, elapsed: recorder.elapsed, line: CallEndWatch.line(reason), reason: reason)
    }

    /// Self-test: `work` while macOS asks over the card, as a source turned
    /// on asks.
    func whileMacOSAsksForTest(_ work: () async -> Void) async {
        await card.whileMacOSAsks(true, work)
    }

    /// Self-test: the card gone, as a call's app back withdraws it.
    func dismissCardForTest() {
        card.dismiss()
    }

    /// Self-test: ⌘R's recording takes this long to start (an unfinished
    /// one found meanwhile).
    var startDelay: Duration = .zero
    /// Self-test: ⌘R's next recording fails to start.
    var startFails = false

    /// Self-test: a Stop that could not finish `folder`'s files, as the
    /// recorder reports it.
    func offerAtOnceForTest(_ folder: URL, record: MeetingRecord) {
        offerAtOnce(folder, record: record)
    }

    /// Self-test: the found ones offered now, without the wait.
    func offerUnfinishedNow() -> Int {
        unfinished = recordings.unfinished().map { ($0.folder, MeetingRecorder.measured($0.folder, record: $0.record)) }
        let count = unfinished.count
        offerNext()
        return count
    }

    #endif
}
