@testable import SkilliCore
import XCTest

final class SkilliLinkTests: XCTestCase {
    func testLinksAreBuiltAndReadBack() {
        let links: [SkilliLink] = [
            .run("cmd:emoji"),
            .run("system:window.leftHalf"),
            .run("catalog.timer"),
            .run("snippet:adresse perso"),
            .quicklink("g", query: "skilli launcher"),
            .quicklink("g", query: nil),
            .quicklink("wiki", query: "a&b=c #d/é + e?"),
            .layout("coding"),
            .skillie("tools/deploy prod.sh", arguments: ["prod", "a&b", ""]),
            .skillie("hello.sh", arguments: [])
        ]
        for link in links {
            XCTAssertEqual(SkilliLink.parse(link.url), link, link.url.absoluteString)
        }
        XCTAssertEqual(SkilliLink.run("cmd:emoji").url.absoluteString, "skilli://run/cmd:emoji")
        XCTAssertEqual(SkilliLink.run("system:window.leftHalf").url.absoluteString, "skilli://run/system:window.leftHalf")
        XCTAssertEqual(SkilliLink.quicklink("g", query: "skilli launcher").url.absoluteString, "skilli://quicklink/g?q=skilli%20launcher")
        XCTAssertEqual(SkilliLink.layout("coding").url.absoluteString, "skilli://layout/coding")
        XCTAssertEqual(SkilliLink.skillie("tools/deploy.sh", arguments: ["prod"]).url.absoluteString, "skilli://skillie/tools/deploy.sh?arg=prod")
        // `+` and `&` stay part of the query: web pages read `+` as a space.
        XCTAssertTrue(SkilliLink.quicklink("g", query: "1+1&x").url.absoluteString.hasSuffix("q=1%2B1%26x"))
    }

    func testLinksTypedByHand() throws {
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "SKILLI://Run/cmd:emoji"))), .run("cmd:emoji"))
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://quicklink/g?q=a+b"))), .quicklink("g", query: "a+b"))
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://quicklink/g?q="))), .quicklink("g", query: nil), "an empty query: the selection's")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://run/script:/Users/me/x.sh"))), .run("script:/Users/me/x.sh"))
    }

    /// "Do it here" from a link (docs/do-it-here-from-anywhere.md): the
    /// goal and the app in the query, built and read back; typed by hand
    /// with `+` or spaces; an empty goal is still the link (the card says
    /// it has nothing to do).
    func testDoLinks() throws {
        let links: [SkilliLink] = [
            .doHere(goal: "exporte en PDF dans mes documents", app: "TextEdit"),
            .doHere(goal: "mets « a&b=c #d + e? » dans le nom", app: nil),
            .doHere(goal: "ouvre le dossier Documents", app: "com.apple.finder")
        ]
        for link in links {
            XCTAssertEqual(SkilliLink.parse(link.url), link, link.url.absoluteString)
        }
        XCTAssertEqual(SkilliLink.doHere(goal: "exporte en PDF", app: "TextEdit").url.absoluteString,
                       "skilli://do?app=TextEdit&goal=exporte%20en%20PDF")
        XCTAssertEqual(SkilliLink.doHere(goal: "joue", app: nil).url.absoluteString, "skilli://do?goal=joue")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "SKILLI://Do?goal=exporte%20en%20PDF&app=TextEdit"))),
                       .doHere(goal: "exporte en PDF", app: "TextEdit"))
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://do/?goal=%20joue%20&app="))), .doHere(goal: "joue", app: nil),
                       "trimmed; an empty app: the one in front")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://do"))), .doHere(goal: "", app: nil))
    }

    /// The Record card from a link, its name given or not; the recording
    /// on now paused, resumed or stopped.
    func testRecordLinks() throws {
        let links: [SkilliLink] = [.record(title: nil), .record(title: "Weekly sync & co"), .recording(.pause), .recording(.resume), .recording(.stop),
                                   .importRecording(file: nil), .importRecording(file: "/Users/me/Board call #2.m4a")]
        for link in links {
            XCTAssertEqual(SkilliLink.parse(link.url), link, link.url.absoluteString)
        }
        XCTAssertEqual(SkilliLink.record(title: "Weekly sync").url.absoluteString, "skilli://record?title=Weekly%20sync")
        XCTAssertEqual(SkilliLink.recording(.stop).url.absoluteString, "skilli://record/stop")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "SKILLI://Record?title=%20"))), .record(title: nil), "an empty name: the card's own")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/STOP"))), .recording(.stop))
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/delete"))))
        XCTAssertEqual(SkilliLink.importRecording(file: "/Users/me/Call.m4a").url.absoluteString, "skilli://record/import?file=%2FUsers%2Fme%2FCall%2Em4a")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/import?file="))), .importRecording(file: nil))
        let open = SkilliLink.openRecording("2026-10-22 14.00 Weekly sync", at: 724.6)
        XCTAssertEqual(open.url.absoluteString, "skilli://record/open?recording=2026-10-22%2014%2E00%20Weekly%20sync&at=724%2E6")
        XCTAssertEqual(SkilliLink.parse(open.url), open, "its fraction kept: the line that starts then")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/open?recording=x&at=1e20"))), .openRecording("x", at: nil),
                       "a time no recording reaches")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/open?recording=x&at=nan"))), .openRecording("x", at: nil))
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/open?recording=Weekly%20sync"))), .openRecording("Weekly sync", at: nil))
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/open"))), "a recording named")
        for action in MeetingFollowUp.Action.allCases {
            let link = SkilliLink.recordingFollowUp(action, recording: "Weekly sync", question: action == .ask ? "Who sends the deck?" : nil)
            XCTAssertEqual(SkilliLink.parse(link.url), link, action.rawValue)
        }
        XCTAssertEqual(SkilliLink.recordingFollowUp(.actionItems, recording: "", question: nil).url.absoluteString, "skilli://record/actions")
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/recap"))), .recordingFollowUp(.recapMail, recording: "", question: nil))
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/ask?recording=x"))), "ask needs its question")
        let rename = SkilliLink.renameRecording("2026-10-22 14.00 Weekly sync", title: "Weekly sync with legal")
        XCTAssertEqual(rename.url.absoluteString, "skilli://record/rename?recording=2026-10-22%2014%2E00%20Weekly%20sync&title=Weekly%20sync%20with%20legal")
        XCTAssertEqual(SkilliLink.parse(rename.url), rename)
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/rename?title=New"))), "which one: never the newest by default")
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/rename?recording=x"))), "a name to give it")
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(SkilliLink.parse(SkilliLink.renameRecording("x", title: long).url), .renameRecording("x", title: String(long.prefix(120))))
    }

    /// A recording's source on or off, as `set_recording_source` takes
    /// it; the whole screen by the screen it names.
    func testRecordingSourceLinks() throws {
        let whole = SkilliLink.recordingSource(.screen, on: true, display: "main")
        XCTAssertEqual(whole.url.absoluteString, "skilli://record/source?source=screen&display=main")
        let named = SkilliLink.recordingSource(.screen, on: true, display: "LG UltraFine")
        XCTAssertEqual(named.url.absoluteString, "skilli://record/source?source=screen&display=LG%20UltraFine")
        XCTAssertEqual(SkilliLink.recordingSource(.macSound, on: false, display: nil).url.absoluteString, "skilli://record/source?source=mac_sound&on=false")
        for link in [whole, named, .recordingSource(.screen, on: true, display: nil), .recordingSource(.screen, on: false, display: nil),
                     .recordingSource(.webcam, on: true, display: nil), .recordingSource(.microphone, on: false, display: nil)] {
            XCTAssertEqual(SkilliLink.parse(link.url), link, link.url.absoluteString)
        }
        XCTAssertEqual(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/SOURCE?source=Screen&on=1&display=%20meeting%20"))),
                       .recordingSource(.screen, on: true, display: "meeting"), "trimmed, any case")
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/source"))), "which source")
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/source?source=keyboard"))))
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/source?source=screen&on=maybe"))))
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/source?source=webcam&display=main"))), "a screen named for the webcam")
        XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: "skilli://record/source?source=screen&on=false&display=main"))),
                     "a screen named to turn it off")
    }

    func testWhatIsNotALink() throws {
        for text in ["skilli://run", "skilli://run/", "skilli://nothing/here", "https://run/cmd:emoji", "skilli://commands/import?command=x",
                     "skilli://layout"] {
            XCTAssertNil(SkilliLink.parse(try XCTUnwrap(URL(string: text))), text)
        }
        // Import links stay CommandLink's.
        XCTAssertNotNil(CommandLink.parse(try XCTUnwrap(URL(string: "skilli://commands/import?command=x"))))
    }

    func testEveryCatalogEntryHasALinkThatFindsItAgain() throws {
        let google = Quicklink.defaults[0]
        let bare = Quicklink(name: "Intranet", keyword: "", url: "https://intranet.example/{query}")
        let skillie = try XCTUnwrap(ScriptCommand.parse("""
        #!/bin/bash
        # @skilli.schemaVersion 1
        # @skilli.title Deploy
        # @skilli.mode compact
        echo done
        """, path: "/Users/me/skillies/tools/deploy.sh"))
        let input = FeatureCatalog.Input(
            commands: [.init(id: "translate", title: "Translate", oneLine: "")],
            snippets: [Snippet(id: "addr", name: "Address", keyword: ";addr", text: "12 rue")],
            skillies: [skillie],
            quicklinks: [google, bare],
            layouts: [SavedWindowLayout(id: "coding", name: "Coding", windows: [])]
        )
        let folders = ["/Users/me/skillies"]
        for entry in FeatureCatalog.entries(input) {
            let link = SkilliLink.link(for: entry, quicklinks: input.quicklinks) { SkilliLink.skilliePath($0, folders: folders) }
            XCTAssertEqual(SkilliLink.parse(link.url), link, entry.id)
            switch link {
            case .run(let id): XCTAssertEqual(id, entry.id)
            case .quicklink(let name, _): XCTAssertEqual(entry.run, .quicklink(SkilliLink.quicklink(named: name, in: input.quicklinks)?.id ?? UUID()))
            case .layout(let id): XCTAssertEqual(entry.run, .layout(id))
            case .skillie(let path, _):
                XCTAssertEqual(path, "tools/deploy.sh")
                XCTAssertEqual(SkilliLink.skillie(at: path, among: [skillie.path], folders: folders), skillie.path)
            case .doHere:
                XCTFail("no Catalog entry is a “do it here”: \(entry.id)")
            case .record, .recording, .recordingSource, .importRecording, .openRecording, .recordingFollowUp, .renameRecording:
                XCTFail("Record Meeting's and Import Recording's links are their entries': \(entry.id)")
            case .workflow:
                XCTFail("no Catalog entry starts a GitHub workflow: \(entry.id)")
            }
        }
        XCTAssertEqual(SkilliLink.link(for: FeatureCatalog.entries(input).first { $0.id == "quicklink:\(google.id.uuidString)" }!,
                                       quicklinks: input.quicklinks), .quicklink("g", query: nil))
        XCTAssertEqual(SkilliLink.link(for: FeatureCatalog.entries(input).first { $0.id == "quicklink:\(bare.id.uuidString)" }!,
                                       quicklinks: input.quicklinks), .quicklink(bare.id.uuidString, query: nil), "no keyword: its id")
    }

    func testQuicklinksAndSkilliesFound() {
        let links = Quicklink.defaults + [Quicklink(name: "Google Twice", keyword: "G", url: "https://example.com/{query}")]
        XCTAssertEqual(links[0].linkName(among: links), links[0].id.uuidString, "a keyword two quicklinks share: the id")
        XCTAssertEqual(SkilliLink.quicklink(named: "YT", in: links)?.name, "YouTube")
        XCTAssertEqual(SkilliLink.quicklink(named: "maps", in: links)?.name, "Maps", "by name")
        XCTAssertEqual(SkilliLink.quicklink(named: links[1].id.uuidString, in: links)?.name, "YouTube")
        XCTAssertNil(SkilliLink.quicklink(named: "nope", in: links))

        let folders = ["/s/skillies", "/other/"]
        let paths = ["/s/skillies/hello.sh", "/s/skillies/tools/deploy.sh", "/other/deploy.sh"]
        XCTAssertEqual(SkilliLink.skilliePath("/s/skillies/tools/deploy.sh", folders: folders), "tools/deploy.sh")
        XCTAssertEqual(SkilliLink.skilliePath("/elsewhere/x.sh", folders: folders), "x.sh")
        XCTAssertEqual(SkilliLink.skillie(at: "deploy.sh", among: paths, folders: folders), "/other/deploy.sh", "the same place first")
        XCTAssertEqual(SkilliLink.skillie(at: "moved/hello.sh", among: paths, folders: folders), "/s/skillies/hello.sh", "moved: the only one with that name")
        XCTAssertNil(SkilliLink.skillie(at: "x/deploy.sh", among: paths, folders: folders), "two with that name: none")
    }

    /// A web page can open these: what changes the Mac out of sight, types
    /// or runs the user's code asks first; opening and reading run at once.
    func testWhatAsksFirst() {
        // Wi-Fi off cuts the user off; Show Desktop and Arrange Windows move every window.
        for command in [SystemCommand.lockScreen, .sleep, .sleepDisplays, .ejectDisks, .toggleHiddenFiles, .cleanKeyboard, .toggleMicrophone,
                        .pasteLatestScreenshot, .wifiOff, .showDesktop, .arrangeWindows] {
            XCTAssertTrue(SkilliLink.asksFirst(.system(command)), command.rawValue)
        }
        // Wi-Fi on is seen at once and undone as easily.
        for command in [SystemCommand.toggleDarkMode, .playPause, .volumeUp, .mute, .systemInfo, .speedTest, .pickColor, .keepAwake, .hideOtherApps,
                        .wifiOn] {
            XCTAssertFalse(SkilliLink.asksFirst(.system(command)), command.rawValue)
        }
        // Those asking in the card anyway are not asked twice.
        for command in SystemCommand.allCases where command.asksAnyway {
            XCTAssertFalse(SkilliLink.asksFirst(.system(command)), command.rawValue)
        }
        XCTAssertEqual(Set(SystemCommand.allCases.filter(\.asksAnyway)), [.emptyTrash, .restart, .shutDown, .logOut, .quitAllApps, .quitOtherApps])
        XCTAssertTrue(SkilliLink.asksFirst(.command(.quit)))
        // A page could read the user's copies pasted in its own field.
        XCTAssertTrue(SkilliLink.asksFirst(.command(.pasteInSequence)))
        for id in LauncherCommand.ID.allCases where id != .quit && id != .pasteInSequence {
            XCTAssertFalse(SkilliLink.asksFirst(.command(id)), id.rawValue)
        }
        for run: CatalogEntry.Run in [.snippet("addr"), .skillie("/x.sh"), .prompt("translate"), .transform(.uppercase), .askByVoice, .dictate] {
            XCTAssertTrue(SkilliLink.asksFirst(run), "\(run)")
        }
        // The volume at a level and Bluetooth devices type their words first;
        // Auto Quit opens its pane.
        for run: CatalogEntry.Run in [.window(.leftHalf), .type("timer ", hint: nil), .ask, .settings("snippets"), .layout("coding"), .quicklink(UUID()),
                                      .type("volume ", hint: nil), .type("bluetooth ", hint: nil), .settings("windows")] {
            XCTAssertFalse(SkilliLink.asksFirst(run), "\(run)")
        }
    }
}
