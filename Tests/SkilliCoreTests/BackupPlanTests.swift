@testable import SkilliCore
import XCTest

final class BackupPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    func testANameTellsItsDateBack() {
        let name = BackupPlan.name(at: date(15, 9, 5, 12), calendar: calendar)
        XCTAssertEqual(name, "skil.li Backup 2026-10-15 at 09.05.12.zip")
        XCTAssertEqual(BackupPlan.date(fromName: name, calendar: calendar), date(15, 9, 5, 12))
        XCTAssertNil(BackupPlan.date(fromName: "notes.zip", calendar: calendar))
        XCTAssertNil(BackupPlan.date(fromName: "skil.li Backup soon.zip", calendar: calendar))
    }

    func testTheNextOneIsDueAPeriodAfterTheLast() {
        let now = date(15, 12)
        XCTAssertNil(BackupPlan.nextDue(after: date(15, 9), schedule: .off, now: now, calendar: calendar))
        XCTAssertEqual(BackupPlan.nextDue(after: date(15, 9), schedule: .daily, now: now, calendar: calendar), date(16, 9))
        XCTAssertEqual(BackupPlan.nextDue(after: date(15, 9), schedule: .weekly, now: now, calendar: calendar), date(22, 9))
        XCTAssertEqual(BackupPlan.nextDue(after: date(15, 9), schedule: .monthly, now: now, calendar: calendar), date(15, 9, month: 11))
    }

    func testNoneYetOrMissedWhileAsleepIsDueNow() {
        let now = date(15, 12)
        XCTAssertEqual(BackupPlan.nextDue(after: nil, schedule: .weekly, now: now, calendar: calendar), now)
        XCTAssertEqual(BackupPlan.nextDue(after: date(1, 9), schedule: .daily, now: now, calendar: calendar), now)
    }

    func testOnlyTheNewestAreKept() {
        let backups = (1...6).map { (url: URL(fileURLWithPath: "/b/\($0).zip"), date: date($0, 9)) }
        XCTAssertEqual(BackupPlan.expired(backups.shuffled(), keep: 4).map(\.lastPathComponent).sorted(), ["1.zip", "2.zip"])
        XCTAssertEqual(BackupPlan.expired(backups, keep: 10), [])
        XCTAssertEqual(BackupPlan.expired(backups, keep: nil), [])
    }

    func testASummaryInTheUsersWords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("backup-summary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        for path in ["snippets/hello.md", "snippets/sign.md", "prompts/fix.md", "layouts/desk.json"] {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        try Data(#"[{"title":"a"},{"title":"b"},{"title":"c"}]"#.utf8).write(to: folder.appendingPathComponent("quicklinks.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("shortcuts.json"))
        XCTAssertEqual(BackupPlan.summary(of: folder, preferenceCount: 31),
                       ["31 settings", "2 snippets", "1 command", "3 quicklinks", "1 window layout", "your shortcuts"])
    }

    func testTheClipboardHistoryAndRecordingsAreNeverBackedUp() {
        XCTAssertEqual(BackupPlan.neverCopied, ["mcp.sock", "Clipboard", "Recordings"])
    }

    func testARestoreLeavesTheRecordingsAlone() {
        // Recordings made after the backup stay; an older backup's are not brought back.
        let plan = BackupPlan.restore(current: ["snippets", "Recordings", "tools.json"],
                                      backup: ["snippets", "Recordings", "quicklinks.json"])
        XCTAssertEqual(plan.remove, ["snippets", "tools.json"])
        XCTAssertEqual(plan.copy, ["snippets", "quicklinks.json"])
    }

    func testARestoreLeavesTheClipboardHistoryAlone() {
        // An older backup made with the clipboard history in it.
        let plan = BackupPlan.restore(current: ["snippets", "Clipboard", "mcp.sock", "tools.json"],
                                      backup: ["snippets", "Clipboard", "quicklinks.json"])
        XCTAssertEqual(plan.remove, ["snippets", "tools.json"])
        XCTAssertEqual(plan.copy, ["snippets", "quicklinks.json"])
    }

    func testASummaryNeverNamesTheClipboardHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("backup-old-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = folder.appendingPathComponent("Clipboard/history.sqlite")
        try FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: history)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("shortcuts.json"))
        XCTAssertEqual(BackupPlan.summary(of: folder, preferenceCount: 0), ["your shortcuts"])
    }

    func testWhoSyncsTheFolderByWhereItIs() {
        XCTAssertEqual(BackupPlan.syncService(ofPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/skil.li"), "iCloud")
        XCTAssertEqual(BackupPlan.syncService(ofPath: "/Users/me/Library/CloudStorage/Dropbox/Backups"), "Dropbox")
        XCTAssertEqual(BackupPlan.syncService(ofPath: "/Users/me/Library/CloudStorage/GoogleDrive-camille@example.com/My Drive"), "Google Drive")
        XCTAssertEqual(BackupPlan.syncService(ofPath: "/Users/me/Library/CloudStorage/OneDrive-Personal/skil.li"), "OneDrive")
        XCTAssertNil(BackupPlan.syncService(ofPath: "/Users/me/Documents/skil.li Backups"))
        XCTAssertNil(BackupPlan.syncService(ofPath: "/Volumes/Backup/skil.li"))
        XCTAssertNil(BackupPlan.syncService(ofPath: "/Users/me/Library/CloudStorage"))
    }
}
