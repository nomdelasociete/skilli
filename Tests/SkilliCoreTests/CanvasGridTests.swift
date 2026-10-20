import CoreGraphics
import Foundation
import ImageIO
@testable import SkilliCore
import XCTest

final class CanvasGridTests: XCTestCase {
    /// Chess's window on the mini: 907 × 712 pt at (5, 368).
    private let chess = CGRect(x: 5, y: 368, width: 907, height: 712)

    func testCoarseGridHasAboutTwelveSquareCellsOnTheLongestSide() {
        let grid = CanvasGrid.over(chess)
        XCTAssertEqual(grid.columns, 12)
        XCTAssertEqual(grid.rows, 9)
        XCTAssertEqual(grid.count, 108)
        // Under a decision question's 255 options, "none" included.
        XCTAssertLessThan(grid.count, 255)
        let cell = grid.rect(1)!
        XCTAssertEqual(cell.width, 907 / 12, accuracy: 0.01)
        XCTAssertEqual(cell.height, 712 / 9, accuracy: 0.01)
    }

    func testNumbersGoRowByRowFromTheTopLeft() {
        let grid = CanvasGrid(area: CGRect(x: 0, y: 0, width: 120, height: 90), columns: 4, rows: 3)
        XCTAssertEqual(grid.rect(1), CGRect(x: 0, y: 0, width: 30, height: 30))
        XCTAssertEqual(grid.rect(4), CGRect(x: 90, y: 0, width: 30, height: 30))
        XCTAssertEqual(grid.rect(5), CGRect(x: 0, y: 30, width: 30, height: 30))
        XCTAssertEqual(grid.rect(12), CGRect(x: 90, y: 60, width: 30, height: 30))
        XCTAssertNil(grid.rect(0))
        XCTAssertNil(grid.rect(13))
        XCTAssertEqual(grid.point(6), CGPoint(x: 45, y: 45))
        XCTAssertEqual(grid.describe(7), "cell 7: row 2 of 3, column 3 of 4")
    }

    func testThePointsCellIsFoundBack() {
        let grid = CanvasGrid.over(chess)
        for number in grid.numbers {
            XCTAssertEqual(grid.number(at: grid.point(number)!), number)
        }
        XCTAssertNil(grid.number(at: CGPoint(x: 0, y: 0)))
        // The far edge belongs to the last cell.
        XCTAssertEqual(grid.number(at: CGPoint(x: chess.maxX - 0.001, y: chess.maxY - 0.001)), grid.count)
    }

    func testTheCloseUpHoldsThreeCellsASideAroundThePickAndStaysInside() {
        let grid = CanvasGrid.over(chess)
        // In the middle: the pick's cell in the middle of the close-up.
        let middle = grid.around(5 * 12 + 6)!
        let cell = grid.rect(5 * 12 + 6)!
        XCTAssertEqual(middle.midX, cell.midX, accuracy: 0.01)
        XCTAssertEqual(middle.midY, cell.midY, accuracy: 0.01)
        XCTAssertEqual(middle.width, cell.width * 3, accuracy: 0.01)
        // In a corner: moved inside the window, never cut.
        let corner = grid.around(1)!
        XCTAssertEqual(corner.minX, chess.minX, accuracy: 0.01)
        XCTAssertEqual(corner.minY, chess.minY, accuracy: 0.01)
        XCTAssertEqual(corner.width, cell.width * 3, accuracy: 0.01)
        XCTAssertTrue(corner.contains(CGPoint(x: grid.rect(1)!.midX, y: grid.rect(1)!.midY)))
        let last = grid.around(grid.count)!
        XCTAssertEqual(last.maxX, chess.maxX, accuracy: 0.01)
        XCTAssertEqual(last.maxY, chess.maxY, accuracy: 0.01)
    }

    func testTheFineCellsAreUnderTheSmallestChessSquare() {
        let grid = CanvasGrid.over(chess)
        let close = grid.around(50)!
        let fine = CanvasGrid.over(close, side: CanvasGrid.fineSide)
        let cell = fine.rect(1)!
        // Rank 8 squares are ~32 × 28 pt: a fine cell's middle is less
        // than half a square from any point in it.
        XCTAssertLessThan(cell.width, 28)
        XCTAssertLessThan(cell.height, 28)
        XCTAssertLessThan(fine.count, 255)
    }

    // MARK: - Drawn

    private func capture(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Left half black, right half white: where a cut comes from shows.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    private func size(_ data: Data) -> (Int, Int) {
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
        return (image.width, image.height)
    }

    func testTheGridIsDrawnOverThePicture() {
        let image = capture(1814, 1424)
        let plain = WindowPicture.jpeg(image, window: chess)!
        let gridded = WindowPicture.jpeg(image, window: chess, grid: .over(chess))!
        XCTAssertEqual(size(plain).0, 1024)
        XCTAssertEqual(size(gridded).0, 1024)
        XCTAssertNotEqual(plain, gridded)
    }

    func testTheCloseUpIsCutFromTheCaptureAndBroughtTo768() {
        let image = capture(1814, 1424)
        let grid = CanvasGrid.over(chess)
        // Cell 1 sits in the black half: its close-up is mostly black.
        let area = grid.around(1)!
        let close = WindowPicture.closeUp(image, window: chess, area: area, grid: .over(area, side: CanvasGrid.fineSide))!
        let (width, height) = size(close.data)
        XCTAssertEqual(max(width, height), 768)
        XCTAssertGreaterThanOrEqual(min(width, height), 280)
        // Outside the window: nothing.
        XCTAssertNil(WindowPicture.closeUp(image, window: chess, area: CGRect(x: 2000, y: 2000, width: 50, height: 50),
                                           grid: .over(area)))
    }
}
