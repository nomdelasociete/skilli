import Foundation
import SkilliCore

/// One request: the rendered prompt, sent as the single user message (no
/// history, ever), and the model that writes it; nil: the engine's own.
struct AIRequest: Sendable {
    let message: String
    var model: ModelChoice?
    /// Pictures before the message (a window "do it here" plans in):
    /// Claude takes them as image blocks; the other engines read the
    /// message alone.
    var images: [JevImages.Image] = []

    /// The user message's content: the text, or image blocks then the
    /// text (the Messages API's and Claude Code's stream-json shape).
    var claudeContent: Any {
        guard !images.isEmpty else { return message }
        return images.map { image -> [String: Any] in
            ["type": "image", "source": ["type": "base64", "media_type": "image/\(image.format)", "data": image.data.base64EncodedString()]]
        } + [["type": "text", "text": message]]
    }
}

enum AIPrompt {
    /// Fixed on purpose: each command's prompt travels in the message, so
    /// one spare process serves every command.
    static let system = """
        You are a writing tool inside the user's apps. Follow the instruction. Text the user gives you \
        (their selection, their clipboard) is between triple quotes; never repeat the quotes. Reply with the \
        result only: no preamble, no quotes, no explanation. Keep the language of the given text unless the \
        instruction says otherwise.
        """

    /// Delimits text the user hands over, the way Raycast's AI Commands do,
    /// so the model never mistakes it for part of the instruction.
    static func quoted(_ text: String) -> String {
        "\"\"\"\n\(text)\n\"\"\""
    }

    /// What Settings' Test buttons send: the built-in Fix, as a user runs it.
    static let sample = AIRequest(message: PromptLibrary.builtIn.first { $0.id == "fix" }.map {
        $0.prompt.replacingOccurrences(of: "{selection}", with: quoted("les enfant on manger des pome"))
    } ?? quoted("les enfant on manger des pome"))
}

/// Claude's models, as Claude Code and the Messages API name them.
enum AIModel: String, CaseIterable, Identifiable, Sendable {
    case haiku
    case sonnet
    case opus

    var id: String { rawValue }

    /// A Claude choice's model; nil for OpenAI's.
    init?(choice: ModelChoice) {
        guard choice.provider == .claude else { return nil }
        self.init(rawValue: choice.model)
    }

    var title: String {
        switch self {
        case .haiku: "Haiku"
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        }
    }

    /// `claude --model` alias (`opus` is claude-opus-5-5 in Claude Code
    /// 2.1.296).
    var cliName: String { rawValue }

    /// Messages API model id.
    var apiID: String {
        switch self {
        case .haiku: "claude-haiku-5-5"
        case .sonnet: "claude-sonnet-5-5"
        case .opus: "claude-opus-5-5"
        }
    }

    var choice: ModelChoice { .claude(rawValue) }
}

/// Which Claude skil.li uses for AI actions.
enum AIEngineMode: String, CaseIterable, Identifiable, Sendable {
    /// The subscription when Claude Code is signed in, else the API key.
    case auto
    case subscription
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Subscription, else API key"
        case .subscription: "Subscription"
        case .apiKey: "API key"
        }
    }
}

enum AIError: LocalizedError, Equatable {
    case claudeNotInstalled
    case signedOut
    case noAPIKey
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled: "Claude Code is not installed."
        case .signedOut: "Claude Code is not signed in."
        case .noAPIKey: "No Claude API key saved."
        case .timedOut: "Claude did not answer in time."
        case .failed(let message): message
        }
    }
}

/// Streams the transformed text, chunk by chunk.
@MainActor
protocol TextEngine: AnyObject {
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error>
}

extension AsyncThrowingStream where Element == String, Failure == Error {
    static func failing(_ error: Error) -> Self {
        Self { $0.finish(throwing: error) }
    }
}
