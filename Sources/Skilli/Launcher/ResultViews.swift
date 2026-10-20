import AppKit

/// Selection is a soft capsule concentric with the card, drawn the same way
/// whether or not skil.li is the active app (the launcher never activates it).
final class ResultRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultRowView")
    private static let inset = NSSize(width: 10, height: 1)

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: Self.inset.width, dy: Self.inset.height)
        Theme.selectionFill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Theme.Radius.row, yRadius: Theme.Radius.row).fill()
    }
}

final class ResultCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCellView")

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    /// "SI Command" reveals "AI Command" under the pointer.
    private let accessory = SIRevealLabel(labelWithString: "")
    /// Pinned with ⌘K → Pin: a small pin after the title.
    private let pin = NSImageView()
    private(set) var isPinned = false
    private static let pinSize: CGFloat = 12

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 700, height: 46))
        identifier = Self.identifier

        icon.frame = NSRect(x: 22, y: 7, width: 32, height: 32)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        imageView = icon

        title.font = Theme.Font.rowTitle
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
        textField = title

        accessory.font = Theme.Font.rowAccessory
        accessory.textColor = .tertiaryLabelColor
        accessory.alignment = .right
        accessory.lineBreakMode = .byTruncatingTail
        addSubview(accessory)

        pin.image = Theme.symbol("pin.fill", pointSize: 10, weight: .semibold)
        pin.imageScaling = .scaleNone
        pin.contentTintColor = .secondaryLabelColor
        pin.frame.size = NSSize(width: Self.pinSize, height: Self.pinSize)
        pin.isHidden = true
        pin.setAccessibilityLabel("Pinned")
        addSubview(pin)
        layoutLabels()
    }

    var accessoryText: String { accessory.text }

    /// Self-test hook: the accessory as drawn ("AI Command" under the
    /// pointer) and where it is on screen.
    var accessoryShown: (text: String, frame: NSRect?) {
        (accessory.stringValue, window.map { $0.convertToScreen(accessory.convert(accessory.bounds, to: nil)) })
    }

    /// The item's alias, a keycap before the accessory ("e").
    private var aliasCap: KeycapView?
    private(set) var aliasText: String?

    func setAlias(_ alias: String?) {
        guard alias != aliasText else { return }
        aliasText = alias
        aliasCap?.removeFromSuperview()
        aliasCap = alias.map(KeycapView.init)
        if let aliasCap { addSubview(aliasCap) }
        layoutLabels()
    }

    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        pin.isHidden = !pinned
        layoutLabels()
    }

    /// A row that shows the same thing after a key (most do, typing on)
    /// is left as it is: nothing set, laid out or drawn again.
    func configure(title: String, accessory: String, icon: NSImage) {
        if self.icon.image !== icon { self.icon.image = icon }
        guard title != shownTitle || accessory != self.accessory.text else { return }
        shownTitle = title
        self.title.stringValue = title
        if accessory != self.accessory.text { self.accessory.text = accessory }
        layoutLabels()
    }

    /// The title as last set (no round trip through the label).
    private var shownTitle = ""

    override func layout() {
        super.layout()
        layoutLabels()
    }

    /// The title takes what the accessory leaves: 440 pt beside it in the
    /// full list, the whole row in the clipboard's narrow one.
    private func layoutLabels() {
        let accessoryWidth: CGFloat = accessory.stringValue.isEmpty ? 0 : 156
        accessory.frame = NSRect(x: bounds.width - 24 - accessoryWidth, y: 15, width: accessoryWidth, height: 16)
        var titleEnd = accessoryWidth > 0 ? accessory.frame.minX - 14 : bounds.width - 16
        // Right after the title's text, where Raycast shows its alias: the
        // pin, then the alias.
        let pinWidth = isPinned ? Self.pinSize : 0
        let marks = pinWidth + (isPinned && aliasCap != nil ? 8 : 0) + (aliasCap?.frame.width ?? 0)
        if marks > 0 {
            let gap: CGFloat = isPinned ? 8 : 10
            var x = min(66 + ceil(title.attributedStringValue.size().width) + gap, titleEnd - marks)
            // The label draws its text 2 pt in from each side.
            titleEnd = x - 2
            if isPinned {
                pin.frame.origin = NSPoint(x: x, y: ((bounds.height - Self.pinSize) / 2).rounded())
                x += pinWidth + 8
            }
            aliasCap?.frame.origin = NSPoint(x: x, y: (bounds.height - (aliasCap?.frame.height ?? 0)) / 2)
        }
        title.frame = NSRect(x: 66, y: 14, width: max(0, titleEnd - 66), height: 18)
    }

    /// Keep label colors on selection: the soft capsule needs no inversion.
    override var backgroundStyle: NSView.BackgroundStyle {
        get { .normal }
        set {}
    }
}
