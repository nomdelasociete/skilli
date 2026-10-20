import Foundation

/// Claude on the user's subscription, through their own `claude` binary.
///
/// One process answers one request (no history) and is killed after. With
/// `keepReady`, a spare is started ahead and replaced right after each use,
/// so answers start in ~0.6 s instead of ~1 s. Idle, a spare sends nothing:
/// 0 tokens, ~230 MB outside skil.li. Measurements: docs/ai-engines.md.
@MainActor
final class ClaudeSubscriptionEngine: TextEngine {
    var binary: URL? {
        didSet { if oldValue != binary { resetSpare() } }
    }

    var model: AIModel = .haiku {
        didSet { if oldValue != model { resetSpare() } }
    }

    var keepReady = false {
        didSet { keepReady ? ensureSpare() : dropSpare() }
    }

    private var spare: ClaudeSession?

    /// Self-test hook: a spare is running and unused.
    var hasSpare: Bool { spare?.isRunning == true }
    /// Self-test hook: process id of the current spare.
    var sparePID: Int32? { spare?.pid }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        guard let binary else { return .failing(AIError.claudeNotInstalled) }
        // A command on another model than the spare's starts its own process
        // (about 0.4 s slower) and leaves the spare for the next request.
        if let other = request.model.flatMap(AIModel.init(choice:)), other != model {
            do {
                return try ClaudeSession(binary: binary, model: other).send(request)
            } catch {
                return .failing(AIError.failed("Could not start Claude Code: \(error.localizedDescription)"))
            }
        }
        let session: ClaudeSession
        if let spare, spare.isRunning {
            session = spare
            self.spare = nil
        } else {
            dropSpare()
            do {
                session = try ClaudeSession(binary: binary, model: model)
            } catch {
                return .failing(AIError.failed("Could not start Claude Code: \(error.localizedDescription)"))
            }
        }
        // Replace it at once: the next request should not wait either.
        ensureSpare()
        return session.send(request)
    }

    func ensureSpare() {
        guard keepReady, let binary, spare?.isRunning != true else { return }
        do {
            spare = try ClaudeSession(binary: binary, model: model)
        } catch {
            spare = nil
            Log.actions.error("Could not start a spare claude: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dropSpare() {
        spare?.terminate()
        spare = nil
    }

    private func resetSpare() {
        dropSpare()
        ensureSpare()
    }
}

/// One headless `claude` process, stripped of everything but text: no tools,
/// no MCP, no user settings or CLAUDE.md, no session files, a short system
/// prompt (~850 input tokens instead of ~55k).
final class ClaudeSession: @unchecked Sendable {
    private let child = ChildProcess()
    private let input = Pipe()
    private let output = Pipe()

    init(binary: URL, model: AIModel) throws {
        let process = child.process
        process.executableURL = binary
        process.arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--no-session-persistence", "--model", model.cliName,
            "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
            "--system-prompt", AIPrompt.system
        ]
        process.environment = ClaudeCLI.environment(for: binary)
        process.currentDirectoryURL = ClaudeCLI.scratchDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    var isRunning: Bool { child.process.isRunning }
    var pid: Int32 { child.process.processIdentifier }

    func terminate() {
        child.terminate()
    }

    /// Sends the request and streams the answer's text. Ends at
    /// `message_stop`: Claude Code then spends ~1.6 s on a post-turn summary
    /// nobody needs, so the process is killed instead of waited for.
    func send(_ request: AIRequest, timeout: Duration = .seconds(30)) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": request.claudeContent]]
            guard let line = try? JSONSerialization.data(withJSONObject: message) else {
                continuation.finish(throwing: AIError.failed("Could not encode the request."))
                return
            }
            do {
                try input.fileHandleForWriting.write(contentsOf: line + Data("\n".utf8))
            } catch {
                terminate()
                continuation.finish(throwing: AIError.failed("Claude Code stopped before the request."))
                return
            }

            let reader = Task.detached { [self] in
                defer { terminate() }
                do {
                    for try await line in output.fileHandleForReading.bytes.lines {
                        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                        switch event["type"] as? String {
                        case "stream_event":
                            let streamEvent = event["event"] as? [String: Any]
                            switch streamEvent?["type"] as? String {
                            case "content_block_delta":
                                if let delta = streamEvent?["delta"] as? [String: Any],
                                   delta["type"] as? String == "text_delta",
                                   let text = delta["text"] as? String {
                                    continuation.yield(text)
                                }
                            case "message_stop":
                                continuation.finish()
                                return
                            default:
                                continue
                            }
                        case "result":
                            // Failures ("Not logged in", rate limits) end the
                            // turn without a message.
                            if event["is_error"] as? Bool == true {
                                continuation.finish(throwing: AIError.failed(event["result"] as? String ?? "Claude Code failed."))
                            } else {
                                continuation.finish()
                            }
                            return
                        default:
                            continue
                        }
                    }
                    continuation.finish(throwing: AIError.failed("Claude Code stopped without answering."))
                } catch {
                    continuation.finish(throwing: AIError.failed(error.localizedDescription))
                }
            }
            let timer = Task.detached { [self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                continuation.finish(throwing: AIError.timedOut)
                terminate()
            }
            continuation.onTermination = { [self] _ in
                reader.cancel()
                timer.cancel()
                terminate()
            }
        }
    }
}
