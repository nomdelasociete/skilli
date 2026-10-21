import Foundation
import SkilliCore

/// Spotlight's ⌘Space in macOS's own shortcuts (System Settings → Keyboard
/// → Keyboard Shortcuts… → Spotlight), turned off when the launcher takes
/// ⌘Space, as Raycast does (2026-10-19: "that is exactly what I asked"),
/// and turned back on once the launcher leaves it, only when skil.li was the
/// one that turned it off. The one macOS setting skil.li changes.
@MainActor
enum SpotlightKey {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    /// Set while Spotlight's ⌘Space is off because of skil.li.
    private static let turnedOffKey = "SpotlightKey.turnedOff"
    /// Applies a change to macOS's shortcuts at once, without logging out.
    private static let activateSettings = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")

    /// The launcher's keys changed (`Chord.spec`, nil without keys).
    static func launcherKeysChanged(_ spec: String?) {
        let hotKeys = read()
        if spec == "cmd+space" {
            guard SystemShortcuts.spotlightTakesCommandSpace(in: hotKeys) else { return }
            write(SystemShortcuts.settingSpotlightKey(on: false, in: hotKeys))
            UserDefaults.standard.set(true, forKey: turnedOffKey)
            Log.input.notice("Spotlight's ⌘Space turned off: the launcher has it")
        } else if UserDefaults.standard.bool(forKey: turnedOffKey) {
            write(SystemShortcuts.settingSpotlightKey(on: true, in: hotKeys))
            UserDefaults.standard.removeObject(forKey: turnedOffKey)
            Log.input.notice("Spotlight's ⌘Space given back: the launcher left it")
        }
    }

    private static func read() -> [String: Any]? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [String: Any]
    }

    private static func write(_ hotKeys: [String: Any]) {
        CFPreferencesSetAppValue(key, hotKeys as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        let process = Process()
        process.executableURL = activateSettings
        process.arguments = ["-u"]
        do {
            try process.run()
        } catch {
            Log.input.error("activateSettings could not run: \(error.localizedDescription, privacy: .public)")
        }
    }
}
