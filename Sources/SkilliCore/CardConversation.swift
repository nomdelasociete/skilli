import Foundation

/// An answer in the card that the user follows up (⇥): what was asked and
/// answered so far, sent again with each new question so the same AI goes
/// on with the context, and handed whole to Claude Code or Codex (⌘↩).
public struct CardConversation: Equatable, Sendable {
    public struct Turn: Equatable, Sendable {
        /// What was sent: the first message (the selection quoted), then
        /// each follow-up as typed.
        public let request: String
        public let answer: String
        /// What an agent did for it ("Read the selection").
        public let steps: [String]

        public init(request: String, answer: String, steps: [String] = []) {
            self.request = request
            self.answer = answer
            self.steps = steps
        }
    }

    public private(set) var turns: [Turn] = []

    public init() {}

    public mutating func add(request: String, answer: String, steps: [String] = []) {
        turns.append(Turn(request: Self.cut(request, 30_000), answer: Self.cut(answer, 15_000), steps: steps))
    }

    /// The message for a follow-up: the conversation so far, then the new
    /// question. The oldest turns go first when it grows too long.
    public func message(followUp: String) -> String {
        var earlier = turns
        while earlier.count > 1, Self.transcript(earlier).count > 80_000 { earlier.removeFirst() }
        return "This continues a conversation the user started in skil.li, their Mac launcher. What was said so far:\n\n"
            + Self.transcript(earlier)
            + "The user now asks:\n\(followUp.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            + "Answer this last message, in its language, with the conversation in mind."
    }

    /// "User: … / You answered: …", turn after turn.
    /// The message for a follow-up on a text the user had changed (fixed,
    /// translated, shortened): the exchange so far, then what they want
    /// different; the answer is the text alone, ready to paste.
    public func message(refining request: String) -> String {
        var earlier = turns
        while earlier.count > 1, Self.transcript(earlier).count > 80_000 { earlier.removeFirst() }
        return "The user had skil.li, their Mac launcher, change a text they selected. What was asked and the text you gave:\n\n"
            + Self.transcript(earlier)
            + "They want it changed again:\n\(request.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            + "Reply with the new text only, ready to paste in place of their selection: no quotes, no comment, nothing before or after it."
    }

    public static func transcript(_ turns: [Turn]) -> String {
        turns.map { turn in
            var text = "User:\n\(turn.request.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            if !turn.steps.isEmpty {
                text += "What you did on their Mac:\n" + turn.steps.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
            }
            return text + "You answered:\n\(turn.answer.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }.joined()
    }

    private static func cut(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "\n[…cut]" : text
    }
}
