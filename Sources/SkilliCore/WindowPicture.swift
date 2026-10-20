import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One picture of the window "do it here" acts in, for Jev (TypeSafe's
/// images): a JPEG of that window only, its longest side two pixels a
/// point between 512 and 1024 (a Retina capture's own size up to 1024),
/// padded on white like `JevImages.jpeg` so each side
/// is at least 280 (TypeSafe takes 256 to 1568 px a side and 78,400 px or
/// more). It can outline items without words with their id
/// (`ComputerControl.marksInPicture`); measured, Jev told icons apart
/// better without, so the window goes as it is.
public enum WindowPicture {
    public static let smallest = 512
    public static let largest = 1024
    /// 280 × 280 = 78,400: TypeSafe's least total.
    public static let leastSide = 280
    /// Marks drawn at most: more would hide the window.
    public static let markLimit = 40

    /// An item outlined in the picture: its id and where it is on screen
    /// (points, top-left origin, as Accessibility gives it).
    public struct Mark: Equatable, Sendable {
        public let id: String
        public let frame: CGRect

        public init(id: String, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    /// Where the window goes in the picture: drawn at `drawn` from
    /// `origin` (top-left), on a white `canvas`.
    public struct Layout: Equatable, Sendable {
        public let canvas: CGSize
        public let drawn: CGSize
        public let origin: CGPoint
    }

    /// The longest side for a window `points` big: 1024, the most detail
    /// for small icons (~2,000 tokens more than words alone), 512 at
    /// least; a smaller capture is never scaled up (`layout`).
    public static func longest(forPoints points: CGSize) -> Int {
        min(largest, max(smallest, Int((max(points.width, points.height) * 2).rounded())))
    }

    /// An image `pixels` big, its longest side brought down to `longest`
    /// (up too with `upscale`: a close-up), centered on a canvas padded to
    /// `leastSide` a side.
    public static func layout(pixels: CGSize, longest: Int, upscale: Bool = false) -> Layout {
        let fit = CGFloat(longest) / max(pixels.width, pixels.height, 1)
        let scale = upscale ? fit : min(1, fit)
        let drawn = CGSize(width: max(1, (pixels.width * scale).rounded()), height: max(1, (pixels.height * scale).rounded()))
        let canvas = CGSize(width: max(CGFloat(leastSide), drawn.width), height: max(CGFloat(leastSide), drawn.height))
        return Layout(canvas: canvas, drawn: drawn,
                      origin: CGPoint(x: ((canvas.width - drawn.width) / 2).rounded(.down), y: ((canvas.height - drawn.height) / 2).rounded(.down)))
    }

    /// The items to outline: those without words inside the window, in
    /// reading order, `markLimit` at most.
    public static func marks(_ candidates: [ScreenItem], window: CGRect) -> [Mark] {
        candidates.compactMap { item -> Mark? in
            guard item.isWordless, let frame = item.frame, window.intersects(frame) else { return nil }
            return Mark(id: item.id, frame: frame)
        }.prefix(markLimit).map { $0 }
    }

    /// `frame` (screen points) in the picture's pixels, top-left origin.
    public static func place(_ frame: CGRect, window: CGRect, layout: Layout) -> CGRect {
        guard window.width > 0, window.height > 0 else { return .zero }
        let sx = layout.drawn.width / window.width, sy = layout.drawn.height / window.height
        return CGRect(x: layout.origin.x + (frame.minX - window.minX) * sx, y: layout.origin.y + (frame.minY - window.minY) * sy,
                      width: frame.width * sx, height: frame.height * sy)
    }

    /// A box Jev found (TypeSafe's Box: edges as fractions of the picture,
    /// top-left origin) back on screen, in points: the inverse of `place`.
    public static func unplace(_ fractions: CGRect, window: CGRect, layout: Layout) -> CGRect {
        guard layout.drawn.width > 0, layout.drawn.height > 0 else { return .zero }
        let sx = window.width / layout.drawn.width, sy = window.height / layout.drawn.height
        return CGRect(x: window.minX + (fractions.minX * layout.canvas.width - layout.origin.x) * sx,
                      y: window.minY + (fractions.minY * layout.canvas.height - layout.origin.y) * sy,
                      width: fractions.width * layout.canvas.width * sx, height: fractions.height * layout.canvas.height * sy)
    }

    /// The window's capture (`image`, any scale) as the JPEG Jev gets:
    /// `window` is where it is on screen, in points; `marks` are outlined
    /// with their id; `grid`'s cells numbered over it (a spot to click).
    public static func jpeg(_ image: CGImage, window: CGRect, marks: [Mark] = [], grid: CanvasGrid? = nil, longest: Int? = nil,
                            quality: Double = 0.82) -> Data? {
        let layout = layout(pixels: CGSize(width: image.width, height: image.height), longest: longest ?? self.longest(forPoints: window.size))
        return render(image, window: window, layout: layout, marks: marks, grid: grid, quality: quality)
    }

    /// A close-up for the second look: `area` (screen points) cut from
    /// the window's capture, its longest side brought to `longest` (up or
    /// down: the capture's own pixels, never the first JPEG's), `grid`'s
    /// cells numbered over it if any. `shown` is what was cut, in points
    /// (`area` within the window). Nil when `area` is outside the window.
    public static func closeUp(_ image: CGImage, window: CGRect, area: CGRect, grid: CanvasGrid? = nil, longest: Int = closeUpSide,
                               quality: Double = 0.85) -> (data: Data, layout: Layout, shown: CGRect)? {
        guard window.width > 0, window.height > 0 else { return nil }
        let scaleX = CGFloat(image.width) / window.width, scaleY = CGFloat(image.height) / window.height
        let pixels = CGRect(x: (area.minX - window.minX) * scaleX, y: (area.minY - window.minY) * scaleY,
                            width: area.width * scaleX, height: area.height * scaleY).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1, let cut = image.cropping(to: pixels) else { return nil }
        // What was cut, back in points: the grid is drawn over that.
        let shown = CGRect(x: window.minX + pixels.minX / scaleX, y: window.minY + pixels.minY / scaleY,
                           width: pixels.width / scaleX, height: pixels.height / scaleY)
        let layout = layout(pixels: CGSize(width: cut.width, height: cut.height), longest: longest, upscale: true)
        return render(cut, window: shown, layout: layout, marks: [], grid: grid, quality: quality).map { ($0, layout, shown) }
    }

    /// The close-up's longest side: cells of ~64 px at 12 a side.
    public static let closeUpSide = 768

    private static func render(_ image: CGImage, window: CGRect, layout: Layout, marks: [Mark], grid: CanvasGrid?, quality: Double) -> Data? {
        let width = Int(layout.canvas.width), height = Int(layout.canvas.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // Top-left origin, as the frames are given.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: layout.canvas))
        context.interpolationQuality = .high
        // CGContext draws images upright in its own space: flip back for it.
        context.saveGState()
        context.translateBy(x: layout.origin.x, y: layout.origin.y + layout.drawn.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: layout.drawn))
        context.restoreGState()
        for mark in marks {
            draw(mark, at: place(mark.frame, window: window, layout: layout), in: context, canvas: layout.canvas)
        }
        if let grid {
            draw(grid, window: window, layout: layout, in: context)
        }
        guard let picture = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, picture, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The color of the marks: a magenta no app's chrome uses.
    static let markColor = CGColor(srgbRed: 0.88, green: 0.0, blue: 0.55, alpha: 1)

    /// An outline around the item and its id on a tag at its top left,
    /// above it when there is room.
    private static func draw(_ mark: Mark, at rect: CGRect, in context: CGContext, canvas: CGSize) {
        context.setStrokeColor(markColor)
        context.setLineWidth(2)
        context.stroke(rect.insetBy(dx: -1, dy: -1))
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 13, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil)
        let text = NSAttributedString(string: mark.id, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(text)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let tag = CGSize(width: ceil(width) + 6, height: 17)
        var origin = CGPoint(x: rect.minX - 1, y: rect.minY - 1 - tag.height)
        if origin.y < 0 { origin.y = rect.minY + 1 }
        origin.x = min(max(0, origin.x), canvas.width - tag.width)
        context.setFillColor(markColor)
        context.fill(CGRect(origin: origin, size: tag))
        // Text is drawn upright: flip around its baseline.
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: origin.x + 3, y: origin.y + 13)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// The grid's lines, then each cell's number on a small tag in its top
    /// left corner: magenta like the marks, dark-edged so the lines read
    /// over light and dark alike.
    private static func draw(_ grid: CanvasGrid, window: CGRect, layout: Layout, in context: CGContext) {
        let area = place(grid.area, window: window, layout: layout)
        let cellWidth = area.width / CGFloat(grid.columns), cellHeight = area.height / CGFloat(grid.rows)
        context.saveGState()
        for (color, width) in [(CGColor(gray: 0, alpha: 0.45), CGFloat(2.5)), (markColor.copy(alpha: 0.9) ?? markColor, CGFloat(1))] {
            context.setStrokeColor(color)
            context.setLineWidth(width)
            for column in 0...grid.columns {
                let x = area.minX + CGFloat(column) * cellWidth
                context.move(to: CGPoint(x: x, y: area.minY))
                context.addLine(to: CGPoint(x: x, y: area.maxY))
            }
            for row in 0...grid.rows {
                let y = area.minY + CGFloat(row) * cellHeight
                context.move(to: CGPoint(x: area.minX, y: y))
                context.addLine(to: CGPoint(x: area.maxX, y: y))
            }
            context.strokePath()
        }
        // Tags small enough to leave most of each cell seen.
        let size: CGFloat = min(12, max(9, min(cellWidth, cellHeight) / 4.5))
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        for number in grid.numbers {
            let text = NSAttributedString(string: "\(number)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
            ])
            let line = CTLineCreateWithAttributedString(text)
            let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            let origin = CGPoint(x: area.minX + CGFloat(grid.column(of: number) - 1) * cellWidth + 1,
                                 y: area.minY + CGFloat(grid.row(of: number) - 1) * cellHeight + 1)
            let tag = CGRect(origin: origin, size: CGSize(width: ceil(textWidth) + 4, height: size + 3))
            context.setFillColor(markColor.copy(alpha: 0.85) ?? markColor)
            context.fill(tag)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: tag.minX + 2, y: tag.minY + size)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// TypeSafe's asset for an image: `{type, format, data_base64}`.
    public static func asset(_ data: Data, format: String = "jpeg") -> [String: String] {
        ["type": "image", "format": format, "data_base64": data.base64EncodedString()]
    }

    /// A reference no text can hold by chance.
    public static func reference() -> String {
        "window-\(UUID().uuidString.lowercased())"
    }
}
