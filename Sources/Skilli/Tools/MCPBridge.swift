import Darwin
import Foundation

/// The `Skilli` binary as a command-line tool, before any AppKit:
///
///     Skilli mcp [--socket <path>] [--run <id>]
///         MCP server on stdio for any agent (Claude Code, Codex…): bridges
///         to the running skil.li, starting it if needed.
///     Skilli call <tool> [<json arguments>] [--socket <path>] [--run <id>]
///         Calls one tool and prints its text (scripts, quick checks).
///
/// The app does the work (it has Accessibility and the card); this process
/// only moves lines.
enum MCPBridge {
    /// The exit status when the arguments ask for the command line, nil to
    /// start the app.
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard let command = arguments.dropFirst().first, ["mcp", "call"].contains(command) else { return nil }
        signal(SIGPIPE, SIG_IGN)
        let socketPath = value(after: "--socket", in: arguments)
        let path = socketPath ?? MCPSocketServer.defaultPath
        guard let fd = connect(path, startApp: socketPath == nil) else {
            FileHandle.standardError.write(Data("skil.li is not running (no tool server at \(path)).\n".utf8))
            return 1
        }
        if command == "mcp" {
            return bridge(fd, run: value(after: "--run", in: arguments))
        }
        let run = value(after: "--run", in: arguments)
        var rest: [String] = []
        var words = Array(arguments.dropFirst(2))[...]
        while let word = words.popFirst() {
            if ["--socket", "--run"].contains(word) { _ = words.popFirst() } else if !word.hasPrefix("--") { rest.append(word) }
        }
        guard let tool = rest.first else {
            FileHandle.standardError.write(Data("usage: Skilli call <tool> [<json arguments>]\n".utf8))
            return 2
        }
        return call(fd, tool: tool, arguments: rest.dropFirst().first ?? "{}", run: run)
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

    private static func call(_ fd: Int32, tool: String, arguments: String, run: String?) -> Int32 {
        hello(fd, run: run)
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] else {
            FileHandle.standardError.write(Data("arguments must be a JSON object\n".utf8))
            return 2
        }
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
