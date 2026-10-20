@testable import SkilliCore
import XCTest

final class QuitRequestTests: XCTestCase {
    func testTheProcessesThatMayBeIt() {
        func group(_ name: String, _ path: String) -> ProcessListing.Group {
            let entry = ProcessListing.Entry(pid: Int32(name.count), cpu: 0, memoryKB: 1, path: path)
            return ProcessListing.Group(key: path, name: name, appPath: entry.appPath, entries: [entry])
        }
        let groups = [group("Creative Cloud", "/Applications/Adobe Creative Cloud/Adobe Creative Cloud.app/Contents/MacOS/Creative Cloud"),
                      group("CCXProcess", "/Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app/Contents/MacOS/CCXProcess"),
                      group("Adobe Desktop Service", "/Library/Application Support/Adobe/Adobe Desktop Common/ADS/Adobe Desktop Service.app/Contents/MacOS/Adobe Desktop Service"),
                      group("Slack", "/Applications/Slack.app/Contents/MacOS/Slack"),
                      group("Script Editor", "/Applications/Utilities/Script Editor.app/Contents/MacOS/Script Editor")]
        let found = QuitRequest.candidates(groups, target: "creative cloud").map(\.name)
        XCTAssertEqual(Set(found), ["Creative Cloud", "CCXProcess", "Adobe Desktop Service"])
        XCTAssertFalse(found.contains("Slack"))
        XCTAssertFalse(found.contains("Script Editor"), "Utilities is no vendor")
        XCTAssertEqual(QuitRequest.description(groups[1]), "CCXProcess")
        XCTAssertEqual(QuitRequest.description(groups[0]), "Creative Cloud, in Adobe Creative Cloud")
    }

    func testWhatBearsTheNameIsSure() {
        func group(_ name: String, _ path: String) -> ProcessListing.Group {
            let entry = ProcessListing.Entry(pid: 1, cpu: 0, memoryKB: 1, path: path)
            return ProcessListing.Group(key: path, name: name, appPath: entry.appPath, entries: [entry])
        }
        let helper = group("Google Chrome Helper (Renderer)", "/Applications/Google Chrome.app/Contents/Frameworks/Helper")
        XCTAssertTrue(QuitRequest.namesIt(helper, target: "chrome"))
        XCTAssertTrue(QuitRequest.namesIt(group("skillitest-sync", "/tmp/skillitest-sync"), target: "skillitest"))
        XCTAssertTrue(QuitRequest.namesIt(group("Code", "/Applications/Visual Studio Code.app/Contents/MacOS/Code"), target: "code"))
        XCTAssertFalse(QuitRequest.namesIt(group("Xcode", "/Applications/Xcode.app/Contents/MacOS/Xcode"), target: "code"))
        XCTAssertTrue(QuitRequest.namesIt(group("Creative Cloud", "/Applications/Adobe Creative Cloud/Adobe Creative Cloud.app/Contents/MacOS/Creative Cloud"),
                                          target: "creative cloud"))
        XCTAssertFalse(QuitRequest.namesIt(group("CCXProcess", "/Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app/Contents/MacOS/CCXProcess"),
                                           target: "creative cloud"), "a vendor helper is for the decision model")
    }
}
