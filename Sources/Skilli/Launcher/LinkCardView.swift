import AppKit
import SkilliCore

/// A copied link's social card in the clipboard history's preview: the
/// page's picture across the top, its icon and site, its title and
/// description (`LinkPreview`). Before the page is read, without previews,
/// or when it says nothing: the site's name large and the link itself,
/// quietly (no error, no spinner).
@MainActor
final class LinkCardView: NSView {
    private enum Style {
        /// The site and the link.
        case plain
        /// The page's words, no picture.
        case words
        /// The picture, then the words.
        case picture
    }

    private let picture = FillImageView()
    private let badge = SoftSquare()
    private let icon = NSImageView()
    private let site = NSTextField(labelWithString: "")
    private let domain = NSTextField(labelWithString: "")
    private let title = NSTextField(wrappingLabelWithString: "")
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let address = NSTextField(wrappingLabelWithString: "")
    private var style = Style.plain

    /// Self-test hooks.
    private(set) var shownTitle = ""
    private(set) var hasPicture = false
    private(set) var hasIcon = false

    private static let radius: CGFloat = 12
    private static var globes: [CGFloat: NSImage] = [:]

    /// The globe for a site without an icon, made once a size.
    private static func globe(_ size: CGFloat, weight: NSFont.Weight) -> NSImage? {
        if let made = globes[size] { return made }
        let made = Theme.symbol("globe", pointSize: size, weight: weight)
        globes[size] = made
        return made
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(picture)
        addSubview(badge)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 4
        icon.layer?.cornerCurve = .continuous
        icon.layer?.masksToBounds = true
        addSubview(icon)
        for label in [site, domain] {
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        for label in [title, summary, address] {
            label.lineBreakMode = .byWordWrapping
            label.cell?.truncatesLastVisibleLine = true
            addSubview(label)
        }
        address.lineBreakMode = .byCharWrapping
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The link, and what its page said when it was read.
    func show(url: URL, preview: LinkPreview?, picture image: NSImage?, icon favicon: NSImage?) {
        let host = LinkPreviews.domain(of: url)
        let words = preview.flatMap { $0.isEmpty ? nil : $0 }
        style = image != nil ? .picture : words?.title != nil || words?.summary != nil ? .words : .plain
        picture.image = image
        icon.image = favicon
        hasPicture = image != nil
        hasIcon = favicon != nil
        let siteName = words?.siteName.flatMap { $0.isEmpty ? nil : $0 } ?? host
        switch style {
        case .plain:
            site.stringValue = host
            site.font = .systemFont(ofSize: 18, weight: .semibold)
            site.textColor = .labelColor
            site.alignment = .center
            address.stringValue = url.absoluteString
            address.font = .systemFont(ofSize: 12)
            address.textColor = .secondaryLabelColor
            address.alignment = .center
            address.maximumNumberOfLines = 3
            if favicon == nil {
                icon.image = Self.globe(26, weight: .light)
                icon.contentTintColor = .tertiaryLabelColor
            } else {
                icon.contentTintColor = nil
            }
            shownTitle = host
        case .words, .picture:
            site.stringValue = siteName
            site.font = .systemFont(ofSize: style == .picture ? 11.5 : 13, weight: .semibold)
            site.textColor = style == .picture ? .secondaryLabelColor : .labelColor
            site.alignment = .left
            domain.stringValue = siteName == host ? "" : host
            domain.font = .systemFont(ofSize: 11.5)
            domain.textColor = .secondaryLabelColor
            title.stringValue = words?.title ?? host
            title.font = .systemFont(ofSize: style == .picture ? 14 : 17, weight: .semibold)
            title.textColor = .labelColor
            title.maximumNumberOfLines = style == .picture ? 2 : 3
            summary.stringValue = words?.summary ?? ""
            summary.font = .systemFont(ofSize: style == .picture ? 12 : 13)
            summary.textColor = .secondaryLabelColor
            address.stringValue = url.absoluteString
            address.font = .systemFont(ofSize: 11)
            address.textColor = .tertiaryLabelColor
            address.alignment = .left
            address.maximumNumberOfLines = 1
            address.lineBreakMode = .byTruncatingMiddle
            if favicon == nil {
                icon.image = Self.globe(style == .picture ? 12 : 18, weight: .regular)
                icon.contentTintColor = .secondaryLabelColor
            } else {
                icon.contentTintColor = nil
            }
            shownTitle = title.stringValue
        }
        if style == .plain { address.lineBreakMode = .byCharWrapping }
        picture.isHidden = style != .picture
        badge.isHidden = style != .plain
        domain.isHidden = style != .words || domain.stringValue.isEmpty
        title.isHidden = style == .plain
        summary.isHidden = style == .plain || summary.stringValue.isEmpty
        address.isHidden = style == .picture
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        switch style {
        case .plain:
            let text = width - 48
            let addressHeight = height(of: address, width: text, lines: 3)
            let total: CGFloat = 56 + 14 + 22 + 6 + addressHeight
            var y = ((bounds.height - total) / 2).rounded()
            address.frame = NSRect(x: 24, y: y, width: text, height: addressHeight)
            y += addressHeight + 6
            site.frame = NSRect(x: 24, y: y, width: text, height: 22)
            y += 22 + 14
            badge.frame = NSRect(x: (width - 56) / 2, y: y, width: 56, height: 56)
            let side: CGFloat = 30
            icon.frame = NSRect(x: badge.frame.midX - side / 2, y: badge.frame.midY - side / 2, width: side, height: side)
            icon.layer?.cornerRadius = hasIcon ? 7 : 0

        case .words:
            let inset: CGFloat = 18
            let text = width - inset * 2
            var y = bounds.height - inset
            // Icon and site, the domain under the site when they differ.
            icon.frame = NSRect(x: inset, y: y - 32, width: 32, height: 32)
            icon.layer?.cornerRadius = hasIcon ? 7 : 0
            if domain.isHidden {
                site.frame = NSRect(x: inset + 42, y: y - 24, width: text - 42, height: 18)
            } else {
                site.frame = NSRect(x: inset + 42, y: y - 16, width: text - 42, height: 17)
                domain.frame = NSRect(x: inset + 42, y: y - 32, width: text - 42, height: 15)
            }
            y -= 32 + 16
            let titleHeight = height(of: title, width: text, lines: 3)
            title.frame = NSRect(x: inset, y: y - titleHeight, width: text, height: titleHeight)
            y -= titleHeight + 6
            address.frame = NSRect(x: inset, y: 14, width: text, height: 14)
            // The description takes what is left above the link.
            let room = y - address.frame.maxY - 12
            let lineHeight = ceil((summary.font?.boundingRectForFont.height ?? 16))
            let lines = max(0, min(8, Int(room / lineHeight)))
            summary.isHidden = summary.stringValue.isEmpty || lines == 0
            let summaryHeight = height(of: summary, width: text, lines: lines)
            summary.frame = NSRect(x: inset, y: y - summaryHeight, width: text, height: summaryHeight)

        case .picture:
            let inset: CGFloat = 14
            let text = width - inset * 2
            let titleHeight = height(of: title, width: text, lines: 2)
            let lineHeight = ceil((summary.font?.boundingRectForFont.height ?? 15))
            // The picture as wide as the card, at the Open Graph shape when
            // there is room, never lower than 110 pt.
            let words: CGFloat = 12 + 16 + 6 + titleHeight + 12
            let natural = (width / 1.91).rounded()
            var pictureHeight = min(natural, bounds.height - words - (summary.stringValue.isEmpty ? 0 : 4 + lineHeight * 2))
            pictureHeight = max(110, pictureHeight)
            picture.frame = NSRect(x: 0, y: bounds.height - pictureHeight, width: width, height: pictureHeight)
            var y = picture.frame.minY - 12
            icon.frame = NSRect(x: inset, y: y - 16, width: 16, height: 16)
            icon.layer?.cornerRadius = hasIcon ? 4 : 0
            site.frame = NSRect(x: inset + 22, y: y - 16, width: text - 22, height: 16)
            y -= 16 + 6
            title.frame = NSRect(x: inset, y: y - titleHeight, width: text, height: titleHeight)
            y -= titleHeight + 4
            let lines = max(0, min(4, Int((y - 10) / lineHeight)))
            summary.isHidden = summary.stringValue.isEmpty || lines == 0
            let summaryHeight = height(of: summary, width: text, lines: lines)
            summary.frame = NSRect(x: inset, y: y - summaryHeight, width: text, height: summaryHeight)
        }
    }

    /// The label's height at `width`, `lines` at most.
    private func height(of label: NSTextField, width: CGFloat, lines: Int) -> CGFloat {
        guard lines > 0, !label.stringValue.isEmpty else { return 0 }
        label.maximumNumberOfLines = lines
        return ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1_000)).height ?? 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.radius, yRadius: Self.radius).fill()
    }
}

/// A picture filling its frame (cropped to keep its shape), its top
/// corners rounded like the card's.
private final class FillImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let radius: CGFloat = 12
        let path = NSBezierPath()
        let rect = bounds
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: 90, endAngle: 180)
        path.close()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        // Cropped around its middle, as the sites that show these cards do.
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = NSPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
        image.draw(in: NSRect(origin: origin, size: drawn), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        // Where the picture meets the words.
        Theme.hairline.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
    }
}

/// The soft square behind a site's icon.
private final class SoftSquare: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }
}
