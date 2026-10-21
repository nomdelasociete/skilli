import AppKit

/// Shared visual language: Liquid Glass surfaces, concentric radii, SF type.
///
/// Colors are semantic (label, secondaryLabel…) so they stay legible and
/// vibrant on glass in both light and dark appearances.
@MainActor
enum Theme {
    enum Radius {
        static let card: CGFloat = 26
        /// Selection inside a card: card radius minus its inset, so corners
        /// stay concentric.
        static let row: CGFloat = 14
        static let keycap: CGFloat = 6
        static let overlay: CGFloat = 24
    }

    @MainActor
    enum Font {
        static let search = NSFont.systemFont(ofSize: 22, weight: .regular)
        static let rowTitle = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let rowAccessory = NSFont.systemFont(ofSize: 12, weight: .regular)
        static let sectionHeader = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let hint = NSFont.systemFont(ofSize: 12, weight: .regular)
        static let keycap = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let overlayLabel = NSFont.systemFont(ofSize: 13, weight: .regular)
    }

    /// Soft fill for the selected row: a light wash of the accent color —
    /// skil.li's mint when the user's accent is Multicolor, their own
    /// accent otherwise — never the heavy solid highlight of classic lists.
    static var selectionFill: NSColor { .controlAccentColor.withAlphaComponent(0.20) }
    static var keycapFill: NSColor { .labelColor.withAlphaComponent(0.07) }
    static var keycapStroke: NSColor { .labelColor.withAlphaComponent(0.16) }
    static var hairline: NSColor { .labelColor.withAlphaComponent(0.08) }

    /// The S mark from the brand kit as a template image (menu bar, launcher).
    static func brandTemplate(size: CGFloat) -> NSImage? {
        guard let source = NSImage(named: "MenuBarIcon")?.copy() as? NSImage else { return nil }
        source.size = NSSize(width: size, height: size)
        source.isTemplate = true
        source.accessibilityDescription = "skil.li"
        return source
    }

    /// The Halo menthe composition, for app-icon-like tiles.
    static var brandMark: NSImage? { NSImage(named: "BrandMark") }

    /// The glass S alone on a transparent background (the launcher's
    /// search bar).
    static var brandGlass: NSImage? { NSImage(named: "BrandGlass") }

    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    /// Clear space between glass and the edge of its window. Liquid Glass
    /// draws a soft shadow past its shape; a window cut to the shape clips
    /// that shadow into square corners and dark bands.
    nonisolated static let glassMargin: CGFloat = 40

    /// A glass surface whose content view fills it.
    static func glass(cornerRadius: CGFloat, content: NSView) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: content.frame)
        glass.cornerRadius = cornerRadius
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        glass.contentView = content
        return glass
    }
}

/// A key drawn like a keyboard keycap: rounded, hairline border, soft fill.
final class KeycapView: NSView {
    private let label: NSTextField
    private static let height: CGFloat = 20
    private static let horizontalPadding: CGFloat = 6

    init(_ text: String) {
        label = NSTextField(labelWithString: text)
        label.font = Theme.Font.keycap
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        super.init(frame: NSRect(x: 0, y: 0, width: Self.height, height: Self.height))
        fit()
        addSubview(label)
    }

    /// Its text; set, the cap takes the new text's width (a row's keycap
    /// reused for another row).
    var text: String {
        get { label.stringValue }
        set {
            guard newValue != label.stringValue else { return }
            label.stringValue = newValue
            fit()
            needsDisplay = true
        }
    }

    private func fit() {
        label.sizeToFit()
        let width = max(Self.height + 2, ceil(label.frame.width) + Self.horizontalPadding * 2)
        frame.size = NSSize(width: width, height: Self.height)
        label.frame = NSRect(
            x: 0,
            y: (Self.height - label.frame.height) / 2,
            width: width,
            height: label.frame.height
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.Radius.keycap, yRadius: Theme.Radius.keycap)
        Theme.keycapFill.setFill()
        path.fill()
        Theme.keycapStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Right-aligned row of "Label [key]" hints, e.g. "Open ↩   Close esc".
final class HintBar: NSView {
    private static let spacing: CGFloat = 18
    private static let labelToKey: CGFloat = 6
    private var builtShape: [String] = []
    /// Each set of hints built once: the launcher and the card switch
    /// between a few as the user types.
    private var built: [[String]: [NSView]] = [:]

    /// The hints shown.
    private(set) var shown: [(label: String, key: String)] = []

    func setHints(_ hints: [(label: String, key: String)]) {
        shown = hints
        // Laid out again on every chunk and key: changed only when they change.
        let shape = hints.map { "\($0.label)\u{1}\($0.key)" } + ["\(bounds.width)"]
        guard shape != builtShape else { return }
        builtShape = shape
        if let views = built[shape] {
            subviews = views
            return
        }
        var views: [NSView] = []
        var x = bounds.width
        for hint in hints.reversed() {
            let key = KeycapView(hint.key)
            x -= key.frame.width
            key.frame.origin = NSPoint(x: x, y: (bounds.height - key.frame.height) / 2)
            views.append(key)

            let label = NSTextField(labelWithString: hint.label)
            label.font = Theme.Font.hint
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            x -= Self.labelToKey + label.frame.width
            label.frame.origin = NSPoint(x: x, y: (bounds.height - label.frame.height) / 2)
            views.append(label)

            x -= Self.spacing
        }
        subviews = views
        built[shape] = views
    }
}
