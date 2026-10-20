import CoreGraphics
import Foundation
@testable import SkilliCore
import XCTest

final class PictureChangeTests: XCTestCase {
    /// A 1814 × 1424 window of one gray with a square of `square` gray at
    /// (`x`, `y`) pixels, 80 px a side (a chess piece at 2×).
    private func window(square: CGFloat? = nil, x: Int = 600, y: Int = 700) -> CGImage {
        let context = CGContext(data: nil, width: 1814, height: 1424, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1814, height: 1424))
        if let square {
            context.setFillColor(CGColor(gray: square, alpha: 1))
            context.fill(CGRect(x: x, y: y, width: 80, height: 80))
        }
        return context.makeImage()!
    }

    func testAPieceMovingIsAChange() {
        let before = PictureChange.thumbnail(window(square: 0.9, x: 600, y: 700))
        let after = PictureChange.thumbnail(window(square: 0.9, x: 600, y: 860))
        XCTAssertTrue(PictureChange.differs(before, after))
        XCTAssertEqual(before.count, PictureChange.width * PictureChange.height)
    }

    func testTheSamePictureIsNoChange() {
        let one = PictureChange.thumbnail(window(square: 0.9))
        XCTAssertFalse(PictureChange.differs(one, PictureChange.thumbnail(window(square: 0.9))))
        // A faint shade change is noise.
        XCTAssertFalse(PictureChange.differs(one, PictureChange.thumbnail(window(square: 0.92))))
    }
}
