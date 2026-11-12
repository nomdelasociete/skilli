import Foundation
import SkilliCore
import SQLite3

/// The clipboard history on disk: one SQLite database, searched with FTS5
/// over the text, what OCR read in images and what Jev tagged them as
/// (`ImageTags`), a folder of images, and one of link previews named by
/// their copy's id (`LinkPreviewCache`), removed with it.
/// Only on this Mac, in a folder only the user can read.
///
/// Calls are short and serialized by a lock: the launcher searches on the
/// main thread (well under a millisecond), OCR writes from a background one.
final class ClipboardStore: @unchecked Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable {
            case text
            case image
            /// Files copied in Finder: `text` holds their paths, one a line.
            case files
        }

        let id: Int64
        let kind: Kind
        let text: String
        let ocr: String?
        /// The image's file name in `images/`.
        let image: String?
        /// "1280×720" for an image.
        let size: String?
        let app: String?
        let appName: String?
        let copiedAt: Date
        /// How many times the same content was copied.
        var copies: Int = 1
        /// What Jev saw in an image (`ImageTags.words`); nil until asked.
        var tags: String?
        /// When it was pinned (⌘K → Pin): first in the list, never
        /// removed by Keep copies for. Nil: not pinned.
        var pinnedAt: Date?
        var isPinned: Bool { pinnedAt != nil }
        /// What it is (`ClipboardKind`), kept when copied; nil on a copy
        /// of before, until `fillKinds` reads it.
        var value: String?
        /// What it is: as kept, or read now.
        var what: ClipboardKind { value.flatMap(ClipboardKind.init(rawValue:)) ?? .of(stored: kind.rawValue, text: text) }
    }

    /// The list narrowed (⌘K → Show Only…): one kind, or one app's copies.
    enum Only: Equatable, Sendable {
        case kind(ClipboardKind)
        case app(id: String, name: String)

        /// "Links", "Safari": after "Clipboard ·" in the field's chip.
        var title: String {
            switch self {
            case .kind(let kind): kind.plural
            case .app(_, let name): name
            }
        }
    }

    /// What the history saw on the pasteboard, before it has an id.
    struct NewItem: Sendable {
        var kind: Item.Kind
        var text: String
        /// PNG, for an image.
        var imageData: Data?
        var size: String?
        /// Every format the app copied it with (RTF, cells, a slide's
        /// object…), in its order, to paste it back as it was
        /// (`ClipboardFormats`).
        var formats: [ClipboardFormats.Format]?
        var app: String?
        var appName: String?
        /// Same content, same hash: copying it again moves it to the top.
        var hash: String
    }

    enum StoreError: LocalizedError {
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case .sqlite(let message): "Clipboard history: \(message)"
            }
        }
    }

    let folder: URL
    var imagesFolder: URL { folder.appendingPathComponent("images", isDirectory: true) }
    var previewsFolder: URL { folder.appendingPathComponent("previews", isDirectory: true) }
    private var db: OpaquePointer?
    private let lock = NSLock()

    /// `~/Library/Application Support/skil.li/Clipboard`.
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li/Clipboard", isDirectory: true)
    }

    init(folder: URL) throws {
        self.folder = folder
        let manager = FileManager.default
        try manager.createDirectory(at: folder.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)
        try manager.createDirectory(at: folder.appendingPathComponent("previews", isDirectory: true), withIntermediateDirectories: true)
        // What people copy is private: only the user reads this folder.
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let path = folder.appendingPathComponent("history.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(db)
            db = nil
            throw StoreError.sqlite(message)
        }
        try execute("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY,
                kind TEXT NOT NULL,
                text TEXT NOT NULL DEFAULT '',
                ocr TEXT,
                image TEXT,
                size TEXT,
                formats BLOB,
                app TEXT,
                app_name TEXT,
                hash TEXT NOT NULL UNIQUE,
                copied REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS items_copied ON items (copied DESC);
            CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5 (
                text, ocr, content = 'items', content_rowid = 'id',
                tokenize = 'unicode61 remove_diacritics 2'
            );
            CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
                INSERT INTO items_fts (rowid, text, ocr) VALUES (new.id, new.text, coalesce(new.ocr, ''));
            END;
            CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
                INSERT INTO items_fts (items_fts, rowid, text, ocr) VALUES ('delete', old.id, old.text, coalesce(old.ocr, ''));
            END;
            CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE OF text, ocr ON items BEGIN
                INSERT INTO items_fts (items_fts, rowid, text, ocr) VALUES ('delete', old.id, old.text, coalesce(old.ocr, ''));
                INSERT INTO items_fts (rowid, text, ocr) VALUES (new.id, new.text, coalesce(new.ocr, ''));
            END;
            """)
        // Added after the first version: how many times it was copied.
        if try !strings("SELECT name FROM pragma_table_info('items')", []).contains("copies") {
            try execute("ALTER TABLE items ADD COLUMN copies INTEGER NOT NULL DEFAULT 1;")
        }
        // Added later: when a copy was pinned (docs/clipboard-pins-filter-actions.md).
        if try !strings("SELECT name FROM pragma_table_info('items')", []).contains("pinned") {
            try execute("ALTER TABLE items ADD COLUMN pinned REAL;")
        }
        // Added later: what the copy is, to show one kind at a time.
        if try !strings("SELECT name FROM pragma_table_info('items')", []).contains("value") {
            try execute("ALTER TABLE items ADD COLUMN value TEXT;")
        }
        // Added later: what Jev tagged an image as, searched like its text.
        if try !strings("SELECT name FROM pragma_table_info('items')", []).contains("tags") {
            try execute("ALTER TABLE items ADD COLUMN tags TEXT;")
        }
        if try !strings("SELECT name FROM pragma_table_info('items_fts')", []).contains("tags") {
            try execute("""
                DROP TRIGGER IF EXISTS items_ai;
                DROP TRIGGER IF EXISTS items_ad;
                DROP TRIGGER IF EXISTS items_au;
                DROP TABLE IF EXISTS items_fts;
                CREATE VIRTUAL TABLE items_fts USING fts5 (
                    text, ocr, tags, content = 'items', content_rowid = 'id',
                    tokenize = 'unicode61 remove_diacritics 2'
                );
                CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
                    INSERT INTO items_fts (rowid, text, ocr, tags) VALUES (new.id, new.text, coalesce(new.ocr, ''), coalesce(new.tags, ''));
                END;
                CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
                    INSERT INTO items_fts (items_fts, rowid, text, ocr, tags)
                        VALUES ('delete', old.id, old.text, coalesce(old.ocr, ''), coalesce(old.tags, ''));
                END;
                CREATE TRIGGER items_au AFTER UPDATE OF text, ocr, tags ON items BEGIN
                    INSERT INTO items_fts (items_fts, rowid, text, ocr, tags)
                        VALUES ('delete', old.id, old.text, coalesce(old.ocr, ''), coalesce(old.tags, ''));
                    INSERT INTO items_fts (rowid, text, ocr, tags) VALUES (new.id, new.text, coalesce(new.ocr, ''), coalesce(new.tags, ''));
                END;
                INSERT INTO items_fts (items_fts) VALUES ('rebuild');
                """)
        }
        // Added later: the same four read by threes of letters, so a word
        // is found from inside too (docs/clipboard-rows-and-search.md).
        // Kept by its own triggers; made and filled once on an older file.
        // Not made (an SQLite without the tokenizer): the search stays
        // the words' one.
        do {
            if try strings("SELECT name FROM sqlite_master WHERE name = 'items_sub'", []).isEmpty {
                // One transaction: the table is there only whole, with its
                // triggers and every copy in it. Stopped half way (a full
                // disk, the app quit while a long history is read), nothing
                // of it stays and the next launch makes it again.
                try execute("BEGIN IMMEDIATE;")
                do {
                    try execute(Self.insideWordsIndex)
                    try execute("COMMIT;")
                } catch {
                    try? execute("ROLLBACK;")
                    throw error
                }
            }
            findsInsideWords = true
        } catch {
            Log.actions.error("Clipboard history, no search inside words: \(error.localizedDescription, privacy: .public)")
        }
        // The words the word index holds, read from it (nothing stored):
        // what a mistyped word is compared with (`close`).
        do {
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS items_words USING fts5vocab(items_fts, row);")
            findsCloseWords = true
        } catch {
            Log.actions.error("Clipboard history, no close words: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let insideWordsIndex = """
                    CREATE VIRTUAL TABLE items_sub USING fts5 (
                        text, ocr, tags, app_name, content = 'items', content_rowid = 'id',
                        tokenize = 'trigram remove_diacritics 1'
                    );
                    CREATE TRIGGER items_sub_ai AFTER INSERT ON items BEGIN
                        INSERT INTO items_sub (rowid, text, ocr, tags, app_name)
                            VALUES (new.id, new.text, coalesce(new.ocr, ''), coalesce(new.tags, ''), coalesce(new.app_name, ''));
                    END;
                    CREATE TRIGGER items_sub_ad AFTER DELETE ON items BEGIN
                        INSERT INTO items_sub (items_sub, rowid, text, ocr, tags, app_name)
                            VALUES ('delete', old.id, old.text, coalesce(old.ocr, ''), coalesce(old.tags, ''), coalesce(old.app_name, ''));
                    END;
                    CREATE TRIGGER items_sub_au AFTER UPDATE OF text, ocr, tags, app_name ON items BEGIN
                        INSERT INTO items_sub (items_sub, rowid, text, ocr, tags, app_name)
                            VALUES ('delete', old.id, old.text, coalesce(old.ocr, ''), coalesce(old.tags, ''), coalesce(old.app_name, ''));
                        INSERT INTO items_sub (rowid, text, ocr, tags, app_name)
                            VALUES (new.id, new.text, coalesce(new.ocr, ''), coalesce(new.tags, ''), coalesce(new.app_name, ''));
                    END;
                    INSERT INTO items_sub (items_sub) VALUES ('rebuild');
                    """

    /// The trigram index is there: words are found from inside too.
    private(set) var findsInsideWords = false
    /// The index's own words can be read (`items_words`).
    private(set) var findsCloseWords = false

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Writing

    /// Keeps a copy, or moves the same content back to the top. Returns the
    /// item and whether it is new (an image then wants OCR).
    @discardableResult
    func add(_ new: NewItem, at date: Date = .now) throws -> (item: Item, isNew: Bool) {
        guard let added = try add(new, at: date, ifClears: nil) else { throw StoreError.sqlite("the copy was not kept") }
        return added
    }

    /// How many times the history was cleared since it opened: a copy
    /// being made off the main thread when Clear History ran is not
    /// kept after it (`add(_:at:ifClears:)`).
    var clears: Int {
        lock.lock()
        defer { lock.unlock() }
        return cleared
    }

    private var cleared = 0

    /// The same content already kept, counted once more. It moves to
    /// `date` with where it came from only when that is its latest copy:
    /// two copies of it made off the main thread can end out of order.
    /// Its formats are then this copy's, when it has some: the same text
    /// copied plain first, then from a table, pastes back as cells. A
    /// plain copy of it after (skil.li's own ⇧↩ is one) keeps those it
    /// had.
    private func again(_ new: NewItem, at date: Date) throws -> (item: Item, isNew: Bool)? {
        guard let existing = try rows("SELECT \(Self.columns) FROM items WHERE hash = ?", [.text(new.hash)]).first else { return nil }
        if date >= existing.copiedAt {
            let formats = new.formats.flatMap(ClipboardFormats.encoded)
            try run("UPDATE items SET copied = ?, app = ?, app_name = ?, formats = coalesce(?, formats), copies = copies + 1 WHERE id = ?",
                    [.double(date.timeIntervalSince1970), .optionalText(new.app), .optionalText(new.appName),
                     formats.map(Value.blob) ?? .null, .int(existing.id)])
        } else {
            try run("UPDATE items SET copies = copies + 1 WHERE id = ?", [.int(existing.id)])
        }
        return (try rows("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(existing.id)])[0], false)
    }

    /// `add`, unless the history was cleared since `ifClears` was read
    /// (nil then, nothing kept). A picture's file is written outside the
    /// lock: a search on the main thread does not wait for it.
    func add(_ new: NewItem, at date: Date, ifClears: Int?) throws -> (item: Item, isNew: Bool)? {
        lock.lock()
        do {
            if let ifClears, ifClears != cleared {
                lock.unlock()
                return nil
            }
            if let existing = try again(new, at: date) {
                lock.unlock()
                return existing
            }
        } catch {
            lock.unlock()
            throw error
        }
        lock.unlock()
        var image: String?
        if let data = new.imageData {
            let name = UUID().uuidString + ".png"
            try data.write(to: imagesFolder.appendingPathComponent(name), options: .atomic)
            image = name
        }
        lock.lock()
        defer { lock.unlock() }
        // Cleared, or the same content kept, while the file was written.
        var inserted = false
        defer { if !inserted, let image { removeImages([image]) } }
        if let ifClears, ifClears != cleared { return nil }
        if let existing = try again(new, at: date) { return existing }
        let formats = new.formats.flatMap(ClipboardFormats.encoded)
        try run("""
            INSERT INTO items (kind, text, image, size, formats, app, app_name, hash, copied, value)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(new.kind.rawValue), .text(new.text), .optionalText(image), .optionalText(new.size),
                  formats.map(Value.blob) ?? .null, .optionalText(new.app), .optionalText(new.appName),
                  .text(new.hash), .double(date.timeIntervalSince1970),
                  .text(ClipboardKind.of(stored: new.kind.rawValue, text: new.text).rawValue)])
        let id = sqlite3_last_insert_rowid(db)
        inserted = true
        return (try rows("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(id)])[0], true)
    }

    /// What OCR read in an image, searchable from then on.
    func setOCR(_ text: String, for id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        try run("UPDATE items SET ocr = ? WHERE id = ?", [.text(text), .int(id)])
    }

    /// What Jev saw in an image (`ImageTags.words`), searchable from then on.
    func setTags(_ words: String, for id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        try run("UPDATE items SET tags = ? WHERE id = ?", [.text(words), .int(id)])
    }

    /// ⌘K → Pin, Unpin. Returns the copy as it is now; nil when it is gone.
    @discardableResult
    func setPinned(_ pinned: Bool, for id: Int64, at date: Date = .now) throws -> Item? {
        lock.lock()
        defer { lock.unlock() }
        try run("UPDATE items SET pinned = ? WHERE id = ?", [pinned ? .double(date.timeIntervalSince1970) : .null, .int(id)])
        return try rows("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(id)]).first
    }

    /// The pinned copies, in the order pinned.
    func pinned() -> [Item] {
        lock.lock()
        defer { lock.unlock() }
        return (try? rows("SELECT \(Self.columns) FROM items WHERE pinned IS NOT NULL ORDER BY pinned, id", [])) ?? []
    }

    func delete(_ id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        let images = try strings("SELECT image FROM items WHERE id = ? AND image IS NOT NULL", [.int(id)])
        try run("DELETE FROM items WHERE id = ?", [.int(id)])
        removeImages(images)
        removePreviews(of: [id])
    }

    /// A copy forgotten, all of it (its row, its image, its link preview),
    /// held in memory only while ⌘Z can bring it back; nothing of it stays
    /// on disk meanwhile.
    struct Forgotten: Sendable {
        let item: Item
        fileprivate let hash: String
        fileprivate let formats: Data?
        fileprivate let imageData: Data?
        fileprivate let previews: [String: Data]
    }

    /// Deletes it as `delete` does, and returns what `restore` needs.
    func forget(_ id: Int64) throws -> Forgotten? {
        lock.lock()
        defer { lock.unlock() }
        guard let item = try rows("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(id)]).first else { return nil }
        guard let statement = try prepare("SELECT hash, formats FROM items WHERE id = ?", [.int(id)]) else { return nil }
        var hash = ""
        var formats: Data?
        if sqlite3_step(statement) == SQLITE_ROW {
            hash = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            if let bytes = sqlite3_column_blob(statement, 1) { formats = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1))) }
        }
        sqlite3_finalize(statement)
        let imageData = item.image.flatMap { try? Data(contentsOf: imagesFolder.appendingPathComponent($0)) }
        var previews: [String: Data] = [:]
        for name in LinkPreviewCache.files(of: id) {
            if let data = try? Data(contentsOf: previewsFolder.appendingPathComponent(name)) { previews[name] = data }
        }
        try run("DELETE FROM items WHERE id = ?", [.int(id)])
        removeImages(item.image.map { [$0] } ?? [])
        removePreviews(of: [id])
        return Forgotten(item: item, hash: hash, formats: formats, imageData: imageData, previews: previews)
    }

    /// Back as it was: the same id (a new copy took it meanwhile: another
    /// one, without its link preview, which is read again), its image and
    /// preview files. The same content copied again meanwhile is already
    /// there: nothing doubles. Returns the copy as it is now.
    @discardableResult
    func restore(_ forgotten: Forgotten) throws -> Item {
        lock.lock()
        defer { lock.unlock() }
        let old = forgotten.item
        if let existing = try rows("SELECT \(Self.columns) FROM items WHERE hash = ?", [.text(forgotten.hash)]).first {
            // Copied again meanwhile: that row stays, pinned as the
            // forgotten one was.
            guard let pinned = old.pinnedAt, !existing.isPinned else { return existing }
            try run("UPDATE items SET pinned = ? WHERE id = ?", [.double(pinned.timeIntervalSince1970), .int(existing.id)])
            return try rows("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(existing.id)])[0]
        }
        let idFree = try int64s("SELECT id FROM items WHERE id = ?", [.int(old.id)]).isEmpty
        if let name = old.image, let data = forgotten.imageData {
            try data.write(to: imagesFolder.appendingPathComponent(name), options: .atomic)
        }
        try run("""
            INSERT INTO items (id, kind, text, ocr, image, size, formats, app, app_name, hash, copied, copies, tags, pinned, value)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [idFree ? .int(old.id) : .null, .text(old.kind.rawValue), .text(old.text), .optionalText(old.ocr), .optionalText(old.image),
                  .optionalText(old.size), forgotten.formats.map(Value.blob) ?? .null, .optionalText(old.app), .optionalText(old.appName),
                  .text(forgotten.hash), .double(old.copiedAt.timeIntervalSince1970), .int(Int64(old.copies)), .optionalText(old.tags),
                  old.pinnedAt.map { .double($0.timeIntervalSince1970) } ?? .null, .text(old.what.rawValue)])
        let id = sqlite3_last_insert_rowid(db)
        if idFree {
            for (name, data) in forgotten.previews {
                try? data.write(to: previewsFolder.appendingPathComponent(name), options: .atomic)
            }
        }
        return try rows("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(id)])[0]
    }

    /// Drops what was copied before `cutoff`, but for the pinned copies.
    /// Returns the ids that went.
    @discardableResult
    func prune(before cutoff: Date) throws -> [Int64] {
        lock.lock()
        defer { lock.unlock() }
        let images = try strings("SELECT image FROM items WHERE copied < ? AND pinned IS NULL AND image IS NOT NULL", [.double(cutoff.timeIntervalSince1970)])
        let ids = try int64s("SELECT id FROM items WHERE copied < ? AND pinned IS NULL", [.double(cutoff.timeIntervalSince1970)])
        try run("DELETE FROM items WHERE copied < ? AND pinned IS NULL", [.double(cutoff.timeIntervalSince1970)])
        removeImages(images)
        removePreviews(of: ids)
        return ids
    }

    /// How many were copied before `cutoff`: what the next prune removes.
    func count(before cutoff: Date) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = try? prepare("SELECT count(*) FROM items WHERE copied < ? AND pinned IS NULL", [.double(cutoff.timeIntervalSince1970)]) else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        cleared += 1
        try run("DELETE FROM items", [])
        try execute("INSERT INTO items_fts (items_fts) VALUES ('rebuild');")
        if findsInsideWords { try execute("INSERT INTO items_sub (items_sub) VALUES ('rebuild');") }
        try execute("VACUUM;")
        let manager = FileManager.default
        for file in ((try? manager.contentsOfDirectory(at: imagesFolder, includingPropertiesForKeys: nil)) ?? [])
            + ((try? manager.contentsOfDirectory(at: previewsFolder, includingPropertiesForKeys: nil)) ?? []) {
            try? manager.removeItem(at: file)
        }
    }

    /// The copies of before `value` was kept: what each is, read once, a
    /// couple of hundred at a time. Off the main thread; until it is
    /// done, Show Only misses the ones not read yet.
    func fillKinds() {
        while true {
            lock.lock()
            var unread: [(id: Int64, kind: String, text: String)] = []
            if let statement = try? prepare("SELECT id, kind, substr(text, 1, 4100) FROM items WHERE value IS NULL LIMIT 200", []) {
                while sqlite3_step(statement) == SQLITE_ROW {
                    unread.append((sqlite3_column_int64(statement, 0),
                                   sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "text",
                                   sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""))
                }
                sqlite3_finalize(statement)
            }
            lock.unlock()
            guard !unread.isEmpty else { return }
            let read = unread.map { ($0.id, ClipboardKind.of(stored: $0.kind, text: $0.text).rawValue) }
            lock.lock()
            var failed = false
            // One write to the disk for the lot.
            try? execute("BEGIN;")
            for (id, value) in read {
                do { try run("UPDATE items SET value = ? WHERE id = ?", [.text(value), .int(id)]) } catch { failed = true }
            }
            do { try execute("COMMIT;") } catch {
                try? execute("ROLLBACK;")
                failed = true
            }
            lock.unlock()
            // A write that fails would be read again for ever.
            if failed { return }
        }
    }

    /// Link previews whose copy is gone (removed while skil.li was not
    /// running, or by an older version): removed. Off the main thread.
    func sweepPreviews() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: previewsFolder.path)) ?? []
        guard !names.isEmpty else { return }
        lock.lock()
        let ids = Set((try? int64s("SELECT id FROM items", [])) ?? [])
        lock.unlock()
        for name in LinkPreviewCache.orphans(among: names, kept: ids) {
            try? FileManager.default.removeItem(at: previewsFolder.appendingPathComponent(name))
        }
    }

    private func removePreviews(of ids: [Int64]) {
        for id in ids {
            for name in LinkPreviewCache.files(of: id) {
                try? FileManager.default.removeItem(at: previewsFolder.appendingPathComponent(name))
            }
        }
    }

    private func removeImages(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: imagesFolder.appendingPathComponent(name))
        }
    }

    // MARK: - Reading

    /// Newest first; words of 3 letters or more are found anywhere, inside
    /// words too, in the text, what OCR read, an image's tags and the
    /// app's name; with a shorter word, words match as prefixes, in the
    /// text and OCR. Accents ignored ("reunion" finds "Réunion").
    /// `before`: only
    /// what was copied before then (the list's next older rows, as it
    /// nears its end).
    /// `unpinnedOnly`, with no words: the pinned copies left out (the
    /// list shows them first, from `pinned()`).
    /// `only`: one kind, or one app's copies (⌘K → Show Only…), with
    /// the words or without.
    func search(_ text: String, limit: Int = 50, before: Date? = nil, unpinnedOnly: Bool = false, only: Only? = nil) -> [Item] {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // What narrows every way of searching: bound than, one kind or app.
        var narrowed: [String] = []
        /// Their values, in the same order.
        var bound: [Value] = []
        if let before {
            narrowed.append("items.copied < ?")
            bound.append(.double(before.timeIntervalSince1970))
        }
        switch only {
        case .kind(let kind):
            narrowed.append("items.value = ?")
            bound.append(.text(kind.rawValue))
        case .app(let id, _):
            narrowed.append("items.app = ?")
            bound.append(.text(id))
        case nil:
            break
        }
        let and = narrowed.map { "AND \($0)" }.joined(separator: " ")
        do {
            if trimmed.isEmpty {
                let conditions = narrowed + (unpinnedOnly ? ["pinned IS NULL"] : [])
                let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
                return try rows("SELECT \(Self.columns) FROM items \(filter) ORDER BY copied DESC LIMIT ?", bound + [.int(Int64(limit))])
            }
            // Every word of 3 letters or more: found inside words too,
            // and in the app's name.
            if findsInsideWords, let match = ClipboardSearch.substringQuery(trimmed) {
                return try rows("""
                    SELECT \(Self.columnList("items")) FROM items_sub JOIN items ON items.id = items_sub.rowid
                    WHERE items_sub MATCH ? \(and) ORDER BY items.copied DESC LIMIT ?
                    """, [.text(match)] + bound + [.int(Int64(limit))])
            }
            if let match = ClipboardSearch.ftsQuery(trimmed) {
                return try rows("""
                    SELECT \(Self.columnList("items")) FROM items_fts JOIN items ON items.id = items_fts.rowid
                    WHERE items_fts MATCH ? \(and) ORDER BY items.copied DESC LIMIT ?
                    """, [.text(match)] + bound + [.int(Int64(limit))])
            }
            // Only symbols ("€", "->"): plain substring.
            return try rows("""
                SELECT \(Self.columns) FROM items WHERE (instr(text, ?) > 0 OR instr(coalesce(ocr, ''), ?) > 0)
                \(and) ORDER BY copied DESC LIMIT ?
                """, [.text(trimmed), .text(trimmed)] + bound + [.int(Int64(limit))])
        } catch {
            Log.actions.error("\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Every kept copy, newest first, its text and OCR cut at `words`
    /// characters: what a search by meaning reads (an excerpt and the
    /// kinds in it), light enough for a long history. Never pasted:
    /// `items(_:)` reads the ones picked whole.
    func meaningCandidates(words: Int = 1_000) -> [Item] {
        lock.lock()
        defer { lock.unlock() }
        let columns = Self.columns.replacingOccurrences(of: "text, ocr", with: "substr(text, 1, \(words)), substr(ocr, 1, \(words))")
        return (try? rows("SELECT \(columns) FROM items ORDER BY copied DESC", [])) ?? []
    }

    /// These copies, whole, in the order given; a forgotten one left out.
    func items(_ ids: [Int64]) -> [Item] {
        guard !ids.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let found = (try? rows("SELECT \(Self.columns) FROM items WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ", ")))",
                               ids.map(Value.int))) ?? []
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Images Jev has not tagged yet, newest first.
    func untaggedImages(limit: Int) -> [Item] {
        lock.lock()
        defer { lock.unlock() }
        return (try? rows("SELECT \(Self.columns) FROM items WHERE kind = 'image' AND tags IS NULL ORDER BY copied DESC LIMIT ?",
                          [.int(Int64(limit))])) ?? []
    }

    /// Every format kept with a copy, in the order the app gave them, to
    /// paste it as it was copied.
    func formats(of id: Int64) -> [ClipboardFormats.Format]? {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = try? prepare("SELECT formats FROM items WHERE id = ?", [.int(id)]) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        let formats = ClipboardFormats.decoded(data)
        return formats.isEmpty ? nil : formats
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = try? prepare("SELECT count(*) FROM items", []) else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    /// The database and the images, for Settings.
    var diskSize: Int64 {
        let manager = FileManager.default
        let files = ((try? manager.contentsOfDirectory(at: imagesFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            + ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func imageURL(_ item: Item) -> URL? {
        item.image.map { imagesFolder.appendingPathComponent($0) }
    }

    // MARK: - SQLite

    private static let columns = columnList(nil)

    private static func columnList(_ table: String?) -> String {
        let prefix = table.map { "\($0)." } ?? ""
        return ["id", "kind", "text", "ocr", "image", "size", "app", "app_name", "copied", "copies", "tags", "pinned", "value"]
            .map { prefix + $0 }
            .joined(separator: ", ")
    }

    private enum Value {
        case text(String)
        case int(Int64)
        case double(Double)
        case blob(Data)
        case null

        static func optionalText(_ value: String?) -> Value {
            value.map(Value.text) ?? .null
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "error"
            sqlite3_free(error)
            throw StoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .int(let int): sqlite3_bind_int64(statement, position, int)
            case .double(let double): sqlite3_bind_double(statement, position, double)
            case .blob(let data):
                _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32(data.count), Self.transient) }
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Copies holding words close to the ones typed, when the words as
    /// typed find nothing: each word of four letters or more may be
    /// mistyped once (twice from eight), its first letter right
    /// (docs/clipboard-rows-and-search.md → Mistyped). Newest first, one
    /// page. `words`: what was found instead, to mark and to say; nil
    /// when nothing is close.
    func close(to text: String, limit: Int = 50, only: Only? = nil) -> (items: [Item], words: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard findsCloseWords else { return nil }
        let typed = ClipboardSearch.foldedWords(text)
        guard !typed.isEmpty else { return nil }
        do {
            var words: [(typed: String, close: [String])] = []
            for word in typed {
                guard ClipboardSearch.slipsAllowed(in: word) > 0, let first = word.unicodeScalars.first else {
                    words.append((word, []))
                    continue
                }
                // The index's words with the same first letter, not
                // shorter than a slip allows.
                let statement = try prepare("""
                    SELECT term, doc FROM items_words WHERE term >= ? AND term < ? AND length(term) >= ?
                    """, [.text(String(first)), .text(String(first) + "\u{10FFFF}"),
                          .int(Int64(word.unicodeScalars.count - ClipboardSearch.slipsAllowed(in: word)))])
                defer { sqlite3_finalize(statement) }
                var kept: [(word: String, copies: Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let term = sqlite3_column_text(statement, 0) { kept.append((String(cString: term), Int(sqlite3_column_int64(statement, 1)))) }
                }
                words.append((word, ClipboardSearch.close(to: word, among: kept)))
            }
            guard let match = ClipboardSearch.closeQuery(words) else { return nil }
            var narrowed = ""
            var bound: [Value] = []
            switch only {
            case .kind(let kind):
                narrowed = "AND items.value = ?"
                bound.append(.text(kind.rawValue))
            case .app(let id, _):
                narrowed = "AND items.app = ?"
                bound.append(.text(id))
            case nil:
                break
            }
            let items = try rows("""
                SELECT \(Self.columnList("items")) FROM items_fts JOIN items ON items.id = items_fts.rowid
                WHERE items_fts MATCH ? \(narrowed) ORDER BY items.copied DESC LIMIT ?
                """, [.text(match)] + bound + [.int(Int64(limit))])
            guard !items.isEmpty else { return nil }
            // What to mark: each word's close ones, the closest first,
            // or the word as typed.
            return (items, words.flatMap { $0.close.isEmpty ? [$0.typed] : $0.close }.prefix(8).joined(separator: " "))
        } catch {
            Log.actions.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func strings(_ sql: String, _ values: [Value]) throws -> [String] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
        }
        return result
    }

    private func int64s(_ sql: String, _ values: [Value]) throws -> [Int64] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(sqlite3_column_int64(statement, 0))
        }
        return result
    }

    private func rows(_ sql: String, _ values: [Value]) throws -> [Item] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var items: [Item] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(Item(
                id: sqlite3_column_int64(statement, 0),
                kind: text(1).flatMap(Item.Kind.init(rawValue:)) ?? .text,
                text: text(2) ?? "",
                ocr: text(3),
                image: text(4),
                size: text(5),
                app: text(6),
                appName: text(7),
                copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                copies: Int(sqlite3_column_int64(statement, 9)),
                tags: text(10),
                pinnedAt: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
                value: text(12)
            ))
        }
        return items
    }
}

extension ClipboardStore.Item {
    /// A found row's title: the line where the first word typed is, when
    /// its first line does not hold it (an image: among its words).
    func title(searched words: String) -> String {
        guard !words.isEmpty else { return title }
        switch kind {
        case .text:
            return ClipboardSearch.found(words, in: text) ?? title
        case .image:
            guard let ocr, let line = ClipboardSearch.found(words, in: ocr, limit: 80) else { return title }
            return "\(tags.flatMap(ImageTags.init(words:))?.kind.title ?? "Image") “\(line)”"
        case .files:
            return title
        }
    }

    /// The one picture file this copy is (copied in Finder, or by a
    /// capture app that puts its file on the clipboard).
    var pictureFile: URL? {
        kind == .files ? CopiedPicture.path(in: text).map { URL(fileURLWithPath: $0) } : nil
    }

    /// The text read in an image, copied as an image or as its file, when
    /// there is some.
    var imageText: String? {
        guard kind == .image || pictureFile != nil,
              let text = ocr?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// A row's title: the first line, an image's first words, file names.
    var title: String {
        switch kind {
        case .text:
            return ClipboardSearch.title(of: text)
        case .image:
            let words = ocr.map { ClipboardSearch.title(of: $0, limit: 80) } ?? ""
            let kind = tags.flatMap(ImageTags.init(words:))?.kind.title ?? "Image"
            return words.isEmpty ? kind : "\(kind) “\(words)”"
        case .files:
            return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }.joined(separator: ", ")
        }
    }
}
