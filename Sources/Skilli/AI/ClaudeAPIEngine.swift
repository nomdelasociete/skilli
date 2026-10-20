import Foundation

/// Claude through the Messages API with the user's own key (Keychain).
/// Swift has no official Anthropic SDK: raw HTTP with server-sent events.
@MainActor
final class ClaudeAPIEngine: TextEngine {
    var model: AIModel = .haiku
    /// Read on each request, so a key saved in Settings applies at once.
    private let key: @MainActor () -> String?
    /// One session for the app's lifetime: its connection stays warm.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    init(key: @escaping @MainActor () -> String?) {
        self.key = key
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        guard let key = key() else { return .failing(AIError.noAPIKey) }
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        let model = request.model.flatMap(AIModel.init(choice:)) ?? self.model
        var body: [String: Any] = [
            "model": model.apiID,
            "max_tokens": 4096,
            "stream": true,
            "system": AIPrompt.system,
            "messages": [["role": "user", "content": request.claudeContent]],
            // Transforms need little thought; low effort answers sooner.
            "output_config": ["effort": "low"]
        ]
        // Sonnet's and Opus's safety classifiers may decline a request:
        // Anthropic then answers with the model it recommends, on the same
        // stream. Haiku has no fallback.
        if model != .haiku {
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
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
                        throw AIError.failed(Self.errorMessage(text, status: status))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:"),
                              let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                        else { continue }
                        switch event["type"] as? String {
                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any],
                               delta["type"] as? String == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_delta":
                            let delta = event["delta"] as? [String: Any]
                            if delta?["stop_reason"] as? String == "refusal" {
                                throw AIError.failed("Claude declined to write this.")
                            }
                        case "message_stop":
                            continuation.finish()
                            return
                        case "error":
                            let error = event["error"] as? [String: Any]
                            throw AIError.failed(error?["message"] as? String ?? "The Claude API failed.")
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIError.failed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// "invalid x-api-key (401)" from the API's JSON error body.
    nonisolated private static func errorMessage(_ body: String, status: Int) -> String {
        let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        let message = (json?["error"] as? [String: Any])?["message"] as? String
        return "\(message ?? "The Claude API failed") (\(status))"
    }
}

/// skil.li's own Keychain items (generic passwords). Other apps' items are
/// never read.
enum Keychain {
    private static let service = "com.nomdelasociete.Skilli"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) throws {
        delete(account: account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AIError.failed(SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)")
        }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
