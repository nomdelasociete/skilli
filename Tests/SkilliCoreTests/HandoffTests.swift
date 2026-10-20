import XCTest
@testable import SkilliCore

final class HandoffTests: XCTestCase {
    func testConversation() {
        let claude = Handoff.conversation(request: "explique ce mot\n\n\"\"\"\nBonjour\n\"\"\"", answer: "C'est une salutation.", for: .claude)
        XCTAssertTrue(claude.contains("User:\nexplique ce mot"))
        XCTAssertTrue(claude.contains("You answered:\nC'est une salutation."))
        XCTAssertTrue(claude.hasSuffix("Go on from there when they write, in their language."))
        XCTAssertFalse(claude.contains("What you did"))
        let codex = Handoff.conversation(request: "range mes téléchargements", answer: "Fait.", steps: ["List files", "Move files"], for: .codex)
        XCTAssertTrue(codex.contains("What you did on their Mac:\n- List files\n- Move files"))
        XCTAssertTrue(codex.contains("ready for what's next"))
    }

    func testScriptQuotesEverything() {
        let script = Handoff.script(target: .claude, binary: "/Users/m e/.local/bin/claude", conversationFile: "/tmp/it's.md", directory: "/Users/m e")
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(script.contains("cd '/Users/m e' 2>/dev/null || cd ~"))
        XCTAssertTrue(script.contains("context=$(cat '/tmp/it'\\''s.md')"))
        XCTAssertTrue(script.contains("rm -f '/tmp/it'\\''s.md' \"$0\""))
        XCTAssertTrue(script.contains("exec '/Users/m e/.local/bin/claude' --append-system-prompt \"$context\""))
        let codex = Handoff.script(target: .codex, binary: "/opt/homebrew/bin/codex", conversationFile: "/tmp/c.md", directory: "/Users/me")
        XCTAssertTrue(codex.contains("exec '/opt/homebrew/bin/codex' \"$context\""))
        XCTAssertEqual(Handoff.quoted("a'b"), "'a'\\''b'")
    }
}
