@testable import SkilliCore
import XCTest

final class SettingsTableTests: XCTestCase {
    /// `SettingsPane.title`, as the app names its panes.
    private let titles = ["general": "General", "keys": "Keys", "privacy": "Privacy", "backup": "Backup", "launcher": "Launcher",
                          "clipboard": "Clipboard", "snippets": "Snippets", "emoji": "Emoji", "gifs": "GIFs", "windows": "Windows", "calendar": "Calendar",
                          "recorder": "Recorder", "reminders": "Reminders", "github": "GitHub", "apps": "Apps", "yourDetails": "Your Details", "ask": "Ask",
                          "commands": "Commands", "tools": "Tools", "skillies": "Skillies", "aiAccounts": "SI Accounts", "catalog": "Catalog",
                          "about": "About"]
    private func title(_ pane: String) -> String { titles[pane] ?? pane }

    private func entry(_ key: String) throws -> SettingEntry {
        try XCTUnwrap(SettingsTable.entries.first { $0.key == key })
    }

    // MARK: - The table

    func testEveryEntryIsInAPaneWithAUniqueKeyAndName() {
        let entries = SettingsTable.entries
        XCTAssertEqual(Set(entries.map(\.key)).count, entries.count, "keys are unique")
        XCTAssertEqual(Set(entries.map { "\($0.pane)/\(SettingsTable.folded($0.name))" }).count, entries.count, "names unique in a pane")
        for entry in entries {
            XCTAssertTrue(SettingsTable.panes.contains(entry.pane), "\(entry.key): pane \(entry.pane)")
        }
        XCTAssertEqual(Set(SettingsTable.panes), Set(titles.keys))
        // In the panes' order, as get_settings lists them.
        let order = entries.map { SettingsTable.panes.firstIndex(of: $0.pane) ?? -1 }
        XCTAssertEqual(order, order.sorted())
    }

    func testEverySettableEntryHasToolsThatExist() {
        let known = Set(SettingsTable.Tool.all + ["create_skillie", "create_skill", "create_app_link"])
        XCTAssertEqual(Set(SettingsTable.Tool.all).count, SettingsTable.Tool.all.count)
        for entry in SettingsTable.entries {
            switch entry.access {
            case .tools(let tools):
                XCTAssertFalse(tools.isEmpty, entry.key)
                for tool in tools { XCTAssertTrue(known.contains(tool), "\(entry.key): \(tool)") }
                XCTAssertFalse(entry.secret, "\(entry.key): a secret is never set by tools")
            case .paneOnly(let why):
                XCTAssertFalse(why.isEmpty, entry.key)
            }
        }
    }

    func testChoicesHaveDistinctValues() {
        for entry in SettingsTable.entries {
            let options = SettingsTable.options(of: entry)
            if case .choice = entry.kind { XCTAssertGreaterThan(options.count, 1, entry.key) }
            XCTAssertEqual(Set(options.map(\.value)).count, options.count, entry.key)
            XCTAssertEqual(Set(options.map { SettingsTable.folded($0.title) }).count, options.count, entry.key)
        }
    }

    func testSecretsAndRightsAreNeverSettable() throws {
        for key in ["claudeAPIKey", "openAIKey", "typeSafeKey", "relayToken", "klipyKey"] {
            let secret = try entry(key)
            XCTAssertTrue(secret.secret, key)
            XCTAssertFalse(secret.isSettable, key)
        }
        for key in ["approvalMode", "approvalRules", "toolRights", "servers", "customTools", "permissions", "relayPublicURL", "trustedLinks"] {
            XCTAssertFalse(try entry(key).isSettable, key)
        }
    }

    /// "A setting with no tool is not finished": every stored preference
    /// (a `didSet` that saves) is in the table or said not to be in a pane.
    func testEveryPreferenceHasAnEntry() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Skilli/Settings/Preferences.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"\n    var (\w+): [^\n{]+\{\n\s+didSet"#)
        let stored = Set(pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        })
        XCTAssertGreaterThan(stored.count, 40, "the pattern still finds Preferences' properties")
        let covered = SettingsTable.preferences.union(SettingsTable.notInPanes.keys)
        XCTAssertEqual(stored.subtracting(covered).sorted(), [], "preferences without an entry: add them to SettingsTable")
        XCTAssertEqual(SettingsTable.preferences.subtracting(stored).sorted(), [], "entries naming no preference")
        XCTAssertTrue(SettingsTable.preferences.isDisjoint(with: SettingsTable.notInPanes.keys))
    }

    func testNoAIInWhatUsersRead() {
        let texts = SettingsTable.entries.flatMap { [$0.name, $0.note ?? ""] + SettingsTable.options(of: $0).map(\.title) }
            + [SettingsSkill.markdown, SettingsSkill.description, SettingsSkill.pointer, SettingsReport.how]
        for text in texts {
            XCTAssertNil(text.range(of: #"\bAI\b"#, options: .regularExpression), text)
        }
    }

    func testTheSkillNamesEveryTool() {
        for tool in SettingsTable.Tool.all {
            XCTAssertTrue(SettingsSkill.markdown.contains(tool), tool)
        }
        XCTAssertTrue(SettingsSkill.markdown.hasPrefix("---\nname: set-up-skilli\n"))
        XCTAssertTrue(SettingsSkill.pointer.contains(SettingsSkill.uri))
    }

    // MARK: - Finding a setting

    func testASettingByItsNameOrKeyInAPaneByItsTitleOrId() throws {
        XCTAssertEqual(try SettingsTable.entry(pane: "Backup", setting: "How often", title: title).key, "backupSchedule")
        XCTAssertEqual(try SettingsTable.entry(pane: "backup", setting: "backupSchedule", title: title).key, "backupSchedule")
        XCTAssertEqual(try SettingsTable.entry(pane: "si accounts", setting: "pay for claude with", title: title).key, "aiEngineMode")
        XCTAssertEqual(try SettingsTable.entry(pane: nil, setting: "“Keep clipboard history”", title: title).key, "clipboardHistory")
        XCTAssertEqual(try SettingsTable.entry(pane: "", setting: "glassStyle", title: title).key, "glassStyle")
    }

    func testAnUnknownPaneOrSettingSaysWhatThereIs() {
        XCTAssertThrowsError(try SettingsTable.entry(pane: "Backups", setting: "How often", title: title)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Panes: General, Keys"), error.localizedDescription)
        }
        XCTAssertThrowsError(try SettingsTable.entry(pane: "Backup", setting: "Day", title: title)) { error in
            XCTAssertEqual(error.localizedDescription, "Backup has no setting “Day”. Its settings: Back up to, How often, Keep.")
        }
        XCTAssertThrowsError(try SettingsTable.entry(pane: nil, setting: "Volume", title: title))
        XCTAssertThrowsError(try SettingsTable.entry(pane: "About", setting: "Version", title: title)) { error in
            XCTAssertEqual(error.localizedDescription, "About has no setting tools can change.")
        }
    }

    // MARK: - Values

    func testTogglesInWordsPeopleUse() throws {
        let toggle = try entry("showMenuBarIcon")
        for word in ["true", "On", "yes", "1", "oui", "activé"] {
            XCTAssertEqual(try SettingsTable.parse(word, for: toggle, paneTitle: "General"), .bool(true), word)
        }
        for word in ["false", "off", "No", "0", "non", "désactivé"] {
            XCTAssertEqual(try SettingsTable.parse(word, for: toggle, paneTitle: "General"), .bool(false), word)
        }
        XCTAssertThrowsError(try SettingsTable.parse("maybe", for: toggle, paneTitle: "General"))
    }

    func testAChoiceByItsValueItsTitleOrItsOnlyWord() throws {
        let schedule = try entry("backupSchedule")
        XCTAssertEqual(try SettingsTable.parse("weekly", for: schedule, paneTitle: "Backup"), .text("weekly"))
        XCTAssertEqual(try SettingsTable.parse("Every week", for: schedule, paneTitle: "Backup"), .text("weekly"))
        XCTAssertEqual(try SettingsTable.parse("week", for: schedule, paneTitle: "Backup"), .text("weekly"))
        XCTAssertEqual(try SettingsTable.parse("only when i ask", for: schedule, paneTitle: "Backup"), .text("off"))
        XCTAssertThrowsError(try SettingsTable.parse("every", for: schedule, paneTitle: "Backup"), "three fit: none chosen")
        XCTAssertThrowsError(try SettingsTable.parse("sometimes", for: schedule, paneTitle: "Backup")) { error in
            XCTAssertEqual(error.localizedDescription,
                           "“sometimes” is not a value of Backup → How often. Valid: off (Only when I ask), daily (Every day), weekly (Every week), monthly (Every month).")
        }
        let keep = try entry("backupKeep")
        XCTAssertEqual(try SettingsTable.parse("30", for: keep, paneTitle: "Backup"), .text("30"))
        XCTAssertEqual(try SettingsTable.parse("all", for: keep, paneTitle: "Backup"), .text("0"))
        XCTAssertThrowsError(try SettingsTable.parse("12", for: keep, paneTitle: "Backup"))
    }

    func testChoicesThisMacHasComeFromTheApp() throws {
        let list = try entry("remindersDefaultList")
        let options = [SettingOption("", "The Reminders app's default list"), SettingOption("Courses", "Courses")]
        XCTAssertEqual(try SettingsTable.parse("courses", for: list, options: options, paneTitle: "Reminders"), .text("Courses"))
        XCTAssertEqual(try SettingsTable.parse("default list", for: list, options: options, paneTitle: "Reminders"), .text(""))
        XCTAssertThrowsError(try SettingsTable.parse("Travail", for: list, options: options, paneTitle: "Reminders")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Courses"), error.localizedDescription)
        }
    }

    func testRetentionTakesAChoiceOrDays() throws {
        let retention = try entry("clipboardRetention")
        XCTAssertEqual(try SettingsTable.parse("1 month", for: retention, paneTitle: "Clipboard"), .text("month"))
        XCTAssertEqual(try SettingsTable.parse("unlimited", for: retention, paneTitle: "Clipboard"), .text("unlimited"))
        XCTAssertEqual(try SettingsTable.parse("14", for: retention, paneTitle: "Clipboard"), .text("days:14"))
        XCTAssertEqual(try SettingsTable.parse("14 days", for: retention, paneTitle: "Clipboard"), .text("days:14"))
        XCTAssertEqual(try SettingsTable.parse("days:3", for: retention, paneTitle: "Clipboard"), .text("days:3"))
        XCTAssertThrowsError(try SettingsTable.parse("0", for: retention, paneTitle: "Clipboard"))
        XCTAssertThrowsError(try SettingsTable.parse("5000 days", for: retention, paneTitle: "Clipboard"))
        XCTAssertEqual(SettingsTable.shown(.text("days:14"), for: retention), "14 days")
        XCTAssertEqual(SettingsTable.shown(.text("days:1"), for: retention), "1 day")
        XCTAssertEqual(SettingsTable.shown(.text("week"), for: retention), "1 week")
    }

    func testAFolderMustExist() throws {
        let backup = try entry("backupFolder")
        let home = NSHomeDirectory()
        XCTAssertEqual(try SettingsTable.parse("~/Backups", for: backup, paneTitle: "Backup", isFolder: { _ in true }),
                       .text(home + "/Backups"))
        XCTAssertThrowsError(try SettingsTable.parse("/nope", for: backup, paneTitle: "Backup", isFolder: { _ in false })) { error in
            XCTAssertTrue(error.localizedDescription.hasPrefix("No folder at “/nope”"), error.localizedDescription)
        }
        XCTAssertThrowsError(try SettingsTable.parse("Backups", for: backup, paneTitle: "Backup"), "a full path")
        XCTAssertThrowsError(try SettingsTable.parse("default", for: backup, paneTitle: "Backup"), "a backup needs a folder")
        let images = try entry("imageTagsFolderPath")
        XCTAssertEqual(try SettingsTable.parse("default", for: images, paneTitle: "Clipboard"), .text(""))
        XCTAssertEqual(SettingsTable.shown(.text(""), for: images), "macOS's screenshots folder")
        XCTAssertEqual(SettingsTable.shown(.text(home + "/Pictures"), for: images), "~/Pictures")
    }

    func testThePositionOnlyGoesBack() throws {
        let place = try entry("launcherPlace")
        XCTAssertEqual(try SettingsTable.parse("reset", for: place, paneTitle: "General"), .text("default"))
        XCTAssertThrowsError(try SettingsTable.parse("top left", for: place, paneTitle: "General"))
    }

    func testAListChangesByItsItems() throws {
        XCTAssertThrowsError(try SettingsTable.parse("1Password", for: try entry("clipboardExcludedApps"), paneTitle: "Clipboard")) { error in
            XCTAssertTrue(error.localizedDescription.contains("add"), error.localizedDescription)
        }
    }

    func testTheCardSaysTheChangeInThePanesWords() throws {
        let schedule = try entry("backupSchedule")
        let shown = SettingsTable.shown(.text("weekly"), for: schedule)
        XCTAssertEqual(SettingsTable.change(schedule, paneTitle: "Backup", to: shown), "Backup: How often → Every week")
        XCTAssertEqual(SettingsTable.listChange(try entry("clipboardExcludedApps"), paneTitle: "Clipboard", adding: true, item: "1Password"),
                       "Clipboard: Never keep copies from + 1Password")
        XCTAssertEqual(SettingsTable.shown(.bool(false), for: try entry("snippetExpansion")), "Off")
        XCTAssertEqual(SettingsTable.shown(.text("Line one\nline two"), for: try entry("aboutYou")), "“Line one…”")
    }

    // MARK: - get_settings: settings, never the user's own content

    func testTheUsersOwnContentIsMarked() {
        XCTAssertEqual(Set(SettingsTable.entries.filter(\.personal).map(\.key)),
                       ["otherDetails", "people", "aboutYou", "reminderPlaces", "snippets", "quicklinks", "scheduledAsks"])
        XCTAssertTrue(SettingsTable.entries.filter(\.personal).allSatisfy { !$0.secret })
    }

    /// A scratch About You, a field's value, a snippet's text, a place's
    /// address, a person, a quicklink's address: none of it in the JSON,
    /// only whether each is set; settings themselves stay readable.
    func testNoPersonalContentLeaks() throws {
        let about = "I am Jean-François Selftest, I write in French to my clients"
        let siret = "98765432100019"
        let signature = "Best regards, Jean-François, 06 12 34 56 78"
        let address = "12 rue Secrète, 75011 Paris"
        let person = "Margot Confidentielle"
        let link = "https://intranet.example-secret.com/search?q={query}"
        let readings: [String: SettingReading] = [
            "aboutYou": SettingReading(value: .text(about)),
            "otherDetails": SettingReading(value: .list(["SIRET: \(siret)"]), items: [
                SettingItem(["field": "SIRET"], content: "value", siret),
                SettingItem(["field": "IBAN", "kept": "in the Keychain"], content: "value", "")
            ]),
            "snippets": SettingReading(value: .list(["Signature (;sig): \(signature)"]),
                                       items: [SettingItem(["name": "Signature", "keyword": ";sig"], content: "text", signature)]),
            "reminderPlaces": SettingReading(value: .list(["Bureau: \(address)"]), items: [SettingItem(["name": "Bureau"], content: "address", address)]),
            "people": SettingReading(value: .list([person])),
            "quicklinks": SettingReading(value: .list(["Intranet (in): \(link)"]),
                                         items: [SettingItem(["name": "Intranet", "keyword": "in"], content: "address", link)]),
            "backupFolder": SettingReading(value: .text("/Users/test/Backups")),
            "backupSchedule": SettingReading(value: .text("weekly"), options: SettingsTable.options(of: try entry("backupSchedule")))
        ]
        let settings = try readings.map { key, reading in SettingsReport.describe(try entry(key), reading) }
        let json = try SettingsReport.json([("Test", settings)])
        for secret in [about, siret, signature, address, person, link, "Jean-François", "Secrète", "Confidentielle", "intranet"] {
            XCTAssertFalse(json.contains(secret), "“\(secret)” leaked")
        }
        for said in [#""value":"set (11 words)""#, #""field":"SIRET","value":"set""#, #""value":"not set""#, #""text":"set""#,
                     #""address":"set""#, #""name":"Bureau""#, #""value":"set (1)""#, #""keyword":";sig""#,
                     #""value":"/Users/test/Backups""#, #""shown":"Every week""#] {
            XCTAssertTrue(json.contains(said), "missing \(said) in \(json)")
        }
        XCTAssertEqual(SettingsReport.presence(of: "  "), "not set")
        XCTAssertEqual(SettingsReport.presence(of: "one"), "set (1 word)")
    }

    func testSecretsSayOnlyWhetherTheyAreSet() throws {
        let key = SettingsReport.describe(try entry("claudeAPIKey"), SettingReading(value: .text("sk-ant-never"), isSet: true))
        XCTAssertEqual(key["value"] as? String, "set")
        XCTAssertNil(key["shown"])
    }

    // MARK: - A change asks every time

    func testASettingsChangeAsksEveryTime() {
        XCTAssertEqual(SettingsTable.Tool.changes, Set(SettingsTable.Tool.all).subtracting([SettingsTable.Tool.getSettings,
                                                                                           SettingsTable.Tool.listScheduledAsks]))
        for mode in ApprovalMode.allCases {
            for right in [nil, ToolOverride.ask, .always] {
                XCTAssertEqual(ToolPolicy.decision(risk: .changes, mode: mode, override: right, everyTime: true), .ask, "\(mode) \(String(describing: right))")
            }
            XCTAssertEqual(ToolPolicy.decision(risk: .changes, mode: mode, override: .never, everyTime: true), .block)
        }
        XCTAssertEqual(ToolPolicy.decision(risk: .changes, mode: .always, override: nil), .run, "other tools keep the mode")
    }

    // MARK: - Alerts and keys as said

    func testAlertsAsSaid() {
        XCTAssertEqual(MeetingAlert.parse("on time"), MeetingAlert(minutes: 0, style: .card))
        XCTAssertEqual(MeetingAlert.parse("5 min before"), MeetingAlert(minutes: 5, style: .card))
        XCTAssertEqual(MeetingAlert.parse("1 hour before, screens dark"), MeetingAlert(minutes: 60, style: .dark))
        XCTAssertEqual(MeetingAlert.parse("10 minutes, dark"), MeetingAlert(minutes: 10, style: .dark))
        XCTAssertEqual(MeetingAlert.parse("1h"), MeetingAlert(minutes: 60, style: .card))
        XCTAssertNil(MeetingAlert.parse("7 min before"), "not a choice")
        XCTAssertNil(MeetingAlert.parse("soon"))
        let alert = MeetingAlert(minutes: 5, style: .dark)
        XCTAssertEqual(alert.spoken, "5 min before · Card, screens dark")
        XCTAssertEqual(MeetingAlert.parse(alert.spoken), alert, "read back as said")
    }

    func testKeysAsPeopleWriteThem() throws {
        XCTAssertEqual(Chord.spec(try Chord.sequence(said: "hyper+y")), "hyper+y")
        XCTAssertEqual(Chord.spec(try Chord.sequence(said: "✦Y")), "hyper+y")
        XCTAssertEqual(Chord.spec(try Chord.sequence(said: "✦ K › U")), "hyper+k u")
        XCTAssertEqual(Chord.spec(try Chord.sequence(said: "✦K then Y")), "hyper+k y")
        XCTAssertEqual(Chord.spec(try Chord.sequence(said: "⌘⇧K")), "shift+cmd+k")
        XCTAssertEqual(Chord.spec(try Chord.sequence(said: "Caps Lock + Space")), "hyper+space")
        XCTAssertEqual(Chord.spec(try Chord.sequence(said: "cmd+,")), "cmd+,")
        XCTAssertThrowsError(try Chord.sequence(said: "hyper+"))
    }
}
