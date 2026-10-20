import XCTest
@testable import SkilliCore

final class BindingEngineTests: XCTestCase {
    private enum Action: Hashable, Sendable {
        case launcher
        case upper
        case lower
    }

    private let start = ContinuousClock.now

    private func makeEngine() throws -> BindingEngine<Action> {
        var engine = BindingEngine<Action>(timeout: .seconds(2))
        try engine.bind(Chord.sequence("hyper+space"), label: "Launcher", to: .launcher)
        try engine.bind(Chord.sequence("hyper+k u"), label: "Upper", to: .upper)
        try engine.bind(Chord.sequence("hyper+k l"), label: "Lower", to: .lower)
        try engine.labelGroup(Chord.sequence("hyper+k"), "Text")
        return engine
    }

    private func chord(_ spec: String) throws -> Chord {
        try Chord(parsing: spec)
    }

    func testSingleChordFires() throws {
        var engine = try makeEngine()
        XCTAssertEqual(engine.handle(try chord("hyper+space"), at: start), .fire(.launcher))
        XCTAssertFalse(engine.isPending)
    }

    func testUnboundChordPassesThrough() throws {
        var engine = try makeEngine()
        XCTAssertEqual(engine.handle(try chord("cmd+c"), at: start), .passThrough)
    }

    func testSequenceShowsHintsInDeclarationOrderThenFires() throws {
        var engine = try makeEngine()
        let first = engine.handle(try chord("hyper+k"), at: start)
        XCTAssertEqual(first, .pending(
            prefix: [try chord("hyper+k")],
            title: "Text",
            hints: [
                .init(chord: try chord("u"), label: "Upper", isGroup: false),
                .init(chord: try chord("l"), label: "Lower", isGroup: false)
            ]
        ))
        XCTAssertTrue(engine.isPending)
        XCTAssertEqual(engine.handle(try chord("u"), at: start + .milliseconds(300)), .fire(.upper))
        XCTAssertFalse(engine.isPending)
    }

    func testUnknownKeyCancelsPendingSequence() throws {
        var engine = try makeEngine()
        _ = engine.handle(try chord("hyper+k"), at: start)
        XCTAssertEqual(engine.handle(try chord("x"), at: start), .cancelled)
        XCTAssertFalse(engine.isPending)
        // Back at the root afterwards.
        XCTAssertEqual(engine.handle(try chord("u"), at: start), .passThrough)
    }

    func testTimeoutDropsPendingSequence() throws {
        var engine = try makeEngine()
        _ = engine.handle(try chord("hyper+k"), at: start)
        XCTAssertFalse(engine.expireIfNeeded(at: start + .seconds(1)))
        XCTAssertTrue(engine.expireIfNeeded(at: start + .seconds(2)))
        XCTAssertFalse(engine.isPending)
    }

    func testExpiredSequenceTreatsNextKeyFromRoot() throws {
        var engine = try makeEngine()
        _ = engine.handle(try chord("hyper+k"), at: start)
        XCTAssertEqual(engine.handle(try chord("u"), at: start + .seconds(5)), .passThrough)
    }

    func testGroupLabelAppearsInHints() throws {
        var engine = BindingEngine<Action>()
        try engine.bind(Chord.sequence("hyper+k t u"), label: "Upper", to: .upper)
        try engine.labelGroup(Chord.sequence("hyper+k t"), "Transform")
        let outcome = engine.handle(try chord("hyper+k"), at: start)
        XCTAssertEqual(outcome, .pending(
            prefix: [try chord("hyper+k")],
            title: nil,
            hints: [.init(chord: try chord("t"), label: "Transform", isGroup: true)]
        ))
    }

    func testRejectsConflictingBindings() throws {
        var engine = BindingEngine<Action>()
        try engine.bind(Chord.sequence("hyper+k"), label: "K", to: .upper)
        XCTAssertThrowsError(try engine.bind(Chord.sequence("hyper+k u"), label: "U", to: .lower)) {
            XCTAssertEqual($0 as? BindingEngine<Action>.BindingError, .conflict([try! self.chord("hyper+k")]))
        }

        var other = BindingEngine<Action>()
        try other.bind(Chord.sequence("hyper+k u"), label: "U", to: .lower)
        XCTAssertThrowsError(try other.bind(Chord.sequence("hyper+k"), label: "K", to: .upper))
        XCTAssertThrowsError(try other.bind(Chord.sequence("hyper+k u"), label: "U again", to: .upper))
    }

    func testRejectsLabelForUnknownGroup() {
        var engine = BindingEngine<Action>()
        XCTAssertThrowsError(try engine.labelGroup(Chord.sequence("hyper+k"), "Nope"))
    }
    /// ⌘Space then Space runs whether ⌘ is let go before the second Space
    /// or kept down; saved either way, it is one shortcut.
    func testSameKeyTwiceRunsWithTheModifierHeldOrLetGo() throws {
        var engine = BindingEngine<Action>()
        try engine.bind(Chord.sequence("cmd+space space"), label: "Launcher", to: .launcher)
        XCTAssertEqual(engine.handle(try chord("cmd+space"), at: start), .pending(prefix: [try chord("cmd+space")], title: nil,
                                                                                  hints: [.init(chord: try chord("space"), label: "Launcher", isGroup: false)]))
        XCTAssertEqual(engine.handle(try chord("cmd+space"), at: start), .fire(.launcher), "⌘ kept down")
        _ = engine.handle(try chord("cmd+space"), at: start)
        XCTAssertEqual(engine.handle(try chord("space"), at: start), .fire(.launcher), "⌘ let go")

        var saved = BindingEngine<Action>()
        try saved.bind(Chord.sequence("cmd+space cmd+space"), label: "Launcher", to: .launcher)
        _ = saved.handle(try chord("cmd+space"), at: start)
        XCTAssertEqual(saved.handle(try chord("space"), at: start), .fire(.launcher), "a chain saved with ⌘ held runs let go too")
        XCTAssertThrowsError(try saved.bind(Chord.sequence("cmd+space space"), label: "Again", to: .upper), "the same shortcut")
    }

    func testHyperHeldThroughAChainDoesNotCount() throws {
        var engine = try makeEngine()
        _ = engine.handle(try chord("hyper+k"), at: start)
        XCTAssertEqual(engine.handle(try chord("hyper+u"), at: start), .fire(.upper))
    }

    /// The first chord alone still fires its own binding: a binding is
    /// never both an action and the start of a chain.
    func testOneChordCannotAlsoStartAChain() throws {
        var engine = BindingEngine<Action>()
        try engine.bind(Chord.sequence("cmd+space"), label: "Launcher", to: .launcher)
        XCTAssertThrowsError(try engine.bind(Chord.sequence("cmd+space space"), label: "Upper", to: .upper))
    }
}
