import CoreGraphics
import Foundation

/// A grid of numbered cells over part of the window, for "do it here" to
/// click a place no item names: a board, a map, a photo, a canvas
/// (`ComputerControl.pickSpot`, docs/click-what-you-see.md). The model
/// picks a cell's number among the cells, never a coordinate; code turns
/// the cell into a point. In screen points, top-left origin, as
/// Accessibility gives frames. Numbers, not letters and digits: "E4" would
/// read as a chess square or a spreadsheet cell.
public struct CanvasGrid: Equatable, Sendable {
    /// What the grid covers, in screen points.
    public let area: CGRect
    public let columns: Int
    public let rows: Int

    /// Cells on the longest side in the first, coarse pick: ~75 pt in a
    /// 900 pt window, a dozen tags a row the model can still read.
    public static let coarseSide = 12
    /// The fine pick: cells a side over the coarse cells around the first
    /// pick (`around`), each a twelfth of them: ~19 pt in a 900 pt window,
    /// under the smallest square of Chess's board (28 pt).
    public static let fineSide = 12
    /// The fine pick's close-up: this many coarse cells a side, the pick in
    /// the middle, so a pick one cell off still holds the thing.
    public static let fineSpan = 3

    public init(area: CGRect, columns: Int, rows: Int) {
        self.area = area
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    /// Square-ish cells over `area`, `side` of them on its longest side.
    public static func over(_ area: CGRect, side: Int = coarseSide) -> CanvasGrid {
        let longest = max(area.width, area.height, 1)
        let cell = longest / CGFloat(max(1, side))
        return CanvasGrid(area: area, columns: Int((area.width / cell).rounded()), rows: Int((area.height / cell).rounded()))
    }

    public var count: Int { columns * rows }

    /// The cells' numbers, 1 to `count`, row by row from the top left.
    public var numbers: ClosedRange<Int> { 1...count }

    public func row(of number: Int) -> Int { (number - 1) / columns + 1 }
    public func column(of number: Int) -> Int { (number - 1) % columns + 1 }

    /// Cell `number` on screen; nil outside the grid.
    public func rect(_ number: Int) -> CGRect? {
        guard numbers.contains(number) else { return nil }
        let width = area.width / CGFloat(columns), height = area.height / CGFloat(rows)
        return CGRect(x: area.minX + CGFloat(column(of: number) - 1) * width, y: area.minY + CGFloat(row(of: number) - 1) * height,
                      width: width, height: height)
    }

    /// Where a click on cell `number` goes: its middle.
    public func point(_ number: Int) -> CGPoint? {
        rect(number).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    /// The cell holding `point`; nil outside the grid.
    public func number(at point: CGPoint) -> Int? {
        guard area.contains(point) else { return nil }
        let column = min(columns, Int((point.x - area.minX) / (area.width / CGFloat(columns))) + 1)
        let row = min(rows, Int((point.y - area.minY) / (area.height / CGFloat(rows))) + 1)
        return (row - 1) * columns + column
    }

    /// "cell 37: row 4 of 9, column 1 of 12": how the model reads one
    /// option.
    public func describe(_ number: Int) -> String {
        "cell \(number): row \(row(of: number)) of \(rows), column \(column(of: number)) of \(columns)"
    }

    /// The close-up for the fine pick: `span` cells a side around cell
    /// `number` (it in the middle), moved inside `bounds` rather than cut.
    public func around(_ number: Int, span: Int = fineSpan, within bounds: CGRect? = nil) -> CGRect? {
        guard let cell = rect(number) else { return nil }
        let size = CGSize(width: cell.width * CGFloat(span), height: cell.height * CGFloat(span))
        var close = CGRect(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height)
        let limit = bounds ?? area
        if close.width <= limit.width {
            close.origin.x = min(max(close.minX, limit.minX), limit.maxX - close.width)
        }
        if close.height <= limit.height {
            close.origin.y = min(max(close.minY, limit.minY), limit.maxY - close.height)
        }
        return close.intersection(limit)
    }
}
