import AppKit
import SkilliCore

/// Skillies, skil.li's own commands: the scripts of
/// `~/Library/Application Support/skil.li/skillies` with `@skilli.`
/// metadata, written by the user, by their agents (`create`) or imported
/// from Raycast (`importRaycast`, converted, never read in place). Read
/// again only when the folder changed; inline ones keep their last line.
@MainActor
final class ScriptLibrary {
    struct Run: Sendable {
        let output: String
        let status: Int32
        var succeeded: Bool { status == 0 }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li/skillies", isDirectory: true)
    }

    /// The folders scanned; the first one is where new skillies go.
    var folders: () -> [URL]
    private var cached: (stamp: [String: Date], commands: [ScriptCommand])?
    /// Inline commands' last line and when it was read.
    private var inline: [String: (line: String, date: Date)] = [:]
    private var refreshing: Set<String> = []

    init(folders: @escaping () -> [URL]) {
        self.folders = folders
    }

    /// Every Script Command, by title.
    func all() -> [ScriptCommand] {
        let folders = self.folders()
        var stamp: [String: Date] = [:]
        for folder in folders {
            stamp[folder.path] = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        if let cached, cached.stamp == stamp { return cached.commands }
        var seen = Set<String>()
        let commands = folders.flatMap(scan)
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        cached = (stamp, commands)
        Log.trace("Skillies: \(commands.count) in \(folders.count) folders")
        return commands
    }

    /// Scripts in the folder and one level of subfolders; hidden ones and
    /// Raycast's `.template.` files left out.
    private func scan(_ folder: URL) -> [ScriptCommand] {
        let manager = FileManager.default
        var files: [URL] = []
        let top = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        for url in top {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                files += (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            } else {
                files.append(url)
            }
        }
        return files.filter { !$0.lastPathComponent.contains(".template.") }.compactMap { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 8_192)) ?? Data()
            return ScriptCommand.parse(String(decoding: head, as: UTF8.self), path: url.path)
        }
    }

    // MARK: - Running

    /// Runs it with the arguments' values; its output (and errors) and exit
    /// status. Stopped after `timeout`.
    func run(_ command: ScriptCommand, arguments: [String], timeout: TimeInterval = 120) async throws -> Run {
        let url = URL(fileURLWithPath: command.path)
        let executable: URL
        let all: [String]
        if FileManager.default.isExecutableFile(atPath: command.path) {
            executable = url
            all = command.values(for: arguments)
        } else {
            // Not executable: its shebang says what runs it.
            guard let interpreter = Self.shebang(command.path) else {
                throw Failure(message: "“\(command.title)” is not executable: chmod +x \(url.lastPathComponent)")
            }
            executable = URL(fileURLWithPath: interpreter[0])
            all = Array(interpreter.dropFirst()) + [command.path] + command.values(for: arguments)
        }
        let directory = command.directory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? url.deletingLastPathComponent()
        Log.trace("Skillie “\(command.title)” run")
        let (output, status) = try await ChildProcess.run(executable, all, directory: directory, timeout: timeout)
        return Run(output: ScriptCommand.plain(output), status: status)
    }

    // MARK: - New skillies

    /// Raycast Script Commands turned into skillies: each file (or each one
    /// of a folder) copied into skil.li's folder with its metadata renamed,
    /// executable. What was imported, and how many files were not commands.
    func importRaycast(_ urls: [URL]) throws -> (imported: [String], skipped: Int) {
        let manager = FileManager.default
        var files: [URL] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                files += ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
                    .filter { !$0.lastPathComponent.contains(".template.") }
            } else {
                files.append(url)
            }
        }
        var imported: [String] = []
        var skipped = 0
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8), let converted = ScriptCommand.converted(fromRaycast: text),
                  let command = ScriptCommand.parse(converted, path: file.path) else {
                skipped += 1
                continue
            }
            try write(converted, named: file.lastPathComponent)
            imported.append(command.title)
        }
        Log.trace("Skillies: \(imported.count) imported from Raycast, \(skipped) files skipped")
        return (imported, skipped)
    }

    /// A new skillie from its parts (an agent writing one); refused when one
    /// already has its title.
    func create(title: String, description: String, mode: ScriptCommand.Mode, language: ScriptCommand.Language, code: String,
                arguments: [(placeholder: String, optional: Bool)], needsConfirmation: Bool) throws -> ScriptCommand {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure(message: "A skillie needs a title and its code.")
        }
        guard !all().contains(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) else {
            throw Failure(message: "A skillie is already called “\(title)”.")
        }
        let made = ScriptCommand.make(title: title, description: description, mode: mode, language: language, code: code,
                                      arguments: arguments, needsConfirmation: needsConfirmation)
        let url = try write(made.text, named: made.fileName)
        guard let command = ScriptCommand.parse(made.text, path: url.path) else { throw Failure(message: "The skillie could not be read back.") }
        Log.trace("Skillie “\(title)” created")
        return command
    }

    /// Into the first folder, executable; "name-2.sh" when the name is taken.
    @discardableResult
    private func write(_ text: String, named name: String) throws -> URL {
        guard let folder = folders().first else { throw Failure(message: "No skillies folder.") }
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var index = 2
        while manager.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(index)" + (ext.isEmpty ? "" : ".\(ext)"))
            index += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        cached = nil
        return url
    }

    /// `#!/usr/bin/env python3` → ["/usr/bin/env", "python3"].
    private static func shebang(_ path: String) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 256)) ?? Data(), as: UTF8.self)
        guard head.hasPrefix("#!"), let line = head.dropFirst(2).split(whereSeparator: \.isNewline).first else { return nil }
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        return parts.first?.hasPrefix("/") == true ? parts : nil
    }

    // MARK: - Inline

    /// An inline command's last line, if read.
    func inlineLine(_ command: ScriptCommand) -> String? {
        inline[command.path]?.line
    }

    /// Runs the inline commands whose line is older than their refresh time
    /// (or never read); `done` after each one.
    func refreshInline(done: @escaping @MainActor () -> Void) {
        for command in all() where command.mode == .inline && command.arguments.isEmpty && !refreshing.contains(command.path) {
            let age = inline[command.path].map { Date.now.timeIntervalSince($0.date) } ?? .infinity
            guard age >= TimeInterval(command.refreshSeconds ?? 10) else { continue }
            refreshing.insert(command.path)
            Task {
                let run = try? await self.run(command, arguments: [], timeout: 10)
                self.refreshing.remove(command.path)
                if let run { self.inline[command.path] = (ScriptCommand.lastLine(run.output), .now) }
                done()
            }
        }
    }
}
