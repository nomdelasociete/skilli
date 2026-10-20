import XCTest
@testable import SkilliCore

final class SystemSettingsPaneTests: XCTestCase {
    /// The shape of Displays' `DisplaysSearchGroups.searchTerms`.
    private let searchTerms: [String: Any] = [
        "nightShiftSection": ["localizableStrings": [["index": "blue light, warm", "title": "Night Shift"]]],
        "ambienceSection": ["localizableStrings": [
            ["index": "ambient light, brighten", "title": "Display Brightness"],
            ["index": "white balance", "title": "True Tone"]
        ]],
        "advancedSection": ["localizableStrings": [
            ["index": "", "title": "Advanced Settings"],
            ["index": "ipad", "title": "true tone"],
            ["index": "", "title": "  "]
        ]],
        "notAGroup": "ignored"
    ]

    func testSectionTitlesInGroupOrderOnce() {
        XCTAssertEqual(SystemSettingsPane.sectionTitles(searchTerms),
                       ["Advanced Settings", "true tone", "Display Brightness", "Night Shift"])
    }

    func testCodeNamesAreNotShown() {
        for name in ["Displays", "Touch ID & Password", "VPN", "Wi‑Fi", "AirDrop & Continuity", "Background Security Improvements"] {
            XCTAssertTrue(SystemSettingsPane.isReadable(name), name)
        }
        for name in ["HeadphoneSettingsExtension", "DisplaysExt", "PowerPreferences", "CoverageSettingPane_macOS", "WiFiSettings", ""] {
            XCTAssertFalse(SystemSettingsPane.isReadable(name), name)
        }
    }

    func testRepresentationFollowsTheMac() {
        // Battery's two faces, and Touch ID's three.
        let battery: [[String: Any]] = [
            ["predicate": "powersource.battery != YES", "sidebar-name": "ENERGY_SAVER_PREF_TITLE"],
            ["predicate": "powersource.battery == YES", "sidebar-name": "BATTERY_PREF_TITLE"]
        ]
        XCTAssertEqual(SystemSettingsPane.representation(battery, facts: ["powersource.battery": true])?["sidebar-name"] as? String, "BATTERY_PREF_TITLE")
        XCTAssertEqual(SystemSettingsPane.representation(battery, facts: ["powersource.battery": false])?["sidebar-name"] as? String, "ENERGY_SAVER_PREF_TITLE")
        let touchID: [[String: Any]] = [
            ["predicate": "user.isguest == YES"],
            ["predicate": "device.touchID != YES", "sidebar-name": "Login Password"],
            ["predicate": "device.touchID == YES", "sidebar-name": "Touch ID & Password"]
        ]
        let facts = ["user.isguest": false, "device.touchID": false]
        XCTAssertEqual(SystemSettingsPane.representation(touchID, facts: facts)?["sidebar-name"] as? String, "Login Password")
        // A fact skil.li does not know counts as yes.
        XCTAssertEqual(SystemSettingsPane.representation([["predicate": "device.mouse != YES"], ["predicate": "device.mouse == YES", "sidebar-name": "Mouse"]],
                                                         facts: [:])?["sidebar-name"] as? String, "Mouse")
        XCTAssertTrue(SystemSettingsPane.holds(nil, facts: [:]))
        XCTAssertTrue(SystemSettingsPane.holds("something odd", facts: [:]))
    }

    /// A settings word before or after names the pane asked for; alone, it
    /// is the app.
    func testPaneAskedWithASettingsWord() {
        XCTAssertEqual(SystemSettingsPane.asked("réglages bluetooth"), "bluetooth")
        XCTAssertEqual(SystemSettingsPane.asked("Bluetooth Settings"), "bluetooth")
        XCTAssertEqual(SystemSettingsPane.asked("bluetooth system settings"), "bluetooth")
        XCTAssertEqual(SystemSettingsPane.asked("Moniteurs réglages "), "moniteurs")
        XCTAssertNil(SystemSettingsPane.asked("bluetooth"))
        XCTAssertNil(SystemSettingsPane.asked("System Settings"))
        XCTAssertNil(SystemSettingsPane.asked("Réglages Système"))
        XCTAssertNil(SystemSettingsPane.asked("settings"))
        // Never to look for panes: "bluetooth settings" still finds them by
        // their "… settings" keywords, not by `paneQuery`.
        XCTAssertNil(SystemSettingsPane.paneQuery("bluetooth settings"))
    }

    func testPaneAskedAfterSettings() {
        XCTAssertEqual(SystemSettingsPane.paneQuery("réglages bluetooth"), "bluetooth")
        XCTAssertEqual(SystemSettingsPane.paneQuery("Réglages Système moniteurs"), "moniteurs")
        XCTAssertEqual(SystemSettingsPane.paneQuery("settings  displays "), "displays")
        XCTAssertEqual(SystemSettingsPane.paneQuery("System Settings night shift"), "night shift")
        XCTAssertNil(SystemSettingsPane.paneQuery("sett"))
        XCTAssertNil(SystemSettingsPane.paneQuery("settings"))
        XCTAssertNil(SystemSettingsPane.paneQuery("display settings"))
    }

    func testOpensByItsExtensionID() {
        let pane = SystemSettingsPane(id: "com.apple.Displays-Settings.extension", name: "Displays")
        XCTAssertEqual(pane.url?.absoluteString, "x-apple.systempreferences:com.apple.Displays-Settings.extension")
        XCTAssertEqual(pane, SystemSettingsPane(id: "com.apple.Displays-Settings.extension", name: "Moniteurs"))
    }

    /// Settings' section titles are long: a section counts when the query
    /// is made of its words' starts, not letters scattered across it.
    func testWordStartMatchesOnly() {
        // As the launcher counts a section: made of word starts (the
        // linear check first), and strong.
        func strong(_ query: String, _ text: String) -> Bool {
            let parsed = FuzzyMatcher.Query(query), candidate = FuzzyCandidate(text)
            return FuzzyMatcher.matchesWordStarts(parsed, candidate)
                && FuzzyMatcher.score(parsed, candidate).map { FuzzyMatcher.isStrong($0, for: parsed) } ?? parsed.isEmpty
        }
        XCTAssertTrue(strong("display", "Displays"))
        XCTAssertTrue(strong("night", "Night Shift"))
        XCTAssertTrue(strong("shift", "Night Shift"))
        XCTAssertTrue(strong("true tone", "True Tone"))
        XCTAssertTrue(strong("display settings", "Displays settings"))
        XCTAssertFalse(strong("safari", "Arrange multiple displays and screen savers"))
        XCTAssertFalse(strong("slack", "Show live captions and accessibility keyboard"))
        XCTAssertTrue(strong("nightsh", "Night Shift options"))
        XCTAssertTrue(strong("shift", "Night Shift options"))
        XCTAssertTrue(strong("nshift", "Night Shift options"))
        XCTAssertFalse(strong("ightshift", "Night Shift options"))
        XCTAssertFalse(strong("nigth", "Night Shift options"))
        XCTAssertTrue(FuzzyMatcher.matchesWordStarts(FuzzyMatcher.Query(""), FuzzyCandidate("anything")))
        // Word starts alone would take "slack" (Show, Live, Accessibility,
        // Keyboard); the score says it is scattered.
        XCTAssertTrue(FuzzyMatcher.matchesWordStarts(FuzzyMatcher.Query("slack"),
                                                     FuzzyCandidate("Show live captions and accessibility keyboard")))
    }
}
