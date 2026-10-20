import XCTest
@testable import SkilliCore

final class SkillieEnvironmentTests: XCTestCase {
    func testTellsTheSkillieItsCommandLineSocketAndRun() {
        let variables = SkillieEnvironment.variables(cli: "/Applications/skil.li.app/Contents/MacOS/Skilli",
                                                     socket: "/Users/someone/Library/Application Support/skil.li/mcp.sock", run: "run-1")
        XCTAssertEqual(variables, [
            "SKILLI_CLI": "/Applications/skil.li.app/Contents/MacOS/Skilli",
            "SKILLI_SOCKET": "/Users/someone/Library/Application Support/skil.li/mcp.sock",
            "SKILLI_SKILLIE": "run-1"
        ])
    }

    func testTellsNothingWithoutAToolServer() {
        XCTAssertEqual(SkillieEnvironment.variables(cli: "/bin/Skilli", socket: nil, run: "run-1"), [:])
        XCTAssertEqual(SkillieEnvironment.variables(cli: "/bin/Skilli", socket: "", run: "run-1"), [:])
        XCTAssertEqual(SkillieEnvironment.variables(cli: nil, socket: "/tmp/mcp.sock", run: "run-1"), [:])
    }

    func testCallsReachTheSkilliRunningTheSkillie() {
        let usual = "/Users/someone/Library/Application Support/skil.li/mcp.sock"
        // The flag first, then the skillie's, then the usual one (started if needed).
        XCTAssertTrue(SkillieEnvironment.socket(flag: "/tmp/a.sock", environment: ["SKILLI_SOCKET": "/tmp/b.sock"], defaultPath: usual)
            == ("/tmp/a.sock", false))
        XCTAssertTrue(SkillieEnvironment.socket(flag: nil, environment: ["SKILLI_SOCKET": "/tmp/b.sock"], defaultPath: usual)
            == ("/tmp/b.sock", false))
        XCTAssertTrue(SkillieEnvironment.socket(flag: nil, environment: ["SKILLI_SOCKET": ""], defaultPath: usual) == (usual, true))
        XCTAssertTrue(SkillieEnvironment.socket(flag: nil, environment: [:], defaultPath: usual) == (usual, true))
    }

    func testReadsNameValueWords() {
        XCTAssertEqual(SkillieEnvironment.arguments(["app=TextEdit", "goal=exporte en PDF dans mes documents"]),
                       ["app": "TextEdit", "goal": "exporte en PDF dans mes documents"])
        // Only the first "=" splits: the value keeps the rest, quotes included.
        XCTAssertEqual(SkillieEnvironment.arguments([#"goal=tape « a=b" app=Mail »"#]), ["goal": #"tape « a=b" app=Mail »"#])
        XCTAssertEqual(SkillieEnvironment.arguments(["app="]), ["app": ""])
        XCTAssertEqual(SkillieEnvironment.arguments([]), [:])
    }

    func testRefusesWordsThatAreNotNameValue() {
        XCTAssertNil(SkillieEnvironment.arguments(["TextEdit"]))
        XCTAssertNil(SkillieEnvironment.arguments(["=TextEdit"]))
        XCTAssertNil(SkillieEnvironment.arguments(["1app=TextEdit"]))
        XCTAssertNil(SkillieEnvironment.arguments(["the app=TextEdit"]))
        XCTAssertNil(SkillieEnvironment.arguments(["app=TextEdit", "app=Finder"]))
    }
}
