import Foundation

/// Who asked skil.li to quit, by the sender's executable: System Settings'
/// Privacy & Security pane quits an app so a permission just turned on
/// (Full Disk Access, Screen Recording…) takes effect, and says it reopens
/// it; on macOS 26 it does not, so skil.li reopens itself then. Any other
/// Quit (the menu, logging out, a script) stays a quit.
public enum QuitSender {
    /// The pane's process, or System Settings itself.
    public static func reopensAfter(_ executable: String) -> Bool {
        guard executable.hasPrefix("/System/") else { return false }
        return executable.hasSuffix("/SecurityPrivacyExtension.appex/Contents/MacOS/SecurityPrivacyExtension")
            || executable.hasSuffix("/System Settings.app/Contents/MacOS/System Settings")
    }
}
