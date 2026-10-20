import AppKit
import SkilliCore

/// Backups of what skil.li keeps (Settings → Backup, "Back Up skil.li
/// Now"): its folder in Application Support, minus the socket agents use
/// and the clipboard history (never in a backup), plus its settings, zipped
/// into the folder the user chose, on the schedule chosen. API keys and
/// sensitive form fields stay in the Keychain: never in a backup.
///
/// Nothing polls: one timer waits for the next backup due; it is set again
/// when the Mac wakes or a backup setting changes. Restoring backs up what
/// is there first (so it can be undone), puts the files and settings back,
/// and skil.li opens again.
@MainActor
@Observable
final class BackupCenter {
    /// What is backed up: skil.li's folder and the defaults its settings
    /// live in. Self-tests point both at scratch copies.
    struct Source: Sendable {
        let folder: URL
        let defaultsSuite: String?

        static var live: Source {
            Source(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("skil.li", isDirectory: true), defaultsSuite: nil)
        }
    }

    struct Backup: Identifiable, Equatable {
        let url: URL
        let date: Date
        let bytes: Int64
        var id: String { url.path }
    }

    enum Failure: LocalizedError {
        case noFolder
        case busy
        case tool(String)
        case notABackup

        var errorDescription: String? {
            switch self {
            case .noFolder: "Choose where backups go in Settings → Backup."
            case .busy: "A backup is already being made."
            case let .tool(message): message
            case .notABackup: "This file is not a skil.li backup."
            }
        }
    }

    /// A backup being made or put back: Settings shows it.
    private(set) var isWorking = false
    /// Why the last scheduled backup failed, until one works.
    private(set) var lastError: String?
    /// Goes up each time the folder's backups change: Settings follows.
    private(set) var revision = 0

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let source: Source
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// When the scheduled one fires next (self-tests).
    var nextBackup: Date? { timer?.fireDate }
    /// What is backed up (self-tests seed and check their scratch copies).
    var sourceFolder: URL { source.folder }
    var sourceDefaults: UserDefaults { defaults }

    init(preferences: Preferences, source: Source = .live) {
        self.preferences = preferences
        self.source = source
        lastError = UserDefaults.standard.string(forKey: Self.lastErrorKey)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    /// The folder chosen in Settings, nil until one is.
    var folder: URL? {
        preferences.backupFolder.isEmpty ? nil : URL(fileURLWithPath: preferences.backupFolder, isDirectory: true)
    }

    /// The backups in the folder, newest first.
    func backups() -> [Backup] {
        guard let folder else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.compactMap { url in
            BackupPlan.date(fromName: url.lastPathComponent).map { date in
                Backup(url: url, date: date, bytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            }
        }
        .sorted { $0.date > $1.date }
    }

    /// Sets the one timer for the next backup due; a backup missed while
    /// the Mac was off runs a minute after skil.li starts or wakes.
    func refresh(now: Date = .now) {
        timer?.invalidate()
        timer = nil
        guard folder != nil, let due = BackupPlan.nextDue(after: backups().first?.date, schedule: preferences.backupSchedule, now: now)
        else { return }
        let timer = Timer(fire: max(due, now.addingTimeInterval(60)), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task {
                    _ = try? await self.backUpNow()
                    self.refresh()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Copies, zips and keeps only the newest as set. The backup's file.
    @discardableResult
    func backUpNow() async throws -> URL {
        guard let folder else { throw Failure.noFolder }
        guard !isWorking else { throw Failure.busy }
        isWorking = true
        defer {
            isWorking = false
            revision += 1
        }
        let settings = try PropertyListSerialization.data(fromPropertyList: exportedSettings(), format: .xml, options: 0)
        let skipped = BackupPlan.neverCopied
        // Two in the same second (a restore's backup of now) keep both.
        var stamp = Date.now
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(BackupPlan.name(at: stamp)).path) {
            stamp.addTimeInterval(1)
        }
        let name = BackupPlan.name(at: stamp)
        let from = source.folder
        do {
            let url = try await Task.detached(priority: .utility) {
                try Self.write(from: from, skipping: skipped, settings: settings, name: name, into: folder)
            }.value
            let keep = preferences.backupKeep
            for old in BackupPlan.expired(backups().map { ($0.url, $0.date) }, keep: keep > 0 ? keep : nil) {
                try? FileManager.default.removeItem(at: old)
            }
            record(error: nil)
            Log.actions.notice("Backed up skil.li to \(url.lastPathComponent, privacy: .public)")
            return url
        } catch {
            record(error: error.localizedDescription)
            throw error
        }
    }

    /// What a backup holds, in the user's words, for the card before a
    /// restore: "31 settings", "12 snippets"…
    func contents(of backup: URL) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let unpacked = try Self.unpack(backup)
            defer { try? FileManager.default.removeItem(at: unpacked.staging) }
            let count = (try? PropertyListSerialization.propertyList(from: unpacked.settings, format: nil) as? [String: Any])?.count ?? 0
            return BackupPlan.summary(of: unpacked.folder, preferenceCount: count)
        }.value
    }

    /// Puts a backup back: unpacked first, then what is there now is
    /// backed up (when a folder is set), then skil.li's files and settings
    /// are replaced. The caller opens skil.li again so every part reads
    /// them.
    func restore(_ backup: URL) async throws {
        guard !isWorking else { throw Failure.busy }
        let unpacked = try await Task.detached(priority: .userInitiated) { try Self.unpack(backup) }.value
        defer { try? FileManager.default.removeItem(at: unpacked.staging) }
        if folder != nil { try await backUpNow() }
        isWorking = true
        defer {
            isWorking = false
            revision += 1
        }
        let target = source.folder
        let restored = unpacked.folder
        try await Task.detached(priority: .userInitiated) { try Self.replace(target, with: restored) }.value
        let settings = unpacked.settings
        importSettings((try? PropertyListSerialization.propertyList(from: settings, format: nil) as? [String: Any]) ?? [:])
        Log.actions.notice("Restored skil.li from \(backup.lastPathComponent, privacy: .public)")
    }

    // MARK: - Settings

    private var defaults: UserDefaults {
        source.defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// skil.li's own settings, without this Mac's state.
    private func exportedSettings() -> [String: Any] {
        defaults.dictionaryRepresentation().filter { key, _ in
            key.hasPrefix(Self.settingsPrefix) && !Preferences.machineKeys.contains(key)
        }
    }

    /// The backup's settings replace skil.li's (this Mac's state stays).
    private func importSettings(_ settings: [String: Any]) {
        let defaults = defaults
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.settingsPrefix) && !Preferences.machineKeys.contains(key) && settings[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings where key.hasPrefix(Self.settingsPrefix) && !Preferences.machineKeys.contains(key) {
            defaults.set(value, forKey: key)
        }
    }

    private func record(error: String?) {
        lastError = error
        UserDefaults.standard.set(error, forKey: Self.lastErrorKey)
    }

    // MARK: - Files (off the main thread)

    /// The backup's folder in a scratch place, zipped with ditto (as the
    /// Finder does) into `name` beside the others.
    nonisolated private static func write(from source: URL, skipping skipped: Set<String>, settings: Data, name: String,
                                          into folder: URL) throws -> URL {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appendingPathComponent("skilli-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: staging) }
        let root = staging.appendingPathComponent((name as NSString).deletingPathExtension, isDirectory: true)
        let copy = root.appendingPathComponent("skil.li", isDirectory: true)
        try files.createDirectory(at: copy, withIntermediateDirectories: true)
        for item in (try? files.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        where !skipped.contains(item.lastPathComponent) {
            try files.copyItem(at: item, to: copy.appendingPathComponent(item.lastPathComponent))
        }
        try settings.write(to: root.appendingPathComponent(settingsFile))
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(name + ".partial")
        let target = folder.appendingPathComponent(name)
        try? files.removeItem(at: partial)
        try ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, partial.path])
        if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
        try files.moveItem(at: partial, to: target)
        return target
    }

    /// A backup unzipped in a scratch place: its copy of skil.li's folder
    /// and its settings (a property list).
    nonisolated private static func unpack(_ backup: URL) throws -> (staging: URL, folder: URL, settings: Data) {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appendingPathComponent("skilli-restore-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try ditto(["-x", "-k", backup.path, staging.path])
            let roots = try files.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }
            guard let root = roots.first(where: { files.fileExists(atPath: $0.appendingPathComponent(settingsFile).path) }) else {
                throw Failure.notABackup
            }
            let settings = try Data(contentsOf: root.appendingPathComponent(settingsFile))
            return (staging, root.appendingPathComponent("skil.li", isDirectory: true), settings)
        } catch {
            try? files.removeItem(at: staging)
            throw error
        }
    }

    /// skil.li's folder gets the backup's items; the socket and the
    /// clipboard history stay as they are (an older backup's clipboard
    /// history is left out).
    nonisolated private static func replace(_ target: URL, with backup: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: target, withIntermediateDirectories: true)
        let current = (try? files.contentsOfDirectory(atPath: target.path)) ?? []
        let restored = (try? files.contentsOfDirectory(atPath: backup.path)) ?? []
        let plan = BackupPlan.restore(current: current, backup: restored)
        for name in plan.remove {
            try files.removeItem(at: target.appendingPathComponent(name))
        }
        for name in plan.copy {
            try files.copyItem(at: backup.appendingPathComponent(name), to: target.appendingPathComponent(name))
        }
    }

    nonisolated private static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.tool(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "The backup could not be zipped." : message)
        }
    }

    nonisolated private static let settingsFile = "Settings.plist"
    private static let settingsPrefix = "Preferences."
    private static let lastErrorKey = "Backup.lastError"
}
