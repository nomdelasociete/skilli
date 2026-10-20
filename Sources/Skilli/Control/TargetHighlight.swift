import AppKit

/// A ring around what skil.li is about to press, a moment before it does:
/// the user sees where it acts. Above every window, never in the way of a
/// click.
@MainActor
final class TargetHighlight {
    private var panel: NSPanel?

    /// `frame` in Accessibility's coordinates (top-left origin).
    func show(_ frame: CGRect) {
        let rect = Self.cocoaRect(frame).insetBy(dx: -4, dy: -4)
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        panel.setFrame(rect, display: true)
        panel.contentView?.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Accessibility's top-left origin to AppKit's bottom-left, on the
    /// screen whose top-left is the origin.
    static func cocoaRect(_ frame: CGRect) -> NSRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = RingView()
        return panel
    }

    private final class RingView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 3
            path.stroke()
        }
    }
}
