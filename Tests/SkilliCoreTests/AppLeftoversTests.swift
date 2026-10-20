@testable import SkilliCore
import XCTest

final class AppLeftoversTests: XCTestCase {
    func testWhereAnAppLeavesFiles() {
        let paths = AppLeftovers.paths(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
        XCTAssertTrue(paths.contains("Application Support/Slack"))
        XCTAssertTrue(paths.contains("Containers/com.tinyspeck.slackmacgap"))
        XCTAssertTrue(paths.contains("Preferences/com.tinyspeck.slackmacgap.plist"))
        XCTAssertFalse(AppLeftovers.paths(bundleID: "com.example.notes", name: "Notes").contains("Application Support/Notes"),
                       "a common name is no app's own folder")
        XCTAssertTrue(paths.allSatisfy { !$0.hasPrefix("/") && !$0.contains("..") }, "under ~/Library only")
    }

    func testEntriesOfListedFolders() {
        XCTAssertTrue(AppLeftovers.belongs("T23Q.com.tinyspeck.slackmacgap", bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(AppLeftovers.belongs("com.tinyspeck.slackmacgap.6F1A.plist", bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(AppLeftovers.belongs("com.tinyspeck.slackmacgapother", bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(AppLeftovers.belongs("group.com.apple.notes", bundleID: "com"), "an id needs two parts")
    }

    func testProtectedAppsAndRequests() {
        XCTAssertTrue(AppLeftovers.isProtected("/System/Applications/Notes.app", bundleID: "com.apple.Notes"))
        XCTAssertTrue(AppLeftovers.isProtected("/Applications/Safari.app", bundleID: "com.apple.Safari"))
        XCTAssertTrue(AppLeftovers.isProtected("/Applications/skil.li.app", bundleID: "com.nomdelasociete.Skilli"))
        XCTAssertFalse(AppLeftovers.isProtected("/Applications/Slack.app", bundleID: "com.tinyspeck.slackmacgap"))
    }
}
