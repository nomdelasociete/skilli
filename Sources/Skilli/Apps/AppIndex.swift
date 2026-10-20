import AppKit
import SkilliCore

/// Installed applications, prepared for fuzzy search.
///
/// Scanning runs off the main thread; searching is synchronous on the main
/// thread because it takes microseconds. Icons are downscaled once into small
/// bitmaps: full app icons hold large representations and would dominate
/// memory.
@MainActor
final class AppIndex {
    struct Entry: Sendable, Equatable {
        let name: String
        let url: URL
        /// The bundle with symlinks resolved (Safari's cryptex): the path a
        /// running app reports.
        let realPath: String
        /// Display name and, when different, the bundle file name, so both
        /// "Calculatrice" and "Calculator" find the same app.
        let candidates: [FuzzyCandidate]

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.url == rhs.url
        }
    }

    private(set) var entries: [Entry] = [] {
        didSet { byPath = Dictionary(entries.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first }) }
    }
    private var byPath: [String: Entry] = [:]
    private(set) var lastScanDuration: Duration?
    private var lastScan: ContinuousClock.Instant?
    private var iconCache: [URL: NSImage] = [:]
    private var isScanning = false
    /// Empty-query ordering, rebuilt only when entries or usage change.
    private var defaultOrder: (usageVersion: Int, entries: [Entry])?
    /// The running apps' bundle paths, read again as apps start and quit:
    /// a row only looks itself up.
    private var runningPaths: Set<String> = []
    private var runningObservation: NSKeyValueObservation?

    private static let staleAfter: Duration = .seconds(60)
    private static let iconSize = NSSize(width: 28, height: 28)
    /// Icons rendered right after a scan, so the first show draws from cache.
    private static let iconWarmCount = 50

    init() {
        runningPaths = Self.runningPaths()
        runningObservation = Self.observeRunningApps { [weak self] in self?.runningPaths = Self.runningPaths() }
    }

    func isRunning(_ entry: Entry) -> Bool {
        runningPaths.contains(entry.realPath)
    }

    /// The running app behind a row.
    func runningApp(_ entry: Entry) -> NSRunningApplication? {
        guard isRunning(entry) else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == entry.realPath }
    }

    private static func runningPaths() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
    }

    /// Built outside the main actor: KVO calls the block where the list
    /// changed.
    private nonisolated static func observeRunningApps(_ changed: @escaping @MainActor @Sendable () -> Void) -> NSKeyValueObservation {
        NSWorkspace.shared.observe(\.runningApplications) { _, _ in
            Task { @MainActor in changed() }
        }
    }

    func reload(usage: UsageStore) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let start = ContinuousClock.now
        let scanned = await Task.detached(priority: .userInitiated) {
            AppScanner.scan()
        }.value
        entries = scanned
        defaultOrder = nil
        lastScan = .now
        lastScanDuration = .now - start
        Log.perf.info("Indexed \(scanned.count) apps in \(self.lastScanDuration?.compact ?? "?", privacy: .public)")

        await warmIcons(for: search("", usage: usage, limit: Self.iconWarmCount))
    }

    func reloadIfStale(usage: UsageStore) {
        guard let lastScan, .now - lastScan > Self.staleAfter else { return }
        Task { await reload(usage: usage) }
    }

    func search(_ text: String, usage: UsageStore, limit: Int) -> [Entry] {
        let query = FuzzyMatcher.Query(text)
        if query.isEmpty {
            return Array(defaultEntries(usage: usage).prefix(limit))
        }
        return scored(query, usage: usage).prefix(limit).map(\.entry)
    }

    /// Matching apps with their ranking score (fuzzy score, a name typed
    /// whole, usage boost), best first. Every candidate is a name.
    func scored(_ query: FuzzyMatcher.Query, usage: UsageStore) -> [(entry: Entry, score: Int)] {
        var scored: [(entry: Entry, score: Int)] = []
        scored.reserveCapacity(64)
        for entry in entries {
            if let best = LauncherRank.score(query, names: entry.candidates[...]) {
                scored.append((entry, best + usage.boost(for: entry.url)))
            }
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.entry.name.count < rhs.entry.name.count
        }
        return scored
    }

    func entry(path: String) -> Entry? {
        byPath[path]
    }

    func icon(for entry: Entry) -> NSImage {
        if let cached = iconCache[entry.url] { return cached }
        let icon = Self.downscaledIcon(forFile: entry.url.path)
        iconCache[entry.url] = icon
        return icon
    }

    private func defaultEntries(usage: UsageStore) -> [Entry] {
        if let defaultOrder, defaultOrder.usageVersion == usage.version {
            return defaultOrder.entries
        }
        // Entries arrive sorted by name; a stable sort on usage keeps that
        // order among apps with equal usage.
        let ordered = entries
            .enumerated()
            .sorted { lhs, rhs in
                let left = usage.boost(for: lhs.element.url)
                let right = usage.boost(for: rhs.element.url)
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        defaultOrder = (usage.version, ordered)
        return ordered
    }

    /// Renders icons one per main-queue turn so a hotkey pressed right after
    /// launch is never stuck behind icon rendering.
    private func warmIcons(for entries: [Entry]) async {
        let start = ContinuousClock.now
        for entry in entries {
            autoreleasepool {
                _ = icon(for: entry)
            }
            await Task.yield()
        }
        Log.perf.info("Warmed \(entries.count) icons in \((ContinuousClock.now - start).compact, privacy: .public)")
    }

    private static func downscaledIcon(forFile path: String) -> NSImage {
        smallIcon(NSWorkspace.shared.icon(forFile: path), size: iconSize)
    }

    /// `source` drawn once into a bitmap of `size` at the screen's scale:
    /// the full `NSWorkspace` icon holds large representations (memory)
    /// and is drawn again from them on every redraw.
    static func smallIcon(_ source: NSImage, size iconSize: NSSize) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int((iconSize.width * scale).rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = iconSize
            return source
        }
        // Points before the context exists: set after, the context draws 1:1
        // in pixels and the icon fills a quarter of a Retina bitmap.
        bitmap.size = iconSize
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            source.size = iconSize
            return source
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: iconSize))
        NSGraphicsContext.restoreGraphicsState()

        let icon = NSImage(size: iconSize)
        icon.addRepresentation(bitmap)
        return icon
    }
}

enum AppScanner {
    private static let roots = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications"
    ]

    private static let extras = [
        "/System/Library/CoreServices/Finder.app"
    ]

    /// Folders like `/Applications/Setapp` hold apps one level down.
    private static let maxDepth = 2

    static func scan() -> [AppIndex.Entry] {
        let fileManager = FileManager.default
        var seen = Set<String>()
        var found: [(name: String, fileName: String, url: URL, realPath: String)] = []

        func add(_ url: URL) {
            // Dedupe on the resolved path, but keep the path the user knows
            // (/Applications/Safari.app, not the cryptex it points into).
            let resolved = url.resolvingSymlinksInPath()
            // Helpers reached through symlinks into another app's bundle.
            guard !resolved.deletingLastPathComponent().path.contains(".app/"),
                  seen.insert(resolved.path).inserted
            else { return }

            var name = fileManager.displayName(atPath: resolved.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            found.append((name, url.deletingPathExtension().lastPathComponent, url, resolved.path))
        }

        func visit(_ directory: URL, depth: Int) {
            // Not `.skipsHiddenFiles`: /Applications/Safari.app is a hidden
            // symlink into the Safari cryptex and would be dropped.
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else { return }

            for child in children where !child.lastPathComponent.hasPrefix(".") {
                if child.pathExtension == "app" {
                    add(child)
                } else if depth < maxDepth,
                          (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(child, depth: depth + 1)
                }
            }
        }

        for root in roots {
            visit(URL(fileURLWithPath: root, isDirectory: true), depth: 1)
        }
        for extra in extras where fileManager.fileExists(atPath: extra) {
            add(URL(fileURLWithPath: extra))
        }

        // Distinct apps can share a display name ("Siri AI.app" displays as
        // "Siri"); show their file names instead so rows are tell-apart.
        let nameCounts = Dictionary(found.map { ($0.name, 1) }, uniquingKeysWith: +)
        let entries = found.map { app in
            let name = nameCounts[app.name, default: 0] > 1 ? app.fileName : app.name
            var candidates = [FuzzyCandidate(name)]
            if app.fileName.caseInsensitiveCompare(name) != .orderedSame {
                candidates.append(FuzzyCandidate(app.fileName))
            }
            if app.name.caseInsensitiveCompare(name) != .orderedSame,
               app.name.caseInsensitiveCompare(app.fileName) != .orderedSame {
                candidates.append(FuzzyCandidate(app.name))
            }
            return AppIndex.Entry(name: name, url: app.url, realPath: app.realPath, candidates: candidates)
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
