import XCTest
@testable import SkilliCore

final class ToolPolicyTests: XCTestCase {
    func testAutoAsksOnlyForChanges() {
        XCTAssertFalse(ToolPolicy.needsApproval(risk: .read, mode: .auto, override: nil))
        XCTAssertFalse(ToolPolicy.needsApproval(risk: .harmless, mode: .auto, override: nil))
        XCTAssertTrue(ToolPolicy.needsApproval(risk: .changes, mode: .auto, override: nil))
    }

    func testAskAndAlwaysModes() {
        XCTAssertTrue(ToolPolicy.needsApproval(risk: .read, mode: .ask, override: nil))
        XCTAssertFalse(ToolPolicy.needsApproval(risk: .changes, mode: .always, override: nil))
    }

    func testOverridesWinAndTalkingNeverAsks() {
        XCTAssertFalse(ToolPolicy.needsApproval(risk: .changes, mode: .ask, override: .always))
        XCTAssertTrue(ToolPolicy.needsApproval(risk: .read, mode: .always, override: .ask))
        XCTAssertFalse(ToolPolicy.needsApproval(risk: .none, mode: .ask, override: .ask))
    }
}

final class AgentStreamTests: XCTestCase {
    func testToolUseResultTextAndEnd() {
        let toolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_1","name":"mcp__skilli__get_selection","input":{"b":1,"a":"x"}}]}}"#
        XCTAssertEqual(AgentStream.events(in: toolUse), [.toolUse(id: "toolu_1", name: "mcp__skilli__get_selection", input: #"{"a":"x","b":1}"#)])
        let result = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_1","content":[{"type":"text","text":"hi"}]}]}}"#
        XCTAssertEqual(AgentStream.events(in: result), [.toolResult(id: "toolu_1", isError: false)])
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done"}}}"#
        XCTAssertEqual(AgentStream.events(in: delta), [.text("Done")])
        let end = #"{"type":"result","subtype":"success","is_error":false,"result":"BONJOUR","total_cost_usd":0.0003}"#
        XCTAssertEqual(AgentStream.events(in: end), [.finished(result: "BONJOUR", isError: false, costUSD: 0.0003)])
    }

    func testFailuresAndNoise() {
        let failed = #"{"type":"result","subtype":"error_max_turns","is_error":true}"#
        XCTAssertEqual(AgentStream.events(in: failed), [.finished(result: "Claude Code stopped: error_max_turns.", isError: true, costUSD: nil)])
        XCTAssertEqual(AgentStream.events(in: #"{"type":"system","subtype":"init"}"#), [])
        XCTAssertEqual(AgentStream.events(in: "not json"), [])
    }

    func testSplitsMCPToolNames() {
        XCTAssertEqual(AgentStream.split(toolName: "mcp__skilli__get_selection").server, "skilli")
        XCTAssertEqual(AgentStream.split(toolName: "mcp__linear__create__issue").tool, "create__issue")
        XCTAssertNil(AgentStream.split(toolName: "Read").server)
    }
}

final class PromptFileToolsTests: XCTestCase {
    func testToolsRoundTrip() {
        let file = PromptFile(parsing: "---\ntools: [Selection, apps, mcp:linear, apps]\n---\nDo it.")
        XCTAssertEqual(file.tools, ["selection", "apps", "mcp:linear"])
        XCTAssertEqual(PromptFile(parsing: file.text), file)
    }
}
