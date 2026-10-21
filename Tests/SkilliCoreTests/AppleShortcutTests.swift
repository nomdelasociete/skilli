@testable import SkilliCore
import XCTest

/// The user's shortcuts in Apple's Shortcuts app (docs/apps.md): the list
/// `shortcuts list --show-identifiers` prints, the editor's link, what a
/// run gave back, and their Catalog entries, links and trust.
final class AppleShortcutTests: XCTestCase {
    private let morning = AppleShortcut(id: "0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F501", name: "Morning Routine")

    func testTheListReadsEachNameAndIdentifier() {
        let output = """
        Morning Routine (0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F501)
        Text Camille (Work) (0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F502)
        Résumé & Notes + (0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F503)

        Without an identifier
        Broken (not-a-uuid)
        """
        let shortcuts = AppleShortcut.list(output)
        XCTAssertEqual(shortcuts.map(\.name), ["Morning Routine", "Text Camille (Work)", "Résumé & Notes +"])
        XCTAssertEqual(shortcuts.map(\.id), ["0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F501", "0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F502",
                                             "0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F503"])
        XCTAssertEqual(AppleShortcut.list(""), [])
    }

    func testEqualByIdentifierWhateverItsName() {
        // A key saved before the list was read knows only the identifier.
        XCTAssertEqual(AppleShortcut(id: morning.id, name: ""), morning)
        XCTAssertEqual(Set([morning, AppleShortcut(id: morning.id, name: "Renamed")]).count, 1)
        XCTAssertNotEqual(AppleShortcut(id: "0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F502", name: "Morning Routine"), morning)
    }

    func testRunsByItsIdentifier() {
        XCTAssertEqual(morning.runArguments, ["run", "0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F501"])
        XCTAssertEqual(AppleShortcut.listArguments, ["list", "--show-identifiers"])
    }

    func testTheEditorsLinkEncodesTheWholeName() {
        XCTAssertEqual(morning.editURL?.absoluteString, "shortcuts://open-shortcut?name=Morning%20Routine")
        let odd = AppleShortcut(id: morning.id, name: "Résumé & Notes + #1")
        XCTAssertEqual(odd.editURL?.absoluteString, "shortcuts://open-shortcut?name=R%C3%A9sum%C3%A9%20%26%20Notes%20%2B%20%231")
        XCTAssertNil(AppleShortcut(id: morning.id, name: "").editURL)
    }

    func testTheCardShowsTextOnly() {
        XCTAssertEqual(AppleShortcut.shownOutput(Data("echo:zebra\n".utf8)), "echo:zebra")
        XCTAssertEqual(AppleShortcut.shownOutput(Data("  line one\nline two\n\n".utf8)), "line one\nline two")
        XCTAssertNil(AppleShortcut.shownOutput(Data()))
        XCTAssertNil(AppleShortcut.shownOutput(Data(" \n".utf8)))
        // An image: not text.
        XCTAssertNil(AppleShortcut.shownOutput(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])))
        XCTAssertNil(AppleShortcut.shownOutput(Data([0xFF, 0xFE, 0xFD])))
    }

    func testAFailureSaysItsLastLine() {
        XCTAssertEqual(AppleShortcut.failure("Error: The operation couldn’t be completed.\n"), "The operation couldn’t be completed.")
        XCTAssertEqual(AppleShortcut.failure("first\nError: Couldn’t find shortcut\n\n"), "Couldn’t find shortcut")
        XCTAssertNil(AppleShortcut.failure(" \n"))
        XCTAssertNil(AppleShortcut.failure("Error:"))
    }

    func testEachShortcutIsACatalogEntryInYourApps() throws {
        let entries = FeatureCatalog.entries(FeatureCatalog.Input(shortcuts: [morning]))
        let entry = try XCTUnwrap(entries.first { $0.run == .shortcut(morning.id) })
        // Its launcher row's learning id: the same alias, pin and link.
        XCTAssertEqual(entry.id, "system:shortcut:0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F501")
        XCTAssertEqual(entry.id, FeatureCatalog.shortcutEntryID(morning.id))
        XCTAssertEqual(entry.title, "Morning Routine")
        XCTAssertEqual(entry.group, .apps)
        XCTAssertTrue(entry.takesAlias)
        XCTAssertTrue(entry.canBeOff)
        XCTAssertLessThanOrEqual(entry.oneLine.count, 80)
        XCTAssertFalse(entry.oneLine.hasSuffix("."))
        // Found by its name and by "raccourci".
        XCTAssertEqual(FeatureCatalog.filter(entries, "morning").first?.id, entry.id)
        XCTAssertTrue(FeatureCatalog.filter(entries, "raccourci").contains { $0.id == entry.id })
        // None read: no entry, nothing promised.
        XCTAssertFalse(FeatureCatalog.entries().contains { if case .shortcut = $0.run { true } else { false } })
    }

    func testALinkAsksFirstAndAlwaysMayTrustIt() {
        let run = CatalogEntry.Run.shortcut(morning.id)
        let id = FeatureCatalog.shortcutEntryID(morning.id)
        XCTAssertTrue(SkilliLink.asksFirst(run))
        XCTAssertFalse(LinkTrust.neverTrusted(run))
        XCTAssertEqual(LinkTrust().ask(run, entry: id), .asks(offersAlways: true))
        var trust = LinkTrust()
        XCTAssertTrue(trust.trust(run, entry: id, title: morning.name))
        XCTAssertEqual(trust.ask(run, entry: id), .runs)
        // Its link runs the entry by its id.
        let entry = CatalogEntry(id: id, title: morning.name, oneLine: FeatureCatalog.shortcutLine, group: .apps, symbol: "square.2.layers.3d",
                                 run: run)
        XCTAssertEqual(SkilliLink.link(for: entry).url.absoluteString,
                       "skilli://run/system:shortcut:0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F501")
        XCTAssertEqual(SkilliLink.parse(SkilliLink.link(for: entry).url), .run(id))
    }
}
