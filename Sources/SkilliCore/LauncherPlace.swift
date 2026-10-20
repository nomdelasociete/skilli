import CoreGraphics

/// Where the user put the launcher's glass, the same on every screen: how
/// far across and down the free space around the glass it sits. 0 is flush
/// with the left or top edge, 1 with the right or bottom one, 0.5 centered,
/// so a centered launcher stays centered and one put in a corner stays in
/// it on a screen of another size. Frames are AppKit's: origin at the
/// bottom left, y going up.
public struct LauncherPlace: Codable, Equatable, Sendable {
    /// From flush left (0) to flush right (1).
    public var across: Double
    /// From flush with the visible top (0) to the bottom (1).
    public var down: Double

    public init(across: Double, down: Double) {
        self.across = across
        self.down = down
    }

    /// The place of a glass the user moved on that visible frame.
    public init(glass: CGRect, in visible: CGRect) {
        across = Self.fraction(glass.minX - visible.minX, of: visible.width - glass.width)
        down = Self.fraction(visible.maxY - glass.maxY, of: visible.height - glass.height)
    }

    /// Where it opens until it is moved: centered across, its top 18 % down
    /// the screen.
    public static func standard(size: CGSize, in visible: CGRect) -> LauncherPlace {
        LauncherPlace(across: 0.5, down: fraction(visible.height * 0.18, of: visible.height - size.height))
    }

    /// A glass of that size at this place, whole on the visible frame and
    /// on whole points. Too small a screen keeps its top left, where the
    /// search field is.
    public func frame(size: CGSize, in visible: CGRect) -> CGRect {
        let minX = visible.minX + max(visible.width - size.width, 0) * across
        let maxY = visible.maxY - max(visible.height - size.height, 0) * down
        return CGRect(x: minX.rounded(), y: (maxY - size.height).rounded(), width: size.width, height: size.height)
    }

    /// A glass dragged to `glass`, pulled onto the lines it comes within
    /// `reach` of: the screen's middles and the standard height. Where it
    /// goes, on whole points, and the lines it sits on.
    public static func snap(_ glass: CGRect, in visible: CGRect, reach: CGFloat = 8) -> (frame: CGRect, guides: [LauncherGuide]) {
        var frame = glass
        var guides: [LauncherGuide] = []
        let toCenterX = visible.midX - glass.midX
        if abs(toCenterX) <= reach {
            frame.origin.x += toCenterX
            guides.append(.centerX)
        }
        let standardTop = standard(size: glass.size, in: visible).frame(size: glass.size, in: visible).maxY
        let pulls: [(guide: LauncherGuide, by: CGFloat)] = [(.centerY, visible.midY - glass.midY), (.standardTop, standardTop - glass.maxY)]
        if let nearest = pulls.filter({ abs($0.by) <= reach }).min(by: { abs($0.by) < abs($1.by) }) {
            frame.origin.y += nearest.by
            guides.append(nearest.guide)
        }
        frame.origin = CGPoint(x: frame.minX.rounded(), y: frame.minY.rounded())
        return (frame, guides)
    }

    private static func fraction(_ offset: CGFloat, of free: CGFloat) -> Double {
        free > 0 ? min(max(offset / free, 0), 1) : 0
    }
}

/// A line the launcher's glass is pulled onto while it is dragged.
public enum LauncherGuide: Equatable, Sendable {
    /// The screen's vertical middle: the glass centered across.
    case centerX
    /// The screen's horizontal middle: the glass centered down.
    case centerY
    /// Where the launcher opens until it is moved: its top 18 % down.
    case standardTop
}
