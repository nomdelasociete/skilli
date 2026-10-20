import Foundation
import SkilliCore

/// OpenAI's models through the Responses API, with the OpenAI key skil.li
/// keeps for Decisions (Keychain). Raw HTTP with server-sent events, like
/// `ClaudeAPIEngine`; nothing stored at OpenAI (`store: false`).
@MainActor
final class OpenAIEngine: TextEngine {
    /// When a request names no OpenAI model.
    var model = ModelChoice(provider: .openAI, model: "gpt-6-luna", effort: .low)
    /// Read on each request, so a key saved in Settings applies at once.
    private let key: @MainActor () -> String?
    /// One session for the app's lifetime: its connection stays warm.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()

    init(key: @escaping @MainActor () -> String?) {
        self.key = key
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        guard let key = key() else { return .failing(AIError.failed("No OpenAI key saved: add one in Settings → SI Accounts.")) }
        let choice = request.model?.provider == .openAI ? request.model ?? model : model
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": choice.model,
            "instructions": AIPrompt.system,
            "input": request.message,
            "stream": true,
            "store": false
        ]
        if let effort = choice.effort { body["reasoning"] = ["effort": effort.rawValue] }
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let session = session
        let finalRequest = urlRequest

        return AsyncThrowingStream { continuation in
            let task = Task.detached { [session, finalRequest] in
                do {
                    let (bytes, response) = try await session.bytes(for: finalRequest)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var text = ""
                        for try await line in bytes.lines { text += line }
                        throw AIError.failed(WritingFailure.openAI(status: status, body: text))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:"),
                              let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                        else { continue }
                        switch event["type"] as? String {
                        case "response.output_text.delta":
                            if let text = event["delta"] as? String { continuation.yield(text) }
                        case "response.completed":
                            continuation.finish()
                            return
                        case "response.incomplete":
                            // Cut at max_output_tokens: what came is kept.
                            continuation.finish()
                            return
                        case "response.failed":
                            let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
                            throw AIError.failed("OpenAI failed: " + (error?["message"] as? String ?? "no reason given."))
                        case "error":
                            throw AIError.failed("OpenAI failed: " + (event["message"] as? String ?? "no reason given."))
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: AIError.failed("OpenAI did not answer in time."))
                } catch let error as URLError where error.code != .cancelled {
                    continuation.finish(throwing: AIError.failed("OpenAI could not be reached: check the connection, then try again."))
                } catch {
                    continuation.finish(throwing: AIError.failed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The text models this key may use (`GET /v1/models`); nil when the
    /// API cannot say.
    nonisolated static func models(key: String) async -> [ModelOffer]? {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        // Nothing kept on disk: the request carries the key.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let offers = ModelCatalog.openAIModels(data), !offers.isEmpty
        else { return nil }
        return offers
    }
}
