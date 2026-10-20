import CoreGraphics
import XCTest
@testable import SkilliCore

final class LauncherPlaceTests: XCTestCase {
    /// A 1512×945 screen under a 37 pt menu bar, AppKit's origin at the
    /// bottom left.
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 908)
    /// A second display to its right, larger, under its own menu bar.
    private let wide = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
    private let glass = CGSize(width: 700, height: 580)

    private func standardFrame(in visible: CGRect) -> CGRect {
        LauncherPlace.standard(size: glass, in: visible).frame(size: glass, in: visible)
    }

    func testStandardIsCenteredItsTopEighteenPercentDown() {
        for screen in [visible, wide] {
            let frame = standardFrame(in: screen)
            XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
            XCTAssertEqual(frame.maxY, screen.maxY - screen.height * 0.18, accuracy: 1)
            XCTAssertEqual(frame.size, glass)
        }
    }

    func testAMovedGlassComesBackWhereItWas() {
        let moved = CGRect(x: 120, y: 260, width: 700, height: 580)
        let place = LauncherPlace(glass: moved, in: visible)
        XCTAssertEqual(place.frame(size: glass, in: visible), moved)
    }

    func testCenteredStaysCenteredOnAnotherDisplay() {
        let centered = CGRect(x: 406, y: 164, width: 700, height: 580)
        let frame = LauncherPlace(glass: centered, in: visible).frame(size: glass, in: wide)
        XCTAssertEqual(frame.midX, wide.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, wide.midY, accuracy: 1)
    }

    func testACornerStaysInItsCornerOnAnotherDisplay() {
        let bottomRight = CGRect(x: 812, y: 0, width: 700, height: 580)
        let frame = LauncherPlace(glass: bottomRight, in: visible).frame(size: glass, in: wide)
        XCTAssertEqual(frame.maxX, wide.maxX)
        XCTAssertEqual(frame.minY, wide.minY)
    }

    func testTheGlassStaysWholeOnScreen() {
        // Dragged half past the bottom right corner.
        let place = LauncherPlace(glass: CGRect(x: 1300, y: -300, width: 700, height: 580), in: visible)
        let frame = place.frame(size: glass, in: visible)
        XCTAssertEqual(frame.maxX, visible.maxX)
        XCTAssertEqual(frame.minY, visible.minY)
        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(small.contains(place.frame(size: glass, in: small)))
    }

    func testTooSmallAScreenShowsTheTopLeft() {
        // The search field sits at the top: it must stay on screen.
        let tiny = CGRect(x: 0, y: 0, width: 600, height: 400)
        let frame = LauncherPlace.standard(size: glass, in: tiny).frame(size: glass, in: tiny)
        XCTAssertEqual(frame.maxY, tiny.maxY)
        XCTAssertEqual(frame.minX, tiny.minX)
    }

    func testWholePoints() {
        let frame = LauncherPlace(across: 0.3333, down: 0.1777).frame(size: glass, in: visible)
        XCTAssertEqual(frame.minX, frame.minX.rounded())
        XCTAssertEqual(frame.minY, frame.minY.rounded())
    }

    func testSavedAsJSONAndOldPlacesAreDropped() throws {
        let place = LauncherPlace(across: 0.25, down: 0.4)
        let data = try JSONEncoder().encode(place)
        XCTAssertEqual(try JSONDecoder().decode(LauncherPlace.self, from: data), place)
        // Saved by the first version (fractions of the screen): not read.
        XCTAssertNil(try? JSONDecoder().decode(LauncherPlace.self, from: Data(#"{"x":0.5,"top":0.2}"#.utf8)))
    }

    // MARK: - Pulled onto the guides

    func testNearTheMiddleItIsPulledCenteredAcross() {
        let near = CGRect(x: 412, y: 100, width: 700, height: 580)
        let snapped = LauncherPlace.snap(near, in: visible)
        XCTAssertEqual(snapped.frame.midX, visible.midX)
        XCTAssertEqual(snapped.frame.minY, 100)
        XCTAssertEqual(snapped.guides, [.centerX])
    }

    func testOutOfReachNothingPulls() {
        let free = CGRect(x: 430, y: 60, width: 700, height: 580)
        let snapped = LauncherPlace.snap(free, in: visible)
        XCTAssertEqual(snapped.frame, free)
        XCTAssertEqual(snapped.guides, [])
    }

    func testCenteredDownOnATallScreen() {
        // On the large display the middle and the standard height are apart.
        let near = CGRect(x: 1700, y: 210, width: 700, height: 580)
        let snapped = LauncherPlace.snap(near, in: wide)
        XCTAssertEqual(snapped.frame.midY, wide.midY, accuracy: 0.5)
        XCTAssertEqual(snapped.guides, [.centerY])
    }

    func testBothGuidesLandExactlyOnTheStandardPlace() {
        let standard = standardFrame(in: wide)
        let snapped = LauncherPlace.snap(standard.offsetBy(dx: 5, dy: -6), in: wide)
        XCTAssertEqual(snapped.frame, standard)
        XCTAssertEqual(snapped.guides, [.centerX, .standardTop])
    }

    func testTheNearerLineWins() {
        // On this screen the middle and the standard height are 1 pt apart.
        let standard = standardFrame(in: visible)
        let snapped = LauncherPlace.snap(standard.offsetBy(dx: 0, dy: 3), in: visible)
        XCTAssertEqual(snapped.frame, standard)
        XCTAssertEqual(snapped.guides, [.centerX, .standardTop])
    }
}
