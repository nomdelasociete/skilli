import XCTest
@testable import SkilliCore

final class AudioRouteTests: XCTestCase {
    private func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    func testTransportFromCoreAudioCodes() {
        XCTAssertEqual(AudioRoute.Transport(code: code("bltn")), .builtIn)
        XCTAssertEqual(AudioRoute.Transport(code: code("blue")), .bluetooth)
        XCTAssertEqual(AudioRoute.Transport(code: code("blea")), .bluetooth)
        XCTAssertEqual(AudioRoute.Transport(code: code("hdmi")), .display)
        XCTAssertEqual(AudioRoute.Transport(code: code("airp")), .airPlay)
        XCTAssertEqual(AudioRoute.Transport(code: code("virt")), .virtual)
        XCTAssertEqual(AudioRoute.Transport(code: code("usb ")), .usb)
        XCTAssertEqual(AudioRoute.Transport(code: 0), .other)
    }

    func testWords() {
        XCTAssertEqual(AudioRoute.title(name: "AirPods Pro", output: true), "Sound Output: AirPods Pro")
        XCTAssertEqual(AudioRoute.title(name: "MacBook Pro Microphone", output: false), "Microphone: MacBook Pro Microphone")
        XCTAssertEqual(AudioRoute.description(name: "AirPods Pro", transport: .bluetooth, output: true),
                       "Play the sound through Bluetooth headphones or speaker, named “AirPods Pro”: where it plays, not how loud")
        XCTAssertEqual(AudioRoute.symbol(name: "AirPods Pro de Camille", transport: .bluetooth, output: true), "airpodspro")
        XCTAssertEqual(AudioRoute.symbol(name: "SAMSUNG", transport: .display, output: true), "tv")
        XCTAssertEqual(AudioRoute.symbol(name: "SAMSUNG", transport: .display, output: false), "mic.fill")
    }

    func testMatchByNameThenKind() {
        let outputs: [(name: String, transport: AudioRoute.Transport)] = [
            ("MacBook Pro Speakers", .builtIn), ("AirPods Pro de Camille", .bluetooth), ("LG UltraFine", .display), ("NDI Audio", .virtual)
        ]
        XCTAssertEqual(AudioRoute.match("airpods", among: outputs, output: true), 1)
        XCTAssertEqual(AudioRoute.match("les AirPods", among: outputs, output: true), 1)
        XCTAssertEqual(AudioRoute.match("haut-parleurs du mac", among: outputs, output: true), 0)
        XCTAssertEqual(AudioRoute.match("speakers", among: outputs, output: true), 0)
        XCTAssertEqual(AudioRoute.match("l'écran", among: outputs, output: true), 2)
        XCTAssertEqual(AudioRoute.match("le casque", among: outputs, output: true), 1)
        XCTAssertEqual(AudioRoute.match("ndi", among: outputs, output: true), 3)
        XCTAssertNil(AudioRoute.match("la cuisine", among: outputs, output: true))
        XCTAssertNil(AudioRoute.match("le son", among: outputs, output: true))
        let twins: [(name: String, transport: AudioRoute.Transport)] = [("AirPods Pro", .bluetooth), ("AirPods Max", .bluetooth)]
        XCTAssertNil(AudioRoute.match("airpods", among: twins, output: true), "two AirPods: ask which")
        XCTAssertEqual(AudioRoute.match("airpods max", among: twins, output: true), 1)
    }
}
