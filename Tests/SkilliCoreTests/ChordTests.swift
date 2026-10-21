import XCTest
@testable import SkilliCore

final class ChordTests: XCTestCase {
    func testParsesHyperWithNamedKey() throws {
        XCTAssertEqual(try Chord(parsing: "hyper+space"), Chord(.named(.space), .hyper))
    }

    func testParsesModifiersInAnyOrderAndCase() throws {
        XCTAssertEqual(try Chord(parsing: "Shift+CMD+K"), Chord(.character("k"), [.command, .shift]))
    }

    func testParsesBareCharacterAndAliases() throws {
        XCTAssertEqual(try Chord(parsing: "u"), Chord(.character("u")))
        XCTAssertEqual(try Chord(parsing: "esc"), Chord(.named(.escape)))
        XCTAssertEqual(try Chord(parsing: "alt+enter"), Chord(.named(.return), .option))
    }

    func testRejectsMalformedSpecs() {
        XCTAssertThrowsError(try Chord(parsing: "")) { XCTAssertEqual($0 as? ChordParseError, .empty) }
        XCTAssertThrowsError(try Chord(parsing: "cmd+")) { XCTAssertEqual($0 as? ChordParseError, .missingKey("cmd+")) }
        XCTAssertThrowsError(try Chord(parsing: "meta+k")) { XCTAssertEqual($0 as? ChordParseError, .unknownModifier("meta")) }
        XCTAssertThrowsError(try Chord(parsing: "cmd+banana")) { XCTAssertEqual($0 as? ChordParseError, .unknownKey("banana")) }
    }

    func testParsesSequences() throws {
        XCTAssertEqual(
            try Chord.sequence("hyper+k  u"),
            [Chord(.character("k"), .hyper), Chord(.character("u"))]
        )
    }

    func testSpecRoundTrips() throws {
        for spec in ["hyper+k", "ctrl+opt+shift+cmd+k", "cmd+shift+k", "space", "hyper+space", "cmd+plus", "opt+return", "u", "ctrl+pageup"] {
            let chord = try Chord(parsing: spec)
            XCTAssertEqual(try Chord(parsing: chord.spec), chord, spec)
        }
        XCTAssertEqual(try Chord(parsing: "hyper+k").spec, "hyper+k")
        XCTAssertEqual(try Chord.spec(Chord.sequence("hyper+k u")), "hyper+k u")
        XCTAssertEqual(try Chord(parsing: "cmd+plus"), Chord(.character("+"), .command))
    }

    func testKeycapsSplitModifiersAndKey() throws {
        XCTAssertEqual(try Chord(parsing: "hyper+k").keycaps, ["✦", "K"])
        XCTAssertEqual(try Chord(parsing: "cmd+shift+k").keycaps, ["⇧", "⌘", "K"])
        XCTAssertEqual(try Chord(parsing: "space").keycaps, ["Space"])
    }

    func testDescriptionUsesMacSymbols() throws {
        XCTAssertEqual(try Chord(parsing: "cmd+shift+k").description, "⇧⌘K")
        XCTAssertEqual(try Chord(parsing: "hyper+space").description, "✦ Space")
        XCTAssertEqual(try Chord(parsing: "hyper+u").description, "✦ U")
        XCTAssertEqual(try Chord(parsing: "t").description, "T")
    }
    /// 2026-10-16: the same key twice in a chain (⌘Space Space), with ⌘
    /// kept down or let go: what is still held from the first chord does
    /// not count on the next ones, nor Hyper.
    func testInChainDropsWhatIsStillHeldFromTheFirstChord() throws {
        let commandSpace = try Chord(parsing: "cmd+space")
        XCTAssertEqual(try Chord(parsing: "cmd+space").inChain(after: commandSpace), try Chord(parsing: "space"))
        XCTAssertEqual(try Chord(parsing: "space").inChain(after: commandSpace), try Chord(parsing: "space"))
        XCTAssertEqual(try Chord(parsing: "hyper+y").inChain(after: try Chord(parsing: "hyper+k")), try Chord(parsing: "y"))
        XCTAssertEqual(try Chord(parsing: "hyper+y").inChain(after: commandSpace), try Chord(parsing: "y"), "Hyper never counts in a chain")
        XCTAssertEqual(try Chord(parsing: "cmd+u").inChain(after: try Chord(parsing: "cmd+shift+k")), try Chord(parsing: "u"), "⇧ let go, ⌘ kept")
        XCTAssertEqual(try Chord(parsing: "ctrl+cmd+x").inChain(after: try Chord(parsing: "cmd+k")), try Chord(parsing: "ctrl+x"), "a modifier added still counts")
        XCTAssertEqual(try Chord(parsing: "shift+u").inChain(after: try Chord(parsing: "hyper+k")), try Chord(parsing: "u"))
    }

    func testChainIsWrittenAsTheEngineMatchesIt() throws {
        XCTAssertEqual(Chord.spec(Chord.chain(try Chord.sequence("cmd+space cmd+space"))), "cmd+space space")
        XCTAssertEqual(Chord.spec(Chord.chain(try Chord.sequence("cmd+space space"))), "cmd+space space")
        XCTAssertEqual(Chord.spec(Chord.chain(try Chord.sequence("hyper+k hyper+y"))), "hyper+k y")
        XCTAssertEqual(Chord.spec(Chord.chain(try Chord.sequence("cmd+k cmd+j cmd+x"))), "cmd+k j x")
        XCTAssertEqual(Chord.spec(Chord.chain(try Chord.sequence("opt+cmd+space"))), "opt+cmd+space", "one chord stays as it is")
        XCTAssertEqual(Chord.chain([]), [])
    }
}
