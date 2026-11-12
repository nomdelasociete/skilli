@testable import SkilliCore
import XCTest

final class LauncherAliasTests: XCTestCase {
    private let aliases = [LauncherAlias(id: "cmd:emoji", alias: "e", title: "Emoji"),
                           LauncherAlias(id: "cmd:clipboardHistory", alias: "cl", title: "Clipboard History")]

    func testAnAliasThenASpaceOpensItWithTheRest() {
        XCTAssertEqual(LauncherAliases.split("e smile", among: aliases)?.alias.id, "cmd:emoji")
        XCTAssertEqual(LauncherAliases.split("e smile", among: aliases)?.rest, "smile")
        XCTAssertEqual(LauncherAliases.split("E ", among: aliases)?.rest, "")
        XCTAssertEqual(LauncherAliases.split("cl facture", among: aliases)?.alias.title, "Clipboard History")
        XCTAssertNil(LauncherAliases.split("e", among: aliases), "no space yet: e could become emoji")
        XCTAssertNil(LauncherAliases.split("emoji ", among: aliases))
    }

    func testTheAliasAlone() {
        XCTAssertEqual(LauncherAliases.exact("cl", among: aliases)?.id, "cmd:clipboardHistory")
        XCTAssertNil(LauncherAliases.exact("c", among: aliases))
        XCTAssertNil(LauncherAliases.exact("", among: aliases))
    }

    func testAnAliasBelongsToOneItem() {
        let moved = LauncherAliases.setting("E", id: "app:/Applications/Emacs.app", title: "Emacs", in: aliases)
        XCTAssertEqual(moved.first { $0.alias == "e" }?.id, "app:/Applications/Emacs.app")
        XCTAssertFalse(moved.contains { $0.id == "cmd:emoji" })
        let removed = LauncherAliases.setting("", id: "cmd:clipboardHistory", title: "Clipboard History", in: aliases)
        XCTAssertEqual(removed.map(\.id), ["cmd:emoji"])
        // Taken from another item: who had it is known first, to say it.
        XCTAssertEqual(LauncherAliases.holder(of: " E", otherThan: "app:/Applications/Emacs.app", in: aliases)?.title, "Emoji")
        XCTAssertNil(LauncherAliases.holder(of: "e", otherThan: "cmd:emoji", in: aliases), "its own alias, set again")
        XCTAssertNil(LauncherAliases.holder(of: "zz", otherThan: "cmd:emoji", in: aliases))
        XCTAssertNil(LauncherAliases.holder(of: "", otherThan: "cmd:emoji", in: aliases))
        XCTAssertTrue(LauncherAliases.isValid("cl"))
        XCTAssertFalse(LauncherAliases.isValid("c l"))
        XCTAssertFalse(LauncherAliases.isValid(""))
    }
}
