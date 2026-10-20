import AppKit

/// Every screen dark around the card (a meeting alert set to "Card,
/// screens dark"): one window per screen, blurred and darkened, under the
/// card and over everything else, the menu bar and the Dock included. A click on the dark
/// lets the alert go; it leaves with the card.
@MainActor
final class ScreenDimmer {
    /// A click on the dark.
    var onClick: (() -> Void)?
    private var windows: [NSWindow] = []
    /// Self-test hook.
    var isShown: Bool { !windows.isEmpty }

    /// Below the card's level: the screen blurred and darkened, as macOS
    /// does behind its own alerts.
    func show(below level: NSWindow.Level) {
        hide()
        for screen in NSScreen.screens {
            let window = DarkWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: level.rawValue - 1)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.alphaValue = 0
            window.onClick = { [weak self] in self?.onClick?() }
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .darkAqua)
            let shade = NSView(frame: blur.bounds)
            shade.wantsLayer = true
            shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
            shade.autoresizingMask = [.width, .height]
            blur.addSubview(shade)
            window.contentView = blur
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.35
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private final class DarkWindow: NSWindow {
        var onClick: (() -> Void)?
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        /// Over the menu bar too: never moved below it.
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }
    }
}
