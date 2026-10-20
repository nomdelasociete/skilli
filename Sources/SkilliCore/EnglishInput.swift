import Foundation

/// Settings → Launcher → Type in English while open: which of the user's
/// own input sources the launcher types with. Only one they turned on in
/// System Settings → Keyboard (skil.li never adds or turns on a source):
/// ABC first, then U.S., then any other English keyboard layout that types
/// plain letters (British, ABC – Extended…).
public enum EnglishInput {
    /// An input source as Text Input Sources describes it.
    public struct Source: Equatable, Sendable {
        public let id: String
        public let name: String
        /// Its languages, the first being its own ("en", "fr").
        public let languages: [String]
        /// Types plain Latin letters (kTISPropertyInputSourceIsASCIICapable).
        public let asciiCapable: Bool
        /// A keyboard layout, not an input method or one of its modes.
        public let isKeyboardLayout: Bool

        public init(id: String, name: String, languages: [String], asciiCapable: Bool, isKeyboardLayout: Bool) {
            self.id = id
            self.name = name
            self.languages = languages
            self.asciiCapable = asciiCapable
            self.isKeyboardLayout = isKeyboardLayout
        }

        /// An English keyboard layout of plain letters.
        public var isEnglish: Bool {
            asciiCapable && isKeyboardLayout && (languages.first?.lowercased().hasPrefix("en") ?? false)
        }
    }

    /// Tried first, in this order.
    public static let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]

    /// The source to type with among those the user turned on; nil when
    /// none is English.
    public static func pick(_ enabled: [Source]) -> Source? {
        for id in preferred {
            if let source = enabled.first(where: { $0.id == id }) { return source }
        }
        return enabled.first(where: \.isEnglish)
    }

    /// Whether opening the launcher switches from `current` to `english`:
    /// not when there is none, nor when the user types English already.
    public static func switches(from current: Source?, to english: Source?) -> Bool {
        guard let english else { return false }
        guard let current else { return true }
        return current.id != english.id && !current.isEnglish
    }
}
