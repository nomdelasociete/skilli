import AppKit
import Synchronization
import SkilliCore

/// What a shortcut is given to work on.
enum ShortcutInput: Equatable, Sendable {
    case none
    /// The text selected in the app in front, read as it runs.
    case selection
    /// Text read already: the launcher's selection, what Ask was asked on.
    case text(String)
}

/// The user's shortcuts in Apple's Shortcuts app (docs/apps.md), read with
/// Apple's own tool (`shortcuts list`), and run with it (`shortcuts run`):
/// their output comes back to the card, their input from the selection.
enum AppleShortcuts {
    /// What the last read found; nil before the first. A key never runs the
    /// tool: rows use what was read last.
    private static let known = Mutex<[AppleShortcut]?>(nil)

    /// The shortcuts as last read (none before the first read).
    static func all() -> [AppleShortcut] {
        known.withLock { $0 } ?? []
    }

    /// A read is running: the launcher opened again meanwhile waits for none.
    private static let reading = Mutex(false)

    /// Reads them again (~10 ms, Apple's tool): off the main thread at
    /// launch and as the launcher opens, with the radios. Kept as they
    /// were when the tool fails, or while another read runs.
    @discardableResult
    static func read() -> [AppleShortcut] {
        guard reading.withLock({ running -> Bool in
            if running { return false }
            running = true
            return true
        }) else { return all() }
        defer { reading.withLock { $0 = false } }
        let started = ContinuousClock.now
        guard let output = try? runTool(AppleShortcut.listArguments, input: nil, timeout: 10), output.status == 0 else {
            Log.trace("Shortcuts: the list could not be read")
            return all()
        }
        let found = AppleShortcut.list(String(decoding: output.output, as: UTF8.self))
        let changed = known.withLock { known -> Bool in
            defer { known = found }
            return known.map { $0.map(\.id) != found.map(\.id) || $0.map(\.name) != found.map(\.name) } ?? true
        }
        if changed { Log.trace("Shortcuts: \(found.count) read in \((ContinuousClock.now - started).compact)") }
        return found
    }

    /// The shortcuts as last read, to see a change.
    static var summary: [String] {
        all().map { "\($0.id) \($0.name)" }
    }

    /// The shortcut as last read, with its name now (a key saved before
    /// knows only its identifier).
    static func current(_ shortcut: AppleShortcut) -> AppleShortcut {
        all().first { $0 == shortcut } ?? shortcut
    }

    /// Its name as last read, else as saved, else what it is.
    static func name(of shortcut: AppleShortcut) -> String {
        let name = current(shortcut).name
        return name.isEmpty ? "Shortcut" : name
    }

    @MainActor private static var shortcutsIcon: NSImage?

    /// Shortcuts' own icon, as rows show apps' (32 pt): every shortcut runs
    /// there.
    @MainActor
    static var icon: NSImage? {
        if let shortcutsIcon { return shortcutsIcon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppleShortcut.bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        shortcutsIcon = icon
        return icon
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// How long a run may take: a shortcut can wait for the user (Ask for
    /// Input, a menu).
    static let timeout: TimeInterval = 300

    /// Runs it, `input` given as text on the standard input; the text it
    /// gave back, nil for nothing or what is not text. Throws what
    /// Shortcuts said when it failed.
    static func run(_ shortcut: AppleShortcut, input: String?, timeout: TimeInterval = timeout) async throws -> String? {
        let name = name(of: shortcut)
        Log.trace("Shortcut “\(name)” run\(input == nil ? "" : " with the selection")")
        let ran = try await Task.detached(priority: .userInitiated) {
            try runTool(shortcut.runArguments, input: input.map { Data($0.utf8) }, timeout: timeout)
        }.value
        guard ran.status == 0 else {
            let said = AppleShortcut.failure(ran.errors)
            throw Failure(message: said.map { "“\(name)” stopped: \($0)" } ?? "“\(name)” stopped (Shortcuts said \(ran.status)).")
        }
        return AppleShortcut.shownOutput(ran.output)
    }

    /// Apple's tool with `arguments`: its output and errors apart, and its
    /// exit status. Blocks: off the main thread only. Stopped after
    /// `timeout`, with what it started, killed 3 s later if that did not
    /// stop it (as `ChildProcess.run` stops a skillie): its output must end.
    private static func runTool(_ arguments: [String], input: Data?, timeout: TimeInterval) throws -> (output: Data, errors: String, status: Int32) {
        let child = ChildProcess()
        child.process.executableURL = URL(fileURLWithPath: AppleShortcut.tool)
        child.process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        child.process.standardOutput = output
        child.process.standardError = errors
        let stdin = input.map { _ in Pipe() }
        child.process.standardInput = stdin ?? FileHandle.nullDevice
        try child.process.run()
        let stop = DispatchWorkItem {
            child.terminateGroup()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { child.terminateGroup(SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        defer { stop.cancel() }
        // Written and read on their own: a big input or a big output must
        // not wait for the other.
        if let stdin, let input {
            DispatchQueue.global(qos: .userInitiated).async {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
            }
        }
        let said = ErrorsRead()
        let readErrors = DispatchGroup()
        readErrors.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            said.data = errors.fileHandleForReading.readDataToEndOfFile()
            readErrors.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        readErrors.wait()
        child.closedOutput()
        child.process.waitUntilExit()
        return (data, String(decoding: said.data, as: UTF8.self), child.process.terminationStatus)
    }

    /// Written once by the queue reading the errors, read after it left
    /// the group.
    private final class ErrorsRead: @unchecked Sendable {
        var data = Data()
    }
}
