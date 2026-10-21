import AppKit
@testable import SkilliCore
import XCTest

/// Linked apps written in files (docs/apps.md, "App files"): read
/// strictly, the built-in CleanShot X winning any clash, skil.li's own
/// files before the user's, and their commands run as CleanShot's do.
final class LinkedAppFileTests: XCTestCase {
    override func tearDown() {
        LinkedApp.useFiles([])
        super.tearDown()
    }

    /// A small valid file, changed by `edit` before it is written.
    private func file(_ edit: (inout [String: Any]) -> Void = { _ in }) -> Data {
        var object: [String: Any] = [
            "id": "nimbus",
            "name": "Nimbus Notes",
            "shortName": "Nimbus",
            "bundleID": "com.example.Nimbus",
            "scheme": "nimbus",
            "minimumVersion": "2.0",
            "documentation": "https://example.com/nimbus/links",
            "commands": [
                [
                    "id": "today",
                    "path": "show/today",
                    "title": "Nimbus Today",
                    "description": "Shows today's notes.",
                    "words": ["notes", "today", "aujourd'hui"],
                    "symbol": "sun.max",
                    "group": "Show"
                ],
                [
                    "id": "new-note",
                    "path": "x-callback-url/create",
                    "title": "New Nimbus Note",
                    "description": "Opens a new note",
                    "query": [["name": "open_note", "value": "yes"]],
                    "variants": [["id": "pinned", "title": "New Pinned Note", "label": "Pinned", "query": [["name": "pin", "value": "yes"]],
                                  "since": "2.4"]],
                    "group": "Write"
                ],
                [
                    "id": "share",
                    "path": "/share/all",
                    "title": "Share All Notes",
                    "description": "Sends every note to the team",
                    "asksFirst": true,
                    "group": "Write"
                ]
            ]
        ]
        edit(&object)
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func command(_ edit: @escaping (inout [String: Any]) -> Void) -> Data {
        file { object in
            var commands = object["commands"] as! [[String: Any]]
            edit(&commands[0])
            object["commands"] = commands
        }
    }

    private func problem(_ data: Data, symbolExists: (String) -> Bool = { _ in true }) -> String? {
        do {
            _ = try LinkedAppFile.read(data, file: "Nimbus.json", symbolExists: symbolExists)
            return nil
        } catch {
            return error.message
        }
    }

    // MARK: Reading

    func testAValidFileGivesItsAppAndCommands() throws {
        let app = try LinkedAppFile.read(file(), file: "Nimbus.json")
        XCTAssertEqual(app.id, "nimbus")
        XCTAssertEqual(app.name, "Nimbus Notes")
        XCTAssertEqual(app.shortName, "Nimbus")
        XCTAssertEqual(app.bundleID, "com.example.Nimbus")
        XCTAssertEqual(app.file, "Nimbus.json")
        XCTAssertEqual(app.documentation, "https://example.com/nimbus/links")
        XCTAssertEqual(app.commands.map(\.id), ["nimbus.today", "nimbus.new-note", "nimbus.share"])
        // Its groups in the order they first come.
        XCTAssertEqual(app.groups, [.init(title: "Show", commands: ["today"]), .init(title: "Write", commands: ["new-note", "share"])])
        let today = app.commands[0]
        // The period goes: the Catalog's line has none.
        XCTAssertEqual(today.oneLine, "Shows today's notes")
        XCTAssertEqual(today.symbol, "sun.max")
        // Found by the app's name too, then its words.
        XCTAssertEqual(today.keywords, ["nimbus notes", "notes", "today", "aujourd'hui"])
        // The app's minimum is every command's; a variant's own is later.
        XCTAssertEqual(today.since, "2.0")
        XCTAssertFalse(today.runs(onVersion: "1.9"))
        let note = app.commands[1]
        XCTAssertEqual(note.symbol, "link")
        XCTAssertEqual(note.variants.first?.since, "2.4")
        XCTAssertEqual(note.variants.first?.symbol, "link")
        XCTAssertTrue(app.commands[2].asksFirst)
        XCTAssertFalse(today.asksFirst)
    }

    func testItsLinksAsTheFileWritesThem() throws {
        LinkedApp.useFiles([try LinkedAppFile.read(file(), file: "Nimbus.json")])
        let today = try XCTUnwrap(LinkedApp.command(id: "nimbus.today"))
        XCTAssertEqual(today.url()?.absoluteString, "nimbus://show/today")
        let note = try XCTUnwrap(LinkedApp.command(id: "nimbus.new-note"))
        XCTAssertEqual(note.url()?.absoluteString, "nimbus://x-callback-url/create?open_note=yes")
        XCTAssertEqual(note.url(variant: note.variant(id: "pinned"))?.absoluteString, "nimbus://x-callback-url/create?open_note=yes&pin=yes")
        // A path that starts with "/" has no host: msteams:/l/meeting/new.
        XCTAssertEqual(LinkedApp.command(id: "nimbus.share")?.url()?.absoluteString, "nimbus:/share/all")
        // A `+` in a value is not a space.
        XCTAssertEqual(AppLinkCommand.url(scheme: "nimbus", path: "find", query: [.init("q", "c++ notes")])?.absoluteString,
                       "nimbus://find?q=c%2B%2B%20notes")
        XCTAssertEqual(today.app?.name, "Nimbus Notes")
    }

    func testSkilliShipsValidFilesThatClashWithNothing() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Skilli/Resources/Apps")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        let loaded = LinkedAppFile.load(try files.map { LinkedAppFile.Source(name: $0.lastPathComponent, data: try Data(contentsOf: $0), shipped: true) })
        XCTAssertEqual(loaded.problems, [])
        XCTAssertEqual(loaded.apps.count, files.count)
        LinkedApp.useFiles(loaded.apps)
        // As their apps document them (docs/apps.md).
        XCTAssertEqual(LinkedApp.command(id: "warp.appearance")?.url()?.absoluteString, "warp://settings/appearance")
        XCTAssertEqual(LinkedApp.command(id: "zed.tool-permissions")?.url()?.absoluteString, "zed://settings/agent.tool_permissions")
        XCTAssertEqual(LinkedApp.command(id: "teams.new-meeting")?.url()?.absoluteString, "msteams:/l/meeting/new")
        for app in loaded.apps {
            XCTAssertNil(app.file, app.id)
            XCTAssertNotNil(app.documentation, "\(app.id): only links the app documents")
            XCTAssertEqual(app.documentation.flatMap(URL.init(string:))?.scheme, "https")
            for command in app.commands {
                // Not checked as the app reads them (macOS's first answer is slow).
                XCTAssertNotNil(NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil), "\(command.id): \(command.symbol)")
                for variant in command.variants {
                    XCTAssertNotNil(NSImage(systemSymbolName: variant.symbol, accessibilityDescription: nil), "\(command.id)/\(variant.id)")
                }
                // As the Catalog lists it: one line of 80 at most.
                XCTAssertLessThanOrEqual("\(command.oneLine), in \(app.name)".count, 80, command.id)
                XCTAssertTrue(command.keywords.contains(app.name.lowercased()), command.id)
                XCTAssertNotNil(command.url(), command.id)
            }
        }
    }

    func testEveryWrongThingIsSaidAndTheFileLeftOut() {
        let wrong: [(Data, String)] = [
            (Data("{ not json".utf8), "Not JSON"),
            (Data("[1, 2]".utf8), "one JSON object"),
            (Data(repeating: 32, count: LinkedAppFile.largest + 1), "Over 64 KB"),
            (file { $0["colour"] = "blue" }, "“colour” is not a key"),
            (file { $0["id"] = "Nimbus Notes" }, "lowercase letters, digits and hyphens"),
            (file { $0["id"] = "text" }, "names something else"),
            (file { $0.removeValue(forKey: "name") }, "“name” is missing"),
            (file { $0["name"] = "" }, "“name” is empty"),
            (file { $0["name"] = 12 }, "“name” must be text"),
            (file { $0["bundleID"] = "nimbus" }, "not a bundle id"),
            (file { $0["bundleID"] = "com.nomdelasociete.Skilli" }, "skil.li's own"),
            (file { $0["scheme"] = "https" }, "not one app's own"),
            (file { $0["scheme"] = "skilli" }, "not one app's own"),
            (file { $0["scheme"] = "nim bus" }, "not a link scheme"),
            (file { $0["minimumVersion"] = "two" }, "not a version"),
            (file { $0["documentation"] = "http://example.com/links" }, "https address"),
            (file { $0["commands"] = [] as [Any] }, "at least one command"),
            (file { $0["commands"] = "today" }, "list of objects"),
            (command { $0.removeValue(forKey: "title") }, "Command 1 (“today”): “title” is missing"),
            (command { $0["path"] = "show?id=today" }, "not a link's path"),
            (command { $0["path"] = "//evil" }, "not a link's path"),
            (command { $0["path"] = "show/../../etc" }, "not a link's path"),
            (command { $0["asksFirst"] = "yes" }, "true or false"),
            (command { $0["title"] = String(repeating: "a", count: 51) }, "longer than 50"),
            (command { $0["title"] = "Two\nlines" }, "more than one line"),
            (command { $0["words"] = ["ok", 3] }, "list of words"),
            (command { $0["query"] = ["a=b"] }, "{\"name\", \"value\"}"),
            (command { $0["query"] = [["name": "a"]] }, "“value” must be text (it is missing)"),
            (command { $0["query"] = [["name": "a b", "value": "c"]] }, "not a parameter's name"),
            (command { $0["variants"] = [["id": "x", "title": "X", "label": "X", "query": [] as [Any]]] }, "a variant says more"),
            (command { $0["variants"] = [["id": "x", "title": "X", "label": "X"]] }, "variant 1 (“x”): “query” is missing"),
            (command { $0["id"] = "new-note" }, "another command has the id “new-note”")
        ]
        for (data, said) in wrong {
            let message = problem(data)
            XCTAssertNotNil(message, said)
            XCTAssertTrue(message?.contains(said) == true, "“\(message ?? "nil")” does not say “\(said)”")
        }
        // An SF Symbol this Mac does not have: the user's file left out,
        // skil.li's own read (its symbols are checked here instead).
        XCTAssertTrue(problem(file(), symbolExists: { $0 != "sun.max" })?.contains("“sun.max” is not an SF Symbol") == true)
        let symbols = { (symbol: String) in symbol != "sun.max" }
        XCTAssertEqual(LinkedAppFile.load([.init(name: "Nimbus.json", data: file(), shipped: false)], symbolExists: symbols).apps.count, 0)
        XCTAssertEqual(LinkedAppFile.load([.init(name: "nimbus.json", data: file(), shipped: true)], symbolExists: symbols).apps.count, 1)
        XCTAssertNil(problem(file()))
    }

    // MARK: Clashes

    func testTheBuiltInAppWinsAnyClash() {
        let clashes: [(Data, String)] = [
            (file { $0["id"] = "cleanshot" }, "Its id “cleanshot” is CleanShot X's already (skil.li's own)."),
            (file { $0["bundleID"] = "pl.maketheweb.cleanshotx" }, "CleanShot X is driven already (skil.li's own)."),
            (file { $0["scheme"] = "CleanShot" }, "Its scheme “cleanshot” is CleanShot X's already (skil.li's own).")
        ]
        for (data, said) in clashes {
            let loaded = LinkedAppFile.load([.init(name: "Nimbus.json", data: data, shipped: false)])
            XCTAssertEqual(loaded.apps.count, 0)
            XCTAssertEqual(loaded.problems, [.init(file: "Nimbus.json", message: said)])
        }
    }

    func testSkilliFilesWinThenTheUsersByName() {
        let shipped = LinkedAppFile.Source(name: "nimbus.json", data: file(), shipped: true)
        let mine = LinkedAppFile.Source(name: "A Nimbus.json", data: file { $0["scheme"] = "nimbus2" }, shipped: false)
        let other = LinkedAppFile.Source(name: "B.json", data: file { $0["id"] = "other"; $0["bundleID"] = "com.example.Other"; $0["scheme"] = "nimbus2" },
                                         shipped: false)
        let broken = LinkedAppFile.Source(name: "C.json", data: Data("{".utf8), shipped: false)
        let loaded = LinkedAppFile.load([other, broken, mine, shipped])
        // skil.li's own first, even named after the user's.
        XCTAssertEqual(loaded.apps.map(\.id), ["nimbus", "other"])
        XCTAssertNil(loaded.apps[0].file)
        XCTAssertEqual(loaded.apps[1].file, "B.json")
        XCTAssertEqual(loaded.problems.map(\.file), ["A Nimbus.json", "C.json"])
        XCTAssertEqual(loaded.problems.first?.message, "Its id “nimbus” is Nimbus Notes's already (skil.li's own).")
        XCTAssertTrue(loaded.problems.last?.message.hasPrefix("Not JSON") == true)
        // A later file clashing with the user's own names it.
        let again = LinkedAppFile.load([.init(name: "B.json", data: file(), shipped: false),
                                        .init(name: "C.json", data: file { $0["id"] = "nimbus-two" }, shipped: false)])
        XCTAssertEqual(again.problems, [.init(file: "C.json", message: "Nimbus Notes is driven already (your “B.json”).")])
    }

    // MARK: Running

    func testWhatAsksFirstAsksFromLinksAndIsNeverTrusted() throws {
        LinkedApp.useFiles([try LinkedAppFile.read(file(), file: "Nimbus.json")])
        XCTAssertTrue(SkilliLink.asksFirst(.appLink("nimbus.share")))
        XCTAssertFalse(LinkTrust.canTrust(.appLink("nimbus.share")))
        XCTAssertFalse(SkilliLink.asksFirst(.appLink("nimbus.today")))
        XCTAssertEqual(LinkTrust().ask(.appLink("nimbus.share"), entry: "system:link:nimbus.share"), .asks(offersAlways: false))
        XCTAssertEqual(LinkTrust().ask(.appLink("nimbus.today"), entry: "system:link:nimbus.today"), .runs)
        // A raw link an agent opens cannot go round it.
        XCTAssertEqual(LinkedApp.asksFirst(try XCTUnwrap(URL(string: "nimbus:/share/all")))?.command.id, "nimbus.share")
        XCTAssertNil(LinkedApp.asksFirst(try XCTUnwrap(URL(string: "nimbus://show/today"))))
        // CleanShot's upload is its variant that asks first.
        let area = try XCTUnwrap(LinkedApp.command(id: "cleanshot.capture-area"))
        XCTAssertTrue(area.asksFirst(variant: area.variant(id: "upload")))
        XCTAssertFalse(area.asksFirst(variant: area.variant(id: "copy")))
        XCTAssertEqual(LinkedApp.asksFirst(try XCTUnwrap(URL(string: "cleanshot://capture-area?action=Upload")))?.variant?.id, "upload")
    }

    func testTheirCommandsJoinTheCatalogAndGoWithTheirFile() throws {
        let app = try LinkedAppFile.read(file(), file: "Nimbus.json")
        LinkedApp.useFiles([app])
        XCTAssertEqual(LinkedApp.all.map(\.id), ["cleanshot", "nimbus"])
        let entries = FeatureCatalog.entries(FeatureCatalog.Input(appLinks: app.commands))
        let today = try XCTUnwrap(entries.first { $0.run == .appLink("nimbus.today") })
        XCTAssertEqual(today.id, "system:link:nimbus.today")
        XCTAssertEqual(today.oneLine, "Shows today's notes, in Nimbus Notes")
        XCTAssertEqual(FeatureCatalog.filter(entries, "nimbus today").first?.title, "Nimbus Today")
        LinkedApp.useFiles([])
        XCTAssertNil(LinkedApp.command(id: "nimbus.today"))
        XCTAssertNotNil(LinkedApp.command(id: "cleanshot.capture-area"))
    }

    // MARK: Import links

    func testAnImportLinkCarriesWholeFiles() throws {
        let text = String(decoding: file(), as: UTF8.self)
        let link = AppFileLink.importLink(for: [text])
        XCTAssertTrue(link.absoluteString.hasPrefix("skilli://apps/import?app="))
        XCTAssertFalse(link.absoluteString.contains("+"))
        XCTAssertEqual(AppFileLink.parse(link), AppFileLink.Request(files: [text]))
        let remote = try XCTUnwrap(URL(string: "skilli://apps/import?url=https://example.com/nimbus.json&url=http://example.com/x.json"))
        XCTAssertEqual(AppFileLink.parse(remote), AppFileLink.Request(urls: [URL(string: "https://example.com/nimbus.json")!]))
        XCTAssertNil(AppFileLink.parse(try XCTUnwrap(URL(string: "skilli://apps/import"))))
        XCTAssertNil(AppFileLink.parse(try XCTUnwrap(URL(string: "skilli://commands/import?app=x"))))
        // Not one of skil.li's run links.
        XCTAssertNil(SkilliLink.parse(link))
    }

    func testAnAgentsAppIsWrittenAsItIsRead() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: file()) as? [String: Any])
        object["id"] = "nimbus"
        let text = try LinkedAppFile.text(object)
        XCTAssertTrue(text.contains("\"documentation\" : \"https://example.com/nimbus/links\""), "slashes kept")
        XCTAssertEqual(try LinkedAppFile.read(Data(text.utf8), file: "nimbus.json").commands.count, 3)
    }
}

private extension Error {
    var message: String { (self as? LinkedAppFile.Problem)?.message ?? localizedDescription }
}
