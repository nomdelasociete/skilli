import Foundation
import SkilliCore

/// Reads another MCP server's tools, to show them with their rights: over
/// Streamable HTTP (with the user's sign-in headers) or by starting its
/// command (stdio). Only `initialize` and `tools/list`: no tool is called.
enum MCPClient {
    struct Failure: LocalizedError {
        let message: String
        /// The server answered 401: it wants the user signed in.
        var needsSignIn = false
        var errorDescription: String? { message }
    }

    static let protocolVersion = "2025-06-18"

    static func listTools(_ server: MCPServerConfig, headers: [String: String]) async throws -> [MCPToolInfo] {
        if let address = server.url {
            guard let url = URL(string: address), url.host != nil else { throw Failure(message: "“\(server.name)” has no valid address.") }
            // A token goes over https only (plain http to this Mac for tests).
            guard headers.isEmpty || MCPOAuth.isAllowed(address) else {
                throw Failure(message: "“\(server.name)” needs an https:// address to receive your sign-in.")
            }
            return try await http(url, headers: headers, name: server.name)
        }
        guard let command = server.command, !command.isEmpty else { throw Failure(message: "“\(server.name)” has no command.") }
        return try await stdio(command, server.args, environment: server.env, name: server.name)
    }

    private static var initialize: [String: Any] {
        ["jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": ["protocolVersion": protocolVersion, "capabilities": [String: Any](), "clientInfo": ["name": "skil.li", "version": "1"]]]
    }

    // MARK: - Streamable HTTP

    private static func http(_ url: URL, headers: [String: String], name: String) async throws -> [MCPToolInfo] {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var sessionID: String?
        var version = protocolVersion
        func request(_ method: String) -> URLRequest {
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = method
            if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            return request
        }
        func send(_ message: [String: Any]) async throws -> (messages: [[String: Any]], status: Int) {
            var post = request("POST")
            post.setValue("application/json", forHTTPHeaderField: "Content-Type")
            post.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if message["method"] as? String != "initialize" { post.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
            post.httpBody = try JSONSerialization.data(withJSONObject: message)
            let (data, response) = try await session.data(for: post, delegate: SameHostRedirects.shared)
            let http = response as? HTTPURLResponse
            if let id = http?.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = id }
            return (MCPToolList.messages(data, contentType: http?.value(forHTTPHeaderField: "Content-Type") ?? ""), http?.statusCode ?? 0)
        }
        let started = try await send(initialize)
        if started.status == 401 { throw Failure(message: "Sign in to “\(name)” first.", needsSignIn: true) }
        guard (200..<300).contains(started.status), let result = reply(1, in: started.messages) else {
            throw Failure(message: "“\(name)” did not answer as an MCP server (HTTP \(started.status)).")
        }
        version = result["protocolVersion"] as? String ?? protocolVersion
        defer {
            // Done with it: the spec's way to end a session.
            if sessionID != nil {
                let end = request("DELETE")
                Task.detached { _ = try? await URLSession.shared.data(for: end, delegate: SameHostRedirects.shared) }
            }
        }
        _ = try? await send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        var tools: [MCPToolInfo] = []
        var cursor: String?
        for page in 0..<50 {
            var message: [String: Any] = ["jsonrpc": "2.0", "id": page + 2, "method": "tools/list"]
            if let cursor { message["params"] = ["cursor": cursor] }
            let answer = try await send(message)
            guard let result = reply(page + 2, in: answer.messages) else { throw Failure(message: "“\(name)” did not list its tools.") }
            let found = MCPToolList.page(result)
            tools += found.tools
            guard let next = found.next else { break }
            cursor = next
        }
        return tools
    }

    /// The result of the reply to `id`; nil for an error or nothing.
    private static func reply(_ id: Int, in messages: [[String: Any]]) -> [String: Any]? {
        messages.first { ($0["id"] as? Int) == id || ($0["id"] as? String) == String(id) }?["result"] as? [String: Any]
    }

    // MARK: - stdio

    private static func stdio(_ command: String, _ arguments: [String], environment: [String: String], name: String) async throws -> [MCPToolInfo] {
        let peer = StdioPeer()
        try peer.start(command, arguments, environment: environment)
        defer { peer.stop() }
        peer.send(initialize)
        guard let started = try await peer.reply(1, timeout: .seconds(60)), started["result"] != nil else {
            throw Failure(message: "“\(name)” did not start as an MCP server.")
        }
        peer.send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        var tools: [MCPToolInfo] = []
        var cursor: String?
        for page in 0..<50 {
            var message: [String: Any] = ["jsonrpc": "2.0", "id": page + 2, "method": "tools/list"]
            if let cursor { message["params"] = ["cursor": cursor] }
            peer.send(message)
            guard let answer = try await peer.reply(page + 2, timeout: .seconds(30)), let result = answer["result"] as? [String: Any] else {
                throw Failure(message: "“\(name)” did not list its tools.")
            }
            let found = MCPToolList.page(result)
            tools += found.tools
            guard let next = found.next else { break }
            cursor = next
        }
        return tools
    }
}

/// Follows a redirect only to the same host (a trailing slash, http to
/// https): the sign-in headers never go anywhere else.
private final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = SameHostRedirects()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let from = task.originalRequest?.url, let to = request.url, from.host == to.host,
              to.scheme == "https" || to.scheme == from.scheme else { return nil }
        return request
    }
}

/// A server started as a command, spoken to in JSON lines.
private final class StdioPeer: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    /// Every message read so far, parsed line by line as it comes.
    private var messages: [[String: Any]] = []

    func start(_ command: String, _ arguments: [String], environment: [String: String]) throws {
        // Through env: "npx", "uvx" or a path, found on skil.li's PATH.
        let env = URL(fileURLWithPath: "/usr/bin/env")
        process.executableURL = env
        process.arguments = [command] + arguments
        process.environment = ClaudeCLI.environment(for: env).merging(environment) { $1 }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else {
                // End of the output: nothing more will come.
                handle.readabilityHandler = nil
                return
            }
            self.lock.withLock { self.append(data) }
        }
        try process.run()
    }

    /// Under the lock.
    private func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] { messages.append(message) }
        }
    }

    func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    /// The message answering `id`.
    func reply(_ id: Int, timeout: Duration) async throws -> [String: Any]? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let found = lock.withLock { messages.first { ($0["id"] as? Int) == id || ($0["id"] as? String) == String(id) } }
            if let found { return found }
            if !process.isRunning { return nil }
            try await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    /// Closing its input ends most servers; the rest are stopped.
    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
