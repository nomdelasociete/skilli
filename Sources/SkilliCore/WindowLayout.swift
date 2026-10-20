import CoreGraphics

/// Where the front window goes: halves, thirds, quarters, fill, center,
/// another display. Frames are in screen points with the origin at the top
/// left and y going down, like Accessibility's.
public enum WindowLayout: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case maximize
    case almostMaximize
    case center
    case nextDisplay
    case previousDisplay
    case restore

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .maximize: "Maximize Window"
        case .almostMaximize: "Almost Maximize"
        case .center: "Center Window"
        case .nextDisplay: "Move to Next Display"
        case .previousDisplay: "Move to Previous Display"
        case .restore: "Restore Window"
        }
    }

    /// Other words people type, in English and French.
    public var keywords: [String] {
        let window = ["window", "fenêtre"]
        let words: [String] = switch self {
        case .leftHalf: ["left", "gauche", "moitié gauche", "snap left"]
        case .rightHalf: ["right", "droite", "moitié droite", "snap right"]
        case .topHalf: ["top", "haut", "moitié haute"]
        case .bottomHalf: ["bottom", "bas", "moitié basse"]
        case .topLeft: ["quarter", "quart", "haut gauche", "coin"]
        case .topRight: ["quarter", "quart", "haut droite", "coin"]
        case .bottomLeft: ["quarter", "quart", "bas gauche", "coin"]
        case .bottomRight: ["quarter", "quart", "bas droite", "coin"]
        case .leftThird: ["third", "tiers", "tiers gauche"]
        case .centerThird: ["third", "tiers", "tiers central", "milieu"]
        case .rightThird: ["third", "tiers", "tiers droit"]
        case .leftTwoThirds: ["two thirds", "deux tiers", "gauche"]
        case .rightTwoThirds: ["two thirds", "deux tiers", "droite"]
        case .maximize: ["fill", "full", "zoom", "agrandir", "plein écran", "maximiser", "remplir"]
        case .almostMaximize: ["almost", "presque", "grand"]
        case .center: ["centrer", "milieu", "middle"]
        case .nextDisplay: ["screen", "monitor", "display", "écran suivant", "autre écran", "moniteur"]
        case .previousDisplay: ["screen", "monitor", "display", "écran précédent", "autre écran", "moniteur"]
        case .restore: ["undo", "back", "previous size", "restaurer", "taille d'avant", "annuler"]
        }
        return words + window
    }

    /// What it does, for the decision model choosing it from a request.
    public var description: String {
        switch self {
        case .leftHalf: "Put the front window on the left half of the screen"
        case .rightHalf: "Put the front window on the right half of the screen"
        case .topHalf: "Put the front window on the top half of the screen"
        case .bottomHalf: "Put the front window on the bottom half of the screen"
        case .topLeft: "Put the front window in the top left quarter of the screen"
        case .topRight: "Put the front window in the top right quarter of the screen"
        case .bottomLeft: "Put the front window in the bottom left quarter of the screen"
        case .bottomRight: "Put the front window in the bottom right quarter of the screen"
        case .leftThird: "Put the front window on the left third of the screen"
        case .centerThird: "Put the front window on the middle third of the screen"
        case .rightThird: "Put the front window on the right third of the screen"
        case .leftTwoThirds: "Put the front window on the left two thirds of the screen"
        case .rightTwoThirds: "Put the front window on the right two thirds of the screen"
        case .maximize: "Make the front window fill the screen (not macOS full screen)"
        case .almostMaximize: "Make the front window almost fill the screen, centered"
        case .center: "Center the front window on its screen, same size"
        case .nextDisplay: "Move the front window to the next display"
        case .previousDisplay: "Move the front window to the previous display"
        case .restore: "Put the front window back where it was before skil.li moved it"
        }
    }

    public var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .leftThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .rightThird: "rectangle.trailingthird.inset.filled"
        case .leftTwoThirds: "rectangle.split.2x1.fill"
        case .rightTwoThirds: "rectangle.split.2x1.fill"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .almostMaximize: "arrow.up.left.and.down.right.magnifyingglass"
        case .center: "rectangle.center.inset.filled"
        case .nextDisplay: "rectangle.portrait.and.arrow.right"
        case .previousDisplay: "rectangle.portrait.and.arrow.forward"
        case .restore: "arrow.uturn.backward"
        }
    }

    /// What applying a layout gives: a frame, or "back to the frame before".
    public enum Target: Equatable, Sendable {
        case frame(CGRect)
        case restore
    }

    /// The sizes a place goes through when it is pressed again soon
    /// (`WindowCycle`), as fractions of the screen's usable area: ½ → ⅔ → ⅓
    /// for the halves, ⅓ → ½ → ⅔ for the middle third; one size for the
    /// others. Empty for what keeps the size (Center) or needs more than
    /// one screen (the displays, Restore).
    public var sizes: [CGRect] {
        func f(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        switch self {
        case .leftHalf: return [f(0, 0, 1 / 2, 1), f(0, 0, 2 / 3, 1), f(0, 0, 1 / 3, 1)]
        case .rightHalf: return [f(1 / 2, 0, 1 / 2, 1), f(1 / 3, 0, 2 / 3, 1), f(2 / 3, 0, 1 / 3, 1)]
        case .topHalf: return [f(0, 0, 1, 1 / 2), f(0, 0, 1, 2 / 3), f(0, 0, 1, 1 / 3)]
        case .bottomHalf: return [f(0, 1 / 2, 1, 1 / 2), f(0, 1 / 3, 1, 2 / 3), f(0, 2 / 3, 1, 1 / 3)]
        case .topLeft: return [f(0, 0, 1 / 2, 1 / 2)]
        case .topRight: return [f(1 / 2, 0, 1 / 2, 1 / 2)]
        case .bottomLeft: return [f(0, 1 / 2, 1 / 2, 1 / 2)]
        case .bottomRight: return [f(1 / 2, 1 / 2, 1 / 2, 1 / 2)]
        case .leftThird: return [f(0, 0, 1 / 3, 1)]
        case .centerThird: return [f(1 / 3, 0, 1 / 3, 1), f(1 / 4, 0, 1 / 2, 1), f(1 / 6, 0, 2 / 3, 1)]
        case .rightThird: return [f(2 / 3, 0, 1 / 3, 1)]
        case .leftTwoThirds: return [f(0, 0, 2 / 3, 1)]
        case .rightTwoThirds: return [f(1 / 3, 0, 2 / 3, 1)]
        case .maximize: return [f(0, 0, 1, 1)]
        case .almostMaximize: return [f(0.05, 0.05, 0.9, 0.9)]
        case .center, .nextDisplay, .previousDisplay, .restore: return []
        }
    }

    /// Where size `size` of this place is on a screen whose usable area is
    /// `visible`, with `gap` points between windows and at the screen's
    /// edges (none for Almost Maximize: its margin is its own). Nil for
    /// what has no size of its own.
    public func frame(in visible: CGRect, gap: CGFloat = 0, size: Int = 0) -> CGRect? {
        let sizes = sizes
        guard !sizes.isEmpty else { return nil }
        return Self.place(sizes[min(max(size, 0), sizes.count - 1)], in: visible, gap: self == .almostMaximize ? 0 : gap)
    }

    /// `fraction` of `visible` (0…1 across and down), with `gap` points
    /// between windows and at the screen's edges: an edge on the screen's
    /// edge comes in by the whole gap, an edge inside by half of it, so two
    /// windows side by side have one gap between them. Edges are rounded
    /// to whole points: two halves never overlap.
    public static func place(_ fraction: CGRect, in visible: CGRect, gap: CGFloat = 0) -> CGRect {
        let v = visible
        var minX = v.minX + fraction.minX * v.width
        var maxX = v.minX + fraction.maxX * v.width
        var minY = v.minY + fraction.minY * v.height
        var maxY = v.minY + fraction.maxY * v.height
        if gap > 0 {
            minX += fraction.minX < 0.001 ? gap : gap / 2
            maxX -= fraction.maxX > 0.999 ? gap : gap / 2
            minY += fraction.minY < 0.001 ? gap : gap / 2
            maxY -= fraction.maxY > 0.999 ? gap : gap / 2
        }
        let x = minX.rounded(), y = minY.rounded()
        return CGRect(x: x, y: y, width: max(maxX.rounded() - x, 1), height: max(maxY.rounded() - y, 1))
    }

    /// Where a window now at `current`, on a screen whose usable area is
    /// `visible`, goes: size `size` of the place (`WindowCycle` says which
    /// when it is pressed again), `gap` points from the other windows and
    /// the edges. Maximize on a filled window restores it; Center keeps its
    /// size. The displays (and Restore) are the caller's: they need the
    /// other screens and the past.
    public func target(current: CGRect, visible: CGRect, gap: CGFloat = 0, size: Int = 0) -> Target? {
        switch self {
        case .maximize:
            guard let filled = frame(in: visible, gap: gap) else { return nil }
            return Self.matches(current, filled) ? .restore : .frame(filled)
        case .center:
            let area = gap > 0 ? visible.insetBy(dx: gap, dy: gap) : visible
            let size = CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
            return .frame(Self.rounded(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                              width: size.width, height: size.height)))
        case .nextDisplay, .previousDisplay, .restore:
            return nil
        default:
            return frame(in: visible, gap: gap, size: size).map(Target.frame)
        }
    }

    /// The same place on another display. A place ✦W puts windows in (any
    /// of its sizes, with the gap) stays exactly that place there, the gap
    /// unchanged; any other frame keeps its position and size in
    /// proportion.
    public static func moved(_ current: CGRect, from source: CGRect, to destination: CGRect, gap: CGFloat) -> CGRect {
        for layout in allCases {
            for size in layout.sizes.indices {
                if let here = layout.frame(in: source, gap: gap, size: size), matches(current, here, tolerance: 4),
                   let there = layout.frame(in: destination, gap: gap, size: size) {
                    return there
                }
            }
        }
        return moved(current, from: source, to: destination)
    }

    /// The same place on another display: position and size kept in
    /// proportion, so a left half stays a left half.
    public static func moved(_ current: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return current }
        let x = (current.minX - source.minX) / source.width
        let y = (current.minY - source.minY) / source.height
        let width = min(current.width / source.width, 1)
        let height = min(current.height / source.height, 1)
        var frame = CGRect(
            x: destination.minX + x * destination.width,
            y: destination.minY + y * destination.height,
            width: width * destination.width,
            height: height * destination.height
        )
        // Keep it on the destination.
        frame.origin.x = min(max(frame.minX, destination.minX), destination.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, destination.minY), destination.maxY - frame.height)
        return rounded(frame)
    }

    /// Apps round sizes to their own steps (a terminal's character grid):
    /// a few points off is still the same place.
    public static func matches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 12) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }
}

/// A place pressed again soon takes its next size: ✦W ← then ✦W ← within
/// `repeatWindow` goes ½ → ⅔ → ⅓ → ½. After a pause it starts over at the
/// first size, unless the window is there already: then the next one, so a
/// press never does nothing. Kept per window by whoever moves it.
public struct WindowCycle: Equatable, Sendable {
    /// How soon "again" is.
    public static let repeatWindow: Duration = .milliseconds(1_500)

    public var layout: WindowLayout
    /// The size it was put at (`WindowLayout.sizes`).
    public var size: Int
    /// Where the window ended, as read back (an app may round it).
    public var placed: CGRect
    public var at: ContinuousClock.Instant

    public init(layout: WindowLayout, size: Int, placed: CGRect, at: ContinuousClock.Instant) {
        self.layout = layout
        self.size = size
        self.placed = placed
        self.at = at
    }

    /// Which size of `layout` a press at `now` gives a window at `current`,
    /// after `last` (this window's last place).
    public static func size(of layout: WindowLayout, current: CGRect, visible: CGRect, gap: CGFloat,
                            last: WindowCycle?, now: ContinuousClock.Instant) -> Int {
        let count = layout.sizes.count
        guard count > 1 else { return 0 }
        // Again, soon, and still where it was put.
        if let last, last.layout == layout, now - last.at <= repeatWindow, WindowLayout.matches(current, last.placed) {
            return (last.size + 1) % count
        }
        if let first = layout.frame(in: visible, gap: gap, size: 0), WindowLayout.matches(current, first) { return 1 }
        return 0
    }
}
