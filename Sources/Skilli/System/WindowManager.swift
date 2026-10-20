import AppKit
import ApplicationServices
import SkilliCore

/// Puts the front window where a `WindowLayout` says: through Accessibility
/// for other apps, directly for skil.li's own windows (Accessibility into
/// skil.li from skil.li can deadlock). Remembers where each window was
/// before skil.li first moved it, for Restore and for Maximize twice, and
/// its last place, so the same place pressed again soon takes its next
/// size (`WindowCycle`): shortcuts, the launcher, Ask and agents all come
/// through `apply`.
@MainActor
final class WindowManager {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Key: Hashable {
        let pid: pid_t
        let window: Int
    }

    /// Where skil.li last put a window, where it was before, and the place
    /// and size it was put at.
    private struct Memory {
        var placed: CGRect
        var before: CGRect
        var cycle: WindowCycle?
    }

    private var memory: [Key: Memory] = [:]
    /// Points between windows and at the screen's edges (Settings →
    /// Windows), read at each press.
    var gap: () -> CGFloat = { 0 }

    /// The front window, as skil.li can move it.
    private enum Handle {
        case other(app: AXUIElement, window: AXUIElement, pid: pid_t, name: String)
        case own(NSWindow)

        var key: Key {
            switch self {
            case .other(_, let window, let pid, _): Key(pid: pid, window: Int(CFHash(window)))
            case .own(let window): Key(pid: getpid(), window: window.windowNumber)
            }
        }

        var name: String {
            switch self {
            case .other(_, _, _, let name): name
            case .own: "skil.li"
            }
        }
    }

    /// What it did, in one line; throws a message for the user.
    @discardableResult
    func apply(_ layout: WindowLayout) throws -> String {
        let start = ContinuousClock.now
        let handle = try frontWindow()
        let current = try frame(of: handle)
        let screens = NSScreen.screens.map { (frame: Self.topLeft($0.frame), visible: Self.topLeft($0.visibleFrame)) }
        guard !screens.isEmpty else { throw Failure(message: "No display.") }
        // The screen showing most of the window.
        let here = screens.indices.max { screens[$0].frame.intersection(current).area < screens[$1].frame.intersection(current).area } ?? 0
        let key = handle.key
        let remembered = memory[key]
        let gap = gap()
        var cycle: WindowCycle?
        // Moved by the user since: where it is now is what Restore keeps.
        let before = remembered.flatMap { WindowLayout.matches(current, $0.placed) ? $0.before : nil } ?? current

        let target: CGRect
        switch layout {
        case .restore:
            guard let remembered, remembered.before != current else {
                throw Failure(message: "Nothing to restore: skil.li has not moved this window.")
            }
            target = remembered.before
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1 else { throw Failure(message: "There is only one display.") }
            let ordered = screens.indices.sorted { (screens[$0].frame.minX, screens[$0].frame.minY) < (screens[$1].frame.minX, screens[$1].frame.minY) }
            let position = ordered.firstIndex(of: here) ?? 0
            let step = layout == .nextDisplay ? 1 : ordered.count - 1
            // A place ✦W gives stays that place there; any other frame keeps
            // its place in proportion.
            target = WindowLayout.moved(current, from: screens[here].visible, to: screens[ordered[(position + step) % ordered.count]].visible,
                                        gap: gap)
        default:
            let visible = screens[here].visible
            let size = WindowCycle.size(of: layout, current: current, visible: visible, gap: gap, last: remembered?.cycle, now: .now)
            switch layout.target(current: current, visible: visible, gap: gap, size: size) {
            case .frame(let frame):
                target = frame
                if layout.sizes.count > 1 { cycle = WindowCycle(layout: layout, size: size, placed: frame, at: .now) }
            case .restore:
                // Filled already: back to before, or almost filled when
                // skil.li did not fill it.
                if let remembered, remembered.before != current {
                    target = remembered.before
                } else if case .frame(let almost) = WindowLayout.almostMaximize.target(current: current, visible: visible) {
                    target = almost
                } else {
                    return layout.title
                }
            case nil:
                return layout.title
            }
        }

        try setFrame(target, of: handle)
        let placed = (try? frame(of: handle)) ?? target
        // Pressed again from now: where it ended, as the app keeps it.
        cycle?.placed = placed
        cycle?.at = .now
        memory[key] = layout == .restore ? nil : Memory(placed: placed, before: before, cycle: cycle)
        Log.trace("Window: \(layout.rawValue)\(cycle.map { " size \($0.size + 1)" } ?? "") for \(handle.name), \(Self.describe(current)) → \(Self.describe(placed)), gap \(Int(gap)), in \((ContinuousClock.now - start).compact)")
        return layout.title
    }

    // MARK: - The front window

    /// Where the front window is (Accessibility's top left), to capture
    /// it: in full screen or not movable alike.
    func frontWindowFrame() throws -> CGRect {
        try frame(of: frontWindow(toMove: false))
    }

    private func frontWindow(toMove: Bool = true) throws -> Handle {
        guard let app = NSWorkspace.shared.frontmostApplication else { throw Failure(message: "No app in front.") }
        if app.processIdentifier == getpid() {
            // Settings or the setup window; never the launcher or the card.
            guard let window = NSApp.orderedWindows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }) else {
                throw Failure(message: "No window in front.")
            }
            return .own(window)
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // A busy app must not hold skil.li up.
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard let window: AXUIElement = Self.attribute(element, kAXFocusedWindowAttribute) ?? Self.attribute(element, kAXMainWindowAttribute) else {
            throw Failure(message: "\(app.localizedName ?? "This app") has no window in front.")
        }
        guard toMove else { return .other(app: element, window: window, pid: app.processIdentifier, name: app.localizedName ?? "?") }
        if Self.attribute(window, "AXFullScreen") as Bool? == true {
            throw Failure(message: "The window is in full screen: leave it first (⌃⌘F).")
        }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
        guard settable.boolValue else { throw Failure(message: "\(app.localizedName ?? "This app")'s window cannot be moved.") }
        return .other(app: element, window: window, pid: app.processIdentifier, name: app.localizedName ?? "?")
    }

    private func frame(of handle: Handle) throws -> CGRect {
        switch handle {
        case .own(let window):
            return Self.topLeft(window.frame)
        case .other(_, let window, _, _):
            guard let positionValue: AXValue = Self.attribute(window, kAXPositionAttribute),
                  let sizeValue: AXValue = Self.attribute(window, kAXSizeAttribute)
            else { throw Failure(message: "The window's place cannot be read.") }
            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionValue, .cgPoint, &position)
            AXValueGetValue(sizeValue, .cgSize, &size)
            return CGRect(origin: position, size: size)
        }
    }

    private func setFrame(_ frame: CGRect, of handle: Handle) throws {
        switch handle {
        case .own(let window):
            window.setFrame(Self.bottomLeft(frame), display: true, animate: false)
        case .other(let app, let window, _, _):
            try Self.place(window, of: app, at: frame)
        }
    }

    /// Another app's window at `frame` (top-left, like Accessibility).
    static func place(_ window: AXUIElement, of app: AXUIElement, at frame: CGRect) throws {
        // Apps that turned on enhanced UI for VoiceOver (Chrome,
        // Electron…) animate every change: off while we move.
        let enhanced = attribute(app, "AXEnhancedUserInterface") as Bool? == true
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer {
            if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        }
        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        // Size, place, size again: a window too big for where it was
        // gets its size only once it moved.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard moved == .success else { throw Failure(message: "The window did not move (\(moved.rawValue)).") }
    }

    // MARK: - Helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self || T.self == AXValue.self {
            return (value as! T)
        }
        return value as? T
    }

    /// AppKit's frames start at the bottom left of the main display;
    /// Accessibility's at its top left, y going down.
    static func topLeft(_ rect: NSRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func bottomLeft(_ rect: CGRect) -> NSRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
