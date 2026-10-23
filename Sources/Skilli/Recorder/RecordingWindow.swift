import AppKit
import AVFoundation
import Carbon.HIToolbox
import SkilliCore

/// A recording's window (docs/meeting-recorder-views.md): a window, not a
/// card, since it is read and played. The player with both sides'
/// waveforms, then the transcript, a line each, Me or Them; a click plays
/// from a line, the line playing is lit and followed. Built when opened,
/// released when closed.
@MainActor
final class RecordingWindowController: NSObject, NSWindowDelegate {
    let folder: URL
    private(set) var record: MeetingRecord
    private let window: RecordingWindow
    private let view = RecordingView()
    private var player: AVPlayer?
    private var observer: Any?
    var onClose: ((RecordingWindowController) -> Void)?
    var onDelete: ((URL, MeetingRecord) -> Void)?
    var onShowFolder: ((URL) -> Void)?
    /// A transcript waiting for a language: made in the one picked.
    var onTranscribe: ((URL, MeetingRecord) -> Void)?

    init(folder: URL, record: MeetingRecord, transcript: MeetingTranscript.File?) {
        self.folder = folder
        self.record = record
        window = RecordingWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
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
    /// Where a line is on screen (AppKit's coordinates), to click it.
    func screenFrame(ofLine row: Int) -> NSRect? { view.screenFrame(ofLine: row) }

    /// What the folder holds now: the transcript once made, or why there is
    /// none.
    func show(_ record: MeetingRecord, transcript: MeetingTranscript.File?, transcribing: MeetingTranscriber.Step? = nil) {
        self.record = record
        window.title = record.title
        view.header(title: record.title, about: MeetingTranscriber.about(record))
        if let transcribing {
            view.showTranscribing(transcribing)
        } else if let transcript {
            view.showLines(transcript.lines)
        } else {
            view.showPending(language: record.language)
        }
        if player == nil { loadPlayer() }
    }

    func present() {
        Foreground.bring(window)
    }

    func close() {
        window.close()
    }

    // MARK: - Playing

    private func loadPlayer() {
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
            self.player = player
            self.view.duration = max(self.record.seconds, composition.duration.seconds.isFinite ? composition.duration.seconds : 0)
            self.observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
                MainActor.assumeIsolated { self?.view.played(to: time.seconds, playing: (self?.player?.rate ?? 0) > 0) }
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
        } else {
            if let item = player.currentItem, item.currentTime() >= item.duration, item.duration.isNumeric { player.seek(to: .zero) }
            player.play()
        }
        view.played(to: player.currentTime().seconds, playing: player.rate > 0)
    }

    func seek(to seconds: Double, play: Bool) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if play { player.play() }
        view.played(to: seconds, playing: play || player.rate > 0)
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
    private var languageIDs: [String] = []
    private(set) var litLine: Int?
    private var heights: [Int: CGFloat] = [:]
    private var heightsWidth: CGFloat = 0
    /// The user scrolled the lines: following waits 3 s.
    private var scrolledAt: Date?
    var duration: Double = 0 {
        didSet { waveform.duration = duration }
    }
    private var position: Double = 0

    var stateText: String { state.isHidden ? "" : state.stringValue }

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
        for subview in [title, about, playButton, time, waveform, topLine, scroll, state, languageMenu, transcribeButton, bottomLine, hints] as [NSView] {
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

    func showLines(_ lines: [TranscriptLine]) {
        self.lines = lines
        heights = [:]
        table.reloadData()
        scroll.isHidden = false
        state.isHidden = !lines.isEmpty
        state.stringValue = lines.isEmpty ? "Nothing was said, or nothing the engine could hear." : ""
        languageMenu.isHidden = true
        transcribeButton.isHidden = true
        hints.setHints(lines.isEmpty ? [("Play", "space"), ("Show in Finder", "⌘↩"), ("Delete", "⌘⌫")]
                       : [("Play", "space"), ("Copy Transcript", "⌘C"), ("Show in Finder", "⌘↩"), ("Delete", "⌘⌫")])
        needsLayout = true
    }

    func showTranscribing(_ step: MeetingTranscriber.Step) {
        lines = []
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

    /// No transcript: the language this Mac could not transcribe, and the
    /// ones it can.
    func showPending(language: String) {
        lines = []
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

    func screenFrame(ofLine row: Int) -> NSRect? {
        guard row < lines.count, let window else { return nil }
        table.scrollRowToVisible(row)
        let rect = table.convert(table.rect(ofRow: row), to: nil)
        return window.convertToScreen(rect)
    }

    func setPeaks(me: [Float], them: [Float]) {
        waveform.me = me
        waveform.them = them
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
        for row in [previous, line].compactMap({ $0 }) where row < lines.count {
            (table.rowView(atRow: row, makeIfNecessary: false) as? LineRowView)?.isLit = row == line
        }
        if playing, let line, scrolledAt.map({ Date.now.timeIntervalSince($0) > 3 }) ?? true {
            table.scrollRowToVisible(line)
        }
    }

    private func updateTime(playing: Bool) {
        time.stringValue = "\(MeetingTranscript.clock(position)) / \(MeetingTranscript.clock(duration))"
        playButton.image = Theme.symbol(playing ? "pause.fill" : "play.fill", pointSize: 18, weight: .medium)
        playButton.setAccessibilityLabel(playing ? "Pause" : "Play")
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

    func numberOfRows(in tableView: NSTableView) -> Int { lines.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: LineCell.identifier, owner: nil) as? LineCell ?? LineCell()
        cell.show(lines[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LineRowView()
        rowView.isLit = row == litLine
        return rowView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let width = tableView.bounds.width
        if width != heightsWidth {
            heights = [:]
            heightsWidth = width
        }
        if let height = heights[row] { return height }
        let height = LineCell.height(of: lines[row], width: width)
        heights[row] = height
        return height
    }

    /// A click on a line plays from its start (the one playing too: from
    /// its start again).
    @objc private func lineClicked() {
        let row = table.clickedRow
        guard row >= 0, row < lines.count else { return }
        scrolledAt = nil
        onSeek?(lines[row].start, true)
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
        scroll.frame = NSRect(x: inset - 12, y: y + 1, width: inner + 24, height: max(0, bottom - y - 1))
        if table.tableColumns.first?.width != scroll.contentSize.width {
            table.tableColumns.first?.width = scroll.contentSize.width
            // Wrapped lines take another height at another width.
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<lines.count))
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

    func show(_ line: TranscriptLine) {
        speaker.stringValue = line.speaker.title
        speaker.textColor = line.speaker == .me ? .controlAccentColor : .secondaryLabelColor
        time.stringValue = MeetingTranscript.clock(line.start)
        words.stringValue = line.text
        needsLayout = true
    }

    static func height(of line: TranscriptLine, width: CGFloat) -> CGFloat {
        let textWidth = max(80, width - padding * 2 - speakerWidth - timeWidth)
        let measured = (line.text as NSString).boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
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

/// Both sides' waveforms, Me above in the accent color, Them below; the
/// playhead. A click or a drag seeks.
private final class WaveformView: NSView {
    var me: [Float] = [] { didSet { needsDisplay = true } }
    var them: [Float] = [] { didSet { needsDisplay = true } }
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
        let half = lanes.height / 2
        for (index, speaker) in Speaker.allCases.enumerated() {
            let top = CGFloat(index) * half
            let label = NSAttributedString(string: speaker.title, attributes: [
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
