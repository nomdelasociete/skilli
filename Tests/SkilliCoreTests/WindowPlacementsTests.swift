import CoreGraphics
import XCTest
@testable import SkilliCore

final class WindowPlacementsTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 25, width: 1512, height: 957)
    private let big = CGRect(x: 1512, y: -300, width: 2560, height: 1415)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let editor = "com.example.Editor"
    private let browser = "com.example.Browser"

    private func placed(_ layout: WindowLayout, on display: String = "ext", title: String = "", document: String? = nil,
                        rank: Int = 0, with: [String] = [], how: WindowPlacements.Placement.How = .hand,
                        daysAgo: Double = 0) -> WindowPlacements.Placement {
        let fraction = layout.sizes[0]
        return .init(place: .init(fraction: fraction, layout: layout.rawValue), display: display, title: title, document: document,
                     rank: rank, with: with, how: how, at: now.addingTimeInterval(-daysAgo * 86_400))
    }

    func testANamedPlaceIsKeptByNameAndAFreeFrameInProportion() {
        let half = WindowLayout.leftTwoThirds.frame(in: big, gap: 12)!
        // A hand's drag a few points off is still the left two thirds.
        let dragged = half.offsetBy(dx: 9, dy: -6)
        let place = WindowPlacements.Place.of(dragged, in: big, gap: 12)
        XCTAssertNotNil(place.layout)
        XCTAssertEqual(place.frame(in: big, gap: 12), half)
        // On the laptop, the same place with its gap.
        XCTAssertEqual(place.frame(in: laptop, gap: 12), WindowLayout.leftTwoThirds.frame(in: laptop, gap: 12))

        let free = CGRect(x: big.minX + 640, y: big.minY + 200, width: 1280, height: 700)
        let freePlace = WindowPlacements.Place.of(free, in: big)
        XCTAssertNil(freePlace.layout)
        XCTAssertEqual(freePlace.frame(in: big).minX, free.minX, accuracy: 3)
        XCTAssertEqual(freePlace.frame(in: big).width, free.width, accuracy: 3)
        let onLaptop = freePlace.frame(in: laptop)
        XCTAssertEqual(onLaptop.width / laptop.width, free.width / big.width, accuracy: 0.01)
    }

    func testTheUsualPlaceWinsAndOldHabitsFade() {
        var book = WindowPlacements()
        let displays = ["built-in", "ext"]
        for _ in 0..<3 { book.record(placed(.leftTwoThirds, daysAgo: 1), bundleID: editor, displays: displays) }
        // Long ago, more often: it fades.
        for _ in 0..<5 { book.record(placed(.rightHalf, daysAgo: 120), bundleID: editor, displays: displays) }
        let choices = book.choices(for: .init(bundleID: editor, title: ""), displays: displays, at: now)
        XCTAssertEqual(choices.first?.place.layout, WindowLayout.leftTwoThirds.rawValue)
        XCTAssertEqual(choices.first?.count, 3)
        XCTAssertGreaterThan(choices.first?.share ?? 0, 0.7)
        // Another app, another set of displays: nothing.
        XCTAssertTrue(book.choices(for: .init(bundleID: browser, title: ""), displays: displays, at: now).isEmpty)
    }

    func testAKeyCountsDoubleAndTheAppsBesideItCount() {
        var book = WindowPlacements()
        let displays = ["ext"]
        book.record(placed(.leftHalf, with: [browser]), bundleID: editor, displays: displays)
        book.record(placed(.maximize, with: []), bundleID: editor, displays: displays)
        // With the browser beside it: the half; alone: filled.
        let beside = book.choices(for: .init(bundleID: editor, title: "", with: [browser]), displays: displays, at: now)
        XCTAssertEqual(beside.first?.place.layout, WindowLayout.leftHalf.rawValue)
        let alone = book.choices(for: .init(bundleID: editor, title: "", with: []), displays: displays, at: now)
        XCTAssertEqual(alone.first?.place.layout, WindowLayout.maximize.rawValue)
        // Placed with ✦W once beats twice by hand.
        var keyed = WindowPlacements()
        keyed.record(placed(.rightThird), bundleID: editor, displays: displays)
        keyed.record(placed(.rightThird), bundleID: editor, displays: displays)
        keyed.record(placed(.leftThird, how: .key), bundleID: editor, displays: displays)
        keyed.record(placed(.leftThird, how: .key), bundleID: editor, displays: displays)
        keyed.record(placed(.leftThird, how: .key), bundleID: editor, displays: displays)
        XCTAssertEqual(keyed.choices(for: .init(bundleID: editor, title: ""), displays: displays, at: now).first?.place.layout,
                       WindowLayout.leftThird.rawValue)
    }

    func testTitlesTellAnAppsWindowsApart() {
        var book = WindowPlacements()
        let displays = ["ext"]
        for _ in 0..<2 {
            book.record(placed(.leftHalf, title: "Inbox — Work — Example Browser"), bundleID: browser, displays: displays)
            book.record(placed(.rightHalf, title: "Recipes — Personal — Example Browser"), bundleID: browser, displays: displays)
        }
        let work = book.choices(for: .init(bundleID: browser, title: "Calendar — Work — Example Browser"), displays: displays, at: now)
        XCTAssertEqual(work.first?.place.layout, WindowLayout.leftHalf.rawValue)
        let personal = book.choices(for: .init(bundleID: browser, title: "News — Personal — Example Browser"), displays: displays, at: now)
        XCTAssertEqual(personal.first?.place.layout, WindowLayout.rightHalf.rawValue)
        // The words every title has tell nothing.
        XCTAssertEqual(WindowPlacements.commonWords(["Inbox — Work — Example Browser", "Recipes — Personal — Example Browser"]),
                       ["example", "browser"])
        XCTAssertEqual(WindowPlacements.words("Plan 2026 — v2.txt"), ["plan", "txt"])
    }

    func testTheSameFileWinsAndUntitledWindowsGoByRank() {
        var book = WindowPlacements()
        let displays = ["ext"]
        book.record(placed(.leftHalf, title: "Notes", document: "file:///Users/me/a.txt"), bundleID: editor, displays: displays)
        book.record(placed(.rightHalf, title: "Notes", document: "file:///Users/me/b.txt"), bundleID: editor, displays: displays)
        let b = book.choices(for: .init(bundleID: editor, title: "Notes", document: "file:///Users/me/b.txt"), displays: displays, at: now)
        XCTAssertEqual(b.first?.place.layout, WindowLayout.rightHalf.rawValue)

        var untitled = WindowPlacements()
        untitled.record(placed(.leftHalf, rank: 0), bundleID: editor, displays: displays)
        untitled.record(placed(.rightHalf, rank: 1), bundleID: editor, displays: displays)
        let second = untitled.choices(for: .init(bundleID: editor, title: "", rank: 1), displays: displays, at: now)
        XCTAssertEqual(second.first?.place.layout, WindowLayout.rightHalf.rawValue)
    }

    func testOtherDisplaysStandInAtHalfTheirWeight() {
        var book = WindowPlacements()
        book.record(placed(.leftTwoThirds, on: "ext"), bundleID: editor, displays: ["built-in", "ext"])
        // The big display on another desk: an external one stands in.
        let elsewhere = book.choices(for: .init(bundleID: editor, title: ""), displays: ["built-in", "other"], at: now)
        XCTAssertEqual(elsewhere.first?.display, "other")
        XCTAssertEqual(elsewhere.first?.place.layout, WindowLayout.leftTwoThirds.rawValue)
        // The laptop alone: an external display's place does not go there.
        XCTAssertTrue(book.choices(for: .init(bundleID: editor, title: ""), displays: ["built-in"], at: now).isEmpty)
    }

    func testKeptSmall() {
        var book = WindowPlacements()
        for day in 0..<60 { book.record(placed(.leftHalf, daysAgo: Double(day)), bundleID: editor, displays: ["ext"]) }
        book.record(placed(.rightHalf), bundleID: browser, displays: ["ext"])
        XCTAssertEqual(book.entries.values.map(\.count).max(), WindowPlacements.kept)
        XCTAssertEqual(book.apps, [editor, browser])
        // Written and read back the same.
        let data = try! JSONEncoder().encode(book)
        XCTAssertEqual(try JSONDecoder().decode(WindowPlacements.self, from: data), book)
    }

    func testDisplayKeys() {
        let builtIn = DisplayFingerprint(name: "Built-in", vendor: 1552, model: 41_000, serial: 0, builtIn: true, uuid: "A")
        let external = DisplayFingerprint(name: "Example 27", vendor: 4268, model: 30_787, serial: 16_780_800, builtIn: false, uuid: "B")
        let noSerial = DisplayFingerprint(name: "Example 24", vendor: 4268, model: 1, serial: 0, builtIn: false, uuid: "C")
        XCTAssertEqual(WindowPlacements.displayKey(builtIn), WindowPlacements.builtIn)
        XCTAssertEqual(WindowPlacements.displayKey(external), "4268-30787-16780800")
        XCTAssertEqual(WindowPlacements.displayKey(noSerial), "4268-1-C")
        XCTAssertEqual(WindowPlacements.displaysKey(["b", "a"]), WindowPlacements.displaysKey(["a", "b"]))
    }

    func testArrangeGivesAnAppsWindowsDifferentPlacesAndLeavesTheUnknown() {
        var book = WindowPlacements()
        let displays = [WindowArrangement.Display(key: "ext", visible: big)]
        for _ in 0..<2 {
            book.record(placed(.leftHalf, title: "Inbox — Work"), bundleID: browser, displays: ["ext"])
            book.record(placed(.rightHalf, title: "Recipes — Personal"), bundleID: browser, displays: ["ext"])
            book.record(placed(.leftHalf), bundleID: editor, displays: ["ext"])
        }
        let somewhere = CGRect(x: big.minX + 100, y: big.minY + 100, width: 800, height: 600)
        let items: [WindowArrangement.Item] = [
            .init(window: .init(bundleID: browser, title: "Mail — Personal"), frame: somewhere),
            .init(window: .init(bundleID: browser, title: "Mail — Work"), frame: somewhere),
            .init(window: .init(bundleID: editor, title: "main.swift"), frame: somewhere),
            .init(window: .init(bundleID: "com.example.Unknown", title: ""), frame: somewhere)
        ]
        let targets = WindowArrangement.targets(of: items, on: displays, placements: book, gap: 0, at: now)
        XCTAssertEqual(targets[0], WindowLayout.rightHalf.frame(in: big))
        XCTAssertEqual(targets[1], WindowLayout.leftHalf.frame(in: big))
        // Another app may share a place: the user stacks them.
        XCTAssertEqual(targets[2], WindowLayout.leftHalf.frame(in: big))
        XCTAssertNil(targets[3])

        // Two windows, one place learned: the other stays.
        var one = WindowPlacements()
        one.record(placed(.maximize), bundleID: editor, displays: ["ext"])
        let two = WindowArrangement.targets(of: [items[2], items[2]], on: displays, placements: one, at: now)
        XCTAssertEqual(two.compactMap { $0 }.count, 1)
    }

    func testASavedLayoutForWhatIsOpenComesFirst() {
        let fingerprint = DisplayFingerprint(name: "Example 27", vendor: 4268, model: 30_787, serial: 16_780_800, builtIn: false, uuid: "B")
        let display = LayoutDisplay(fingerprint: fingerprint, frame: big, visible: big)
        func layout(_ name: String, _ apps: [String], saved: Double) -> SavedWindowLayout {
            SavedWindowLayout(id: name, name: name, windows: apps.map { .init(bundleID: $0, appName: $0, title: "", index: 0, frame: .zero) },
                              displays: [display], saved: Date(timeIntervalSince1970: saved))
        }
        let layouts = [layout("Old", [editor, browser], saved: 1), layout("Coding", [editor, browser], saved: 2), layout("Mail", [browser], saved: 3)]
        XCTAssertEqual(WindowArrangement.layout(for: [editor, browser], among: layouts, on: [display])?.name, "Coding")
        XCTAssertNil(WindowArrangement.layout(for: [editor], among: layouts, on: [display]))
        // One that would open a file or a link: not for Arrange.
        var opening = layout("Opening", [editor], saved: 4)
        opening.windows[0].opens = "https://example.com"
        var showing = layout("Showing", [editor], saved: 5)
        showing.windows[0].document = "file:///Users/me/a.txt"
        XCTAssertNil(WindowArrangement.layout(for: [editor], among: [opening, showing], on: [display]))
        XCTAssertEqual(WindowArrangement.layout(for: [editor], documents: ["file:///Users/me/a.txt"], among: [opening, showing], on: [display])?.name,
                       "Showing")
        // Another display: not that layout.
        var other = display
        other.fingerprint.serial = 1
        other.fingerprint.uuid = "Z"
        XCTAssertNil(WindowArrangement.layout(for: [browser], among: layouts, on: [other]))
    }
}
