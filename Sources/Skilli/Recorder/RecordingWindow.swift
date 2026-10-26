import AppKit
import AVFoundation
import Carbon.HIToolbox
import SkilliCore

/// A recording's window (docs/meeting-recorder-views.md): a window, not a
/// card, since it is read and played. The player with both sides'
/// waveforms, then the transcript, a line each, Me or Them, the slides
/// read on screen among them at their time; a click plays from a line,
/// the line playing is lit and followed. The webcam and the screen play
/// small beside it, in step (phase 3). Built when opened, released when
/// closed.
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
    /// Loading it: once, however often the window is shown meanwhile.
    private var loadingPlayer = false
    private var observer: Any?
    var onClose: ((RecordingWindowController) -> Void)?
    var onDelete: ((URL, MeetingRecord) -> Void)?
    var onShowFolder: ((URL) -> Void)?
    /// A transcript waiting for a language: made in the one picked.
    var onTranscribe: ((URL, MeetingRecord) -> Void)?

    init(folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File?) {
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
        show(record, transcript: transcript)
    }

    var isVisible: Bool { window.isVisible }
    var nsWindow: NSWindow { window }
    /// Self-test hooks.
    var shownLines: [TranscriptLine] { view.lines }
    var playing: Bool { (player?.rate ?? 0) > 0 }
    var currentTime: Double { player?.currentTime().seconds ?? 0 }
    var litLine: Int? { view.litLine }
    var shownState: String { view.stateText }
    var spaceHint: String? { view.spaceHint }
    var shownLanes: [String] { view.shownLanes }
    var shownAbout: String { view.aboutText }
    var shownSlides: [SlideLog.Slide] { view.slides }
    var shownPictures: Int { view.pictureCount }
    /// Where the screen's and the webcam's players are, and the sound's.
    var pictureTimes: [Double] { pictures.map { $0.currentTime().seconds } }
    /// Where a line is on screen (AppKit's coordinates), to click it.
    func screenFrame(ofLine row: Int) -> NSRect? { view.screenFrame(ofLine: row) }

    /// What the folder holds now: the transcript once made, or why there is
    /// none.
    func show(_ record: MeetingRecord, transcript: MeetingTranscript.File?, transcribing: MeetingTranscriber.Step? = nil) {
        self.record = record
        window.title = record.title
        view.header(title: record.title, about: MeetingTranscriber.about(record))
        // In person, the microphone holds the room: one lane, its name.
        view.setSpeakers(record.speakers, lanes: Speaker.allCases.filter { !(record.unused ?? []).contains($0) })
        if let transcribing {
            view.showTranscribing(transcribing)
        } else if let transcript {
            view.showLines(transcript.lines, slides: Self.slides(in: folder))
        } else if record.state == .transcribing || record.state == .stopped {
            // Its turn not come yet (another being made, or the launch's).
            view.showWaiting()
        } else {
            view.showPending(language: record.language)
        }
        if player == nil, !loadingPlayer { loadPlayer() }
    }

    func present() {
        Foreground.bring(window)
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
        loadingPlayer = true
        let urls = Speaker.allCases.map { folder.appendingPathComponent($0.file) }
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
        }
        Task.detached(priority: .utility) {
            let peaks = urls.map { RecordingWindowController.peaks(of: $0) }
            await MainActor.run { [weak self] in self?.view.setPeaks(me: peaks[0], them: peaks[1]) }
        }
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
    }

    /// While playing, a picture more than a frame off the sound (a file
    /// that ended and held, a seek still on its way) is put back in step.
    private func keepPicturesInStep() {
        guard let player, player.rate > 0, !pictures.isEmpty else { return }
        let now = player.currentTime()
        for picture in pictures {
            guard let item = picture.currentItem, item.duration.isNumeric else { continue }
            let wanted = min(now.seconds, item.duration.seconds)
            if abs(picture.currentTime().seconds - wanted) > 0.07, now.seconds < item.duration.seconds {
                let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 20))
                picture.setRate(1, time: CMTimeAdd(now, CMTime(value: 1, timescale: 20)), atHostTime: host)
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

    fileprivate func key(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        switch (flags, code) {
        case ([], kVK_Space):
            togglePlay()
        case (.command, kVK_ANSI_C) where view.lines.isEmpty == false:
            copyTranscript()
        case (.command, kVK_Return), (.command, kVK_ANSI_KeypadEnter):
            onShowFolder?(folder)
        case (.command, kVK_Delete):
            player?.pause()
            pictures.forEach { $0.pause() }
            onDelete?(folder, record)
        default:
            return false
        }
        return true
    }

    /// ⌘C: the transcript, as `transcript.md` has it.
    func copyTranscript() {
        let text = (try? String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8))
            ?? MeetingTranscriber.markdown(record, lines: view.lines)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func transcribe(in language: String) {
        var record = record
        record.language = language
        self.record = record
        onTranscribe?(folder, record)
    }

    func windowWillClose(_ notification: Notification) {
        player?.pause()
        pictures.forEach { $0.pause() }
        pictures = []
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player = nil
        onClose?(self)
    }
}

/// The window, its keys: space plays, ⌘C copies, ⌘↩ shows the folder, ⌘⌫
/// deletes (a text being edited keeps its own).
private final class RecordingWindow: NSWindow {
    weak var controller: RecordingWindowController?

    override func keyDown(with event: NSEvent) {
        if controller?.key(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, !(firstResponder is NSText), controller?.key(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// The window's content: the header, the player, the transcript (or why
/// there is none yet), the keys.
private final class RecordingView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onPlay: (() -> Void)?
    var onSeek: ((Double, Bool) -> Void)?
    var onTranscribe: ((String) -> Void)?

    private let title = NSTextField(labelWithString: "")
    private let about = NSTextField(labelWithString: "")
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
    private(set) var lines: [TranscriptLine] = []
    /// What the table shows: the lines said and the slides read, by time.
    private enum Row {
        case said(TranscriptLine)
        case shown(SlideLog.Slide)

        var start: Double {
            switch self {
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
    private var speakerNames: [String: String] = [:]
    /// Self-test hook: the lanes, by name.
    var shownLanes: [String] { waveform.lanesShown.map { speakerNames[$0.rawValue] ?? $0.title } }
    var aboutText: String { about.stringValue }
    private var languageIDs: [String] = []
    private(set) var litLine: Int?
    private var heights: [Int: CGFloat] = [:]
    /// The lines' width as last laid out: their heights are measured at it.
    private var linesWidth: CGFloat = 0
    /// The user scrolled the lines: following waits 3 s.
    private var scrolledAt: Date?
    var duration: Double = 0 {
        didSet { waveform.duration = duration }
    }
    private var position: Double = 0

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
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(lineClicked)
        table.onSpace = { [weak self] in self?.onPlay?() }
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
        for subview in [title, about, playButton, time, waveform, topLine, scroll, picturesColumn, state, languageMenu, transcribeButton, bottomLine,
                        hints] as [NSView] {
            addSubview(subview)
        }
        updateTime(playing: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func header(title text: String, about line: String) {
        title.stringValue = text
        about.stringValue = line
    }

    func showLines(_ lines: [TranscriptLine], slides: [SlideLog.Slide] = []) {
        self.lines = lines
        self.slides = slides
        setRows(lines.map(Row.said) + slides.map(Row.shown))
        heights = [:]
        table.reloadData()
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        scroll.isHidden = false
        state.isHidden = !rows.isEmpty
        state.stringValue = rows.isEmpty ? "Nothing was said, or nothing the engine could hear." : ""
        languageMenu.isHidden = true
        transcribeButton.isHidden = true
        hints.setHints(lines.isEmpty ? [("Play", "space"), ("Show in Finder", "⌘↩"), ("Delete", "⌘⌫")]
                       : [("Play", "space"), ("Copy Transcript", "⌘C"), ("Show in Finder", "⌘↩"), ("Delete", "⌘⌫")])
        needsLayout = true
    }

    func showTranscribing(_ step: MeetingTranscriber.Step) {
        lines = []
        setRows([])
        table.reloadData()
        scroll.isHidden = true
        state.isHidden = false
        switch step {
        case .downloading(let language): state.stringValue = "Downloading the \(language) speech model…"
        case .transcribing(let done): state.stringValue = "Transcribing… \(Int((done * 100).rounded())) %"
        }
        languageMenu.isHidden = true
        transcribeButton.isHidden = true
        hints.setHints([("Play", "space"), ("Show in Finder", "⌘↩"), ("Delete", "⌘⌫")])
        needsLayout = true
    }

    /// Its transcript waits its turn.
    func showWaiting() {
        lines = []
        setRows([])
        table.reloadData()
        scroll.isHidden = true
        state.isHidden = false
        state.stringValue = "Waiting to be transcribed…"
        languageMenu.isHidden = true
        transcribeButton.isHidden = true
        hints.setHints([("Play", "space"), ("Show in Finder", "⌘↩"), ("Delete", "⌘⌫")])
        needsLayout = true
    }

    /// No transcript: the language this Mac could not transcribe, and the
    /// ones it can.
    func showPending(language: String) {
        lines = []
        setRows([])
        table.reloadData()
        scroll.isHidden = true
        state.isHidden = false
        state.stringValue = "Not transcribed yet: \(MeetingTranscriber.shortName(of: language)) can't be transcribed on this Mac."
        languageMenu.isHidden = false
        transcribeButton.isHidden = false
        hints.setHints([("Play", "space"), ("Show in Finder", "⌘↩"), ("Delete", "⌘⌫")])
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

    /// The rows by time (a slide before the line said as it showed),
    /// each line's row noted.
    private func setRows(_ unsorted: [Row]) {
        rows = unsorted.enumerated().sorted { a, b in
            a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
        }.map(\.element)
        rowOfLine = rows.indices.filter { if case .said = rows[$0] { true } else { false } }
    }

    func screenFrame(ofLine line: Int) -> NSRect? {
        guard line < rowOfLine.count, let window else { return nil }
        let row = rowOfLine[line]
        table.scrollRowToVisible(row)
        let rect = table.convert(table.rect(ofRow: row), to: nil)
        return window.convertToScreen(rect)
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

    /// The speakers' names ("Me", "Them", "Room" in person) and the
    /// tracks that have a lane.
    func setSpeakers(_ names: [String: String], lanes: [Speaker]) {
        guard names != speakerNames || lanes != waveform.lanesShown else { return }
        speakerNames = names
        waveform.names = names
        waveform.lanesShown = lanes.isEmpty ? Speaker.allCases : lanes
        table.reloadData()
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
        if playing, let line, line < rowOfLine.count, scrolledAt.map({ Date.now.timeIntervalSince($0) > 3 }) ?? true {
            table.scrollRowToVisible(rowOfLine[line])
        }
    }

    private func updateTime(playing: Bool) {
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

    @objc private func scrolled() { scrolledAt = .now }

    @objc private func languagePicked() {}

    @objc private func transcribePressed() {
        let index = languageMenu.indexOfSelectedItem
        guard languageIDs.indices.contains(index) else { return }
        onTranscribe?(languageIDs[index])
    }

    // MARK: - Lines

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: LineCell.identifier, owner: nil) as? LineCell ?? LineCell()
        switch rows[row] {
        case .said(let line): cell.show(line, name: speakerNames[line.speaker.rawValue])
        case .shown(let slide): cell.show(slide)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LineRowView()
        rowView.isLit = litLine.map { $0 < rowOfLine.count && rowOfLine[$0] == row } ?? false
        return rowView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if let height = heights[row] { return height }
        // Before the first layout: the window's starting width.
        let text: String = switch rows[row] {
        case .said(let line): line.text
        case .shown(let slide): LineCell.text(of: slide)
        }
        let height = LineCell.height(of: text, width: linesWidth > 0 ? linesWidth : 712)
        heights[row] = height
        return height
    }

    /// A click on a line plays from its start (the one playing too: from
    /// its start again).
    @objc private func lineClicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count else { return }
        scrolledAt = nil
        onSeek?(rows[row].start, true)
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
        about.frame = NSRect(x: inset, y: y, width: inner, height: 18)
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
        scroll.frame = NSRect(x: inset - 12, y: y + 1, width: linesInner + 24, height: max(0, bottom - y - 1))
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
    }
}

/// The lines' table: space plays, as anywhere in the window.
private final class LinesTable: NSTableView {
    var onSpace: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Space, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}

/// The line playing: the selection's soft capsule.
private final class LineRowView: NSTableRowView {
    var isLit = false {
        didSet { if isLit != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isLit else { return }
        Theme.selectionFill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: Theme.Radius.row, yRadius: Theme.Radius.row).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// One line: who, when, what was said.
private final class LineCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("transcript-line")
    private static let textFont = NSFont.systemFont(ofSize: 13)
    private static let speakerWidth: CGFloat = 56
    private static let timeWidth: CGFloat = 54
    private static let padding: CGFloat = 12
    private static let vertical: CGFloat = 7
    private let speaker = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let words = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        speaker.font = .systemFont(ofSize: 13, weight: .semibold)
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        time.textColor = .tertiaryLabelColor
        words.font = Self.textFont
        words.textColor = .labelColor
        words.isSelectable = false
        for subview in [speaker, time, words] { addSubview(subview) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func show(_ line: TranscriptLine, name: String? = nil) {
        speaker.stringValue = name ?? line.speaker.title
        speaker.textColor = line.speaker == .me ? .controlAccentColor : .secondaryLabelColor
        time.stringValue = MeetingTranscript.clock(line.start)
        words.stringValue = line.text
        words.textColor = .labelColor
        needsLayout = true
    }

    /// A slide read on screen: "Screen", its lines joined, quieter than
    /// what was said.
    func show(_ slide: SlideLog.Slide) {
        speaker.stringValue = "Screen"
        speaker.textColor = .tertiaryLabelColor
        time.stringValue = MeetingTranscript.clock(slide.start)
        words.stringValue = Self.text(of: slide)
        words.textColor = .secondaryLabelColor
        needsLayout = true
    }

    static func text(of slide: SlideLog.Slide) -> String {
        slide.lines.joined(separator: " · ")
    }

    static func height(of text: String, width: CGFloat) -> CGFloat {
        let textWidth = max(80, width - padding * 2 - speakerWidth - timeWidth)
        let measured = (text as NSString).boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: textFont]).height
        return ceil(max(measured, 17)) + vertical * 2
    }

    override func layout() {
        super.layout()
        let x = Self.padding
        speaker.frame = NSRect(x: x, y: Self.vertical, width: Self.speakerWidth - 6, height: 17)
        time.frame = NSRect(x: x + Self.speakerWidth, y: Self.vertical + 1, width: Self.timeWidth - 6, height: 16)
        let left = x + Self.speakerWidth + Self.timeWidth
        words.frame = NSRect(x: left, y: Self.vertical, width: max(0, bounds.width - left - Self.padding), height: bounds.height - Self.vertical * 2)
    }
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
    var duration: Double = 0 { didSet { needsDisplay = true } }
    var position: Double = 0 { didSet { if position != oldValue { needsDisplay = true } } }
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
            label.draw(at: NSPoint(x: 0, y: top + (half - label.size().height) / 2))
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
            let x = lanes.minX + CGFloat(min(1, position / duration)) * lanes.width
            NSColor.labelColor.setFill()
            NSRect(x: x.rounded() - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
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
