import AppKit
import AVFoundation
import Carbon.HIToolbox
import SkilliCore
import UniformTypeIdentifiers

/// A recording's window (docs/meeting-recorder-views.md): a window, not a
/// card, since it is read and played. The player with both sides'
/// waveforms, then the transcript, a line each, its speaker's name, the
/// slides read on screen among them at their time; a click plays from a
/// line, the line playing is lit and followed. The webcam and the screen
/// play small beside it, in step (phase 3). A line selected is edited in
/// place, given to another speaker or deleted, a speaker renamed, every
/// change written at once and undone with ⌘Z; Transcribe Again; a file
/// dropped on it is imported (phase 4). ⌘K lists what can be done with
/// the recording; its chapters head the lines and mark the waveform, its
/// summary tops them (phase 5). Built when opened, released when closed.
@MainActor
final class RecordingWindowController: NSObject, NSWindowDelegate {
    let folder: URL
    private(set) var record: MeetingRecord
    private let window: RecordingWindow
    private let view = RecordingView()
    private var player: AVPlayer?
    /// The screen's and the webcam's players, kept in step with the
    /// sound's (one host time to start them all).
    private var pictures: [AVPlayer] = []
    /// A correction scheduled for a picture, until its host time: not
    /// scheduled again meanwhile (its time reads the old one until then).
    private var correcting: [ObjectIdentifier: CMTime] = [:]
    /// Loading it: once, however often the window is shown meanwhile.
    private var loadingPlayer = false
    /// Where to play from once the player is loaded (a link's `at`).
    private var playOnLoad: Double?
    private var observer: Any?
    /// The transcript as edited here, and its changes (⌘Z, ⇧⌘Z) while
    /// the window is open; nil until there is one.
    private(set) var draft: TranscriptDraft?
    private var history = TranscriptHistory()
    /// The transcript's own language and engine, written back with it.
    private var made: (language: String, engine: String)?
    /// The lines are shown: none while a transcript is made (again) or an
    /// import copies, when ⌘Z and edits would be written over.
    private var linesShown = false
    /// Its transcript being made (again), or waiting its turn.
    private var making = false
    /// The user's own name (My Card), offered first for Me; read once.
    private var ownName: String?
    var onClose: ((RecordingWindowController) -> Void)?
    var onDelete: ((URL, MeetingRecord) -> Void)?
    var onShowFolder: ((URL) -> Void)?
    /// A transcript waiting for a language: made in the one picked.
    var onTranscribe: ((URL, MeetingRecord) -> Void)?
    /// Transcribe Again (phase 4): the record with the language picked,
    /// and the engine picked.
    var onTranscribeAgain: ((URL, MeetingRecord, TranscriptEngine) -> Void)?
    /// A line deleted: its words, and how to bring it back (false: it
    /// could not be).
    var onDeleteLine: ((String, @escaping @MainActor () -> Bool) -> Void)?
    /// Files dropped on the window: imported, each a recording of its own.
    var onImport: (([URL]) -> Void)?
    /// The lines changed: the lists and the search read again.
    var onEdited: ((URL) -> Void)?
    /// The engines Transcribe Again offers, each with why it cannot be
    /// used (nil: it can).
    var engines: () -> [(engine: TranscriptEngine, unusable: String?)] = { [(.macOS, nil)] }
    /// The languages an engine transcribes on this Mac, by name.
    var languages: (TranscriptEngine) async -> [(id: String, name: String)] = { _ in await MeetingTranscriber.languages() }
    /// Settings → Recorder (Better transcription's line, a click).
    var onOpenSettings: (() -> Void)?
    /// ⌘K's summary, chapters, action items, recap mail (phase 5): done by
    /// the center, the window told what to show.
    var onFollowUp: ((URL, MeetingFollowUp.Action) -> Void)?
    /// Remove Chapters: gone at once, the undo card offers them back.
    var onRemoveChapters: ((URL, MeetingRecord) -> Void)?
    /// Ask About This Meeting…: the question typed in ⌘K's list.
    var onAsk: ((URL, String) -> Void)?
    /// The skillies for recordings ⌘K lists, the one marked to run after
    /// every transcript (its path), and one run on this recording.
    var skillies: () -> [ScriptCommand] = { [] }
    var markedSkillie: () -> String = { "" }
    var onRunSkillie: ((URL, ScriptCommand) -> Void)?
    /// Who writes for the AI's actions, as their titles name it ("Claude").
    var provider: () -> String = { "Claude" }
    /// The summary shown above the lines, from `summary.md`: its words and
    /// its header ("SUMMARY BY CLAUDE · 14:52").
    private(set) var summary: (text: String, header: String)?
    /// What the AI is doing for this recording now, as the window says it
    /// ("Writing the summary with Claude · Haiku…"); nil: nothing.
    private(set) var working: String?
    /// ⌘K's list over the window.
    private let actionPanel = ActionPanelView()
    /// Keys the list took: their repeats are not new presses.
    private var heldKeys = HeldKeys()
    /// Whether this window says once what Better transcription does (the
    /// record's transcript made by macOS's engine, never said before);
    /// asked once per window, when it shows a transcript.
    var betterHint: ((MeetingRecord) -> Bool)? {
        didSet { considerBetterHint() }
    }
    private var betterHintAsked = false
    /// The line shown, until the transcript is no longer macOS's.
    private var betterHintShown = false

    init(folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File?, ownName: (() async -> String?)? = nil) {
        self.folder = folder
        self.record = record
        // With pictures it opens wider: the column beside the lines.
        let pictured = [RecorderPictures.screenFile, RecorderPictures.webcamFile].contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        window = RecordingWindow(contentRect: NSRect(x: 0, y: 0, width: pictured ? 1020 : 760, height: 640),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 420)
        window.title = record.title
        window.contentView = view
        window.delegate = self
        window.controller = self
        window.center()
        view.onPlay = { [weak self] in self?.togglePlay() }
        view.onSeek = { [weak self] seconds, plays in self?.seek(to: seconds, play: plays) }
        view.onTranscribe = { [weak self] language in self?.transcribe(in: language) }
        view.onKey = { [weak self] event in self?.key(event) ?? false }
        view.onEdited = { [weak self] line, text in self?.edit(line, text: text) }
        view.onRenameClicked = { [weak self] line, point in self?.showRenameMenu(line: line, at: point) }
        view.onRenamed = { [weak self] line, name in self?.rename(line: line, to: name) }
        view.onSelect = { [weak self] _ in self?.updateHints() }
        view.onTranscribeAgain = { [weak self] in self?.showTranscribeAgain() }
        view.onDrop = { [weak self] urls in self?.onImport?(urls) }
        view.onHint = { [weak self] in self?.onOpenSettings?() }
        actionPanel.isHidden = true
        actionPanel.bottom = 48
        actionPanel.autoresizingMask = [.width, .height]
        actionPanel.onRun = { [weak self] action in self?.runAction(action) }
        actionPanel.onDismiss = { [weak self] in self?.closeActions() }
        view.addSubview(actionPanel)
        if let ownName {
            Task { [weak self] in
                let name = await ownName()
                // A name already given (the self-test's) stays.
                if self?.ownName == nil { self?.ownName = name }
            }
        }
        show(record, transcript: transcript)
    }

    var isVisible: Bool { window.isVisible }
    var nsWindow: NSWindow { window }
    /// Self-test hooks.
    var shownLines: [TranscriptLine] { view.lines }
    var shownNames: [String: String] { view.names }
    var selectedLine: Int? { view.selectedLine }
    var playing: Bool { (player?.rate ?? 0) > 0 }
    var currentTime: Double { player?.currentTime().seconds ?? 0 }
    var litLine: Int? { view.litLine }
    var shownState: String { view.stateText }
    var spaceHint: String? { view.spaceHint }
    var shownHints: [String] { view.hintLabels }
    var shownLanes: [String] { view.shownLanes }
    /// Both tracks' waveforms read and drawn (read off the main thread).
    var showsWaveform: Bool { view.showsWaveform }
    var shownAbout: String { view.aboutText }
    var shownSlides: [SlideLog.Slide] { view.slides }
    var shownPictures: Int { view.pictureCount }
    var isEditingLine: Bool { view.editingLine != nil }
    var shownHint: String? { view.hintText }
    var shownWork: String? { view.workText }
    var shownRan: String? { view.ranText }
    var shownChapters: [MeetingRecord.Chapter] { view.chapters }
    var shownChapterMarks: Int { view.chapterMarks }
    var shownSummary: String? { view.summaryShown }
    var isShowingActions: Bool { !actionPanel.isHidden }
    /// ⌘K's list turned into a field (Ask About This Meeting…).
    var isAskingInActions: Bool { !actionPanel.isHidden && actionPanel.isPrompting }
    var shownActions: [(title: String, key: String?)] { actionPanel.shown.map { ($0.title, $0.key?.label) } }
    var shownActionsNote: String? { actionPanel.note }
    /// Where a chapter's heading is on screen, to click it.
    func screenFrame(ofChapter index: Int) -> NSRect? { view.screenFrame(ofChapter: index) }
    /// Where the screen's and the webcam's players are, and the sound's.
    var pictureTimes: [Double] { pictures.map { $0.currentTime().seconds } }
    /// Where a line is on screen (AppKit's coordinates), to click it.
    func screenFrame(ofLine row: Int) -> NSRect? { view.screenFrame(ofLine: row) }
    /// Where a line's speaker's name is on screen, to click it.
    func screenFrame(ofSpeakerIn row: Int) -> NSRect? { view.screenFrame(ofSpeakerIn: row) }
    /// The rename menu while it is open (self-test: its items, to pick one).
    private(set) var renameMenu: NSMenu?
    /// The Transcribe Again panel shown now.
    private(set) var againPanel: TranscribeAgainPanel?

    /// What the folder holds now: the transcript once made, or why there is
    /// none.
    /// `waiting`: made again once another is made, nothing of it yet; the
    /// transcript before is not shown to be edited meanwhile.
    func show(_ record: MeetingRecord, transcript: MeetingTranscript.File?, transcribing: MeetingTranscriber.Step? = nil, waiting: Bool = false) {
        self.record = record
        // Made again (by whisper, or being made): the line no longer
        // applies.
        if betterHintShown, transcribing != nil || TranscriptEngine(stored: transcript?.engine) != .macOS {
            betterHintShown = false
            view.setHint(nil)
        }
        window.title = record.title
        view.header(title: record.title, about: MeetingTranscriber.about(record))
        // In person, the microphone holds the room: one lane, its name.
        view.setLanes(Self.laneNames(record, lines: transcript?.lines), lanes: Speaker.allCases.filter { !(record.unused ?? []).contains($0) })
        if let transcribing {
            view.showTranscribing(transcribing)
        } else if waiting {
            view.showWaiting()
        } else if let transcript {
            // Read again from disk (opened again, made again): a draft that
            // differs is replaced, and with it what ⌘Z would undo.
            let fresh = TranscriptDraft(lines: transcript.lines, names: record.speakers)
            if draft != fresh {
                draft = fresh
                history = TranscriptHistory()
            }
            made = (transcript.language, transcript.engine)
            summary = Self.summary(in: folder, record: record)
            view.setRan(Self.ranLine(record))
            view.showLines(fresh.lines, names: fresh.names, slides: Self.slides(in: folder), chapters: record.chapters, summary: summary)
            view.setChapterMarks(record.chapters)
            considerBetterHint()
        } else if record.state == .transcribing || record.state == .stopped {
            // Its turn not come yet (another being made, or the launch's).
            view.showWaiting()
        } else {
            view.showPending(language: record.language)
        }
        linesShown = transcribing == nil && !waiting && transcript != nil
        making = transcribing != nil || waiting
        view.canTranscribeAgain = linesShown && working == nil
        updateAgainPanel()
        updateHints()
        if player == nil, !loadingPlayer { loadPlayer() }
    }

    /// Better transcription taught once: the line at the bottom of the
    /// lines, in this window only.
    /// Better transcription downloaded meanwhile: its line goes.
    func hideBetterHint() {
        guard betterHintShown else { return }
        betterHintShown = false
        view.setHint(nil)
    }

    private func considerBetterHint() {
        guard !betterHintAsked, draft != nil, let betterHint else { return }
        betterHintAsked = true
        if betterHint(record) {
            betterHintShown = true
            view.setHint("Names heard wrong? Better transcription gets two in three right, on this Mac: Settings → Recorder (1.6 GB download).")
        }
    }

    /// The lanes' names: the microphone's as the record has it ("Me",
    /// "Room", "Sound"); the Mac's sound "Them", or its one voice's name
    /// when the other side was one voice.
    static func laneNames(_ record: MeetingRecord, lines: [TranscriptLine]?) -> [String: String] {
        let others = Set((lines ?? []).map(\.speaker).filter { $0.track == .them })
        let them = others == [.them] ? MeetingVoices.name(of: .them, in: record.speakers) : Speaker.them.title
        return [Speaker.me.rawValue: record.speakers[Speaker.me.rawValue] ?? Speaker.me.title, Speaker.them.rawValue: them]
    }

    /// An import being made (its sound copied): "Importing… 30 %".
    func showImporting(_ done: Double) {
        view.showState("Importing… \(Int((done * 100).rounded())) %")
        linesShown = false
        view.canTranscribeAgain = false
        updateHints()
    }

    func present() {
        Foreground.bring(window)
    }

    /// The summary in `summary.md`, and its header: who wrote it and when
    /// ("SUMMARY BY CLAUDE · 14:52"); nil when there is none.
    static func summary(in folder: URL, record: MeetingRecord) -> (text: String, header: String)? {
        guard let file = try? String(contentsOf: folder.appendingPathComponent(Recordings.summary), encoding: .utf8) else { return nil }
        let text = MeetingFollowUp.summary(inFile: file)
        guard !text.isEmpty else { return nil }
        return (text, summaryHeader(record.summarized))
    }

    /// The skillie marked, as it last ran after the transcript: "“Send to
    /// Notes” ran after the transcript at 14:52: Sent."; nil: none ran.
    static func ranLine(_ record: MeetingRecord) -> String? {
        guard let ran = record.skillies?.last(where: \.automatic) else { return nil }
        let when = Calendar.current.isDateInToday(ran.at) ? ran.at.formatted(date: .omitted, time: .shortened)
            : ran.at.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let line = ran.line.isEmpty ? "" : ": \(ran.line)"
        return ran.status == 0 ? "“\(ran.title)” ran after the transcript at \(when)\(line)"
            : "“\(ran.title)” failed after the transcript at \(when)\(line.isEmpty ? " (exit \(ran.status))" : line)"
    }

    /// "SUMMARY BY CLAUDE · 14:52"; another day's, its date too.
    static func summaryHeader(_ summarized: MeetingRecord.Summarized?) -> String {
        guard let summarized else { return "SUMMARY" }
        let who = summarized.by.components(separatedBy: " · ").first ?? summarized.by
        let when = Calendar.current.isDateInToday(summarized.at) ? summarized.at.formatted(date: .omitted, time: .shortened)
            : summarized.at.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "SUMMARY BY \(who.uppercased()) · \(when)"
    }

    /// The slides read on screen, from `slides.json` (none: empty).
    nonisolated static func slides(in folder: URL) -> [SlideLog.Slide] {
        (try? Data(contentsOf: folder.appendingPathComponent(RecorderPictures.slidesFile))).flatMap { try? SlideLog.decode($0) } ?? []
    }

    func close() {
        window.close()
    }

    // MARK: - Playing

    private func loadPlayer() {
        let urls = Speaker.allCases.map { folder.appendingPathComponent($0.file) }
        // An import still copying its sound: loaded once its file is in.
        if record.imported != nil, !FileManager.default.fileExists(atPath: urls[0].path) { return }
        loadingPlayer = true
        let composition = AVMutableComposition()
        Task { [weak self] in
            // Both tracks from 0, in one composition: they play in step.
            for url in urls {
                let asset = AVURLAsset(url: url)
                guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                      let range = try? await track.load(.timeRange),
                      let added = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try? added.insertTimeRange(range, of: track, at: .zero)
            }
            guard let self else { return }
            let player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
            player.automaticallyWaitsToMinimizeStalling = false
            self.player = player
            // The screen and the webcam, each its own player on its own
            // layer, started with the sound at one host time.
            var layers: [(AVPlayerLayer, CGSize)] = []
            for name in [RecorderPictures.screenFile, RecorderPictures.webcamFile] {
                let url = self.folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let asset = AVURLAsset(url: url)
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize), size.width > 0 else { continue }
                let picture = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                picture.automaticallyWaitsToMinimizeStalling = false
                picture.isMuted = true
                picture.actionAtItemEnd = .pause
                self.pictures.append(picture)
                layers.append((AVPlayerLayer(player: picture), size))
            }
            self.view.setPictures(layers)
            self.view.duration = max(self.record.seconds, composition.duration.seconds.isFinite ? composition.duration.seconds : 0)
            self.observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    self?.view.played(to: time.seconds, playing: (self?.player?.rate ?? 0) > 0)
                    self?.keepPicturesInStep()
                }
            }
            self.view.played(to: 0, playing: false)
            if let start = self.playOnLoad {
                self.playOnLoad = nil
                self.seek(to: start, play: true)
            }
        }
        Task.detached(priority: .utility) {
            let peaks = urls.map { RecordingWindowController.peaks(of: $0) }
            await MainActor.run { [weak self] in self?.view.setPeaks(me: peaks[0], them: peaks[1]) }
        }
    }

    /// A link's `at` (a reminder's way back): the line said then selected,
    /// played from its start.
    func play(from seconds: Double) {
        // Never past the recording's end (a link's `at` is anyone's).
        let seconds = seconds.isFinite ? min(max(0, seconds), max(record.seconds, 0)) : 0
        let line = MeetingTranscript.line(at: seconds + 0.05, in: view.lines)
        if let line { view.select(line, scrollToIt: true) }
        let start = line.map { view.lines[$0].start } ?? seconds
        if player == nil { playOnLoad = start } else { seek(to: start, play: true) }
    }

    func togglePlay() {
        guard let player else { return }
        if player.rate > 0 {
            player.pause()
            pictures.forEach { $0.pause() }
            let at = player.currentTime()
            pictures.forEach { $0.seek(to: at, toleranceBefore: .zero, toleranceAfter: .zero) }
        } else {
            var from = player.currentTime()
            if let item = player.currentItem, from >= item.duration, item.duration.isNumeric { from = .zero }
            playAll(from: from)
        }
        view.played(to: player.currentTime().seconds, playing: player.rate > 0)
    }

    func seek(to seconds: Double, play: Bool) {
        guard let player else { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        if play || player.rate > 0 {
            playAll(from: time)
        } else {
            for each in [player] + pictures { each.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) }
        }
        view.played(to: seconds, playing: play || player.rate > 0)
    }

    /// Every player from `time`, started at the same host time a moment
    /// from now: the pictures in step with the sound.
    private func playAll(from time: CMTime) {
        guard let player else { return }
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 20))
        for each in [player] + pictures {
            each.setRate(1, time: time, atHostTime: host)
        }
        // Each picture starts then: nothing to correct before.
        correcting = Dictionary(uniqueKeysWithValues: pictures.map { (ObjectIdentifier($0), host) })
    }

    /// While playing, a picture more than a frame off the sound (a file
    /// that ended and held, a seek still on its way) is put back in step.
    private func keepPicturesInStep() {
        guard let player, player.rate > 0, !pictures.isEmpty else { return }
        let now = player.currentTime()
        let hostNow = CMClockGetTime(CMClockGetHostTimeClock())
        for picture in pictures {
            let key = ObjectIdentifier(picture)
            if let pending = correcting[key], CMTimeCompare(hostNow, pending) < 0 { continue }
            correcting[key] = nil
            guard let item = picture.currentItem, item.duration.isNumeric else { continue }
            let wanted = min(now.seconds, item.duration.seconds)
            if abs(picture.currentTime().seconds - wanted) > 0.07, now.seconds < item.duration.seconds {
                let host = CMTimeAdd(hostNow, CMTime(value: 1, timescale: 20))
                picture.setRate(1, time: CMTimeAdd(now, CMTime(value: 1, timescale: 20)), atHostTime: host)
                correcting[key] = host
            }
        }
    }

    /// Each side's loudest sample per bucket, 0…1: the waveform.
    nonisolated static func peaks(of url: URL, buckets: Int = 1600) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65536) else { return [] }
        let perBucket = max(1, Int(file.length) / buckets)
        var peaks: [Float] = []
        peaks.reserveCapacity(buckets + 1)
        var current: Float = 0, inBucket = 0
        while file.framePosition < file.length {
            let frames = AVAudioFrameCount(min(65536, file.length - file.framePosition))
            guard (try? file.read(into: buffer, frameCount: frames)) != nil, let data = buffer.floatChannelData?[0] else { break }
            for index in 0..<Int(buffer.frameLength) {
                current = max(current, abs(data[index]))
                inBucket += 1
                if inBucket == perBucket {
                    peaks.append(current)
                    current = 0
                    inBucket = 0
                }
            }
        }
        if inBucket > 0 { peaks.append(current) }
        // Speech rarely nears full scale: drawn against the loudest.
        let loudest = max(peaks.max() ?? 1, 0.05)
        return peaks.map { min(1, $0 / loudest) }
    }

    // MARK: - Keys

    /// The window's keys (docs/meeting-recorder-views.md, phase 4): space
    /// plays; ↑ ↓ select a line, esc lets go; with a line selected ↩
    /// edits it, ⇥ ⇧⇥ give it to the next or previous speaker, ⌥↩ renames
    /// its speaker, ⌘C copies it, ⌘⌫ deletes it; without one ⌘C copies the
    /// transcript and ⌘⌫ deletes the recording; ⌘↩ shows the folder; ⌘Z
    /// ⇧⌘Z undo and redo the lines' changes.
    fileprivate func key(_ event: NSEvent) -> Bool {
        // A key the list took, held: its repeats move or type in the list,
        // else nothing (held ⌘K opens it once, held ↩ runs one action).
        switch heldKeys.press(event.keyCode, isRepeat: event.isARepeat, listShown: !actionPanel.isHidden,
                              repeatsInList: Self.repeatsInList(event)) {
        case .swallowed:
            return true
        case .toList:
            actionPanelKey(event)
            return true
        case .new:
            break
        }
        let listed = !actionPanel.isHidden
        let handled = listed ? { actionPanelKey(event); return true }() : windowKey(event)
        if handled, listed || !actionPanel.isHidden { heldKeys.took(event.keyCode) }
        return handled
    }

    /// A key released: a held one is over.
    fileprivate func keyReleased(_ event: NSEvent) {
        heldKeys.released(event.keyCode)
    }

    /// Keys whose repeats mean something in the list: arrows, ⌃N ⌃P, ⌫, a
    /// letter typed.
    private static func repeatsInList(_ event: NSEvent) -> Bool {
        let code = Int(event.keyCode)
        if [kVK_UpArrow, kVK_DownArrow, kVK_Delete].contains(code) || LauncherController.controlStep(event) != nil { return true }
        let flags = event.modifierFlags.intersection([.command, .control])
        return flags.isEmpty && ![kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab].contains(code)
    }

    /// The window's own keys, the list closed.
    private func windowKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        // Letters by what they type (on AZERTY, Z is W's key): C and Z are
        // the only ones the window takes.
        let letter = event.charactersIgnoringModifiers?.lowercased()
        let code: Int = switch letter {
        case "c": kVK_ANSI_C
        case "k": kVK_ANSI_K
        case "z": kVK_ANSI_Z
        case let typed? where typed.count == 1 && typed.first?.isLetter == true: -1
        default: Int(event.keyCode)
        }
        let selected = view.selectedLine
        switch (flags, code) {
        case ([], kVK_Space):
            togglePlay()
        case ([], kVK_UpArrow), ([], kVK_DownArrow):
            view.moveSelection(code == kVK_UpArrow ? -1 : 1)
        case ([], kVK_Escape) where selected != nil:
            view.select(nil)
        case ([], kVK_Return) where selected != nil, ([], kVK_ANSI_KeypadEnter) where selected != nil:
            view.beginEditing(line: selected!)
        case (.option, kVK_Return) where selected != nil:
            showRenameMenu(line: selected!, at: nil)
        case ([], kVK_Tab) where selected != nil, (.shift, kVK_Tab) where selected != nil:
            moveSpeaker(line: selected!, step: flags == .shift ? -1 : 1)
        case (.command, kVK_ANSI_C) where selected != nil:
            copyLine(selected!)
        case (.command, kVK_ANSI_C) where view.lines.isEmpty == false:
            copyTranscript()
        case (.command, kVK_Return), (.command, kVK_ANSI_KeypadEnter):
            onShowFolder?(folder)
        case (.command, kVK_Delete) where selected != nil:
            deleteLine(selected!)
        case (.command, kVK_Delete):
            player?.pause()
            pictures.forEach { $0.pause() }
            onDelete?(folder, record)
        case (.command, kVK_ANSI_Z):
            undo()
        case ([.command, .shift], kVK_ANSI_Z):
            redo()
        case (.command, kVK_ANSI_K):
            showActions()
        default:
            return false
        }
        return true
    }

    // MARK: - ⌘K (phase 5)

    /// The recording's actions over the window (docs/meeting-recorder-views.md,
    /// "The recording's window: ⌘K"), the launcher's list and keys.
    func showActions() {
        guard actionPanel.isHidden else { return }
        actionPanel.frame = view.bounds
        actionPanel.show(actions(), for: record.title)
        view.setHints([("Run", "↩"), ("Back", "esc")])
        // Its keys come to the window, whatever had the keyboard.
        if window.firstResponder !== view.linesTable { window.makeFirstResponder(view.linesTable) }
    }

    func closeActions() {
        guard !actionPanel.isHidden else { return }
        actionPanel.isHidden = true
        updateHints()
    }

    private func runAction(_ action: LauncherAction) {
        if !action.keepsOpen { closeActions() }
        action.run()
    }

    /// What ⌘K lists now: the AI's actions (once there is a transcript), the
    /// window's own, the copies, what removes. Each AI action names who it
    /// goes to; one asked while another is being done says so in the list.
    func actions() -> [LauncherAction] {
        let by = provider()
        var list: [LauncherAction] = []
        func ai(_ title: String, _ symbol: String, _ action: MeetingFollowUp.Action) -> LauncherAction {
            LauncherAction(title: title, symbol: symbol, keepsOpen: working != nil) { [weak self] in
                guard let self else { return }
                if let working = self.working {
                    self.actionPanel.say("\(working.replacingOccurrences(of: "…", with: "")): one at a time.")
                    return
                }
                self.onFollowUp?(self.folder, action)
            }
        }
        if linesShown {
            list.append(ai(summary == nil ? "Summary by \(by)" : "Summary Again by \(by)", "text.append", .summary))
            if record.seconds >= MeetingFollowUp.shortestForChapters {
                list.append(ai(record.chapters.isEmpty ? "Chapters by \(by)" : "Chapters Again by \(by)", "list.bullet.indent", .chapters))
            }
            list.append(ai("Action Items to Reminders by \(by)", "checklist", .actionItems))
            list.append(ai(summary == nil ? "Recap Mail to the Attendees by \(by)" : "Recap Mail to the Attendees", "envelope", .recapMail))
            list.append(LauncherAction(title: "Ask \(by) About This Meeting…", symbol: "questionmark.bubble", keepsOpen: true) { [weak self] in
                self?.askAboutThisMeeting()
            })
            // The user's skillies for recordings; the one marked says so.
            let marked = markedSkillie()
            for skillie in skillies() {
                list.append(LauncherAction(title: skillie.title + (RecordingFollowUps.isMarked(skillie, marked) ? " · after every transcript" : ""),
                                           symbol: "play") { [weak self] in
                    guard let self else { return }
                    self.onRunSkillie?(self.folder, skillie)
                })
            }
            // Not while one of its actions runs (it reads this transcript).
            if working == nil {
                list.append(LauncherAction(title: "Transcribe Again…", symbol: "arrow.triangle.2.circlepath") { [weak self] in self?.showTranscribeAgain() })
            }
        }
        list.append(LauncherAction(title: "Show in Finder", symbol: "folder", key: .openSecond) { [weak self] in
            guard let self else { return }
            self.onShowFolder?(self.folder)
        })
        if linesShown {
            list.append(LauncherAction(title: "Copy Transcript", symbol: "doc.on.doc", key: .copy, group: .copy) { [weak self] in self?.copyTranscript() })
        }
        if let summary {
            list.append(LauncherAction(title: "Copy Summary", symbol: "doc.on.doc", group: .copy) {
                AIActionController.writeAnswerToClipboard(summary.text)
            })
        }
        if linesShown, !record.chapters.isEmpty {
            list.append(LauncherAction(title: "Remove Chapters", symbol: "trash", group: .remove) { [weak self] in
                guard let self else { return }
                self.onRemoveChapters?(self.folder, self.record)
            })
        }
        list.append(LauncherAction(title: "Delete Recording", symbol: "trash", key: .delete, group: .remove) { [weak self] in
            guard let self else { return }
            self.player?.pause()
            self.pictures.forEach { $0.pause() }
            self.onDelete?(self.folder, self.record)
        })
        return list
    }

    /// Ask About This Meeting…: the list becomes a field; ↩ sends the
    /// question, the answer comes in the card.
    private func askAboutThisMeeting() {
        actionPanel.ask("Ask about “\(record.title)”", initial: "", placeholder: "What did they decide about…?",
                         line: "Type your question, ↩ asks \(provider()), esc goes back") { [weak self] typed in
            guard let self else { return }
            let question = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            self.closeActions()
            guard !question.isEmpty else { return }
            self.onAsk?(self.folder, question)
        }
    }

    /// A key while ⌘K's list is open, as the launcher's: arrows move, ↩
    /// runs the selected action, an action's own key runs it, letters
    /// filter, esc or ⌘K close it. A key that does nothing here says so.
    private func actionPanelKey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        // A question typed in the list: ↩ sends it.
        if actionPanel.isPrompting, flags.isEmpty, code == kVK_Return || code == kVK_ANSI_KeypadEnter {
            actionPanel.submit()
            return
        }
        if code == kVK_Escape || (flags == .command && event.charactersIgnoringModifiers?.lowercased() == "k") {
            closeActions()
        } else if code == kVK_UpArrow {
            actionPanel.move(by: -1, wraps: !event.isARepeat)
        } else if code == kVK_DownArrow {
            actionPanel.move(by: 1, wraps: !event.isARepeat)
        } else if let step = LauncherController.controlStep(event) {
            actionPanel.move(by: step, wraps: !event.isARepeat)
        } else if let key = LauncherAction.Key(event) {
            if let found = key == .open ? actionPanel.selectedAction : LauncherAction.find(key, in: actionPanel.actions) {
                runAction(found)
            } else if key == .open {
                actionPanel.say("No action matches “\(actionPanel.filter)”: ⌫ shows them again.")
            } else {
                actionPanel.say("Nothing on \(key.label) here: pick an action in the list.")
            }
        } else if code == kVK_Delete, flags.isEmpty || flags == .option {
            actionPanel.deleteBackward()
        } else if flags.isDisjoint(with: [.command, .control]), let text = event.characters, !text.isEmpty,
                  text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .privateUse }) {
            actionPanel.type(text)
        }
    }

    /// What the AI is doing for this recording, at the bottom of the lines
    /// (nil: done, the line goes).
    func showWork(_ text: String?) {
        working = text
        view.setWork(text)
        // Not made again under an action reading it, its panel open too.
        view.canTranscribeAgain = linesShown && text == nil
        updateAgainPanel()
    }

    /// An open Transcribe Again panel waits while an action runs or the
    /// transcript is being made: Transcribe dims, saying why.
    private func updateAgainPanel() {
        againPanel?.busy = working.map { "\($0.replacingOccurrences(of: "…", with: "")): Transcribe Again once it is done." }
            ?? (making ? "Its transcript is being made: Transcribe Again once it is done." : nil)
    }

    /// The summary as it is written (`header` says who and when), or read
    /// again once written.
    func showSummary(_ text: String, header: String) {
        summary = text.isEmpty ? nil : (text, header)
        view.setSummary(summary)
    }

    /// ⌘C: the transcript, as `transcript.md` has it.
    func copyTranscript() {
        let text = (try? String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8))
            ?? MeetingTranscriber.markdown(record, lines: view.lines)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// ⌘C on a selected line: its speaker, its time and its words, as
    /// `transcript.md` writes a line.
    func copyLine(_ index: Int) {
        guard let draft, draft.lines.indices.contains(index) else { return }
        let line = draft.lines[index]
        let text = "**\(MeetingVoices.name(of: line.speaker, in: draft.names))** · \(MeetingTranscript.clock(line.start))\n\(line.text)\n"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func transcribe(in language: String) {
        var record = record
        record.language = language
        self.record = record
        onTranscribe?(folder, record)
    }

    private func updateHints() {
        // Under ⌘K's list: its own, until it closes.
        guard actionPanel.isHidden else { return }
        view.updateHints(canUndo: linesShown && history.canUndo)
    }

    // MARK: - Editing (phase 4)

    /// A change made to the lines: kept for ⌘Z, written at once, shown
    /// with `select` selected.
    @discardableResult
    private func apply(_ edit: TranscriptDraft.Edit?, select: Int?) -> Int? {
        guard let edit else { return nil }
        let id = history.record(edit)
        changed(select: select)
        return id
    }

    /// The draft as it is now: written (`transcript.json`, `transcript.md`,
    /// `meeting.json`), shown, told.
    private func changed(select: Int?) {
        guard let draft else { return }
        record.speakers = draft.names
        record.edited = true
        save()
        view.update(lines: draft.lines, names: draft.names, select: select)
        view.setLanes(Self.laneNames(record, lines: draft.lines), lanes: Speaker.allCases.filter { !(record.unused ?? []).contains($0) })
        updateHints()
        onEdited?(folder)
    }

    private func save() {
        guard let draft else { return }
        let file = MeetingTranscript.File(language: made?.language ?? record.language, engine: made?.engine ?? record.engine ?? MeetingTranscriber.engine,
                                          lines: draft.lines)
        do {
            try file.encoded().write(to: folder.appendingPathComponent("transcript.json"), options: .atomic)
            try MeetingTranscriber.markdown(record, lines: draft.lines)
                .write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
            try record.encoded().write(to: folder.appendingPathComponent(Recordings.record), options: .atomic)
        } catch {
            Log.actions.error("Recorder: “\(self.record.title, privacy: .private)” not written (\(error.localizedDescription, privacy: .public))")
        }
    }

    /// ↩ kept in a line's field: its words as typed (emptied: deleted).
    private func edit(_ line: Int, text: String) {
        guard linesShown, var draft else { return }
        let edit = draft.setText(text, at: line)
        self.draft = draft
        if case .delete? = edit {
            deleted(edit, line: line)
        } else {
            apply(edit, select: line)
        }
    }

    /// ⇥: the line to the next speaker (⇧⇥ the one before).
    private func moveSpeaker(line: Int, step: Int) {
        guard linesShown, var draft else { return }
        let edit = draft.moveSpeaker(at: line, step: step)
        self.draft = draft
        apply(edit, select: line)
    }

    /// ⌘⌫ on a selected line: gone at once, the undo card offers it back.
    private func deleteLine(_ line: Int) {
        guard linesShown, var draft else { return }
        let edit = draft.delete(at: line)
        self.draft = draft
        deleted(edit, line: line)
    }

    private func deleted(_ edit: TranscriptDraft.Edit?, line: Int) {
        guard case .delete(_, let removed)? = edit, let draft else { return }
        let id = apply(edit, select: draft.lines.isEmpty ? nil : min(line, draft.lines.count - 1))
        guard let id else { return }
        onDeleteLine?(removed.text) { [weak self] in
            self?.revert(id: id, select: line) ?? false
        }
    }

    /// The undo card's ⌘Z: that delete undone, wherever it is in the
    /// changes.
    private func revert(id: Int, select: Int) -> Bool {
        guard linesShown, var draft, history.revert(id: id, in: &draft) else { return false }
        self.draft = draft
        changed(select: select)
        return true
    }

    func undo() {
        guard linesShown, var draft, let edit = history.undo(&draft) else { return }
        self.draft = draft
        changed(select: Self.line(of: edit))
    }

    func redo() {
        guard linesShown, var draft, let edit = history.redo(&draft) else { return }
        self.draft = draft
        changed(select: Self.line(of: edit).map { min($0, max(0, draft.lines.count - 1)) })
    }

    private static func line(of edit: TranscriptDraft.Edit) -> Int? {
        switch edit {
        case .words(let line, _, _), .speaker(let line, _, _), .delete(let line, _): line
        case .rename(let renamed): renamed.moved.keys.min()
        }
    }

    // MARK: - Renaming (phase 4)

    /// The menu of names for a line's speaker (docs/meeting-recorder-views.md,
    /// "Rename"): under its name, or at `point` in the view.
    func showRenameMenu(line: Int, at point: NSPoint?) {
        guard let draft, draft.lines.indices.contains(line) else { return }
        view.select(line)
        let voice = draft.lines[line].speaker
        let current = MeetingVoices.name(of: voice, in: draft.names)
        let offered = MeetingVoices.offered(for: voice, lines: draft.lines, names: draft.names, attendees: record.attendees,
                                            ownName: ownName)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = menu.addItem(withTitle: "Rename “\(current)”", action: nil, keyEquivalent: "")
        title.isEnabled = false
        if !offered.fresh.isEmpty { menu.addItem(.separator()) }
        for name in offered.fresh {
            let item = menu.addItem(withTitle: name, action: #selector(renamePicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = RenamePick(line: line, name: name)
        }
        if !offered.given.isEmpty { menu.addItem(.separator()) }
        for given in offered.given {
            let joins = given.voice == .me && voice != .me ? "your lines" : "\(given.name)’s lines"
            let item = menu.addItem(withTitle: "\(given.name) — joins \(joins)", action: #selector(renamePicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = RenamePick(line: line, name: given.name)
        }
        menu.addItem(.separator())
        let other = menu.addItem(withTitle: "Other Name…", action: #selector(otherName(_:)), keyEquivalent: "")
        other.target = self
        other.representedObject = RenamePick(line: line, name: current)
        renameMenu = menu
        let at = point ?? view.speakerPoint(ofLine: line)
        menu.popUp(positioning: nil, at: at, in: view)
        renameMenu = nil
    }

    private final class RenamePick: NSObject {
        let line: Int
        let name: String

        init(line: Int, name: String) {
            self.line = line
            self.name = name
        }
    }

    @objc private func renamePicked(_ item: NSMenuItem) {
        guard let pick = item.representedObject as? RenamePick else { return }
        rename(line: pick.line, to: pick.name)
    }

    @objc private func otherName(_ item: NSMenuItem) {
        guard let pick = item.representedObject as? RenamePick else { return }
        view.beginRenaming(line: pick.line, name: pick.name)
    }

    /// The speaker of `line` given `name` (merged into another of that
    /// name).
    func rename(line: Int, to name: String) {
        guard linesShown, var draft, draft.lines.indices.contains(line) else { return }
        let edit = draft.rename(draft.lines[line].speaker, to: name, ownName: ownName)
        self.draft = draft
        apply(edit, select: line)
    }

    #if SKILLI_SELFTEST
    /// Self-test: the user's own name, as My Card would give it.
    func standInOwnName(_ name: String?) {
        ownName = name
    }

    /// Self-test: a key as the window gets it.
    func press(_ event: NSEvent) -> Bool {
        key(event)
    }

    /// Self-test: the line's field typed and kept, as ↩ does.
    func typeInLine(_ text: String) -> Bool {
        view.commitEditing(text)
    }

    /// Self-test: the name typed in the speaker's field, then ↩.
    func typeName(_ text: String) -> Bool {
        view.commitRenaming(text)
    }

    /// Self-test: the ring a file dragged over the window shows.
    func showDropRing(_ shown: Bool) {
        view.showDropRing(shown)
    }

    /// Self-test: the speaker being named in place.
    var isRenaming: Bool { view.renamingLine != nil }

    /// Self-test: the line's editor as it is now (shown, its text), and
    /// who closed one while it still had the keyboard.
    var editorState: String { view.editorState + "; closed under the keyboard by " + (LineCell.closedUnderKeyboard.last ?? "nobody") }
    #endif

    // MARK: - Transcribe Again (phase 4)

    /// The panel under its button: the language and the engine, used as
    /// picked.
    func showTranscribeAgain() {
        guard draft != nil || record.state == .done, working == nil, !making else { return }
        againPanel?.close()
        let panel = TranscribeAgainPanel(language: made?.language ?? record.language,
                                         engine: TranscriptEngine(stored: made?.engine ?? record.engine) ?? .macOS,
                                         engines: engines(), edited: record.edited == true, languages: languages)
        panel.onTranscribe = { [weak self] language, engine in
            guard let self, self.working == nil, !self.making else { return }
            var record = self.record
            record.language = language
            self.againPanel = nil
            self.onTranscribeAgain?(self.folder, record, engine)
        }
        panel.onClose = { [weak self] in self?.againPanel = nil }
        againPanel = panel
        panel.show(relativeTo: view.transcribeAgainButton)
    }

    func windowWillClose(_ notification: Notification) {
        againPanel?.close()
        player?.pause()
        pictures.forEach { $0.pause() }
        pictures = []
        correcting = [:]
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player = nil
        onClose?(self)
    }
}

/// The window, its keys: space plays, ⌘C copies, ⌘↩ shows the folder, ⌘⌫
/// deletes, ⌘Z undoes (a text being edited keeps its own).
private final class RecordingWindow: NSWindow {
    weak var controller: RecordingWindowController?

    override func keyDown(with event: NSEvent) {
        if controller?.key(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, !(firstResponder is NSText), controller?.key(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Every key's release, whoever has the keyboard: a held key is over.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyUp { controller?.keyReleased(event) }
        super.sendEvent(event)
    }
}

/// The window's content: the header, the player, the transcript (or why
/// there is none yet), the keys.
private final class RecordingView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onPlay: (() -> Void)?
    var onSeek: ((Double, Bool) -> Void)?
    var onTranscribe: ((String) -> Void)?
    /// A key the lines' table got first.
    var onKey: ((NSEvent) -> Bool)?
    /// A line's words kept as typed.
    var onEdited: ((Int, String) -> Void)?
    /// A click on a line's speaker's name, where.
    var onRenameClicked: ((Int, NSPoint) -> Void)?
    /// A name typed for a line's speaker.
    var onRenamed: ((Int, String) -> Void)?
    var onSelect: ((Int?) -> Void)?
    var onTranscribeAgain: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onHint: (() -> Void)?

    private let title = NSTextField(labelWithString: "")
    private let about = NSTextField(labelWithString: "")
    let transcribeAgainButton = NSButton(title: "Transcribe Again…", target: nil, action: nil)
    private let playButton = NSButton()
    private let time = NSTextField(labelWithString: "0:00")
    private let waveform = WaveformView()
    private let topLine = NSView()
    private let bottomLine = NSView()
    private let scroll = NSScrollView()
    private let table = LinesTable()
    private let state = NSTextField(wrappingLabelWithString: "")
    private let languageMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let transcribeButton = NSButton(title: "Transcribe", target: nil, action: nil)
    private let hints = HintBar()
    private let dropRing = DropRing()
    /// A line taught once at the bottom of the lines (Better
    /// transcription); a click acts on it.
    private let hintLine = NSButton(title: "", target: nil, action: nil)
    var hintText: String? { hintLine.isHidden ? nil : hintLine.title }
    /// What the AI is doing for the recording (phase 5), a spinner before it.
    private let workLine = NSTextField(labelWithString: "")
    private let workSpinner = NSProgressIndicator()
    var workText: String? { workLine.isHidden ? nil : workLine.stringValue }
    /// The skillie marked, as it last ran after the transcript (phase 5).
    private let ranLine = NSTextField(labelWithString: "")
    var ranText: String? { ranLine.isHidden ? nil : ranLine.stringValue }
    private(set) var lines: [TranscriptLine] = []
    private(set) var names: [String: String] = [:]
    /// The chapters heading the lines, and the summary above them (phase 5).
    private(set) var chapters: [MeetingRecord.Chapter] = []
    private var summary: (text: String, header: String)?
    var summaryShown: String? { summary?.text }
    var chapterMarks: Int { waveform.chapters.count }
    /// What the table shows: the summary, then the lines said, the slides
    /// read and the chapters' headings, by time.
    private enum Row {
        case summary
        case chapter(MeetingRecord.Chapter, first: Bool)
        case said(TranscriptLine)
        case shown(SlideLog.Slide)

        var start: Double {
            switch self {
            case .summary: -1
            case .chapter(let chapter, _): chapter.start
            case .said(let line): line.start
            case .shown(let slide): slide.start
            }
        }
    }

    private var rows: [Row] = []
    /// Each line said, its row.
    private var rowOfLine: [Int] = []
    private(set) var slides: [SlideLog.Slide] = []
    private let picturesColumn = PicturesColumn()
    var pictureCount: Int { picturesColumn.count }
    /// The lanes' names ("Me", "Them", "Room" in person).
    private var laneNames: [String: String] = [:]
    /// Self-test hook: the lanes, by name.
    var shownLanes: [String] { waveform.lanesShown.map { laneNames[$0.rawValue] ?? $0.title } }
    var showsWaveform: Bool { !waveform.me.isEmpty || !waveform.them.isEmpty }
    var aboutText: String { about.stringValue }
    var hintLabels: [String] { hints.shown.map(\.label) }
    private var languageIDs: [String] = []
    private(set) var litLine: Int?
    /// The line selected (phase 4), by its place in `lines`.
    private(set) var selectedLine: Int?
    /// The line whose words are being edited, and the name being typed.
    private(set) var editingLine: Int?
    /// The edited line's words as typed, for its height: the table must not
    /// be asked for its cell while it measures rows (it raises).
    private var editedText: String?
    private(set) var renamingLine: Int?
    /// Lines that came while a line was edited or renamed: shown once it
    /// ends (a reload would take the editor's cell away).
    private var linesLater: (lines: [TranscriptLine], names: [String: String], slides: [SlideLog.Slide])?
    /// The summary written meanwhile: shown once the line's editor closes.
    private var summaryLater = false
    private var heights: [Int: CGFloat] = [:]
    /// The lines' width as last laid out: their heights are measured at it.
    private var linesWidth: CGFloat = 0
    /// The speakers' column, as wide as the longest name.
    private var speakerWidth: CGFloat = LineCell.minimumSpeakerWidth
    /// The user scrolled the lines: following waits 3 s.
    private var scrolledAt: Date?
    var duration: Double = 0 {
        didSet { waveform.duration = duration }
    }
    private var position: Double = 0
    private var playing = false
    var canTranscribeAgain = false {
        didSet { transcribeAgainButton.isHidden = !canTranscribeAgain }
    }

    var stateText: String { state.isHidden ? "" : state.stringValue }
    var spaceHint: String? { hints.shown.first { $0.key == "space" }?.label }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        about.font = .systemFont(ofSize: 13)
        about.textColor = .secondaryLabelColor
        about.lineBreakMode = .byTruncatingTail
        transcribeAgainButton.bezelStyle = .accessoryBarAction
        transcribeAgainButton.controlSize = .small
        transcribeAgainButton.target = self
        transcribeAgainButton.action = #selector(transcribeAgainPressed)
        transcribeAgainButton.isHidden = true
        playButton.bezelStyle = .circular
        playButton.isBordered = false
        playButton.imagePosition = .imageOnly
        playButton.contentTintColor = .labelColor
        playButton.target = self
        playButton.action = #selector(playPressed)
        playButton.setAccessibilityLabel("Play")
        time.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        time.textColor = .secondaryLabelColor
        waveform.onSeek = { [weak self] seconds, ended in
            self?.position = seconds
            self?.onSeek?(seconds, false)
            if ended { self?.updateTime(playing: false) }
        }
        for line in [topLine, bottomLine] { line.wantsLayer = true }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("line"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(lineClicked)
        table.doubleAction = #selector(lineDoubleClicked)
        table.onKey = { [weak self] event in self?.onKey?(event) ?? false }
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        state.font = .systemFont(ofSize: 14)
        state.textColor = .secondaryLabelColor
        state.alignment = .center
        languageMenu.target = self
        languageMenu.action = #selector(languagePicked)
        transcribeButton.bezelStyle = .push
        transcribeButton.keyEquivalent = "\r"
        transcribeButton.target = self
        transcribeButton.action = #selector(transcribePressed)
        dropRing.isHidden = true
        hintLine.isBordered = false
        hintLine.isHidden = true
        hintLine.alignment = .left
        hintLine.target = self
        hintLine.action = #selector(hintPressed)
        workLine.font = .systemFont(ofSize: 12)
        workLine.textColor = .secondaryLabelColor
        workLine.lineBreakMode = .byTruncatingTail
        workLine.isHidden = true
        workSpinner.style = .spinning
        workSpinner.controlSize = .small
        workSpinner.isDisplayedWhenStopped = false
        ranLine.font = .systemFont(ofSize: 12)
        ranLine.textColor = .secondaryLabelColor
        ranLine.lineBreakMode = .byTruncatingTail
        ranLine.isHidden = true
        for subview in [title, about, transcribeAgainButton, playButton, time, waveform, topLine, scroll, picturesColumn, state, languageMenu,
                        transcribeButton, hintLine, workSpinner, workLine, ranLine, bottomLine, hints, dropRing] as [NSView] {
            addSubview(subview)
        }
        registerForDraggedTypes([.fileURL])
        updateTime(playing: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func header(title text: String, about line: String) {
        title.stringValue = text
        about.stringValue = line
    }

    func showLines(_ lines: [TranscriptLine], names: [String: String], slides: [SlideLog.Slide] = [],
                   chapters: [MeetingRecord.Chapter], summary: (text: String, header: String)?) {
        self.chapters = chapters
        self.summary = summary
        guard editingLine == nil, renamingLine == nil else {
            linesLater = (lines, names, slides)
            return
        }
        linesLater = nil
        summaryLater = false
        self.lines = lines
        self.names = names
        self.slides = slides
        measureSpeakers()
        // A chapter heads the line it starts on (the rows keep this order
        // when they start together).
        let starts = MeetingTranscript.chapterLines(chapters, in: lines).sorted { $0.key < $1.key }
        let headings = starts.enumerated().map { index, start in Row.chapter(start.value, first: index == 0) }
        setRows((summary == nil ? [] : [Row.summary]) + headings + lines.map(Row.said) + slides.map(Row.shown))
        if let selected = selectedLine, selected >= lines.count { selectedLine = nil }
        heights = [:]
        table.reloadData()
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        scroll.isHidden = false
        state.isHidden = !rows.isEmpty
        state.stringValue = rows.isEmpty ? "Nothing was said, or nothing the engine could hear." : ""
        languageMenu.isHidden = true
        transcribeButton.isHidden = true
        needsLayout = true
    }

    /// The lines after a change made here: shown again in place, the
    /// scroll kept, `select` selected.
    func update(lines: [TranscriptLine], names: [String: String], select line: Int?) {
        let origin = scroll.contentView.bounds.origin
        showLines(lines, names: names, slides: slides, chapters: chapters, summary: summary)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
        select(line.flatMap { lines.indices.contains($0) ? $0 : nil }, scrollToIt: true)
    }

    func showTranscribing(_ step: MeetingTranscriber.Step) {
        switch step {
        case .downloading(let language): showState("Downloading the \(language) speech model…")
        case .transcribing(let done): showState("Transcribing… \(Int((done * 100).rounded())) %")
        }
    }

    /// A state in place of the lines (transcribing, importing).
    func showState(_ text: String) {
        // The lines go: a line being edited or renamed is put back first.
        linesLater = nil
        summaryLater = false
        endEditing(keep: false)
        endRenaming(keep: false)
        lines = []
        select(nil)
        setRows([])
        table.reloadData()
        scroll.isHidden = true
        state.isHidden = false
        state.stringValue = text
        languageMenu.isHidden = true
        transcribeButton.isHidden = true
        needsLayout = true
    }

    /// Its transcript waits its turn.
    func showWaiting() {
        showState("Waiting to be transcribed…")
    }

    /// No transcript: the language this Mac could not transcribe, and the
    /// ones it can.
    func showPending(language: String) {
        showState("Not transcribed yet: \(MeetingTranscriber.shortName(of: language)) can't be transcribed on this Mac.")
        languageMenu.isHidden = false
        transcribeButton.isHidden = false
        Task {
            let languages = await MeetingTranscriber.languages()
            languageIDs = languages.map(\.id)
            languageMenu.removeAllItems()
            languageMenu.addItems(withTitles: languages.map(\.name))
            let first = languageIDs.firstIndex { $0.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") } ?? 0
            if !languageIDs.isEmpty { languageMenu.selectItem(at: first) }
            needsLayout = true
        }
        needsLayout = true
    }

    /// The hints by what the keys do now: a line selected, or none (⌘K
    /// lists the rest, Show in Finder ⌘↩ and Delete ⌘⌫ among them).
    func updateHints(canUndo: Bool) {
        let space = playing ? "Pause" : "Play"
        if selectedLine != nil {
            hints.setHints([("Edit", "↩"), ("Next Speaker", "⇥"), ("Rename", "⌥↩"), ("Copy Line", "⌘C"), ("Delete Line", "⌘⌫")])
        } else if lines.isEmpty {
            hints.setHints([(space, "space"), ("Actions", "⌘K")])
        } else {
            hints.setHints([(space, "space"), ("Copy Transcript", "⌘C"), ("Actions", "⌘K")])
        }
    }

    /// ⌘K's own hints while its list is open.
    func setHints(_ shown: [(label: String, key: String)]) {
        hints.setHints(shown)
    }

    /// The lines' table: the window's keys reach the controller through it.
    var linesTable: NSTableView { table }

    /// What the AI is doing now, at the bottom of the lines; nil: nothing.
    func setWork(_ text: String?) {
        workLine.isHidden = text == nil
        workLine.stringValue = text ?? ""
        if text == nil { workSpinner.stopAnimation(nil) } else { workSpinner.startAnimation(nil) }
        needsLayout = true
    }

    /// The summary above the lines, as it is written; nil: none. Its row
    /// alone is drawn again while the lines stay where they are; a line
    /// being edited keeps its editor (shown once it closes).
    func setSummary(_ shown: (text: String, header: String)?) {
        let had = summary != nil
        summary = shown
        guard editingLine == nil, renamingLine == nil else {
            summaryLater = true
            return
        }
        guard !lines.isEmpty || !rows.isEmpty else { return }
        if had, shown != nil, case .summary? = rows.first {
            heights[0] = nil
            table.reloadData(forRowIndexes: [0], columnIndexes: [0])
            table.noteHeightOfRows(withIndexesChanged: [0])
        } else {
            update(lines: lines, names: names, select: selectedLine)
        }
    }

    /// How the skillie marked last ran after the transcript; nil: none.
    func setRan(_ text: String?) {
        guard text != ranText else { return }
        ranLine.isHidden = text == nil
        ranLine.stringValue = text ?? ""
        ranLine.toolTip = text
        needsLayout = true
    }

    /// The chapters' marks on the waveform.
    func setChapterMarks(_ chapters: [MeetingRecord.Chapter]) {
        waveform.chapters = chapters
    }

    func screenFrame(ofChapter index: Int) -> NSRect? {
        let headings = rows.indices.filter { if case .chapter = rows[$0] { true } else { false } }
        guard headings.indices.contains(index), let window else { return nil }
        table.scrollRowToVisible(headings[index])
        return window.convertToScreen(table.convert(table.rect(ofRow: headings[index]), to: nil))
    }

    /// The rows by time (a slide before the line said as it showed),
    /// each line's row noted.
    private func setRows(_ unsorted: [Row]) {
        rows = unsorted.enumerated().sorted { a, b in
            a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
        }.map(\.element)
        rowOfLine = []
        var line = 0
        // The lines keep their order among the rows (two at the same time
        // too): each said row is the next line.
        for (index, row) in rows.enumerated() {
            if case .said = row {
                rowOfLine.append(index)
                line += 1
            }
        }
    }

    /// The speakers' column fits the longest name (up to 160 pt: a first
    /// and a last name).
    private func measureSpeakers() {
        let widest = lines.map { MeetingVoices.name(of: $0.speaker, in: names) }.reduce(CGFloat(0)) { widest, name in
            max(widest, (name as NSString).size(withAttributes: [.font: LineCell.speakerFont]).width)
        }
        let width = min(160, max(LineCell.minimumSpeakerWidth, ceil(widest) + 12))
        if width != speakerWidth {
            speakerWidth = width
            heights = [:]
        }
    }

    func screenFrame(ofLine line: Int) -> NSRect? {
        guard line < rowOfLine.count, let window else { return nil }
        let row = rowOfLine[line]
        table.scrollRowToVisible(row)
        let rect = table.convert(table.rect(ofRow: row), to: nil)
        return window.convertToScreen(rect)
    }

    func screenFrame(ofSpeakerIn line: Int) -> NSRect? {
        guard line < rowOfLine.count, let window else { return nil }
        let row = rowOfLine[line]
        table.scrollRowToVisible(row)
        let rowRect = table.rect(ofRow: row)
        let rect = NSRect(x: rowRect.minX + LineCell.padding, y: rowRect.minY + LineCell.vertical, width: speakerWidth - 6, height: 17)
        return window.convertToScreen(table.convert(rect, to: nil))
    }

    /// Under a line's speaker's name, in this view: where its menu opens.
    func speakerPoint(ofLine line: Int) -> NSPoint {
        guard line < rowOfLine.count else { return NSPoint(x: 28, y: bounds.midY) }
        let rowRect = table.rect(ofRow: rowOfLine[line])
        return convert(NSPoint(x: rowRect.minX + LineCell.padding, y: rowRect.minY + LineCell.vertical + 20), from: table)
    }

    /// The screen's and the webcam's players' layers, beside the lines.
    func setPictures(_ layers: [(AVPlayerLayer, CGSize)]) {
        picturesColumn.set(layers)
        needsLayout = true
    }

    func setPeaks(me: [Float], them: [Float]) {
        waveform.me = me
        waveform.them = them
    }

    /// The lanes' names ("Me", "Them", "Room" in person) and the tracks
    /// that have a lane.
    func setLanes(_ names: [String: String], lanes: [Speaker]) {
        guard names != laneNames || lanes != waveform.lanesShown else { return }
        laneNames = names
        waveform.names = names
        waveform.lanesShown = lanes.isEmpty ? Speaker.allCases : lanes
    }

    /// Where the player is: the time, the playhead, the line lit and kept
    /// in sight.
    func played(to seconds: Double, playing: Bool) {
        guard seconds.isFinite else { return }
        position = seconds
        waveform.position = seconds
        updateTime(playing: playing)
        let line = MeetingTranscript.line(at: seconds + 0.05, in: lines)
        guard line != litLine else { return }
        let previous = litLine
        litLine = line
        for index in [previous, line].compactMap({ $0 }) where index < rowOfLine.count {
            (table.rowView(atRow: rowOfLine[index], makeIfNecessary: false) as? LineRowView)?.isLit = index == line
        }
        if playing, editingLine == nil, renamingLine == nil, let line, line < rowOfLine.count,
           scrolledAt.map({ Date.now.timeIntervalSince($0) > 3 }) ?? true {
            table.scrollRowToVisible(rowOfLine[line])
        }
    }

    private func updateTime(playing: Bool) {
        self.playing = playing
        time.stringValue = "\(MeetingTranscript.clock(position)) / \(MeetingTranscript.clock(duration))"
        playButton.image = Theme.symbol(playing ? "pause.fill" : "play.fill", pointSize: 18, weight: .medium)
        playButton.setAccessibilityLabel(playing ? "Pause" : "Play")
        // Space's hint says what it does now.
        let space = playing ? "Pause" : "Play"
        if let first = hints.shown.first, first.key == "space", first.label != space {
            hints.setHints([(space, "space")] + hints.shown.dropFirst())
        }
    }

    @objc private func playPressed() { onPlay?() }

    @objc private func transcribeAgainPressed() { onTranscribeAgain?() }

    @objc private func hintPressed() { onHint?() }

    func setHint(_ text: String?) {
        hintLine.isHidden = text == nil
        hintLine.attributedTitle = NSAttributedString(string: text ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        needsLayout = true
    }

    @objc private func scrolled() { scrolledAt = .now }

    @objc private func languagePicked() {}

    @objc private func transcribePressed() {
        let index = languageMenu.indexOfSelectedItem
        guard languageIDs.indices.contains(index) else { return }
        onTranscribe?(languageIDs[index])
    }

    // MARK: - Selecting, editing (phase 4)

    /// `line` selected (nil: none), the ring drawn on its row, the keys
    /// said.
    func select(_ line: Int?, scrollToIt: Bool = false) {
        let line = line.flatMap { lines.indices.contains($0) ? $0 : nil }
        let previous = selectedLine
        selectedLine = line
        for index in [previous, line].compactMap({ $0 }) where index < rowOfLine.count {
            (table.rowView(atRow: rowOfLine[index], makeIfNecessary: false) as? LineRowView)?.isPicked = index == line
        }
        if let line, scrollToIt, line < rowOfLine.count { table.scrollRowToVisible(rowOfLine[line]) }
        if line != nil, window?.firstResponder !== table { window?.makeFirstResponder(table) }
        onSelect?(line)
    }

    /// ↑ ↓: the line before or after the selected one (none selected: the
    /// one playing, else the first or the last).
    func moveSelection(_ step: Int) {
        guard !lines.isEmpty else { return }
        let from = selectedLine ?? litLine.map { $0 - step } ?? (step > 0 ? -1 : lines.count)
        select(min(max(0, from + step), lines.count - 1), scrollToIt: true)
    }

    /// ↩ on a line: its words a text view in place, the caret at the end;
    /// ↩ keeps, esc puts back, a click elsewhere keeps.
    func beginEditing(line: Int) {
        guard line < rowOfLine.count, let cell = table.view(atColumn: 0, row: rowOfLine[line], makeIfNecessary: true) as? LineCell else { return }
        endRenaming(keep: false)
        editingLine = line
        cell.beginEditing(onEnd: { [weak self] keep in self?.endEditing(keep: keep) },
                          onChange: { [weak self, weak cell] in self?.editedTextChanged(cell?.editor.string) })
        editedText = cell.editor.string
        window?.makeFirstResponder(cell.editor)
        cell.editor.moveToEndOfDocument(nil)
    }

    /// The line grows as its words wrap.
    private func editedTextChanged(_ text: String?) {
        guard let line = editingLine, line < rowOfLine.count else { return }
        editedText = text
        heights[rowOfLine[line]] = nil
        table.noteHeightOfRows(withIndexesChanged: [rowOfLine[line]])
    }

    /// "Other Name…": the speaker's name a field over its line.
    func beginRenaming(line: Int, name: String) {
        guard line < rowOfLine.count, let cell = table.view(atColumn: 0, row: rowOfLine[line], makeIfNecessary: true) as? LineCell else { return }
        endEditing(keep: false)
        renamingLine = line
        cell.beginRenaming(name, delegate: self)
        window?.makeFirstResponder(cell.nameField)
        cell.nameField.currentEditor()?.selectAll(nil)
    }

    /// The field being edited, kept (↩, a click elsewhere) or put back
    /// (esc).
    private func endEditing(keep: Bool) {
        guard let line = editingLine, line < rowOfLine.count,
              let cell = table.view(atColumn: 0, row: rowOfLine[line], makeIfNecessary: false) as? LineCell else {
            editingLine = nil
            editedText = nil
            showLinesLater()
            return
        }
        editingLine = nil
        editedText = nil
        let text = cell.editor.string
        cell.endEditing()
        window?.makeFirstResponder(table)
        if keep { onEdited?(line, text) } else { table.reloadData(forRowIndexes: [rowOfLine[line]], columnIndexes: [0]) }
        showLinesLater()
    }

    private func endRenaming(keep: Bool) {
        guard let line = renamingLine, line < rowOfLine.count,
              let cell = table.view(atColumn: 0, row: rowOfLine[line], makeIfNecessary: false) as? LineCell else {
            renamingLine = nil
            showLinesLater()
            return
        }
        renamingLine = nil
        let text = (cell.nameField.currentEditor() as? NSTextView)?.string ?? cell.nameField.stringValue
        window?.makeFirstResponder(table)
        cell.endRenaming()
        if keep { onRenamed?(line, text) }
        showLinesLater()
    }

    /// The lines that came meanwhile, unless the change just kept showed
    /// newer ones; the summary written meanwhile.
    private func showLinesLater() {
        if let later = linesLater {
            showLines(later.lines, names: later.names, slides: later.slides, chapters: chapters, summary: summary)
        } else if summaryLater {
            summaryLater = false
            update(lines: lines, names: names, select: selectedLine)
        }
    }

    #if SKILLI_SELFTEST
    func commitEditing(_ text: String) -> Bool {
        guard let line = editingLine, line < rowOfLine.count,
              let cell = table.view(atColumn: 0, row: rowOfLine[line], makeIfNecessary: false) as? LineCell else { return false }
        cell.editor.string = text
        endEditing(keep: true)
        return true
    }

    func showDropRing(_ shown: Bool) {
        dropRing.isHidden = !shown
    }

    var editorState: String {
        guard let line = editingLine, line < rowOfLine.count,
              let cell = table.view(atColumn: 0, row: rowOfLine[line], makeIfNecessary: false) as? LineCell else { return "no cell for the line" }
        return "editor shown \(!cell.editor.isHidden), in the window \(cell.editor.window != nil), text “\(cell.editor.string.prefix(30))”"
    }

    func commitRenaming(_ text: String) -> Bool {
        guard let line = renamingLine, line < rowOfLine.count,
              let cell = table.view(atColumn: 0, row: rowOfLine[line], makeIfNecessary: false) as? LineCell else { return false }
        cell.nameField.stringValue = text
        endRenaming(keep: true)
        return true
    }
    #endif

    /// The name typed in place: ↩ keeps, esc puts back.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard renamingLine != nil else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            endRenaming(keep: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endRenaming(keep: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // A click elsewhere keeps the name typed.
        if renamingLine != nil, (notification.object as? NSTextField) is LineNameField { endRenaming(keep: true) }
    }

    // MARK: - Lines

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .summary:
            let cell = tableView.makeView(withIdentifier: SummaryCell.identifier, owner: nil) as? SummaryCell ?? SummaryCell()
            if let summary { cell.show(summary.text, header: summary.header) }
            return cell
        case .chapter(let chapter, let first):
            let cell = tableView.makeView(withIdentifier: ChapterCell.identifier, owner: nil) as? ChapterCell ?? ChapterCell()
            cell.show(chapter, first: first)
            return cell
        case .said, .shown:
            break
        }
        let cell = tableView.makeView(withIdentifier: LineCell.identifier, owner: nil) as? LineCell ?? LineCell()
        // The line being edited or renamed, asked for again as it grows:
        // left as it is (shown again, its editor would close under the
        // keyboard).
        if cell.isEditing, [editingLine, renamingLine].contains(where: { $0.map { $0 < rowOfLine.count && rowOfLine[$0] == row } ?? false }) {
            return cell
        }
        cell.speakerWidth = speakerWidth
        switch rows[row] {
        case .said(let line): cell.show(line, name: MeetingVoices.name(of: line.speaker, in: names))
        case .shown(let slide): cell.show(slide)
        case .summary, .chapter: break
        }
        cell.onName = { [weak self, weak cell] in
            guard let self, let cell, let line = self.rowOfLine.firstIndex(of: self.table.row(for: cell)) else { return }
            self.onRenameClicked?(line, self.speakerPoint(ofLine: line))
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LineRowView()
        rowView.isLit = litLine.map { $0 < rowOfLine.count && rowOfLine[$0] == row } ?? false
        rowView.isPicked = selectedLine.map { $0 < rowOfLine.count && rowOfLine[$0] == row } ?? false
        return rowView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if let height = heights[row] { return height }
        // Before the first layout: the window's starting width.
        let width = linesWidth > 0 ? linesWidth : 712
        let text: String
        switch rows[row] {
        case .summary:
            let height = summary.map { SummaryCell.height(of: $0.text, width: width) } ?? 1
            heights[row] = height
            return height
        case .chapter(_, let first):
            heights[row] = ChapterCell.height(first: first)
            return ChapterCell.height(first: first)
        case .said(let line): text = line.text
        case .shown(let slide): text = LineCell.text(of: slide)
        }
        var height = LineCell.height(of: text, width: width, speakerWidth: speakerWidth)
        // Being edited: the words as typed.
        if let line = editingLine, line < rowOfLine.count, rowOfLine[line] == row, let typed = editedText {
            height = max(height, LineCell.height(of: typed, width: linesWidth > 0 ? linesWidth : 712, speakerWidth: speakerWidth))
        }
        heights[row] = height
        return height
    }

    /// A click on a line selects it and plays from its start (the one
    /// playing too: from its start again); a slide plays from its time.
    @objc private func lineClicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count else { return }
        // The summary is read, not played.
        if case .summary = rows[row] { return }
        scrolledAt = nil
        if let line = rowOfLine.firstIndex(of: row) {
            if editingLine != nil, editingLine != line { endEditing(keep: true) }
            select(line)
        } else {
            select(nil)
        }
        onSeek?(rows[row].start, true)
    }

    @objc private func lineDoubleClicked() {
        let row = table.clickedRow
        guard let line = rowOfLine.firstIndex(of: row) else { return }
        select(line)
        beginEditing(line: line)
    }

    // MARK: - A file dropped: imported

    private func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .audiovisualContent)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedFiles(sender).isEmpty else { return [] }
        dropRing.isHidden = false
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropRing.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropRing.isHidden = true
        let files = droppedFiles(sender)
        guard !files.isEmpty else { return false }
        onDrop?(files)
        return true
    }

    // MARK: - Layout

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for line in [topLine, bottomLine] { line.layer?.backgroundColor = Theme.hairline.cgColor }
    }

    override func layout() {
        super.layout()
        for line in [topLine, bottomLine] { line.layer?.backgroundColor = Theme.hairline.cgColor }
        let inset: CGFloat = 28
        let width = bounds.width
        let inner = width - 2 * inset
        var y: CGFloat = 22
        title.frame = NSRect(x: inset, y: y, width: inner, height: 28)
        y += 30
        transcribeAgainButton.sizeToFit()
        let again = transcribeAgainButton.isHidden ? 0 : transcribeAgainButton.frame.width + 12
        transcribeAgainButton.frame.origin = NSPoint(x: width - inset - transcribeAgainButton.frame.width, y: y - 2)
        about.frame = NSRect(x: inset, y: y, width: inner - again, height: 18)
        y += 32
        playButton.frame = NSRect(x: inset - 4, y: y - 4, width: 32, height: 32)
        time.sizeToFit()
        time.frame.origin = NSPoint(x: inset + 36, y: y + 3)
        y += 34
        waveform.frame = NSRect(x: inset, y: y, width: inner, height: 84)
        y += 84 + 16
        topLine.frame = NSRect(x: 0, y: y, width: width, height: 1)
        let bottom = bounds.height - 44
        bottomLine.frame = NSRect(x: 0, y: bottom, width: width, height: 1)
        hints.frame = NSRect(x: inset, y: bottom + 12, width: inner, height: 20)
        hints.setHints(hints.shown)
        // The pictures' column on the right, beside the lines.
        let columnWidth = picturesColumn.count > 0 ? PicturesColumn.width : 0
        picturesColumn.isHidden = columnWidth == 0
        picturesColumn.frame = NSRect(x: width - inset - columnWidth, y: y + 16, width: columnWidth, height: max(0, bottom - y - 32))
        let linesInner = columnWidth > 0 ? inner - columnWidth - 20 : inner
        // Under the lines: the hint taught once, the skillie that ran, what
        // the AI is doing.
        let hintHeight: CGFloat = hintLine.isHidden ? 0 : 30
        let ranHeight: CGFloat = ranLine.isHidden ? 0 : 26
        let workHeight: CGFloat = workLine.isHidden ? 0 : 28
        hintLine.frame = NSRect(x: inset, y: bottom - hintHeight + 6, width: linesInner, height: 18)
        ranLine.frame = NSRect(x: inset, y: bottom - hintHeight - ranHeight + 6, width: linesInner, height: 18)
        let workY = bottom - hintHeight - ranHeight - workHeight + 6
        workSpinner.frame = NSRect(x: inset, y: workY + 1, width: 16, height: 16)
        workLine.frame = NSRect(x: inset + 22, y: workY, width: max(0, linesInner - 22), height: 18)
        let notes = hintHeight + ranHeight + workHeight
        scroll.frame = NSRect(x: inset - 12, y: y + 1, width: linesInner + 24, height: max(0, bottom - y - 1 - notes))
        let tableWidth = scroll.contentSize.width
        if tableWidth != linesWidth {
            linesWidth = tableWidth
            table.tableColumns.first?.width = tableWidth
            // Wrapped lines take another height at another width.
            heights = [:]
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        }
        let stateHeight = state.isHidden ? 0 : (state.stringValue as NSString).boundingRect(
            with: NSSize(width: min(inner, 460), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: state.font!]).height + 4
        let middle = y + (bottom - y) / 2
        let block = stateHeight + (languageMenu.isHidden ? 0 : 44)
        state.frame = NSRect(x: (width - min(inner, 460)) / 2, y: middle - block / 2, width: min(inner, 460), height: stateHeight)
        languageMenu.sizeToFit()
        transcribeButton.sizeToFit()
        let rowWidth = languageMenu.frame.width + 12 + transcribeButton.frame.width
        languageMenu.frame.origin = NSPoint(x: (width - rowWidth) / 2, y: state.frame.maxY + 14)
        transcribeButton.frame.origin = NSPoint(x: languageMenu.frame.maxX + 12, y: state.frame.maxY + 12)
        dropRing.frame = bounds.insetBy(dx: 8, dy: 8)
    }
}

/// The lines' table: its keys go to the window's first (space, ↑ ↓, ↩, ⇥,
/// esc on a line), the rest as a table has them.
private final class LinesTable: NSTableView {
    var onKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// The line playing: the selection's soft capsule; the line selected: a
/// ring in the accent color on the same shape (both: both).
private final class LineRowView: NSTableRowView {
    var isLit = false {
        didSet { if isLit != oldValue { needsDisplay = true } }
    }
    var isPicked = false {
        didSet { if isPicked != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 4.75, dy: 0.75), xRadius: Theme.Radius.row, yRadius: Theme.Radius.row)
        if isLit {
            Theme.selectionFill.setFill()
            shape.fill()
        }
        if isPicked {
            NSColor.controlAccentColor.setStroke()
            shape.lineWidth = 1.5
            shape.stroke()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// A line's words while they are edited (↩ keeps, esc puts back, the
/// keyboard going elsewhere keeps): a text view of its own over the words'
/// label, so its keys are its own whatever a field would do with them.
private final class LineWordsEditor: NSTextView {
    var onEnd: ((Bool) -> Void)?
    var onChange: (() -> Void)?
    private var ended = true

    func begin(_ text: String) {
        string = text
        ended = false
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (flags, Int(event.keyCode)) {
        case ([], kVK_Return), ([], kVK_ANSI_KeypadEnter): end(keep: true)
        case ([], kVK_Escape): end(keep: false)
        default: super.keyDown(with: event)
        }
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)): end(keep: true)
        case #selector(cancelOperation(_:)): end(keep: false)
        default: super.doCommand(by: selector)
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { end(keep: true) }
        return resigned
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?()
    }

    private func end(keep: Bool) {
        guard !ended else { return }
        ended = true
        onEnd?(keep)
    }
}

/// The speaker's name typed in place ("Other Name…").
private final class LineNameField: NSTextField {}

/// One line: who, when, what was said. A click on the speaker's name
/// opens its menu of names.
private final class LineCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("transcript-line")
    private static let textFont = NSFont.systemFont(ofSize: 13)
    static let speakerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let minimumSpeakerWidth: CGFloat = 56
    private static let timeWidth: CGFloat = 54
    static let padding: CGFloat = 12
    static let vertical: CGFloat = 7
    private let speaker = SpeakerLabel(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    let words = NSTextField(wrappingLabelWithString: "")
    let editor = LineWordsEditor()
    let nameField = LineNameField(string: "")
    var speakerWidth: CGFloat = minimumSpeakerWidth {
        didSet { if speakerWidth != oldValue { needsLayout = true } }
    }
    var onName: (() -> Void)?
    /// Its words or its speaker's name are being typed.
    var isEditing: Bool { !editor.isHidden || !nameField.isHidden }
    #if SKILLI_SELFTEST
    nonisolated(unsafe) static var closedUnderKeyboard: [String] = []
    #endif

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        speaker.font = Self.speakerFont
        speaker.lineBreakMode = .byTruncatingTail
        speaker.onClick = { [weak self] in self?.onName?() }
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        time.textColor = .tertiaryLabelColor
        words.font = Self.textFont
        words.textColor = .labelColor
        words.isSelectable = false
        editor.font = Self.textFont
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = true
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 2
        editor.textContainer?.widthTracksTextView = true
        editor.isHidden = true
        nameField.font = Self.speakerFont
        nameField.drawsBackground = true
        nameField.backgroundColor = .textBackgroundColor
        nameField.isHidden = true
        nameField.placeholderString = "Name"
        for subview in [speaker, time, words, editor, nameField] { addSubview(subview) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func show(_ line: TranscriptLine, name: String) {
        endEditing()
        endRenaming()
        speaker.stringValue = name
        speaker.textColor = line.speaker == .me ? .controlAccentColor : .secondaryLabelColor
        speaker.isClickable = true
        time.stringValue = MeetingTranscript.clock(line.start)
        words.stringValue = line.text
        words.textColor = .labelColor
        needsLayout = true
    }

    /// A slide read on screen: "Screen", its lines joined, quieter than
    /// what was said.
    func show(_ slide: SlideLog.Slide) {
        endEditing()
        endRenaming()
        speaker.stringValue = "Screen"
        speaker.textColor = .tertiaryLabelColor
        speaker.isClickable = false
        time.stringValue = MeetingTranscript.clock(slide.start)
        words.stringValue = Self.text(of: slide)
        words.textColor = .secondaryLabelColor
        needsLayout = true
    }

    func beginEditing(onEnd: @escaping (Bool) -> Void, onChange: @escaping () -> Void) {
        editor.onEnd = onEnd
        editor.onChange = onChange
        editor.begin(words.stringValue)
        editor.isHidden = false
        words.isHidden = true
        needsLayout = true
    }

    func endEditing() {
        guard !editor.isHidden else { return }
        #if SKILLI_SELFTEST
        // Self-test: closed while it still had the keyboard, and by whom.
        if window?.firstResponder === editor {
            LineCell.closedUnderKeyboard.append(Thread.callStackSymbols.dropFirst().prefix(5)
                .map { $0.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).prefix(1).joined() }.joined(separator: " < "))
        }
        #endif
        editor.onEnd = nil
        editor.onChange = nil
        editor.isHidden = true
        words.isHidden = false
    }

    func beginRenaming(_ name: String, delegate: NSTextFieldDelegate) {
        nameField.stringValue = name
        nameField.delegate = delegate
        nameField.isHidden = false
        speaker.isHidden = true
        needsLayout = true
    }

    func endRenaming() {
        guard !nameField.isHidden else { return }
        nameField.isHidden = true
        nameField.delegate = nil
        speaker.isHidden = false
    }

    static func text(of slide: SlideLog.Slide) -> String {
        slide.lines.joined(separator: " · ")
    }

    static func height(of text: String, width: CGFloat, speakerWidth: CGFloat = minimumSpeakerWidth) -> CGFloat {
        let textWidth = max(80, width - padding * 2 - speakerWidth - timeWidth)
        let measured = (text as NSString).boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: textFont]).height
        return ceil(max(measured, 17)) + vertical * 2
    }

    override func layout() {
        super.layout()
        let x = Self.padding
        speaker.frame = NSRect(x: x, y: Self.vertical, width: speakerWidth - 6, height: 17)
        nameField.frame = NSRect(x: x - 3, y: Self.vertical - 3, width: max(160, speakerWidth + Self.timeWidth - 8), height: 22)
        time.frame = NSRect(x: x + speakerWidth, y: Self.vertical + 1, width: Self.timeWidth - 6, height: 16)
        let left = x + speakerWidth + Self.timeWidth
        words.frame = NSRect(x: left, y: Self.vertical, width: max(0, bounds.width - left - Self.padding), height: bounds.height - Self.vertical * 2)
        editor.frame = words.frame.insetBy(dx: -2, dy: 0)
    }
}

/// The summary above the lines (phase 5): who wrote it and when,
/// letterspaced, then its Markdown as the card draws it.
private final class SummaryCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("transcript-summary")
    private static let font = NSFont.systemFont(ofSize: 13)
    private static let headerHeight: CGFloat = 16
    private let header = NSTextField(labelWithString: "")
    private let words = NSTextField(wrappingLabelWithString: "")
    private let line = HairlineView()

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        header.font = Theme.Font.sectionHeader
        header.textColor = .secondaryLabelColor
        words.isSelectable = false
        for subview in [header, words, line] { addSubview(subview) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func show(_ text: String, header title: String) {
        header.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: Theme.Font.sectionHeader, .foregroundColor: NSColor.secondaryLabelColor, .kern: 0.6,
        ])
        words.attributedStringValue = Self.styled(text)
        needsLayout = true
    }

    static func styled(_ text: String) -> NSAttributedString {
        CardMarkdown.render(text, font: font, color: .labelColor)
    }

    /// Its height at `width`: the header, the summary wrapped, a margin
    /// and the hairline under it.
    static func height(of text: String, width: CGFloat) -> CGFloat {
        let measured = styled(text).boundingRect(with: NSSize(width: max(80, width - LineCell.padding * 2), height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        return LineCell.vertical + headerHeight + 6 + ceil(measured) + 18
    }

    override func layout() {
        super.layout()
        let x = LineCell.padding
        let width = max(0, bounds.width - x * 2)
        header.frame = NSRect(x: x, y: LineCell.vertical, width: width, height: Self.headerHeight)
        words.frame = NSRect(x: x, y: header.frame.maxY + 6, width: width, height: max(0, bounds.height - header.frame.maxY - 6 - 18))
        line.frame = NSRect(x: x, y: bounds.height - 6, width: width, height: 1)
    }
}

/// A chapter's heading among the lines (phase 5): its title, its time on
/// the right; a hairline above it but the first.
private final class ChapterCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("transcript-chapter")
    private let title = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let line = HairlineView()
    private var first = false

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        time.textColor = .tertiaryLabelColor
        time.alignment = .right
        for subview in [line, title, time] { addSubview(subview) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func show(_ chapter: MeetingRecord.Chapter, first: Bool) {
        self.first = first
        title.stringValue = chapter.title
        time.stringValue = MeetingTranscript.clock(chapter.start)
        line.isHidden = first
        setAccessibilityLabel("Chapter: \(chapter.title)")
        needsLayout = true
    }

    static func height(first: Bool) -> CGFloat { first ? 34 : 46 }

    override func layout() {
        super.layout()
        let x = LineCell.padding
        let top: CGFloat = first ? 8 : 20
        line.frame = NSRect(x: x, y: 8, width: max(0, bounds.width - x * 2), height: 1)
        time.frame = NSRect(x: bounds.width - x - 60, y: top + 3, width: 60, height: 16)
        title.frame = NSRect(x: x, y: top, width: max(0, bounds.width - x * 2 - 68), height: 20)
    }
}

/// A speaker's name: a click opens its menu of names (the pointing hand
/// says so).
private final class SpeakerLabel: NSTextField {
    var onClick: (() -> Void)?
    var isClickable = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    override func mouseDown(with event: NSEvent) {
        if isClickable, let onClick { onClick() } else { super.mouseDown(with: event) }
    }

    override func resetCursorRects() {
        if isClickable { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

/// While a file is dragged over the window: a ring in the accent color
/// and what a drop does.
private final class DropRing: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        // The window's lines dimmed under it, so what it says reads.
        NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
        shape.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        shape.fill()
        NSColor.controlAccentColor.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        let text = NSAttributedString(string: "Drop to import it as a recording", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.controlAccentColor,
        ])
        let size = text.size()
        var y = (bounds.height - size.height) / 2
        if let symbol = Theme.symbol("square.and.arrow.down", pointSize: 30, weight: .medium) {
            let tinted = symbol.tinted(.controlAccentColor)
            y += (tinted.size.height + 10) / 2
            tinted.draw(in: NSRect(x: (bounds.width - tinted.size.width) / 2, y: y - tinted.size.height - 10, width: tinted.size.width,
                                   height: tinted.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The screen and the webcam beside the lines (phase 3): the screen at
/// its own shape across the column, the webcam under it at half its
/// width, corners of 10 pt, black behind the picture.
private final class PicturesColumn: NSView {
    static let width: CGFloat = 260
    private var shown: [(view: NSView, size: CGSize)] = []

    var count: Int { shown.count }

    override var isFlipped: Bool { true }

    func set(_ layers: [(AVPlayerLayer, CGSize)]) {
        shown.forEach { $0.view.removeFromSuperview() }
        shown = layers.map { layer, size in
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.layer?.cornerRadius = 10
            view.layer?.masksToBounds = true
            layer.videoGravity = .resizeAspect
            view.layer?.addSublayer(layer)
            addSubview(view)
            return (view, size)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for (index, picture) in shown.enumerated() {
            // The first (the screen, or the webcam alone) across; a second
            // (the webcam under the screen) at half the width.
            let width = index == 0 ? bounds.width : (bounds.width / 2).rounded()
            let ratio = picture.size.width > 0 ? picture.size.height / picture.size.width : 9.0 / 16
            let height = min((width * ratio).rounded(), max(0, bounds.height - y))
            picture.view.frame = NSRect(x: 0, y: y, width: width, height: height)
            picture.view.layer?.sublayers?.first?.frame = picture.view.bounds
            y += height + 12
        }
    }
}

/// Both sides' waveforms, Me above in the accent color, Them below (in
/// person, the room's alone); the playhead. A click or a drag seeks.
private final class WaveformView: NSView {
    var me: [Float] = [] { didSet { needsDisplay = true } }
    var them: [Float] = [] { didSet { needsDisplay = true } }
    var names: [String: String] = [:] { didSet { needsDisplay = true } }
    var lanesShown: [Speaker] = Speaker.allCases { didSet { needsDisplay = true } }
    var duration: Double = 0 {
        didSet {
            needsDisplay = true
            updateTips()
        }
    }
    var position: Double = 0 { didSet { if position != oldValue { needsDisplay = true } } }
    /// The chapters' starts, marked across the lanes (phase 5); the pointer
    /// over one says its title.
    var chapters: [MeetingRecord.Chapter] = [] {
        didSet {
            needsDisplay = true
            updateTips()
        }
    }
    var onSeek: ((Double, Bool) -> Void)?
    private static let labelWidth: CGFloat = 48

    override var isFlipped: Bool { true }

    private var lanes: NSRect {
        NSRect(x: Self.labelWidth, y: 0, width: max(1, bounds.width - Self.labelWidth), height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let lanes = self.lanes
        let half = lanes.height / CGFloat(max(1, lanesShown.count))
        for (index, speaker) in lanesShown.enumerated() {
            let top = CGFloat(index) * half
            let label = NSAttributedString(string: names[speaker.rawValue] ?? speaker.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: speaker == .me ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            ])
            label.draw(with: NSRect(x: 0, y: top + (half - label.size().height) / 2, width: Self.labelWidth - 4, height: label.size().height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            let peaks = speaker == .me ? me : them
            let color = speaker == .me ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: NSRect(x: lanes.minX, y: top + 3, width: lanes.width, height: half - 6), xRadius: 6, yRadius: 6).fill()
            guard !peaks.isEmpty else { continue }
            // One bar per 3 pt, the loudest of the buckets under it.
            let bars = max(1, Int(lanes.width / 3))
            let played = duration > 0 ? CGFloat(position / duration) * lanes.width : 0
            for bar in 0..<bars {
                let from = bar * peaks.count / bars, to = max(from + 1, (bar + 1) * peaks.count / bars)
                let value = CGFloat(peaks[from..<min(to, peaks.count)].max() ?? 0)
                let height = max(1, value * (half - 10))
                let x = lanes.minX + CGFloat(bar) * 3
                (x <= lanes.minX + played ? color : color.withAlphaComponent(0.45)).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: top + half / 2 - height / 2, width: 2, height: height), xRadius: 1, yRadius: 1).fill()
            }
        }
        if duration > 0 {
            // The chapters: a line across the lanes, a notch on top.
            NSColor.tertiaryLabelColor.setFill()
            for chapter in chapters {
                let x = chapterX(chapter)
                NSRect(x: x - 0.5, y: 0, width: 1, height: bounds.height).fill()
                let notch = NSBezierPath()
                notch.move(to: NSPoint(x: x - 4, y: 0))
                notch.line(to: NSPoint(x: x + 4, y: 0))
                notch.line(to: NSPoint(x: x, y: 5))
                notch.close()
                notch.fill()
            }
            let x = lanes.minX + CGFloat(min(1, position / duration)) * lanes.width
            NSColor.labelColor.setFill()
            NSRect(x: x.rounded() - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
    }

    private func chapterX(_ chapter: MeetingRecord.Chapter) -> CGFloat {
        (lanes.minX + CGFloat(min(1, max(0, chapter.start / max(duration, 0.001)))) * lanes.width).rounded()
    }

    /// The tool tips' owners: AppKit keeps them weakly.
    private var tipOwners: [NSString] = []

    /// Each chapter's title, said by the pointer over its mark.
    private func updateTips() {
        removeAllToolTips()
        tipOwners = []
        guard duration > 0 else { return }
        for chapter in chapters {
            let owner = chapter.title as NSString
            tipOwners.append(owner)
            addToolTip(NSRect(x: chapterX(chapter) - 5, y: 0, width: 10, height: bounds.height), owner: owner, userData: nil)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTips()
    }

    override func mouseDown(with event: NSEvent) {
        seek(event, ended: false)
    }

    override func mouseDragged(with event: NSEvent) {
        seek(event, ended: false)
    }

    override func mouseUp(with event: NSEvent) {
        seek(event, ended: true)
    }

    private func seek(_ event: NSEvent, ended: Bool) {
        guard duration > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let fraction = min(1, max(0, (point.x - lanes.minX) / lanes.width))
        position = Double(fraction) * duration
        onSeek?(position, ended)
    }

    override func resetCursorRects() {
        addCursorRect(lanes, cursor: .pointingHand)
    }
}
