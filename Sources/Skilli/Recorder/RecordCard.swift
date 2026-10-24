import AppKit
import AVFoundation
import Carbon.HIToolbox
import SkilliCore

/// The Record card (docs/meeting-recorder-views.md): the recording's name,
/// the two sources with their meters live, the language, and ↩. Nothing is
/// recorded before ↩. While a meeting is on, the card is that meeting's
/// (its attendees, its case's sources). The same card, at launch, offers a
/// recording never stopped: Save ↩, Later esc, Discard ⌘⌫; and when the
/// call being recorded ends: Stop ↩, Keep Recording esc.
@MainActor
final class RecordCard {
    enum Content: Equatable {
        case record
        case unfinished(URL, MeetingRecord)
        case callEnded(CallEndWatch.Reason)
    }

    /// The meeting the card records: its case, and whether ↩ joins its
    /// call too (a call not joined yet).
    struct Meeting {
        var reading: MeetingMoment.Reading
        var joins: Bool
    }

    /// ↩: the name and the language picked, the meeting it is for.
    var onRecord: ((_ title: String, _ language: String, _ meeting: Meeting?) -> Void)?
    /// esc, or closed: nothing recorded.
    var onCancel: (() -> Void)?
    /// Stop ↩ as the call ended.
    var onStopCall: (() -> Void)?
    /// A source's row clicked: on or off.
    var onToggleSource: ((Speaker) -> Void)?
    var onSave: ((URL, MeetingRecord) -> Void)?
    var onLater: ((URL, MeetingRecord) -> Void)?
    var onDiscard: ((URL, MeetingRecord) -> Void)?
    /// ⌘↩: a permission's list in System Settings.
    var onOpenPrivacy: ((Permission) -> Void)?

    private let recorder: MeetingRecorder
    private(set) var content: Content?
    private var panel: RecordPanel?
    private var glass: NSGlassEffectView?
    let view = RecordCardView()
    private var ticker: Timer?
    private var keysFrom: ContinuousClock.Instant?
    /// Languages this Mac transcribes, read once.
    private var languages: [(id: String, name: String)] = []
    private var language = ""
    private var meeting: Meeting?

    init(recorder: MeetingRecorder) {
        self.recorder = recorder
        view.onPrimary = { [weak self] in self?.primary() }
        view.onToggleSource = { [weak self] speaker in
            guard self?.content == .record else { return }
            self?.onToggleSource?(speaker)
        }
        view.onLanguage = { [weak self] id in self?.picked(language: id) }
        view.onReturnInName = { [weak self] in
            // The field's own Return obeys the grace too.
            guard let self, self.keysFrom.map({ ContinuousClock.now >= $0 }) ?? true else { return }
            self.primary()
        }
        view.onEscapeInName = { [weak self] in self?.cancel() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var window: NSWindow? { panel }

    /// The card before a recording: `title` in its field (else "Meeting
    /// 14:30"), the sources started for their meters; `consent` adds the
    /// paragraph shown the first time. `fromOutside` (a link, a tool): it
    /// never takes keys from the app the user is typing in, so a Return on
    /// its way there cannot start a recording; a click gives it the keys.
    func showRecord(title: String?, askedLanguage: String, consent: Bool, fromOutside: Bool, meeting: Meeting? = nil) {
        content = .record
        self.meeting = meeting
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? RecordingFolder.defaultTitle(at: .now)
        view.showRecord(name: name, consent: consent, attendees: meeting?.reading.attendees ?? [],
                        inPerson: meeting?.reading.kind == .inPerson, joins: meeting?.joins == true)
        let typing = fromOutside && CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1
        keysFrom = typing ? .now + MeetingCard.typingGrace : nil
        show(takingKeys: !typing)
        if !typing { view.focusName(in: panel) }
        let asksMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        Task {
            language = await MeetingTranscriber.defaultLanguage(asked: askedLanguage)
            if languages.isEmpty { languages = await MeetingTranscriber.languages() }
            guard content == .record else { return }
            view.setLanguages(languages, picked: language)
            updateLanguageNote()
            relayout()
        }
        Task {
            // macOS's question must not be under the card.
            if asksMicrophone { stepDown() }
            await recorder.listen(sources: meeting?.reading.sources ?? .both)
            if asksMicrophone { stepUp() }
            guard content == .record else { return recorder.stopListening() }
            tick()
        }
        startTicking()
    }

    /// The call being recorded ended: Stop ↩, Keep Recording esc. It
    /// never takes keys from the app the user is typing in.
    func showCallEnded(title: String, elapsed: Double, line: String, reason: CallEndWatch.Reason) {
        content = .callEnded(reason)
        view.showCallEnded(title: title, elapsed: MeetingTranscript.clock(elapsed), line: line)
        let typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1
        show(takingKeys: !typing)
        keysFrom = typing ? .now + MeetingCard.typingGrace : nil
    }

    /// A recording never stopped, found at launch.
    func showUnfinished(_ folder: URL, record: MeetingRecord) {
        content = .unfinished(folder, record)
        view.showUnfinished(record)
        // It never takes keys from the app the user is typing in.
        let typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1
        show(takingKeys: !typing)
        keysFrom = typing ? .now + MeetingCard.typingGrace : nil
    }

    func dismiss() {
        ticker?.invalidate()
        ticker = nil
        panel?.orderOut(nil)
        content = nil
        meeting = nil
    }

    private func show(takingKeys: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        relayout(center: true)
        if takingKeys { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    private func startTicking() {
        ticker?.invalidate()
        let ticker = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    /// The meters, and what the sources say.
    private func tick() {
        guard content == .record else { return }
        let levels = recorder.levels
        let sources = recorder.sources
        view.setMicrophone(sources.microphone ? recorder.microphone.state : nil, level: levels.mic)
        let silent = recorder.macSilentFor ?? 0
        // Only digital silence for 3 s while an app plays: macOS gives the
        // tap nothing (its permission off), every call succeeding.
        let blocked = sources.macSound && recorder.macSoundFailure == nil && silent > 3 ? playingApp() : nil
        view.setMacSound(failure: recorder.macSoundFailure, blockedWhile: blocked, level: levels.mac, starting: !recorder.sourcesStarted,
                         off: !sources.macSound, inPerson: meeting?.reading.kind == .inPerson)
        if view.needsRelayout { relayout() }
    }

    /// Which app plays, read once a second at most (Core Audio's process
    /// list), never on a key.
    private var playingRead: (at: ContinuousClock.Instant, app: String?)?
    private func playingApp() -> String? {
        if let playingRead, ContinuousClock.now - playingRead.at < .seconds(1) { return playingRead.app }
        let app = MacSoundTap.playing()
        playingRead = (.now, app)
        return app
    }

    private func picked(language id: String) {
        language = id
        updateLanguageNote()
        relayout()
    }

    private func updateLanguageNote() {
        let known = languages.contains { $0.id == language }
        view.setLanguageNote(known || languages.isEmpty ? nil
                             : "\(MeetingTranscriber.shortName(of: language)) can't be transcribed on this Mac yet: the recording is kept, its transcript waits.")
    }

    // MARK: - Keys

    private func primary() {
        switch content {
        case .record:
            guard view.canRecord else { return }
            let (name, meeting) = (view.name, meeting)
            dismiss()
            onRecord?(name, language, meeting)
        case .unfinished(let folder, let record):
            dismiss()
            onSave?(folder, record)
        case .callEnded:
            dismiss()
            onStopCall?()
        case nil:
            break
        }
    }

    private func cancel() {
        switch content {
        case .record:
            dismiss()
            onCancel?()
        case .unfinished(let folder, let record):
            dismiss()
            onLater?(folder, record)
        case .callEnded:
            // Keep Recording: nothing asked again for the same reason.
            dismiss()
        case nil:
            break
        }
    }

    fileprivate func handle(_ event: NSEvent) -> Bool {
        if let keysFrom, ContinuousClock.now < keysFrom { return true }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        let isReturn = code == kVK_Return || code == kVK_ANSI_KeypadEnter
        switch (content, code) {
        case (_, kVK_Escape):
            cancel()
        case (.some, _) where isReturn && flags.isEmpty:
            primary()
        case (.record, _) where isReturn && flags == .command:
            if let missing = view.missingPermission { onOpenPrivacy?(missing) }
        case (.unfinished(let folder, let record), kVK_Delete) where flags == .command:
            dismiss()
            onDiscard?(folder, record)
        default:
            return false
        }
        return true
    }

    fileprivate func closed() {
        cancel()
    }

    #if SKILLI_SELFTEST
    /// Self-test: closed as esc would, without a key (a card that has none).
    func closeWithoutKeys() {
        cancel()
    }
    #endif

    // MARK: - Drawing

    /// macOS asks for the microphone: its question over the card.
    private func stepDown() {
        panel?.level = .floating
    }

    private func stepUp() {
        panel?.level = .modalPanel
        panel?.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> RecordPanel {
        let panel = RecordPanel(card: self)
        let glass = Theme.glass(cornerRadius: Theme.Radius.card, content: view)
        self.glass = glass
        let root = NSView()
        root.addSubview(glass)
        panel.contentView = root
        return panel
    }

    /// Laid out at its height, its top kept (or centered on the screen the
    /// pointer is on).
    private func relayout(center: Bool = false) {
        guard let panel, let root = panel.contentView, let glass else { return }
        let top = panel.frame.maxY
        let height = view.fittingHeight
        let margin = Theme.glassMargin
        let size = NSSize(width: RecordCardView.width + 2 * margin, height: height + 2 * margin)
        panel.setContentSize(size)
        root.frame = NSRect(origin: .zero, size: size)
        glass.frame = NSRect(x: margin, y: margin, width: RecordCardView.width, height: height)
        view.frame = glass.bounds
        if center {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(),
                                             y: (visible.midY - size.height / 2 + visible.height * 0.06).rounded()))
            }
        } else {
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - size.height))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Borderless, non-activating, over every space: the app in front stays
/// in front (the call goes on), the keys come here once it is key.
private final class RecordPanel: NSPanel {
    weak var card: RecordCard?

    init(card: RecordCard) {
        self.card = card
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .alertPanel
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if card?.handle(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, event.type == .keyDown, event.modifierFlags.contains(.command), card?.handle(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        card?.closed()
    }
}

/// The card's content, top-down: the eyebrow and the language, the name,
/// the two sources, what needs saying, then the keys and Record.
final class RecordCardView: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 520
    private static let inset: CGFloat = 28
    private static let titleFont = NSFont.systemFont(ofSize: 26, weight: .semibold)

    var onPrimary: (() -> Void)?
    var onLanguage: ((String) -> Void)?
    var onReturnInName: (() -> Void)?
    var onEscapeInName: (() -> Void)?
    /// A source's row clicked.
    var onToggleSource: ((Speaker) -> Void)?

    private let dot = DotView()
    private let eyebrow = NSTextField(labelWithString: "")
    /// The call's time, on the right of the eyebrow (the call ended).
    private let clock = NSTextField(labelWithString: "")
    private let languageMenu = LanguageButton()
    private let nameField = NSTextField(string: "")
    private let detail = NSTextField(labelWithString: "")
    private let microphoneRow = SourceRow(symbol: "mic.fill", title: "Microphone")
    private let macRow = SourceRow(symbol: "speaker.wave.2.fill", title: "The Mac's sound")
    private let note = CardNoteView()
    private let consent = CardNoteView()
    private let hairline = NSView()
    private let leftHints = HintBar()
    private let button = PrimaryButton()
    private var isRecordCard = true
    private var inPersonNote: String?
    private var languageIDs: [String] = []
    /// What ⌘↩ opens: the permission a row says is missing.
    private(set) var missingPermission: Permission?
    private(set) var needsRelayout = false
    private var microphoneOn = false
    private var macOn = false

    override var isFlipped: Bool { true }

    var name: String { nameField.stringValue }
    var canRecord: Bool { !isRecordCard || microphoneOn || macOn }
    /// Self-test hooks.
    var eyebrowText: String { eyebrow.stringValue }
    var buttonTitle: String { button.title }
    var microphoneLine: String { microphoneRow.line }
    var macLine: String { macRow.line }
    var noteText: String { note.isHidden ? "" : note.text }
    var consentShown: Bool { !consent.isHidden }
    var detailText: String { detail.isHidden ? "" : detail.stringValue }
    var languageShown: String { languageMenu.shown }
    var clockText: String { clock.isHidden ? "" : clock.stringValue }

    override init(frame: NSRect) {
        super.init(frame: frame)
        eyebrow.textColor = .secondaryLabelColor
        nameField.font = Self.titleFont
        nameField.textColor = .labelColor
        nameField.isBordered = false
        nameField.isBezeled = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.usesSingleLineMode = true
        nameField.lineBreakMode = .byTruncatingTail
        nameField.cell?.isScrollable = true
        nameField.delegate = self
        nameField.setAccessibilityLabel("Recording name")
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        clock.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        clock.textColor = .secondaryLabelColor
        clock.alignment = .right
        clock.isHidden = true
        microphoneRow.onClick = { [weak self] in self?.onToggleSource?(.me) }
        macRow.onClick = { [weak self] in self?.onToggleSource?(.them) }
        languageMenu.onPick = { [weak self] index in self?.languagePicked(index) }
        hairline.wantsLayer = true
        button.target = self
        button.action = #selector(primaryPressed)
        consent.symbol = "info.circle"
        consent.text = "The others in the call must agree to be recorded: in many countries, France included, recording a private conversation without consent is an offense."
        for subview in [dot, eyebrow, clock, languageMenu, nameField, detail, microphoneRow, macRow, note, consent, hairline, leftHints, button] as [NSView] {
            addSubview(subview)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func primaryPressed() {
        onPrimary?()
    }

    private func languagePicked(_ index: Int) {
        guard languageIDs.indices.contains(index) else { return }
        onLanguage?(languageIDs[index])
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onReturnInName?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onEscapeInName?()
            return true
        default:
            return false
        }
    }

    // MARK: - Content

    /// The card before a recording; for a meeting, its attendees under the
    /// name, the in-person line, "Record and Join" when ↩ joins its call.
    func showRecord(name: String, consent shown: Bool, attendees: [String] = [], inPerson: Bool = false, joins: Bool = false) {
        isRecordCard = true
        setEyebrow("RECORD A MEETING", dot: .systemRed, hollow: false)
        clock.isHidden = true
        nameField.stringValue = name
        nameField.isHidden = false
        nameField.isSelectable = true
        nameField.isEditable = true
        let people = MeetingPeople.sentence(attendees)
        detail.isHidden = people.isEmpty
        detail.stringValue = people.isEmpty ? "" : "With \(people)"
        languageMenu.isHidden = languageIDs.isEmpty
        microphoneRow.isHidden = false
        macRow.isHidden = false
        microphoneRow.clickable = true
        macRow.clickable = true
        microphoneRow.setState("Starting…", level: nil)
        macRow.setState("Starting…", level: nil)
        consent.isHidden = !shown
        inPersonNote = inPerson ? "In person: set the Mac in the middle of the table." : nil
        updateNote()
        button.title = joins ? "Record and Join" : "Record"
        button.alphaValue = 1
        leftHints.setHints([("Cancel", "esc")])
        layoutContent()
    }

    /// The call being recorded ended: its name, why, Stop ↩.
    func showCallEnded(title: String, elapsed: String, line: String) {
        isRecordCard = false
        window?.makeFirstResponder(nil)
        setEyebrow("THE CALL ENDED", dot: .systemRed, hollow: true)
        clock.stringValue = elapsed
        clock.isHidden = false
        nameField.stringValue = title
        nameField.isSelectable = false
        nameField.isEditable = false
        languageMenu.isHidden = true
        detail.isHidden = false
        detail.stringValue = line
        microphoneRow.isHidden = true
        macRow.isHidden = true
        consent.isHidden = true
        inPersonNote = nil
        note.isHidden = true
        missingPermission = nil
        button.title = "Stop"
        button.alphaValue = 1
        leftHints.setHints([("Keep Recording", "esc")])
        layoutContent()
    }

    func showUnfinished(_ record: MeetingRecord) {
        isRecordCard = false
        // Read, not edited: no caret, nothing selected from the card before.
        window?.makeFirstResponder(nil)
        nameField.isSelectable = false
        setEyebrow("UNFINISHED RECORDING", dot: .systemOrange, hollow: false)
        clock.isHidden = true
        inPersonNote = nil
        nameField.stringValue = record.title
        nameField.isEditable = false
        languageMenu.isHidden = true
        detail.isHidden = false
        detail.stringValue = Self.unfinishedLine(record)
        microphoneRow.isHidden = true
        macRow.isHidden = true
        consent.isHidden = true
        note.isHidden = true
        missingPermission = nil
        button.title = "Save"
        button.alphaValue = 1
        leftHints.setHints([("Later", "esc"), ("Discard", "⌘⌫")])
        layoutContent()
    }

    /// "18 min, stopped Wed 22 Oct at 14:48".
    static func unfinishedLine(_ record: MeetingRecord) -> String {
        let stopped = record.stopped ?? record.started
        let when = stopped.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " at "
            + stopped.formatted(date: .omitted, time: .shortened)
        return record.seconds > 0 ? "\(MeetingTranscriber.length(record.seconds)), stopped \(when)" : "Stopped \(when)"
    }

    func focusName(in window: NSWindow?) {
        guard let window else { return }
        window.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    func setLanguages(_ languages: [(id: String, name: String)], picked: String) {
        languageIDs = languages.map(\.id)
        var names = languages.map(\.name)
        if !languageIDs.contains(picked) {
            // Not one this Mac has: shown all the same, the note says so.
            names.append(MeetingTranscriber.name(of: picked))
            languageIDs.append(picked)
        }
        // The card says "French"; its region only when the Mac has the
        // language in several (the menu names each).
        let short = languageIDs.map(MeetingTranscriber.shortName(of:))
        languageMenu.set(names, picked: languageIDs.firstIndex(of: picked) ?? 0) { index in
            let language = short[index]
            return short.filter { $0 == language }.count > 1 ? names[index] : language
        }
        languageMenu.isHidden = !isRecordCard
    }

    func setLanguageNote(_ text: String?) {
        languageNote = text
        updateNote()
    }

    private var languageNote: String?
    private var permissionNote: String?

    /// The microphone's row; nil: turned off (a click turns it on).
    func setMicrophone(_ state: MicrophoneTrack.State?, level: Double) {
        let before = (microphoneRow.line, missingPermission)
        switch state {
        case nil:
            microphoneOn = false
            microphoneRow.setState("Off", level: nil)
        case .on(let device)?:
            microphoneOn = true
            microphoneRow.setState(device, level: level)
        case .denied?:
            microphoneOn = false
            microphoneRow.setState("Not allowed · ⌘↩ opens Privacy", level: nil, warns: true)
        case .some(.none):
            microphoneOn = false
            microphoneRow.setState("No microphone", level: nil)
        case .off?:
            microphoneOn = false
            microphoneRow.setState("Starting…", level: nil)
        }
        if case .denied? = state { missingPermission = .microphone } else if missingPermission == .microphone { missingPermission = nil }
        updateMissing()
        if before != (microphoneRow.line, missingPermission) { needsRelayout = true }
    }

    /// `blockedWhile`: the app playing while the tap hears only silence;
    /// `starting`: the tap not started yet (it does not count for Record);
    /// `off`: turned off (in person, or a click).
    func setMacSound(failure: String?, blockedWhile app: String?, level: Double, starting: Bool = false, off: Bool = false, inPerson: Bool = false) {
        let before = (macRow.line, permissionNote)
        if off {
            macOn = false
            macRow.setState(inPerson ? "Off · in person" : "Off", level: nil)
            permissionNote = nil
        } else if starting {
            macOn = false
            macRow.setState("Starting…", level: nil)
            permissionNote = nil
        } else if let failure {
            macOn = false
            macRow.setState("Not available", level: nil, warns: true)
            permissionNote = failure
        } else {
            macOn = true
            macRow.setState("Every app", level: level)
            permissionNote = app.map { "No sound while \($0) plays: allow skil.li in Screen & System Audio Recording · ⌘↩" }
        }
        if app != nil, missingPermission == nil { missingPermission = .screenRecording }
        if app == nil, missingPermission == .screenRecording { missingPermission = nil }
        updateMissing()
        if before != (macRow.line, permissionNote) { needsRelayout = true }
    }

    private func updateMissing() {
        // Both off by a click: nothing to record, nothing to allow.
        if isRecordCard, !microphoneOn, !macOn, microphoneRow.line == "Off", macRow.line.hasPrefix("Off") {
            permissionNoteBlocking = "Nothing to record: turn a source on."
        } else if isRecordCard, !microphoneOn, !macOn, microphoneRow.line != "Starting…", macRow.line != "Starting…" {
            permissionNoteBlocking = "Nothing to record: allow the microphone or the Mac's sound."
        } else {
            permissionNoteBlocking = nil
        }
        button.alphaValue = canRecord ? 1 : 0.45
        updateNote()
    }

    private var permissionNoteBlocking: String?

    private func updateNote() {
        let lines = [permissionNoteBlocking, permissionNote, languageNote, inPersonNote].compactMap { $0 }
        note.isHidden = lines.isEmpty || !isRecordCard
        note.text = lines.joined(separator: "\n")
        note.symbol = permissionNoteBlocking != nil || permissionNote != nil ? "exclamationmark.triangle"
            : languageNote != nil ? "character.bubble" : "person.2"
    }

    private func setEyebrow(_ text: String, dot color: NSColor, hollow: Bool) {
        eyebrow.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .kern: 0.9, .foregroundColor: NSColor.secondaryLabelColor,
        ])
        eyebrow.sizeToFit()
        dot.color = color
        dot.isHollow = hollow
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hairline.layer?.backgroundColor = Theme.hairline.cgColor
    }

    private func layoutContent() {
        needsRelayout = false
        let inset = Self.inset
        let width = Self.width
        let inner = width - 2 * inset
        hairline.layer?.backgroundColor = Theme.hairline.cgColor

        var y: CGFloat = 26
        dot.frame = NSRect(x: inset, y: y + 4, width: 9, height: 9)
        clock.sizeToFit()
        let clockWidth = clock.isHidden ? 0 : clock.frame.width
        clock.frame = NSRect(x: width - inset - clockWidth, y: y, width: clockWidth, height: 18)
        let menuWidth = languageMenu.isHidden ? clockWidth : min(languageMenu.fittingWidth, inner / 2)
        languageMenu.frame = NSRect(x: width - inset - menuWidth, y: y - 2, width: languageMenu.isHidden ? 0 : menuWidth, height: 20)
        eyebrow.frame = NSRect(x: inset + 17, y: y + 1, width: max(0, inner - 17 - menuWidth - 12), height: 16)
        y += 32

        let lineHeight = ceil(Self.titleFont.ascender - Self.titleFont.descender + Self.titleFont.leading)
        nameField.frame = NSRect(x: inset - 2, y: y, width: inner + 4, height: lineHeight + 4)
        y = nameField.frame.maxY + 8

        if !detail.isHidden {
            detail.frame = NSRect(x: inset, y: y, width: inner, height: 20)
            y += isRecordCard ? 22 : 28
        }

        if !microphoneRow.isHidden {
            y += 6
            microphoneRow.frame = NSRect(x: inset, y: y, width: inner, height: SourceRow.height)
            y += SourceRow.height + 4
            macRow.frame = NSRect(x: inset, y: y, width: inner, height: SourceRow.height)
            y += SourceRow.height + 4
        }

        for paragraph in [note, consent] where !paragraph.isHidden {
            y += 10
            let height = paragraph.height(for: inner)
            paragraph.frame = NSRect(x: inset, y: y, width: inner, height: height)
            y += height
        }

        y += 18
        hairline.frame = NSRect(x: 0, y: y, width: width, height: 1)
        y += 16
        button.sizeToFit()
        button.frame = NSRect(x: width - inset + 6 - button.frame.width, y: y, width: button.frame.width, height: PrimaryButton.height)
        let keysY = y + (PrimaryButton.height - 20) / 2
        leftHints.frame = NSRect(x: inset, y: keysY, width: 260, height: 20)
        leftHints.setHints(leftHints.shown)
        // HintBar right-aligns: this one starts at the inset.
        let used = leftHints.subviews.map(\.frame.minX).min() ?? 0
        leftHints.subviews.forEach { $0.frame.origin.x -= used }
    }

    var fittingHeight: CGFloat {
        layoutContent()
        return button.frame.maxY + 20
    }
}

/// The language, as a word and a chevron in the secondary color; a click
/// lists the languages this Mac transcribes, the one picked checked.
private final class LanguageButton: NSView {
    var onPick: ((Int) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var names: [String] = []
    private var picked = 0

    var shown: String { label.stringValue }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        chevron.image = Theme.symbol("chevron.up.chevron.down", pointSize: 10, weight: .semibold)
        chevron.contentTintColor = .secondaryLabelColor
        addSubview(label)
        addSubview(chevron)
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Language")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// `titled`: how the picked one reads on the card (the menu names
    /// each in full).
    private var titled: (Int) -> String = { _ in "" }

    func set(_ names: [String], picked: Int, titled: @escaping (Int) -> String) {
        self.names = names
        self.titled = titled
        pick(picked)
    }

    private func pick(_ index: Int) {
        picked = index
        label.stringValue = names.indices.contains(index) ? titled(index) : ""
        setAccessibilityValue(label.stringValue)
        needsLayout = true
    }

    var fittingWidth: CGFloat {
        label.sizeToFit()
        return ceil(label.frame.width) + 4 + 12
    }

    override func layout() {
        super.layout()
        label.sizeToFit()
        let labelWidth = max(0, min(label.frame.width, bounds.width - 16))
        label.frame = NSRect(x: 0, y: (bounds.height - label.frame.height) / 2, width: labelWidth, height: label.frame.height)
        chevron.frame = NSRect(x: labelWidth + 4, y: (bounds.height - 12) / 2, width: 12, height: 12)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for (index, name) in names.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == picked ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.items.indices.contains(picked) ? menu.items[picked] : nil, at: NSPoint(x: 0, y: bounds.height - 2), in: self)
    }

    @objc private func choose(_ item: NSMenuItem) {
        pick(item.tag)
        onPick?(item.tag)
    }
}

/// One source: its symbol, its name, its device in the secondary color,
/// and its level, live, at the right.
private final class SourceRow: NSView {
    static let height: CGFloat = 26
    private let icon = NSImageView()
    private let title: NSTextField
    private let device = NSTextField(labelWithString: "")
    private let meter = LevelMeter()

    var line: String { device.stringValue }
    /// A click turns the source on or off (the Record card).
    var onClick: (() -> Void)?
    var clickable = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    init(symbol: String, title text: String) {
        title = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        icon.image = Theme.symbol(symbol, pointSize: 13, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = .labelColor
        device.font = .systemFont(ofSize: 13)
        device.textColor = .secondaryLabelColor
        device.lineBreakMode = .byTruncatingTail
        for subview in [icon, title, device, meter] as [NSView] { addSubview(subview) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        if clickable { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        if clickable { onClick?() } else { super.mouseDown(with: event) }
    }

    /// The device (or why it is off) and its level; nil: no meter.
    func setState(_ text: String, level: Double?, warns: Bool = false) {
        if device.stringValue != text { device.stringValue = text }
        device.textColor = warns ? .systemOrange : .secondaryLabelColor
        meter.isHidden = level == nil
        if let level { meter.level = level }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let middle = bounds.height / 2
        icon.frame = NSRect(x: 0, y: middle - 9, width: 18, height: 18)
        title.sizeToFit()
        title.frame.origin = NSPoint(x: 28, y: middle - title.frame.height / 2)
        let meterWidth: CGFloat = meter.isHidden ? 0 : 64
        meter.frame = NSRect(x: bounds.width - meterWidth, y: middle - 3, width: meterWidth, height: 6)
        let left = title.frame.maxX + 10
        let right = bounds.width - (meter.isHidden ? 0 : meterWidth + 14)
        device.sizeToFit()
        device.frame = NSRect(x: left, y: middle - device.frame.height / 2, width: max(0, right - left), height: device.frame.height)
    }
}

/// A paragraph in the secondary color with its symbol: the consent, what a
/// source lacks, a language this Mac cannot transcribe; the meeting card's
/// line about ⌘R, the first time.
final class CardNoteView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    var symbol = "info.circle" {
        didSet { icon.image = Theme.symbol(symbol, pointSize: 13, weight: .regular) }
    }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.image = Theme.symbol(symbol, pointSize: 13, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        addSubview(icon)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func height(for width: CGFloat) -> CGFloat {
        let measured = (label.stringValue as NSString).boundingRect(with: NSSize(width: width - 28, height: .greatestFiniteMagnitude),
                                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                                    attributes: [.font: label.font!]).height
        return ceil(measured) + 2
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 0, y: 0, width: 18, height: 18)
        label.frame = NSRect(x: 28, y: 0, width: bounds.width - 28, height: bounds.height)
    }
}
