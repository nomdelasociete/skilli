import Foundation

/// A skillie: one of skil.li's own commands, a script whose first comments
/// say `@skilli.title`, `@skilli.mode` and the rest (Raycast's Script
/// Command metadata, under skil.li's name). Any language with a shebang;
/// `#` or `//` comments. Raycast's own scripts become skillies through
/// `converted(fromRaycast:)`; agents write new ones with `make`.
public struct ScriptCommand: Hashable, Sendable {
    /// What the run shows: nothing but a short line, the last line, the
    /// whole output, or the last line in the list itself.
    public enum Mode: String, Sendable {
        case silent, compact, fullOutput, inline
    }

    public struct Argument: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case text, password, dropdown
        }

        public let kind: Kind
        public let placeholder: String
        public let optional: Bool
        public let percentEncoded: Bool
        /// For a dropdown: what it shows, what the script gets.
        public let choices: [(title: String, value: String)]

        public static func == (lhs: Argument, rhs: Argument) -> Bool {
            lhs.kind == rhs.kind && lhs.placeholder == rhs.placeholder && lhs.optional == rhs.optional
                && lhs.percentEncoded == rhs.percentEncoded && lhs.choices.map(\.value) == rhs.choices.map(\.value)
        }
    }

    public let path: String
    public let title: String
    public let mode: Mode
    public let packageName: String
    public let icon: String
    public let description: String
    public let arguments: [Argument]
    public let needsConfirmation: Bool
    /// For inline: how often the line is refreshed, in seconds.
    public let refreshSeconds: Int?
    /// Where it runs; nil for the script's own folder.
    public let directory: String?

    /// Stable id: its path.
    public var id: String { path }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    /// The metadata of a script's text; nil when it is not a Script
    /// Command (no title, no mode, or an unknown schema).
    public static func parse(_ text: String, path: String) -> ScriptCommand? {
        var values: [String: String] = [:]
        var arguments: [Int: Argument] = [:]
        // Only the header: the metadata comes before the code.
        for line in text.split(whereSeparator: \.isNewline).prefix(60) {
            var body = line.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("#") { body.removeFirst() } else if body.hasPrefix("//") { body.removeFirst(2) } else { continue }
            body = body.trimmingCharacters(in: .whitespaces)
            let rest: Substring
            if body.hasPrefix("@skilli.") { rest = body.dropFirst(8) } else if body.hasPrefix("@raycast.") { rest = body.dropFirst(9) } else { continue }
            guard let space = rest.firstIndex(where: \.isWhitespace) else { continue }
            let key = String(rest[..<space])
            let value = rest[space...].trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("argument"), let index = Int(key.dropFirst(8)), let argument = parseArgument(value) {
                arguments[index] = argument
            } else {
                values[key] = value
            }
        }
        guard let title = values["title"], !title.isEmpty, let mode = values["mode"].flatMap(Mode.init(rawValue:)),
              (values["schemaVersion"] ?? "1") == "1" else { return nil }
        return ScriptCommand(
            path: path, title: title, mode: mode, packageName: values["packageName"] ?? "", icon: values["icon"] ?? "",
            description: values["description"] ?? "",
            // Raycast takes three at most, in order.
            arguments: (1...3).compactMap { arguments[$0] },
            needsConfirmation: values["needsConfirmation"] == "true",
            refreshSeconds: values["refreshTime"].flatMap(seconds),
            directory: values["currentDirectoryPath"]
        )
    }

    /// A Raycast Script Command's text as a skillie: its `@raycast.` keys
    /// renamed `@skilli.` in the header comments, the code untouched. Nil
    /// when it is not a Script Command.
    public static func converted(fromRaycast text: String) -> String? {
        guard parse(text, path: "") != nil else { return nil }
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices.prefix(60) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") || trimmed.hasPrefix("//") else { continue }
            lines[index] = lines[index].replacingOccurrences(of: "@raycast.", with: "@skilli.")
        }
        return lines.joined(separator: "\n")
    }

    /// Languages a new skillie can be written in: shebang, comment, extension.
    public enum Language: String, CaseIterable, Sendable {
        case bash, zsh, python, node, swift, ruby

        var shebang: String {
            switch self {
            case .bash: "#!/bin/bash"
            case .zsh: "#!/bin/zsh"
            case .python: "#!/usr/bin/env python3"
            case .node: "#!/usr/bin/env node"
            case .swift: "#!/usr/bin/swift"
            case .ruby: "#!/usr/bin/env ruby"
            }
        }

        var comment: String { self == .node || self == .swift ? "//" : "#" }

        var fileExtension: String {
            switch self {
            case .bash, .zsh: "sh"
            case .python: "py"
            case .node: "js"
            case .swift: "swift"
            case .ruby: "rb"
            }
        }
    }

    /// A new skillie's file name and text: its header, then the code.
    /// Arguments are text ones, in order.
    public static func make(title: String, description: String, mode: Mode, language: Language, code: String,
                            arguments: [(placeholder: String, optional: Bool)] = [], icon: String = "",
                            needsConfirmation: Bool = false) -> (fileName: String, text: String) {
        let c = language.comment
        var header = [language.shebang, "", "\(c) @skilli.schemaVersion 1", "\(c) @skilli.title \(oneLine(title))", "\(c) @skilli.mode \(mode.rawValue)"]
        if !icon.isEmpty { header.append("\(c) @skilli.icon \(oneLine(icon))") }
        if !description.isEmpty { header.append("\(c) @skilli.description \(oneLine(description))") }
        for (index, argument) in arguments.prefix(3).enumerated() {
            let object: [String: Any] = ["type": "text", "placeholder": oneLine(argument.placeholder), "optional": argument.optional]
            let json = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            header.append("\(c) @skilli.argument\(index + 1) \(json)")
        }
        if needsConfirmation { header.append("\(c) @skilli.needsConfirmation true") }
        let slug = title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
        let body = code.hasPrefix("#!") ? code.split(separator: "\n", maxSplits: 1).dropFirst().joined() : code
        return ("\(slug.isEmpty ? "skillie" : String(slug.prefix(60))).\(language.fileExtension)",
                header.joined(separator: "\n") + "\n\n" + body.trimmingCharacters(in: .newlines) + "\n")
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// `{ "type": "text", "placeholder": "Name", "optional": true }`.
    static func parseArgument(_ json: String) -> Argument? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let kind = (object["type"] as? String).flatMap(Argument.Kind.init(rawValue:)) else { return nil }
        let choices = (object["data"] as? [[String: Any]] ?? []).compactMap { item -> (String, String)? in
            guard let title = item["title"] as? String else { return nil }
            return (title, item["value"] as? String ?? title)
        }
        if kind == .dropdown, choices.isEmpty { return nil }
        return Argument(kind: kind, placeholder: object["placeholder"] as? String ?? (kind == .dropdown ? "Choose" : "Argument"),
                        optional: object["optional"] as? Bool ?? false, percentEncoded: object["percentEncoded"] as? Bool ?? false,
                        choices: choices)
    }

    /// "10s", "1m", "12h", "1d" → seconds; Raycast refreshes at most every 10 s.
    static func seconds(_ text: String) -> Int? {
        let units: [Character: Int] = ["s": 1, "m": 60, "h": 3_600, "d": 86_400]
        guard let unit = text.last.flatMap({ units[$0] }), let number = Int(text.dropLast()), number > 0 else { return nil }
        return max(10, number * unit)
    }

    /// What the script gets for each argument: optional ones left empty
    /// stay empty, percent-encoded ones are encoded.
    public func values(for typed: [String]) -> [String] {
        arguments.enumerated().map { index, argument in
            let value = index < typed.count ? typed[index] : ""
            return argument.percentEncoded ? (value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value) : value
        }
    }

    /// The line a run leaves for compact, silent and inline: the last line
    /// that says something.
    public static func lastLine(_ output: String) -> String {
        output.split(whereSeparator: \.isNewline).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Terminal colors (ANSI escapes) taken out: the card shows text.
    public static func plain(_ output: String) -> String {
        output.replacingOccurrences(of: #"\u001B\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
    }
}
