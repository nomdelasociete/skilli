import Foundation

/// What a copied text is, read from the whole copy (the clipboard
/// history's preview picks its view by it): one link, one color, one email
/// address, one phone number, one postal address, code, or text. Each is a
/// parse of the text that IS that value (a color's grammar, Apple's data
/// detectors covering all of it), never something found inside a sentence.
public enum CopiedValue: Equatable, Sendable {
    case text
    case link(URL)
    case color(CopiedColor)
    case email(String)
    case phone(String)
    case address(PostalAddress)
    /// Code, in a language when a cheap rule can tell (`CodeLanguage`).
    case code(String?)

    /// A postal address as copied: its own lines, and what Apple's
    /// detector read in it.
    public struct PostalAddress: Equatable, Sendable {
        public let lines: [String]
        public let city: String?
        public let country: String?
    }

    /// Longest copy read as a value; longer is text or code.
    static let valueLimit = 300
    /// What code detection reads of a long copy.
    static let codeLimit = 4_000

    public static func read(_ text: String) -> CopiedValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        let short = trimmed.utf8.count <= valueLimit
        if short {
            if let color = CopiedColor.parse(trimmed) { return .color(color) }
            if let url = LinkPreviews.link(in: trimmed) { return .link(url) }
            if let email = email(trimmed) { return .email(email) }
            if let phone = phone(trimmed) { return .phone(phone) }
            if let address = address(trimmed) { return .address(address) }
        }
        let head = trimmed.utf8.count > codeLimit ? String(trimmed.prefix(codeLimit)) : trimmed
        if let language = CodeLanguage.guess(head) {
            return .code(language.isEmpty ? nil : language)
        }
        return .text
    }

    /// Apple's detectors are slow the first time each is used: used once
    /// off the main thread (at launch), a copy shown later reads at once.
    public static func warmUp() {
        for text in ["camille@example.com", "+33 6 12 34 56 78", "1 Infinite Loop, Cupertino, CA 95014", "let a = 1;\nlet b = 2;"] {
            _ = read(text)
        }
    }

    // MARK: - Detectors

    // One detector a kind (a detector of several is slower on every
    // text); NSDataDetector is immutable and safe to share between threads.
    private static let detectors: [UInt64: NSDataDetector] = Dictionary(uniqueKeysWithValues: [
        NSTextCheckingResult.CheckingType.link, .phoneNumber, .address
    ].compactMap { type in (try? NSDataDetector(types: type.rawValue)).map { (type.rawValue, $0) } })

    /// The one match of `type` that covers the whole text.
    private static func whole(_ text: String, _ type: NSTextCheckingResult.CheckingType) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = detectors[type.rawValue]?.matches(in: text, range: range) ?? []
        guard matches.count == 1, let match = matches.first, match.resultType == type else { return nil }
        // Punctuation around it does not make it something else.
        let rest = (text as NSString).replacingCharacters(in: match.range, with: "")
        return rest.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty ? match : nil
    }

    /// "camille@example.com", "mailto:camille@example.com".
    private static func email(_ text: String) -> String? {
        guard text.utf8.count <= 260, text.contains("@"), !text.contains(where: \.isWhitespace) else { return nil }
        guard let match = whole(text, .link), let url = match.url, url.scheme == "mailto" else { return nil }
        let address = String(url.absoluteString.dropFirst("mailto:".count)).removingPercentEncoding ?? ""
        return address.contains("@") ? address : nil
    }

    /// "+33 6 12 34 56 78", "(415) 555-0132": digits and the signs numbers
    /// are written with, 7 to 15 digits, all of it one number.
    private static func phone(_ text: String) -> String? {
        let allowed = CharacterSet(charactersIn: "0123456789+-.() /\u{00A0}")
        guard text.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let digits = text.filter(\.isNumber).count
        guard (7...15).contains(digits), whole(text, .phoneNumber) != nil else { return nil }
        return text
    }

    /// "1 Infinite Loop, Cupertino, CA 95014": Apple's detector reads all
    /// of it as one address. Only a text shaped like one is given to it
    /// (a number, letters, its parts split by commas or lines).
    private static func address(_ text: String) -> PostalAddress? {
        guard text.utf8.count <= 200, text.contains(where: \.isNumber), text.contains(where: \.isLetter),
              text.contains(",") || text.contains(where: \.isNewline),
              !text.contains("?"), !text.contains("!"),
              text.split(whereSeparator: \.isNewline).count <= 6 else { return nil }
        guard let match = whole(text, .address) else { return nil }
        let components = match.addressComponents ?? [:]
        var lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count == 1 {
            // One line: its parts, as an envelope shows them.
            lines = lines[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return PostalAddress(lines: lines, city: components[.city], country: components[.country])
    }
}

/// Which language a copied piece of code is in, by a few cheap rules on
/// its lines (code is typed grammar, not a sentence): JSON when it parses,
/// else the language with the most signs. "" is code in no language told
/// apart; nil is not code.
public enum CodeLanguage {
    public static func guess(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }
        if let first = trimmed.first, first == "{" || first == "[",
           trimmed.utf8.count <= 200_000,
           (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])) != nil,
           trimmed.contains(":") || first == "[" {
            return "JSON"
        }
        // Prose has none of code's marks: no rule read at all.
        guard looksMarked(trimmed) else { return nil }
        // The first lines say it; each line's start is enough.
        let lines = trimmed.split(whereSeparator: \.isNewline).prefix(40).map { line in
            String(line.trimmingCharacters(in: .whitespaces).prefix(160))
        }
        var scores: [String: Int] = [:]
        for (language, signs) in signs {
            var score = 0
            for line in lines {
                for sign in signs where sign.matches(line) { score += sign.weight }
            }
            if score > 0 { scores[language] = score }
        }
        if trimmed.hasPrefix("<"), trimmed.contains("</") || trimmed.contains("/>") {
            let lower = trimmed.prefix(400).lowercased()
            let html = ["<!doctype html", "<html", "<div", "<span", "<p>", "<a ", "<body", "<head", "<script", "<ul", "<li", "<img", "<section"]
            scores[html.contains(where: lower.contains) ? "HTML" : "XML", default: 0] += 6
        }
        if let best = scores.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }), best.value >= 4 {
            // TypeScript is JavaScript with types.
            if best.key == "JavaScript", (scores["TypeScript"] ?? 0) >= 3 { return "TypeScript" }
            return best.key
        }
        // Lines shaped like code, in no language told apart.
        let shaped = lines.filter { line in
            line.hasSuffix(";") || line.hasSuffix("{") || line == "}" || line.hasSuffix("};") || line.hasPrefix("//")
        }.count
        return lines.count >= 2 && shaped * 2 >= lines.count ? "" : nil
    }

    /// Marks of code (braces, semicolons, "=", "<…>", a shebang, "def ",
    /// "SELECT"): two or more of them, or a keyword a line starts with.
    static func looksMarked(_ text: String) -> Bool {
        var marks = 0
        for byte in text.utf8.prefix(4_000) {
            switch byte {
            case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: ";"), UInt8(ascii: "="), UInt8(ascii: "<"), UInt8(ascii: ">"),
                 UInt8(ascii: "$"), UInt8(ascii: "#"), UInt8(ascii: "["), UInt8(ascii: "_"):
                marks += 1
                if marks >= 2 { return true }
            default:
                continue
            }
        }
        let starts = ["def ", "import ", "from ", "class ", "SELECT ", "INSERT ", "UPDATE ", "DELETE ", "CREATE ", "package ", "fn ",
                      "func ", "sudo ", "brew ", "git ", "npm ", "cd ", "print(", "console."]
        return text.split(whereSeparator: \.isNewline).prefix(40).contains { line in
            let start = line.drop { $0 == " " || $0 == "\t" }
            return starts.contains { start.hasPrefix($0) }
        }
    }

    /// One sign of a language: a line starting with it, or holding it.
    struct Sign {
        let pattern: NSRegularExpression
        let weight: Int

        func matches(_ line: String) -> Bool {
            pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }

    private static func sign(_ pattern: String, _ weight: Int = 2) -> Sign {
        // Patterns are constants: a typo fails the unit tests at once.
        Sign(pattern: try! NSRegularExpression(pattern: pattern), weight: weight)
    }

    // Built once; NSRegularExpression is immutable and Sendable.
    static let signs: [String: [Sign]] = [
        "Swift": [
            sign(#"^(public |private |fileprivate |internal |open )?(final )?(func|struct|enum|protocol|extension|actor) [A-Za-z_]"#, 3),
            sign(#"^(let|var) [a-z_][A-Za-z0-9_]*(: [A-Z][A-Za-z<>\[\]?]*)? = "#),
            sign(#"^guard .+ else \{"#, 3),
            sign(#"^import (Foundation|SwiftUI|AppKit|UIKit|Combine|SkilliCore)$"#, 4),
            sign(#"^@(MainActor|Observable|State|Binding|available|objc)\b"#, 3),
            sign(#"\bif let [a-z]"#, 2)
        ],
        "Python": [
            sign(#"^def [a-z_][A-Za-z0-9_]*\(.*\):$"#, 4),
            sign(#"^class [A-Z][A-Za-z0-9_]*(\(.*\))?:$"#, 3),
            sign(#"^(from [a-z_.]+ )?import [a-z_][a-z0-9_.]*( as [a-z_]+)?$"#),
            sign(#"^(elif|except|finally|with) .*:$|^else:$|^try:$"#, 3),
            sign(#"\bself\.[a-z_]"#, 1),
            sign(#"^print\("#, 2)
        ],
        "JavaScript": [
            sign(#"^(export )?(const|let|var) [A-Za-z_$][A-Za-z0-9_$]* = "#, 2),
            sign(#"^(export )?(async )?function [A-Za-z_$]"#, 3),
            sign(#"=> \{?"#, 2),
            sign(#"\bconsole\.(log|error|warn)\("#, 3),
            sign(#"^import .+ from ['"]"#, 3),
            sign(#"\brequire\(['"]"#, 3)
        ],
        "TypeScript": [
            sign(#"^(export )?(interface|type) [A-Z][A-Za-z0-9_]* "#, 3),
            sign(#": (string|number|boolean|void)\b"#, 2)
        ],
        "Shell": [
            sign(#"^#!/(usr/)?bin/(env )?(ba|z)?sh"#, 6),
            sign(#"^\$ [a-z]"#, 3),
            sign(#"^(sudo |brew |git |npm |npx |yarn |cd |ls |mkdir |rm |cp |mv |curl |ssh |export [A-Z_]+=|echo )"#, 2),
            sign(#"^(if|for|while) .*; (then|do)$|^fi$|^done$"#, 3)
        ],
        "SQL": [
            // In capitals, as SQL is written; in lowercase, only a whole statement.
            sign(#"^(SELECT .+ FROM|INSERT INTO|UPDATE [A-Za-z_]+ SET|DELETE FROM|CREATE (TABLE|INDEX|VIEW)|ALTER TABLE)\b"#, 5),
            sign(#"(?i)^(select .+ from [a-z_.]+|insert into|delete from|create table)\b.*;$"#, 4),
            sign(#"(?i)^(where|group by|order by|left join|inner join|join) "#, 2)
        ],
        "CSS": [
            sign(#"^[.#]?[A-Za-z][A-Za-z0-9_\-.:# >]*\{$"#, 2),
            sign(#"^[a-z\-]+: [^;]+;$"#, 2)
        ],
        "Go": [
            sign(#"^package [a-z]+$"#, 5),
            sign(#"^func (\([a-z]+ \*?[A-Z][A-Za-z]*\) )?[A-Za-z]+\("#, 4),
            sign(#"[a-z] := "#, 2)
        ],
        "Rust": [
            sign(#"^(pub )?fn [a-z_]+(<.*>)?\("#, 4),
            sign(#"^let mut "#, 3),
            sign(#"^(impl|use std::|mod |#\[derive)"#, 4)
        ],
        "C": [
            sign(#"^#include [<"]"#, 5),
            sign(#"^int main\("#, 4)
        ],
        "Java": [
            sign(#"^(public |private |protected )(static )?(final )?(class|void|interface) "#, 4),
            sign(#"\bSystem\.out\.print"#, 4)
        ]
    ]
}
