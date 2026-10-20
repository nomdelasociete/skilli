import Carbon.HIToolbox
import Foundation
import SkilliCore

/// Owns the Caps Lock → F-key mapping that powers Hyper.
///
/// Coexists with other Hyper tools: if Caps Lock is already mapped to an
/// F-key (Raycast uses F20), skil.li adopts that key and never touches the
/// mapping. It only installs Caps Lock → F18 when no mapping exists at all,
/// and removes it again on quit.
@MainActor
final class HyperKeyRemapper {
    private static let hidutil = URL(fileURLWithPath: "/usr/bin/hidutil")
    /// Survives crashes: lets the next launch recognise our own leftover
    /// mapping and clean it up on quit.
    private static let installedDefaultsKey = "HyperKeyRemapper.installedMapping"

    private(set) var plan: HyperKeyPlan?
    private var ownsMapping = false

    /// Key codes that act as the Hyper trigger in the event tap.
    var triggerKeyCodes: Set<CGKeyCode> {
        switch plan {
        case .adopt(let usage): Self.keyCode(forUsage: usage).map { [$0] } ?? []
        case .install(let mapping): Self.keyCode(forUsage: mapping.destination).map { [$0] } ?? []
        case .leaveAlone, nil: []
        }
    }

    var statusDescription: String {
        switch plan {
        case .adopt(let usage) where ownsMapping:
            "Hyper Key: Caps Lock → \(Self.name(forUsage: usage)) (skil.li)"
        case .adopt(let usage):
            "Hyper Key: Caps Lock → \(Self.name(forUsage: usage)) (shared with another app)"
        case .install(let mapping):
            ownsMapping
                ? "Hyper Key: Caps Lock → \(Self.name(forUsage: mapping.destination)) (skil.li)"
                : "Hyper Key: remap failed — see logs"
        case .leaveAlone:
            "Hyper Key: Caps Lock left as configured (custom key mappings found)"
        case nil:
            "Hyper Key: not set up"
        }
    }

    /// What Caps Lock does, for Settings (the row is already titled "Caps Lock").
    var settingsSummary: String {
        switch plan {
        case .adopt(let usage) where ownsMapping:
            "Mapped to \(Self.name(forUsage: usage)) by skil.li"
        case .adopt(let usage):
            "Mapped to \(Self.name(forUsage: usage)) by another app"
        case .install(let mapping):
            ownsMapping ? "Mapped to \(Self.name(forUsage: mapping.destination)) by skil.li" : "Remapping failed"
        case .leaveAlone:
            "Left as is: custom key mappings found"
        case nil:
            "Not set up"
        }
    }

    @discardableResult
    func activate() -> HyperKeyPlan {
        let existing = HyperKeyPlanner.parseHIDUtilOutput(run(["property", "--get", "UserKeyMapping"]) ?? "")
        let plan = HyperKeyPlanner.plan(existing: existing)

        switch plan {
        case .install(let mapping):
            ownsMapping = set([mapping])
        case .adopt(let usage):
            // Our own mapping left behind by a crash looks like an adoption.
            ownsMapping = UserDefaults.standard.bool(forKey: Self.installedDefaultsKey)
                && usage == HIDKeyMapping.f18
        case .leaveAlone:
            ownsMapping = false
        }
        UserDefaults.standard.set(ownsMapping, forKey: Self.installedDefaultsKey)
        self.plan = plan
        return plan
    }

    /// Caps Lock as the welcome shows it: mapped by skil.li, by another
    /// Hyper Key app, or left alone (custom mappings).
    var welcomeState: WelcomeModel.HyperKeyState {
        switch plan {
        case .adopt where !ownsMapping: .shared
        case .leaveAlone: .custom
        case .adopt, .install, nil: .own
        }
    }

    func deactivate() {
        guard ownsMapping else { return }
        if set([]) {
            ownsMapping = false
            UserDefaults.standard.set(false, forKey: Self.installedDefaultsKey)
        }
    }

    private func set(_ mappings: [HIDKeyMapping]) -> Bool {
        let payload: [String: Any] = [
            "UserKeyMapping": mappings.map {
                [
                    "HIDKeyboardModifierMappingSrc": NSNumber(value: $0.source),
                    "HIDKeyboardModifierMappingDst": NSNumber(value: $0.destination)
                ]
            }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8),
              run(["property", "--set", json]) != nil
        else {
            Log.input.error("hidutil --set failed")
            return false
        }
        return true
    }

    /// Runs hidutil synchronously; returns stdout, or `nil` on failure.
    private func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = Self.hidutil
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.input.error("hidutil failed to start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            Log.input.error("hidutil exited with \(process.terminationStatus)")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static let functionKeys: [(usage: UInt64, keyCode: Int, name: String)] = [
        (0x7_0000_0068, kVK_F13, "F13"),
        (0x7_0000_0069, kVK_F14, "F14"),
        (0x7_0000_006A, kVK_F15, "F15"),
        (0x7_0000_006B, kVK_F16, "F16"),
        (0x7_0000_006C, kVK_F17, "F17"),
        (0x7_0000_006D, kVK_F18, "F18"),
        (0x7_0000_006E, kVK_F19, "F19"),
        (0x7_0000_006F, kVK_F20, "F20")
    ]

    static func keyCode(forUsage usage: UInt64) -> CGKeyCode? {
        functionKeys.first { $0.usage == usage }.map { CGKeyCode($0.keyCode) }
    }

    static func name(forUsage usage: UInt64) -> String {
        functionKeys.first { $0.usage == usage }?.name ?? String(format: "0x%llX", usage)
    }
}
