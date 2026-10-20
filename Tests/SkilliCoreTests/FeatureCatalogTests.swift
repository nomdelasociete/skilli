@testable import SkilliCore
import XCTest

final class FeatureCatalogTests: XCTestCase {
    private let entries = FeatureCatalog.entries()

    func testEveryLauncherCommandIsThereOnce() {
        for id in LauncherCommand.ID.allCases {
            XCTAssertEqual(entries.filter { $0.run == .command(id) }.count, 1, "\(id)")
        }
        XCTAssertEqual(Set(LauncherCommand.all.map(\.id)), Set(LauncherCommand.ID.allCases), "every command has its row in the launcher")
    }

    func testEveryMacCommandAndWindowPlaceIsThereOnce() {
        for command in SystemCommand.allCases {
            XCTAssertEqual(entries.filter { $0.run == .system(command) }.count, 1, "\(command)")
        }
        for layout in WindowLayout.allCases {
            XCTAssertEqual(entries.filter { $0.run == .window(layout) }.count, 1, "\(layout)")
        }
    }

    func testEachEntryOnceWithOneLineOfItsOwn() {
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "ids are unique")
        XCTAssertEqual(Set(entries.map(\.title)).count, entries.count, "titles are unique")
        for entry in entries {
            XCTAssertFalse(entry.oneLine.trimmingCharacters(in: .whitespaces).isEmpty, entry.title)
            XCTAssertLessThanOrEqual(entry.oneLine.count, 80, "\(entry.title): one line")
            XCTAssertFalse(entry.oneLine.hasSuffix("."), "\(entry.title): no period, like the rest")
            XCTAssertNotEqual(entry.oneLine, entry.title, entry.title)
            XCTAssertNil(entry.oneLine.range(of: #"\bAI\b"#, options: .regularExpression), "\(entry.title): the brand says SI")
        }
    }

    func testGroupsInOrderEachWithEntries() {
        let sections = FeatureCatalog.sections(entries)
        // In Your Apps only with a linked app installed (CleanShot X).
        XCTAssertEqual(sections.map(\.group), CatalogEntry.Group.allCases.filter { $0 != .apps }, "each group once, in order")
        XCTAssertEqual(sections.map(\.group.title), ["Find", "Do", "Write", "Stay on Top", "Yours", "skil.li"])
        let withApps = FeatureCatalog.sections(FeatureCatalog.entries(FeatureCatalog.Input(appLinks: CleanShot.commands)))
        XCTAssertEqual(withApps.map(\.group), CatalogEntry.Group.allCases)
        XCTAssertEqual(withApps.map(\.group.title), ["Find", "Do", "Write", "Stay on Top", "In Your Apps", "Yours", "skil.li"])
        XCTAssertFalse(entries.contains { $0.title.localizedCaseInsensitiveContains("open app") }, "apps are implicit")
    }

    /// One row for System Settings' panes and one per sound direction, not
    /// one per pane or device.
    func testOneRowForPanesAndForEachSoundDirection() {
        XCTAssertEqual(entries.filter { $0.title.contains("System Settings") }.count, 1)
        XCTAssertEqual(entries.filter { $0.id == "catalog.soundOutput" || $0.id == "catalog.microphone" }.count, 2)
    }

    func testFilteringPutsTheBestFirst() {
        XCTAssertEqual(FeatureCatalog.filter(entries, "kill").first?.id, "cmd:killProcess")
        XCTAssertEqual(FeatureCatalog.filter(entries, " kill").first?.id, "cmd:killProcess", "? kill: the space after ? does not count")
        XCTAssertEqual(FeatureCatalog.filter(entries, "timer").first?.id, "catalog.timer")
        XCTAssertEqual(FeatureCatalog.filter(entries, "left half").first?.id, "system:window.leftHalf")
        XCTAssertEqual(FeatureCatalog.filter(entries, "emoji").first?.id, "cmd:emoji")
        XCTAssertEqual(FeatureCatalog.filter(entries, "lock").first?.id, "system:lockScreen")
        XCTAssertEqual(FeatureCatalog.filter(entries, "contacts").first?.id, "cmd:searchContacts")
        XCTAssertEqual(FeatureCatalog.filter(entries, "si").first?.id, "si:ask", "SI, the word the user reads for AI")
        XCTAssertEqual(FeatureCatalog.filter(entries, "dictate").first?.id, "catalog.dictate")
        XCTAssertEqual(FeatureCatalog.filter(entries, "dictée").first?.id, "catalog.dictate", "in French too")
        XCTAssertEqual(entries.first { $0.id == "catalog.dictate" }?.group, .write)
        XCTAssertEqual(FeatureCatalog.filter(entries, "@").map(\.id), ["cmd:searchContacts"], "a prefix finds its row")
        XCTAssertEqual(FeatureCatalog.filter(entries, "fenetre gauche").first?.id, "system:window.leftHalf", "accents aside, French words")
        XCTAssertEqual(FeatureCatalog.filter(entries, "").map(\.id), entries.map(\.id), "nothing typed: everything, in order")
        XCTAssertTrue(FeatureCatalog.filter(entries, "zqxj").isEmpty)
    }

    /// Every word typed starts a word of the entry: letters scattered in a
    /// name do not count.
    func testOnlyWordStartsCount() {
        let kill = FeatureCatalog.filter(entries, "kill").map(\.title)
        XCTAssertFalse(kill.contains { $0.contains("skil.li") }, "“kill” is not in “skil.li”: \(kill)")
        let leftHalf = FeatureCatalog.filter(entries, "left half").map(\.id)
        XCTAssertEqual(leftHalf, ["system:window.leftHalf"], "both words, in the title or its line")
    }

    func testFilteredGroupsStayTogether() {
        let found = FeatureCatalog.filter(entries, "window")
        let groups = FeatureCatalog.sections(found).map(\.group)
        XCTAssertEqual(groups.count, Set(groups).count, "a group shows once: \(groups)")
        XCTAssertEqual(found.first?.group, .act)
    }

    /// The keycap is the string the launcher's parser reads: typed with
    /// words after it, it opens that mode with those words.
    func testEveryPrefixShownOpensItsMode() throws {
        for entry in entries {
            guard case .command(let id) = entry.run, let prefix = entry.prefix else { continue }
            XCTAssertEqual(prefix, LauncherPrefix.shown(for: id), entry.title)
            let mode = try XCTUnwrap(LauncherPrefix.mode(of: prefix + "salut"), entry.title)
            XCTAssertEqual(mode.command, id, entry.title)
            XCTAssertEqual(mode.rest, "salut", entry.title)
        }
        let withPrefix = entries.filter { if case .command = $0.run { $0.prefix != nil } else { false } }.map(\.id)
        XCTAssertEqual(Set(withPrefix), ["cmd:killProcess", "cmd:homebrew", "cmd:searchHistory", "cmd:searchFiles", "cmd:searchContacts",
                                         "cmd:reminders", "cmd:github", "cmd:agenda", "cmd:searchTabs", "cmd:emoji", "cmd:clipboardHistory",
                                         "cmd:searchSnippets", "cmd:catalog", "cmd:searchMenus", "cmd:searchGIFs"])
    }

    /// The launcher's own parsers read the same lists.
    func testTheParsersReadTheSamePrefixes() {
        XCTAssertEqual(ProcessListing.query(LauncherPrefix.shown(for: .killProcess)! + "gather"), .name("gather"))
        XCTAssertEqual(ClipboardSearch.modeFilter(LauncherPrefix.shown(for: .clipboardHistory)! + "facture"), "facture")
        XCTAssertEqual(FileMeaning.modeFilter(LauncherPrefix.shown(for: .searchFiles)! + "contrat"), "contrat")
        XCTAssertEqual(HistoryMeaning.modeFilter(LauncherPrefix.shown(for: .searchHistory)! + "impôts"), "impôts")
        XCTAssertEqual(SnippetMeaning.modeFilter(LauncherPrefix.shown(for: .searchSnippets)! + "iban"), "iban")
        XCTAssertEqual(LauncherPrefix.mode(of: "Snippet adresse bureau")?.command, .searchSnippets)
        XCTAssertNil(LauncherPrefix.mode(of: "snipaste"))
        XCTAssertEqual(LauncherPrefix.mode(of: "@jean")?.command, .searchContacts)
        XCTAssertEqual(LauncherPrefix.mode(of: ":smile")?.rest, "smile")
        XCTAssertEqual(LauncherPrefix.mode(of: "?kill")?.command, .catalog)
        XCTAssertEqual(LauncherPrefix.mode(of: "Tâches pain")?.command, .reminders)
        XCTAssertNil(LauncherPrefix.mode(of: "clip studio"))
        XCTAssertNil(LauncherPrefix.mode(of: "figma"))
        XCTAssertNil(LauncherPrefix.mode(of: "killer whale"))
    }

    /// What Return types for the user to go on is read by its parser once
    /// the rest is typed.
    func testWhatReturnTypesIsReadOnceFinished() throws {
        func typed(_ id: String) throws -> String {
            let entry = try XCTUnwrap(entries.first { $0.id == id })
            guard case .type(let text, _) = entry.run else { throw XCTSkip("\(id) does not type") }
            XCTAssertEqual(entry.prefix, text, "the keycap is what Return types")
            return text
        }
        XCTAssertEqual(TimerRequest.parse(try typed("catalog.timer") + "10 min tea")?.seconds, 600)
        XCTAssertEqual(AwakeRequest.parse(try typed("catalog.awake") + "2h"), .awake(seconds: 7_200))
        XCTAssertNotNil(EventRequest.parse(try typed("catalog.event") + "lunch with Paul tomorrow 1pm"))
        XCTAssertEqual(ReminderRequest.parse(try typed("catalog.remind") + "to call Paul tomorrow 9am")?.title, "Call Paul")
        XCTAssertEqual(VolumeRequest.parse(try typed("catalog.volume") + "30 %"), 30)
    }

    func testWhatTheUserMadeComesInItsGroup() throws {
        let script = try XCTUnwrap(ScriptCommand.parse("""
        #!/bin/bash
        # @skilli.schemaVersion 1
        # @skilli.title Deploy Site
        # @skilli.mode compact
        # @skilli.description Ships the website.
        echo done
        """, path: "/skillies/deploy.sh"))
        let layout = SavedWindowLayout(id: "coding", name: "Coding", windows: [
            .init(bundleID: "a", appName: "Xcode", title: "", index: 0, frame: .zero)
        ])
        let input = FeatureCatalog.Input(
            commands: [.init(id: "fix", title: "Fix Spelling & Grammar", oneLine: "Fixes spelling and grammar in the selected text"),
                       .init(id: "mine", title: "Summarize", oneLine: "")],
            snippets: [Snippet(id: "addr", name: "Address", keyword: ";addr", text: "12 rue des Lilas\n75011 Paris")],
            skillies: [script],
            quicklinks: Quicklink.defaults,
            layouts: [layout],
            appLinks: CleanShot.commands
        )
        let all = FeatureCatalog.entries(input)
        func entry(_ id: String) throws -> CatalogEntry { try XCTUnwrap(all.first { $0.id == id }, id) }
        XCTAssertEqual(try entry("si:fix").group, .write)
        XCTAssertEqual(try entry("si:mine").oneLine, "Your own SI command")
        XCTAssertEqual(try entry("snippet:addr").prefix, ";addr")
        XCTAssertEqual(try entry("snippet:addr").oneLine, "Types “12 rue des Lilas”")
        XCTAssertEqual(try entry("script:/skillies/deploy.sh").oneLine, "Ships the website.")
        XCTAssertEqual(try entry("script:/skillies/deploy.sh").group, .yours)
        let google = try entry("quicklink:\(Quicklink.defaults[0].id.uuidString)")
        XCTAssertEqual(google.prefix, "g ")
        XCTAssertEqual(google.oneLine, "Searches Google: “g what you look for”")
        XCTAssertEqual(try entry("layout:coding").oneLine, "Puts back Xcode")
        XCTAssertNil(all.first { $0.id == "catalog.snippets" || $0.id == "catalog.skillies" || $0.id == "catalog.quicklinks" },
                     "the rows that point to Settings go once there is one")
        XCTAssertEqual(FeatureCatalog.sections(all).map(\.group), CatalogEntry.Group.allCases)
    }

    func testNothingMadeYetPointsWhereToMakeIt() {
        XCTAssertEqual(entries.first { $0.id == "catalog.snippets" }?.run, .settings("snippets"))
        XCTAssertEqual(entries.first { $0.id == "catalog.skillies" }?.run, .settings("skillies"))
        XCTAssertEqual(entries.first { $0.id == "catalog.quicklinks" }?.run, .settings("catalog/quicklinks"))
    }

    /// New Snippet, New Quicklink and New Command are there whether the user
    /// made some or none, each after what it makes, and found in English
    /// and French.
    func testNewOnesAreThereWithOrWithoutWhatTheyMake() throws {
        let made = FeatureCatalog.entries(FeatureCatalog.Input(
            commands: [.init(id: "mine", title: "Summarize", oneLine: "")],
            snippets: [Snippet(id: "addr", name: "Address", keyword: ";addr", text: "12 rue des Lilas")],
            quicklinks: Quicklink.defaults
        ))
        for all in [entries, made] {
            let ids = all.map(\.id)
            func index(_ id: String) throws -> Int { try XCTUnwrap(ids.firstIndex(of: id), id) }
            XCTAssertEqual(all.first { $0.id == "cmd:newSnippet" }?.group, .write)
            XCTAssertEqual(all.first { $0.id == "cmd:newCommand" }?.group, .write)
            XCTAssertEqual(all.first { $0.id == "cmd:newQuicklink" }?.group, .yours)
            XCTAssertGreaterThan(try index("cmd:newSnippet"), ids.lastIndex { $0.hasPrefix("snippet:") || $0 == "catalog.snippets" } ?? -1)
            XCTAssertGreaterThan(try index("cmd:newQuicklink"), ids.lastIndex { $0.hasPrefix("quicklink:") || $0 == "catalog.quicklinks" } ?? -1)
        }
        XCTAssertGreaterThan(try XCTUnwrap(made.map(\.id).firstIndex(of: "cmd:newCommand")), try XCTUnwrap(made.map(\.id).firstIndex(of: "si:mine")))
        XCTAssertEqual(FeatureCatalog.filter(entries, "new snippet").first?.id, "cmd:newSnippet")
        XCTAssertEqual(FeatureCatalog.filter(entries, "nouveau snippet").first?.id, "cmd:newSnippet")
        XCTAssertEqual(FeatureCatalog.filter(entries, "add quicklink").first?.id, "cmd:newQuicklink")
        XCTAssertEqual(FeatureCatalog.filter(entries, "nouvelle commande").first?.id, "cmd:newCommand")
        XCTAssertTrue(try XCTUnwrap(entries.first { $0.id == "cmd:newSnippet" }).takesAlias, "a launcher row of its own")
    }

    /// In the launcher's own search: "new snippet" names New Snippet first,
    /// "snippets" still Search Snippets.
    func testNewOnesComeFirstForTheirWordsOnly() {
        func best(_ text: String) -> LauncherCommand.ID? {
            let query = FuzzyMatcher.Query(text)
            return LauncherCommand.all.compactMap { command in command.score(query).map { (command.id, $0) } }.max { $0.1 < $1.1 }?.0
        }
        XCTAssertEqual(best("new snippet"), .newSnippet)
        XCTAssertEqual(best("add snippet"), .newSnippet)
        XCTAssertEqual(best("nouveau snippet"), .newSnippet)
        XCTAssertEqual(best("new quicklink"), .newQuicklink)
        XCTAssertEqual(best("new command"), .newCommand)
        XCTAssertEqual(best("nouvelle commande"), .newCommand)
        XCTAssertEqual(best("snippets"), .searchSnippets)
    }

    // MARK: - Off (Settings → Catalog)

    /// Each launcher row belongs to one entry: its own, or the one whose
    /// words make it or whose search finds it.
    func testEachRowBelongsToItsEntry() {
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "cmd:emoji"), "cmd:emoji")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:lockScreen"), "system:lockScreen")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:window.leftHalf"), "system:window.leftHalf")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "calculation"), "catalog.calculator")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "start-timer"), "catalog.timer")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "timer:4F2A"), "catalog.timer", "a timer running")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "keep-awake-for"), "catalog.awake")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:sound.output.BuiltInSpeakerDevice"), "catalog.soundOutput")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:sound.input.BuiltInMicrophoneDevice"), "catalog.microphone")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:settings:com.apple.Displays-Settings.extension"), "catalog.settingsPanes")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "ask"), "si:ask", "Ask “…”, the last row")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:bluetooth.a4-83-e7-11-22-33"), "catalog.bluetooth")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:volume.30"), "catalog.volume")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "system:wifiOff"), "system:wifiOff", "a Mac command is its own row")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "contact:ABC-123"), "cmd:searchContacts")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "project:com.todesktop.cursor:/Users/me/site"), "cmd:searchProjects")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "app:/Applications/Safari.app"), "app:/Applications/Safari.app", "apps belong to none")
        XCTAssertEqual(FeatureCatalog.entryID(ofRow: "asking"), "asking", "a whole id, not its start")
    }

    /// Every entry rows are given to is in the list: a typo would make a
    /// switch that turns nothing off.
    func testRowsGoToEntriesThatExist() {
        let ids = Set(entries.map(\.id))
        for owner in FeatureCatalog.rowOwners {
            XCTAssertTrue(ids.contains(owner.entry), owner.entry)
        }
    }

    /// A switch only where Off takes something out of the results.
    func testOnlyEntriesWithRowsCanBeOff() throws {
        func entry(_ id: String) throws -> CatalogEntry { try XCTUnwrap(entries.first { $0.id == id }, id) }
        for id in ["cmd:emoji", "cmd:killProcess", "system:lockScreen", "system:window.center", "si:ask", "catalog.calculator",
                   "catalog.timer", "catalog.awake", "catalog.soundOutput", "catalog.settingsPanes", "catalog.event", "catalog.remind"] {
            XCTAssertTrue(try entry(id).canBeOff, id)
        }
        for id in ["catalog.voice", "catalog.dictate", "catalog.doItHere", "catalog.text.uppercase", "catalog.snippets", "catalog.skillies",
                   "catalog.quicklinks"] {
            XCTAssertFalse(try entry(id).canBeOff, id)
        }
    }

    /// An alias reaches what is a launcher row of its own, as ⌘K → Set
    /// Alias… in the "?" does.
    func testOnlyRowsOfTheirOwnTakeAnAlias() throws {
        func entry(_ id: String) throws -> CatalogEntry { try XCTUnwrap(entries.first { $0.id == id }, id) }
        for id in ["cmd:emoji", "cmd:clipboardHistory", "system:lockScreen", "system:window.leftHalf", "si:ask"] {
            XCTAssertTrue(try entry(id).takesAlias, id)
        }
        for id in ["catalog.timer", "catalog.calculator", "catalog.doItHere", "catalog.voice", "catalog.dictate", "catalog.text.lowercase",
                   "catalog.snippets"] {
            XCTAssertFalse(try entry(id).takesAlias, id)
        }
    }

    /// The launcher's results leave out the rows of what is off, and only
    /// those; nothing off keeps everything.
    func testOffLeavesOutItsRowsOnly() {
        let off: Set<String> = ["cmd:killProcess", "catalog.calculator", "catalog.soundOutput"]
        XCTAssertFalse(FeatureCatalog.shows(row: "cmd:killProcess", off: off))
        XCTAssertFalse(FeatureCatalog.shows(row: "calculation", off: off))
        XCTAssertFalse(FeatureCatalog.shows(row: "system:sound.output.AirPods", off: off))
        XCTAssertTrue(FeatureCatalog.shows(row: "system:sound.input.AirPods", off: off), "the microphone is its own entry")
        XCTAssertTrue(FeatureCatalog.shows(row: "cmd:emoji", off: off))
        XCTAssertTrue(FeatureCatalog.shows(row: "app:/Applications/Kill.app", off: off), "apps are never off")
        XCTAssertTrue(FeatureCatalog.shows(row: "cmd:killProcess", off: []))
    }

    func testACommandsLineIsItsPromptsFirstSentence() {
        XCTAssertEqual(FeatureCatalog.firstSentence(ofPrompt: "Translate into natural Spanish. Keep the tone.\n\n{selection}"),
                       "Translate into natural Spanish")
        XCTAssertEqual(FeatureCatalog.firstSentence(ofPrompt: "{selection}\n\nSummarize this in three bullets"), "Summarize this in three bullets")
        XCTAssertEqual(FeatureCatalog.firstSentence(ofPrompt: "Correct this text: every mistake"), "Correct this text")
        XCTAssertEqual(FeatureCatalog.firstSentence(ofPrompt: "{ask.instruction}"), "")
    }
}
