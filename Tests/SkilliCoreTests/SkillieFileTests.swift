import XCTest
@testable import SkilliCore

final class SkillieFileTests: XCTestCase {
    private let weekNumber = """
    #!/bin/bash

    # @skilli.schemaVersion 1
    # @skilli.title Week Number
    # @skilli.mode compact
    # @skilli.packageName Everyday
    # @skilli.description Says this week's number.

    date +%V
    """

    func testASkillieFileIsCheckedAsTheFolderReadsIt() throws {
        let checked = try SkillieFile.check(Data(weekNumber.utf8), name: "Week Number.skilli")
        XCTAssertEqual(checked.command.title, "Week Number")
        XCTAssertEqual(checked.command.mode, .compact)
        XCTAssertEqual(checked.text, weekNumber, "added as it came, byte for byte")
        XCTAssertEqual(checked.fileName, "week-number.sh")
    }

    func testItsNameComesFromTheFileThenTheTitleWithItsProgramsExtension() {
        XCTAssertEqual(SkillieFile.fileName("week-number.sh.skilli", title: "x", program: "bash"), "week-number.sh")
        XCTAssertEqual(SkillieFile.fileName("https-name.py", title: "x", program: "python3"), "https-name.py")
        XCTAssertEqual(SkillieFile.fileName("Confetti Cannon.skilli", title: "x", program: "swift"), "confetti-cannon.swift")
        XCTAssertEqual(SkillieFile.fileName("…!.skilli", title: "Café Time", program: "node"), "cafe-time.js")
        XCTAssertEqual(SkillieFile.fileName(".skilli", title: "", program: "ruby"), "skillie.rb")
        XCTAssertEqual(SkillieFile.fileName("notes.skilli", title: "x", program: "osascript"), "notes", "another program: no extension")
        XCTAssertEqual(SkillieFile.fileName("tool.v2.skilli", title: "x", program: "zsh"), "tool-v2.sh")
    }

    func testTheProgramIsReadFromTheShebang() {
        XCTAssertEqual(SkillieFile.program(of: "#!/bin/zsh\necho"), "zsh")
        XCTAssertEqual(SkillieFile.program(of: "#!/usr/bin/env python3\n"), "python3")
        XCTAssertEqual(SkillieFile.program(of: "#!/usr/bin/env -S node --no-warnings\n"), "node")
        XCTAssertEqual(SkillieFile.program(of: "#! /usr/bin/swift\n"), "swift")
        XCTAssertNil(SkillieFile.program(of: "#!bash\n"), "not an absolute path")
        XCTAssertNil(SkillieFile.program(of: "# @skilli.title No shebang\n"))
    }

    func testWhatIsNotASkillieSaysWhy() {
        func problem(_ data: Data) -> String? {
            do { _ = try SkillieFile.check(data, name: "x.skilli"); return nil } catch { return error.localizedDescription }
        }
        XCTAssertEqual(problem(Data(weekNumber.replacingOccurrences(of: "#!/bin/bash\n", with: "").utf8)),
                       "Its first line does not say what runs it (#!/bin/bash, #!/usr/bin/env python3…): not a skillie.")
        XCTAssertEqual(problem(Data("#!/bin/bash\n# @skilli.title No Mode\necho\n".utf8)),
                       "Its first lines do not say “@skilli.title” and “@skilli.mode”: not a skillie.")
        XCTAssertEqual(problem(Data(weekNumber.replacingOccurrences(of: "schemaVersion 1", with: "schemaVersion 2").utf8)),
                       "Its first lines do not say “@skilli.title” and “@skilli.mode”: not a skillie.")
        XCTAssertEqual(problem(Data([0x23, 0x21, 0xFF, 0xFE, 0x00])), "It is not text: not a skillie.")
        XCTAssertEqual(problem(Data(repeating: 0x41, count: SkillieFile.largest + 1)), "It is over 256 KB: not a skillie.")
        // A header past 8 KB is not read, as the folder does not read it.
        let late = "#!/bin/bash\n" + String(repeating: "#\n", count: 10) + String(repeating: " ", count: 8_200)
            + "\n# @skilli.title Late\n# @skilli.mode compact\n"
        XCTAssertNotNil(problem(Data(late.utf8)))
    }

    func testOneWithTheSameTitleIsReplaced() throws {
        let new = try SkillieFile.check(Data(weekNumber.utf8), name: "w.skilli").command
        let installed = [
            try XCTUnwrap(ScriptCommand.parse(weekNumber.replacingOccurrences(of: "Week Number", with: "week number"), path: "/s/mine.sh")),
            try XCTUnwrap(ScriptCommand.parse(weekNumber.replacingOccurrences(of: "Week Number", with: "Other"), path: "/s/other.sh")),
        ]
        XCTAssertEqual(SkillieFile.replaced(by: new, among: installed)?.path, "/s/mine.sh")
        XCTAssertNil(SkillieFile.replaced(by: new, among: Array(installed.dropFirst())))
    }

    func testAnImportLinkNamesHttpsAddressesOnly() throws {
        let file = try XCTUnwrap(URL(string: "https://skil.li/skillies/files/week-number.sh?v=1&x=a+b"))
        let link = SkillieImportLink.importLink(for: [file])
        XCTAssertTrue(link.absoluteString.hasPrefix("skilli://skillies/import?url=https"))
        XCTAssertFalse(link.absoluteString.contains("+"))
        XCTAssertEqual(SkillieImportLink.parse(link), [file])
        let mixed = try XCTUnwrap(URL(string: "skilli://skillies/import?url=https://example.com/a.skilli&url=http://example.com/b.skilli&url=file:///etc/x"))
        XCTAssertEqual(SkillieImportLink.parse(mixed), [URL(string: "https://example.com/a.skilli")!])
        XCTAssertNil(SkillieImportLink.parse(try XCTUnwrap(URL(string: "skilli://skillies/import?url=http://example.com/a"))))
        XCTAssertNil(SkillieImportLink.parse(try XCTUnwrap(URL(string: "skilli://apps/import?url=https://example.com/a"))))
        // Neither a run link nor another import.
        XCTAssertNil(SkilliLink.parse(link))
        XCTAssertNil(AppFileLink.parse(link))
        XCTAssertNil(CommandLink.parse(link))
    }
}
