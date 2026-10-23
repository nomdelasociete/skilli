import Foundation
import SkilliCore

/// Snippets as files in `~/Library/Application Support/skil.li/snippets`,
/// one Markdown file each: editable in Settings or any editor, read again
/// when the folder changes.
final class SnippetLibrary: @unchecked Sendable {
    let folder: URL?
    private let lock = NSLock()
    private var cache: [Snippet] = []
    /// Each snippet file's date, read with the folder.
    private var dates: [String: Date] = [:]
    private var stamp: Date?

    /// Shown once, so the feature explains itself: ";date" types the date.
    static let examples = [
        Snippet(id: "todays-date", name: "Today's Date", keyword: ";date", text: "{date}")
    ]

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li/snippets", isDirectory: true)
    }

    /// `nil` keeps nothing on disk (benchmark).
    init(folder: URL?) {
        self.folder = folder
        guard let folder, !FileManager.default.fileExists(atPath: folder.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for example in Self.examples { write(example) }
    }

    /// By name. Cheap: the folder is read again only when it changed.
    var all: [Snippet] {
        lock.lock()
        defer { lock.unlock() }
        guard let folder else { return cache }
        let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if modified != stamp || stamp == nil {
            stamp = modified
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            var dates: [String: Date] = [:]
            cache = files.filter { $0.pathExtension == "md" }.compactMap { url in
                let id = url.deletingPathExtension().lastPathComponent
                dates[id] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (try? String(contentsOf: url, encoding: .utf8)).map { Snippet(id: id, parsing: $0) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.dates = dates
        }
        return cache
    }

    func snippet(_ id: String) -> Snippet? {
        all.first { $0.id == id }
    }

    /// When its file last changed, as the folder was last read (nothing
    /// read here: Search Snippets' preview asks on every row).
    func modified(_ id: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return dates[id]
    }

    /// A new snippet gets a file name from its name, unique in the folder.
    func save(_ snippet: Snippet) -> Snippet {
        var snippet = snippet
        if snippet.id.isEmpty {
            let base = Snippet.fileID(for: snippet.name)
            var id = base
            var number = 2
            while all.contains(where: { $0.id == id }) {
                id = "\(base)-\(number)"
                number += 1
            }
            snippet.id = id
        }
        write(snippet)
        invalidate()
        return snippet
    }

    /// Raycast's snippets export: each one a snippet here; a keyword
    /// already used is left off its import. Nil when the file is not one.
    func importRaycast(_ data: Data) -> (imported: Int, keywordsLeftOff: Int, unknown: [String])? {
        guard let items = RaycastImport.snippets(data) else { return nil }
        var keywords = Set(all.map(\.keyword).filter { !$0.isEmpty })
        var leftOff = 0
        var unknown: [String] = []
        for item in items {
            var keyword = item.keyword
            if !keyword.isEmpty, !keywords.insert(keyword).inserted {
                keyword = ""
                leftOff += 1
            }
            _ = save(Snippet(id: "", name: item.name, keyword: keyword, text: item.text))
            unknown += item.unknown.filter { !unknown.contains($0) }
        }
        Log.trace("Snippets: \(items.count) imported from Raycast")
        return (items.count, leftOff, unknown)
    }

    /// "my iban", "adresse bureau": the decision model picks among the
    /// snippets, each told by its name, keyword and first 80 characters as
    /// written (`SnippetMeaning`). Only on ⇥ in Search Snippets (Settings →
    /// Snippets); nil when no key answered. `maybe`: none picked, the
    /// snippet "none" narrowly won over (`SnippetMeaning.maybe`).
    func searchByMeaning(_ request: String, keys: [DecisionProvider: String]) async -> (snippets: [Snippet], maybe: Snippet?, label: String)? {
        let candidates = Array(all.prefix(SnippetMeaning.candidateLimit))
        guard !candidates.isEmpty else { return ([], nil, "") }
        let question = DecisionQuestion(
            name: "snippet", instructions: SnippetMeaning.instructions,
            options: candidates.enumerated().map { index, snippet in
                .init(value: SnippetMeaning.value(index), description: SnippetMeaning.describe(snippet))
            } + [.init(value: "none", description: "No snippet fits what the user needs")]
        )
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let start = ContinuousClock.now
            do {
                let answers = try await DecisionClient.decide([question], input: SnippetMeaning.input(request), provider: provider, key: key)
                guard let answer = answers[question.name] else { continue }
                let picked = SnippetMeaning.picked(answer.probabilities, choice: answer.choice, count: candidates.count).map { candidates[$0] }
                let maybe = SnippetMeaning.maybe(answer.probabilities, choice: answer.choice, count: candidates.count).map { candidates[$0] }
                let elapsed = ContinuousClock.now - start
                let name = provider == .typeSafe ? "Jev" : "Decisions"
                // The request, the names picked and the likeliest answers;
                // never a snippet's text.
                let likeliest = answer.probabilities.sorted { $0.value > $1.value }.prefix(3).map { entry in
                    let shown = entry.key.first == "s" ? Int(entry.key.dropFirst()).flatMap { candidates.indices.contains($0) ? candidates[$0].name : nil } : nil
                    return "\(shown ?? entry.key) \(Int((entry.value * 100).rounded())) %"
                }
                Log.trace("Snippets by meaning “\(request)”: \(candidates.count) snippets, \(name) picked \(picked.prefix(3).map(\.name))"
                          + (maybe.map { ", maybe \($0.name)" } ?? "") + " \(likeliest) in \(elapsed.compact)")
                return (picked, maybe, "\(name) · \(String(format: "%.2f s", elapsed.milliseconds / 1_000))")
            } catch {
                Log.actions.error("Snippets by meaning with \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    /// What a delete took: the snippet and its file as written, for ⌘Z.
    struct Deleted {
        let snippet: Snippet
        fileprivate let file: Data?
    }

    @discardableResult
    func delete(_ id: String) -> Deleted? {
        let found = snippet(id)
        guard let folder else {
            lock.lock()
            cache.removeAll { $0.id == id }
            lock.unlock()
            return found.map { Deleted(snippet: $0, file: nil) }
        }
        let url = folder.appendingPathComponent("\(id).md")
        let file = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        invalidate()
        return found.map { Deleted(snippet: $0, file: file) }
    }

    /// Back as it was written, under its own name; another snippet that
    /// took that name meanwhile keeps it, this one gets a free one.
    @discardableResult
    func restore(_ deleted: Deleted) -> Snippet {
        guard let folder, let file = deleted.file, snippet(deleted.snippet.id) == nil else {
            var snippet = deleted.snippet
            if self.snippet(snippet.id) != nil { snippet.id = "" }
            return save(snippet)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? file.write(to: folder.appendingPathComponent("\(deleted.snippet.id).md"), options: .atomic)
        invalidate()
        return deleted.snippet
    }

    private func write(_ snippet: Snippet) {
        guard let folder else {
            lock.lock()
            cache.removeAll { $0.id == snippet.id }
            cache.append(snippet)
            lock.unlock()
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? snippet.file.write(to: folder.appendingPathComponent("\(snippet.id).md"), atomically: true, encoding: .utf8)
    }

    private func invalidate() {
        lock.lock()
        stamp = nil
        lock.unlock()
    }
}
