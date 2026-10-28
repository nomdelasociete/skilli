import AppKit

/// skil.li in the Dock and ⌘⇥ while a window that needs it is open
/// (Settings, a recording's window), an accessory again once the last of
/// them closes; the recorder's icon while a recording's window is open
/// (docs/meeting-recorder-views.md, "In the Dock"). The one place that
/// sets either: two windows never undo each other's.
@MainActor
enum DockPresence {
    /// The icon a window shows in the Dock.
    enum Icon {
        /// skil.li's own (`AppIcon.icon`, as the system draws it).
        case app
        /// `RecorderIcon.icns` (assets/brand/recorder-icon): while any
        /// recording's window is open, Settings in front or not.
        case recorder
    }

    private struct Holder {
        weak var window: NSWindow?
        let icon: Icon
    }

    private static var holders: [ObjectIdentifier: Holder] = [:]
    /// The icon shown now.
    private(set) static var icon: Icon = .app
    /// Read when first shown, let go once no window shows it: not kept by
    /// name in NSImage's cache (its sizes up to 1024 px).
    private static var recorderImage: NSImage?

    /// `window` keeps skil.li in the Dock, with `icon`, until `release`.
    static func hold(_ window: NSWindow, icon: Icon = .app) {
        holders[ObjectIdentifier(window)] = Holder(window: window, icon: icon)
        update()
    }

    static func release(_ window: NSWindow) {
        holders[ObjectIdentifier(window)] = nil
        update()
    }

    /// The windows keeping skil.li in the Dock, the one in front first,
    /// minimized ones last: the Dock's icon brings the first
    /// (`applicationShouldHandleReopen`).
    static var windows: [NSWindow] {
        let order = NSApp.orderedWindows
        return holders.values.compactMap(\.window).sorted {
            (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max)
        }
    }

    private static func update() {
        holders = holders.filter { $0.value.window != nil }
        let policy: NSApplication.ActivationPolicy = holders.isEmpty ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        let wanted: Icon = holders.values.contains { $0.icon == .recorder } ? .recorder : .app
        guard wanted != icon else { return }
        icon = wanted
        switch wanted {
        case .recorder:
            if recorderImage == nil {
                recorderImage = Bundle.main.url(forResource: "RecorderIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
            }
            NSApp.applicationIconImage = recorderImage
        case .app:
            // nil: the app's own icon again.
            NSApp.applicationIconImage = nil
            recorderImage = nil
        }
    }
}
