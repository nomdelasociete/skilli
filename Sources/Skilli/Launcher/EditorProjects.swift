import AppKit
import SQLite3
import SkilliCore

/// Recent projects of the editors installed: VS Code and its forks
/// (Cursor, Windsurf, VSCodium), Zed, Sublime Text, JetBrains IDEs and
/// Android Studio, read from their own files (read-only, never written),
/// again only when one changed. Folders that are gone are left out.
@MainActor
final class EditorProjects {
    struct Editor: Sendable {
        enum Source: Sendable {
            /// `<Application Support>/<folder>/User/globalStorage/state.vscdb`.
            case vscode(String)
            /// `<Application Support>/Zed/db/<channel>/db.sqlite`.
            case zed(String)
            case sublime
            /// `<Application Support>/JetBrains/<product><version>/options/recentProjects.xml`.
            case jetBrains(String)
        }

        let name: String
        let bundleID: String
        let source: Source
    }

    nonisolated static let editors: [Editor] = [
        Editor(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", source: .vscode("Cursor")),
        Editor(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", source: .vscode("Code")),
        Editor(name: "VS Code Insiders", bundleID: "com.microsoft.VSCodeInsiders", source: .vscode("Code - Insiders")),
        Editor(name: "Windsurf", bundleID: "com.exafunction.windsurf", source: .vscode("Windsurf")),
        Editor(name: "VSCodium", bundleID: "com.vscodium", source: .vscode("VSCodium")),
        Editor(name: "Zed", bundleID: "dev.zed.Zed", source: .zed("0-stable")),
        Editor(name: "Zed Preview", bundleID: "dev.zed.Zed-Preview", source: .zed("0-preview")),
        Editor(name: "Sublime Text", bundleID: "com.sublimetext.4", source: .sublime),
        Editor(name: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij", source: .jetBrains("JetBrains/IntelliJIdea")),
        Editor(name: "IntelliJ IDEA CE", bundleID: "com.jetbrains.intellij.ce", source: .jetBrains("JetBrains/IdeaIC")),
        Editor(name: "PyCharm", bundleID: "com.jetbrains.pycharm", source: .jetBrains("JetBrains/PyCharm")),
        Editor(name: "PyCharm CE", bundleID: "com.jetbrains.pycharm.ce", source: .jetBrains("JetBrains/PyCharmCE")),
        Editor(name: "WebStorm", bundleID: "com.jetbrains.WebStorm", source: .jetBrains("JetBrains/WebStorm")),
        Editor(name: "GoLand", bundleID: "com.jetbrains.goland", source: .jetBrains("JetBrains/GoLand")),
        Editor(name: "RustRover", bundleID: "com.jetbrains.rustrover", source: .jetBrains("JetBrains/RustRover")),
        Editor(name: "PhpStorm", bundleID: "com.jetbrains.PhpStorm", source: .jetBrains("JetBrains/PhpStorm")),
        Editor(name: "CLion", bundleID: "com.jetbrains.CLion", source: .jetBrains("JetBrains/CLion")),
        Editor(name: "Rider", bundleID: "com.jetbrains.rider", source: .jetBrains("JetBrains/Rider")),
        Editor(name: "Android Studio", bundleID: "com.google.android.studio", source: .jetBrains("Google/AndroidStudio"))
    ]

    /// `~/Library/Application Support`, or a scratch one in the self-test.
    let root: URL
    /// The app for a bundle id, nil when not installed.
    let installed: (String) -> URL?
    private var cached: (stamp: [String: Date], projects: [EditorProject])?
    /// Which editors are installed, asked again after a minute: the
    /// launcher asks on every key.
    private var installedEditors: (editors: [Editor], date: Date)?

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
         installed: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
        self.root = root
        self.installed = installed
    }

    /// Every editor's recent projects, most recent first.
    func all() -> [EditorProject] {
        if installedEditors == nil || Date.now.timeIntervalSince(installedEditors!.date) > 60 {
            installedEditors = (Self.editors.filter { installed($0.bundleID) != nil }, .now)
        }
        let sources = (installedEditors?.editors ?? []).compactMap { editor in file(for: editor).map { (editor, $0) } }
        var stamp: [String: Date] = [:]
        for (_, url) in sources {
            for candidate in [url, URL(fileURLWithPath: url.path + "-wal")] {
                stamp[candidate.path] = (try? candidate.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
        }
        if let cached, cached.stamp == stamp { return cached.projects }
        // The editor whose file changed last comes first among equals.
        let ordered = sources.sorted { (stamp[$0.1.path] ?? .distantPast) > (stamp[$1.1.path] ?? .distantPast) }
        let lists = ordered.map { editor, url in read(editor, url) }
        let projects = EditorProjectParsing.merged(lists).filter { FileManager.default.fileExists(atPath: $0.path) }
        cached = (stamp, projects)
        Log.trace("Editor projects: \(projects.count) from \(sources.map(\.0.name).joined(separator: ", "))")
        return projects
    }

    /// Opens it in its editor; ⌘ shows it in Finder instead.
    static func open(_ project: EditorProject, reveal: Bool) {
        let url = URL(fileURLWithPath: project.path)
        if reveal {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: project.bundleID) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        Log.trace("Project opened in \(project.editor)")
    }

    // MARK: - Reading

    private func file(for editor: Editor) -> URL? {
        let url: URL
        switch editor.source {
        case .vscode(let folder):
            url = root.appendingPathComponent("\(folder)/User/globalStorage/state.vscdb")
        case .zed(let channel):
            url = root.appendingPathComponent("Zed/db/\(channel)/db.sqlite")
        case .sublime:
            url = root.appendingPathComponent("Sublime Text/Local/Session.sublime_session")
        case .jetBrains(let prefix):
            // The newest version's folder: "PyCharm2025.2" (not "PyCharmCE…").
            let parent = root.appendingPathComponent((prefix as NSString).deletingLastPathComponent)
            let product = (prefix as NSString).lastPathComponent
            let versions = ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
                .filter { $0.hasPrefix(product) && $0.dropFirst(product.count).first?.isNumber == true }
                .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            guard let newest = versions.first else { return nil }
            url = parent.appendingPathComponent("\(newest)/options/recentProjects.xml")
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func read(_ editor: Editor, _ url: URL) -> [EditorProject] {
        func project(_ path: String, _ kind: EditorProject.Kind, _ rank: Int, _ opened: Date? = nil) -> EditorProject {
            EditorProject(path: path, kind: kind, editor: editor.name, bundleID: editor.bundleID, rank: rank, opened: opened)
        }
        switch editor.source {
        case .vscode:
            let json = Self.query(url, "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'").first ?? ""
            return EditorProjectParsing.vscodeRecent(Data(json.utf8)).enumerated().map { project($1.path, $1.kind, $0) }
        case .zed:
            let rows = Self.query(url, "SELECT paths FROM workspaces WHERE remote_connection_id IS NULL AND paths != '' ORDER BY timestamp DESC LIMIT 100")
            return rows.compactMap(EditorProjectParsing.zedPaths).enumerated().map { project($1, .folder, $0) }
        case .sublime:
            guard let data = try? Data(contentsOf: url) else { return [] }
            return EditorProjectParsing.sublimeFolders(data).enumerated().map { project($1, .folder, $0) }
        case .jetBrains:
            guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return EditorProjectParsing.jetBrainsRecent(xml).enumerated().map { project($1.path, .folder, $0, $1.opened) }
        }
    }

    /// The first column of every row, read-only. A database open in its
    /// editor (WAL) is read as it is; one that cannot be opened so is read
    /// as of its last checkpoint.
    private static func query(_ url: URL, _ sql: String) -> [String] {
        for mode in ["mode=ro", "immutable=1"] {
            var db: OpaquePointer?
            let uri = "file:\(url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)?\(mode)"
            defer { sqlite3_close(db) }
            guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { continue }
            sqlite3_busy_timeout(db, 100)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            var rows: [String] = []
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) { rows.append(String(cString: text)) }
                result = sqlite3_step(statement)
            }
            if result == SQLITE_DONE { return rows }
        }
        return []
    }
}
