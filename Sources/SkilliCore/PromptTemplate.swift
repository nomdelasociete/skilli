import Foundation

/// A command's prompt with `{variables}`: `{selection}`, `{date}`, `{app}`…,
/// answers to its questions (`{ask.tone}`), and modifiers after a bar
/// (`{selection | trim}`).
///
/// Rendering replaces the known tokens and leaves anything else as typed,
/// so a stray brace never breaks a prompt.
public struct PromptTemplate: Equatable, Sendable {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    /// Every variable skil.li fills, in the order Settings offers them.
    public enum Variable: String, CaseIterable, Sendable {
        case selection
        case clipboard
        case date
        case time
        case datetime
        case day
        case app
        case window
        case profile
        case name
        case language

        public var token: String { "{\(rawValue)}" }

        /// One line for Settings' variable menu and completion list.
        public var summary: String {
            switch self {
            case .selection: "Selected text"
            case .clipboard: "Text on the clipboard"
            case .date: "Today's date"
            case .time: "Current time"
            case .datetime: "Date and time"
            case .day: "Day of the week"
            case .app: "App you are working in"
            case .window: "Title of its window"
            case .profile: "About You, from Settings"
            case .name: "Your name"
            case .language: "Your preferred language"
            }
        }
    }

    /// Applied to a value once filled, left to right: `{clipboard | trim | raw}`.
    public enum Modifier: String, CaseIterable, Sendable {
        case trim
        case upper
        case lower
        /// Selection and clipboard without the `"""` around them.
        case raw

        public var summary: String {
            switch self {
            case .trim: "Without spaces and blank lines around"
            case .upper: "In capitals"
            case .lower: "In lowercase"
            case .raw: "Without the quotes around selection and clipboard"
            }
        }
    }

    /// One `{…}` in the prompt.
    public struct Token: Equatable, Sendable {
        public let range: Range<String.Index>
        /// A variable skil.li fills, or nil.
        public let variable: Variable?
        /// `{ask.tone}`: the id of the command's question.
        public let question: String?
        public let modifiers: [Modifier]

        /// Filled when rendering; anything else stays as typed.
        public var isKnown: Bool { variable != nil || question != nil }
    }

    /// Prefix of a question's token: `{ask.tone}`.
    public static let questionPrefix = "ask."

    /// Every `{name}` token, known or not, for highlighting and rendering.
    public func tokens() -> [Token] {
        var found: [Token] = []
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "{") {
            guard let close = text[text.index(after: open)...].firstIndex(where: { $0 == "}" || $0 == "{" || $0.isNewline }),
                  text[close] == "}"
            else {
                index = text.index(after: open)
                continue
            }
            let parts = text[text.index(after: open)..<close]
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let name = parts[0].lowercased()
            if let first = name.first, first.isLetter, name.allSatisfy(Self.isNameCharacter) {
                let modifiers = parts.dropFirst().map { Modifier(rawValue: $0.lowercased()) }
                let valid = !modifiers.contains(nil)
                var variable: Variable?
                var question: String?
                if valid {
                    if name.hasPrefix(Self.questionPrefix) {
                        let id = String(name.dropFirst(Self.questionPrefix.count))
                        question = id.isEmpty || id.contains(".") ? nil : id
                    } else {
                        variable = Variable(rawValue: name)
                    }
                }
                found.append(Token(
                    range: open..<text.index(after: close),
                    variable: variable,
                    question: question,
                    modifiers: valid ? modifiers.compactMap { $0 } : []
                ))
            }
            index = text.index(after: close)
        }
        return found
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
    }

    public func uses(_ variable: Variable) -> Bool {
        tokens().contains { $0.variable == variable }
    }

    /// Ids of the questions the prompt names, in order, once each.
    public func questionIDs() -> [String] {
        var ids: [String] = []
        for case let id? in tokens().map(\.question) where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    /// The prompt with its tokens filled: variables from `values`, questions
    /// from `answers` (missing ones become empty), then each token's
    /// modifiers. Variables in `quoting` go through `quote` unless empty or
    /// marked `raw`. Unknown `{words}` stay as typed.
    public func render(
        _ values: [Variable: String],
        answers: [String: String] = [:],
        quoting: Set<Variable> = [],
        quote: (String) -> String = { $0 }
    ) -> String {
        pieces(values, answers: answers, quoting: quoting, quote: quote).map(\.text).joined()
    }

    /// One part of the rendered prompt: text as written, or a known
    /// token and what fills it.
    public enum Piece: Equatable, Sendable {
        case written(String)
        /// `token` as written (`{date}`), `value` what `render` puts there.
        case filled(token: String, variable: Variable?, value: String)

        public var text: String {
            switch self {
            case .written(let text): text
            case .filled(_, _, let value): value
            }
        }
    }

    /// `render`, piece by piece: what each known token became, between the
    /// text as written (unknown `{words}` included). A snippet's preview
    /// shows what was filled.
    public func pieces(
        _ values: [Variable: String],
        answers: [String: String] = [:],
        quoting: Set<Variable> = [],
        quote: (String) -> String = { $0 }
    ) -> [Piece] {
        var pieces: [Piece] = []
        var written = ""
        var index = text.startIndex
        for token in tokens() {
            written += text[index..<token.range.lowerBound]
            if token.isKnown {
                var value = token.variable.map { values[$0] ?? "" } ?? answers[token.question ?? ""] ?? ""
                for modifier in token.modifiers {
                    switch modifier {
                    case .trim: value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    case .upper: value = value.uppercased()
                    case .lower: value = value.lowercased()
                    case .raw: break
                    }
                }
                if let variable = token.variable, quoting.contains(variable), !value.isEmpty, !token.modifiers.contains(.raw) {
                    value = quote(value)
                }
                if !written.isEmpty { pieces.append(.written(written)) }
                written = ""
                pieces.append(.filled(token: String(text[token.range]), variable: token.variable, value: value))
            } else {
                written += text[token.range]
            }
            index = token.range.upperBound
        }
        written += text[index...]
        if !written.isEmpty { pieces.append(.written(written)) }
        return pieces
    }

    /// Variable names starting with `prefix` (what follows an open `{`), for
    /// completion.
    public static func completions(for prefix: String) -> [Variable] {
        let prefix = prefix.lowercased()
        return Variable.allCases.filter { $0.rawValue.hasPrefix(prefix) }
    }
}
