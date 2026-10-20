import Foundation
import Network

/// A tiny HTTP server on 127.0.0.1, one handler for every request: where a
/// browser comes back after signing in to an MCP server (and the
/// self-test's stand-in servers). One request per connection.
final class LoopbackServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        /// Path and query: "/callback?code=…".
        let target: String
        /// Lowercased names.
        let headers: [String: String]
        let body: Data
    }

    struct Response: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()

        static func json(_ object: Any, status: Int = 200) -> Response {
            Response(status: status, headers: ["Content-Type": "application/json"],
                     body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }

        static func html(_ text: String) -> Response {
            Response(headers: ["Content-Type": "text/html; charset=utf-8"], body: Data(text.utf8))
        }
    }

    private let listener: NWListener
    private let handler: @Sendable (Request) -> Response
    private let lock = NSLock()
    private var boundPort: UInt16?

    init?(handler: @escaping @Sendable (Request) -> Response) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else { return nil }
        self.listener = listener
        self.handler = handler
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = listener.port?.rawValue, let self else { return }
            self.lock.withLock { self.boundPort = port }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.receive(connection, buffer: Data())
        }
        listener.start(queue: .global())
    }

    /// Its port once listening (within a second).
    func port() async -> UInt16? {
        for _ in 0..<100 {
            if let port = lock.withLock({ boundPort }) { return port }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    func stop() {
        listener.cancel()
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                let response = self.handler(request)
                connection.send(content: Self.serialize(response), completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            if isComplete || error != nil || buffer.count > 1_000_000 { return connection.cancel() }
            self.receive(connection, buffer: buffer)
        }
    }

    /// A whole request once its head and its body (Content-Length) are in.
    static func parse(_ buffer: Data) -> Request? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = head.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(parts[0]), target: String(parts[1]), headers: headers, body: Data(body.prefix(length)))
    }

    static func serialize(_ response: Response) -> Data {
        let reason = [200: "OK", 201: "Created", 302: "Found", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found"][response.status] ?? "OK"
        var text = "HTTP/1.1 \(response.status) \(reason)\r\n"
        for (name, value) in response.headers { text += "\(name): \(value)\r\n" }
        text += "Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        return Data(text.utf8) + response.body
    }
}
