import AppKit

/// A small glass panel at System Settings' window, while the welcome waits
/// for the Accessibility switch: "Turn on skil.li", and skil.li's icon to
/// drag into the list when it is not there (docs/onboarding.md, step 2).
/// It follows the window, never takes the keyboard, and goes when the
/// switch is on or System Settings closes.
@MainActor
final class SettingsGuide {
    private var panel: NSPanel?
    private var timer: Timer?
    /// When System Settings' window was last seen: gone a while, the guide
    /// goes too.
    private var lastSeen: ContinuousClock.Instant?
    private var shownAt: ContinuousClock.Instant?

    static let settingsBundleID = "com.apple.systempreferences"
    /// Whose window it follows: System Settings, or the self-test's own.
    var followed: @MainActor () -> pid_t? = {
        NSRunningApplication.runningApplications(withBundleIdentifier: SettingsGuide.settingsBundleID).first?.processIdentifier
    }
    private static let size = NSSize(width: 360, height: 76)

    var isVisible: Bool { panel?.isVisible == true }
    /// Self-test hook: the panel, to check where it sits.
    var shownPanel: NSPanel? { panel }

    /// Shown for `listName` ("Accessibility", or "Device Control and Data
    /// Access" from macOS 27) until `isDone` says so.
    func show(listName: String, isDone: @escaping @MainActor () -> Bool) {
        let panel = self.panel ?? makePanel(listName: listName)
        self.panel = panel
        shownAt = .now
        lastSeen = nil
        timer?.invalidate()
        // System Settings takes a moment to open its pane.
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if isDone() { return self.hide() }
                self.follow()
            }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    /// Under System Settings' window when there is room, else inside its
    /// bottom edge: never over the list or its + and − buttons.
    private func follow() {
        guard let panel else { return }
        guard let frame = followed().flatMap(Self.windowFrame(of:)) else {
            // Not open yet, or closed: gone after a while.
            let since = lastSeen ?? shownAt ?? .now
            if ContinuousClock.now - since > .seconds(lastSeen == nil ? 6 : 1.5) { hide() }
            panel.orderOut(nil)
            return
        }
        lastSeen = .now
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? frame
        let margin = Theme.glassMargin
        var origin = NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY - Self.size.height - 8 - margin)
        if origin.y + margin < visible.minY { origin.y = frame.minY + 12 - margin }
        origin.x = min(max(origin.x, visible.minX - margin), visible.maxX - panel.frame.width + margin)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// An app's largest window (System Settings' main one), in AppKit's
    /// coordinates. Bounds and owners need no Screen Recording, only names
    /// would.
    static func windowFrame(of pid: pid_t) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first
        else { return nil }
        let frames = list.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 320, rect.height > 240
            else { return nil }
            return rect
        }
        guard let largest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
        // Window server: origin at the primary screen's top left, y down.
        return NSRect(x: largest.minX, y: primary.frame.maxY - largest.maxY, width: largest.width, height: largest.height)
    }

    private func makePanel(listName: String) -> NSPanel {
        let margin = Theme.glassMargin
        let content = NSView(frame: NSRect(origin: .zero, size: Self.size))

        let icon = DraggableAppIcon(frame: NSRect(x: 16, y: (Self.size.height - 44) / 2, width: 44, height: 44))
        content.addSubview(icon)

        let title = NSTextField(labelWithString: "Turn on skil.li")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: "In \(listName). Not in the list? Drag this icon into it.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2
        detail.preferredMaxLayoutWidth = Self.size.width - 120
        let texts = NSStackView(views: [title, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        texts.frame = NSRect(x: 72, y: 12, width: Self.size.width - 120, height: Self.size.height - 24)
        content.addSubview(texts)

        let arrow = NSImageView(image: Theme.symbol("arrow.up", pointSize: 18, weight: .semibold) ?? NSImage())
        arrow.contentTintColor = NSColor(named: "AccentColor")
        arrow.frame = NSRect(x: Self.size.width - 40, y: (Self.size.height - 24) / 2, width: 24, height: 24)
        content.addSubview(arrow)

        let glass = Theme.glass(cornerRadius: 18, content: content)
        glass.frame = NSRect(x: margin, y: margin, width: Self.size.width, height: Self.size.height)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: Self.size.width + margin * 2, height: Self.size.height + margin * 2))
        root.addSubview(glass)

        let panel = GuidePanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = root
        panel.setAccessibilityLabel("Turn on skil.li in \(listName)")
        return panel
    }
}

/// Never key: the keyboard stays with System Settings.
private final class GuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// skil.li's icon, dragged as the app itself: System Settings' list adds
/// an app dropped on it.
private final class DraggableAppIcon: NSImageView, NSDraggingSource {
    override init(frame: NSRect) {
        super.init(frame: frame)
        image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityLabel("skil.li, to drag into the list")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
