import AppKit
import SkilliCore

/// At the right of the empty search field while the Mac is kept awake: the
/// menu bar's full cup and the time left ("42 min"; the cup alone until let
/// sleep), quiet as a row's accessory. A click types "awake": its running
/// row, ↩ Allow Sleep, ⌘K an hour more. Drawn, not laid out.
final class AwakeChipView: NSView {
    var onClick: (() -> Void)?
    /// Self-test hook: the time shown beside the cup ("" for the cup alone).
    private(set) var shownText = ""
    private var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    static let height: CGFloat = 24
    private static let font = Theme.Font.rowAccessory
    private static let padding: CGFloat = 9
    private static let cupHeight: CGFloat = 12
    private static let gap: CGFloat = 5

    /// Another time left; the width follows it, the right edge stays.
    /// Only when it changed: nothing measured on a show that says the same.
    func show(left: String) {
        guard left != shownText || frame.width == 0 else { return }
        shownText = left
        let right = frame.maxX
        var width = Self.padding * 2 + Self.cupSize.width
        if !left.isEmpty { width += Self.gap + ceil(Self.attributed(left).size().width) }
        frame = NSRect(x: right - width, y: frame.minY, width: width, height: Self.height)
        setAccessibilityLabel(left.isEmpty ? "Keeping the Mac awake until you allow sleep" : "Keeping the Mac awake, \(left) left")
        needsDisplay = true
    }

    private static var cupSize: NSSize {
        guard let size = AwakeIndicator.cup?.size, size.height > 0 else { return NSSize(width: cupHeight, height: cupHeight) }
        return NSSize(width: (size.width * cupHeight / size.height).rounded(), height: cupHeight)
    }

    private static func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func draw(_ dirtyRect: NSRect) {
        // A keycap's wash, a little more under the pointer: it can be
        // clicked, it does not call for it.
        (hovered ? NSColor.labelColor.withAlphaComponent(0.12) : Theme.keycapFill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let cup = Self.cupSize
        var x = Self.padding
        if let image = AwakeIndicator.cup?.tinted(.secondaryLabelColor) {
            image.draw(in: NSRect(x: x, y: ((bounds.height - cup.height) / 2).rounded(), width: cup.width, height: cup.height))
        }
        x += cup.width + Self.gap
        guard !shownText.isEmpty else { return }
        let text = Self.attributed(shownText)
        text.draw(at: NSPoint(x: x, y: ((bounds.height - text.size().height) / 2).rounded()))
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
