import AppKit
import CoreServices
import SkilliCore
import UniformTypeIdentifiers

/// Files through Spotlight's own index: by name as the user types, and the
/// recent ones for a search by meaning. In the user's home; Library,
/// hidden and app-internal folders left out.
///
/// Spotlight's C query, synchronous, on a queue of its own: NSMetadataQuery's
/// notifications on the main run loop left the Swift runtime's executor
/// check crashing in a later timer (seen in the self-test).
enum FileSearch {
    struct File: Equatable, Sendable {
        let url: URL
        let name: String
        let kind: String
        let modified: Date?
        let used: Date?

        var folder: String { FileMeaning.folder(of: url.path) }
    }

    /// Names containing every word, recently used first.
    static func search(_ text: String, limit: Int = 40) async -> [File] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let query = words.map { "kMDItemFSName == \"*\(escaped($0))*\"cd" }.joined(separator: " && ")
        let files = await run(query, max: 400)
        return Array(files.sorted { ($0.used ?? $0.modified ?? .distantPast) > ($1.used ?? $1.modified ?? .distantPast) }.prefix(limit))
    }

    /// GIFs whose name holds every word (Search GIFs' "On this Mac"),
    /// recently used or changed first. `folder`: the self-test's own.
    static func gifs(_ text: String, in folder: URL? = nil, limit: Int = 24) async -> [URL] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let query = (["kMDItemContentType == \"com.compuserve.gif\""] + words.map { "kMDItemFSName == \"*\(escaped($0))*\"cd" })
            .joined(separator: " && ")
        let files = await run(query, max: 200, scope: folder?.path ?? NSHomeDirectory())
        return files.sorted { ($0.used ?? $0.modified ?? .distantPast) > ($1.used ?? $1.modified ?? .distantPast) }.prefix(limit).map(\.url)
    }

    /// Files opened in the last 90 days, most recent first.
    static func recentlyUsed(limit: Int) async -> [File] {
        let query = "kMDItemLastUsedDate >= $time.now(-7776000) && kMDItemContentType != \"public.folder\""
        let files = await run(query, max: 2_000)
        return Array(files.sorted { ($0.used ?? .distantPast) > ($1.used ?? .distantPast) }.prefix(limit))
    }

    /// Documents changed in the last week, newest first: PDFs, office
    /// files, archives, videos, audio and screenshots. Not every image or
    /// "movie": a project's thousands of icons and TypeScript files (.ts
    /// reads as a video stream) would crowd them out.
    static func recentlyChanged(limit: Int) async -> [File] {
        let kinds = ["public.composite-content", "public.archive", "public.presentation", "public.spreadsheet", "public.rtf",
                     "public.mpeg-4", "com.apple.quicktime-movie", "public.audio"]
        let query = "kMDItemFSContentChangeDate >= $time.now(-604800) && ("
            + kinds.map { "kMDItemContentTypeTree == \"\($0)\"" }.joined(separator: " || ") + " || kMDItemIsScreenCapture == 1)"
        let files = await run(query, max: 2_000)
        return Array(files.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }.prefix(limit))
    }

    /// What a search by meaning chooses among: files named with the
    /// request's words, then the ones opened lately, then documents
    /// changed this week, each with its share of the 240 places.
    /// Gathered here, chosen by the model.
    static func candidates(for request: String) async -> [File] {
        var files: [File] = []
        var seen = Set<String>()
        func add(_ found: [File]) {
            for file in found where files.count < FileMeaning.candidateLimit && seen.insert(file.url.path).inserted { files.append(file) }
        }
        let words = FileMeaning.significantWords(request).prefix(5)
        if words.count > 1 { add(await search(words.joined(separator: " "), limit: 15)) }
        for word in words { add(await search(word, limit: 15)) }
        add(await recentlyUsed(limit: 90))
        add(await recentlyChanged(limit: 60))
        return files
    }

    /// Wildcards and quotes typed are taken as letters.
    private static func escaped(_ word: String) -> String {
        word.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
    }

    /// One query at a time on its own queue, never on Swift's thread
    /// pool: Spotlight queries started together (one per key typed) were
    /// seen waiting forever. One no longer wanted is skipped or stopped;
    /// one still gathering after 3 s stops with what it found.
    private static let queue = DispatchQueue(label: "li.skil.spotlight", qos: .userInitiated)

    private final class Running: @unchecked Sendable {
        private let lock = NSLock()
        private var query: MDQuery?
        private var stopped = false

        /// False when the query was stopped before it started.
        func start(_ query: MDQuery) -> Bool {
            lock.withLock {
                self.query = query
                return !stopped
            }
        }

        func stop() {
            lock.withLock {
                stopped = true
                if let query { MDQueryStop(query) }
            }
        }

        func finish() {
            lock.withLock { query = nil }
        }
    }

    private static func run(_ text: String, max: Int, timeout: Double = 3, scope: String = NSHomeDirectory()) async -> [File] {
        let running = Running()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: execute(text, max: max, timeout: timeout, scope: scope, running)) }
            }
        } onCancel: {
            running.stop()
        }
    }

    private static func execute(_ text: String, max: Int, timeout: Double, scope: String, _ running: Running) -> [File] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, text as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [scope] as CFArray, 0)
        MDQuerySetMaxCount(query, max)
        guard running.start(query) else { return [] }
        defer { running.finish() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [running] in running.stop() }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var files: [File] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, !isHidden(path) else { continue }
            let url = URL(fileURLWithPath: path)
            let type = (MDItemCopyAttribute(item, kMDItemContentType) as? String).flatMap(UTType.init)
            files.append(File(url: url, name: url.lastPathComponent, kind: type?.localizedDescription ?? "",
                              modified: MDItemCopyAttribute(item, kMDItemFSContentChangeDate) as? Date,
                              used: MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date))
        }
        return files
    }

    /// Library, hidden folders, app internals: not what people look for.
    private static func isHidden(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/Library/") { return true }
        return path.split(separator: "/").contains { $0.hasPrefix(".") } || path.contains(".app/")
    }

    /// "le contrat de location du mois dernier": the decision model picks
    /// among recent files. Only names, kinds, folders and dates are sent.
    static func searchByMeaning(_ request: String, keys: [DecisionProvider: String],
                                among given: [File]? = nil) async -> (files: [File], label: String)? {
        var candidates = given ?? []
        if given == nil { candidates = await self.candidates(for: request) }
        guard !candidates.isEmpty else { return ([], "") }
        let now = Date.now
        let question = DecisionQuestion(
            name: "file", instructions: FileMeaning.instructions,
            options: candidates.enumerated().map { index, file in
                .init(value: "f\(index)", description: FileMeaning.describe(name: file.name, kind: file.kind, folder: file.folder, modified: file.modified, now: now))
            } + [.init(value: "none", description: "No file fits what the user describes")]
        )
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let start = ContinuousClock.now
            do {
                let answers = try await DecisionClient.decide([question], input: FileMeaning.input(request, now: now), provider: provider, key: key)
                guard let answer = answers[question.name] else { continue }
                let ranked = answer.probabilities.filter { $0.key != "none" && $0.value >= 0.04 }
                    .sorted { $0.value > $1.value }
                    .prefix(8)
                    .compactMap { entry in Int(entry.key.dropFirst()).flatMap { candidates.indices.contains($0) ? candidates[$0] : nil } }
                let elapsed = ContinuousClock.now - start
                let name = provider == .typeSafe ? "Jev" : "Decisions"
                Log.trace("Files by meaning “\(request)”: \(candidates.count) candidates, \(ranked.count) picked by \(name) in \(elapsed.compact)")
                return (ranked, "\(name) · \(String(format: "%.2f s", elapsed.milliseconds / 1_000))")
            } catch {
                Log.actions.error("Files by meaning with \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}
