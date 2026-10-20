import CoreGraphics
import XCTest
@testable import SkilliCore

final class WindowLayoutPlanTests: XCTestCase {
    private func window(_ title: String, _ index: Int) -> SavedWindowLayout.Window {
        .init(bundleID: "com.apple.TextEdit", appName: "TextEdit", title: title, index: index, frame: .zero)
    }

    func testTitlesFirstThenRank() {
        let saved = [window("Notes.txt", 0), window("Plan.txt", 1), window("", 2)]
        XCTAssertEqual(WindowLayoutPlan.match(saved: saved, current: ["Plan.txt", "Other", "Notes.txt"]), [2, 0, 1])
        // Fewer windows now: the rest stays unmatched.
        XCTAssertEqual(WindowLayoutPlan.match(saved: saved, current: ["Untitled"]), [0, nil, nil])
        XCTAssertEqual(WindowLayoutPlan.match(saved: [], current: ["A"]), [])
    }

    func testAFrameOnAGoneDisplayComesToTheMainOne() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: -300, width: 2560, height: 1440)
        let onExternal = CGRect(x: 1512, y: -300, width: 1280, height: 1440)
        XCTAssertEqual(WindowLayoutPlan.fit(onExternal, savedScreens: [main, external], screens: [main, external], main: main), onExternal)
        let fitted = WindowLayoutPlan.fit(onExternal, savedScreens: [main, external], screens: [main], main: main)
        XCTAssertEqual(fitted, CGRect(x: 0, y: 0, width: 756, height: 982))
    }

    func testSaveNameAndSummary() {
        XCTAssertEqual(WindowLayoutPlan.saveName("save layout Coding"), "Coding")
        XCTAssertEqual(WindowLayoutPlan.saveName("Enregistrer disposition  matin "), "matin")
        XCTAssertNil(WindowLayoutPlan.saveName("layout coding"))
        let layout = SavedWindowLayout(id: "coding", name: "Coding", windows: [
            .init(bundleID: "a", appName: "Xcode", title: "", index: 0, frame: .zero),
            .init(bundleID: "b", appName: "Safari", title: "", index: 0, frame: .zero),
            .init(bundleID: "b", appName: "Safari", title: "", index: 1, frame: .zero),
            .init(bundleID: "c", appName: "Notes", title: "", index: 0, frame: .zero),
            .init(bundleID: "d", appName: "Slack", title: "", index: 0, frame: .zero)
        ])
        XCTAssertEqual(layout.summary, "Xcode, Safari and 2 more")
    }

    // MARK: - Displays known by who they are

    private let builtIn = DisplayFingerprint(name: "Built-in Retina Display", vendor: 1552, model: 41054, serial: 1, builtIn: true, uuid: "B")
    private let samsung = DisplayFingerprint(name: "SAMSUNG", vendor: 19501, model: 30787, serial: 16_780_800, made: "2025-W1", builtIn: false, uuid: "S")

    private func display(_ fingerprint: DisplayFingerprint, _ frame: CGRect, menuBar: CGFloat = 0) -> LayoutDisplay {
        LayoutDisplay(fingerprint: fingerprint, frame: frame,
                      visible: CGRect(x: frame.minX, y: frame.minY + menuBar, width: frame.width, height: frame.height - menuBar))
    }

    func testTheSameFileFirst() {
        var notes = window("Notes", 0)
        notes.document = "file:///Users/me/Notes.txt"
        var plan = window("Plan", 1)
        plan.document = "file:///Users/me/Plan.txt"
        // Titles changed, ranks swapped: the files still tell them apart.
        XCTAssertEqual(WindowLayoutPlan.match(saved: [notes, plan], current: ["Plan — edited", "Notes — edited"],
                                              documents: ["file:///Users/me/Plan.txt", "file:///Users/me/Notes.txt"]), [1, 0])
    }

    func testAWindowKeepsItsPlaceOnItsDisplayWhereverItIsNow() {
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let savedSamsung = display(samsung, CGRect(x: -3840, y: -2160, width: 3840, height: 2160), menuBar: 30)
        let layout = SavedWindowLayout(id: "desk", name: "Desk", windows: [
            .init(bundleID: "x", appName: "Xcode", title: "", index: 0, frame: CGRect(x: -3840, y: -2130, width: 1920, height: 2130), display: 1)
        ], displays: [display(builtIn, main, menuBar: 30), savedSamsung])
        // The Samsung moved to the right of the Mac: same size, same place on it.
        let movedSamsung = display(samsung, CGRect(x: 1800, y: 0, width: 3840, height: 2160), menuBar: 30)
        let moved = WindowLayoutPlan.placement(of: layout, on: [display(builtIn, main, menuBar: 30), movedSamsung])
        XCTAssertEqual(moved.frames, [CGRect(x: 1800, y: 30, width: 1920, height: 2130)])
        XCTAssertEqual(moved.changes, [])
        // At 2560×1440 now: the left half still, proportions kept, and said.
        let smaller = display(samsung, CGRect(x: 1800, y: 0, width: 2560, height: 1440), menuBar: 30)
        let resized = WindowLayoutPlan.placement(of: layout, on: [display(builtIn, main, menuBar: 30), smaller])
        XCTAssertEqual(resized.frames, [CGRect(x: 1800, y: 30, width: 1280, height: 1410)])
        XCTAssertEqual(resized.visible, [smaller.visible])
        XCTAssertEqual(resized.changes, [.resized(display: "SAMSUNG", from: CGSize(width: 3840, height: 2160), to: CGSize(width: 2560, height: 1440))])
        // Not connected: onto the built-in, the left half of it, and said.
        let alone = WindowLayoutPlan.placement(of: layout, on: [display(builtIn, main, menuBar: 30)])
        XCTAssertEqual(alone.frames, [CGRect(x: 0, y: 30, width: 900, height: 1139)])
        XCTAssertEqual(alone.changes, [.standIn(saved: "SAMSUNG", current: "Built-in Retina Display", windows: 1)])
    }

    func testLayoutsSavedBeforeDisplaysStillWork() throws {
        let json = """
        {"id":"coding","name":"Coding","saved":"2026-10-12T10:00:00Z","screens":[[[0,0],[1512,982]]],
         "windows":[{"bundleID":"com.apple.TextEdit","appName":"TextEdit","title":"Notes.txt","index":0,"frame":[[0,0],[756,982]]}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let layout = try decoder.decode(SavedWindowLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.displays, [])
        XCTAssertEqual(layout.windows[0].state, .normal)
        XCTAssertNil(layout.windows[0].display)
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(WindowLayoutPlan.placement(of: layout, on: [display(builtIn, main)]).frames, [CGRect(x: 0, y: 0, width: 756, height: 982)])
    }

    func testANewLayoutKeepsEverythingAndStillWritesItsScreens() throws {
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let layout = SavedWindowLayout(id: "desk", name: "Desk", windows: [
            .init(bundleID: "a", appName: "Notes", title: "", index: 0, frame: main, display: 0, state: .minimized, document: "file:///a.txt")
        ], displays: [display(builtIn, main)], hiddenApps: ["a"], saved: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(layout.screens, [main])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(SavedWindowLayout.self, from: encoder.encode(layout)), layout)
    }

    // MARK: - Files, folders and links a layout opens

    func testWhatALayoutOpensIsKeptAndReadBack() throws {
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let layout = SavedWindowLayout(id: "work", name: "Work", windows: [
            .init(bundleID: "com.apple.Safari", appName: "Safari", title: "github.com/nomdelasociete", index: 0, frame: main,
                  display: 0, opens: "https://github.com/nomdelasociete"),
            .init(bundleID: "com.apple.finder", appName: "Finder", title: "Documents", index: 0, frame: main, display: 0,
                  opens: "file:///Users/me/Documents/"),
            .init(bundleID: "com.apple.TextEdit", appName: "TextEdit", title: "Notes", index: 0, frame: main, display: 0)
        ], displays: [display(builtIn, main)], saved: Date(timeIntervalSince1970: 0))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let read = try decoder.decode(SavedWindowLayout.self, from: encoder.encode(layout))
        XCTAssertEqual(read, layout)
        XCTAssertEqual(read.openings.map(\.appName), ["Safari", "Finder"])
        // Older layouts have none.
        XCTAssertNil(window("Old", 0).opens)
    }

    func testTakenAnewALayoutKeepsWhatItOpensOnTheDisplaysThereAre() {
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let samsungThen = display(samsung, CGRect(x: 1800, y: 0, width: 3840, height: 2160), menuBar: 30)
        var page = SavedWindowLayout.Window(bundleID: "com.apple.Safari", appName: "Safari", title: "github.com", index: 0,
                                            frame: CGRect(x: 1800, y: 30, width: 1920, height: 2130), display: 1, opens: "https://github.com")
        let layout = SavedWindowLayout(id: "w", name: "W", windows: [window("Notes", 0), page], displays: [display(builtIn, main), samsungThen])
        // The Samsung now on the left of the Mac, and first.
        let samsungNow = display(samsung, CGRect(x: -3840, y: 0, width: 3840, height: 2160), menuBar: 30)
        let kept = layout.openings(on: [samsungNow, display(builtIn, main)])
        page.frame = CGRect(x: -3840, y: 30, width: 1920, height: 2130)
        page.display = 0
        XCTAssertEqual(kept, [page])
    }

    func testLinksAsTypedAndWhatTheyAreCalled() {
        XCTAssertEqual(LayoutOpening.link("github.com/nomdelasociete")?.absoluteString, "https://github.com/nomdelasociete")
        XCTAssertEqual(LayoutOpening.link(" https://www.apple.com/fr/ ")?.absoluteString, "https://www.apple.com/fr/")
        XCTAssertEqual(LayoutOpening.link("http://127.0.0.1:8080/page")?.absoluteString, "http://127.0.0.1:8080/page")
        XCTAssertNil(LayoutOpening.link("file:///etc/passwd"))
        XCTAssertNil(LayoutOpening.link("javascript:alert(1)"))
        XCTAssertNil(LayoutOpening.link("two words"))
        XCTAssertNil(LayoutOpening.link("notes"))
        XCTAssertEqual(LayoutOpening.kind(of: "https://github.com"), .link)
        XCTAssertEqual(LayoutOpening.kind(of: "file:///Users/me/Documents/"), .folder)
        XCTAssertEqual(LayoutOpening.kind(of: "file:///Users/me/Notes.txt"), .file)
        XCTAssertEqual(LayoutOpening.name(of: "https://www.github.com/nomdelasociete"), "github.com/nomdelasociete")
        XCTAssertEqual(LayoutOpening.name(of: "https://apple.com/"), "apple.com")
        XCTAssertEqual(LayoutOpening.name(of: "file:///Users/me/Documents/"), "Documents")
        XCTAssertEqual(LayoutOpening.name(of: "file:///Users/me/Notes%20du%20jour.txt"), "Notes du jour.txt")
    }

    func testAWindowShowsWhatItOpened() {
        // The same file, however the app writes its URL.
        XCTAssertTrue(LayoutOpening.shows("file:///Users/me/Notes.txt", title: "Anything", document: "file:///Users/me/./Notes.txt"))
        // Finder says no document: the folder's name as its title.
        XCTAssertTrue(LayoutOpening.shows("file:///Users/me/Documents/", title: "Documents", document: nil))
        XCTAssertTrue(LayoutOpening.shows("file:///Users/me/Notes.txt", title: "Notes", document: nil))
        XCTAssertFalse(LayoutOpening.shows("file:///Users/me/Notes.txt", title: "Plan", document: "file:///Users/me/Plan.txt"))
        // A page: the same address, a trailing slash aside; never by title.
        XCTAssertTrue(LayoutOpening.shows("https://github.com/x", title: "", document: "https://github.com/x/"))
        XCTAssertFalse(LayoutOpening.shows("https://github.com/x", title: "github.com/x", document: nil))
    }

    func testWindowsAFileOrLinkOpenedAreTheirsTheOthersMatchedAmongTheRest() {
        var page = window("github.com/x", 0)
        page.opens = "https://github.com/x"
        let mail = window("Inbox", 1)
        let other = window("Docs", 2)
        // The page opened in the window now second; the others by title.
        XCTAssertEqual(WindowLayoutPlan.match(saved: [page, mail, other], current: ["Docs", "GitHub — x", "Inbox"],
                                              documents: [nil, nil, nil], decided: [0: 1]), [1, 2, 0])
        // It opened nowhere: left without a window, never someone else's.
        XCTAssertEqual(WindowLayoutPlan.match(saved: [page, mail], current: ["Inbox", "Something"], documents: [nil, nil], decided: [:]), [nil, 0])
    }

    func testAWindowTooLargeStaysOnItsDisplay() {
        let visible = CGRect(x: 0, y: 30, width: 1800, height: 1139)
        XCTAssertEqual(WindowLayoutPlan.kept(CGRect(x: 1200, y: 30, width: 900, height: 1139), inside: visible),
                       CGRect(x: 900, y: 30, width: 900, height: 1139))
        // Larger than the display: its top left corner stays on it.
        XCTAssertEqual(WindowLayoutPlan.kept(CGRect(x: 100, y: 0, width: 2000, height: 1300), inside: visible).origin, CGPoint(x: 0, y: 30))
    }

    func testTheCardSaysWhatWasAdapted() {
        XCTAssertEqual(LayoutReport(name: "Desk", placed: 3, total: 3).message, "“Desk”: 3 windows in place.")
        let report = LayoutReport(name: "Desk", placed: 4, total: 5, changes: [
            .resized(display: "SAMSUNG", from: CGSize(width: 3840, height: 2160), to: CGSize(width: 2560, height: 1440)),
            .standIn(saved: "LG", current: "Built-in Retina Display", windows: 2),
            .larger(app: "Xcode"),
            .notOpen(app: "Notes", windows: 1)
        ])
        XCTAssertEqual(report.message, """
        “Desk”: 4 of 5 windows in place, adapted:

        - SAMSUNG: 3840×2160 → 2560×1440, proportions kept
        - LG not connected: its 2 windows on Built-in Retina Display, proportions kept
        - Xcode keeps its window a little larger than saved (its minimum size)
        - Notes: a window did not open
        """)
        XCTAssertEqual(LayoutReport(name: "Desk", placed: 0, total: 1, changes: [.notInstalled(app: "Zed")]).message,
                       "“Desk”: 0 of 1 windows in place:\n\n- Zed is not installed")
    }

    func testOnlyAWindowNotPutBackIsSaid() {
        XCTAssertFalse(LayoutReport(name: "Desk", placed: 3, total: 3).hasFailures)
        XCTAssertFalse(LayoutReport(name: "Desk", placed: 3, total: 3, changes: [.larger(app: "Slack")]).hasFailures, "adapted: seen, not said")
        XCTAssertTrue(LayoutReport(name: "Desk", placed: 2, total: 3).hasFailures, "a window refused to move")
        XCTAssertTrue(LayoutReport(name: "Desk", placed: 2, total: 3, changes: [.notOpen(app: "Mail", windows: 1)]).hasFailures)
        XCTAssertTrue(LayoutReport(name: "Desk", placed: 3, total: 3, changes: [.notInstalled(app: "Figma")]).hasFailures)
    }
}
