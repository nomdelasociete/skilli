import AppKit
import SkilliCore
import SQLite3

/// The recordings as the launcher and Settings → Recorder list them
/// (docs/meeting-recorder-views.md, "Finding recordings", "Settings →
/// Recorder"): what each `meeting.json` says, kept in memory (titles,
/// dates, attendees, never the words), read off the main thread at
/// launch when there is a Recordings folder and again when one changes;
/// the words said through `RecordingIndex`. Delete after N days prunes
/// here, to the Trash.
@MainActor
@Observable
final class RecordingLibrary {
    private(set) var root: URL
    @ObservationIgnored private let index: RecordingIndex
    /// Newest first.
    private(set) var recordings: [(folder: String, record: MeetingRecord)] = []
    private(set) var isLoaded = false
    /// What it lists changed: the launcher (the pane observes it).
    @ObservationIgnored var onChange: (() -> Void)?
    /// Recordings moved between folders (`move`) so far, of how many.
    private(set) var moving: (done: Int, of: Int)?
    /// Moves that failed, by title, and why.
    private(set) var moveFailures: [String] = []
    @ObservationIgnored private var reading: Task<Void, Never>?

    @ObservationIgnored private var observer: NSObjectProtocol?

    init(root: URL, index: URL) {
        self.root = root
        self.index = RecordingIndex(url: index)
        observer = NotificationCenter.default.addObserver(forName: Recordings.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var summaries: [RecordingSummary] { recordings.map { RecordingSummary(folder: $0.folder, record: $0.record) } }

    func folder(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    /// Read again off the main thread (a few small files), then told.
    func reload() {
        reading?.cancel()
        let root = root
        reading = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { Self.read(root) }.value
            guard let self, !Task.isCancelled, self.root == root else { return }
            self.recordings = found
            self.isLoaded = true
            self.onChange?()
        }
    }

    /// Every recording in `root` by its folder's name and title, for a
    /// move: none when the folder was never made; a folder that cannot be
    /// listed throws (never read as empty). A recording is a folder with a
    /// `meeting.json`; one that cannot be read or decoded still moves with
    /// the others (named by its folder), never left behind.
    nonisolated private static func inventory(_ root: URL) throws -> [(String, String)] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let recordings = Recordings(root: root)
        return folders.compactMap { folder in
            if let record = recordings.read(folder) { return (folder.lastPathComponent, record.title) }
            let made = FileManager.default.fileExists(atPath: folder.appendingPathComponent(Recordings.record).path)
            return made ? (folder.lastPathComponent, folder.lastPathComponent) : nil
        }
    }

    nonisolated private static func read(_ root: URL) -> [(folder: String, record: MeetingRecord)] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let recordings = Recordings(root: root)
        return folders.compactMap { folder in recordings.read(folder).map { (folder.lastPathComponent, $0) } }
            .sorted { $0.record.started > $1.record.started }
    }

    // MARK: - Searching

    /// The words said: the recordings whose transcript holds every word
    /// typed (as prefixes, accents aside), with the words around the first
    /// match. The index catches up first (a transcript made, renamed or
    /// deleted since), off the main thread.
    func searchWords(_ text: String) async -> [(folder: String, snippet: String)] {
        let (index, root, folders) = (index, root, recordings.map(\.folder))
        return await Task.detached(priority: .userInitiated) {
            index.sync(root: root, folders: folders)
            return index.search(text)
        }.value
    }

    // MARK: - Delete after

    /// How many the next pass removes, as `retention` is now.
    func expiredCount(_ retention: RecordingRetention, now: Date = .now) -> Int {
        retention.expired(recordings, now: now).count
    }

    /// The expired ones to the Trash (at launch, then each hour; never as
    /// the setting changes), off the main thread. How many went.
    @discardableResult
    func prune(_ retention: RecordingRetention, now: Date = .now) async -> Int {
        let expired = retention.expired(recordings, now: now).map(folder)
        guard !expired.isEmpty else { return 0 }
        let trashed = await Task.detached(priority: .utility) {
            expired.filter { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }.count
        }.value
        Log.trace("Recorder: \(trashed) recordings older than \(retention.rawValue) moved to the Trash")
        reload()
        return trashed
    }

    // MARK: - Keep recordings in

    /// The recordings moved to `newRoot`, one by one, off the main thread,
    /// then the folder is the new one. One that cannot move stops it: those
    /// moved before it go back, so every recording stays in one folder and
    /// in the lists; `moveFailures` says why. Whether they all moved.
    @discardableResult
    func move(to newRoot: URL) async -> Bool {
        let oldRoot = root
        guard newRoot.standardizedFileURL != oldRoot.standardizedFileURL else { return true }
        moveFailures = []
        moving = (0, 0)
        onChange?()
        // What the folder holds now, read from it: the list in memory may not
        // be read yet, or be older than a recording made since. A folder that
        // cannot be read stops it (nothing moved, nothing hidden).
        let inventory = await Task.detached(priority: .utility) { Result { try Self.inventory(oldRoot) } }.value
        guard case .success(let names) = inventory else {
            if case .failure(let error) = inventory {
                moveFailures = ["The recordings' folder could not be read: \(error.localizedDescription) They stay where they were."]
            }
            moving = nil
            onChange?()
            return false
        }
        moving = (0, names.count)
        onChange?()
        var moved: [(from: String, to: String)] = []
        var failure: String?
        for (name, title) in names {
            #if SKILLI_SELFTEST
            if moveStepDelay > .zero { try? await Task.sleep(for: moveStepDelay) }
            #endif
            let result = await Task.detached(priority: .utility) { () -> Result<String, Error> in
                let manager = FileManager.default
                do {
                    try manager.createDirectory(at: newRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let target = RecordingFolder.free(name) { manager.fileExists(atPath: newRoot.appendingPathComponent($0).path) }
                    try manager.moveItem(at: oldRoot.appendingPathComponent(name), to: newRoot.appendingPathComponent(target))
                    return .success(target)
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let target): moved.append((name, target))
            case .failure(let error): failure = "“\(title)” could not move: \(error.localizedDescription)"
            }
            if failure != nil { break }
            moving = (moved.count, names.count)
            onChange?()
        }
        if let failure {
            // Back where they were, last first.
            let stranded = await Task.detached(priority: .utility) { () -> [String] in
                moved.reversed().compactMap { pair in
                    (try? FileManager.default.moveItem(at: newRoot.appendingPathComponent(pair.to), to: oldRoot.appendingPathComponent(pair.from))) == nil
                        ? pair.to : nil
                }
            }.value
            moveFailures = [failure + " The recordings stay where they were."]
                + stranded.map { "“\($0)” is left in the new folder: move it back in Finder." }
            moving = nil
            reload()
            return false
        }
        root = newRoot
        moving = nil
        reload()
        return true
    }

    /// The folder changed without a move (the self-test's own).
    func use(_ newRoot: URL) {
        root = newRoot
        reload()
    }

    #if SKILLI_SELFTEST
    /// Self-test: each recording takes this long to move (a recording asked
    /// for meanwhile).
    @ObservationIgnored var moveStepDelay: Duration = .zero
    #endif
}

/// The words said in each recording, for the launcher's search: one SQLite
/// FTS5 table on this Mac (as the clipboard's), filled from each
/// `transcript.json` and caught up before each search by its file's
/// date (a transcript made again, a recording renamed or deleted in
/// Finder). Searched off the main thread; calls serialized by a lock.
final class RecordingIndex: @unchecked Sendable {
    private let url: URL
    private var db: OpaquePointer?
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    deinit {
        sqlite3_close(db)
    }

    private func open() -> Bool {
        if db != nil { return true }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return false
        }
        // What was said is private: only the user reads the file.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return execute("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS transcripts (folder TEXT PRIMARY KEY, stamp REAL NOT NULL);
            CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts5 (folder UNINDEXED, text, tokenize = 'unicode61 remove_diacritics 2');
            """)
    }

    /// Each of `folders` in `root` as its transcript is now: added or read
    /// again when its file changed, gone when it has none.
    func sync(root: URL, folders: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard open() else { return }
        var known: [String: Double] = [:]
        query("SELECT folder, stamp FROM transcripts", []) { statement in
            if let folder = sqlite3_column_text(statement, 0) { known[String(cString: folder)] = sqlite3_column_double(statement, 1) }
        }
        var wanted: Set<String> = []
        for folder in folders {
            let file = root.appendingPathComponent(folder).appendingPathComponent("transcript.json")
            guard let stamp = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970
            else { continue }
            wanted.insert(folder)
            guard known[folder] != stamp else { continue }
            let text = (try? Data(contentsOf: file)).flatMap { try? MeetingTranscript.File.decode($0) }?.lines.map(\.text).joined(separator: "\n") ?? ""
            execute("BEGIN")
            run("DELETE FROM words WHERE folder = ?", [folder])
            run("INSERT INTO words (folder, text) VALUES (?, ?)", [folder, text])
            run("INSERT OR REPLACE INTO transcripts (folder, stamp) VALUES (?, ?)", [folder, String(stamp)])
            execute("COMMIT")
        }
        for gone in Set(known.keys).subtracting(wanted) {
            run("DELETE FROM words WHERE folder = ?", [gone])
            run("DELETE FROM transcripts WHERE folder = ?", [gone])
        }
    }

    /// The folders whose words hold every word of `text` (prefixes), best
    /// first, with six words around the match ("…for the third quarter is
    /// on…": a row's second line shows the match, not what led to it).
    func search(_ text: String, limit: Int = 30) -> [(folder: String, snippet: String)] {
        lock.lock()
        defer { lock.unlock() }
        guard open(), let match = ClipboardSearch.ftsQuery(text) else { return [] }
        var found: [(String, String)] = []
        query("SELECT folder, snippet(words, 1, '', '', '…', 6) FROM words WHERE words MATCH ? ORDER BY rank LIMIT \(limit)", [match]) { statement in
            guard let folder = sqlite3_column_text(statement, 0) else { return }
            let snippet = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            found.append((String(cString: folder), snippet.replacingOccurrences(of: "\n", with: " ")))
        }
        return found
    }

    // MARK: - SQLite

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func run(_ sql: String, _ values: [String]) {
        query(sql, values) { _ in }
    }

    /// `sql` with `values` bound as text (SQLite converts the numbers),
    /// `row` called for each row.
    private func query(_ sql: String, _ values: [String], row: (OpaquePointer?) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Log.actions.error("Recordings index: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, Self.transient)
        }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }
}
