import AppKit
import SkilliCore

/// Clean Keyboard: every key, modifier and media key does nothing for a
/// minute, so the keyboard can be wiped; a glass card on each screen counts
/// down, and its Done button (the mouse still works) turns the keys back on.
/// Its own event tap, ahead of skil.li's, only while cleaning. Keys typed in
/// a password field (Secure Input) are not seen by any tap: macOS keeps them.
@MainActor
final class KeyboardCleaner {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var panels: [NSPanel] = []
    private var countdowns: [NSTextField] = []
    private var ticker: Timer?
    private var end: Date?
    /// Self-test hooks: what the tap kept from the apps, and the card.
    private(set) var swallowed = 0
    var overlay: NSWindow? { panels.first }
    var isCleaning: Bool { end != nil }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Turns the keys off for `seconds`; again while cleaning starts over.
    func start(seconds: Int = 60) throws {
        if port == nil {
            let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
            // NX_SYSDEFINED: brightness, volume, media and the other function keys.
            let mask = types.reduce(CGEventMask(1 << 14)) { $0 | CGEventMask(1 << $1.rawValue) }
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: keyboardCleanerCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque())
            else { throw Failure(message: "skil.li needs Accessibility to turn the keyboard off.") }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            self.port = port
            self.source = source
        }
        swallowed = 0
        end = .now.addingTimeInterval(TimeInterval(seconds))
        showOverlay()
        ticker?.invalidate()
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        tick()
        Log.trace("Clean Keyboard: keys off for \(seconds) s")
    }

    /// The keys back on, the card gone.
    func stop() {
        guard end != nil else { return }
        end = nil
        ticker?.invalidate()
        ticker = nil
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        countdowns = []
        Log.trace("Clean Keyboard: keys back on, \(swallowed) events kept")
    }

    fileprivate func process(_ type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port, end != nil { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        guard end != nil else { return false }
        swallowed += 1
        return true
    }

    private func tick() {
        guard let end else { return }
        let left = Int(end.timeIntervalSinceNow.rounded(.up))
        guard left > 0 else {
            stop()
            return
        }
        countdowns.forEach { $0.stringValue = TimerRequest.clock(left) }
    }

    // MARK: - The card

    private func showOverlay() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        countdowns = []
        for screen in NSScreen.screens {
            let panel = CleaningPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.35)
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.setFrame(screen.frame, display: false)
            let card = makeCard()
            card.frame.origin = NSPoint(x: (screen.frame.width - card.frame.width) / 2, y: (screen.frame.height - card.frame.height) / 2)
            panel.contentView?.addSubview(card)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        // Key (without taking the app in front): Done draws active.
        panels.first?.makeKey()
    }

    private func makeCard() -> NSView {
        let size = NSSize(width: 360, height: 300)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let glass = Theme.glass(cornerRadius: Theme.Radius.card, content: content)
        glass.frame = content.frame

        let icon = NSImageView(image: Theme.symbol("keyboard", pointSize: 40, weight: .light) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: "Cleaning the keyboard")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let detail = NSTextField(labelWithString: "Every key is off: wipe away.")
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        let countdown = NSTextField(labelWithString: "1:00")
        countdown.font = .monospacedDigitSystemFont(ofSize: 34, weight: .medium)
        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.bezelStyle = .glass
        done.bezelColor = .controlAccentColor
        done.controlSize = .large
        done.setAccessibilityLabel("Done Cleaning")
        countdowns.append(countdown)

        // Centered as one column: icon, title, detail, countdown, Done.
        icon.frame.size = icon.intrinsicContentSize
        let views: [NSView] = [icon, title, detail, countdown, done]
        let gaps: [CGFloat] = [14, 6, 14, 18, 0]
        for view in views { (view as? NSControl)?.sizeToFit() }
        done.frame.size.width = max(done.frame.width, 120)
        let total = zip(views, gaps).reduce(0) { $0 + $1.0.frame.height + $1.1 }
        var y = (size.height + total) / 2
        for (view, gap) in zip(views, gaps) {
            y -= view.frame.height
            view.frame.origin = NSPoint(x: ((size.width - view.frame.width) / 2).rounded(), y: y.rounded())
            content.addSubview(view)
            y -= gap
        }
        return glass
    }

    @objc private func doneClicked() {
        stop()
    }
}

/// Borderless panels are never key by default; this one is, so its button
/// draws active.
private final class CleaningPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private func keyboardCleanerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                     refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let cleaner = Unmanaged<KeyboardCleaner>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated { cleaner.process(type) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
