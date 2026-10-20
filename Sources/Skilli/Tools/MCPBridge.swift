import Darwin
import Foundation
import SkilliCore

/// The `Skilli` binary as a command-line tool, before any AppKit:
///
///     Skilli mcp [--socket <path>] [--run <id>]
///         MCP server on stdio for any agent (Claude Code, Codex…): bridges
///         to the running skil.li, starting it if needed.
///     Skilli call <tool> [<json arguments> | <name>=<value>…] [--socket <path>] [--run <id>]
///         Calls one tool and prints its text (scripts, quick checks):
///         exit 0 with its answer, 1 with its error, 2 when written wrong.
///
/// A skillie's process reaches the skil.li running it (`SKILLI_SOCKET`)
/// and says which run it is (`SKILLI_SKILLIE`): `SkillieEnvironment`.
///
/// The app does the work (it has Accessibility and the card); this process
/// only moves lines.
enum MCPBridge {
    /// The exit status when the arguments ask for the command line, nil to
    /// start the app.
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard let command = arguments.dropFirst().first, ["mcp", "call"].contains(command) else { return nil }
        signal(SIGPIPE, SIG_IGN)
        let run = value(after: "--run", in: arguments)
        // A call written wrong is said (exit 2) before skil.li is reached.
        var request: (tool: String, arguments: [String: Any])?
        if command == "call" {
            var rest: [String] = []
            var words = Array(arguments.dropFirst(2))[...]
            while let word = words.popFirst() {
                if ["--socket", "--run"].contains(word) { _ = words.popFirst() } else if !word.hasPrefix("--") { rest.append(word) }
            }
            guard let tool = rest.first else {
                FileHandle.standardError.write(Data("usage: Skilli call <tool> [<json arguments> | <name>=<value>…]\n".utf8))
                return 2
            }
            guard let parsed = parse(Array(rest.dropFirst())) else { return 2 }
            request = (tool, parsed)
        }
        let (path, startsApp) = SkillieEnvironment.socket(flag: value(after: "--socket", in: arguments),
                                                          environment: ProcessInfo.processInfo.environment,
                                                          defaultPath: MCPSocketServer.defaultPath)
        guard let fd = connect(path, startApp: startsApp) else {
            FileHandle.standardError.write(Data("skil.li is not running (no tool server at \(path)).\n".utf8))
            return 1
        }
        guard let request else { return bridge(fd, run: run) }
        return call(fd, tool: request.tool, arguments: request.arguments, run: run)
    }

    /// A call's arguments: one JSON object, or `name=value` words (each
    /// value a string: a skillie's argument in it cannot break the call);
    /// nil once said what is wrong.
    private static func parse(_ words: [String]) -> [String: Any]? {
        if words.count == 1, words[0].hasPrefix("{") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(words[0].utf8)) as? [String: Any] else {
                FileHandle.standardError.write(Data("arguments must be a JSON object\n".utf8))
                return nil
            }
            return object
        }
        guard let pairs = SkillieEnvironment.arguments(words) else {
            FileHandle.standardError.write(Data("arguments must be one JSON object or name=value words\n".utf8))
            return nil
        }
        return pairs
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Connects, starting skil.li in the background once if it is not
    /// running.
    private static func connect(_ path: String, startApp: Bool) -> Int32? {
        if let fd = tryConnect(path) { return fd }
        guard startApp else { return nil }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-b", "com.nomdelasociete.Skilli"]
        try? open.run()
        for _ in 0..<50 {
            usleep(100_000)
            if let fd = tryConnect(path) { return fd }
        }
        return nil
    }

    private static func tryConnect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes + [0]) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// First line on every connection: who is calling.
    private static func hello(_ fd: Int32, run: String?) {
        var hello: [String: Any] = ["client": "bridge"]
        if let run { hello["run"] = run }
        // A skillie's process: its calls under its name, in its card.
        if let skillie = ProcessInfo.processInfo.environment[SkillieEnvironment.skillie], !skillie.isEmpty { hello["skillie"] = skillie }
        if let data = try? JSONSerialization.data(withJSONObject: ["skilli": hello]) {
            writeAll(fd, data + Data([0x0A]))
        }
    }

    private static func bridge(_ fd: Int32, run: String?) -> Int32 {
        hello(fd, run: run)
        // stdin → socket on a thread; socket → stdout here.
        let input = Thread {
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = read(STDIN_FILENO, &chunk, chunk.count)
                if count <= 0 { break }
                chunk.withUnsafeBytes { writeAll(fd, Data($0.prefix(count))) }
            }
            // The agent is done with us.
            exit(0)
        }
        input.start()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { return 0 }
            chunk.withUnsafeBytes { writeAll(STDOUT_FILENO, Data($0.prefix(count))) }
        }
    }

    private static func call(_ fd: Int32, tool: String, arguments parsed: [String: Any], run: String?) -> Int32 {
        hello(fd, run: run)
        let messages: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "skilli-cli", "title": "Terminal", "version": "1"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": tool, "arguments": parsed]]
        ]
        for message in messages {
            if let data = try? JSONSerialization.data(withJSONObject: message) { writeAll(fd, data + Data([0x0A])) }
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { return 1 }
            buffer.append(chunk, count: count)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let response = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      response["id"] as? Int == 2 else { continue }
                if let error = response["error"] as? [String: Any] {
                    FileHandle.standardError.write(Data("\(error["message"] as? String ?? "error")\n".utf8))
                    return 1
                }
                let result = response["result"] as? [String: Any]
                let text = (result?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
                let isError = result?["isError"] as? Bool ?? false
                (isError ? FileHandle.standardError : FileHandle.standardOutput).write(Data((text + "\n").utf8))
                return isError ? 1 : 0
            }
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written <= 0 {
                    if errno == EINTR { continue }
                    return
                }
                offset += written
            }
        }
    }
}
