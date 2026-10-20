import CoreGraphics
import Foundation
import ImageIO
@testable import SkilliCore
import XCTest

final class WindowPictureTests: XCTestCase {
    /// A window's capture: `width` × `height` pixels of one gray.
    private func capture(_ width: Int, _ height: Int, gray: CGFloat = 0.5) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The JPEG back: its size and its pixels (RGBA, top row first).
    private func decode(_ data: Data) -> (width: Int, height: Int, pixel: (Int, Int) -> (r: Int, g: Int, b: Int)) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let copy = bytes
        return (width, height, { x, y in
            let index = (y * width + x) * 4
            return (Int(copy[index]), Int(copy[index + 1]), Int(copy[index + 2]))
        })
    }

    /// What TypeSafe takes: 256 to 1568 px a side, 78,400 px or more.
    private func assertWithinTypeSafe(_ width: Int, _ height: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue((256...1568).contains(width), "width \(width)", file: file, line: line)
        XCTAssertTrue((256...1568).contains(height), "height \(height)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(width * height, 78_400, file: file, line: line)
    }

    func testLongestSideIsTwoPixelsAPointFrom512To1024() {
        XCTAssertEqual(WindowPicture.longest(forPoints: CGSize(width: 200, height: 150)), 512)
        XCTAssertEqual(WindowPicture.longest(forPoints: CGSize(width: 400, height: 300)), 800)
        XCTAssertEqual(WindowPicture.longest(forPoints: CGSize(width: 820, height: 700)), 1024)
        XCTAssertEqual(WindowPicture.longest(forPoints: CGSize(width: 300, height: 1200)), 1024)
    }

    func testARetinaWindowComesDownToItsLongestSide() throws {
        let window = CGRect(x: 100, y: 50, width: 1460, height: 900)
        let data = try XCTUnwrap(WindowPicture.jpeg(capture(2920, 1800), window: window))
        let picture = decode(data)
        XCTAssertEqual(picture.width, 1024)
        XCTAssertEqual(picture.height, 631)
        assertWithinTypeSafe(picture.width, picture.height)
        // About 2,300 tokens at 1024 px: a few hundred kilobytes at most.
        XCTAssertLessThan(data.count, 400_000)
    }

    func testSmallWindowsArePaddedOnWhiteLikeJevImages() throws {
        // A short wide window: 512 wide, padded to 280 high.
        let wide = WindowPicture.layout(pixels: CGSize(width: 600, height: 200), longest: 512)
        XCTAssertEqual(wide.drawn, CGSize(width: 512, height: 171))
        XCTAssertEqual(wide.canvas, CGSize(width: 512, height: 280))
        XCTAssertEqual(wide.origin, CGPoint(x: 0, y: 54))
        // Smaller than the least: never scaled up, centered on 280 × 280.
        let tiny = WindowPicture.layout(pixels: CGSize(width: 100, height: 80), longest: 512)
        XCTAssertEqual(tiny.drawn, CGSize(width: 100, height: 80))
        XCTAssertEqual(tiny.canvas, CGSize(width: 280, height: 280))
        XCTAssertEqual(tiny.origin, CGPoint(x: 90, y: 100))

        let data = try XCTUnwrap(WindowPicture.jpeg(capture(100, 80, gray: 0), window: CGRect(x: 0, y: 0, width: 100, height: 80)))
        let picture = decode(data)
        assertWithinTypeSafe(picture.width, picture.height)
        XCTAssertGreaterThan(picture.pixel(5, 5).r, 240, "white around")
        XCTAssertLessThan(picture.pixel(140, 140).r, 20, "the window in the middle")
        // A very wide window still fits.
        let strip = try XCTUnwrap(WindowPicture.jpeg(capture(6000, 200), window: CGRect(x: 0, y: 0, width: 3000, height: 100)))
        let decoded = decode(strip)
        XCTAssertEqual(decoded.width, 1024)
        assertWithinTypeSafe(decoded.width, decoded.height)
    }

    func testOnlyItemsWithoutWordsInsideTheWindowAreMarked() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        var items = [ScreenItem(id: "i1", source: .element, role: "button", label: "Save", frame: CGRect(x: 120, y: 120, width: 60, height: 24)),
                     ScreenItem(id: "i2", source: .element, role: "button", label: "", frame: CGRect(x: 200, y: 360, width: 30, height: 24)),
                     ScreenItem(id: "i3", source: .element, role: "button", label: "", frame: CGRect(x: 900, y: 900, width: 30, height: 24)),
                     ScreenItem(id: "i4", source: .element, role: "button", label: ""),
                     ScreenItem(id: "i5", source: .text, role: "text on screen", label: "", frame: CGRect(x: 150, y: 150, width: 30, height: 20)),
                     ScreenItem(id: "i6", source: .element, role: "text", label: "", frame: CGRect(x: 150, y: 150, width: 30, height: 20))]
        XCTAssertEqual(WindowPicture.marks(items, window: window).map(\.id), ["i2"])
        items = (1...60).map { ScreenItem(id: "i\($0)", source: .element, role: "button", label: "", frame: CGRect(x: 110, y: 110, width: 10, height: 10)) }
        XCTAssertEqual(WindowPicture.marks(items, window: window).count, WindowPicture.markLimit)
    }

    func testAMarkOutlinesItsItemWhereThePictureShowsIt() throws {
        // A 400 × 300 pt window at 2× (800 × 600 px): 512 × 384 in the picture.
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        let mark = WindowPicture.Mark(id: "i7", frame: CGRect(x: 300, y: 300, width: 50, height: 40))
        let layout = WindowPicture.layout(pixels: CGSize(width: 800, height: 600), longest: 512)
        let placed = WindowPicture.place(mark.frame, window: window, layout: layout)
        XCTAssertEqual(placed.minX, 256, accuracy: 0.5)
        XCTAssertEqual(placed.minY, 256, accuracy: 0.5)
        XCTAssertEqual(placed.width, 64, accuracy: 0.5)

        let data = try XCTUnwrap(WindowPicture.jpeg(capture(800, 600, gray: 1), window: window, marks: [mark], longest: 512))
        let picture = decode(data)
        XCTAssertEqual(picture.width, 512)
        XCTAssertEqual(picture.height, 384)
        // The outline's left edge, magenta; inside it, the window untouched.
        let edge = picture.pixel(Int(placed.minX) - 1, Int(placed.midY))
        XCTAssertGreaterThan(edge.r, 150)
        XCTAssertLessThan(edge.g, 90)
        let inside = picture.pixel(Int(placed.midX), Int(placed.midY))
        XCTAssertGreaterThan(inside.g, 230, "the item itself stays visible")
        // The tag sits above the item, at its left.
        let tag = picture.pixel(Int(placed.minX) + 1, Int(placed.minY) - 4)
        XCTAssertGreaterThan(tag.r, 150)
        XCTAssertLessThan(tag.g, 120)
    }

    func testTheAssetIsTypeSafesImage() throws {
        let data = try XCTUnwrap(WindowPicture.jpeg(capture(600, 600), window: CGRect(x: 0, y: 0, width: 300, height: 300)))
        let asset = WindowPicture.asset(data)
        XCTAssertEqual(asset["type"], "image")
        XCTAssertEqual(asset["format"], "jpeg")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(asset["data_base64"])), data)
        XCTAssertFalse(try XCTUnwrap(asset["data_base64"]).contains("\n"), "no line breaks")
        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]), "a JPEG")
        let a = WindowPicture.reference(), b = WindowPicture.reference()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.hasPrefix("window-"))
    }
}

final class PictureBoxTests: XCTestCase {
    func testABoxComesBackWhereItWasOnScreen() {
        let window = CGRect(x: 5, y: 368, width: 907, height: 712)
        // A Retina window, brought down to 1024; and a small one, padded.
        for (pixels, points) in [(CGSize(width: 1814, height: 1424), window), (CGSize(width: 300, height: 120), CGRect(x: 40, y: 50, width: 150, height: 60))] {
            let layout = WindowPicture.layout(pixels: pixels, longest: WindowPicture.longest(forPoints: points.size))
            let item = CGRect(x: points.minX + points.width * 0.4, y: points.minY + points.height * 0.6, width: 20, height: 10)
            let drawn = WindowPicture.place(item, window: points, layout: layout)
            let fractions = CGRect(x: drawn.minX / layout.canvas.width, y: drawn.minY / layout.canvas.height,
                                   width: drawn.width / layout.canvas.width, height: drawn.height / layout.canvas.height)
            let back = WindowPicture.unplace(fractions, window: points, layout: layout)
            XCTAssertEqual(back.minX, item.minX, accuracy: 0.01)
            XCTAssertEqual(back.minY, item.minY, accuracy: 0.01)
            XCTAssertEqual(back.width, item.width, accuracy: 0.01)
            XCTAssertEqual(back.height, item.height, accuracy: 0.01)
        }
    }
}
