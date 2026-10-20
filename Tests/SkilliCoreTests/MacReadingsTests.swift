import XCTest
@testable import SkilliCore

final class MacReadingsTests: XCTestCase {
    func testSpeedTestReadsNetworkQuality() throws {
        let json = Data("""
            {"base_rtt": 8.52, "dl_throughput": 329496256, "ul_throughput": 41234567, "responsiveness": 1337.3, "interface_name": "en0"}
            """.utf8)
        let test = try XCTUnwrap(SpeedTest(json: json))
        XCTAssertEqual(test.summary, "↓ 329 Mbps · ↑ 41 Mbps · Responsiveness: High (1,337 RPM) · Latency 9 ms".replacingOccurrences(of: "1,337", with: 1337.formatted()))
        let slow = SpeedTest(download: 2_400_000, upload: 1_500_000_000, responsiveness: 120, latency: nil)
        XCTAssertEqual(slow.summary, "↓ 2.4 Mbps · ↑ 1.5 Gbps · Responsiveness: Low (120 RPM)")
        XCTAssertNil(SpeedTest(json: Data("{}".utf8)))
        // Sequential runs only give the download's responsiveness.
        let sequential = SpeedTest(json: Data(#"{"dl_throughput": 1e8, "ul_throughput": 1e7, "dl_responsiveness": 400}"#.utf8))
        XCTAssertEqual(sequential?.responsiveness, 400)
    }

    func testPickedColorFormats() {
        let mint = PickedColor(red: 62 / 255, green: 142 / 255, blue: 126 / 255)
        XCTAssertEqual(mint.hex, "#3E8E7E")
        XCTAssertEqual(mint.rgb, "rgb(62, 142, 126)")
        XCTAssertEqual(mint.hsl, "hsl(168, 39%, 40%)")
        XCTAssertEqual(PickedColor(red: 1.2, green: -0.1, blue: 0.5).hex, "#FF0080")
        XCTAssertEqual(PickedColor(red: 0.5, green: 0.5, blue: 0.5).hsl, "hsl(0, 0%, 50%)")
    }

    func testUptimeAndPercent() {
        XCTAssertEqual(MacReadings.uptime(8 * 60 + 30), "8 min")
        XCTAssertEqual(MacReadings.uptime(5 * 3_600 + 12 * 60), "5 h 12 min")
        XCTAssertEqual(MacReadings.uptime(3 * 86_400 + 4 * 3_600), "3 days 4 h")
        XCTAssertEqual(MacReadings.percent("30 %"), 30)
        XCTAssertEqual(MacReadings.percent("100"), 100)
        XCTAssertNil(MacReadings.percent("150"))
        XCTAssertNil(MacReadings.percent("loud"))
    }
}
