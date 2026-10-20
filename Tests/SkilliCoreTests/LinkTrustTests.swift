@testable import SkilliCore
import XCTest

/// D6 (JB 2026-10-17): a link that asks first offers Always ⌘↩; Always
/// trusts that entry only, so its next link runs at once. What asks in
/// its own card anyway, settings and pastes of the user's copies are
/// never trusted.
final class LinkTrustTests: XCTestCase {
    func testWhatAsksFirstOffersAlwaysAndRunsAtOnceOnceTrusted() {
        var trust = LinkTrust()
        let lock = CatalogEntry.Run.system(.lockScreen)
        XCTAssertEqual(trust.ask(lock, entry: "system:lockScreen"), .asks(offersAlways: true))
        XCTAssertTrue(trust.trust(lock, entry: "system:lockScreen", title: "Lock Screen"))
        XCTAssertEqual(trust.ask(lock, entry: "system:lockScreen"), .runs)
        XCTAssertEqual(trust.links, [TrustedLink(entry: "system:lockScreen", title: "Lock Screen")])
    }

    func testTrustIsPerEntryOnly() {
        var trust = LinkTrust()
        trust.trust(.system(.lockScreen), entry: "system:lockScreen", title: "Lock Screen")
        XCTAssertEqual(trust.ask(.system(.sleep), entry: "system:sleep"), .asks(offersAlways: true))
        trust.trust(.snippet("addr"), entry: "snippet:addr", title: "Address")
        XCTAssertEqual(trust.ask(.snippet("iban"), entry: "snippet:iban"), .asks(offersAlways: true))
        XCTAssertEqual(trust.ask(.snippet("addr"), entry: "snippet:addr"), .runs)
    }

    func testWhatRunsAtOnceNeedsNoTrust() {
        var trust = LinkTrust()
        for run: CatalogEntry.Run in [.window(.leftHalf), .command(.clipboardHistory), .layout("coding"), .quicklink(UUID()), .ask,
                                      .type("timer ", hint: nil), .system(.toggleDarkMode)] {
            XCTAssertEqual(trust.ask(run, entry: "x"), .runs, "\(run)")
            XCTAssertFalse(trust.trust(run, entry: "x", title: "X"), "\(run): nothing to trust")
        }
        XCTAssertTrue(trust.links.isEmpty)
    }

    func testWhatAsksAnywayIsNeverTrustedAndItsCardOffersNoAlways() {
        var trust = LinkTrust()
        let anyway = SystemCommand.allCases.filter(\.asksAnyway)
        XCTAssertEqual(Set(anyway), [.emptyTrash, .restart, .shutDown, .logOut, .quitAllApps, .quitOtherApps])
        for command in anyway {
            let run = CatalogEntry.Run.system(command)
            XCTAssertTrue(LinkTrust.neverTrusted(run), command.rawValue)
            XCTAssertFalse(LinkTrust.canTrust(run), command.rawValue)
            XCTAssertFalse(trust.trust(run, entry: "system:\(command.rawValue)", title: command.rawValue), command.rawValue)
        }
        XCTAssertTrue(trust.links.isEmpty)
    }

    func testSettingsAndPastesOfYourCopiesAreNeverTrusted() {
        var trust = LinkTrust()
        for run: CatalogEntry.Run in [.settings("snippets"), .command(.resetLauncherPosition), .command(.pasteInSequence),
                                      .system(.pasteLatestScreenshot)] {
            XCTAssertTrue(LinkTrust.neverTrusted(run), "\(run)")
            XCTAssertFalse(trust.trust(run, entry: "x", title: "X"), "\(run)")
        }
        // They still ask, without Always.
        XCTAssertEqual(trust.ask(.command(.pasteInSequence), entry: "cmd:pasteInSequence"), .asks(offersAlways: false))
        XCTAssertEqual(trust.ask(.system(.pasteLatestScreenshot), entry: "system:pasteLatestScreenshot"), .asks(offersAlways: false))
    }

    func testEverythingElseThatAsksFirstCanBeTrusted() {
        for run: CatalogEntry.Run in [.snippet("addr"), .skillie("/x.sh"), .prompt("translate"), .transform(.uppercase), .askByVoice, .dictate,
                                      .command(.quit), .system(.sleep), .system(.ejectDisks), .system(.wifiOff), .system(.showDesktop)] {
            XCTAssertTrue(LinkTrust.canTrust(run), "\(run)")
        }
    }

    /// A trust in the file for what can no longer be trusted extends nothing.
    func testAStaleTrustDoesNothing() {
        let trust = LinkTrust([TrustedLink(entry: "system:emptyTrash", title: "Empty Trash"),
                               TrustedLink(entry: "cmd:pasteInSequence", title: "Paste in Sequence")])
        XCTAssertEqual(trust.ask(.system(.emptyTrash), entry: "system:emptyTrash"), .runs, "it asks in its own card, not the link's")
        XCTAssertEqual(trust.ask(.command(.pasteInSequence), entry: "cmd:pasteInSequence"), .asks(offersAlways: false))
    }

    func testASkillieIsTrustedWithItsArguments() {
        var trust = LinkTrust()
        let deploy = CatalogEntry.Run.skillie("/s/deploy.sh")
        trust.trust(deploy, entry: "script:/s/deploy.sh", title: "Deploy", arguments: ["prod"])
        XCTAssertEqual(trust.ask(deploy, entry: "script:/s/deploy.sh", arguments: ["prod"]), .runs)
        XCTAssertEqual(trust.ask(deploy, entry: "script:/s/deploy.sh", arguments: ["staging"]), .asks(offersAlways: true))
        XCTAssertEqual(trust.ask(deploy, entry: "script:/s/deploy.sh"), .asks(offersAlways: true))
        XCTAssertEqual(trust.links.first?.shown, "Deploy · “prod”")
        // Other entries take no arguments: whatever a link adds is not kept.
        trust.trust(.snippet("addr"), entry: "snippet:addr", title: "Address", arguments: ["x"])
        XCTAssertEqual(trust.links.last?.arguments, [])
    }

    /// One that asks in its own card is not asked by the link, and its own
    /// question is never skipped.
    func testASkillieThatAsksItselfIsNotAskedTwice() {
        var trust = LinkTrust()
        let run = CatalogEntry.Run.skillie("/s/wipe.sh")
        XCTAssertEqual(trust.ask(run, entry: "script:/s/wipe.sh", asksItself: true), .runs)
        trust.trust(run, entry: "script:/s/wipe.sh", title: "Wipe")
        XCTAssertEqual(trust.ask(run, entry: "script:/s/wipe.sh", asksItself: true), .runs)
    }

    /// A "do it here" link always asks first, Always offered; Always trusts
    /// that very goal in that very app, never another goal or app.
    func testDoLinksTrustedPerGoalAndApp() throws {
        var trust = LinkTrust()
        XCTAssertEqual(trust.askDo(goal: "exporte en PDF", app: "TextEdit"), .asks(offersAlways: true))
        trust.trustDo(goal: "exporte en PDF", app: "TextEdit", title: "Do It Here")
        trust.trustDo(goal: "exporte en PDF", app: "TextEdit", title: "Do It Here")
        XCTAssertEqual(trust.links, [TrustedLink(entry: LinkTrust.doEntry, arguments: ["exporte en PDF", "TextEdit"], title: "Do It Here")])
        XCTAssertEqual(trust.askDo(goal: "exporte en PDF", app: "TextEdit"), .runs)
        XCTAssertEqual(trust.askDo(goal: "exporte en PDF", app: "Pages"), .asks(offersAlways: true), "another app")
        XCTAssertEqual(trust.askDo(goal: "exporte en PDF", app: nil), .asks(offersAlways: true), "whatever app is in front")
        XCTAssertEqual(trust.askDo(goal: "supprime tout", app: "TextEdit"), .asks(offersAlways: true), "another goal")
        trust.trustDo(goal: "joue le prochain coup", app: nil, title: "Do It Here")
        XCTAssertEqual(trust.askDo(goal: "joue le prochain coup", app: nil), .runs)
        XCTAssertEqual(trust.askDo(goal: "joue le prochain coup", app: "Chess"), .asks(offersAlways: true))
        XCTAssertEqual(trust.byTitle.map(\.shown), ["Do It Here · “exporte en PDF”, “TextEdit”", "Do It Here · “joue le prochain coup”"])
        // Kept in tools.json like any.
        let read = LinkTrust(try JSONDecoder().decode([TrustedLink].self, from: JSONEncoder().encode(trust.links)))
        XCTAssertEqual(read.askDo(goal: "exporte en PDF", app: "TextEdit"), .runs)
        trust.remove(trust.links[0])
        XCTAssertEqual(trust.askDo(goal: "exporte en PDF", app: "TextEdit"), .asks(offersAlways: true))
    }

    func testRemovedAsksAgain() {
        var trust = LinkTrust()
        trust.trust(.system(.lockScreen), entry: "system:lockScreen", title: "Lock Screen")
        trust.trust(.system(.lockScreen), entry: "system:lockScreen", title: "Lock Screen")
        XCTAssertEqual(trust.links.count, 1, "trusted once")
        trust.remove(trust.links[0])
        XCTAssertEqual(trust.ask(.system(.lockScreen), entry: "system:lockScreen"), .asks(offersAlways: true))
        XCTAssertTrue(trust.links.isEmpty)
    }

    func testKeptAsJSONAndListedByName() throws {
        var trust = LinkTrust()
        trust.trust(.system(.sleep), entry: "system:sleep", title: "Sleep")
        trust.trust(.snippet("addr"), entry: "snippet:addr", title: "Address")
        trust.trust(.skillie("/s/é.sh"), entry: "script:/s/é.sh", title: "éclair", arguments: ["a"])
        let data = try JSONEncoder().encode(trust.links)
        let read = LinkTrust(try JSONDecoder().decode([TrustedLink].self, from: data))
        XCTAssertEqual(read, trust)
        XCTAssertEqual(read.byTitle.map(\.title), ["Address", "éclair", "Sleep"])
        // The same entry twice in a file edited by hand: once.
        XCTAssertEqual(LinkTrust(trust.links + trust.links).links.count, 3)
    }
}
