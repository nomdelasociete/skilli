import AppKit
import CoreServices
import SkilliCore
import UniformTypeIdentifiers

/// Files through Spotlight's own index: by name as the user types, and the
/// recent ones for a search by meaning. In the user's home and cloud
/// drives; dependency folders, packages, hidden folders and the rest of
/// Library left out, code projects put behind (`FileRanking`,
/// docs/file-search.md).
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
        /// Inside a code project the user cloned or wrote.
        var inProject = false

        var folder: String { FileMeaning.folder(of: url.path) }
    }

    /// The user's files named like the text, best first: the name that is
    /// what was typed, files opened lately, projects' own files behind.
    /// Words' starts first ("contrat" in Contrat-location.pdf: Spotlight's
    /// word index, about 3× faster), then words in the folders above
    /// ("martin invoice"), then any part of the name, each only while
    /// fewer than 15 files fit.
    static func search(_ text: String, limit: Int = 40) async -> [File] {
        let typed = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard !typed.isEmpty else { return [] }
        let words = FileRanking.words(text)
        let codeQuery = FileRanking.isCodeQuery(text)
        let now = Date.now
        var scored: [(file: File, score: Int)] = []
        var seen = Set<String>()
        func add(_ files: [File]) {
            for file in files where seen.insert(file.url.path).inserted {
                guard let score = FileRanking.score(name: file.name, folder: file.folder, words: words, used: file.used, modified: file.modified,
                                                    inProject: file.inProject, codeQuery: codeQuery, now: now) else { continue }
                scored.append((file, score))
            }
        }
        add(await run(typed.map { "kMDItemFSName == \"\(escaped($0))*\"cdw" }.joined(separator: " && "), max: 6_000))
        // One letter alone would match every name.
        let named = typed.filter { $0.count > 1 }
        if typed.count > 1, scored.count < 15, !named.isEmpty, !Task.isCancelled {
            add(await run(named.map { "kMDItemFSName == \"\(escaped($0))*\"cdw" }.joined(separator: " || "), max: 6_000))
        }
        if scored.count < 15, !Task.isCancelled {
            add(await run(typed.map { "kMDItemFSName == \"*\(escaped($0))*\"cd" }.joined(separator: " && "), max: 6_000))
        }
        return scored.sorted { left, right in
            left.score != right.score ? left.score > right.score
                : (left.file.used ?? left.file.modified ?? .distantPast) > (right.file.used ?? right.file.modified ?? .distantPast)
        }.prefix(limit).map(\.file)
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
        // A project's PDFs and test videos are not the user's documents.
        let files = await run(query, max: 2_000).filter { !$0.inProject || $0.used != nil }
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
        // Fetched with the results: read one by one through MDItem, dates
        // cost seconds for a common word's thousands of files. The path
        // cannot be (always nil).
        let attributes = [kMDItemLastUsedDate, kMDItemFSContentChangeDate, kMDItemContentType] as CFArray
        guard let query = MDQueryCreate(kCFAllocatorDefault, text as CFString, attributes, nil) else { return [] }
        MDQuerySetSearchScope(query, [scope] as CFArray, 0)
        MDQuerySetMaxCount(query, max)
        guard running.start(query) else { return [] }
        defer { running.finish() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [running] in running.stop() }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        let home = NSHomeDirectory()
        var files: [File] = []
        var kinds: [String: String] = [:]
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, FileRanking.exclusion(of: path, home: home) == nil else { continue }
            func value(_ attribute: CFString) -> AnyObject? {
                MDQueryGetAttributeValueOfResultAtIndex(query, attribute, index).map { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() }
            }
            func date(_ attribute: CFString) -> Date? { value(attribute) as? Date }
            let used = date(kMDItemLastUsedDate)
            let root = projectRoot(of: (path as NSString).deletingLastPathComponent, home: home)
            // A project's build output: only what the user opened.
            if let root, used == nil, FileRanking.isBuildOutput(path, projectRoot: root) { continue }
            let url = URL(fileURLWithPath: path)
            let type = value(kMDItemContentType) as? String ?? ""
            if kinds[type] == nil { kinds[type] = UTType(type)?.localizedDescription ?? "" }
            files.append(File(url: url, name: url.lastPathComponent, kind: kinds[type] ?? "",
                              modified: date(kMDItemFSContentChangeDate), used: used, inProject: root != nil))
        }
        return files
    }

    /// Each folder's project root (or none), looked up once while skil.li
    /// runs; read and written on `queue` only.
    nonisolated(unsafe) private static var projectRoots: [String: String] = [:]
    nonisolated(unsafe) private static var notInProject = Set<String>()

    /// The nearest folder above with a project's marker (.git,
    /// package.json…), the home itself not counted: a dotfiles repository
    /// there would make every file a project's. Not looked for in cloud
    /// drives: each look there can wait on the drive (0.8 s for a common
    /// word's folders).
    private static func projectRoot(of folder: String, home: String) -> String? {
        if let root = projectRoots[folder] { return root }
        if notInProject.contains(folder) || folder == home || !folder.hasPrefix(home + "/") || folder.hasPrefix(home + "/Library/") { return nil }
        if projectRoots.count + notInProject.count > 50_000 { (projectRoots, notInProject) = ([:], []) }
        let manager = FileManager.default
        let root = FileRanking.projectMarkers.contains { manager.fileExists(atPath: folder + "/" + $0) } ? folder
            : projectRoot(of: (folder as NSString).deletingLastPathComponent, home: home)
        if let root { projectRoots[folder] = root } else { notInProject.insert(folder) }
        return root
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
