import AppKit
import ApplicationServices

/// Brings a skil.li window to the front with keyboard focus.
///
/// skil.li is an accessory app that is almost never active: the launcher
/// panel never activates it. Since macOS 14, `NSApp.activate()` is
/// cooperative and the frontmost app may decline, which left Settings
/// behind other windows. With Accessibility granted, skil.li can make
/// itself frontmost the way the user's click would.
@MainActor
enum Foreground {
    static func bring(_ window: NSWindow) {
        NSApp.activate()
        if !isFrontmost {
            let app = AXUIElementCreateApplication(getpid())
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
    }
}
