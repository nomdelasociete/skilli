@testable import SkilliCore
import XCTest

final class LauncherFooterTests: XCTestCase {
    private func shown(_ hints: [(label: String, key: String)]) -> [String] {
        hints.map { "\($0.label) \($0.key)" }
    }

    func testTheFooterSaysTheRowsOwnKeyThenTabThenActions() {
        XCTAssertEqual(shown(LauncherFooter.hints(main: "Paste", tab: .own("By Meaning"))), ["Paste ↩", "By Meaning ⇥", "Actions ⌘K"])
        XCTAssertEqual(shown(LauncherFooter.hints(main: "Open", tab: .ask)), ["Open ↩", "Ask ⇥", "Actions ⌘K"])
        // ⇥ that only does what ⌘K does is not said twice.
        XCTAssertEqual(shown(LauncherFooter.hints(main: "Quit", tab: .actions)), ["Quit ↩", "Actions ⌘K"])
        XCTAssertEqual(shown(LauncherFooter.hints(main: "Join", tab: .nothing)), ["Join ↩", "Actions ⌘K"])
    }

    func testNoRowNoReturnNorActions() {
        // "No words match: ⇥ searches by meaning": ⇥ alone.
        XCTAssertEqual(shown(LauncherFooter.hints(main: nil, tab: .own("By Meaning"))), ["By Meaning ⇥"])
        XCTAssertTrue(LauncherFooter.hints(main: nil, tab: .nothing).isEmpty)
    }

    func testTabNeverAsksInAMode() {
        // A skillie's password argument typed, ⇥: its actions, never Ask.
        XCTAssertEqual(LauncherTab.of(inMode: true, own: nil, hasRow: true, typed: true, canAsk: true), .actions)
        XCTAssertEqual(LauncherTab.of(inMode: true, own: nil, hasRow: false, typed: true, canAsk: true), .nothing)
        XCTAssertEqual(LauncherTab.of(inMode: true, own: "By Feeling", hasRow: false, typed: true, canAsk: true), .own("By Feeling"))
        XCTAssertEqual(LauncherTab.of(inMode: true, own: "Processes", hasRow: true, typed: false, canAsk: false), .own("Processes"))
    }

    func testTabAsksAboutWordsOutsideTheModes() {
        XCTAssertEqual(LauncherTab.of(inMode: false, own: nil, hasRow: true, typed: true, canAsk: true), .ask)
        XCTAssertEqual(LauncherTab.of(inMode: false, own: nil, hasRow: true, typed: false, canAsk: true), .nothing)
        XCTAssertEqual(LauncherTab.of(inMode: false, own: nil, hasRow: true, typed: true, canAsk: false), .nothing)
        XCTAssertEqual(LauncherTab.ask.hint, "Ask")
        XCTAssertNil(LauncherTab.actions.hint)
    }

    func testEscapeGoesBackOneStepAtATime() {
        XCTAssertEqual(LauncherEscape.of(showingActions: true, unfolded: true, inMode: true, back: "kill"), .closeActions)
        XCTAssertEqual(LauncherEscape.of(showingActions: false, unfolded: true, inMode: true, back: "kill"), .fold)
        XCTAssertEqual(LauncherEscape.of(showingActions: false, unfolded: false, inMode: true, back: "kill"), .root("kill"))
        XCTAssertEqual(LauncherEscape.of(showingActions: false, unfolded: false, inMode: true, back: ""), .root(""))
        // Opened straight into the mode (✦C): back is the app.
        XCTAssertEqual(LauncherEscape.of(showingActions: false, unfolded: false, inMode: true, back: nil), .close)
        XCTAssertEqual(LauncherEscape.of(showingActions: false, unfolded: false, inMode: false, back: "kill"), .close)
    }
}
