import AppKit
import SQLite3
import SkilliCore

/// The browsers' own histories, read on this Mac (never written): Chrome
/// and its family (Arc, Brave, Edge, Vivaldi, Chromium, Opera, Dia) in every
/// profile, Firefox and Zen, opened `immutable` (a running browser keeps its
/// lock: skil.li reads what is on disk); Safari's, once Full Disk Access is
/// on, read only (no lock to fear, and its last pages are still in the
/// write-ahead log).
enum BrowserHistory {
    struct Browser: Sendable {
        enum Kind: Sendable {
            /// `<folder>/<profile>/History`, table `urls`.
            case chrome
            /// `<folder>/Profiles/<profile>/places.sqlite`, table `moz_places`.
            case firefox
            /// `~/Library/Safari/History.db`: `history_items` and their
            /// `history_visits` (titles there, seconds since 2001).
            case safari
        }

        let name: String
        let bundleID: String
        /// Under Application Support.
        let folder: String
        let kind: Kind
    }

    static let browsers: [Browser] = [
        Browser(name: "Chrome", bundleID: "com.google.Chrome", folder: "Google/Chrome", kind: .chrome),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser", folder: "Arc/User Data", kind: .chrome),
        Browser(name: "Dia", bundleID: "company.thebrowser.dia", folder: "Dia/User Data", kind: .chrome),
        Browser(name: "Brave", bundleID: "com.brave.Browser", folder: "BraveSoftware/Brave-Browser", kind: .chrome),
        Browser(name: "Edge", bundleID: "com.microsoft.edgemac", folder: "Microsoft Edge", kind: .chrome),
        Browser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", folder: "Vivaldi", kind: .chrome),
        Browser(name: "Chromium", bundleID: "org.chromium.Chromium", folder: "Chromium", kind: .chrome),
        Browser(name: "Opera", bundleID: "com.operasoftware.Opera", folder: "com.operasoftware.Opera", kind: .chrome),
        Browser(name: "Firefox", bundleID: "org.mozilla.firefox", folder: "Firefox", kind: .firefox),
        Browser(name: "Zen", bundleID: "app.zen-browser.zen", folder: "zen", kind: .firefox),
        Browser(name: "Safari", bundleID: "com.apple.Safari", folder: "Safari", kind: .safari)
    ]

    /// Where to look and which browsers count; the self-test's are scratch.
    struct Source: Sendable {
        var root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        /// Where Safari's folder is (~/Library).
        var library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        var installed: @Sendable (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// Pages whose title or address holds every word, most recent first.
    static func search(_ text: String, limit: Int = 40, source: Source = Source()) async -> [HistoryVisit] {
        let patterns = HistoryMeaning.likePatterns(text)
        guard !patterns.isEmpty else { return await recent(limit: limit, source: source) }
        return await read(source, limit: limit) { browser in
            if browser.kind == .safari {
                let clauses = patterns.indices.map { "(v.title LIKE ?\($0 + 1) ESCAPE '\\' OR i.url LIKE ?\($0 + 1) ESCAPE '\\')" }
                return ("\(Self.safariSelect) WHERE \(clauses.joined(separator: " AND ")) GROUP BY i.id ORDER BY stamp DESC LIMIT \(limit)", patterns)
            }
            let table = browser.kind == .chrome ? "urls" : "moz_places"
            let clauses = patterns.indices.map { "(title LIKE ?\($0 + 1) ESCAPE '\\' OR url LIKE ?\($0 + 1) ESCAPE '\\')" }
            return ("\(Self.select(browser)) FROM \(table) WHERE hidden = 0 AND \(clauses.joined(separator: " AND ")) ORDER BY \(Self.stamp(browser)) DESC LIMIT \(limit)", patterns)
        }
    }

    /// The last pages visited, newest first; every page the browsers keep
    /// when no limit: what a search by meaning chooses among.
    static func recent(limit: Int? = nil, source: Source = Source()) async -> [HistoryVisit] {
        // SQLite reads a negative limit as none.
        let rows = limit ?? -1
        return await read(source, limit: limit ?? .max) { browser in
            if browser.kind == .safari {
                return ("\(Self.safariSelect) GROUP BY i.id HAVING stamp > 0 ORDER BY stamp DESC LIMIT \(rows)", [])
            }
            let table = browser.kind == .chrome ? "urls" : "moz_places"
            return ("\(Self.select(browser)) FROM \(table) WHERE hidden = 0 AND \(Self.stamp(browser)) > 0 ORDER BY \(Self.stamp(browser)) DESC LIMIT \(rows)", [])
        }
    }

    /// Safari is here but its history cannot be opened: Full Disk Access is
    /// off (macOS refuses the folder itself).
    static func safariNeedsAccess(_ source: Source) -> Bool {
        guard source.installed("com.apple.Safari") else { return false }
        let folder = source.library.appendingPathComponent("Safari", isDirectory: true)
        let descriptor = Darwin.open(folder.path, O_RDONLY)
        guard descriptor >= 0 else { return errno == EPERM || errno == EACCES }
        close(descriptor)
        return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) == nil
    }

    /// Opens it in the browser it came from; ⌘ copies its address instead.
    @MainActor
    static func open(_ visit: HistoryVisit, copy: Bool) {
        if copy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(visit.url, forType: .string)
            return
        }
        guard let url = URL(string: visit.url), ["http", "https", "file"].contains(url.scheme ?? "") else { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: visit.bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Reading

    private static func select(_ browser: Browser) -> String {
        "SELECT url, title, visit_count, \(stamp(browser))"
    }

    /// Each page once, with its last visit's title and time.
    private static let safariSelect = "SELECT i.url, v.title, i.visit_count, MAX(v.visit_time) AS stamp FROM history_items i JOIN history_visits v ON v.history_item = i.id"

    private static func stamp(_ browser: Browser) -> String {
        browser.kind == .chrome ? "last_visit_time" : "last_visit_date"
    }

    /// Every history file of the installed browsers: each profile's.
    static func files(_ source: Source) -> [(Browser, URL)] {
        let manager = FileManager.default
        return browsers.filter { source.installed($0.bundleID) }.flatMap { browser -> [(Browser, URL)] in
            let base = source.root.appendingPathComponent(browser.folder, isDirectory: true)
            switch browser.kind {
            case .chrome:
                // Opera keeps one profile at its root; the others, Default and "Profile N".
                let profiles = [base] + ((try? manager.contentsOfDirectory(atPath: base.path)) ?? [])
                    .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
                    .map { base.appendingPathComponent($0, isDirectory: true) }
                return profiles.map { $0.appendingPathComponent("History") }
                    .filter { manager.fileExists(atPath: $0.path) }.map { (browser, $0) }
            case .firefox:
                let profiles = base.appendingPathComponent("Profiles", isDirectory: true)
                return ((try? manager.contentsOfDirectory(atPath: profiles.path)) ?? [])
                    .map { profiles.appendingPathComponent($0).appendingPathComponent("places.sqlite") }
                    .filter { manager.fileExists(atPath: $0.path) }.map { (browser, $0) }
            case .safari:
                // Behind Full Disk Access: unreadable (and so left out) without it.
                let file = source.library.appendingPathComponent("Safari/History.db")
                return manager.isReadableFile(atPath: file.path) ? [(browser, file)] : []
            }
        }
    }

    private static func read(_ source: Source, limit: Int,
                             query: @escaping @Sendable (Browser) -> (sql: String, bindings: [String])) async -> [HistoryVisit] {
        let files = Self.files(source)
        return await Task.detached(priority: .userInitiated) {
            let lists = files.map { browser, url -> [HistoryVisit] in
                let (sql, bindings) = query(browser)
                return rows(url, sql, bindings, immutable: browser.kind != .safari).map { row in
                    let visited = switch browser.kind {
                    case .chrome: HistoryMeaning.chromeDate(row.stamp)
                    case .firefox: HistoryMeaning.firefoxDate(row.stamp)
                    case .safari: HistoryMeaning.safariDate(row.seconds)
                    }
                    return HistoryVisit(url: row.url, title: row.title, browser: browser.name, bundleID: browser.bundleID, visited: visited,
                                        visits: row.visits)
                }
            }
            return HistoryMeaning.merged(lists, limit: limit)
        }.value
    }

    /// `immutable`: what is on disk, whatever locks a running browser holds;
    /// else read only, the write-ahead log included (Safari), falling back to
    /// immutable when that cannot open.
    private static func rows(_ url: URL, _ sql: String, _ bindings: [String], immutable: Bool = true)
        -> [(url: String, title: String, visits: Int, stamp: Int64, seconds: Double)] {
        let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        if !immutable {
            let found = query("file:\(path)?mode=ro", sql, bindings)
            if let found { return found }
        }
        return query("file:\(path)?immutable=1", sql, bindings) ?? []
    }

    private static func query(_ uri: String, _ sql: String, _ bindings: [String]) -> [(url: String, title: String, visits: Int, stamp: Int64, seconds: Double)]? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in bindings.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
        var found: [(String, String, Int, Int64, Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let address = sqlite3_column_text(statement, 0) else { continue }
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            found.append((String(cString: address), title, Int(sqlite3_column_int(statement, 2)), sqlite3_column_int64(statement, 3),
                          sqlite3_column_double(statement, 3)))
        }
        return found.filter { $0.0.hasPrefix("http") }
    }

    /// "la page sur les impôts d'hier": the decision model picks among the
    /// pages the browsers keep, narrowed to the days the request names when
    /// they are more than one question holds (`MeaningNarrowing`), asked in
    /// parts when still more (`MeaningRounds`). Only titles, sites and dates
    /// are sent.
    static func searchByMeaning(_ request: String, keys: [DecisionProvider: String], among given: [HistoryVisit]? = nil,
                                source: Source = Source()) async -> (visits: [HistoryVisit], label: String)? {
        let now = Date.now
        var all = given ?? []
        if given == nil { all = await recent(source: source) }
        let candidates = MeaningNarrowing(request, now: now).narrowed(all, date: \.visited) { _, _ in false }
        guard !candidates.isEmpty else { return ([], "") }
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let start = ContinuousClock.now
            do {
                let outcome = try await MeaningRounds.decide(candidates.indices.map { "p\($0)" }) { values in
                    let question = DecisionQuestion(
                        name: "page", instructions: HistoryMeaning.instructions,
                        options: values.compactMap { value in
                            Int(value.dropFirst()).map { .init(value: value, description: HistoryMeaning.describe(candidates[$0], now: now)) }
                        } + [.init(value: "none", description: "No page fits what the user describes")]
                    )
                    let answers = try await DecisionClient.decide([question], input: HistoryMeaning.input(request, now: now), provider: provider, key: key)
                    return answers[question.name].map { MeaningRounds.Answer(choice: $0.choice, probabilities: $0.probabilities) }
                }
                guard let outcome else { continue }
                let ranked = MeaningRounds.kept(outcome.answer.probabilities)
                    .compactMap { value in Int(value.dropFirst()).flatMap { candidates.indices.contains($0) ? candidates[$0] : nil } }
                let elapsed = ContinuousClock.now - start
                let name = provider == .typeSafe ? "Jev" : "Decisions"
                Log.trace("History by meaning: \(candidates.count) candidates, \(outcome.questions) questions in \(outcome.rounds) rounds"
                          + (outcome.unanswered > 0 ? " (\(outcome.unanswered) unanswered)" : "") + ", \(ranked.count) picked by \(name) in \(elapsed.compact)")
                let parts = outcome.unanswered > 0 ? " · \(outcome.parts - outcome.unanswered) of \(outcome.parts) parts" : ""
                return (ranked, "\(name) · \(String(format: "%.2f s", elapsed.milliseconds / 1_000))\(parts)")
            } catch {
                if Task.isCancelled { return nil }
                Log.actions.error("History by meaning with \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}
