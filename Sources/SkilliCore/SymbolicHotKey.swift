import Foundation

/// One of macOS's own shortcuts, as System Settings → Keyboard → Keyboard
/// Shortcuts keeps it (`com.apple.symbolichotkeys`, `AppleSymbolicHotKeys`):
/// its key code and modifiers, or nil when the user turned it off.
public struct SymbolicHotKey: Equatable, Sendable {
    /// A virtual key code (103 is F11).
    public let keyCode: UInt16
    /// NSEvent's modifier bits as macOS stores them (shift 1 << 17,
    /// control 1 << 18, option 1 << 19, command 1 << 20, fn 1 << 23): the
    /// same bits as CGEventFlags.
    public let modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Mission Control → Show Desktop.
    public static let showDesktopID = "36"
    /// Its default: F11.
    public static let showDesktopDefault = SymbolicHotKey(keyCode: 103, modifiers: 0)

    /// The shortcut `id` in `AppleSymbolicHotKeys` (a dictionary of
    /// entries by number); `standard` when the user never changed it
    /// (macOS writes an entry only then). Nil when it is turned off or has
    /// no key.
    public static func read(_ id: String, in hotKeys: [String: Any]?, standard: SymbolicHotKey?) -> SymbolicHotKey? {
        guard let entry = hotKeys?[id] as? [String: Any] else { return standard }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return nil }
        guard let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3 else {
            return standard
        }
        let code = parameters[1].intValue
        // 65535: no key.
        guard code >= 0, code < 0xFFFF else { return nil }
        return SymbolicHotKey(keyCode: UInt16(code), modifiers: parameters[2].uint64Value)
    }

    /// The character macOS keeps with the shortcut `id` (its first
    /// parameter: "m" for Minimize), nil when it has none (65535).
    public static func character(_ id: String, in hotKeys: [String: Any]?) -> UInt16? {
        guard let entry = hotKeys?[id] as? [String: Any], let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], let first = parameters.first,
              first.intValue >= 0, first.intValue < 0xFFFF
        else { return nil }
        return UInt16(first.intValue)
    }

    /// F1…F20: a keyboard sends them with the fn bit set.
    public var isFunctionKey: Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90].contains(keyCode)
    }
}
