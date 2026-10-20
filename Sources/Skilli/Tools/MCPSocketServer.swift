import Darwin
import Foundation

/// skil.li's MCP server transport: newline-delimited JSON-RPC (MCP's stdio
/// framing) on a Unix socket in skil.li's own folder. Only processes of the
/// same user can connect (`getpeereid`), and the socket file is 0600.
/// Agents reach it through `Skilli mcp` (`MCPBridge`), a stdio bridge.
///
/// Each connection reads on its own thread; lines go to `onLine`, which
/// hops to the main actor. Writes are serialized per connection.
final class MCPSocketServer: @unchecked Sendable {
    let path: String
    private let onLine: @Sendable (MCPConnection, Data) -> Void
    private let onClose: @Sendable (MCPConnection) -> Void
    private let lock = NSLock()
    private var listener: Int32 = -1

    /// `~/Library/Application Support/skil.li/mcp.sock`.
    static var defaultPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true)
            .appendingPathComponent("mcp.sock").path
    }

    init(path: String, onLine: @escaping @Sendable (MCPConnection, Data) -> Void, onClose: @escaping @Sendable (MCPConnection) -> Void) {
        self.path = path
        self.onLine = onLine
        self.onClose = onClose
    }

    func start() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // A socket left by a crash; skil.li is the only one listening here.
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPError.socket("socket: \(String(cString: strerror(errno)))") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw MCPError.socket("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes + [0])
        }
        // 0600 from the start: no moment where another user could connect.
        let previousMask = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(previousMask)
        guard bound == 0, listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw MCPError.socket("bind \(path): \(reason)")
        }
        lock.withLock { listener = fd }
        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "skil.li MCP accept"
        thread.start()
    }

    func stop() {
        let fd = lock.withLock { () -> Int32 in
            let fd = listener
            listener = -1
            return fd
        }
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let connection = MCPConnection(fd: client)
            let thread = Thread { [self] in readLoop(connection) }
            thread.name = "skil.li MCP connection"
            thread.start()
        }
    }

    private func readLoop(_ connection: MCPConnection) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(connection.fd, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(chunk, count: count)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty { onLine(connection, Data(line)) }
            }
            // A client that never ends a line.
            if buffer.count > 16 * 1024 * 1024 { break }
        }
        connection.close()
        onClose(connection)
    }
}

/// One client: a bridge for Claude Code, Codex, a script.
final class MCPConnection: @unchecked Sendable, Hashable {
    let id = UUID()
    let fd: Int32
    private let lock = NSLock()
    private var closed = false

    init(fd: Int32) {
        self.fd = fd
    }

    /// Writes one JSON-RPC message and its newline.
    func send(_ message: Data) {
        lock.withLock {
            guard !closed else { return }
            var data = message
            data.append(0x0A)
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

    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    static func == (lhs: MCPConnection, rhs: MCPConnection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum MCPError: LocalizedError {
    case socket(String)

    var errorDescription: String? {
        switch self {
        case .socket(let reason): "skil.li's tool server: \(reason)"
        }
    }
}
