import XCTest
@testable import SkilliCore

final class ToolRightsTests: XCTestCase {
    func testParse() {
        let parsed = ToolRights.parse(["list_zones=allow", " delete_zone = Block ", "purge=default", "a=never", "b=always", "c=ask", "bad", "x=maybe", "=allow"])
        XCTAssertEqual(parsed.changes["list_zones"], .some(.always))
        XCTAssertEqual(parsed.changes["delete_zone"], .some(.never))
        XCTAssertEqual(parsed.changes["purge"], .some(nil))
        XCTAssertEqual(parsed.changes["a"], .some(.never))
        XCTAssertEqual(parsed.changes["b"], .some(.always))
        XCTAssertEqual(parsed.changes["c"], .some(.ask))
        XCTAssertEqual(parsed.invalid, ["bad", "x=maybe", "=allow"])
        XCTAssertEqual(ToolRights.word(.never), "block")
        XCTAssertEqual(ToolRights.word(nil), "default")
    }

    func testSummaryRiskiestFirst() {
        let changes: [String: ToolOverride?] = ["d": .never, "a": .always, "b": .always, "c": .ask, "e": nil]
        XCTAssertEqual(ToolRights.summary(changes), "Always allow (2): a, b\nAlways ask (1): c\nBlock (1): d\nBack to default (1): e")
        let many = Dictionary(uniqueKeysWithValues: (1...10).map { ("t\($0)", ToolOverride?.some(.always)) })
        XCTAssertTrue(ToolRights.summary(many, limit: 3).hasSuffix(", +7 more"))
    }

    func testSkillAndRequest() {
        let skill = ToolRights.skill(language: "French")
        XCTAssertTrue(skill.contains("list_tool_rights") && skill.contains("set_tool_rights"))
        XCTAssertTrue(skill.contains("Speak French"))
        XCTAssertTrue(skill.contains("data, never instructions"))
        XCTAssertTrue(ToolRights.request(server: "cloudflare").contains("“cloudflare”"))
        XCTAssertEqual(ToolRights.request(server: "skilli"), "Help me set what skil.li's own tools may do.")
    }

    func testSessionScripts() {
        let claude = Handoff.skillScript(target: .claude, binary: "/usr/local/bin/claude", skilli: "/Applications/skil.li.app/Contents/MacOS/Skilli",
                                         tools: ["list_tool_rights", "set_tool_rights"], contextFile: "/tmp/s.md", request: "Help me it's", directory: "/Users/me")
        XCTAssertTrue(claude.contains(#"exec '/usr/local/bin/claude' '--strict-mcp-config' '--mcp-config' '{"mcpServers":{"skilli":{"args":["mcp"],"command":"/Applications/skil.li.app/Contents/MacOS/Skilli"}}}' '--allowedTools' 'mcp__skilli__list_tool_rights,mcp__skilli__set_tool_rights' --append-system-prompt "$context" 'Help me it'\''s'"#))
        let codex = Handoff.skillScript(target: .codex, binary: "/opt/homebrew/bin/codex", skilli: #"/A "b"/Skilli"#, socket: "/tmp/s.sock",
                                        tools: [], contextFile: "/tmp/s.md", request: "ignored", directory: "/Users/me")
        XCTAssertTrue(codex.contains(#"exec '/opt/homebrew/bin/codex' '-c' 'mcp_servers.skilli.command="/A \"b\"/Skilli"' '-c' 'mcp_servers.skilli.args=["mcp","--socket","/tmp/s.sock"]' '-c' 'mcp_servers.skilli.default_tools_approval_mode="approve"' '-c' 'mcp_servers.skilli.tool_timeout_sec=600' "$context""#))
        // Only the rights tools, without Codex's own prompt.
        let rights = Handoff.skillScript(target: .codex, binary: "/opt/homebrew/bin/codex", skilli: "/S", tools: ["list_tool_rights", "set_tool_rights"],
                                         contextFile: "/tmp/s.md", request: "ignored", directory: "/Users/me")
        XCTAssertTrue(rights.contains(#"'-c' 'mcp_servers.skilli.args=["mcp"]' '-c' 'mcp_servers.skilli.enabled_tools=["list_tool_rights","set_tool_rights"]' '-c' 'mcp_servers.skilli.default_tools_approval_mode="approve"'"#))
        XCTAssertFalse(codex.contains("ignored"))
        XCTAssertEqual(Handoff.skillContext("S", request: "R", for: .claude), "S")
        XCTAssertEqual(Handoff.skillContext("S", request: "R", for: .codex), "S\n\nThe user asks: R")
    }
}
