import XCTest
@testable import SkilliCore

final class TimerRequestTests: XCTestCase {
    private func parse(_ text: String) -> (Int, String)? {
        TimerRequest.parse(text).map { ($0.seconds, $0.label) }
    }

    func testLauncherForms() {
        XCTAssertEqual(parse("timer 10 min pâtes")?.0, 600)
        XCTAssertEqual(parse("timer 10 min pâtes")?.1, "Pâtes")
        XCTAssertEqual(parse("timer 10m")?.0, 600)
        XCTAssertEqual(parse("minuteur 1h30")?.0, 5_400)
        XCTAssertEqual(parse("minuteur 1 h 30 four")?.0, 5_400)
        XCTAssertEqual(parse("timer 90s")?.0, 90)
        XCTAssertEqual(parse("timer 2 minutes 30")?.0, 150)
        XCTAssertEqual(parse("timer 1:30 tea")?.0, 90)
        XCTAssertEqual(parse("timer 1:30 tea")?.1, "Tea")
        XCTAssertEqual(parse("timer 10")?.0, 600)
        XCTAssertEqual(parse("timer 1,5 h")?.0, 5_400)
        XCTAssertEqual(parse("pomodoro")?.0, 1_500)
    }

    func testSentences() {
        XCTAssertEqual(parse("mets un minuteur de 10 minutes pour les pâtes")?.0, 600)
        XCTAssertEqual(parse("mets un minuteur de 10 minutes pour les pâtes")?.1, "Pâtes")
        XCTAssertEqual(parse("set a timer for 25 minutes")?.0, 1_500)
        XCTAssertEqual(parse("rappelle-moi dans 20 min de sortir le linge")?.0, 1_200)
    }

    func testNotATimer() {
        XCTAssertNil(parse("10 min"))
        XCTAssertNil(parse("timer"))
        XCTAssertNil(parse("ouvre safari"))
        XCTAssertNil(parse("timer 48 h"), "a day at most")
    }

    func testClockAndSpoken() {
        XCTAssertEqual(TimerRequest.clock(581), "9:41")
        XCTAssertEqual(TimerRequest.clock(3_723), "1:02:03")
        XCTAssertEqual(TimerRequest.spoken(600), "10 min")
        XCTAssertEqual(TimerRequest.spoken(5_400), "1 h 30")
        XCTAssertEqual(TimerRequest.spoken(150), "2 min 30 s")
        XCTAssertEqual(TimerRequest.spoken(45), "45 s")
    }
}
