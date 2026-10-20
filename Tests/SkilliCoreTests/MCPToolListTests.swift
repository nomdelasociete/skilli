import XCTest
@testable import SkilliCore

final class MCPToolListTests: XCTestCase {
    func testPageAndHints() {
        let result: [String: Any] = [
            "tools": [
                ["name": "list_zones", "description": " Lists zones. ", "annotations": ["readOnlyHint": true]],
                ["name": "delete_zone", "title": "Delete a zone", "annotations": ["destructiveHint": true, "readOnlyHint": false]],
                ["name": "purge_cache"],
                ["name": "rename_zone", "annotations": ["readOnlyHint": false, "destructiveHint": false]],
                ["name": "set_dns", "annotations": ["readOnlyHint": false]],
                ["description": "no name"]
            ],
            "nextCursor": "c2"
        ]
        let page = MCPToolList.page(result)
        XCTAssertEqual(page.tools.map(\.name), ["list_zones", "delete_zone", "purge_cache", "rename_zone", "set_dns"])
        XCTAssertEqual(page.next, "c2")
        XCTAssertEqual(page.tools[0].description, "Lists zones.")
        // Not read-only, nothing said about destroying: the spec's default is that it may.
        XCTAssertEqual(page.tools.map(\.kind), [.reads, .destroys, .unknown, .changes, .destroys])
        XCTAssertEqual(page.tools.map(\.risk), [.read, .changes, .changes, .changes, .changes])
        XCTAssertEqual(page.tools[1].title, "Delete a zone")
        XCTAssertEqual(MCPToolList.summary(page.tools), "5 tools · 1 read · 1 change · 2 can destroy · 1 without hints")
        XCTAssertEqual(MCPToolInfo.fullName(server: "cloudflare", tool: "list_zones"), "mcp__cloudflare__list_zones")
        XCTAssertNil(MCPToolList.page(["tools": [], "nextCursor": ""]).next)
    }

    func testMessagesFromJSONAndEvents() {
        let json = Data(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}"#.utf8)
        XCTAssertEqual(MCPToolList.messages(json, contentType: "application/json").first?["id"] as? Int, 2)
        let events = Data("event: message\r\nid: 1\r\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\r\n\r\ndata: {\"jsonrpc\":\"2.0\",\r\ndata: \"id\":3,\"result\":{}}\n\n".utf8)
        let messages = MCPToolList.messages(events, contentType: "text/event-stream; charset=utf-8")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?["id"] as? Int, 3)
    }

    func testBlockedToolsNeverRun() {
        XCTAssertEqual(ToolPolicy.decision(risk: .read, mode: .always, override: .never), .block)
        XCTAssertEqual(ToolPolicy.decision(risk: .read, mode: .auto, override: nil), .run)
        XCTAssertEqual(ToolPolicy.decision(risk: .changes, mode: .auto, override: nil), .ask)
        XCTAssertEqual(ToolPolicy.decision(risk: .changes, mode: .auto, override: .always), .run)
    }
}
