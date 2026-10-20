import AppKit
import SkilliCore

/// A row of the Catalog ("?"): the icon tile and the name where every
/// launcher row has them, one line under the name saying what it does, and
/// on the right how to reach it as keycaps: its prefix, the user's alias,
/// its shortcut. A wider gap between two ways than between the keys of one.
/// Turned off in Settings → Catalog: dimmed, "Off" before its keycaps; it
/// still runs from here.
final class CatalogCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("CatalogCellView")
    /// Between the keys of one way (✦ W, then ←).
    private static let keySpacing: CGFloat = 4
    /// Between two ways (the prefix, the alias, the shortcut).
    private static let waySpacing: CGFloat = 12

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    /// "Ask SI anything…" reveals "AI" under the pointer.
    private let subtitle = SIRevealLabel(labelWithString: "")
    /// The keycaps shown, one array per way; owned by the launcher's cache.
    private var ways: [[KeycapView]] = []
    /// Self-test hook: the keycaps' labels, one array per way.
    private(set) var shownKeys: [[String]] = []
    /// "Off": out of the launcher's results (Settings → Catalog).
    private let offLabel = NSTextField(labelWithString: "Off")
    /// Self-test hook: the name drawn.
    var shownTitle: String { title.stringValue }
    /// Self-test hook: drawn dimmed, "Off".
    var isOff: Bool { !offLabel.isHidden }
    /// How much of the icon and labels shows when off.
    private static let offAlpha: CGFloat = 0.45

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 700, height: 46))
        identifier = Self.identifier

        // Where `ResultCellView` puts its icon and title.
        icon.frame = NSRect(x: 22, y: 7, width: 32, height: 32)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        imageView = icon

        title.font = Theme.Font.rowTitle
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
        textField = title

        subtitle.font = Theme.Font.rowAccessory
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        addSubview(subtitle)

        offLabel.font = Theme.Font.rowAccessory
        offLabel.textColor = .secondaryLabelColor
        offLabel.isHidden = true
        offLabel.sizeToFit()
        addSubview(offLabel)
        layoutLabels()
    }

    func configure(title: String, oneLine: String, icon: NSImage, keys: [[String]], caps: [[KeycapView]], off: Bool = false) {
        self.title.stringValue = title
        subtitle.text = oneLine
        self.icon.image = icon
        offLabel.isHidden = !off
        for view in [self.icon, self.title, subtitle] as [NSView] { view.alphaValue = off ? Self.offAlpha : 1 }
        // Another row's keycaps may have moved here already: only ours go.
        for cap in ways.joined() where cap.superview === self { cap.removeFromSuperview() }
        ways = caps
        shownKeys = keys
        for cap in caps.joined() { addSubview(cap) }
        layoutLabels()
    }

    override func layout() {
        super.layout()
        layoutLabels()
    }

    /// Keycaps from the right edge leftward; the labels take what is left.
    private func layoutLabels() {
        var x = bounds.width - 24
        for (index, way) in ways.enumerated().reversed() {
            for cap in way.reversed() {
                x -= cap.frame.width
                cap.frame.origin = NSPoint(x: x, y: ((bounds.height - cap.frame.height) / 2).rounded())
                x -= Self.keySpacing
            }
            x += Self.keySpacing
            if index > 0 { x -= Self.waySpacing }
        }
        var end = ways.isEmpty ? bounds.width - 24 : x - 16
        if !offLabel.isHidden {
            end -= offLabel.frame.width
            offLabel.frame.origin = NSPoint(x: end, y: ((bounds.height - offLabel.frame.height) / 2).rounded())
            end -= 16
        }
        title.frame = NSRect(x: 66, y: 23, width: max(0, end - 66), height: 18)
        subtitle.frame = NSRect(x: 66, y: 6, width: max(0, end - 66), height: 16)
    }

    /// Keep label colors on selection: the soft capsule needs no inversion.
    override var backgroundStyle: NSView.BackgroundStyle {
        get { .normal }
        set {}
    }
}

/// A group's name in the Catalog ("Do"), drawn like the launcher's own
/// header above the list, with the same room around it.
final class CatalogHeaderView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("CatalogHeaderView")
    /// The launcher's header band: the list's rows start right under it.
    static let height: CGFloat = 34
    private let label = NSTextField(labelWithString: "")

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 700, height: Self.height))
        identifier = Self.identifier
        label.font = Theme.Font.sectionHeader
        label.textColor = .secondaryLabelColor
        // As the launcher's header: 24 pt in, 8 pt above the next row.
        label.frame = NSRect(x: 24, y: 8, width: 400, height: 16)
        addSubview(label)
        textField = label
    }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
}
