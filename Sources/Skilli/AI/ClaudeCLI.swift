import AppKit

/// The user's own `claude` binary (Claude Code), used as is. skil.li never
/// reads its credentials: it asks the binary for its status and lets it run
/// its own sign-in. Details and traps: docs/ai-engines.md.
enum ClaudeCLI {
    enum Status: Equatable, Sendable {
        case notInstalled
        case signedOut
        /// `plan` is the subscription ("pro", "max"), nil for Console billing.
        case signedIn(plan: String?)
    }

    /// Empty working directory: a project's CLAUDE.md must never reach the
    /// model.
    static let scratchDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Usual install locations first; then the login shell, since apps
    /// started from Finder get a bare PATH.
    static func locate() async -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        let shell = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        guard let output = try? await run(shell, ["-lc", "command -v claude"], timeout: 5) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// `claude auth status --json`: ~0.1 s, no network.
    static func status(binary: URL) async -> Status {
        guard let output = try? await run(binary, ["auth", "status", "--json"], timeout: 10),
              let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              json["loggedIn"] as? Bool == true
        else { return .signedOut }
        return .signedIn(plan: json["subscriptionType"] as? String)
    }

    /// The app's own environment with the binary's folder on PATH. It must
    /// keep USER: without it `claude` cannot find its sign-in and reports
    /// signed out. API variables are dropped so the subscription is used.
    static func environment(for binary: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY"] {
            environment[key] = nil
        }
        environment["USER"] = environment["USER"] ?? NSUserName()
        let path = [binary.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            + (environment["PATH"]?.split(separator: ":").map(String.init) ?? [])
        var seen = Set<String>()
        environment["PATH"] = path.filter { seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }

    /// Opens Claude Code's own sign-in in a terminal. The user signs in
    /// with Anthropic in the browser; skil.li never sees the credentials.
    @MainActor
    static func openSignIn(binary: URL) throws {
        let quoted = "'" + binary.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = scratchDirectory.appendingPathComponent("Sign in to Claude.command")
        try """
            #!/bin/zsh
            clear
            \(quoted) auth login --claudeai
            echo
            echo "Done. You can close this window and go back to skil.li."
            """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
    }

    /// Runs a short command off the main thread and returns its standard
    /// output, whatever the exit status (`auth status` exits 1 when signed out).
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws -> String {
        let child = ChildProcess()
        child.process.executableURL = executable
        child.process.arguments = arguments
        child.process.environment = environment(for: executable)
        child.process.currentDirectoryURL = scratchDirectory
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let output = Pipe()
                child.process.standardOutput = output
                child.process.standardError = FileHandle.nullDevice
                do {
                    try child.process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { child.terminate() }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                child.process.waitUntilExit()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}

/// `Process` is not Sendable; it is only touched before launch and through
/// `terminate`, its state and its id, which Foundation makes safe from any
/// thread.
final class ChildProcess: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    /// Its output read to the end.
    private var outputClosed = false

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    /// It and what it started: `Process` makes it its own process group's
    /// leader. While it runs, while something it started holds its output
    /// open, or while a member runs on with its output closed (`kill(-pid,
    /// 0)` answers): a group with a live member keeps its id, no one else's.
    func terminateGroup(_ signal: Int32 = SIGTERM) {
        lock.withLock {
            let pid = process.processIdentifier
            guard pid > 0, process.isRunning || !outputClosed || kill(-pid, 0) == 0 else { return }
            kill(-pid, signal)
        }
    }

    private func closedOutput() {
        lock.withLock { outputClosed = true }
    }

    /// Runs it with skil.li's PATH (and `environment` on top, `unset` taken
    /// out): what it printed (output and errors together, or the output
    /// alone without `withErrors`) and its exit status. Stopped after
    /// `timeout`; with `stopsGroup`, with what it started (a skillie's
    /// `Skilli call`, a process left in the background: either would keep
    /// its output open), killed 3 s later if SIGTERM did not stop them.
    static func run(_ executable: URL, _ arguments: [String], directory: URL? = nil, environment: [String: String] = [:],
                    unset: [String] = [], withErrors: Bool = true, stopsGroup: Bool = false,
                    timeout: TimeInterval) async throws -> (output: String, status: Int32) {
        let child = ChildProcess()
        child.process.executableURL = executable
        child.process.arguments = arguments
        var variables = ClaudeCLI.environment(for: executable).merging(environment) { $1 }
        for key in unset { variables[key] = nil }
        child.process.environment = variables
        if let directory { child.process.currentDirectoryURL = directory }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let pipe = Pipe()
                child.process.standardOutput = pipe
                child.process.standardError = withErrors ? pipe : FileHandle.nullDevice
                child.process.standardInput = FileHandle.nullDevice
                do {
                    try child.process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard stopsGroup else { return child.terminate() }
                    child.terminateGroup()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { child.terminateGroup(SIGKILL) }
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                child.closedOutput()
                child.process.waitUntilExit()
                continuation.resume(returning: (String(decoding: data, as: UTF8.self), child.process.terminationStatus))
            }
        }
    }
}
