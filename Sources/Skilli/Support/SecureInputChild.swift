#if SKILLI_SELFTEST
import AppKit
import Carbon.HIToolbox

/// A real password field in another process. Secure Input permits its owner
/// to see keys, so a field in the self-test's own window cannot test this.
@MainActor
enum SecureInputChild {
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == "secureinputchild" else { return nil }
        guard arguments.count == 3 else { return 2 }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 360, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Password shortcut test"
        let field = NSSecureTextField(frame: NSRect(x: 30, y: 45, width: 300, height: 24))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        app.activate()
        let output = URL(fileURLWithPath: arguments[2])
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                // Only a count leaves the field, never its contents.
                let state: [String: Any] = ["secure": IsSecureEventInputEnabled(), "count": field.stringValue.count]
                if let data = try? JSONSerialization.data(withJSONObject: state) {
                    try? data.write(to: output, options: .atomic)
                }
            }
        }
        // A crashed test must not leave a password field holding Secure Input.
        let deadline = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            MainActor.assumeIsolated { app.terminate(nil) }
        }
        withExtendedLifetime((window, timer, deadline)) { app.run() }
        return 0
    }
}
#endif
