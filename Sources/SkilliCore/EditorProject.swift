import Foundation

/// A folder or workspace an editor opened lately: Cursor, VS Code,
/// Windsurf, Zed, Sublime Text, JetBrains IDEs. Read from the editors' own
/// recent lists; opened again in the same editor.
public struct EditorProject: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case folder, workspace
    }

    public let path: String
    public let kind: Kind
    /// "Cursor".
    public let editor: String
    public let bundleID: String
    /// Its place in the editor's own list, most recent first.
    public let rank: Int
    public let opened: Date?

    public init(path: String, kind: Kind, editor: String, bundleID: String, rank: Int, opened: Date? = nil) {
        self.path = path
        self.kind = kind
        self.editor = editor
        self.bundleID = bundleID
        self.rank = rank
        self.opened = opened
    }

    /// "skilli", or "skilli" for "skilli.code-workspace".
    public var name: String {
        let last = (path as NSString).lastPathComponent
        return kind == .workspace ? (last as NSString).deletingPathExtension : last
    }

    /// "~/Documents/Github/NomDeLaSociete": where it is, without the name.
    public func folder(home: String = NSHomeDirectory()) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}

/// The editors' recent lists, each in its own format.
public enum EditorProjectParsing {
    /// VS Code and its forks (`history.recentlyOpenedPathsList` in
    /// `state.vscdb`): folders and workspaces on this Mac, most recent
    /// first; files and remote ones left out.
    public static func vscodeRecent(_ json: Data) -> [(path: String, kind: EditorProject.Kind)] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            if let uri = entry["folderUri"] as? String, let path = localPath(uri) { return (path, .folder) }
            if let workspace = entry["workspace"] as? [String: Any], let uri = workspace["configPath"] as? String,
               let path = localPath(uri) { return (path, .workspace) }
            return nil
        }
    }

    /// Zed's `workspaces.paths`: one folder per line (several for a
    /// multi-folder workspace, the first names it).
    public static func zedPaths(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).map(String.init).first { $0.hasPrefix("/") }
    }

    /// Sublime Text's session: `folder_history`, most recent first.
    public static func sublimeFolders(_ json: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        return (root["folder_history"] as? [String] ?? []).filter { $0.hasPrefix("/") }
    }

    /// JetBrains' `recentProjects.xml`: each `<entry key="$USER_HOME$/…">`
    /// with its `projectOpenTimestamp`, most recent first.
    public static func jetBrainsRecent(_ xml: String, home: String = NSHomeDirectory()) -> [(path: String, opened: Date?)] {
        let entry = try! NSRegularExpression(pattern: #"<entry key="([^"]+)">(.*?)</entry>"#, options: [.dotMatchesLineSeparators])
        let stamp = try! NSRegularExpression(pattern: #"name="projectOpenTimestamp" value="(\d+)""#)
        let text = xml as NSString
        var found: [(path: String, opened: Date?)] = []
        for match in entry.matches(in: xml, range: NSRange(location: 0, length: text.length)) {
            let path = text.substring(with: match.range(at: 1)).replacingOccurrences(of: "$USER_HOME$", with: home)
            guard path.hasPrefix("/") else { continue }
            let body = text.substring(with: match.range(at: 2)) as NSString
            let opened = stamp.firstMatch(in: body as String, range: NSRange(location: 0, length: body.length))
                .flatMap { Double(body.substring(with: $0.range(at: 1))) }
                .map { Date(timeIntervalSince1970: $0 / 1_000) }
            found.append((path, opened))
        }
        return found.sorted { ($0.opened ?? .distantPast) > ($1.opened ?? .distantPast) }
    }

    /// Every editor's list in one: by date when known, else by rank, the
    /// editors used last first. One row per project and editor.
    public static func merged(_ lists: [[EditorProject]]) -> [EditorProject] {
        var seen = Set<String>()
        let all = lists.enumerated().flatMap { order, list in list.map { (order, $0) } }
        return all.sorted { lhs, rhs in
            if let left = lhs.1.opened, let right = rhs.1.opened, left != right { return left > right }
            if lhs.1.rank != rhs.1.rank { return lhs.1.rank < rhs.1.rank }
            return lhs.0 < rhs.0
        }
        .map(\.1)
        .filter { seen.insert($0.editor + "\u{0}" + $0.path).inserted }
    }

    /// "file:///Users/me/My%20Project" → "/Users/me/My Project"; remote
    /// (vscode-remote://…) and other schemes are nil.
    static func localPath(_ uri: String) -> String? {
        guard uri.hasPrefix("file://"), let url = URL(string: uri), url.isFileURL else { return nil }
        let path = url.path
        return path.isEmpty ? nil : path
    }
}
