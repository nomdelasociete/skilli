import Foundation

/// The relay origin (`PUBLIC_URL`). Empty means the stream stays off.
public enum RelayAddress {
    /// `https` anywhere, `http` only on this Mac. A pasted `/stream` is the
    /// origin. Userinfo is refused so a token cannot ride in the URL.
    public static func origin(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil else {
            return nil
        }
        let local = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && local) else { return nil }
        if parts.path == "/stream" { parts.path = "" }
        guard parts.path.isEmpty || parts.path == "/" else { return nil }
        parts.scheme = scheme
        parts.host = host
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    public static func stream(_ origin: URL) -> URL {
        var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.scheme = origin.scheme
        parts.host = origin.host
        parts.port = origin.port
        parts.path = "/stream"
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? origin
    }
}

/// A sealed stream token (`relay mint` prints `v1.…`). A GitHub OAuth token
/// or PAT does not match, so it cannot be sent to the relay by mistake.
public enum RelayToken {
    public static func accepts(_ token: String) -> Bool {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (token.hasPrefix("v1.") || token.hasPrefix("v2.")), token.count > "v1.".count,
              !token.contains(where: \.isWhitespace) else {
            return false
        }
        let lowered = token.lowercased()
        return !lowered.contains("github_pat_") && !lowered.contains("gho_") && !lowered.contains("ghp_")
    }
}

public enum RelayPlan {
    /// The inbox timer runs unless the stream is configured and up.
    public static func suspendsInboxPoll(configured: Bool, connected: Bool) -> Bool {
        configured && connected
    }

    public static func holdsStream(configured: Bool, interfaceVisible: Bool) -> Bool {
        configured && interfaceVisible
    }
}

/// Many wakes during one fetch become one follow-up fetch.
public struct RelayCoalescer {
    public init() {}

    private var armed = false
    private var again = false

    public mutating func push(inFlight: Bool) -> Bool {
        if inFlight || armed {
            again = true
            armed = true
            return false
        }
        armed = true
        return true
    }

    public mutating func finished() -> Bool {
        armed = false
        if again {
            again = false
            armed = true
            return true
        }
        return false
    }
}

/// One `event: wake`. Comments (`: connected`, `: ping`) are not wakes.
/// Repository, number, title, and body are ignored when present.
public struct RelayWake: Equatable {
    public var app: String
    public var installation: String
    public var type: String
    public var action: String
    public var delivery: String

    public static func parse(_ block: String) -> RelayWake? {
        var event: String?
        var data: [String] = []
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst("data:".count)
                if value.first == " " { value = value.dropFirst() }
                data.append(String(value))
            }
        }
        guard event == "wake", let body = data.joined(separator: "\n").data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let app = object["app"] as? String, !app.isEmpty,
              let installation = object["installation"] as? String, !installation.isEmpty,
              let type = object["type"] as? String else {
            return nil
        }
        return RelayWake(
            app: app,
            installation: installation,
            type: type,
            action: object["action"] as? String ?? "",
            delivery: object["delivery"] as? String ?? ""
        )
    }
}

public struct RelayFrameParser {
    private var lines: [String] = []

    public mutating func consume(_ line: String) -> RelayWake? {
        if lines.count > 40 { lines.removeAll() }
        if !line.isEmpty {
            lines.append(line)
            return nil
        }
        let block = lines.joined(separator: "\n")
        lines.removeAll()
        return RelayWake.parse(block)
    }
}

public enum RelayResponse {
    public static func isEventStream(_ contentType: String?) -> Bool {
        contentType?.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "text/event-stream"
    }
}

public enum RelayRetry {
    /// A stream that delivered a frame after the greeting is a short blip:
    /// retry at once. A 200 that never became that stream backs off.
    public static func delay(previous: TimeInterval, established: Bool) -> TimeInterval {
        if established { return 0.5 }
        return min(30, previous == 0 ? 0.5 : previous * 2)
    }
}

public enum RelayRequest {
    /// Bearer is the sealed token only. No cookies, no GitHub credential.
    /// `inbox`: server sync's stream, which wakes only when the relay's copy
    /// changed (`X-Relay-Inbox: 1`).
    public static func stream(origin: URL, relayToken: String, inbox: Bool = false) -> URLRequest? {
        guard RelayToken.accepts(relayToken) else { return nil }
        var request = URLRequest(url: RelayAddress.stream(origin))
        request.httpMethod = "GET"
        request.setValue("Bearer \(relayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if inbox { request.setValue("1", forHTTPHeaderField: "X-Relay-Inbox") }
        return request
    }
}

/// Drops redirects so the bearer token stays on this host.
public final class RelayNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

public enum RelayFailure: Error {
    case unauthorized
    case closed
}

/// One `GET /stream`. Reconnects after a drop. The owner refetches GitHub.
@MainActor
public final class RelayConnection {
    public init() {}

    public var onConnect: () -> Void = {}
    public var onWake: () -> Void = {}
    public var onDrop: () -> Void = {}
    public var onRejected: () -> Void = {}

    public private(set) var isConnected = false
    private var task: Task<Void, Never>?
    private var session: URLSession?
    private var redirectStop: RelayNoRedirect?
    private var generation = 0

    public var isRunning: Bool { task != nil }

    public func start(origin: URL, token: String, inbox: Bool = false) {
        stop()
        guard let request = RelayRequest.stream(origin: origin, relayToken: token, inbox: inbox) else { return }
        let generation = generation
        let redirectStop = RelayNoRedirect()
        let session = URLSession(configuration: Self.configuration, delegate: redirectStop, delegateQueue: nil)
        self.session = session
        self.redirectStop = redirectStop
        task = Task { [weak self] in
            await self?.run(request: request, session: session, generation: generation)
            if self?.generation == generation { self?.task = nil }
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        redirectStop = nil
        if isConnected {
            isConnected = false
            onDrop()
        }
    }

    private func run(request: URLRequest, session: URLSession, generation: Int) async {
        var delay: TimeInterval = 0
        while !Task.isCancelled, generation == self.generation {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * Double.random(in: 0.5...1) * 1_000_000_000))
                if Task.isCancelled || generation != self.generation { return }
            }
            do {
                let established = try await read(request: request, session: session, generation: generation)
                guard generation == self.generation else { return }
                if isConnected {
                    isConnected = false
                    onDrop()
                }
                delay = RelayRetry.delay(previous: delay, established: established)
            } catch RelayFailure.unauthorized {
                guard generation == self.generation else { return }
                if isConnected {
                    isConnected = false
                    onDrop()
                }
                onRejected()
                return
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                if isConnected {
                    isConnected = false
                    onDrop()
                }
                delay = RelayRetry.delay(previous: delay, established: false)
            }
        }
    }

    /// `true` when a frame arrived after the greeting. A replaced generation
    /// returns without touching `isConnected`: `stop` already dropped the old one.
    private func read(request: URLRequest, session: URLSession, generation: Int) async throws -> Bool {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw RelayFailure.closed }
        if http.statusCode == 401 { throw RelayFailure.unauthorized }
        guard http.statusCode == 200 else { throw RelayFailure.closed }
        guard generation == self.generation else { return false }
        guard RelayResponse.isEventStream(http.value(forHTTPHeaderField: "Content-Type")) else {
            throw RelayFailure.closed
        }
        var parser = RelayFrameParser()
        var frames = 0
        var connectedFrame = false
        var expiredFrame = false
        for try await line in bytes.lines {
            if generation != self.generation { return false }
            if Task.isCancelled { throw CancellationError() }
            if line == ": connected" { connectedFrame = true }
            if line == "event: expired" { expiredFrame = true }
            let wake = parser.consume(line)
            if line.isEmpty {
                frames += 1
                if expiredFrame { throw RelayFailure.unauthorized }
                if !isConnected && connectedFrame {
                    isConnected = true
                    onConnect()
                }
            }
            if wake != nil && isConnected { onWake() }
        }
        return frames > 1
    }

    private static let configuration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 70
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        return configuration
    }()
}
