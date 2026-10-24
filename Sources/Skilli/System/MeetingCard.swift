import AppKit
import Carbon.HIToolbox
import SkilliCore

/// A meeting alert (Settings → Calendar → Before a meeting): one glass card
/// in the middle of the screen, the meeting in it, the time counting down
/// live; ↩ joins (or, without a call, lets it go: Got It), ⌘↩ shows it
/// in Calendar, esc lets it go. "Screens dark": every screen black around
/// it, the menu bar and the Dock too, until it goes; a click on the dark
/// lets it go. It takes the keyboard only when the user is not typing; a
/// click does too. It leaves by itself when the meeting ends, or once the
/// user is in the call (`MeetingWatch.onInCall`).
@MainActor
final class MeetingCard {
    var onJoin: ((AgendaEvent) -> Void)?
    var onShowInCalendar: ((AgendaEvent) -> Void)?

    private(set) var event: AgendaEvent?
    private(set) var isDark = false
    /// Keys before this do nothing: typed on the way to the app as the
    /// card came, they neither join nor reach it.
    private var keysFrom: ContinuousClock.Instant?
    private var panel: CardPanel?
    private var glass: NSGlassEffectView?
    private let view = MeetingCardView()
    private let dimmer = ScreenDimmer()
    private var ticker: Timer?
    /// Check Camera & Mic, while open.
    private var check: MeetingCheck?
    /// A device not allowed: Settings → Privacy.
    var onOpenPrivacy: (() -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }
    /// It has the keyboard (an alert with the screens dark).
    var isKey: Bool { panel?.isKeyWindow ?? false }
    /// Self-test hooks.
    var shownEyebrow: String { view.eyebrowText }
    var shownTitle: String { view.titleText }
    var shownAction: String { view.actionTitle }
    var screensDark: Bool { dimmer.isShown }
    var isChecking: Bool { view.isChecking }
    var offersCheck: Bool { view.offersCheck }
    var checkLine: String { view.checkView.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " · ") }
    var window: NSWindow? { panel }

    init() {
        dimmer.onClick = { [weak self] in self?.dismiss() }
        view.onPrimary = { [weak self] in self?.primary() }
        view.onCheck = { [weak self] in self?.toggleCheck() }
        view.checkView.onOpenPrivacy = { [weak self] in self?.onOpenPrivacy?() }
    }

    /// Shows `event` in the middle of the screen the pointer is on; `dark`
    /// darkens every screen around it. A second alert takes the card.
    func show(_ event: AgendaEvent, dark: Bool) {
        stopCheck()
        self.event = event
        isDark = dark
        let panel = self.panel ?? makePanel()
        self.panel = panel
        view.show(event, now: .now)
        layout()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2 + visible.height * 0.06).rounded()))
        }
        if dark { dimmer.show(below: panel.level) } else { dimmer.hide() }
        // Mid-typing, the card alone leaves the keyboard to the app; with
        // the screens dark the app cannot be seen, so the card takes it at
        // once (2026-10-16: ↩ joins, esc lets it go, hands still on the
        // keys), the keys already on their way swallowed.
        let typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1
        keysFrom = typing ? .now + Self.typingGrace : nil
        if typing, !dark { panel.orderFrontRegardless() } else { panel.makeKeyAndOrderFront(nil) }
        ticker?.invalidate()
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker.tolerance = 0.1
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        Log.trace("Meeting card: \(event.title), \(dark ? "screens dark" : "card")\(typing ? (dark ? ", typing: keyboard taken after a pause" : ", typing: keyboard left alone") : "")")
    }

    func dismiss() {
        stopCheck()
        ticker?.invalidate()
        ticker = nil
        panel?.orderOut(nil)
        dimmer.hide()
        event = nil
    }

    /// Join for a call; for anything else the alert has said it all.
    private func primary() {
        guard let event else { return }
        dismiss()
        if event.meeting != nil { onJoin?(event) }
    }

    /// ⇥ or a click: the camera and microphone shown, or put away. The
    /// card keeps its top where it is and grows down.
    func toggleCheck() {
        guard let event, event.meeting != nil else { return }
        if check != nil {
            stopCheck()
            relayout()
            return
        }
        let check = MeetingCheck()
        self.check = check
        Task { [weak self] in
            await check.start(asking: { self?.stepDown() }, answered: { self?.stepUp() })
            guard let self, self.check === check, self.isVisible else {
                check.stop()
                return
            }
            self.view.showCheck(check)
            self.relayout()
        }
    }

    private func stopCheck() {
        check?.stop()
        check = nil
        if view.isChecking { view.showCheck(nil) }
    }

    /// Self-test: the check drawn on a still image, the card at its new
    /// height.
    func showSampleCheck(image: NSImage) {
        stopCheck()
        view.showSampleCheck(image: image)
        relayout()
    }

    /// macOS asks for the camera: its question must not be under the card
    /// or the dark.
    private func stepDown() {
        panel?.level = .floating
        dimmer.hide()
    }

    private func stepUp() {
        panel?.level = .screenSaver
        if isDark, let panel { dimmer.show(below: panel.level) }
        panel?.orderFrontRegardless()
    }

    /// Laid out again at its new height, its top kept.
    private func relayout() {
        guard let panel else { return }
        let top = panel.frame.maxY
        layout()
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    private func tick() {
        guard let event else { return }
        // Over: it goes by itself.
        guard Date.now < event.end else { return dismiss() }
        view.tick(now: .now)
    }

    /// Taken mid-typing: the keys of this first half second do nothing.
    static let typingGrace: Duration = .milliseconds(500)

    /// A key pressed while it has the keyboard; with the screens dark, any
    /// other key does nothing (the app behind cannot be seen).
    fileprivate func handle(_ event: NSEvent) -> Bool {
        if let keysFrom, ContinuousClock.now < keysFrom { return true }
        return act(on: event) || isDark
    }

    private func act(on event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        let isReturn = code == kVK_Return || code == kVK_ANSI_KeypadEnter
        if isReturn, flags.isEmpty {
            primary()
        } else if isReturn, flags == .command, let shown = self.event {
            dismiss()
            onShowInCalendar?(shown)
        } else if code == kVK_Escape {
            dismiss()
        } else if code == kVK_Tab, flags.isEmpty, self.event?.meeting != nil {
            toggleCheck()
        } else {
            return false
        }
        return true
    }

    // MARK: - Drawing

    private func makePanel() -> CardPanel {
        let panel = CardPanel(card: self)
        let glass = Theme.glass(cornerRadius: Theme.Radius.card, content: view)
        self.glass = glass
        let root = NSView()
        root.addSubview(glass)
        panel.contentView = root
        return panel
    }

    private func layout() {
        guard let panel, let root = panel.contentView, let glass else { return }
        let height = view.fittingHeight
        let margin = Theme.glassMargin
        let size = NSSize(width: MeetingCardView.width + 2 * margin, height: height + 2 * margin)
        panel.setContentSize(size)
        root.frame = NSRect(origin: .zero, size: size)
        glass.frame = NSRect(x: margin, y: margin, width: MeetingCardView.width, height: height)
        view.frame = glass.bounds
    }
}

/// Borderless, non-activating, over every space and every app (above the
/// dark of "screens dark"): the app in front stays in front; the keys come
/// here only once it is the key window.
private final class CardPanel: NSPanel {
    weak var card: MeetingCard?

    init(card: MeetingCard) {
        self.card = card
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
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
        if isKeyWindow, event.type == .keyDown, card?.handle(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        card?.dismiss()
    }
}

/// The card's content, top-down: the time left and its span, the meeting's
/// name, its call and calendar, who is in it, then the keys and Join. Also
/// drawn as Settings → Calendar's preview.
final class MeetingCardView: NSView {
    static let width: CGFloat = 520
    private static let inset: CGFloat = 28
    /// Its width: the alert's own, narrower in Settings' preview.
    var cardWidth: CGFloat = MeetingCardView.width
    private static let titleFont = NSFont.systemFont(ofSize: 26, weight: .semibold)

    var onPrimary: (() -> Void)?
    /// "Camera & Mic ⇥" clicked.
    var onCheck: (() -> Void)?

    private let dot = DotView()
    private let eyebrow = NSTextField(labelWithString: "")
    private let span = NSTextField(labelWithString: "")
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let detailIcon = NSImageView()
    private let people = PeopleView()
    private let hairline = NSView()
    private let dismissHint = HintBar()
    private let calendarHint = HintBar()
    private let button = PrimaryButton()
    private let checkHint = ClickHint(label: "Camera & Mic", key: "⇥")
    /// The camera and the microphone live, while checked.
    let checkView = MeetingCheckView()
    private(set) var isChecking = false
    private var start = Date.now
    private var hasCall = true

    override var isFlipped: Bool { true }

    var eyebrowText: String { eyebrow.stringValue }
    /// Self-test hook: the check's hint shows.
    var offersCheck: Bool { !checkHint.isHidden }
    var titleText: String { title.stringValue }
    var actionTitle: String { button.title }

    override init(frame: NSRect) {
        super.init(frame: frame)
        eyebrow.font = .systemFont(ofSize: 12, weight: .semibold)
        eyebrow.textColor = .secondaryLabelColor
        span.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        span.textColor = .secondaryLabelColor
        span.alignment = .right
        title.font = Self.titleFont
        title.textColor = .labelColor
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.cell?.truncatesLastVisibleLine = true
        title.isSelectable = false
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detailIcon.contentTintColor = .secondaryLabelColor
        hairline.wantsLayer = true
        button.target = self
        button.action = #selector(primaryPressed)
        checkHint.onClick = { [weak self] in self?.onCheck?() }
        checkView.isHidden = true
        for subview in [dot, eyebrow, span, title, detailIcon, detail, people, checkView, hairline, dismissHint, checkHint, calendarHint, button] as [NSView] {
            addSubview(subview)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func primaryPressed() {
        onPrimary?()
    }

    func show(_ event: AgendaEvent, now: Date) {
        start = event.start
        span.stringValue = Self.span(event)
        title.stringValue = event.title.isEmpty ? "Untitled" : event.title
        var parts: [String] = []
        if let meeting = event.meeting {
            parts.append(meeting.service)
            detailIcon.image = Theme.symbol("video.fill", pointSize: 13, weight: .medium)
        } else {
            if !event.location.isEmpty { parts.append(event.location) }
            detailIcon.image = Theme.symbol(event.location.isEmpty ? "calendar" : "location.fill", pointSize: 12, weight: .medium)
        }
        if !event.calendar.isEmpty { parts.append(event.calendar) }
        detail.stringValue = parts.joined(separator: "  ·  ")
        people.names = event.attendees.map(\.name).filter { !$0.isEmpty }
        button.title = event.meeting != nil ? "Join" : "Got It"
        hasCall = event.meeting != nil
        if !hasCall { showCheck(nil) }
        tick(now: now)
        layoutContent()
    }

    /// The time left, or since it started, each second.
    func tick(now: Date) {
        let seconds = Int(start.timeIntervalSince(now).rounded())
        let started = seconds <= 0
        eyebrow.attributedStringValue = NSAttributedString(string: Self.eyebrow(seconds: seconds), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .kern: 0.9,
            .foregroundColor: started ? NSColor.systemRed : NSColor.secondaryLabelColor
        ])
        dot.color = started ? .systemRed : .controlAccentColor
        eyebrow.sizeToFit()
    }

    /// "STARTS IN 4:59", "STARTING NOW", "STARTED 2:05 AGO".
    static func eyebrow(seconds: Int) -> String {
        if abs(seconds) < 5 { return "STARTING NOW" }
        let clock = clock(abs(seconds))
        return seconds > 0 ? "STARTS IN \(clock)" : "STARTED \(clock) AGO"
    }

    static func clock(_ seconds: Int) -> String {
        seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func span(_ event: AgendaEvent) -> String {
        let format = DateFormatter()
        format.timeStyle = .short
        format.dateStyle = .none
        return "\(format.string(from: event.start)) – \(format.string(from: event.end))"
    }

    /// Self-test: the check open on a still image (no camera there).
    func showSampleCheck(image: NSImage) {
        checkView.showSample(camera: "FaceTime HD Camera", microphone: "MacBook Pro Microphone", image: image, level: 0.55)
        isChecking = true
        checkView.isHidden = false
        layoutContent()
    }

    /// The check opened (`check` live) or closed (nil): the card grows
    /// under who is in it, or back.
    func showCheck(_ check: MeetingCheck?) {
        if let check {
            checkView.show(check)
            isChecking = true
        } else {
            checkView.stopShowing()
            isChecking = false
        }
        checkView.isHidden = !isChecking
        layoutContent()
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hairline.layer?.backgroundColor = Theme.hairline.cgColor
    }

    private func layoutContent() {
        let inset = Self.inset
        let width = cardWidth
        let inner = width - 2 * inset
        hairline.layer?.backgroundColor = Theme.hairline.cgColor

        // When: the time left, and its span.
        var y: CGFloat = 26
        dot.frame = NSRect(x: inset, y: y + 4, width: 9, height: 9)
        span.sizeToFit()
        span.frame = NSRect(x: width - inset - span.frame.width, y: y, width: span.frame.width, height: 18)
        eyebrow.frame = NSRect(x: inset + 17, y: y + 1, width: max(0, span.frame.minX - inset - 30), height: 16)
        y += 34

        // What: two lines at most.
        let lineHeight = ceil(Self.titleFont.ascender - Self.titleFont.descender + Self.titleFont.leading)
        let measured = (title.stringValue as NSString).boundingRect(with: NSSize(width: inner, height: .greatestFiniteMagnitude),
                                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                                    attributes: [.font: Self.titleFont]).height
        let lines = min(2, max(1, Int((measured / lineHeight).rounded(.up))))
        title.frame = NSRect(x: inset - 2, y: y, width: inner + 4, height: CGFloat(lines) * lineHeight + 2)
        y = title.frame.maxY + 8

        // Where: the call or the place, and the calendar.
        let hasDetail = !detail.stringValue.isEmpty
        detail.isHidden = !hasDetail
        detailIcon.isHidden = !hasDetail
        if hasDetail {
            detailIcon.frame = NSRect(x: inset, y: y + 1, width: 18, height: 18)
            detail.frame = NSRect(x: inset + 24, y: y, width: inner - 24, height: 20)
            y += 28
        }

        // Who.
        people.isHidden = people.names.isEmpty
        if !people.isHidden {
            people.frame = NSRect(x: inset, y: y + 4, width: inner, height: PeopleView.size)
            y += PeopleView.size + 12
        }

        // The camera and the microphone, while checked.
        if isChecking {
            y += 6
            checkView.frame = NSRect(x: inset, y: y, width: inner, height: checkView.height(for: inner))
            y = checkView.frame.maxY + 4
        }

        // The keys, under a hairline the width of the card.
        y += 14
        hairline.frame = NSRect(x: 0, y: y, width: width, height: 1)
        y += 16
        button.sizeToFit()
        button.frame = NSRect(x: width - inset + 6 - button.frame.width, y: y, width: button.frame.width, height: PrimaryButton.height)
        let keysY = y + (PrimaryButton.height - 20) / 2
        // A call: Dismiss on the left, Calendar beside Join. Without one,
        // Got It is the dismissal: Calendar takes the left.
        let left = hasCall ? ("Dismiss", "esc") : ("Calendar", "⌘↩")
        dismissHint.frame = NSRect(x: inset, y: keysY, width: 160, height: 20)
        dismissHint.setHints([left])
        // HintBar right-aligns: this one starts at the inset.
        let used = dismissHint.subviews.map(\.frame.minX).min() ?? 0
        dismissHint.subviews.forEach { $0.frame.origin.x -= used }
        calendarHint.isHidden = !hasCall
        calendarHint.frame = NSRect(x: button.frame.minX - 20 - 160, y: keysY, width: 160, height: 20)
        calendarHint.setHints([("Calendar", "⌘↩")])
        // A call: the camera and microphone can be checked first (⇥), when
        // there is room between Dismiss and Calendar (not in Settings'
        // narrower preview).
        let dismissWidth = (dismissHint.subviews.map(\.frame.maxX).max() ?? 0)
        checkHint.frame = NSRect(x: inset + dismissWidth + 18, y: keysY, width: checkHint.fittingWidth, height: 20)
        let calendarLeft = calendarHint.frame.minX + (calendarHint.subviews.map(\.frame.minX).min() ?? 0)
        checkHint.isHidden = !hasCall || checkHint.frame.maxX + 18 > calendarLeft
    }

    /// The height its content needs.
    var fittingHeight: CGFloat {
        layoutContent()
        return button.frame.maxY + 20
    }
}


extension MeetingCardView {
    /// A meeting to show the card on: Settings' Try and preview.
    static func sample(startingIn seconds: TimeInterval) -> AgendaEvent {
        let start = Date.now.addingTimeInterval(seconds)
        let people = ["Paul Martin", "Anna Lefèvre", "Claire Dubois", "Marc Petit", "Sophie Bernard", "Louis Moreau"]
        return AgendaEvent(id: "sample-meeting", title: "Weekly design review", start: start, end: start.addingTimeInterval(30 * 60),
                           calendar: "Work", notes: "https://meet.google.com/abc-defg-hij",
                           attendees: people.map { AgendaEvent.Attendee(name: $0, email: nil) })
    }
}

/// A small round dot: mint before the meeting, red once it started.
final class DotView: NSView {
    var color: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// Who is in the meeting: up to four faces of initials, overlapping, then
/// "Paul, Anna and 4 others".
private final class PeopleView: NSView {
    static let size: CGFloat = 28
    var names: [String] = [] {
        didSet {
            if names != oldValue { rebuild() }
        }
    }

    override var isFlipped: Bool { true }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        guard !names.isEmpty else { return }
        var x: CGFloat = 0
        // The first in front: added last.
        let shown = Array(names.prefix(4))
        for (index, name) in shown.enumerated().reversed() {
            let face = InitialsView(name: name)
            face.frame = NSRect(x: CGFloat(index) * (Self.size - 7), y: 0, width: Self.size, height: Self.size)
            addSubview(face)
        }
        x = CGFloat(shown.count - 1) * (Self.size - 7) + Self.size
        let label = NSTextField(labelWithString: Self.sentence(names))
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        label.frame = NSRect(x: x + 12, y: (Self.size - label.frame.height) / 2, width: max(0, bounds.width - x - 12), height: label.frame.height)
        addSubview(label)
    }

    /// Built again only when its width changes: never on a layout pass
    /// (adding views there loops Auto Layout in Settings' preview).
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if changed { rebuild() }
    }

    /// "Paul", "Paul and Anna", "Paul, Anna and 4 others": first names.
    static func sentence(_ names: [String]) -> String {
        let first = names.map { String($0.split(separator: " ").first ?? Substring($0)) }
        switch first.count {
        case 0: return ""
        case 1: return first[0]
        case 2: return "\(first[0]) and \(first[1])"
        default:
            let others = first.count - 2
            return "\(first[0]), \(first[1]) and \(others) other\(others == 1 ? "" : "s")"
        }
    }
}

/// A person's initials on a color of their own (the same name, the same
/// color), white, as Calendar and Contacts draw them; a ring of the card's
/// own tone keeps overlapping faces apart.
private final class InitialsView: NSView {
    private let initials: String
    private let color: NSColor
    /// About the glass's own tone, light or dark: the ring around a face.
    private static let cardTone = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.21, alpha: 1) : NSColor(white: 0.95, alpha: 1)
    }
    private static let palette: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemOrange, .systemTeal, .systemIndigo, .systemGreen, .systemBrown]

    init(name: String) {
        let words = name.split(separator: " ").prefix(2)
        initials = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        // A stable hash: Swift's own changes at each launch.
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        color = Self.palette[sum % Self.palette.count]
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let ring = NSBezierPath(ovalIn: bounds)
        Self.cardTone.setFill()
        ring.fill()
        let face = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        (color.blended(withFraction: 0.12, of: .black) ?? color).setFill()
        face.fill()
        let text = NSAttributedString(string: initials, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/// Join ↩: the one filled control, in the accent color, its key inside.
final class PrimaryButton: NSButton {
    static let height: CGFloat = 36

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = "Join"
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var title: String {
        didSet { needsDisplay = true }
    }

    private var label: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white])
    }

    private static let key = NSAttributedString(string: "↩", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.75)
    ])

    override func sizeToFit() {
        setFrameSize(NSSize(width: ceil(label.size().width + Self.key.size().width) + 20 + 10 + 20, height: Self.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: Self.height / 2, yRadius: Self.height / 2)
        (isHighlighted ? NSColor.controlAccentColor.blended(withFraction: 0.2, of: .black) ?? .controlAccentColor : .controlAccentColor).setFill()
        shape.fill()
        let label = self.label
        let labelSize = label.size()
        let keySize = Self.key.size()
        var x: CGFloat = 20
        label.draw(at: NSPoint(x: x, y: (bounds.height - labelSize.height) / 2))
        x += labelSize.width + 10
        Self.key.draw(at: NSPoint(x: x, y: (bounds.height - keySize.height) / 2))
    }

    override var isFlipped: Bool { false }
}

/// A key hint the pointer can press: "Camera & Mic ⇥" in the meeting card.
private final class ClickHint: NSView {
    var onClick: (() -> Void)?
    private let label: NSTextField
    private let keycap: KeycapView

    init(label text: String, key: String) {
        label = NSTextField(labelWithString: text)
        label.font = Theme.Font.hint
        label.textColor = .secondaryLabelColor
        label.sizeToFit()
        keycap = KeycapView(key)
        super.init(frame: .zero)
        addSubview(label)
        addSubview(keycap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    var fittingWidth: CGFloat { label.frame.width + 6 + keycap.frame.width }

    override func layout() {
        super.layout()
        label.frame.origin = NSPoint(x: 0, y: (bounds.height - label.frame.height) / 2)
        keycap.frame.origin = NSPoint(x: label.frame.width + 6, y: (bounds.height - keycap.frame.height) / 2)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
