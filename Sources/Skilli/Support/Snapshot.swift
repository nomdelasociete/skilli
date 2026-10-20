import AppKit

/// Renders a view hierarchy to PNG for the benchmark report, so layout can be
/// reviewed without screen recording.
///
/// Liquid Glass is composited by the window server and does not render off
/// screen, and off-screen captures always get an opaque white background. So
/// each glass surface is drawn as a light rounded card over a simulated
/// wallpaper: right for judging layout, type and spacing in the light
/// appearance; the glass material and dark appearance need a real screen.
@MainActor
enum Snapshot {
    private static let margin: CGFloat = 40

    static func png(of view: NSView) -> Data? {
        let bounds = view.bounds
        let canvasSize = NSSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2)
        let scale = view.window?.backingScaleFactor ?? 2
        guard let canvas = bitmap(size: canvasSize, scale: scale),
              let context = NSGraphicsContext(bitmapImageRep: canvas)
        else { return nil }

        let surfaces = glassViews(in: view).compactMap { glass -> (NSRect, CGFloat, NSBitmapImageRep)? in
            guard let content = glass.contentView,
                  let rendered = content.bitmapImageRepForCachingDisplay(in: content.bounds)
            else { return nil }
            content.cacheDisplay(in: content.bounds, to: rendered)
            var rect = glass.convert(glass.bounds, to: view)
            rect.origin.x += margin
            rect.origin.y += margin
            return (rect, glass.cornerRadius, rendered)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSGradient(colors: [
            NSColor(red: 0.62, green: 0.76, blue: 0.95, alpha: 1),
            NSColor(red: 0.95, green: 0.78, blue: 0.70, alpha: 1)
        ])?.draw(in: NSRect(origin: .zero, size: canvasSize), angle: -60)
        for (rect, radius, rendered) in surfaces {
            let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            rendered.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 0, alpha: 0.08).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        return canvas.representation(using: .png, properties: [:])
    }

    private static func bitmap(size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        bitmap?.size = size
        return bitmap
    }

    private static func glassViews(in view: NSView) -> [NSGlassEffectView] {
        var found: [NSGlassEffectView] = []
        if let glass = view as? NSGlassEffectView { found.append(glass) }
        for subview in view.subviews {
            found += glassViews(in: subview)
        }
        if let container = view as? NSGlassEffectContainerView,
           let content = container.contentView, !content.isDescendant(of: container) {
            found += glassViews(in: content)
        }
        return found
    }
}
