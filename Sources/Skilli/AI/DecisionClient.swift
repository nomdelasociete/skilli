import Foundation
import SkilliCore

/// Fast typed judgments for commands that decide (docs/si-commands.md):
/// OpenAI's Decisions API or TypeSafe's Jev, both with the user's key.
enum DecisionProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case typeSafe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI Decisions"
        case .typeSafe: "TypeSafe Jev"
        }
    }

    var keyPrompt: String {
        switch self {
        case .openAI: "Paste an OpenAI key: sk-…"
        case .typeSafe: "Paste a TypeSafe key"
        }
    }

    var console: String {
        switch self {
        case .openAI: "platform.openai.com"
        case .typeSafe: "typesafe.ai"
        }
    }

    /// skil.li's Keychain item for this key (prefixed in the self-test).
    var keychainAccount: String {
        switch self {
        case .openAI: "openai-api-key"
        case .typeSafe: "typesafe-api-key"
        }
    }
}

/// Pick one option for an input.
struct DecisionQuestion: Sendable {
    struct Option: Sendable {
        let value: String
        let description: String
    }

    let name: String
    let instructions: String
    let options: [Option]

    /// What Settings' Test buttons ask.
    static let sample = DecisionQuestion(
        name: "action",
        instructions: "Which action fits this request?",
        options: [
            Option(value: "reminder", description: "Create a reminder or a calendar event"),
            Option(value: "translate", description: "Translate text"),
            Option(value: "reply", description: "Write a reply to a message"),
            Option(value: "other", description: "Anything else")
        ]
    )
    static let sampleInput = "Remind me tomorrow at 9 to call the bank"
}

struct DecisionResult: Equatable, Sendable {
    let choice: String
    let confidence: Double
    let probabilities: [String: Double]
}

enum DecisionClient {
    static func decide(_ question: DecisionQuestion, input: String, provider: DecisionProvider, key: String) async throws -> DecisionResult {
        let answers = try await decide([question], input: input, provider: provider, key: key)
        guard let answer = answers[question.name] else {
            throw AIError.failed("\(provider.title): no answer for “\(question.name)”")
        }
        return answer
    }

    /// Several questions in one request: they are answered in parallel, so
    /// more questions barely change the time. Declined or missing answers
    /// are left out. `timeout`: shorter where someone waits on it (a tool
    /// call held for the user's rules).
    static func decide(_ questions: [DecisionQuestion], input: String, provider: DecisionProvider, key: String,
                       timeout: TimeInterval = 15) async throws -> [String: DecisionResult] {
        try await reply(questions, input: input, provider: provider, key: key, timeout: timeout).answers
    }

    /// The answers and the input tokens they cost. With `picture` (Jev
    /// only: OpenAI never gets an image), the state is `{step: input,
    /// window_picture: <reference>}` and the picture goes as TypeSafe's
    /// image asset (`TypeSafe-Danger-Zone-Images`).
    static func reply(_ questions: [DecisionQuestion], input: String, picture: JevImages.Image? = nil, provider: DecisionProvider,
                      key: String, timeout: TimeInterval = 15) async throws -> (answers: [String: DecisionResult], inputTokens: Int) {
        var request: URLRequest
        var body: [String: Any]
        switch provider {
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/decisions")!)
            body = [
                "model": "gpt-6-luna",
                "input": input,
                "questions": questions.map { question in
                    [
                        "type": "choice",
                        "name": question.name,
                        "instructions": question.instructions,
                        "choices": question.options.map { ["value": $0.value, "description": $0.description] }
                    ] as [String: Any]
                }
            ]
        case .typeSafe:
            request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
            body = [
                "model": "jev-latest",
                "state": picture.map { ["step": input, "window_picture": $0.reference] as [String: Any] } ?? input,
                "questions": Dictionary(uniqueKeysWithValues: questions.map { question in
                    (question.name, [
                        "type": "choice",
                        "instructions": question.instructions,
                        "criteria": Dictionary(question.options.map { ($0.value, $0.description) }, uniquingKeysWith: { first, _ in first })
                    ] as [String: Any])
                })
            ]
            if let picture {
                body["assets"] = [picture.reference: WindowPicture.asset(picture.data, format: picture.format)]
                request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
            }
        }
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200, let json else {
            throw AIError.failed("\(provider.title): \(errorMessage(json) ?? "request failed") (\(status))")
        }
        var results: [String: DecisionResult] = [:]
        for question in questions {
            guard let answer = Self.answer(in: json, for: question.name, provider: provider),
                  answer["type"] as? String != "refusal",
                  let choice = answer["choice"] as? String
            else { continue }
            results[question.name] = DecisionResult(
                choice: choice,
                confidence: answer["confidence"] as? Double ?? 0,
                probabilities: probabilities(answer["probabilities"])
            )
        }
        if results.isEmpty, !questions.isEmpty {
            throw AIError.failed("\(provider.title) declined to answer.")
        }
        let usage = json["usage"] as? [String: Any]
        return (results, usage?["input_tokens"] as? Int ?? 0)
    }

    /// OpenAI lists answers with their `name`; TypeSafe keys them by name.
    private static func answer(in json: [String: Any], for name: String, provider: DecisionProvider) -> [String: Any]? {
        switch provider {
        case .openAI:
            (json["answers"] as? [[String: Any]])?.first { $0["name"] as? String == name }
        case .typeSafe:
            (json["answers"] as? [String: Any])?[name] as? [String: Any]
        }
    }

    /// `[{value, probability}]` (OpenAI) or `{value: probability}` (TypeSafe).
    private static func probabilities(_ value: Any?) -> [String: Double] {
        if let list = value as? [[String: Any]] {
            return list.reduce(into: [:]) { result, item in
                if let key = item["value"] as? String, let probability = item["probability"] as? Double { result[key] = probability }
            }
        }
        return (value as? [String: Double]) ?? [:]
    }

    private static func errorMessage(_ json: [String: Any]?) -> String? {
        if let error = json?["error"] as? [String: Any] { return error["message"] as? String }
        if let error = json?["error"] as? String { return error }
        if let detail = json?["detail"] as? String { return detail }
        if let message = json?["message"] as? String { return message }
        return nil
    }
}
