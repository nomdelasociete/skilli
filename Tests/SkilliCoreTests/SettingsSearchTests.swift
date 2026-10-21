@testable import SkilliCore
import XCTest

final class SettingsSearchTests: XCTestCase {
    /// The panes as `SettingsPane` names them, with a line each (a few
    /// real ones: what the pane's line search reads).
    private let panes: [SettingsSearch.PaneInfo] = [
        ("general", "General", "Ready as soon as you log in, in the glass you like."),
        ("keys", "Keys", "Caps Lock becomes your Hyper Key, ✦, and every shortcut is yours to change."),
        ("privacy", "Privacy", "What skil.li may use on this Mac, and all it sends out: what, when, where."),
        ("backup", "Backup", "A copy of everything skil.li keeps, in a folder you choose."),
        ("launcher", "Launcher", "The search panel you open from anywhere."),
        ("clipboard", "Clipboard", "Everything you copy, and your screenshots, ready to paste again."),
        ("snippets", "Snippets", "Text you type often, from a keyword or the launcher."),
        ("emoji", "Emoji", "Every emoji, by its name or by how you feel, typed where you are."),
        ("windows", "Windows", "Where your windows go, the layouts you saved, and the apps you stopped using."),
        ("calendar", "Calendar", "Your next meeting, one key away, in the launcher and the menu bar."),
        ("reminders", "Reminders", "What you have to do, said in one sentence."),
        ("github", "GitHub", "Your pull requests and notifications in the launcher: what is ready, what waits for you."),
        ("yourDetails", "Your Details", "Forms filled in for you and your people, and commands that know who you are."),
        ("ask", "Ask", "Say what you want, in any app: skil.li answers, or does it for you."),
        ("commands", "Commands", "Your prompts, on any text, from any app."),
        ("tools", "Tools", "What commands and agents may do on your Mac."),
        ("skillies", "Skillies", "Your own scripts, run from the launcher like any command."),
        ("aiAccounts", "SI Accounts", "skil.li writes with your own Claude or ChatGPT, already paid for."),
        ("catalog", "Catalog", "Everything skil.li can do, and how you reach each one."),
        ("about", "About", "Whether each part of skil.li works now, and where to fix it.")
    ].map { SettingsSearch.PaneInfo(id: $0.0, title: $0.1, line: $0.2) }

    /// About the shortcuts a Mac has by default (Keys).
    private let shortcuts = [
        "Open skil.li", "Clipboard History", "Paste in Sequence", "Ask", "Ask by Voice", "Dictate", "Uppercase", "Lowercase", "Title Case",
        "Fix Spelling & Grammar", "Translate to English", "Left Half", "Right Half", "Top Half", "Bottom Half", "Maximize", "Center",
        "Next Display", "Restore", "Lock Screen", "Show Desktop", "Kill a Process", "Search Files", "Search Snippets",
        "Paste Latest Screenshot", "Clean Keyboard", "Emoji", "Timer", "Toggle Dark Mode", "Sleep Displays", "Empty Trash"
    ].enumerated().map { SettingsSearch.Named(pane: "keys", anchor: SettingsSearch.shortcutAnchor("s\($0.offset)"), title: $0.element) }

    private let permissions = [
        ("accessibility", "Accessibility"), ("inputMonitoring", "Input Monitoring"), ("screenRecording", "Screen Recording"),
        ("microphone", "Microphone"), ("calendar", "Calendar"), ("reminders", "Reminders"), ("contacts", "Contacts"),
        ("pasteboard", "Clipboard"), ("fullDiskAccess", "Full Disk Access"), ("camera", "Camera"), ("bluetooth", "Bluetooth")
    ].map { SettingsSearch.Named(pane: "privacy", anchor: SettingsSearch.permissionAnchor($0.0), title: $0.1) }

    private lazy var index = SettingsSearch.Index(panes: panes, shortcuts: shortcuts, permissions: permissions)

    private func first(_ query: String) -> (pane: String, anchor: String?)? {
        guard let group = index.search(query).first else { return nil }
        return (group.pane, group.paneFirst ? nil : group.hits.first?.anchor)
    }

    // MARK: - What it finds

    /// What skil.li does is in Settings too, in the Catalog (asked: "emoji"
    /// found nothing): every entry by its title, then by its line and the
    /// words people type for it; what the user made among them.
    func testCatalogEntriesAreFound() {
        let input = FeatureCatalog.Input(snippets: [Snippet(id: "s1", name: "Adresse bureau", keyword: "!!adr", text: "3 rue du Port")])
        let index = SettingsSearch.Index(panes: panes, entries: SettingsSearch.entries(FeatureCatalog.entries(input)))
        let emoji = index.search("emoji")
        // Its own pane first (asked: emoji in one place), then the Catalog's
        // entry.
        XCTAssertEqual(emoji.map(\.pane).prefix(2), ["emoji", "catalog"], "\(emoji.map(\.pane))")
        XCTAssertEqual(index.search("skin tone").first?.hits.first?.anchor, "emojiSkinTone")
        XCTAssertTrue(emoji.first { $0.pane == "catalog" }?.hits.contains { $0.title.localizedCaseInsensitiveContains("emoji") && $0.kind == .entry } == true)
        XCTAssertTrue(index.search("feeling").contains { $0.pane == "catalog" }, "its one line")
        XCTAssertTrue(index.search("adresse").first?.hits.contains { $0.title == "Adresse bureau" } == true, "a snippet the user made")
        let entries = FeatureCatalog.entries(input)
        XCTAssertGreaterThan(entries.count, 90)
        XCTAssertEqual(Set(SettingsSearch.entries(entries).map(\.anchor)).count, entries.count, "one anchor each")
    }

    func testASettingByItsNameCaseAndAccentsIgnored() {
        for query in ["glass", "GLASS", "Glâss", "  glass "] {
            let found = index.search(query)
            XCTAssertEqual(found.first?.pane, "general", query)
            XCTAssertEqual(found.first?.hits.first?.anchor, "glassStyle", query)
        }
        XCTAssertEqual(first("tap caps")?.anchor, "hyperTapSendsEscape")
        XCTAssertEqual(first("escape")?.pane, "keys")
    }

    func testWordsStartWordsInAnyOrder() {
        XCTAssertEqual(first("login")?.anchor, "openAtLogin")
        XCTAssertEqual(first("login open")?.anchor, "openAtLogin")
        // "skil.li" is also one word.
        XCTAssertTrue(index.search("skilli").flatMap(\.hits).map(\.anchor).contains("openAtLogin"))
        // Not inside a word below three letters: "in" finds what starts with it.
        let inside = index.search("in").flatMap(\.hits).map(\.title)
        XCTAssertFalse(inside.contains("Snippets"))
    }

    func testAPaneByItsTitleFirstThenByItsLine() {
        // The Clipboard pane before Privacy's Clipboard permission.
        let clipboard = index.search("clipboard")
        XCTAssertEqual(clipboard.first?.pane, "clipboard")
        XCTAssertTrue(clipboard.first?.paneMatched == true)
        XCTAssertTrue(clipboard.contains { $0.pane == "privacy" && $0.hits.contains { $0.anchor == "permission.pasteboard" } })
        // Its line: Keys says Caps Lock.
        let caps = index.search("caps lock")
        XCTAssertEqual(caps.first?.pane, "keys")
        XCTAssertEqual(caps.first?.hits.first?.anchor, "hyperTapSendsEscape")
        XCTAssertTrue(caps.first?.paneMatched == true)
        // Its row named so matches better than the pane's line: ↩ opens the row.
        XCTAssertFalse(caps.first?.paneFirst ?? true)
        XCTAssertTrue(clipboard.first?.paneFirst == true)
    }

    func testSIIsFoundAsAI() {
        XCTAssertEqual(first("ai")?.pane, "aiAccounts")
        XCTAssertEqual(first("si accounts")?.pane, "aiAccounts")
    }

    func testPluralsAndInsideWords() {
        XCTAssertEqual(first("backups")?.pane, "backup")
        // Inside a word, three letters at least: "board" in Clipboard.
        XCTAssertEqual(index.search("board").first?.pane, "clipboard")
    }

    func testShortcutsPermissionsAndRows() {
        let dark = index.search("dark mode")
        XCTAssertEqual(dark.first?.pane, "keys")
        XCTAssertEqual(dark.first?.hits.first?.title, "Toggle Dark Mode")
        XCTAssertEqual(first("screen rec")?.anchor, "permission.screenRecording")
        XCTAssertEqual(first("diagnostics")?.anchor, "section.copyDiagnostics")
        XCTAssertEqual(first("hyper key")?.anchor, "section.superKey")
    }

    func testBestRowsFirstInAPane() {
        // "Keep" itself before "Keep clipboard history".
        let keep = index.search("keep")
        XCTAssertEqual(keep.first?.pane, "backup")
        XCTAssertEqual(keep.first?.hits.first?.anchor, "backupKeep")
        let clipboard = keep.first { $0.pane == "clipboard" }
        XCTAssertEqual(clipboard?.hits.first?.anchor, "clipboardHistory")
    }

    func testNothingAndEmpty() {
        XCTAssertEqual(index.search("zzqx").count, 0)
        XCTAssertEqual(index.search("").count, 0)
        XCTAssertEqual(index.search("  ✦ ").count, 0)
    }

    func testAShortcutNamedTwiceIsFoundOnce() {
        let twice = SettingsSearch.Index(panes: panes, shortcuts: [
            SettingsSearch.Named(pane: "keys", anchor: "shortcut.a", title: "Clipboard History"),
            SettingsSearch.Named(pane: "keys", anchor: "shortcut.b", title: "Clipboard History")
        ])
        let keys = twice.search("clipboard history").first { $0.pane == "keys" }
        XCTAssertEqual(keys?.hits.map(\.anchor), ["shortcut.a"])
    }

    // MARK: - Speed

    /// Each keystroke well under 5 ms over everything, as typed letter by
    /// letter (this test builds Debug: the app is faster).
    func testAKeystrokeSearchesFast() {
        let typed = ["c", "cl", "cli", "clip", "clipb", "k", "ke", "key", "keys", "s", "sc", "scr", "screen", "screen r", "screen rec",
                     "a", "ap", "app", "apps", "z", "zz", "zzq", "dark", "dark m", "dark mode", "open skil", "login", "glass"]
        var worst = Duration.zero
        var total = Duration.zero
        let start = ContinuousClock.now
        let built = SettingsSearch.Index(panes: panes, shortcuts: shortcuts, permissions: permissions)
        let building = ContinuousClock.now - start
        for _ in 0..<20 {
            for query in typed {
                let begin = ContinuousClock.now
                _ = built.search(query)
                let took = ContinuousClock.now - begin
                worst = max(worst, took)
                total += took
            }
        }
        let average = total / (20 * typed.count)
        print("SettingsSearch: \(built.items.count) items, built in \(building), keystroke average \(average), worst \(worst)")
        XCTAssertGreaterThan(built.items.count, 120)
        XCTAssertLessThan(worst, .milliseconds(5))
        XCTAssertLessThan(average, .milliseconds(1))
    }

    // MARK: - Anchors

    func testRowsAndShownWithAreAnchors() {
        let keys = Set(SettingsTable.entries.map(\.key))
        let rows = SettingsSearch.rows.map(\.anchor)
        XCTAssertEqual(Set(rows).count, rows.count, "row anchors are unique")
        XCTAssertTrue(keys.isDisjoint(with: rows), "a row's anchor is never a setting's key")
        for row in SettingsSearch.rows {
            XCTAssertTrue(SettingsTable.panes.contains(row.pane), row.anchor)
            XCTAssertTrue(row.anchor.hasPrefix("section."), row.anchor)
            // A section named like a setting of its pane is that setting's.
            let named = SettingsTable.entries.filter { $0.pane == row.pane }.map { SettingsTable.folded($0.name) }
            XCTAssertFalse(named.contains(SettingsTable.folded(row.title)), row.title)
        }
        for (hidden, shown) in SettingsSearch.shownWith {
            XCTAssertTrue(SettingsSearch.anchors.contains(hidden), hidden)
            XCTAssertTrue(shown.isEmpty || SettingsSearch.anchors.contains(shown), shown)
            // Same pane, and never round in circles.
            let pane = { (anchor: String) in
                SettingsTable.entries.first { $0.key == anchor }?.pane ?? SettingsSearch.rows.first { $0.anchor == anchor }?.pane
            }
            if !shown.isEmpty { XCTAssertEqual(pane(hidden), pane(shown), hidden) }
            var seen: Set<String> = [hidden]
            var next = shown
            while let after = SettingsSearch.shownWith[next], !after.isEmpty {
                XCTAssertTrue(seen.insert(next).inserted, "\(hidden) leads back to itself")
                next = after
            }
        }
    }

    /// Every setting and every row of `SettingsSearch.rows` has its anchor
    /// in its pane: `.settingAnchor("key")` in Settings' sources, and none
    /// names something else. The self-test (`settingsearch`) opens each
    /// and checks it shows.
    func testEveryAnchorIsWrittenInThePanes() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Skilli/Settings")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 15)
        let call = try NSRegularExpression(pattern: #"settingAnchor\(([^)]*)\)"#)
        let literal = try NSRegularExpression(pattern: #""([^"]+)""#)
        var written = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let argument = String(text[range])
                for found in literal.matches(in: argument, range: NSRange(argument.startIndex..., in: argument)) {
                    if let key = Range(found.range(at: 1), in: argument) { written.insert(String(argument[key])) }
                }
            }
        }
        XCTAssertEqual(SettingsSearch.anchors.subtracting(written).sorted(), [], "settings without an anchor in their pane: add .settingAnchor")
        XCTAssertEqual(written.subtracting(SettingsSearch.anchors).sorted(), [], "anchors naming no setting nor row")
    }
}
