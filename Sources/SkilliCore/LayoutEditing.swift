import CoreGraphics

/// Screen points ⇄ a picture of the displays fitted in a view: the layout
/// editor's canvas, where windows are dragged and resized.
public struct LayoutCanvasMap: Equatable, Sendable {
    /// Every display together, in screen points.
    public let bounds: CGRect
    /// Canvas points per screen point.
    public let scale: CGFloat
    /// Where `bounds`' top left corner is drawn.
    public let origin: CGPoint

    public init(displays: [CGRect], size: CGSize, padding: CGFloat) {
        let union = displays.reduce(CGRect.null) { $0.union($1) }
        bounds = union.isNull ? .zero : union
        let width = max(size.width - 2 * padding, 1)
        let height = max(size.height - 2 * padding, 1)
        scale = bounds.width > 0 && bounds.height > 0 ? min(width / bounds.width, height / bounds.height) : 1
        origin = CGPoint(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
    }

    /// Where a screen rect is drawn.
    public func canvas(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + (rect.minX - bounds.minX) * scale, y: origin.y + (rect.minY - bounds.minY) * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    /// A drag on the canvas, in screen points.
    public func screen(_ translation: CGSize) -> CGSize {
        CGSize(width: translation.width / scale, height: translation.height / scale)
    }
}

/// Windows dragged in the layout editor stick to a display's edges,
/// quarters, thirds and middle, the places ✦W puts them; ⌥ places them
/// freely. Frames are top-left, like Accessibility's.
public enum LayoutSnap {
    public struct Edges: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let left = Edges(rawValue: 1)
        public static let right = Edges(rawValue: 2)
        public static let top = Edges(rawValue: 4)
        public static let bottom = Edges(rawValue: 8)
    }

    /// The lines on a display, as fractions of its usable area.
    public static let fractions: [CGFloat] = [0, 1 / 4, 1 / 3, 1 / 2, 2 / 3, 3 / 4, 1]

    /// Where a window's leading (left, top) and trailing (right, bottom)
    /// edges stick across `length` from `start`, `gap` points off each line
    /// as ✦W leaves it (`WindowLayout.place`): the whole gap at the screen's
    /// edges, half of it inside.
    static func lines(from start: CGFloat, length: CGFloat, gap: CGFloat) -> (leading: [CGFloat], trailing: [CGFloat]) {
        let leading = fractions.dropLast().map { start + $0 * length + ($0 == 0 ? gap : gap / 2) }
        let trailing = fractions.dropFirst().map { start + $0 * length - ($0 == 1 ? gap : gap / 2) }
        return (Array(leading), Array(trailing))
    }

    /// Moved, size kept: whichever edge is nearest a line within
    /// `tolerance` lands on it, across and down separately; with `gap`,
    /// where ✦W would leave that edge.
    public static func move(_ frame: CGRect, in visible: CGRect, tolerance: CGFloat, gap: CGFloat = 0) -> CGRect {
        let xs = lines(from: visible.minX, length: visible.width, gap: gap)
        let ys = lines(from: visible.minY, length: visible.height, gap: gap)
        let dx = nearest([(frame.minX, xs.leading), (frame.maxX, xs.trailing)], within: tolerance) ?? 0
        let dy = nearest([(frame.minY, ys.leading), (frame.maxY, ys.trailing)], within: tolerance) ?? 0
        return WindowLayout.rounded(frame.offsetBy(dx: dx, dy: dy))
    }

    /// `frame` with the dragged `edges` moved by `delta`, never smaller than
    /// `minimum` (the edge stops instead).
    public static func resized(_ frame: CGRect, by delta: CGSize, edges: Edges, minimum: CGSize) -> CGRect {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        if edges.contains(.left) { minX = min(minX + delta.width, maxX - minimum.width) }
        if edges.contains(.right) { maxX = max(maxX + delta.width, minX + minimum.width) }
        if edges.contains(.top) { minY = min(minY + delta.height, maxY - minimum.height) }
        if edges.contains(.bottom) { maxY = max(maxY + delta.height, minY + minimum.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Resized: each dragged edge lands on a line within `tolerance`, the
    /// others stay; never smaller than `minimum`.
    public static func resize(_ frame: CGRect, edges: Edges, in visible: CGRect, tolerance: CGFloat, minimum: CGSize,
                              gap: CGFloat = 0) -> CGRect {
        let xs = lines(from: visible.minX, length: visible.width, gap: gap)
        let ys = lines(from: visible.minY, length: visible.height, gap: gap)
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        if edges.contains(.left), let d = nearest([(minX, xs.leading)], within: tolerance), maxX - (minX + d) >= minimum.width { minX += d }
        if edges.contains(.right), let d = nearest([(maxX, xs.trailing)], within: tolerance), maxX + d - minX >= minimum.width { maxX += d }
        if edges.contains(.top), let d = nearest([(minY, ys.leading)], within: tolerance), maxY - (minY + d) >= minimum.height { minY += d }
        if edges.contains(.bottom), let d = nearest([(maxY, ys.trailing)], within: tolerance), maxY + d - minY >= minimum.height { maxY += d }
        return WindowLayout.rounded(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    /// The smallest shift that puts an edge on one of its lines.
    private static func nearest(_ edges: [(edge: CGFloat, lines: [CGFloat])], within tolerance: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for (edge, lines) in edges {
            for line in lines where abs(line - edge) <= tolerance && abs(line - edge) < abs(best ?? .infinity) {
                best = line - edge
            }
        }
        return best
    }
}

extension LayoutSnap {
    /// Where a window added by hand goes on a display: the first half, then
    /// quarter, that no window there covers much; else the middle, two
    /// thirds of the display. `gap` points from the edges and the others,
    /// as ✦W leaves them.
    public static func freeSpot(among windows: [CGRect], in visible: CGRect, gap: CGFloat = 0) -> CGRect {
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            WindowLayout.place(CGRect(x: x, y: y, width: w, height: h), in: visible, gap: gap)
        }
        let spots = [rect(0, 0, 1 / 2, 1), rect(1 / 2, 0, 1 / 2, 1),
                     rect(0, 0, 1 / 2, 1 / 2), rect(1 / 2, 0, 1 / 2, 1 / 2), rect(0, 1 / 2, 1 / 2, 1 / 2), rect(1 / 2, 1 / 2, 1 / 2, 1 / 2)]
        for spot in spots {
            let covered = windows.map { window -> CGFloat in
                let overlap = window.intersection(spot)
                return overlap.isNull ? 0 : overlap.width * overlap.height
            }.reduce(0, +)
            if covered < spot.width * spot.height / 4 { return spot }
        }
        return rect(1 / 6, 1 / 6, 2 / 3, 2 / 3)
    }
}
