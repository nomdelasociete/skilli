import Foundation

/// An AI command written as a Markdown file the user can edit:
///
///     ---
///     title: Reply to This Email
///     profile: true
///     model: chatgpt/gpt-6-luna
///     effort: low
///     output: replace
///     ask:
///       - id: tone
///         question: Which tone?
///         options: [Friendly, Formal, Short]
///         default: Friendly
///     tools: [selection, apps, mcp:linear]
///     ---
///     Answer this email in a {ask.tone} tone, as me.
///
///     {selection}
///
/// The front matter is optional; the body is the prompt, with
/// `{variables}` (see `PromptTemplate`).
public struct PromptFile: Equatable, Sendable {
    public var title: String?
    public var instruction: String
    /// Adds About You to the prompt.
    public var includeProfile: Bool
    /// "haiku", "chatgpt/gpt-6-luna" (`ModelChoice`); nil uses the
    /// default model. Kept as written, even when this build does not know it.
    public var model: String?
    /// "low", "medium", "high" for OpenAI's models.
    public var effort: String?
    /// nil: replace (or insert at the cursor with nothing selected).
    public var output: OutputMode?
    /// Asked in the card before the prompt is sent.
    public var questions: [PromptQuestion]
    /// Tool groups the command may use (`ToolGroup` names, `mcp:<server>`);
    /// any makes it an Act command, run by an agent.
    public var tools: [String]

    public init(
        title: String?,
        instruction: String,
        includeProfile: Bool = false,
        model: String? = nil,
        effort: String? = nil,
        output: OutputMode? = nil,
        questions: [PromptQuestion] = [],
        tools: [String] = []
    ) {
        self.title = title
        self.instruction = instruction
        self.includeProfile = includeProfile
        self.model = model
        self.effort = effort
        self.output = output
        self.questions = questions
        self.tools = tools
    }

    public init(parsing text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var title: String?
        var includeProfile = false
        var model: String?
        var effort: String?
        var output: OutputMode?
        var questions: [PromptQuestion] = []
        var tools: [String] = []
        var body = Substring(normalized)
        if normalized.hasPrefix("---\n"),
           let end = normalized.range(of: "\n---", range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex) {
            let header = normalized[normalized.index(normalized.startIndex, offsetBy: 4)..<end.lowerBound]
            let lines = header.split(separator: "\n", omittingEmptySubsequences: false)
            var index = 0
            while index < lines.count {
                let line = lines[index]
                index += 1
                guard let (key, value) = Self.keyValue(line) else { continue }
                let unquoted = Self.unquoted(value)
                switch key {
                case "title" where !unquoted.isEmpty: title = unquoted
                case "profile": includeProfile = ["true", "yes", "on"].contains(unquoted.lowercased())
                case "model" where !unquoted.isEmpty && unquoted.lowercased() != "default": model = unquoted.lowercased()
                case "effort" where !unquoted.isEmpty: effort = unquoted.lowercased()
                case "output": output = OutputMode(rawValue: unquoted.lowercased())
                case "tools":
                    for tool in Self.list(value).map({ $0.lowercased() }) where !tool.isEmpty && !tools.contains(tool) {
                        tools.append(tool)
                    }
                case "ask":
                    // The indented list that follows.
                    var block: [Substring] = []
                    while index < lines.count, let first = lines[index].first, first == " " || first == "\t" || first == "-" {
                        block.append(lines[index])
                        index += 1
                    }
                    questions = Self.questions(block)
                default: break
                }
            }
            body = normalized[end.upperBound...]
            // Rest of the closing `---` line.
            if let newline = body.firstIndex(of: "\n") {
                body = body[body.index(after: newline)...]
            } else {
                body = ""
            }
        }
        self.title = title
        self.includeProfile = includeProfile
        self.model = model
        self.effort = model == nil ? nil : effort
        self.output = output
        self.questions = questions
        self.tools = tools
        instruction = body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var text: String {
        var header: [String] = []
        if let title { header.append("title: \(title)") }
        if includeProfile { header.append("profile: true") }
        if let model {
            header.append("model: \(model)")
            if let effort { header.append("effort: \(effort)") }
        }
        if let output { header.append("output: \(output.rawValue)") }
        if !questions.isEmpty {
            header.append("ask:")
            for question in questions {
                header.append("  - id: \(question.id)")
                header.append("    question: \(question.question)")
                if !question.options.isEmpty {
                    header.append("    options: [\(question.options.map(Self.listItem).joined(separator: ", "))]")
                }
                if let value = question.defaultValue, !value.isEmpty {
                    header.append("    default: \(value)")
                }
            }
        }
        if !tools.isEmpty { header.append("tools: [\(tools.map(Self.listItem).joined(separator: ", "))]") }
        let frontMatter = header.isEmpty ? "" : "---\n" + header.joined(separator: "\n") + "\n---\n"
        return frontMatter + instruction + "\n"
    }

    // MARK: - Front matter

    private static func keyValue(_ line: Substring) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// `- id: …` items with `question`, `options` and `default` under them.
    private static func questions(_ lines: [Substring]) -> [PromptQuestion] {
        var items: [[String: String]] = []
        for line in lines {
            var content = line.trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("-") {
                items.append([:])
                content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard !items.isEmpty, let (key, value) = keyValue(Substring(content)) else { continue }
            items[items.count - 1][key] = value
        }
        var questions: [PromptQuestion] = []
        for item in items {
            let text = unquoted(item["question"] ?? "")
            guard !text.isEmpty else { continue }
            var id = PromptQuestion.normalizedID(unquoted(item["id"] ?? ""))
            if id.isEmpty { id = PromptQuestion.normalizedID(text) }
            guard !id.isEmpty, !questions.contains(where: { $0.id == id }) else { continue }
            let options = list(item["options"] ?? "")
            var defaultValue = item["default"].map(unquoted)
            if !options.isEmpty, let value = defaultValue, !options.contains(value) { defaultValue = nil }
            questions.append(PromptQuestion(id: id, question: text, options: options, defaultValue: defaultValue))
        }
        return questions
    }

    /// `[a, "b, c", d]` (brackets optional) → ["a", "b, c", "d"].
    public static func list(_ value: String) -> [String] {
        var text = Substring(value.trimmingCharacters(in: .whitespaces))
        if text.hasPrefix("["), text.hasSuffix("]") { text = text.dropFirst().dropLast() }
        var items: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quote != nil {
                escaped = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'", current.trimmingCharacters(in: .whitespaces).isEmpty {
                quote = character
                current = ""
            } else if character == "," {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current.trimmingCharacters(in: .whitespaces))
        return items.filter { !$0.isEmpty }
    }

    private static func listItem(_ item: String) -> String {
        guard item.contains(where: { ",[]\"'".contains($0) }) || item != item.trimmingCharacters(in: .whitespaces) else { return item }
        return "\"" + item.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Where a command's answer goes.
public enum OutputMode: String, CaseIterable, Sendable {
    /// Return replaces the selection (inserts at the cursor without one).
    case replace
    /// Return inserts the answer after the selection, which stays.
    case insert
    /// Copied to the clipboard as soon as it is written.
    case copy
    /// Shown in the card only; Return copies it.
    case card
}

/// A question asked in the card before the prompt is sent: options as
/// keycaps (1, 2, 3…) or free text. The prompt reads the answer with
/// `{ask.<id>}`.
public struct PromptQuestion: Equatable, Sendable, Identifiable {
    public var id: String
    public var question: String
    /// Empty: the answer is typed.
    public var options: [String]
    /// Pre-selected, so Return runs at once.
    public var defaultValue: String?

    public init(id: String, question: String, options: [String] = [], defaultValue: String? = nil) {
        self.id = id
        self.question = question
        self.options = options
        self.defaultValue = defaultValue
    }

    public var token: String { "{\(PromptTemplate.questionPrefix)\(id)}" }

    /// Lowercase letters, digits and dashes: "Which tone?" → "which-tone".
    public static func normalizedID(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
