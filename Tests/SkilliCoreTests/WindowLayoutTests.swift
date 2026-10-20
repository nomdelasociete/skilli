import CoreGraphics
import XCTest
@testable import SkilliCore

final class WindowLayoutTests: XCTestCase {
    /// A 1512×945 screen under a 37 pt menu bar, origin top left.
    private let visible = CGRect(x: 0, y: 37, width: 1512, height: 908)
    private let small = CGRect(x: 200, y: 300, width: 600, height: 400)

    private func frame(_ layout: WindowLayout, from current: CGRect, gap: CGFloat = 0, size: Int = 0) -> CGRect? {
        if case .frame(let frame) = layout.target(current: current, visible: visible, gap: gap, size: size) { return frame }
        return nil
    }

    func testHalvesHaveThreeSizes() {
        XCTAssertEqual(frame(.leftHalf, from: small), CGRect(x: 0, y: 37, width: 756, height: 908))
        XCTAssertEqual(frame(.leftHalf, from: small, size: 1), CGRect(x: 0, y: 37, width: 1008, height: 908))
        XCTAssertEqual(frame(.leftHalf, from: small, size: 2), CGRect(x: 0, y: 37, width: 504, height: 908))
        XCTAssertEqual(frame(.rightHalf, from: small), CGRect(x: 756, y: 37, width: 756, height: 908))
        XCTAssertEqual(frame(.rightHalf, from: small, size: 1), CGRect(x: 504, y: 37, width: 1008, height: 908))
        XCTAssertEqual(frame(.rightHalf, from: small, size: 2), CGRect(x: 1008, y: 37, width: 504, height: 908))
        // Top and bottom the same way, in height; the middle third widens.
        XCTAssertEqual(frame(.topHalf, from: small, size: 1), CGRect(x: 0, y: 37, width: 1512, height: 605))
        XCTAssertEqual(frame(.bottomHalf, from: small, size: 2), CGRect(x: 0, y: 642, width: 1512, height: 303))
        XCTAssertEqual(frame(.centerThird, from: small, size: 1), CGRect(x: 378, y: 37, width: 756, height: 908))
        XCTAssertEqual(frame(.centerThird, from: small, size: 2), CGRect(x: 252, y: 37, width: 1008, height: 908))
        // One size only: a press again changes nothing.
        XCTAssertEqual(WindowLayout.topLeft.sizes.count, 1)
        XCTAssertTrue(WindowLayout.center.sizes.isEmpty)
    }

    func testQuartersThirdsAndHalvesTopBottom() {
        XCTAssertEqual(frame(.topHalf, from: small), CGRect(x: 0, y: 37, width: 1512, height: 454))
        XCTAssertEqual(frame(.bottomHalf, from: small), CGRect(x: 0, y: 491, width: 1512, height: 454))
        XCTAssertEqual(frame(.bottomRight, from: small), CGRect(x: 756, y: 491, width: 756, height: 454))
        XCTAssertEqual(frame(.centerThird, from: small), CGRect(x: 504, y: 37, width: 504, height: 908))
        XCTAssertEqual(frame(.rightTwoThirds, from: small), CGRect(x: 504, y: 37, width: 1008, height: 908))
    }

    func testOddSizesNeverOverlap() {
        let odd = CGRect(x: 0, y: 25, width: 1513, height: 875)
        let left = WindowLayout.leftHalf.frame(in: odd)!
        let right = WindowLayout.rightHalf.frame(in: odd)!
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(right.maxX, odd.maxX)
    }

    // MARK: - Space between windows

    func testTheGapIsBetweenWindowsAndAtTheEdges() {
        let gap: CGFloat = 8
        let left = frame(.leftHalf, from: small, gap: gap)!
        let topRight = frame(.topRight, from: small, gap: gap)!
        let bottomRight = frame(.bottomRight, from: small, gap: gap)!
        // The whole gap at the screen's edges.
        XCTAssertEqual(left.minX, visible.minX + gap)
        XCTAssertEqual(left.minY, visible.minY + gap)
        XCTAssertEqual(left.maxY, visible.maxY - gap)
        XCTAssertEqual(topRight.maxX, visible.maxX - gap)
        XCTAssertEqual(bottomRight.maxY, visible.maxY - gap)
        // One gap between two windows side by side, and one above the other.
        XCTAssertEqual(topRight.minX - left.maxX, gap)
        XCTAssertEqual(bottomRight.minY - topRight.maxY, gap)
        XCTAssertEqual(left, CGRect(x: 8, y: 45, width: 744, height: 892))
        // Thirds: the same gap between each.
        let first = frame(.leftThird, from: small, gap: gap)!
        let middle = frame(.centerThird, from: small, gap: gap)!
        let last = frame(.rightThird, from: small, gap: gap)!
        XCTAssertEqual(middle.minX - first.maxX, gap)
        XCTAssertEqual(last.minX - middle.maxX, gap)
        XCTAssertEqual(last.maxX, visible.maxX - gap)
    }

    func testMaximizeKeepsTheGapAndTwiceRestores() {
        XCTAssertEqual(frame(.maximize, from: small), visible)
        XCTAssertEqual(WindowLayout.maximize.target(current: visible, visible: visible), .restore)
        let filled = frame(.maximize, from: small, gap: 12)
        XCTAssertEqual(filled, visible.insetBy(dx: 12, dy: 12))
        XCTAssertEqual(WindowLayout.maximize.target(current: filled!, visible: visible, gap: 12), .restore)
        // Almost Maximize has its own margin: no gap added.
        XCTAssertEqual(frame(.almostMaximize, from: small, gap: 12), frame(.almostMaximize, from: small))
    }

    func testCenterKeepsTheSizeAndFitsTheScreen() {
        XCTAssertEqual(frame(.center, from: small), CGRect(x: 456, y: 291, width: 600, height: 400))
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertEqual(frame(.center, from: huge), visible)
        XCTAssertEqual(frame(.center, from: huge, gap: 16), visible.insetBy(dx: 16, dy: 16))
    }

    // MARK: - Pressed again

    func testPressedAgainSoonCyclesHalfTwoThirdsThird() {
        let start = ContinuousClock.now
        var current = small
        var last: WindowCycle?
        var widths: [CGFloat] = []
        for press in 0..<4 {
            let now = start + .milliseconds(600 * press)
            let size = WindowCycle.size(of: .leftHalf, current: current, visible: visible, gap: 0, last: last, now: now)
            current = frame(.leftHalf, from: current, size: size)!
            last = WindowCycle(layout: .leftHalf, size: size, placed: current, at: now)
            widths.append(current.width)
        }
        XCTAssertEqual(widths, [756, 1008, 504, 756])
    }

    func testAfterAPauseItStartsOverButNeverDoesNothing() {
        let start = ContinuousClock.now
        let twoThirds = frame(.leftHalf, from: small, size: 1)!
        let last = WindowCycle(layout: .leftHalf, size: 1, placed: twoThirds, at: start)
        // Two seconds later, from two thirds: back to the half.
        XCTAssertEqual(WindowCycle.size(of: .leftHalf, current: twoThirds, visible: visible, gap: 0, last: last, now: start + .seconds(2)), 0)
        // At the half already (put there by hand or long ago): two thirds.
        let half = frame(.leftHalf, from: small)!
        XCTAssertEqual(WindowCycle.size(of: .leftHalf, current: half, visible: visible, gap: 0, last: nil, now: start), 1)
        // A terminal rounds its width to its character grid: still the half.
        let snapped = CGRect(x: 0, y: 37, width: 749, height: 903)
        XCTAssertEqual(WindowCycle.size(of: .leftHalf, current: snapped, visible: visible, gap: 0, last: nil, now: start), 1)
        // Another place, or a window moved since: its first size.
        XCTAssertEqual(WindowCycle.size(of: .rightHalf, current: twoThirds, visible: visible, gap: 0, last: last, now: start + .milliseconds(500)), 0)
        XCTAssertEqual(WindowCycle.size(of: .leftHalf, current: small, visible: visible, gap: 0, last: last, now: start + .milliseconds(500)), 0)
        // One size only: always it.
        XCTAssertEqual(WindowCycle.size(of: .topLeft, current: small, visible: visible, gap: 0, last: nil, now: start), 0)
    }

    func testCyclingWithAGap() {
        let start = ContinuousClock.now
        let half = frame(.rightHalf, from: small, gap: 16)!
        let last = WindowCycle(layout: .rightHalf, size: 0, placed: half, at: start)
        let size = WindowCycle.size(of: .rightHalf, current: half, visible: visible, gap: 16, last: last, now: start + .seconds(1))
        XCTAssertEqual(size, 1)
        XCTAssertEqual(frame(.rightHalf, from: half, gap: 16, size: size), CGRect(x: 512, y: 53, width: 984, height: 876))
    }

    // MARK: - Another display

    func testMovedToAnotherDisplayKeepsItsPlace() {
        let external = CGRect(x: 1512, y: -300, width: 2560, height: 1415)
        let leftHalf = CGRect(x: 0, y: 37, width: 756, height: 908)
        XCTAssertEqual(WindowLayout.moved(leftHalf, from: visible, to: external), CGRect(x: 1512, y: -300, width: 1280, height: 1415))
        // Bigger than the destination: it fits.
        let wide = CGRect(x: 100, y: 37, width: 1512, height: 908)
        let back = WindowLayout.moved(CGRect(x: 1512, y: -300, width: 2560, height: 1415), from: external, to: visible)
        XCTAssertEqual(back, visible)
        XCTAssertLessThanOrEqual(WindowLayout.moved(wide, from: visible, to: visible).maxX, visible.maxX)
    }

    func testAPlaceStaysThatPlaceOnTheNextDisplayGapIncluded() {
        // A display above, to the left, larger.
        let external = CGRect(x: -500, y: -1415, width: 2560, height: 1390)
        for gap: CGFloat in [0, 12] {
            for layout in [WindowLayout.leftHalf, .topRight, .rightTwoThirds, .maximize] {
                for size in layout.sizes.indices {
                    let here = layout.frame(in: visible, gap: gap, size: size)!
                    XCTAssertEqual(WindowLayout.moved(here, from: visible, to: external, gap: gap),
                                   layout.frame(in: external, gap: gap, size: size), "\(layout) \(size) gap \(gap)")
                }
            }
        }
        // Anywhere else: the same place in proportion.
        XCTAssertEqual(WindowLayout.moved(small, from: visible, to: external, gap: 12), WindowLayout.moved(small, from: visible, to: external))
        // Seen in proportion: 200/1512 across, 263/908 down.
        let moved = WindowLayout.moved(small, from: visible, to: external)
        XCTAssertEqual(moved.minX, (-500 + 200.0 / 1512 * 2560).rounded())
        XCTAssertEqual(moved.minY, (-1415 + 263.0 / 908 * 1390).rounded())
    }

    func testDisplaysAndRestoreAreTheCallers() {
        XCTAssertNil(WindowLayout.nextDisplay.target(current: small, visible: visible))
        XCTAssertNil(WindowLayout.restore.target(current: small, visible: visible))
    }
}
