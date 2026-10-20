import Foundation

/// The number row on layouts that type symbols there without Shift (French
/// AZERTY: & é " ' ( - è _ ç à): shortcuts still name its keys 1 to 0, so
/// `hyper+1` is the key that types 1 with Shift. Typing is not affected.
public enum NumberRow {
    /// The digit a shortcut names this key by: its own when Shift types
    /// that digit and the key alone types something else; nil when the key
    /// alone already types the digit (QWERTY) or the layout is unusual.
    public static func shortcutDigit(_ digit: Character, unshifted: String, shifted: String) -> Character? {
        guard shifted == String(digit), unshifted != String(digit) else { return nil }
        return digit
    }
}
