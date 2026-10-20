import CoreGraphics
import XCTest
@testable import SkilliCore

final class DisplayFingerprintTests: XCTestCase {
    private func samsung(serial: UInt32 = 16_780_800, text: String? = nil, made: String? = "2025-W1", uuid: String = "S1") -> DisplayFingerprint {
        DisplayFingerprint(name: "SAMSUNG", vendor: 19501, model: 30787, serial: serial, serialText: text, made: made, builtIn: false, uuid: uuid)
    }

    private let builtIn = DisplayFingerprint(name: "Built-in Retina Display", vendor: 1552, model: 41054, serial: 1, builtIn: true, uuid: "B")

    private func display(_ fingerprint: DisplayFingerprint, _ frame: CGRect) -> LayoutDisplay {
        LayoutDisplay(fingerprint: fingerprint, frame: frame, visible: frame)
    }

    func testTheSameUnitByItsSerial() {
        XCTAssertEqual(samsung().same(as: samsung(uuid: "other port")), .unit)
        // Another unit of the same model: another serial.
        XCTAssertNil(samsung().same(as: samsung(serial: 16_780_801)))
        // The text serial wins over the number some makers repeat.
        XCTAssertEqual(samsung(text: "HNMX400123").same(as: samsung(text: "HNMX400123")), .unit)
        XCTAssertNil(samsung(text: "HNMX400123").same(as: samsung(text: "HNMX400999")))
        // Same number, made another week: another unit.
        XCTAssertNil(samsung(made: "2025-W1").same(as: samsung(made: "2024-W40")))
        // Same name, another model: never the same.
        var other = samsung()
        other.model = 30788
        XCTAssertNil(samsung().same(as: other))
    }

    func testNoSerialIsOnlyTheModel() {
        XCTAssertEqual(samsung(serial: 0).certainty, .model)
        XCTAssertEqual(samsung(serial: 0).same(as: samsung(serial: 0, uuid: "S2")), .model)
        // One with a serial and one without are two units.
        XCTAssertNil(samsung(serial: 0).same(as: samsung()))
        XCTAssertEqual(builtIn.certainty, .unit)
        XCTAssertNil(builtIn.same(as: samsung()))
    }

    func testPairsEachSavedDisplayWithItself() {
        let left = CGRect(x: -3840, y: 0, width: 3840, height: 2160)
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let saved = [display(builtIn, main), display(samsung(), left)]
        // Connected in another order and another place: still themselves.
        let current = [display(builtIn, main), display(samsung(), CGRect(x: 1800, y: 0, width: 3840, height: 2160))]
        XCTAssertEqual(DisplayPairing.pair(saved: saved, current: current),
                       [.init(index: 0, match: .same(.unit)), .init(index: 1, match: .same(.unit))])
        XCTAssertEqual(DisplayPairing.pair(saved: saved, current: current.reversed()),
                       [.init(index: 1, match: .same(.unit)), .init(index: 0, match: .same(.unit))])
        XCTAssertEqual(DisplayPairing.pair(saved: saved, current: []), [])
    }

    func testTwinsWithTheSameSerialAreToldApartByMacOSsID() {
        // Two units of a model whose maker writes one serial on all.
        let a = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let b = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        let saved = [display(samsung(uuid: "port A"), a), display(samsung(uuid: "port B"), b)]
        let current = [display(samsung(uuid: "port B"), a), display(samsung(uuid: "port A"), b)]
        XCTAssertEqual(DisplayPairing.pair(saved: saved, current: current),
                       [.init(index: 1, match: .same(.model)), .init(index: 0, match: .same(.model))])
    }

    func testAMissingDisplayHandsItsWindowsToTheNearestOfItsKind() {
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let lg = DisplayFingerprint(name: "LG", vendor: 7789, model: 1, serial: 5, builtIn: false, uuid: "L")
        let dell = DisplayFingerprint(name: "DELL", vendor: 4268, model: 2, serial: 9, builtIn: false, uuid: "D")
        let saved = [display(builtIn, main), display(lg, CGRect(x: 1800, y: 0, width: 2560, height: 1440))]
        // The LG is gone, a Dell is there: the Dell stands in, not the built-in.
        let current = [display(builtIn, main), display(dell, CGRect(x: -2560, y: 0, width: 2560, height: 1440))]
        XCTAssertEqual(DisplayPairing.pair(saved: saved, current: current),
                       [.init(index: 0, match: .same(.unit)), .init(index: 1, match: .standIn)])
        // Only the built-in now: it takes both.
        XCTAssertEqual(DisplayPairing.pair(saved: saved, current: [display(builtIn, main)]),
                       [.init(index: 0, match: .same(.unit)), .init(index: 0, match: .standIn)])
    }
}
