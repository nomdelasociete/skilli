import XCTest
@testable import SkilliCore

final class ScriptCommandTests: XCTestCase {
    func testParsesRaycastMetadata() throws {
        let text = """
        #!/bin/bash

        # Required parameters:
        # @raycast.schemaVersion 1
        # @raycast.title Search Issues
        # @raycast.mode fullOutput

        # Optional parameters:
        # @raycast.icon 🐛
        # @raycast.packageName GitHub
        # @raycast.description Finds issues by words.
        # @raycast.argument1 { "type": "text", "placeholder": "Query", "percentEncoded": true }
        # @raycast.argument2 { "type": "dropdown", "placeholder": "State", "data": [{"title": "Open", "value": "open"}, {"title": "Closed", "value": "closed"}], "optional": true }
        # @raycast.needsConfirmation true
        # @raycast.currentDirectoryPath ~

        echo "# @raycast.title Not this one"
        """
        let command = try XCTUnwrap(ScriptCommand.parse(text, path: "/scripts/issues.sh"))
        XCTAssertEqual(command.title, "Search Issues")
        XCTAssertEqual(command.mode, .fullOutput)
        XCTAssertEqual(command.icon, "🐛")
        XCTAssertEqual(command.packageName, "GitHub")
        XCTAssertEqual(command.description, "Finds issues by words.")
        XCTAssertTrue(command.needsConfirmation)
        XCTAssertTrue(command.showsRunning, "the Running… card unless the skillie says otherwise")
        XCTAssertEqual(command.directory, "~")
        XCTAssertEqual(command.arguments.count, 2)
        XCTAssertEqual(command.arguments[0].kind, .text)
        XCTAssertTrue(command.arguments[0].percentEncoded)
        XCTAssertEqual(command.arguments[1].kind, .dropdown)
        XCTAssertTrue(command.arguments[1].optional)
        XCTAssertEqual(command.arguments[1].choices.map(\.value), ["open", "closed"])
        XCTAssertEqual(command.values(for: ["a b&c"]), ["a%20b%26c", ""])
    }

    func testOtherLanguagesAndRefusals() throws {
        let swift = """
        #!/usr/bin/swift
        // @raycast.schemaVersion 1
        // @raycast.title Uptime
        // @raycast.mode inline
        // @raycast.refreshTime 5m
        print("up")
        """
        let inline = try XCTUnwrap(ScriptCommand.parse(swift, path: "/s/uptime.swift"))
        XCTAssertEqual(inline.mode, .inline)
        let quiet = try XCTUnwrap(ScriptCommand.parse(swift + "\n// @skilli.showsRunning false", path: "/s/q.swift"))
        XCTAssertFalse(quiet.showsRunning)
        XCTAssertEqual(inline.refreshSeconds, 300)
        XCTAssertNil(ScriptCommand.parse("#!/bin/bash\n# @raycast.title No mode\necho", path: "/s/a.sh"))
        XCTAssertNil(ScriptCommand.parse("#!/bin/bash\n# @raycast.mode silent\necho", path: "/s/b.sh"))
        XCTAssertNil(ScriptCommand.parse("#!/bin/bash\n# @raycast.schemaVersion 2\n# @raycast.title T\n# @raycast.mode silent", path: "/s/c.sh"))
        XCTAssertEqual(ScriptCommand.seconds("5s"), 10, "Raycast refreshes every 10 s at most")
        XCTAssertNil(ScriptCommand.seconds("soon"))
    }

    func testSkilliesImportAndMake() throws {
        let raycast = "#!/bin/bash\n# @raycast.schemaVersion 1\n# @raycast.title Flush DNS\n# @raycast.mode silent\necho \"@raycast.title stays in code\"\n"
        let converted = try XCTUnwrap(ScriptCommand.converted(fromRaycast: raycast))
        XCTAssertTrue(converted.contains("# @skilli.title Flush DNS"))
        XCTAssertFalse(converted.contains("# @raycast."))
        XCTAssertTrue(converted.contains("echo \"@raycast.title stays in code\""), "only comments are renamed")
        XCTAssertEqual(ScriptCommand.parse(converted, path: "/s/flush.sh")?.title, "Flush DNS")
        XCTAssertNil(ScriptCommand.converted(fromRaycast: "#!/bin/bash\necho hi"))

        let made = ScriptCommand.make(title: "Vider le cache DNS", description: "Flushes the DNS cache\nnow", mode: .compact, language: .zsh,
                                      code: "#!/bin/zsh\ndscacheutil -flushcache\necho done", arguments: [("Host", true)])
        XCTAssertEqual(made.fileName, "vider-le-cache-dns.sh")
        let command = try XCTUnwrap(ScriptCommand.parse(made.text, path: "/s/" + made.fileName))
        XCTAssertEqual(command.title, "Vider le cache DNS")
        XCTAssertEqual(command.description, "Flushes the DNS cache now")
        XCTAssertEqual(command.mode, .compact)
        XCTAssertEqual(command.arguments.first?.placeholder, "Host")
        XCTAssertTrue(command.arguments.first?.optional == true)
        XCTAssertTrue(made.text.hasPrefix("#!/bin/zsh\n"))
        XCTAssertEqual(made.text.components(separatedBy: "#!/bin/zsh").count, 2, "one shebang")
        XCTAssertEqual(ScriptCommand.make(title: "Hi", description: "", mode: .silent, language: .node, code: "console.log(1)").text.split(separator: "\n")[1], "// @skilli.schemaVersion 1")
    }

    func testIconsAndRequiredArguments() throws {
        func command(_ icon: String, _ arguments: String = "") throws -> ScriptCommand {
            try XCTUnwrap(ScriptCommand.parse("""
            #!/bin/bash
            # @skilli.schemaVersion 1
            # @skilli.title Clock
            # @skilli.mode inline
            # @skilli.icon \(icon)
            \(arguments)
            """, path: "/Users/me/skillies/clock.sh"))
        }
        let emoji = try command("⏰")
        XCTAssertEqual(emoji.emojiIcon, "⏰")
        XCTAssertNil(emoji.iconImagePath)
        for drawnAsEmoji in ["©️", "1️⃣", "❤️"] {
            XCTAssertEqual(try command(drawnAsEmoji).emojiIcon, drawnAsEmoji)
            XCTAssertNil(try command(drawnAsEmoji).iconImagePath)
        }
        XCTAssertNil(try command("©").emojiIcon, "a plain text character")
        let image = try command("clock.png")
        XCTAssertNil(image.emojiIcon)
        XCTAssertEqual(image.iconImagePath, "/Users/me/skillies/clock.png")
        XCTAssertEqual(try command("/Users/me/Pictures/clock.png").iconImagePath, "/Users/me/Pictures/clock.png")
        XCTAssertNil(try command("https://example.com/clock.png").iconImagePath)
        XCTAssertNil(try command("https://example.com/clock.png").emojiIcon)

        XCTAssertFalse(emoji.needsArguments)
        XCTAssertTrue(try command("⏰", #"# @skilli.argument1 { "type": "text", "placeholder": "City" }"#).needsArguments)
        XCTAssertFalse(try command("⏰", #"# @skilli.argument1 { "type": "text", "placeholder": "City", "optional": true }"#).needsArguments)

        // A key bound to it opens the same entry as its row in the "?".
        XCTAssertEqual(FeatureCatalog.entry(image).id, "script:/Users/me/skillies/clock.sh")
        XCTAssertEqual(FeatureCatalog.entry(image).run, .skillie("/Users/me/skillies/clock.sh"))
    }

    func testOutputLines() {
        XCTAssertEqual(ScriptCommand.lastLine("one\ntwo\n\n  \n"), "two")
        XCTAssertEqual(ScriptCommand.lastLine(""), "")
        XCTAssertEqual(ScriptCommand.plain("\u{1B}[32mgreen\u{1B}[0m done"), "green done")
    }
}
