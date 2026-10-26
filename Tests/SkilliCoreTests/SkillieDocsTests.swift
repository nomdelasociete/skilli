@testable import SkilliCore
import XCTest

/// `skillies/docs/` is the skillies' reference (2026-10-26: "a detailed
/// documentation, in md files in the repo, for maintenance"): every header
/// key `ScriptCommand.parse` reads, every variable a skillie is told, every
/// tool `"$SKILLI_CLI" call` can reach. One added without its line fails
/// here.
final class SkillieDocsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func read(_ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    func testEveryHeaderKeyIsInTheReference() {
        let doc = Self.read("skillies/docs/header.md")
        XCTAssertFalse(doc.isEmpty, "skillies/docs/header.md could not be read")
        let source = Self.read("Sources/SkilliCore/ScriptCommand.swift")
        // values["title"], and the arguments' own fields (object["type"]).
        let keys = Set(Self.matches(#"values\["(\w+)"\]"#, in: source))
        let fields = Set(Self.matches(#"object\["(\w+)"\]"#, in: source))
        XCTAssertFalse(keys.isEmpty, "ScriptCommand.parse's keys could not be read")
        let missing = keys.union(fields).sorted().filter { !doc.contains("| `\($0)` |") }
        XCTAssertEqual(missing, [], "skillies/docs/header.md: give each key its row")
    }

    func testEveryVariableASkillieIsToldIsDescribed() {
        let doc = Self.read("skillies/docs/running.md")
        // Every `static let … = "SKILLI_…"`: one added there is checked too.
        let variables = Self.matches(#"static let \w+ = "(SKILLI_\w+)""#, in: Self.read("Sources/SkilliCore/SkillieEnvironment.swift"))
        XCTAssertTrue(variables.contains(SkillieEnvironment.cli), "SkillieEnvironment's variables could not be read")
        let missing = variables.filter { !doc.contains("| `\($0)` |") }
        XCTAssertEqual(missing, [], "skillies/docs/running.md: describe each in Environment")
    }

    func testEveryToolASkillieCanCallIsListed() {
        let doc = Self.read("skillies/docs/calling-skilli.md")
        XCTAssertFalse(doc.isEmpty, "skillies/docs/calling-skilli.md could not be read")
        var names = SettingsTable.Tool.all
        for file in ["Sources/Skilli/Tools/SkilliTools.swift", "Sources/Skilli/Tools/ToolRightsTools.swift"] {
            let source = Self.read(file)
            // `ToolDefinition(name: "list_skillies"` or `name: doInApp`,
            // that constant's value.
            names += Self.matches(#"ToolDefinition\(\s*name: "(\w+)""#, in: source)
            for constant in Self.matches(#"ToolDefinition\(\s*name: ([a-z]\w*)\b"#, in: source) {
                names += Self.matches(#"static let \#(constant) = "(\w+)""#, in: source)
            }
        }
        XCTAssertGreaterThan(names.count, 80, "the tools' names could not be read")
        let missing = names.filter { !doc.contains("| `\($0)` |") }
        XCTAssertEqual(missing, [], "skillies/docs/calling-skilli.md: add each tool to its group's table")
    }
}
