import XCTest
@testable import SkilliCore

final class QuitSenderTests: XCTestCase {
    func testOnlySystemSettingsReopens() {
        XCTAssertTrue(QuitSender.reopensAfter("/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/MacOS/SecurityPrivacyExtension"))
        XCTAssertTrue(QuitSender.reopensAfter("/System/Applications/System Settings.app/Contents/MacOS/System Settings"))
        // A Quit from anyone else stays a quit.
        XCTAssertFalse(QuitSender.reopensAfter("/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"))
        XCTAssertFalse(QuitSender.reopensAfter("/usr/bin/osascript"))
        XCTAssertFalse(QuitSender.reopensAfter("/Users/x/Evil/SecurityPrivacyExtension.appex/Contents/MacOS/SecurityPrivacyExtension"))
        XCTAssertFalse(QuitSender.reopensAfter(""))
    }
}
