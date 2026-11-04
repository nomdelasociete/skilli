import AppKit
import ApplicationServices
import notify

enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt. The key is spelled out because
    /// `kAXTrustedCheckOptionPrompt` is a mutable C global, which Swift 6
    /// rejects as not concurrency-safe.
    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    /// `handler` on the main queue each time tccd writes its database (any
    /// app, any service, granted or taken back), until skil.li quits. macOS
    /// has no public notice for it: `com.apple.tcc.access.changed` is the
    /// Darwin notification tccd posts right after each write (AltTab relies
    /// on it, ~30 ms after the switch, measured on macOS 27). The distributed
    /// `com.apple.accessibility.api` comes before the write: not used.
    static func watchChanges(_ handler: @escaping @MainActor () -> Void) {
        var token: Int32 = NOTIFY_TOKEN_INVALID
        let status = notify_register_dispatch("com.apple.tcc.access.changed", &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        if status != NOTIFY_STATUS_OK {
            Log.input.error("Permission changes not watched: notify_register_dispatch \(status)")
        }
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
