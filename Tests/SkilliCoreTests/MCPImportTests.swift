import XCTest
@testable import SkilliCore

final class MCPImportTests: XCTestCase {
    func testClaudeCodeUserAndProjectServers() {
        let json = #"""
        {
          "oauthAccount": {"emailAddress": "x@y.z"},
          "mcpServers": {
            "linear": {"type": "http", "url": "https://mcp.linear.app/mcp"},
            "github": {"type": "http", "url": "https://api.githubcopilot.com/mcp/", "headers": {"Authorization": "Bearer ghp_1"}},
            "memory": {"type": "stdio", "command": "npx", "args": ["-y", "@modelcontextprotocol/server-memory"], "env": {"DIR": "/tmp"}},
            "old": {"type": "sse", "url": "https://example.com/sse"},
            "skilli": {"command": "/Applications/skil.li.app/Contents/MacOS/Skilli", "args": ["mcp"]}
          },
          "projects": {
            "/Users/me/app": {"mcpServers": {"db": {"command": "uvx", "args": ["db-mcp"]}, "keyed": {"type": "http", "url": "https://k.example.com/mcp", "headers": {"X-Api-Key": "k1", "X-Region": "eu"}}}}
          }
        }
        """#
        let found = MCPImport.json(Data(json.utf8), source: .claudeCode)
        XCTAssertEqual(found.map(\.name), ["github", "linear", "memory", "old", "skilli", "db", "keyed"])
        let github = found[0]
        XCTAssertEqual(github.token, "Bearer ghp_1")
        XCTAssertNil(github.header)
        XCTAssertNil(github.problem)
        XCTAssertNil(found[1].token)
        XCTAssertEqual(found[2].command, "npx")
        XCTAssertEqual(found[2].env, ["DIR": "/tmp"])
        XCTAssertNotNil(found[3].problem)
        XCTAssertTrue(MCPImport.isSkilli(found[4]))
        XCTAssertEqual(found[5].project, "/Users/me/app")
        XCTAssertEqual(found[6].token, "k1")
        XCTAssertEqual(found[6].header, "X-Api-Key")
    }

    func testClaudeDesktopAndCursorShape() {
        let json = #"{"mcpServers": {"fs": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me"]}, "plain": {"url": "http://example.com/mcp"}, "env": {"url": "https://e.example.com/mcp", "headers": {"Authorization": "Bearer ${TOKEN}"}}}}"#
        let found = MCPImport.json(Data(json.utf8), source: .claudeDesktop)
        XCTAssertEqual(found.map(\.name), ["env", "fs", "plain"])
        XCTAssertNotNil(found[0].problem, "a token from a variable is added by hand")
        XCTAssertEqual(found[1].args.last, "/Users/me")
        XCTAssertEqual(found[2].problem, "Its address is not https.")
        XCTAssertEqual(MCPImport.json(Data("not json".utf8), source: .cursor), [])
    }

    func testCodexConfig() {
        let toml = #"""
        model = "gpt-5" # a comment
        [mcp_servers.memory]
        command = "npx"
        args = [
          "-y",
          "@modelcontextprotocol/server-memory", # trailing comment
        ]
        env = { "API_KEY" = "secret, with comma", DEBUG = '1' }

        [mcp_servers."figma desktop"]
        url = "https://mcp.figma.com/mcp"
        bearer_token_env_var = "FIGMA_TOKEN"
        http_headers = { "X-Figma-Region" = "us-east-1" }

        [mcp_servers.off]
        command = "off-mcp"
        enabled = false

        [mcp_servers.tabled]
        command = "/usr/local/bin/t"
        [mcp_servers.tabled.env]
        HOME_DIR = "/Users/me # not a comment"

        [profiles.fast]
        model = "o3"
        """#
        let found = MCPImport.codex(toml)
        XCTAssertEqual(found.map(\.name), ["figma desktop", "memory", "off", "tabled"])
        XCTAssertEqual(found[0].url, "https://mcp.figma.com/mcp")
        XCTAssertEqual(found[0].tokenVariable, "FIGMA_TOKEN")
        XCTAssertNil(found[0].token)
        XCTAssertEqual(found[1].args, ["-y", "@modelcontextprotocol/server-memory"])
        XCTAssertEqual(found[1].env, ["API_KEY": "secret, with comma", "DEBUG": "1"])
        XCTAssertEqual(found[2].problem, "Turned off in Codex.")
        XCTAssertEqual(found[3].env, ["HOME_DIR": "/Users/me # not a comment"])
        XCTAssertEqual(TOML.keyPath(#"a."b.c".d"#), ["a", "b.c", "d"])
    }

    func testSameServerKeptOnce() {
        func web(_ source: MCPImport.Source, _ name: String, _ url: String, project: String? = nil, token: String? = nil) -> MCPImport.Candidate {
            var candidate = MCPImport.Candidate(source: source, project: project, name: name)
            candidate.url = url
            candidate.token = token
            return candidate
        }
        var railway = MCPImport.Candidate(source: .claudeCode, project: "/p/a", name: "Railway")
        railway.command = "npx"
        railway.args = ["-y", "@railway/mcp-server"]
        var railwayAgain = MCPImport.Candidate(source: .claudeCode, project: "/p/b", name: "Railway")
        railwayAgain.command = "npx"
        railwayAgain.args = ["-y", "@railway/mcp-server"]
        let merged = MCPImport.merged([
            web(.claudeCode, "nimbus-deployment", "https://deployment.nimbus.example/api/mcp"),
            web(.cursor, "nimbus-deployment", "https://deployment.nimbus.example/api/mcp/"),
            web(.codex, "nimbus_deployment", "https://deployment.nimbus.example/api/mcp", token: "Bearer t"),
            web(.claudeCode, "bastion", "https://b.example.com/mcp", project: "/p/a"),
            web(.claudeCode, "bastion", "https://b.example.com/mcp", project: "/p/b"),
            railway, railwayAgain
        ])
        XCTAssertEqual(merged.map(\.name), ["nimbus_deployment", "bastion", "Railway"])
        XCTAssertEqual(merged[0].token, "Bearer t", "the one with a token is kept")
        XCTAssertEqual(merged[0].alsoIn, ["Claude Code", "Cursor"])
        XCTAssertEqual(merged[1].place, "Claude Code · a")
        XCTAssertEqual(merged[1].alsoIn, ["Claude Code · b"])
        XCTAssertEqual(merged[2].alsoIn, ["Claude Code · b"])
    }
}
