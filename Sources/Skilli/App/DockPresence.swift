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
        /// When it was last in front (held, or made key): a minimized
        /// window is in no on-screen order, so this is the one kept.
        var fronted: Int
    }

    private static var holders: [ObjectIdentifier: Holder] = [:]
    /// Counts each time a held window comes in front.
    private static var fronts = 0
    private static var keyObserver: NSObjectProtocol?
    /// The icon shown now.
    private(set) static var icon: Icon = .app
    /// Read when first shown, let go once no window shows it: not kept by
    /// name in NSImage's cache (its sizes up to 1024 px).
    private static var recorderImage: NSImage?

    /// `window` keeps skil.li in the Dock, with `icon`, until `release`.
    static func hold(_ window: NSWindow, icon: Icon = .app) {
        fronts += 1
        holders[ObjectIdentifier(window)] = Holder(window: window, icon: icon, fronted: fronts)
        if keyObserver == nil {
            keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                let id = ObjectIdentifier(window)
                MainActor.assumeIsolated { cameInFront(id) }
            }
        }
        update()
    }

    static func release(_ window: NSWindow) {
        holders[ObjectIdentifier(window)] = nil
        update()
    }

    /// The windows keeping skil.li in the Dock, the one last in front
    /// first, minimized or not: the Dock's icon brings it
    /// (`applicationShouldHandleReopen`).
    static var windows: [NSWindow] {
        holders.values.sorted { $0.fronted > $1.fronted }.compactMap(\.window)
    }

    private static func cameInFront(_ id: ObjectIdentifier) {
        guard holders[id] != nil else { return }
        fronts += 1
        holders[id]?.fronted = fronts
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
