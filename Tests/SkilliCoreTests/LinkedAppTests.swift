@testable import SkilliCore
import XCTest

/// CleanShot X's commands as skil.li opens them (docs/apps.md): the link
/// its API documents, a variant's parameters, the front window's frame as
/// CleanShot reads it, and the Catalog's entries.
final class LinkedAppTests: XCTestCase {
    private func command(_ name: String) throws -> AppLinkCommand {
        try XCTUnwrap(LinkedApp.command(id: "cleanshot.\(name)"))
    }

    func testEveryCommandHasItsOwnIdUnderItsApp() {
        let ids = CleanShot.commands.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("cleanshot.") })
        for command in CleanShot.commands {
            XCTAssertEqual(LinkedApp.command(id: command.id)?.id, command.id)
            XCTAssertEqual(command.app?.name, "CleanShot X")
            XCTAssertTrue(command.keywords.contains("cleanshot"), command.id)
        }
        XCTAssertNil(LinkedApp.command(id: "cleanshot.nothing"))
        XCTAssertNil(LinkedApp.command(id: "nothing.capture-area"))
    }

    func testEveryDocumentedPathIsThere() {
        let paths = Set(CleanShot.commands.map(\.path))
        let documented = ["all-in-one", "capture-area", "capture-previous-area", "capture-fullscreen", "capture-window", "self-timer",
                          "scrolling-capture", "pin", "record-screen", "capture-text", "open-annotate", "open-from-clipboard",
                          "toggle-desktop-icons", "hide-desktop-icons", "show-desktop-icons", "open-history", "restore-recently-closed",
                          "open-settings"]
        XCTAssertEqual(paths.subtracting(documented), [])
        XCTAssertEqual(Set(documented).subtracting(paths), [])
    }

    func testLinksAsTheAPIWritesThem() throws {
        XCTAssertEqual(try command("capture-area").url()?.absoluteString, "cleanshot://capture-area")
        let area = try command("capture-area")
        XCTAssertEqual(area.url(variant: area.variant(id: "copy"))?.absoluteString, "cleanshot://capture-area?action=copy")
        let scrolling = try command("scrolling-capture")
        XCTAssertEqual(scrolling.url(variant: scrolling.variant(id: "autoscroll"))?.absoluteString,
                       "cleanshot://scrolling-capture?start=true&autoscroll=true")
        let settings = try command("open-settings")
        XCTAssertEqual(settings.url(variant: settings.variant(id: "advanced"))?.absoluteString, "cleanshot://open-settings?tab=advanced")
        let pin = try command("pin-latest-screenshot")
        XCTAssertEqual(pin.path, "pin")
        XCTAssertEqual(pin.url(extra: [.init("filepath", "/Users/me/Desktop/CleanShot 2026-10-20 at 09.05.12@2x.png")])?.absoluteString,
                       "cleanshot://pin?filepath=/Users/me/Desktop/CleanShot%202026-10-20%20at%2009.05.12@2x.png")
    }

    func testVersionsGateWhatCleanShotTakes() throws {
        XCTAssertTrue(AppVersion.isAtLeast("5.0.1", "4.7"))
        XCTAssertTrue(AppVersion.isAtLeast("4.7", "4.7"))
        XCTAssertTrue(AppVersion.isAtLeast("4.10", "4.7"))
        XCTAssertFalse(AppVersion.isAtLeast("4.6.2", "4.7"))
        XCTAssertTrue(AppVersion.isAtLeast(nil, "4.7"))
        XCTAssertTrue(AppVersion.isAtLeast("3.0", nil))
        let area = try command("capture-area")
        XCTAssertEqual(area.variants(forVersion: "4.6").map(\.id), [])
        XCTAssertEqual(area.variants(forVersion: "5.0.1").map(\.id), ["copy", "save", "annotate", "pin", "upload"])
        XCTAssertFalse(try command("record-front-window").runs(onVersion: "4.6"))
        XCTAssertTrue(try command("record-front-window").runs(onVersion: "5.0.1"))
    }

    func testFrontWindowFrameFromTheDisplaysBottomLeft() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Accessibility's top left: 50 pt down, 600 tall → 250 pt up.
        XCTAssertEqual(CleanShot.frame(of: CGRect(x: 100, y: 50, width: 800, height: 600), screens: [main])?.map(\.value),
                       ["100", "250", "800", "600", "1"])
        // A second display to the right, bottoms aligned.
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(CleanShot.frame(of: CGRect(x: 1540, y: 100, width: 400, height: 300), screens: [main, right])?.map(\.value),
                       ["100", "500", "400", "300", "2"])
        // Half off the main display: only what is on it.
        XCTAssertEqual(CleanShot.frame(of: CGRect(x: 1240, y: 0, width: 400, height: 900), screens: [main])?.map(\.value),
                       ["1240", "0", "200", "900", "1"])
        XCTAssertNil(CleanShot.frame(of: CGRect(x: 5000, y: 5000, width: 100, height: 100), screens: [main]))
        XCTAssertNil(CleanShot.frame(of: CGRect(x: 0, y: 0, width: 100, height: 100), screens: []))
    }

    func testCatalogListsTheInstalledCommandsAsTheirRows() throws {
        let entries = FeatureCatalog.entries(FeatureCatalog.Input(appLinks: CleanShot.commands))
        let area = try XCTUnwrap(entries.first { $0.run == .appLink("cleanshot.capture-area") })
        XCTAssertEqual(area.id, "system:link:cleanshot.capture-area")
        XCTAssertEqual(area.group, .apps)
        for entry in entries where entry.group == .apps {
            XCTAssertLessThanOrEqual(entry.oneLine.count, 80, "\(entry.title): one line")
            XCTAssertFalse(entry.oneLine.hasSuffix("."), entry.title)
        }
        XCTAssertTrue(area.takesAlias)
        XCTAssertTrue(area.canBeOff)
        XCTAssertEqual(FeatureCatalog.filter(entries, "capture text").first?.title, "Capture Text")
        XCTAssertEqual(FeatureCatalog.filter(entries, "cleanshot pin").first?.group, .apps)
        // Not installed: nothing listed.
        XCTAssertFalse(FeatureCatalog.entries().contains { $0.group == .apps })
    }

    func testLinksRunThemAtOnceAndNeverTrustThem() {
        XCTAssertFalse(SkilliLink.asksFirst(.appLink("cleanshot.capture-area")))
        XCTAssertFalse(LinkTrust.canTrust(.appLink("cleanshot.capture-area")))
        XCTAssertEqual(SkilliLink.parse(SkilliLink.run("system:link:cleanshot.capture-area").url), .run("system:link:cleanshot.capture-area"))
    }

    /// Settings → Apps lists every command once, under its group.
    func testEveryCommandIsInOneGroup() {
        for app in LinkedApp.all {
            let grouped = app.grouped.flatMap(\.commands).map(\.id)
            XCTAssertEqual(grouped.count, app.groups.flatMap(\.commands).count, "\(app.id): a group names a command it does not have")
            XCTAssertEqual(Set(grouped).count, grouped.count, "\(app.id): a command in two groups")
            XCTAssertEqual(Set(grouped), Set(app.commands.map(\.id)), "\(app.id): a command in no group")
            XCTAssertTrue(app.grouped.allSatisfy { !$0.commands.isEmpty })
        }
    }

    /// Capture Text's line breaks (Settings → Apps): CleanShot's own
    /// setting, or one of its two variants when ⌘K does not say.
    func testCaptureTextLineBreaksPickAVariant() throws {
        let text = try command("capture-text")
        XCTAssertNil(CleanShot.defaultVariant(of: text, lineBreaks: .asSet))
        XCTAssertEqual(text.url(variant: CleanShot.defaultVariant(of: text, lineBreaks: .kept))?.absoluteString,
                       "cleanshot://capture-text?linebreaks=true")
        XCTAssertEqual(text.url(variant: CleanShot.defaultVariant(of: text, lineBreaks: .joined))?.absoluteString,
                       "cleanshot://capture-text?linebreaks=false")
        // Only Capture Text.
        XCTAssertNil(CleanShot.defaultVariant(of: try command("capture-area"), lineBreaks: .joined))
        for option in CleanShot.TextLineBreaks.allCases {
            XCTAssertEqual(option.variant.flatMap(text.variant(id:))?.id, option.variant)
        }
    }
}
