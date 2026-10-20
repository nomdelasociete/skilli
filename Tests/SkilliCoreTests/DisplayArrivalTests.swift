import CoreGraphics
import Foundation
import XCTest
@testable import SkilliCore

final class DisplayArrivalTests: XCTestCase {
    private let builtIn = DisplayFingerprint(name: "Built-in Retina Display", vendor: 1552, model: 41054, serial: 1, builtIn: true, uuid: "B")
    private let samsung = DisplayFingerprint(name: "SAMSUNG", vendor: 19501, model: 30787, serial: 16_780_800, builtIn: false, uuid: "S")
    private let dell = DisplayFingerprint(name: "DELL U2723QE", vendor: 4268, model: 41_234, serial: 0, serialText: "8ZQX2V3", builtIn: false, uuid: "D")
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testPluggingInIsSeenOnce() {
        var arrival = DisplayArrival(present: [builtIn])
        XCTAssertEqual(arrival.update([builtIn, samsung], at: start), [samsung])
        // A change of arrangement or resolution: nothing new.
        XCTAssertEqual(arrival.update([builtIn, samsung], at: start + 5), [])
        // Unplugged, plugged again an hour later: plugged.
        XCTAssertEqual(arrival.update([builtIn], at: start + 10), [])
        XCTAssertEqual(arrival.update([builtIn, samsung], at: start + 3600), [samsung])
    }

    func testComingBackAfterSleepIsNotPluggingIn() {
        var arrival = DisplayArrival(present: [builtIn, samsung])
        arrival.sleep()
        // The display drops off while the Mac sleeps, comes back as it wakes.
        XCTAssertEqual(arrival.update([builtIn], at: start), [])
        arrival.wake(at: start + 60)
        XCTAssertEqual(arrival.update([builtIn, samsung], at: start + 64), [])
        // A display that was not there before sleeping is plugged in, even
        // as the Mac wakes (a dock that wakes it).
        arrival.sleep()
        _ = arrival.update([builtIn], at: start + 100)
        arrival.wake(at: start + 200)
        XCTAssertEqual(arrival.update([builtIn, dell], at: start + 202), [dell])
    }

    func testTheSameDisplayLongAfterWakingIsPluggedIn() {
        var arrival = DisplayArrival(present: [builtIn, samsung])
        arrival.sleep()
        _ = arrival.update([builtIn], at: start)
        arrival.wake(at: start + 60)
        // It stayed away after waking: plugged in again later, it counts.
        XCTAssertEqual(arrival.update([builtIn, samsung], at: start + 60 + DisplayArrival.wakeGrace + 1), [samsung])
    }

    func testTheLidIsNotADisplayPlugged() {
        var arrival = DisplayArrival(present: [samsung])
        XCTAssertEqual(arrival.update([builtIn, samsung], at: start), [])
    }

    // MARK: - Which layouts

    private func layout(_ id: String, _ displays: [DisplayFingerprint], automatic: SavedWindowLayout.Automatic = .ask) -> SavedWindowLayout {
        SavedWindowLayout(id: id, name: id, windows: [], displays: displays.map {
            LayoutDisplay(fingerprint: $0, frame: .zero, visible: .zero)
        }, automatic: automatic)
    }

    func testTheLayoutForExactlyTheseDisplaysComesFirst() {
        let layouts = [layout("samsung only", [samsung]), layout("desk", [builtIn, samsung]), layout("office", [builtIn, dell]),
                       layout("never", [builtIn, samsung], automatic: .never)]
        let offered = LayoutTrigger.candidates(for: [samsung], connected: [builtIn, samsung], layouts: layouts, ignoredMonitors: [])
        XCTAssertEqual(offered.map(\.layoutID), ["desk", "samsung only"])
        XCTAssertEqual(offered.first, .init(layoutID: "desk", certainty: .unit, exact: true))
        // An ignored monitor offers nothing; a display no layout knows neither.
        XCTAssertEqual(LayoutTrigger.candidates(for: [samsung], connected: [builtIn, samsung], layouts: layouts, ignoredMonitors: [samsung]), [])
        let other = DisplayFingerprint(name: "LG", vendor: 7789, model: 1, serial: 5, builtIn: false, uuid: "L")
        XCTAssertEqual(LayoutTrigger.candidates(for: [other], connected: [builtIn, other], layouts: layouts, ignoredMonitors: []), [])
    }

    func testASameModelWithoutSerialIsOfferedButNeverAppliedAlone() {
        let noSerial = DisplayFingerprint(name: "Generic", vendor: 1, model: 2, serial: 0, builtIn: false, uuid: "port A")
        let twin = DisplayFingerprint(name: "Generic", vendor: 1, model: 2, serial: 0, builtIn: false, uuid: "port B")
        let layouts = [layout("desk", [builtIn, noSerial], automatic: .always)]
        let offered = LayoutTrigger.candidates(for: [twin], connected: [builtIn, twin], layouts: layouts, ignoredMonitors: [])
        XCTAssertEqual(offered, [.init(layoutID: "desk", certainty: .model, exact: true)])
        XCTAssertNil(LayoutTrigger.automatic(offered, layouts: layouts))
        // Its own serial: put back without asking.
        let sure = [layout("desk", [builtIn, samsung], automatic: .always)]
        let surely = LayoutTrigger.candidates(for: [samsung], connected: [builtIn, samsung], layouts: sure, ignoredMonitors: [])
        XCTAssertEqual(LayoutTrigger.automatic(surely, layouts: sure), "desk")
        // Two set to always: asked.
        let two = sure + [layout("desk 2", [samsung], automatic: .always)]
        XCTAssertNil(LayoutTrigger.automatic(LayoutTrigger.candidates(for: [samsung], connected: [builtIn, samsung], layouts: two, ignoredMonitors: []),
                                             layouts: two))
    }

    func testOldLayoutsAsk() throws {
        let json = #"{"id":"a","name":"A","saved":"2026-10-12T10:00:00Z","windows":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(SavedWindowLayout.self, from: Data(json.utf8)).automatic, .ask)
    }
}
