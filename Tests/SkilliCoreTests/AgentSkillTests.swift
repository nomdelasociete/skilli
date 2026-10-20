import XCTest
@testable import SkilliCore

final class AgentSkillTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-skills-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, at path: String) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testFrontMatter() {
        let text = "---\nname: weekly-report\ndescription: \"Use when the user asks for the weekly report.\"\nallowed-tools: Read\n---\n\n# Weekly report\n"
        let front = AgentSkill.frontMatter(text)
        XCTAssertEqual(front.name, "weekly-report")
        XCTAssertEqual(front.description, "Use when the user asks for the weekly report.")
        XCTAssertNil(AgentSkill.frontMatter("# No front matter\nname: nope").name)
    }

    func testFoundInTheFolderAndOneLevelDown() throws {
        try write("---\nname: pr-summary\ndescription: Sum up pull requests.\n---\nList them by repository.", at: "pr-summary/SKILL.md")
        try write("---\ndescription: No name: the folder's.\n---\n", at: "meeting-notes/SKILL.md")
        try write("---\nname: docx\ndescription: Word files.\n---\n", at: "synced/docx/SKILL.md")
        try write("not a skill", at: "notes/README.md")
        try write("---\nname: hidden\n---\n", at: ".hidden/SKILL.md")
        let found = AgentSkill.find(in: folder)
        XCTAssertEqual(found.map(\.name), ["meeting-notes", "pr-summary", "docx"])
        XCTAssertEqual(found.first { $0.name == "pr-summary" }?.description, "Sum up pull requests.")
        XCTAssertEqual(found.first { $0.name == "docx" }?.folder.lastPathComponent, "docx")
        XCTAssertTrue(AgentSkill.find(in: folder.appendingPathComponent("missing")).isEmpty)
    }

    func testTheFirstFolderWinsANameTaken() throws {
        try write("---\nname: report\ndescription: skil.li's.\n---\n", at: "mine/report/SKILL.md")
        try write("---\nname: report\ndescription: Claude Code's.\n---\n", at: "theirs/report/SKILL.md")
        try write("---\nname: other\ndescription: Theirs only.\n---\n", at: "theirs/other/SKILL.md")
        let found = AgentSkill.find(in: [folder.appendingPathComponent("mine"), folder.appendingPathComponent("theirs")])
        XCTAssertEqual(found.map(\.name), ["report", "other"])
        XCTAssertEqual(found.first?.description, "skil.li's.")
    }

    func testNamesAndText() throws {
        XCTAssertNoThrow(try AgentSkill.checkName("weekly-report"))
        XCTAssertNoThrow(try AgentSkill.checkName("pr2"))
        for bad in ["", "Weekly", "weekly report", "-start", "end-", "a--b", String(repeating: "a", count: 65), "café"] {
            XCTAssertThrowsError(try AgentSkill.checkName(bad), bad)
        }
        XCTAssertEqual(AgentSkill.name(from: "Weekly Report!"), "weekly-report")
        XCTAssertEqual(AgentSkill.name(from: "Résumé des PR"), "resume-des-pr")
        let text = AgentSkill.markdown(name: "weekly-report", description: "Use for the weekly report.\nAlways.", instructions: "\nGroup by project.\n")
        XCTAssertEqual(text, "---\nname: weekly-report\ndescription: Use for the weekly report. Always.\n---\n\nGroup by project.\n")
        XCTAssertEqual(AgentSkill.frontMatter(text).description, "Use for the weekly report. Always.")
    }
}
