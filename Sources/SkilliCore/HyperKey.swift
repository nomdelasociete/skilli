/// Tracks the Hyper trigger key (Caps Lock remapped to an F-key).
///
/// Held, it acts as ⌘⌃⌥⇧. Tapped alone and released quickly, the caller emits
/// the tap action (Escape).
public struct HyperKeyMachine: Sendable {
    public var tapThreshold: Duration
    public private(set) var isHeld = false
    private var usedWhileHeld = false
    private var pressedAt: ContinuousClock.Instant?

    public init(tapThreshold: Duration = .milliseconds(400)) {
        self.tapThreshold = tapThreshold
    }

    /// Key-repeat downs are ignored so holding the key does not restart the
    /// tap window.
    public mutating func triggerDown(at now: ContinuousClock.Instant) {
        guard !isHeld else { return }
        isHeld = true
        usedWhileHeld = false
        pressedAt = now
    }

    /// Returns `true` when this release completes a tap: no other key was
    /// pressed while held and the hold was shorter than `tapThreshold`.
    public mutating func triggerUp(at now: ContinuousClock.Instant) -> Bool {
        defer {
            isHeld = false
            usedWhileHeld = false
            pressedAt = nil
        }
        guard isHeld, !usedWhileHeld, let pressedAt else { return false }
        return now - pressedAt <= tapThreshold
    }

    public mutating func noteKeyWhileHeld() {
        if isHeld { usedWhileHeld = true }
    }

    /// The trigger's release was missed (Secure Input hid it): no longer
    /// held, and no tap.
    public mutating func release() {
        isHeld = false
        usedWhileHeld = false
        pressedAt = nil
    }
}

/// One `UserKeyMapping` entry, as `hidutil` reports and accepts it.
public struct HIDKeyMapping: Hashable, Sendable {
    public var source: UInt64
    public var destination: UInt64

    public init(source: UInt64, destination: UInt64) {
        self.source = source
        self.destination = destination
    }

    /// HID usages are `0x700000000 | keyboardUsageID`.
    public static let capsLock: UInt64 = 0x7_0000_0039
    public static let f13: UInt64 = 0x7_0000_0068
    public static let f18: UInt64 = 0x7_0000_006D
    public static let f24: UInt64 = 0x7_0000_0073

    public static func isFunctionKeyF13toF24(_ usage: UInt64) -> Bool {
        (f13...f24).contains(usage)
    }
}

/// What skil.li should do about Caps Lock at launch.
public enum HyperKeyPlan: Equatable, Sendable {
    /// Another tool (e.g. Raycast's Hyper Key) already maps Caps Lock to an
    /// F-key: reuse that key as the trigger and leave the mapping alone.
    case adopt(trigger: UInt64)
    /// No key mappings exist anywhere: map Caps Lock → F18 ourselves and
    /// remove it again on quit.
    case install(HIDKeyMapping)
    /// Other mappings exist (e.g. Caps Lock → Control from System Settings).
    /// Do not clobber them; Hyper still works when another tool sends ⌘⌃⌥⇧.
    case leaveAlone
}

public enum HyperKeyPlanner {
    public static func plan(existing: [HIDKeyMapping]) -> HyperKeyPlan {
        if let caps = existing.first(where: {
            $0.source == HIDKeyMapping.capsLock && HIDKeyMapping.isFunctionKeyF13toF24($0.destination)
        }) {
            return .adopt(trigger: caps.destination)
        }
        if existing.isEmpty {
            return .install(HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: HIDKeyMapping.f18))
        }
        return .leaveAlone
    }

    /// Parses `hidutil property --get UserKeyMapping`, which prints one
    /// OpenStep-style array per HID service. Returns the distinct mappings.
    public static func parseHIDUtilOutput(_ output: String) -> [HIDKeyMapping] {
        var mappings: [HIDKeyMapping] = []
        var remainder = output[...]
        while let open = remainder.firstIndex(of: "{"),
              let close = remainder[open...].firstIndex(of: "}") {
            let block = remainder[open...close]
            if let source = value(named: "HIDKeyboardModifierMappingSrc", in: block),
               let destination = value(named: "HIDKeyboardModifierMappingDst", in: block) {
                let mapping = HIDKeyMapping(source: source, destination: destination)
                if !mappings.contains(mapping) { mappings.append(mapping) }
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        return mappings
    }

    private static func value(named name: String, in block: Substring) -> UInt64? {
        guard let nameRange = block.range(of: name) else { return nil }
        let afterName = block[nameRange.upperBound...]
        guard let equals = afterName.firstIndex(of: "=") else { return nil }
        let token = afterName[afterName.index(after: equals)...]
            .drop(while: \.isWhitespace)
            .prefix { $0.isHexDigit || $0 == "x" || $0 == "X" }
        if token.hasPrefix("0x") || token.hasPrefix("0X") {
            return UInt64(token.dropFirst(2), radix: 16)
        }
        return UInt64(token)
    }
}
