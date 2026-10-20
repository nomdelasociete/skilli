import AppKit
import SkilliCore

/// "Which key" hints while a sequence is pending: a Liquid Glass card with
/// the typed prefix as keycaps, then one row per next key. Never takes focus
/// or mouse events, so keys keep flowing through the event tap.
@MainActor
final class LeaderOverlay {
    struct Row: Equatable {
        let keys: String
        let label: String
        let isGroup: Bool

        init(_ hint: BindingEngine<SkilliAction>.Hint) {
            keys = hint.chord.description
            label = hint.isGroup ? "\(hint.label) …" : hint.label
            isGroup = hint.isGroup
        }
    }

    private enum Layout {
        static let padding: CGFloat = 18
        static let headerHeight: CGFloat = 22
        static let headerGap: CGFloat = 12
        static let rowHeight: CGFloat = 28
        static let keyToLabel: CGFloat = 12
        static let prefixSpacing: CGFloat = 4
        static let titleGap: CGFloat = 6
        static let distanceFromBottom: CGFloat = 120
    }

    private lazy var panel = makePanel()
    private let content = NSView()
    private lazy var glass = Theme.glass(cornerRadius: Theme.Radius.overlay, content: content)

    func show(prefix: [Chord], title: String?, hints rows: [Row]) {
        content.subviews.forEach { $0.removeFromSuperview() }

        // Header: the keys typed so far, then the group's name.
        let prefixCaps = prefix.map { KeycapView($0.description) }
        let titleLabel = title.map { title -> NSTextField in
            let label = NSTextField(labelWithString: title)
            label.font = Theme.Font.sectionHeader
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            return label
        }
        let capsWidth = prefixCaps.reduce(0) { $0 + $1.frame.width } + CGFloat(max(prefixCaps.count - 1, 0)) * Layout.prefixSpacing
        let headerWidth = capsWidth + (titleLabel.map { Layout.titleGap + $0.frame.width } ?? 0)

        // Rows: keycap column, then labels.
        let keycaps = rows.map { KeycapView($0.keys) }
        let labels = rows.map { row -> NSTextField in
            let label = NSTextField(labelWithString: row.label)
            label.font = Theme.Font.overlayLabel
            label.textColor = row.isGroup ? .secondaryLabelColor : .labelColor
            label.sizeToFit()
            return label
        }
        let keyColumn = keycaps.map(\.frame.width).max() ?? 0
        let labelColumn = labels.map(\.frame.width).max() ?? 0

        let width = ceil(Layout.padding * 2 + max(headerWidth, keyColumn + Layout.keyToLabel + labelColumn))
        let height = Layout.padding * 2 + Layout.headerHeight + Layout.headerGap + CGFloat(rows.count) * Layout.rowHeight

        // Lay out top-down (AppKit origin is bottom-left).
        let headerY = height - Layout.padding - Layout.headerHeight
        var x = Layout.padding
        for cap in prefixCaps {
            cap.frame.origin = NSPoint(x: x, y: headerY + (Layout.headerHeight - cap.frame.height) / 2)
            content.addSubview(cap)
            x += cap.frame.width + Layout.prefixSpacing
        }
        if let titleLabel {
            titleLabel.frame.origin = NSPoint(
                x: x - Layout.prefixSpacing + Layout.titleGap,
                y: headerY + (Layout.headerHeight - titleLabel.frame.height) / 2
            )
            content.addSubview(titleLabel)
        }

        var rowTop = headerY - Layout.headerGap
        for (keycap, label) in zip(keycaps, labels) {
            let rowY = rowTop - Layout.rowHeight
            // Right-align keys in their column so labels share one edge.
            keycap.frame.origin = NSPoint(
                x: Layout.padding + keyColumn - keycap.frame.width,
                y: rowY + (Layout.rowHeight - keycap.frame.height) / 2
            )
            label.frame.origin = NSPoint(
                x: Layout.padding + keyColumn + Layout.keyToLabel,
                y: rowY + (Layout.rowHeight - label.frame.height) / 2
            )
            content.addSubview(keycap)
            content.addSubview(label)
            rowTop = rowY
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        // The window leaves `glassMargin` around the glass for its shadow.
        let margin = Theme.glassMargin
        glass.frame = NSRect(x: margin, y: margin, width: width, height: height)
        panel.setFrame(
            NSRect(
                x: visible.midX - width / 2 - margin,
                y: visible.minY + Layout.distanceFromBottom - margin,
                width: width + 2 * margin,
                height: height + 2 * margin
            ),
            display: false
        )
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    func applyGlassStyle(_ style: NSGlassEffectView.Style) {
        glass.style = style
    }

    /// Benchmark hook: the overlay's window, for window-server captures.
    var window: NSWindow { panel }

    /// Benchmark hook: PNG of the overlay as currently laid out.
    func snapshotPNG(appearance: NSAppearance? = nil) -> Data? {
        let previous = panel.appearance
        panel.appearance = appearance
        defer { panel.appearance = previous }
        glass.displayIfNeeded()
        return Snapshot.png(of: glass)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass draws its own edge and depth.
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let root = NSView()
        root.addSubview(glass)
        panel.contentView = root
        return panel
    }
}
