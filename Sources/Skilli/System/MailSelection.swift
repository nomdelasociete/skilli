import AppKit
import SkilliCore

/// The message selected in Mail, for "rappelle-moi de répondre à ce mail":
/// its subject and the link back to it, through Mail's scripting
/// dictionary (macOS asks once). Only when Mail is in front: Mail is never
/// opened for it.
@MainActor
enum MailSelection {
    static func selected() -> (subject: String, link: URL)? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.mail" else { return nil }
        let source = """
            tell application "Mail"
                set picked to selection
                if picked is {} then return ""
                set theMessage to item 1 of picked
                return (subject of theMessage) & linefeed & (message id of theMessage)
            end tell
            """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, error == nil else {
            if let error { Log.actions.error("Mail's selection not read: \(error[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public)") }
            return nil
        }
        let lines = result.components(separatedBy: "\n")
        guard lines.count >= 2, let link = Reminders.mailLink(messageID: lines[1]) else { return nil }
        return (lines[0], link)
    }
}
