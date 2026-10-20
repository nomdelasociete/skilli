import XCTest
@testable import SkilliCore

final class HealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var working: Health.Facts {
        var facts = Health.Facts()
        facts.accessibility = true
        facts.superKeyActive = true
        facts.superKeyStatus = "Mapped to F18 by skil.li"
        facts.shortcutsActive = true
        facts.writer = "Claude · Haiku"
        facts.deciders = ["TypeSafe Jev", "OpenAI"]
        facts.clipboardHistory = true
        facts.calendarAccess = true
        facts.screenRecording = true
        facts.githubSignedIn = true
        facts.githubUpdated = now.addingTimeInterval(-120)
        facts.backupFolderSet = true
        facts.lastBackup = now.addingTimeInterval(-2 * 86_400)
        return facts
    }

    func testAllWell() {
        let lines = Health.lines(working, now: now)
        XCTAssertTrue(lines.allSatisfy { $0.state == .ok }, lines.filter { $0.state != .ok }.map(\.feature).description)
        XCTAssertEqual(lines.first { $0.feature == "Ask's choices" }?.detail, "TypeSafe Jev, then OpenAI")
        XCTAssertEqual(lines.first { $0.feature == "GitHub" }?.detail, "Updated 2 min ago")
        XCTAssertEqual(lines.first { $0.feature == "Backup" }?.detail, "Last one 2 days ago")
        XCTAssertTrue(lines.allSatisfy { $0.pane == nil })
    }

    func testWhatNeedsTheUserSaysWhereToFixIt() {
        var facts = working
        facts.accessibility = false
        facts.secureInputApp = "1Password"
        facts.writer = nil
        facts.writerProblem = "Not set up: sign in to Claude Code in Settings → SI Accounts"
        facts.deciders = []
        facts.clipboardAsksEachTime = true
        facts.githubProblem = "GitHub: Bad credentials"
        facts.backupProblem = "The folder is gone"
        let lines = Dictionary(uniqueKeysWithValues: Health.lines(facts, now: now).map { ($0.feature, $0) })
        XCTAssertEqual(lines["Accessibility"]?.pane, "Privacy")
        XCTAssertEqual(lines["Shortcuts"]?.detail, "Paused: Secure Input is on in 1Password")
        XCTAssertEqual(lines["Writing"]?.pane, "SI Accounts")
        XCTAssertEqual(lines["Ask's choices"]?.state, .attention)
        XCTAssertEqual(lines["Clipboard history"]?.pane, "Privacy")
        XCTAssertEqual(lines["GitHub"]?.detail, "GitHub: Bad credentials")
        XCTAssertEqual(lines["Backup"]?.state, .attention)
    }

    func testOffIsNotAProblem() {
        var facts = working
        facts.clipboardHistory = false
        facts.githubSignedIn = false
        facts.backupFolderSet = false
        let lines = Dictionary(uniqueKeysWithValues: Health.lines(facts, now: now).map { ($0.feature, $0) })
        XCTAssertEqual(lines["Clipboard history"]?.state, .off)
        XCTAssertEqual(lines["GitHub"]?.state, .off)
        XCTAssertEqual(lines["Backup"]?.detail, "No folder chosen")
    }

    func testDiagnosticsArePlainLines() {
        let text = Health.diagnostics(Health.lines(working, now: now), version: "1.0 (42)", system: "macOS 27.0")
        let rows = text.split(separator: "\n")
        XCTAssertEqual(rows.first, "skil.li 1.0 (42) · macOS 27.0")
        XCTAssertEqual(rows.count, 11)
        XCTAssertTrue(text.contains("Accessibility: ok — Allowed"))
    }
}
