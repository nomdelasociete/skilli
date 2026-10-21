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
                          "open-settings", "add-quick-access-overlay"]
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

    /// cleanshot.com/docs-api: `pin` and `open-annotate` open PNG and
    /// JPEG images, `add-quick-access-overlay` those and MP4 videos.
    func testFileTypesAsCleanShotOpensThem() throws {
        XCTAssertTrue(CleanShot.images.contains("/Users/me/Desktop/Shot 1.png"))
        XCTAssertTrue(CleanShot.images.contains("Photo.JPG"))
        XCTAssertTrue(CleanShot.images.contains("photo.jpeg"))
        XCTAssertFalse(CleanShot.images.contains("/Users/me/Movies/Clip.mp4"))
        XCTAssertFalse(CleanShot.images.contains("Picture.heic"))
        XCTAssertFalse(CleanShot.images.contains("animation.gif"))
        // No extension, or only a dot at the start: no type.
        XCTAssertFalse(CleanShot.images.contains("/Users/me/png"))
        XCTAssertFalse(CleanShot.images.contains(".png"))
        XCTAssertFalse(CleanShot.images.contains("/Users/me/Shot.png.zip"))
        XCTAssertTrue(CleanShot.imagesAndVideos.contains("/Users/me/Movies/Clip.MP4"))
        XCTAssertTrue(CleanShot.imagesAndVideos.contains("Shot.png"))
        XCTAssertFalse(CleanShot.imagesAndVideos.contains("Clip.mov"))

        XCTAssertEqual(try command("pin").files, CleanShot.images)
        XCTAssertEqual(try command("open-annotate").files, CleanShot.images)
        XCTAssertEqual(try command("pin-latest-screenshot").files, CleanShot.images)
        XCTAssertEqual(try command("quick-access").files, CleanShot.imagesAndVideos)
        // Capture Text reads the text in a file too, its line breaks kept.
        let text = try command("capture-text")
        XCTAssertEqual(text.files, CleanShot.images)
        XCTAssertEqual(text.url(variant: text.variant(id: "nolinebreaks"), extra: [.init("filepath", "/Users/me/Desktop/Receipt.png")])?.absoluteString,
                       "cleanshot://capture-text?linebreaks=false&filepath=/Users/me/Desktop/Receipt.png")
        XCTAssertNil(try command("capture-area").files)
        XCTAssertNil(try command("open-from-clipboard").files)
    }

    /// ⌘K on a file skil.li lists: only what CleanShot opens for its type,
    /// on the version installed.
    func testFileActionsFollowTheFilesType() {
        let app = LinkedApp.cleanShot
        func offered(_ file: String, _ version: String? = "5.0.1") -> [String] {
            app.fileActions(opening: file, version: version).map(\.action.title)
        }
        XCTAssertEqual(offered("/Users/me/Library/Application Support/skil.li/clipboard/images/1B2C.png"),
                       ["Annotate in CleanShot", "Pin in CleanShot", "Add to CleanShot Quick Access"])
        XCTAssertEqual(offered("/Users/me/Pictures/Portrait.JPEG"), ["Annotate in CleanShot", "Pin in CleanShot", "Add to CleanShot Quick Access"])
        XCTAssertEqual(offered("/Users/me/Movies/Demo.mp4"), ["Add to CleanShot Quick Access"])
        XCTAssertEqual(offered("/Users/me/Documents/Notes.txt"), [])
        XCTAssertEqual(offered("/Users/me/Pictures/Loop.gif"), [])
        // Annotate and Quick Access came with 3.8.1, pin before.
        XCTAssertEqual(offered("/Users/me/Desktop/Shot.png", "3.6"), ["Pin in CleanShot"])
        XCTAssertEqual(offered("/Users/me/Movies/Demo.mp4", "3.6"), [])
        // Each runs its own command.
        XCTAssertEqual(app.fileActions(opening: "Shot.png", version: nil).map(\.command.id),
                       ["cleanshot.open-annotate", "cleanshot.pin", "cleanshot.quick-access"])
    }

    /// The Finder selection's commands: its file as `filepath` on the
    /// documented paths.
    func testSelectedFileCommandsOpenItsFile() throws {
        let annotate = try command("annotate-selected-image")
        XCTAssertEqual(annotate.path, "open-annotate")
        XCTAssertEqual(annotate.input, .finderSelection)
        XCTAssertEqual(try command("pin-selected-image").path, "pin")
        XCTAssertEqual(try command("pin-selected-image").input, .finderSelection)
        let quickAccess = try command("quick-access")
        XCTAssertEqual(quickAccess.input, .finderSelection)
        XCTAssertEqual(quickAccess.url(extra: [.init("filepath", "/Users/me/Movies/Demo 1.mp4")])?.absoluteString,
                       "cleanshot://add-quick-access-overlay?filepath=/Users/me/Movies/Demo%201.mp4")
        XCTAssertFalse(quickAccess.runs(onVersion: "3.6"))
        XCTAssertTrue(quickAccess.runs(onVersion: "3.8.1"))
        // Every file action names a command that takes files.
        for action in LinkedApp.cleanShot.fileActions {
            XCTAssertNotNil(LinkedApp.command(id: "cleanshot.\(action.command)")?.files, action.command)
        }
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

    func testAnUploadIsSeenWhateverItsPathOrCase() throws {
        func uploads(_ text: String) throws -> Bool { CleanShot.uploads(try XCTUnwrap(URL(string: text))) }
        XCTAssertTrue(try uploads("cleanshot://capture-area?action=upload"))
        XCTAssertTrue(try uploads("CleanShot://capture-fullscreen?x=1&ACTION=Upload"))
        XCTAssertFalse(try uploads("cleanshot://capture-area?action=copy"))
        XCTAssertFalse(try uploads("cleanshot://capture-area"))
        XCTAssertFalse(try uploads("https://example.com/?action=upload"))
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
