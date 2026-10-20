import Foundation

/// What a command takes when nothing is selected: the whole field when it
/// is short (a message, a search, a subject line), else the paragraph the
/// cursor is in. Ranges are in UTF-16 units, as Accessibility counts them.
public enum InputScope {
    /// A field up to this long is taken whole.
    public static let wholeFieldLimit = 2000

    /// nil when there is nothing but blanks to take.
    public static func range(in text: String, cursor: Int, wholeFieldLimit: Int = InputScope.wholeFieldLimit) -> NSRange? {
        let string = text as NSString
        let scope: NSRange
        if string.length <= wholeFieldLimit {
            scope = NSRange(location: 0, length: string.length)
        } else {
            scope = string.paragraphRange(for: NSRange(location: min(max(cursor, 0), string.length), length: 0))
        }
        return trimmed(scope, in: string)
    }

    /// Nothing but blanks and line breaks, no-break spaces included: no
    /// text to work on, whatever the app says is selected.
    public static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    /// `range` without the blanks and line breaks at its ends.
    private static func trimmed(_ range: NSRange, in string: NSString) -> NSRange? {
        var start = range.location
        var end = range.location + range.length
        let blanks = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = Unicode.Scalar(string.character(at: start)), blanks.contains(scalar) { start += 1 }
        while end > start, let scalar = Unicode.Scalar(string.character(at: end - 1)), blanks.contains(scalar) { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
