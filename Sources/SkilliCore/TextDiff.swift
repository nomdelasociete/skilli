import Foundation

/// Word-level difference between an original text and its rewrite, for
/// highlighting what an AI action changed.
public enum TextDiff {
    public enum Kind: Equatable, Sendable {
        case same
        case inserted
        case deleted
    }

    public struct Segment: Equatable, Sendable {
        public let kind: Kind
        public let text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Above this many token pairs the diff is skipped (`nil`): long texts
    /// are shown plainly rather than stalling the main thread.
    public static let maxWork = 4_000_000

    /// Segments of `new` and `old` interleaved in reading order; `nil` when
    /// the texts are too long to compare.
    public static func segments(from old: String, to new: String) -> [Segment]? {
        let a = tokens(old), b = tokens(new)
        guard a.count * b.count <= maxWork else { return nil }

        // Longest common subsequence, table built from the end.
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var result: [Segment] = []
        func append(_ kind: Kind, _ text: String) {
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = Segment(kind, last.text + text)
            } else {
                result.append(Segment(kind, text))
            }
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                append(.same, a[i]); i += 1; j += 1
            } else if i < a.count, j == b.count || table[i + 1][j] >= table[i][j + 1] {
                // Old before new, the way corrections are read: ~~cat~~ dog.
                append(.deleted, a[i]); i += 1
            } else {
                append(.inserted, b[j]); j += 1
            }
        }
        return refined(result)
    }

    /// A word replaced by a close one shows only the letters that changed:
    /// enfant → enfant·s, manger → mang·~~er~~·é. Unrelated words stay
    /// replaced whole.
    static func refined(_ segments: [Segment]) -> [Segment] {
        var output: [Segment] = []
        func append(_ segment: Segment) {
            if let last = output.last, last.kind == segment.kind {
                output[output.count - 1] = Segment(segment.kind, last.text + segment.text)
            } else {
                output.append(segment)
            }
        }
        var index = 0
        while index < segments.count {
            let segment = segments[index]
            if segment.kind == .deleted, index + 1 < segments.count, segments[index + 1].kind == .inserted,
               let letters = letterDiff(segment.text, segments[index + 1].text) {
                letters.forEach(append)
                index += 2
            } else {
                append(segment)
                index += 1
            }
        }
        return output
    }

    /// Letter-by-letter diff of two close strings; `nil` when they share too
    /// little (under half their letters) for it to read well.
    static func letterDiff(_ old: String, _ new: String) -> [Segment]? {
        let a = Array(old), b = Array(new)
        guard !a.isEmpty, !b.isEmpty, a.count * b.count <= 10_000 else { return nil }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        guard 2 * Double(table[0][0]) / Double(a.count + b.count) >= 0.5 else { return nil }

        var result: [Segment] = []
        func append(_ kind: Kind, _ character: Character) {
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = Segment(kind, last.text + String(character))
            } else {
                result.append(Segment(kind, String(character)))
            }
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                append(.same, a[i]); i += 1; j += 1
            } else if i < a.count, j == b.count || table[i + 1][j] >= table[i][j + 1] {
                append(.deleted, a[i]); i += 1
            } else {
                append(.inserted, b[j]); j += 1
            }
        }
        return result
    }

    /// Share of the rewrite's characters kept from the original (0...1).
    public static func similarity(_ segments: [Segment]) -> Double {
        let kept = segments.filter { $0.kind == .same }.reduce(0) { $0 + $1.text.count }
        let new = segments.filter { $0.kind != .deleted }.reduce(0) { $0 + $1.text.count }
        return new == 0 ? 1 : Double(kept) / Double(new)
    }

    /// Letter-level likeness of two texts (0...1), ignoring case and accents:
    /// a heavy correction ("enfant" → "enfants") stays high, a translation
    /// drops. Decides whether highlighting changes helps. `nil` when too long.
    public static func characterSimilarity(_ old: String, _ new: String) -> Double? {
        func letters(_ text: String) -> [Character] {
            Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { !$0.isWhitespace })
        }
        let a = letters(old), b = letters(new)
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty ? 1 : 0 }
        guard a.count * b.count <= maxWork else { return nil }
        // Longest common subsequence, two rows at a time.
        var previous = Array(repeating: 0, count: b.count + 1)
        var current = previous
        for i in 1...a.count {
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1] ? previous[j - 1] + 1 : max(previous[j], current[j - 1])
            }
            swap(&previous, &current)
        }
        return 2 * Double(previous[b.count]) / Double(a.count + b.count)
    }

    /// Words, runs of whitespace and single punctuation marks, so a fixed
    /// accent or comma changes one token, not the sentence.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWord: Bool?
        for character in text {
            let isWord = character.isLetter || character.isNumber || character == "'" || character == "’"
            let isSpace = character.isWhitespace
            if isWord || isSpace {
                let kind = isWord
                if currentIsWord == kind {
                    current.append(character)
                } else {
                    if !current.isEmpty { tokens.append(current) }
                    current = String(character)
                    currentIsWord = kind
                }
            } else {
                if !current.isEmpty { tokens.append(current) }
                tokens.append(String(character))
                current = ""
                currentIsWord = nil
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
