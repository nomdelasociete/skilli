import AppKit
import SkilliCore

/// At the right of the empty search field while the Mac is kept awake: the
/// menu bar's full cup and the time left ("42 min"; the cup alone until
/// turned off), quiet as a row's accessory. Under the pointer it says what
/// a click does ("42 min · Turn Off"), and a click turns Keep Awake off at
/// once (2026-10-22: turning it off "was not clear at all"). Drawn, not
/// laid out.
final class AwakeChipView: NSView {
    var onTurnOff: (() -> Void)?
    /// Self-test hooks: the time left it shows ("" for the cup alone), and
    /// the words drawn now (with "· Turn Off" under the pointer).
    private(set) var shownText = ""
    var drawnText: String { AwakeStatus.chip(left: shownText, hovered: hovered) }
    private var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            fit()
        }
    }

    static let height: CGFloat = 24
    private static let font = Theme.Font.rowAccessory
    private static let padding: CGFloat = 9
    private static let cupHeight: CGFloat = 12
    private static let gap: CGFloat = 5

    /// Another time left. Only when it changed: nothing measured on a show
    /// that says the same.
    func show(left: String) {
        guard left != shownText || frame.width == 0 else { return }
        shownText = left
        fit()
        let label = left.isEmpty ? AwakeStatus.turnOff : "\(AwakeStatus.turnOff) (\(left) left)"
        setAccessibilityLabel(label)
        toolTip = label
    }

    /// The width follows the words, the right edge stays.
    private func fit() {
        let right = frame.maxX
        let text = drawnText
        var width = Self.padding * 2 + Self.cupSize.width
        if !text.isEmpty { width += Self.gap + ceil(Self.attributed(text, hovered: hovered).size().width) }
        frame = NSRect(x: right - width, y: frame.minY, width: width, height: Self.height)
        needsDisplay = true
    }

    private static var cupSize: NSSize {
        guard let size = AwakeIndicator.cup?.size, size.height > 0 else { return NSSize(width: cupHeight, height: cupHeight) }
        return NSSize(width: (size.width * cupHeight / size.height).rounded(), height: cupHeight)
    }

    private static func color(hovered: Bool) -> NSColor { hovered ? .labelColor : .secondaryLabelColor }

    private static func attributed(_ text: String, hovered: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color(hovered: hovered)])
    }

    override func draw(_ dirtyRect: NSRect) {
        // A keycap's wash, more under the pointer, where it names its click.
        (hovered ? NSColor.labelColor.withAlphaComponent(0.12) : Theme.keycapFill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let cup = Self.cupSize
        var x = Self.padding
        let color = Self.color(hovered: hovered)
        if let image = AwakeIndicator.cup {
            // The words' own color through the cup's shape: tinting over its
            // black ink drew it darker than the words beside it.
            let rect = NSRect(x: x, y: ((bounds.height - cup.height) / 2).rounded(), width: cup.width, height: cup.height)
            let mask = NSImage(size: cup, flipped: false) { frame in
                color.setFill()
                frame.fill()
                image.draw(in: frame, from: .zero, operation: .destinationIn, fraction: 1)
                return true
            }
            mask.draw(in: rect)
        }
        x += cup.width + Self.gap
        let words = drawnText
        guard !words.isEmpty else { return }
        let text = Self.attributed(words, hovered: hovered)
        text.draw(at: NSPoint(x: x, y: ((bounds.height - text.size().height) / 2).rounded()))
    }

    override func mouseDown(with event: NSEvent) {
        onTurnOff?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    /// Hidden under the pointer (clicked, a key typed): no exit comes.
    override func viewDidHide() {
        super.viewDidHide()
        hovered = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        onTurnOff?()
        return true
    }
}
