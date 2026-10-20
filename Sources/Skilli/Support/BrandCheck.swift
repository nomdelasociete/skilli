import AppKit

/// Benchmark hook: renders the brand assets the way macOS shows them, for
/// visual review (brand kit asks for 16/18/22 pt menu checks, light and dark).
@MainActor
enum BrandCheck {
    static func write(to directory: URL) {
        if let menu = menuBarSheet() {
            try? menu.write(to: directory.appendingPathComponent("brand-menubar.png"))
        }
        if let icon = appIconSheet() {
            try? icon.write(to: directory.appendingPathComponent("brand-appicon.png"))
        }
    }

    /// The template S at 16, 18 and 22 pt on a light and a dark menu bar,
    /// tinted like the system does (black on light, white on dark).
    private static func menuBarSheet() -> Data? {
        let sizes: [CGFloat] = [16, 18, 22]
        let rowHeight: CGFloat = 44
        let canvas = NSSize(width: 220, height: rowHeight * 2)
        return render(canvas) {
            for (row, dark) in [false, true].enumerated() {
                let y = canvas.height - rowHeight * CGFloat(row + 1)
                (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(x: 0, y: y, width: canvas.width, height: rowHeight).fill()
                var x: CGFloat = 20
                for size in sizes {
                    guard let mark = Theme.brandTemplate(size: size) else { continue }
                    let tinted = tint(mark, dark ? .white : .black)
                    tinted.draw(in: NSRect(x: x, y: y + (rowHeight - size) / 2, width: size, height: size))
                    x += size + 44
                }
            }
        }
    }

    /// The icon macOS hands out for this bundle (Finder, Dock, Settings).
    private static func appIconSheet() -> Data? {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let canvas = NSSize(width: 360, height: 200)
        return render(canvas) {
            NSColor(white: 0.95, alpha: 1).setFill()
            NSRect(origin: .zero, size: canvas).fill()
            icon.draw(in: NSRect(x: 20, y: 20, width: 160, height: 160))
            icon.draw(in: NSRect(x: 200, y: 100, width: 64, height: 64))
            icon.draw(in: NSRect(x: 280, y: 116, width: 32, height: 32))
            icon.draw(in: NSRect(x: 324, y: 124, width: 16, height: 16))
        }
    }

    private static func tint(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func render(_ size: NSSize, _ draw: () -> Void) -> Data? {
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
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
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
