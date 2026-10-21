import AppKit
import Carbon.HIToolbox
import SkilliCore

/// Asked in the middle of a display just plugged in: put back one of the
/// layouts saved on it? ↑↓ picks, ↩ applies, esc ignores this once, ⌘K the
/// rest (always, never, ignore this monitor, edit, record a new one). It
/// takes the keyboard only when the user is not typing; a click does too.
/// No time limit: it stays until answered or the display goes.
@MainActor
final class DisplayPrompt {
    struct Offer {
        let layout: SavedWindowLayout
        let certainty: DisplayFingerprint.Certainty
        let exact: Bool
    }

    var onApply: ((SavedWindowLayout) -> Void)?
    var onAlways: ((SavedWindowLayout) -> Void)?
    var onNever: ((SavedWindowLayout) -> Void)?
    var onIgnoreMonitors: (([DisplayFingerprint]) -> Void)?
    var onEdit: ((SavedWindowLayout) -> Void)?
    var onRecord: (() -> Void)?

    private(set) var offers: [Offer] = []
    /// The displays it asks about.
    private(set) var plugged: [DisplayFingerprint] = []
    private(set) var selected = 0
    private var panel: PromptPanel?
    /// The glass itself: NSGlassEffectView puts its content view in a
    /// container of its own, so `content.superview` is not it.
    private var glass: NSGlassEffectView?
    private let content = FlippedView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let hints = HintBar()
    private let actions = ActionPanelView()
    private var rows: [OfferRow] = []

    private static let width: CGFloat = 460
    private static let rowHeight: CGFloat = 48
    private static let radius: CGFloat = 26

    var isVisible: Bool { panel?.isVisible ?? false }
    var isKey: Bool { panel?.isKeyWindow ?? false }
    var isShowingActions: Bool { !actions.isHidden }
    var frame: NSRect? { panel?.frame }

    /// Shows (or updates) the question for `plugged`, centered in
    /// `visible` (AppKit's coordinates). The keyboard is taken unless a key
    /// was pressed in the last second.
    func show(_ offers: [Offer], plugged: [DisplayFingerprint], centeredIn visible: NSRect) {
        guard !offers.isEmpty else {
            hide()
            return
        }
        let keep = self.offers.indices.contains(selected) ? self.offers[selected].layout.id : nil
        self.offers = offers
        self.plugged = plugged
        selected = offers.firstIndex { $0.layout.id == keep } ?? 0
        let panel = self.panel ?? makePanel()
        self.panel = panel
        actions.isHidden = true
        layout()
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded()))
        let typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1
        if typing {
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        Log.trace("Display prompt: \(offers.count) layout\(offers.count == 1 ? "" : "s") for \(plugged.map(\.name).joined(separator: ", "))\(typing ? ", typing: keyboard left alone" : "")")
    }

    /// Self-test hook: the question as PNG, as it shows on screen; else
    /// its content drawn off screen on the window background, ⌘K's list
    /// over it (the glass itself does not draw off screen).
    func snapshotPNG() async -> Data? {
        guard let panel, let root = panel.contentView, let glass else { return nil }
        if let png = await WindowCapture.png(of: panel) { return png }
        let image = NSImage(size: root.bounds.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: glass.frame, xRadius: Self.radius, yRadius: Self.radius).fill()
        for (view, frame) in [(content as NSView, glass.frame), (actions as NSView, actions.frame)] where !view.isHidden {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            bitmap.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func hide() {
        panel?.orderOut(nil)
        actions.isHidden = true
        offers = []
        plugged = []
    }

    // MARK: - Keys

    /// A key pressed while it has the keyboard.
    fileprivate func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        let isReturn = code == kVK_Return || code == kVK_ANSI_KeypadEnter
        let commandK = flags == .command && event.charactersIgnoringModifiers?.lowercased() == "k"
        if !actions.isHidden {
            if commandK || code == kVK_Escape {
                closeActions()
            } else if code == kVK_UpArrow {
                actions.move(by: -1, wraps: !event.isARepeat)
            } else if code == kVK_DownArrow {
                actions.move(by: 1, wraps: !event.isARepeat)
            } else if let step = LauncherController.controlStep(event) {
                actions.move(by: step, wraps: !event.isARepeat)
            } else if code == kVK_Delete {
                actions.deleteBackward()
            } else if isReturn {
                if let action = actions.selectedAction { action.run() }
            } else if flags.subtracting(.shift).isEmpty, let text = event.characters, !text.isEmpty {
                actions.type(text)
            } else {
                return false
            }
            return true
        }
        if commandK {
            openActions()
        } else if code == kVK_Escape {
            ignoreOnce()
        } else if code == kVK_UpArrow {
            select(selected - 1)
        } else if code == kVK_DownArrow {
            select(selected + 1)
        } else if isReturn {
            apply()
        } else {
            return false
        }
        return true
    }

    func apply() {
        guard offers.indices.contains(selected) else { return }
        let layout = offers[selected].layout
        hide()
        onApply?(layout)
    }

    func ignoreOnce() {
        Log.trace("Display prompt: ignored once")
        hide()
    }

    private func select(_ index: Int) {
        guard !offers.isEmpty else { return }
        selected = min(max(index, 0), offers.count - 1)
        for (offset, row) in rows.enumerated() { row.isSelected = offset == selected }
    }

    // MARK: - ⌘K

    func openActions() {
        guard offers.indices.contains(selected) else { return }
        let chosen = offers[selected].layout
        let sure = offers[selected].certainty == .unit
        let monitors = plugged.map(\.name).joined(separator: " and ")
        // The layout's name heads the list: the titles stay short.
        var list = [LauncherAction(title: "Apply", symbol: "rectangle.3.group", key: .open) { [weak self] in self?.apply() }]
        // Without its own serial the display may be another unit: always
        // asked, never put back alone.
        if sure {
            list.append(LauncherAction(title: "Always Apply Without Asking", symbol: "bolt") { [weak self] in
                self?.hide()
                self?.onAlways?(chosen)
            })
        }
        list += [
            LauncherAction(title: "Edit Layout…", symbol: "slider.horizontal.3") { [weak self] in
                self?.hide()
                self?.onEdit?(chosen)
            },
            LauncherAction(title: "Record New Layout Here…", symbol: "record.circle") { [weak self] in
                self?.hide()
                self?.onRecord?()
            },
            LauncherAction(title: "Ignore Once", symbol: "xmark", group: .remove) { [weak self] in self?.ignoreOnce() },
            LauncherAction(title: "Never Apply Automatically", symbol: "nosign", group: .remove) { [weak self] in
                self?.hide()
                self?.onNever?(chosen)
            },
            LauncherAction(title: "Ignore \(monitors)", symbol: "display.trianglebadge.exclamationmark", group: .remove) { [weak self] in
                guard let self else { return }
                let plugged = self.plugged
                self.hide()
                self.onIgnoreMonitors?(plugged)
            }
        ]
        // Sized first: the list lays itself out in the space it is given.
        layout(forActions: list.count)
        actions.show(list, for: chosen.name)
    }

    private func closeActions() {
        actions.isHidden = true
        layout()
    }

    // MARK: - Drawing

    private func makePanel() -> PromptPanel {
        let panel = PromptPanel(size: NSSize(width: Self.width + 2 * Theme.glassMargin, height: 200))
        panel.prompt = self
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        content.addSubview(titleLabel)
        content.addSubview(subtitle)
        content.addSubview(hints)
        actions.isHidden = true
        actions.onRun = { action in action.run() }
        actions.onDismiss = { [weak self] in self?.closeActions() }
        let glass = Theme.glass(cornerRadius: Self.radius, content: content)
        self.glass = glass
        let root = NSView()
        root.addSubview(glass)
        root.addSubview(actions)
        panel.contentView = root
        return panel
    }

    /// Title, one row per layout offered, the keys; taller while ⌘K's list
    /// is open so it fits.
    private func layout(forActions count: Int = 0) {
        guard let panel, let root = panel.contentView, let glass else { return }
        let names = plugged.map(\.name)
        titleLabel.stringValue = "\(names.joined(separator: " and ")) plugged in"
        subtitle.stringValue = offers.count == 1 ? "Put this layout's windows back?" : "Put one of these layouts' windows back?"
        rows.forEach { $0.removeFromSuperview() }
        rows = offers.enumerated().map { offset, offer in
            let row = OfferRow(offer: offer)
            row.onClick = { [weak self] double in
                self?.select(offset)
                if double { self?.apply() }
            }
            row.isSelected = offset == selected
            return row
        }
        let top: CGFloat = 20
        titleLabel.frame = NSRect(x: 22, y: top, width: Self.width - 44, height: 22)
        subtitle.frame = NSRect(x: 22, y: top + 26, width: Self.width - 44, height: 18)
        var y = top + 56
        for row in rows {
            row.frame = NSRect(x: 10, y: y, width: Self.width - 20, height: Self.rowHeight)
            content.addSubview(row)
            y += Self.rowHeight
        }
        y += 10
        hints.frame = NSRect(x: 22, y: y, width: Self.width - 44, height: 24)
        hints.setHints([("Apply", "↩"), ("Ignore", "esc"), ("More", "⌘K")])
        let height = y + 24 + 16
        // ⌘K's list rises from just above the keys, inside the glass.
        let listHeight = count == 0 ? 0 : CGFloat(count) * 30 + 2 * 9 + 30 + 8 + 36 + 20
        let total = max(height, listHeight + 40)
        let margin = Theme.glassMargin
        var frame = panel.frame
        let newSize = NSSize(width: Self.width + 2 * margin, height: total + 2 * margin)
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        panel.setFrame(frame, display: true)
        root.frame = NSRect(origin: .zero, size: newSize)
        glass.frame = NSRect(x: margin, y: margin, width: Self.width, height: total)
        content.frame = glass.bounds
        actions.frame = NSRect(x: margin, y: margin, width: Self.width, height: total)
        actions.bottom = 46
    }
}

/// Borderless, non-activating, over every space: the app in front stays in
/// front; the keys come here only once it is the key window.
private final class PromptPanel: NSPanel {
    weak var prompt: DisplayPrompt?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if prompt?.handle(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, event.type == .keyDown, prompt?.handle(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        prompt?.ignoreOnce()
    }
}

/// Top-down layout inside the glass.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One layout offered: its name, what it holds, how sure the display is.
private final class OfferRow: NSView {
    var onClick: ((_ double: Bool) -> Void)?
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init(offer: DisplayPrompt.Offer) {
        super.init(frame: .zero)
        name.stringValue = offer.layout.name
        name.font = Theme.Font.rowTitle
        name.lineBreakMode = .byTruncatingTail
        var parts = [offer.layout.summary, "\(offer.layout.windows.count) window\(offer.layout.windows.count == 1 ? "" : "s")"]
        if offer.exact { parts.append("made for these displays") }
        if offer.certainty == .model { parts.append("same model, no serial to be sure") }
        detail.stringValue = parts.joined(separator: " · ")
        detail.font = Theme.Font.rowAccessory
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        addSubview(name)
        addSubview(detail)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(offer.layout.name)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        name.frame = NSRect(x: 12, y: 6, width: bounds.width - 24, height: 18)
        detail.frame = NSRect(x: 12, y: 25, width: bounds.width - 24, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        Theme.selectionFill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14).fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        onClick?(event.clickCount >= 2)
    }
}
