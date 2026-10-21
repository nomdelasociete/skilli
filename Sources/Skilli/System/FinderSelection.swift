import AppKit
import SkilliCore

/// The file selected in Finder, for CleanShot X's Pin Selected Image and
/// the like: through Finder's scripting dictionary (its `selection`; macOS
/// asks once). Only when Finder is in front: a selection left in a window
/// behind is not what the user is looking at.
@MainActor
enum FinderSelection {
    static let bundleID = "com.apple.finder"

    /// The one file selected; throws what to do instead. `selected`:
    /// Finder's answer (the self-test's stand-in where macOS has not let
    /// skil.li ask Finder yet).
    static func file(selected: @MainActor () throws -> [URL] = readSelection) throws -> URL {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            throw SystemCommands.Failure(message: "Finder is not in front: select the file there first.")
        }
        let files = try selected()
        guard let file = files.first else { throw SystemCommands.Failure(message: "Nothing is selected in Finder.") }
        guard files.count == 1 else { throw SystemCommands.Failure(message: "\(files.count) items are selected in Finder: select one.") }
        guard !file.hasDirectoryPath else { throw SystemCommands.Failure(message: "“\(file.lastPathComponent)” is a folder: select a file.") }
        return file
    }

    /// Every item selected in Finder's front window (or on the desktop),
    /// in its order.
    static func readSelection() throws -> [URL] {
        let source = """
            tell application id "\(bundleID)"
                set found to {}
                repeat with picked in (get selection)
                    set end of found to URL of picked
                end repeat
                return found
            end tell
            """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            Log.actions.error("Finder's selection not read: \(number, privacy: .public)")
            // -1743: the user has not allowed skil.li to control Finder.
            if number == -1743 {
                throw SystemCommands.Failure(message: "skil.li may not read Finder's selection yet: allow it in System Settings → Privacy & Security → Automation.")
            }
            throw SystemCommands.Failure(message: "Finder did not say what is selected.")
        }
        guard let result else { return [] }
        return (0..<result.numberOfItems).compactMap { index in
            // Finder's `URL`: file:///Users/me/Desktop/Shot%201.png.
            guard let text = result.atIndex(index + 1)?.stringValue, let url = URL(string: text), url.isFileURL else { return nil }
            return url
        }
    }
}
