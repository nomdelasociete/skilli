import Foundation

/// Parses what `ps` and `lsof` print, for Kill Process and Kill Port.
public enum ProcessListing {
    public struct Entry: Equatable, Sendable {
        public let pid: Int32
        public let cpu: Double
        public let memoryKB: Int
        /// The executable's path, or its name.
        public let path: String

        /// "Grok Bot Helper".
        public var name: String { (path as NSString).lastPathComponent }

        /// The outermost app bundle the executable lives in, if any
        /// ("/Applications/Grok Bot.app").
        public var appPath: String? {
            guard let range = path.range(of: ".app/") else { return nil }
            return String(path[..<range.lowerBound]) + ".app"
        }
    }

    /// `ps -axo pid=,pcpu=,rss=,comm=`: "  611  42.3 543280 /System/…/WindowServer".
    public static func parse(ps output: String) -> [Entry] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let cpu = Double(fields[1]), let rss = Int(fields[2]) else { return nil }
            return Entry(pid: pid, cpu: cpu, memoryKB: rss, path: String(fields[3]).trimmingCharacters(in: .whitespaces))
        }
    }

    /// `lsof -nP -iTCP:<port> -sTCP:LISTEN -Fp`: "p1234" lines → pids.
    public static func parse(lsofPIDs output: String) -> [Int32] {
        var pids: [Int32] = []
        for line in output.split(separator: "\n") where line.hasPrefix("p") {
            if let pid = Int32(line.dropFirst()), !pids.contains(pid) { pids.append(pid) }
        }
        return pids
    }

    /// An app and all its processes (Gather and its helpers), or a process
    /// on its own (node, python).
    public struct Group: Equatable, Sendable {
        /// The app's bundle path, or the process's own path.
        public let key: String
        public let name: String
        /// The app bundle, when the processes belong to one.
        public let appPath: String?
        public let entries: [Entry]

        public init(key: String, name: String, appPath: String?, entries: [Entry]) {
            self.key = key
            self.name = name
            self.appPath = appPath
            self.entries = entries
        }

        /// One process as a group of its own (a row by port, or unfolded).
        public init(single entry: Entry) {
            self.init(key: "\(entry.path)#\(entry.pid)", name: entry.name, appPath: entry.appPath, entries: [entry])
        }

        public var cpu: Double { entries.reduce(0) { $0 + $1.cpu } }
        public var memoryKB: Int { entries.reduce(0) { $0 + $1.memoryKB } }
        public var pids: [Int32] { entries.map(\.pid) }
    }

    /// Groups by app bundle, busiest first; a filter keeps groups whose
    /// name or any process name contains it.
    public static func groups(_ entries: [Entry], matching filter: String = "") -> [Group] {
        var order: [String] = []
        var byKey: [String: [Entry]] = [:]
        for entry in entries {
            let key = entry.appPath ?? "\(entry.path)#\(entry.pid)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(entry)
        }
        let filter = filter.lowercased()
        return order.compactMap { key -> Group? in
            guard let members = byKey[key] else { return nil }
            let appPath = members[0].appPath
            let name = appPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? members[0].name
            guard filter.isEmpty || name.lowercased().contains(filter) || members.contains(where: { $0.name.lowercased().contains(filter) })
            else { return nil }
            return Group(key: key, name: name, appPath: appPath, entries: members.sorted { $0.cpu > $1.cpu })
        }
        .sorted { $0.cpu > $1.cpu }
    }

    /// "kill 3000" → port 3000; "kill node" → name "node"; "kill" → all.
    public enum Query: Equatable, Sendable {
        case all
        case name(String)
        case port(Int)
    }

    /// What follows "kill " / "quit " / "port " in the launcher, or nil
    /// when the text is not a kill request.
    public static func query(_ text: String) -> Query? {
        let lower = text.lowercased()
        for prefix in LauncherPrefix.prefixes(for: .killProcess) where lower.hasPrefix(prefix) {
            let rest = lower.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if let port = Int(rest.hasPrefix(":") ? String(rest.dropFirst()) : rest), (1...65535).contains(port) { return .port(port) }
            return rest.isEmpty ? .all : .name(rest)
        }
        return nil
    }
}
