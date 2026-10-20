import AppKit
import SkilliCore

/// Running processes for Kill Process / Kill Port: `ps` for the list (CPU
/// and memory as Activity Monitor shows them), `lsof` for a port.
@MainActor
enum Processes {
    struct Row: Sendable {
        let entry: ProcessListing.Entry
        /// The port it listens on, when asked by port.
        let port: Int?
    }

    static func snapshot() async -> [ProcessListing.Entry] {
        let output = (try? await ClaudeCLI.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "pid=,pcpu=,rss=,comm="], timeout: 5)) ?? ""
        return ProcessListing.parse(ps: output).filter { $0.pid != getpid() && $0.pid > 1 }
    }

    /// Processes listening on `port` (TCP).
    static func listening(on port: Int, among entries: [ProcessListing.Entry]) async -> [Row] {
        let output = (try? await ClaudeCLI.run(URL(fileURLWithPath: "/usr/sbin/lsof"), ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"], timeout: 5)) ?? ""
        let pids = ProcessListing.parse(lsofPIDs: output)
        return pids.compactMap { pid in entries.first { $0.pid == pid }.map { Row(entry: $0, port: port) } }
    }

    /// The rows for a kill request: by port, by name, or the busiest.
    static func rows(for query: ProcessListing.Query, in entries: [ProcessListing.Entry], ports: [Int: [Row]]) -> [Row] {
        switch query {
        case .all:
            return entries.sorted { $0.cpu > $1.cpu }.prefix(30).map { Row(entry: $0, port: nil) }
        case .name(let name):
            return entries.filter { $0.name.lowercased().contains(name) || ($0.appPath?.lowercased().contains(name) ?? false) }
                .sorted { $0.cpu > $1.cpu }.prefix(30).map { Row(entry: $0, port: nil) }
        case .port(let port):
            return ports[port] ?? []
        }
    }

    /// Quits (apps get to save) or force quits. Throws a sentence.
    @discardableResult
    static func quit(_ pid: Int32, force: Bool) throws -> String {
        guard pid > 1, pid != getpid() else { throw Failure(message: "skil.li does not quit itself or the system.") }
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited {
            let name = app.localizedName ?? "the app"
            guard force ? app.forceTerminate() : app.terminate() else { throw Failure(message: "\(name) did not quit.") }
            return force ? "Force quit \(name)." : "Asked \(name) to quit."
        }
        guard kill(pid, force ? SIGKILL : SIGTERM) == 0 else {
            throw Failure(message: errno == EPERM ? "That process belongs to the system: skil.li may not stop it." : "The process did not stop.")
        }
        return force ? "Killed process \(pid)." : "Stopped process \(pid)."
    }

    /// Quits an app and every process it started: the app first (it gets
    /// to save), then helpers still there two seconds later. Force: all at
    /// once.
    @discardableResult
    static func quit(_ group: ProcessListing.Group, force: Bool) throws -> String {
        let pids = group.pids.filter { $0 > 1 && $0 != getpid() }
        guard !pids.isEmpty else { throw Failure(message: "skil.li does not quit itself or the system.") }
        let app = group.appPath.flatMap { path in NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path } }
        if let app { _ = force ? app.forceTerminate() : app.terminate() }
        let others = pids.filter { $0 != app?.processIdentifier }
        if force || app == nil {
            var refused = 0
            for pid in others where kill(pid, force ? SIGKILL : SIGTERM) != 0 { refused += 1 }
            if refused == others.count, app == nil, !others.isEmpty {
                throw Failure(message: errno == EPERM ? "That process belongs to the system: skil.li may not stop it." : "It did not stop.")
            }
        } else {
            Task {
                try? await Task.sleep(for: .seconds(2))
                for pid in others where kill(pid, 0) == 0 { kill(pid, SIGTERM) }
            }
        }
        let count = group.entries.count
        return (force ? "Force quit " : "Quit ") + group.name + (count > 1 ? " and its \(count - 1) other process" + (count > 2 ? "es." : ".") : ".")
    }

    /// "7 processes · CPU 45 % · 1.2 GB".
    static func usage(_ group: ProcessListing.Group) -> String {
        let count = group.entries.count
        return (count > 1 ? "\(count) processes · " : "") + usage(cpu: group.cpu, memoryKB: group.memoryKB)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// "CPU 23 % · 512 MB".
    static func usage(_ entry: ProcessListing.Entry) -> String {
        usage(cpu: entry.cpu, memoryKB: entry.memoryKB)
    }

    static func usage(cpu: Double, memoryKB: Int) -> String {
        let memory = memoryKB >= 1024 * 1024
            ? String(format: "%.1f GB", Double(memoryKB) / 1024 / 1024)
            : "\(memoryKB / 1024) MB"
        return "CPU \(Int(cpu.rounded())) % · \(memory)"
    }
}
