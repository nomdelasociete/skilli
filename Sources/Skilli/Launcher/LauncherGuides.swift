import AppKit
import QuartzCore
import SkilliCore

/// The lines the launcher's glass is pulled onto while it is dragged: the
/// screen's middles and the standard height. Each a one-point accent line,
/// strongest beside the glass and fading toward the screen's edges, in a
/// window the size of the line (a full-screen window would hold a
/// full-screen backing store). Made on the first drag, then kept.
@MainActor
final class LauncherGuides {
    private lazy var vertical = GuideLine(vertical: true)
    private lazy var horizontal = GuideLine(vertical: false)
    /// Self-test hook: the lines on screen now.
    private(set) var shown: [LauncherGuide] = []

    /// The lines the glass sits on now; a new one taps the trackpad, like
    /// alignment guides elsewhere in macOS.
    func show(_ guides: [LauncherGuide], glass: NSRect, in visible: NSRect, below launcher: NSWindow) {
        if guides.contains(where: { !shown.contains($0) }) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        shown = guides
        if guides.contains(.centerX) {
            vertical.show(NSRect(x: glass.midX - 0.5, y: visible.minY, width: 1, height: visible.height),
                          peak: (glass.midY - visible.minY) / visible.height, below: launcher)
        } else {
            vertical.hide()
        }
        if let guide = guides.first(where: { $0 != .centerX }) {
            let y = guide == .centerY ? glass.midY : glass.maxY
            horizontal.show(NSRect(x: visible.minX, y: y - 0.5, width: visible.width, height: 1),
                            peak: (glass.midX - visible.minX) / visible.width, below: launcher)
        } else {
            horizontal.hide()
        }
    }

    func hide() {
        shown = []
        vertical.hide()
        horizontal.hide()
    }
}

/// One guide: a borderless, click-through window the size of its line,
/// filled with a gradient that peaks at the glass.
@MainActor
private final class GuideLine {
    private let window: NSPanel
    private let gradient = CAGradientLayer()

    init(vertical: Bool) {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        let view = NSView()
        view.wantsLayer = true
        gradient.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        gradient.endPoint = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(gradient)
        window.contentView = view
    }

    func show(_ frame: NSRect, peak: CGFloat, below launcher: NSWindow) {
        var accent = NSColor.controlAccentColor.cgColor
        window.contentView?.effectiveAppearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        }
        let clear = accent.copy(alpha: 0) ?? accent
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = [clear, accent, clear]
        gradient.locations = [0, NSNumber(value: Double(min(max(peak, 0.05), 0.95))), 1]
        window.setFrame(frame, display: false)
        gradient.frame = window.contentView?.bounds ?? .zero
        CATransaction.commit()
        guard !window.isVisible else { return }
        // A short fade: the line eases in rather than flashing.
        window.alphaValue = 0
        window.order(.below, relativeTo: launcher.windowNumber)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        window.orderOut(nil)
    }
}
