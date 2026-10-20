import CoreGraphics
import Foundation
import XCTest
@testable import SkilliCore

final class LayoutEditingTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 30, width: 1800, height: 1139)

    func testTheCanvasFitsEveryDisplay() {
        // The Mac, and a 4K display above it to the left.
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let samsung = CGRect(x: -1114, y: -2160, width: 3840, height: 2160)
        let map = LayoutCanvasMap(displays: [main, samsung], size: CGSize(width: 640, height: 480), padding: 10)
        XCTAssertEqual(map.bounds, CGRect(x: -1114, y: -2160, width: 3840, height: 3329))
        // Height bound: 460 / 3329.
        XCTAssertEqual(map.scale, 460 / 3329, accuracy: 0.0001)
        let drawn = map.canvas(map.bounds)
        XCTAssertEqual(drawn.minY, 10, accuracy: 0.001)
        XCTAssertEqual(drawn.midX, 320, accuracy: 0.001)
        // A drag of 46 canvas points is 333 screen points.
        XCTAssertEqual(map.screen(CGSize(width: 46, height: 0)).width, 46 / map.scale, accuracy: 0.001)
        XCTAssertEqual(LayoutCanvasMap(displays: [], size: CGSize(width: 100, height: 100), padding: 0).scale, 1)
    }

    func testAMovedWindowSticksToHalvesAndThirds() {
        // Its left edge 8 points from the middle: on the middle.
        let near = CGRect(x: 908, y: 40, width: 900, height: 1139)
        XCTAssertEqual(LayoutSnap.move(near, in: visible, tolerance: 12), CGRect(x: 900, y: 30, width: 900, height: 1139))
        // Its right edge near two thirds (1200).
        XCTAssertEqual(LayoutSnap.move(CGRect(x: 595, y: 300, width: 600, height: 400), in: visible, tolerance: 12).maxX, 1200)
        // Far from every line: where it was dropped.
        let free = CGRect(x: 260, y: 300, width: 500, height: 400)
        XCTAssertEqual(LayoutSnap.move(free, in: visible, tolerance: 12), free)
    }

    func testResizingStopsAtTheMinimumAndSticks() {
        let start = CGRect(x: 0, y: 30, width: 900, height: 1139)
        // Dragged right by 293: the right edge near two thirds sticks there.
        let wider = LayoutSnap.resized(start, by: CGSize(width: 293, height: 0), edges: [.right, .bottom], minimum: CGSize(width: 160, height: 100))
        XCTAssertEqual(LayoutSnap.resize(wider, edges: [.right, .bottom], in: visible, tolerance: 12, minimum: CGSize(width: 160, height: 100)),
                       CGRect(x: 0, y: 30, width: 1200, height: 1139))
        // Dragged past its other edge: it stops at the minimum.
        let tiny = LayoutSnap.resized(start, by: CGSize(width: -2000, height: -2000), edges: [.right, .bottom], minimum: CGSize(width: 160, height: 100))
        XCTAssertEqual(tiny, CGRect(x: 0, y: 30, width: 160, height: 100))
        // The top left corner moves the top and the left only.
        let corner = LayoutSnap.resized(start, by: CGSize(width: 100, height: 50), edges: [.left, .top], minimum: CGSize(width: 160, height: 100))
        XCTAssertEqual(corner, CGRect(x: 100, y: 80, width: 800, height: 1089))
    }

    func testLeftOutAppsAreRemembered() throws {
        let layout = SavedWindowLayout(id: "desk", name: "Desk", windows: [], ignoredApps: ["com.apple.Music"], saved: Date(timeIntervalSince1970: 0))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(SavedWindowLayout.self, from: encoder.encode(layout)).ignoredApps, ["com.apple.Music"])
    }

    func testAnAddedWindowTakesTheFirstFreeHalfThenQuarter() {
        let left = CGRect(x: 0, y: 30, width: 900, height: 1139)
        XCTAssertEqual(LayoutSnap.freeSpot(among: [], in: visible), left)
        XCTAssertEqual(LayoutSnap.freeSpot(among: [left], in: visible), CGRect(x: 900, y: 30, width: 900, height: 1139))
        // Both halves taken: a quarter, then the middle when all are.
        let right = CGRect(x: 900, y: 30, width: 900, height: 1139)
        XCTAssertEqual(LayoutSnap.freeSpot(among: [left, right], in: visible).size, CGSize(width: 1800 * 2 / 3, height: (1139 * 2.0 / 3).rounded()))
        // A small window does not take a half.
        XCTAssertEqual(LayoutSnap.freeSpot(among: [CGRect(x: 100, y: 100, width: 200, height: 200)], in: visible), left)
    }

    func testWithAGapWindowsStickWhereTheKeysLeaveThem() {
        let gap: CGFloat = 10
        // Added by hand: the left half as ✦W ← leaves it.
        let added = LayoutSnap.freeSpot(among: [], in: visible, gap: gap)
        XCTAssertEqual(added, WindowLayout.leftHalf.frame(in: visible, gap: gap))
        XCTAssertEqual(added, CGRect(x: 10, y: 40, width: 885, height: 1119))
        // Dragged near the middle: its left edge half a gap past it, its
        // top a whole gap under the menu bar.
        let near = CGRect(x: 912, y: 44, width: 885, height: 1119)
        XCTAssertEqual(LayoutSnap.move(near, in: visible, tolerance: 12, gap: gap), WindowLayout.rightHalf.frame(in: visible, gap: gap))
        // Its right edge dragged near the screen's: a whole gap before it.
        let wider = LayoutSnap.resize(CGRect(x: 10, y: 40, width: 1775, height: 1119), edges: [.right], in: visible, tolerance: 12,
                                      minimum: CGSize(width: 160, height: 100), gap: gap)
        XCTAssertEqual(wider.maxX, visible.maxX - gap)
    }
}
