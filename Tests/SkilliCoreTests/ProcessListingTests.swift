import XCTest
@testable import SkilliCore

final class ProcessListingTests: XCTestCase {
    func testParsesPSWithSpacesInPaths() {
        let output = """
            75588 100.0  36848 node
              611  42.3 543280 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
            35688  26.2 125984 /Applications/Grok Bot.app/Contents/Frameworks/Grok Bot Helper.app/Contents/MacOS/Grok Bot Helper
            garbage line
            """
        let entries = ProcessListing.parse(ps: output)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0], .init(pid: 75588, cpu: 100, memoryKB: 36848, path: "node"))
        XCTAssertEqual(entries[2].name, "Grok Bot Helper")
        XCTAssertEqual(entries[2].appPath, "/Applications/Grok Bot.app")
        XCTAssertNil(entries[1].appPath)
    }

    func testParsesLsofPIDs() {
        XCTAssertEqual(ProcessListing.parse(lsofPIDs: "p1234\ncnode\np1234\np99\ncpython3\n"), [1234, 99])
    }

    func testKillQueries() {
        XCTAssertEqual(ProcessListing.query("kill"), nil)
        XCTAssertEqual(ProcessListing.query("kill "), .all)
        XCTAssertEqual(ProcessListing.query("Kill Safari"), .name("safari"))
        XCTAssertEqual(ProcessListing.query("kill 3000"), .port(3000))
        XCTAssertEqual(ProcessListing.query("port :8080"), .port(8080))
        XCTAssertEqual(ProcessListing.query("tuer node"), .name("node"))
        XCTAssertEqual(ProcessListing.query("killer whale"), nil)
        XCTAssertEqual(ProcessListing.query("kill 99999"), .name("99999"))
    }

    func testGroupsAnAppWithItsHelpers() {
        let entries = ProcessListing.parse(ps: """
            100 10.0 1000 /Applications/Gather.app/Contents/MacOS/Gather
            101 20.0 2000 /Applications/Gather.app/Contents/Frameworks/Gather Helper (GPU).app/Contents/MacOS/Gather Helper (GPU)
            102 5.0 500 /Applications/Gather.app/Contents/Frameworks/Gather Helper (Renderer).app/Contents/MacOS/Gather Helper (Renderer)
            200 50.0 300 node
            201 1.0 300 node
            """)
        let groups = ProcessListing.groups(entries)
        XCTAssertEqual(groups.map(\.name), ["node", "Gather", "node"])
        let gather = groups[1]
        XCTAssertEqual(gather.pids, [101, 100, 102])
        XCTAssertEqual(gather.cpu, 35)
        XCTAssertEqual(gather.memoryKB, 3500)
        XCTAssertEqual(gather.appPath, "/Applications/Gather.app")
        XCTAssertEqual(ProcessListing.groups(entries, matching: "renderer").map(\.name), ["Gather"])
        XCTAssertEqual(ProcessListing.groups(entries, matching: "gath").count, 1)
    }
}
