import Foundation

/// Keys a window's list took on their press (a recording's ⌘K, phase 5):
/// their auto-repeats are not new presses, as `KeyRouter`'s
/// `swallowedKeyCodes` does for the keys the event tap takes. Held ⌘K
/// opens the list once; held ↩ runs one action, never the window's own ↩
/// after it. In the list, the keys that move or type there (arrows, ⌫, a
/// letter) go on repeating. The key's release ends it; a fresh press of
/// the same key forgets one whose release never came.
public struct HeldKeys: Sendable {
    /// What a press is.
    public enum Press: Equatable, Sendable {
        /// A press of its own: handled as any.
        case new
        /// A repeat of a key the list took, the list open and the key one
        /// that repeats there.
        case toList
        /// A repeat of a key the list took: nothing.
        case swallowed
    }

    private var held: Set<UInt16> = []

    public init() {}

    /// A key down as it comes.
    public mutating func press(_ code: UInt16, isRepeat: Bool, listShown: Bool, repeatsInList: Bool) -> Press {
        guard isRepeat else {
            held.remove(code)
            return .new
        }
        guard held.contains(code) else { return .new }
        return listShown && repeatsInList ? .toList : .swallowed
    }

    /// The key the list took (or opened or closed it, or ran its action):
    /// its repeats are not new presses until it is released.
    public mutating func took(_ code: UInt16) {
        held.insert(code)
    }

    public mutating func released(_ code: UInt16) {
        held.remove(code)
    }
}
