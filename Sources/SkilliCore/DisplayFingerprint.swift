import CoreGraphics

/// Who a display is, from what it says about itself (EDID: maker, model,
/// serial, week of manufacture) and macOS's own id for it: a layout knows
/// its display and never takes another with the same name for it.
public struct DisplayFingerprint: Codable, Equatable, Hashable, Sendable {
    /// What macOS calls it ("SAMSUNG", "Built-in Retina Display").
    public var name: String
    public var vendor: UInt32
    public var model: UInt32
    /// EDID's number, 0 when the display gives none. Some makers put the
    /// same one on every unit.
    public var serial: UInt32
    /// EDID's text serial (the one on the sticker), when there is one.
    public var serialText: String?
    /// "2025-W1", when the display says.
    public var made: String?
    public var builtIn: Bool
    /// macOS's id for the display (`CGDisplayCreateUUIDFromDisplayID`), the
    /// one it keeps the arrangement under: tells two identical displays
    /// without a serial apart.
    public var uuid: String

    public init(name: String, vendor: UInt32, model: UInt32, serial: UInt32, serialText: String? = nil, made: String? = nil,
                builtIn: Bool, uuid: String) {
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.serialText = serialText
        self.made = made
        self.builtIn = builtIn
        self.uuid = uuid
    }

    /// How sure skil.li is that a display is the one saved.
    public enum Certainty: String, Codable, Sendable {
        /// Its own serial, or the Mac's built-in display.
        case unit
        /// Only its model: it has no serial of its own.
        case model
    }

    /// How surely this display can be told from other units of its model.
    public var certainty: Certainty {
        builtIn || hasSerial ? .unit : .model
    }

    var hasSerial: Bool { !(serialText ?? "").isEmpty || serial != 0 }

    /// The same display, and how sure; nil for another one.
    public func same(as other: DisplayFingerprint) -> Certainty? {
        guard vendor == other.vendor, model == other.model, builtIn == other.builtIn else { return nil }
        if builtIn { return .unit }
        if let mine = serialText, !mine.isEmpty, let theirs = other.serialText, !theirs.isEmpty {
            return mine == theirs ? .unit : nil
        }
        if serial != 0, other.serial != 0 {
            guard serial == other.serial else { return nil }
            if let mine = made, let theirs = other.made, mine != theirs { return nil }
            return .unit
        }
        // A display that gave a serial once gives it again: one with and
        // one without are two units.
        guard hasSerial == other.hasSerial else { return nil }
        return .model
    }
}

/// A display as a layout sees it: who it is and where it sits.
public struct LayoutDisplay: Codable, Equatable, Sendable {
    public var fingerprint: DisplayFingerprint
    /// Top-left, y down, like Accessibility; the menu bar's display at 0,0.
    public var frame: CGRect
    /// Without the menu bar and the Dock.
    public var visible: CGRect

    public init(fingerprint: DisplayFingerprint, frame: CGRect, visible: CGRect) {
        self.fingerprint = fingerprint
        self.frame = frame
        self.visible = visible
    }

    /// "SAMSUNG 3840×2160".
    public var label: String { "\(fingerprint.name) \(Int(frame.width))×\(Int(frame.height))" }
}

public enum DisplayPairing {
    public enum Match: Equatable, Sendable {
        /// This very display: sure, or only by its model.
        case same(DisplayFingerprint.Certainty)
        /// The saved display is not connected: this one stands in.
        case standIn
    }

    public struct Pair: Equatable, Sendable {
        /// Among the displays there are now.
        public var index: Int
        public var match: Match
    }

    /// For each saved display, the display its windows go to now: itself
    /// when it is connected (by serial first, then by macOS's id for it),
    /// else the nearest one left of the same kind (built-in or not), else
    /// the nearest one. Empty when no display is connected.
    public static func pair(saved: [LayoutDisplay], current: [LayoutDisplay]) -> [Pair] {
        guard !current.isEmpty else { return [] }
        // Two connected displays that both pass for the same unit (a maker
        // writing one serial on every unit) are only told apart by model.
        let ambiguous = Set(current.indices.filter { index in
            current.indices.contains { $0 != index && current[$0].fingerprint.same(as: current[index].fingerprint) == .unit }
        })
        var candidates: [(saved: Int, current: Int, certainty: DisplayFingerprint.Certainty, score: Int)] = []
        for (s, display) in saved.enumerated() {
            for (c, now) in current.enumerated() {
                guard let found = display.fingerprint.same(as: now.fingerprint) else { continue }
                let certainty: DisplayFingerprint.Certainty = found == .unit && !ambiguous.contains(c) ? .unit : .model
                let score = (certainty == .unit ? 4 : 2) + (display.fingerprint.uuid == now.fingerprint.uuid ? 1 : 0)
                candidates.append((s, c, certainty, score))
            }
        }
        var result = [Pair?](repeating: nil, count: saved.count)
        var used = Set<Int>()
        for candidate in candidates.sorted(by: { ($0.score, -$0.saved) > ($1.score, -$1.saved) })
        where result[candidate.saved] == nil && !used.contains(candidate.current) {
            result[candidate.saved] = Pair(index: candidate.current, match: .same(candidate.certainty))
            used.insert(candidate.current)
        }
        for (s, display) in saved.enumerated() where result[s] == nil {
            let free = current.indices.filter { !used.contains($0) }
            let sameKind = free.filter { current[$0].fingerprint.builtIn == display.fingerprint.builtIn }
            let pool = !sameKind.isEmpty ? sameKind : !free.isEmpty ? free : Array(current.indices)
            let nearest = pool.min { distance(display.frame, current[$0].frame) < distance(display.frame, current[$1].frame) } ?? 0
            result[s] = Pair(index: nearest, match: .standIn)
            used.insert(nearest)
        }
        return result.compactMap(\.self)
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }
}
