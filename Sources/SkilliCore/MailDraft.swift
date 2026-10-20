import Foundation

/// A mail the user's AI wrote: "Subject: …" (or "Objet : …") on its first
/// line, then the body.
public struct MailDraft: Equatable, Sendable {
    public let subject: String
    public let body: String

    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    /// "Subject: …", "Objet : …", "Sujet : …", "**Objet :** …", with the no-break space
    /// French typography puts before the colon.
    public static func parse(_ text: String) -> MailDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: "\n")
        guard let first = lines.first else { return MailDraft(subject: "", body: "") }
        let plain = first.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "*#").union(.whitespaces))
        guard let marker = plain.range(of: #"^(subject|objet|sujet)\s*:"#, options: [.regularExpression, .caseInsensitive]) else {
            return MailDraft(subject: "", body: trimmed)
        }
        let subject = String(plain[marker.upperBound...]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "*")))
        lines.removeFirst()
        return MailDraft(subject: subject, body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
