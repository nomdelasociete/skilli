import XCTest
@testable import SkilliCore

final class HyperKeyMachineTests: XCTestCase {
    private let start = ContinuousClock.now

    func testQuickTapAloneIsATap() {
        var machine = HyperKeyMachine(tapThreshold: .milliseconds(400))
        machine.triggerDown(at: start)
        XCTAssertTrue(machine.isHeld)
        XCTAssertTrue(machine.triggerUp(at: start + .milliseconds(120)))
        XCTAssertFalse(machine.isHeld)
    }

    func testReleaseWithoutTheKeyIsNoTap() {
        var machine = HyperKeyMachine()
        machine.triggerDown(at: start)
        machine.release()
        XCTAssertFalse(machine.isHeld)
        XCTAssertFalse(machine.triggerUp(at: start + .milliseconds(50)), "a late key-up after a release is not a tap")
    }

    func testHoldWithAnotherKeyIsNotATap() {
        var machine = HyperKeyMachine()
        machine.triggerDown(at: start)
        machine.noteKeyWhileHeld()
        XCTAssertFalse(machine.triggerUp(at: start + .milliseconds(100)))
    }

    func testLongHoldIsNotATap() {
        var machine = HyperKeyMachine(tapThreshold: .milliseconds(400))
        machine.triggerDown(at: start)
        XCTAssertFalse(machine.triggerUp(at: start + .milliseconds(900)))
    }

    func testKeyRepeatDoesNotRestartTapWindow() {
        var machine = HyperKeyMachine(tapThreshold: .milliseconds(400))
        machine.triggerDown(at: start)
        machine.triggerDown(at: start + .milliseconds(500))
        XCTAssertFalse(machine.triggerUp(at: start + .milliseconds(550)))
    }

    func testReleaseWithoutPressIsNotATap() {
        var machine = HyperKeyMachine()
        XCTAssertFalse(machine.triggerUp(at: start))
    }

    func testKeysWhileNotHeldDoNotPoisonNextTap() {
        var machine = HyperKeyMachine()
        machine.noteKeyWhileHeld()
        machine.triggerDown(at: start)
        XCTAssertTrue(machine.triggerUp(at: start + .milliseconds(50)))
    }
}

final class HyperKeyPlannerTests: XCTestCase {
    /// Trimmed real output from a Mac running Raycast's Hyper Key
    /// (Caps Lock → F20 on the keyboard services).
    private let raycastOutput = """
    RegistryID  Key                   Value
    100000928   UserKeyMapping   (
    )
    100000b30   UserKeyMapping   (null)
    10028b846   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771183;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    10028a57b   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771183;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    """

    private let f20: UInt64 = 0x7_0000_006F

    func testParsesAndDeduplicatesPerServiceMappings() {
        XCTAssertEqual(
            HyperKeyPlanner.parseHIDUtilOutput(raycastOutput),
            [HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: f20)]
        )
    }

    func testParsesHexValuesInEitherOrder() {
        let output = "( { HIDKeyboardModifierMappingSrc = 0x700000039; HIDKeyboardModifierMappingDst = 0x7000000E0; } )"
        XCTAssertEqual(
            HyperKeyPlanner.parseHIDUtilOutput(output),
            [HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: 0x7_0000_00E0)]
        )
    }

    func testEmptyOutputParsesToNothing() {
        XCTAssertEqual(HyperKeyPlanner.parseHIDUtilOutput("100000b30   UserKeyMapping   (null)\n"), [])
    }

    func testAdoptsExistingCapsLockToFunctionKey() {
        let existing = HyperKeyPlanner.parseHIDUtilOutput(raycastOutput)
        XCTAssertEqual(HyperKeyPlanner.plan(existing: existing), .adopt(trigger: f20))
    }

    func testInstallsF18WhenNothingIsMapped() {
        XCTAssertEqual(
            HyperKeyPlanner.plan(existing: []),
            .install(HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: HIDKeyMapping.f18))
        )
    }

    func testLeavesUserModifierRemapsAlone() {
        let capsToControl = HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: 0x7_0000_00E0)
        XCTAssertEqual(HyperKeyPlanner.plan(existing: [capsToControl]), .leaveAlone)

        let unrelated = HIDKeyMapping(source: 0x7_0000_00E3, destination: 0x7_0000_00E2)
        XCTAssertEqual(HyperKeyPlanner.plan(existing: [unrelated]), .leaveAlone)
    }
}
