/// Layout-independent identity of a key, as bindings see it.
///
/// Character keys are resolved through the active keyboard layout, so `a` means
/// "the key that types a" on AZERTY as well as QWERTY. Named keys are fixed
/// physical keys that do not depend on the layout.
public enum Key: Hashable, Sendable {
    case character(Character)
    case named(NamedKey)
}

public enum NamedKey: String, CaseIterable, Hashable, Sendable {
    case space
    case `return`
    case tab
    case escape
    case delete
    case forwardDelete
    case left
    case right
    case up
    case down
    case home
    case end
    case pageUp
    case pageDown

    /// Spellings accepted in binding specs, e.g. `hyper+esc`.
    static let aliases: [String: NamedKey] = {
        var aliases: [String: NamedKey] = [:]
        for key in NamedKey.allCases {
            aliases[key.rawValue.lowercased()] = key
        }
        aliases["enter"] = .return
        aliases["esc"] = .escape
        aliases["backspace"] = .delete
        aliases["del"] = .forwardDelete
        aliases["pgup"] = .pageUp
        aliases["pgdown"] = .pageDown
        return aliases
    }()

    var symbol: String {
        switch self {
        case .space: "Space"
        case .return: "↩"
        case .tab: "⇥"
        case .escape: "⎋"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        }
    }
}

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)

    /// ⌘⌃⌥⇧ held together — what the Hyper key produces.
    public static let hyper: Modifiers = [.command, .control, .option, .shift]

    /// What counts of these on a later chord of a chain whose first chord
    /// had `first`: not what is still held from it, nor Hyper.
    public func inChain(after first: Modifiers) -> Modifiers {
        var modifiers = self
        if modifiers.isSuperset(of: .hyper) { modifiers.subtract(.hyper) }
        modifiers.subtract(first)
        return modifiers
    }
}

/// One key press with its modifiers, e.g. `hyper+space` or `cmd+shift+k`.
public struct Chord: Hashable, Sendable {
    public var key: Key
    public var modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum ChordParseError: Error, Equatable {
    case empty
    case missingKey(String)
    case unknownModifier(String)
    case unknownKey(String)
}

extension Chord {
    /// Parses a single chord such as `hyper+space`, `cmd+shift+k` or `u`.
    public init(parsing spec: String) throws {
        let tokens = spec.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyToken = tokens.last, !spec.isEmpty else { throw ChordParseError.empty }
        guard !keyToken.isEmpty else { throw ChordParseError.missingKey(spec) }

        var modifiers: Modifiers = []
        for token in tokens.dropLast() {
            switch token {
            case "hyper", "✦": modifiers.formUnion(.hyper)
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "shift", "⇧": modifiers.insert(.shift)
            default: throw ChordParseError.unknownModifier(token)
            }
        }

        if let named = NamedKey.aliases[keyToken] {
            self.init(.named(named), modifiers)
        } else if keyToken == "plus" {
            // "+" separates tokens, so the plus key is spelled out.
            self.init(.character("+"), modifiers)
        } else if keyToken.count == 1, let character = keyToken.first {
            self.init(.character(character), modifiers)
        } else {
            throw ChordParseError.unknownKey(keyToken)
        }
    }

    /// Parses a whitespace-separated sequence such as `hyper+k u`.
    public static func sequence(_ spec: String) throws -> [Chord] {
        let parts = spec.split(whereSeparator: \.isWhitespace)
        guard !parts.isEmpty else { throw ChordParseError.empty }
        return try parts.map { try Chord(parsing: String($0)) }
    }
}

extension Chord {
    /// This chord pressed inside a chain that `first` started: the
    /// modifiers still held from `first` do not count, nor Hyper. ⌘ kept
    /// down while Space is pressed twice is ⌘Space then Space, as Caps Lock
    /// kept down for ✦K then Y is ✦K then Y.
    public func inChain(after first: Chord) -> Chord {
        Chord(key, modifiers.inChain(after: first.modifiers))
    }

    /// A chain as the engine matches it: every chord after the first
    /// `inChain(after:)` it. `cmd+space cmd+space` → `cmd+space space`.
    public static func chain(_ chords: [Chord]) -> [Chord] {
        guard let first = chords.first else { return chords }
        return [first] + chords.dropFirst().map { $0.inChain(after: first) }
    }
}

extension Chord {
    /// One label per physical key, for drawing keycaps: `hyper+k` →
    /// `["✦", "K"]`, `cmd+shift+k` → `["⇧", "⌘", "K"]`.
    public var keycaps: [String] {
        var caps: [String] = []
        if modifiers.isSuperset(of: .hyper) {
            caps.append("✦")
        } else {
            if modifiers.contains(.control) { caps.append("⌃") }
            if modifiers.contains(.option) { caps.append("⌥") }
            if modifiers.contains(.shift) { caps.append("⇧") }
            if modifiers.contains(.command) { caps.append("⌘") }
        }
        caps.append(key.description)
        return caps
    }
}

extension Chord {
    /// Inverse of `init(parsing:)`, for config files: `hyper+k`,
    /// `ctrl+opt+shift+cmd+k`, `space`, `cmd+plus`.
    public var spec: String {
        var parts: [String] = []
        if modifiers.isSuperset(of: .hyper) {
            parts.append("hyper")
        } else {
            if modifiers.contains(.control) { parts.append("ctrl") }
            if modifiers.contains(.option) { parts.append("opt") }
            if modifiers.contains(.shift) { parts.append("shift") }
            if modifiers.contains(.command) { parts.append("cmd") }
        }
        switch key {
        case .character("+"): parts.append("plus")
        case .character(let character): parts.append(String(character))
        case .named(let named): parts.append(named.rawValue.lowercased())
        }
        return parts.joined(separator: "+")
    }

    /// `hyper+k u` for a sequence.
    public static func spec(_ sequence: [Chord]) -> String {
        sequence.map(\.spec).joined(separator: " ")
    }
}

extension Chord: CustomStringConvertible {
    /// Mac-style rendering: modifiers in ⌃⌥⇧⌘ order, Hyper shown as ✦.
    public var description: String {
        var prefix = ""
        if modifiers.isSuperset(of: .hyper) {
            prefix = "✦"
        } else {
            if modifiers.contains(.control) { prefix += "⌃" }
            if modifiers.contains(.option) { prefix += "⌥" }
            if modifiers.contains(.shift) { prefix += "⇧" }
            if modifiers.contains(.command) { prefix += "⌘" }
        }
        let keyText = key.description
        let needsSpace = !prefix.isEmpty && (prefix == "✦" || keyText.count > 1)
        return prefix + (needsSpace ? " " : "") + keyText
    }
}

extension Key: CustomStringConvertible {
    public var description: String {
        switch self {
        case .character(let character): String(character).uppercased()
        case .named(let named): named.symbol
        }
    }
}
