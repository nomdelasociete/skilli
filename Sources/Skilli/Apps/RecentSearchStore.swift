import Foundation
import SkilliCore

/// Persists `RecentSearches` (what ↑ brings back in the launcher) in
/// `~/Library/Application Support/skil.li/recent-searches.json`, like
/// `LearningStore`: read once, kept in memory, writes coalesced so acting
/// on a result never waits on disk.
@MainActor
final class RecentSearchStore {
    private(set) var searches: RecentSearches
    private let fileURL: URL?
    private var saveScheduled = false

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true)
            .appendingPathComponent("recent-searches.json")
    }

    /// `fileURL == nil` keeps them in memory (self-test, benchmark).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            do {
                searches = try JSONDecoder().decode(RecentSearches.self, from: data)
            } catch {
                Log.actions.error("recent-searches.json unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
                searches = RecentSearches()
            }
        } else {
            searches = RecentSearches()
        }
    }

    var entries: [String] { searches.entries }

    func record(_ text: String) {
        let before = searches
        searches.record(text)
        if searches != before { scheduleSave() }
    }

    /// Self-test hook: starts from nothing.
    func forgetAll() {
        searches = RecentSearches()
        scheduleSave()
    }

    private func scheduleSave() {
        guard let fileURL, !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.saveScheduled = false
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(self.searches).write(to: fileURL, options: .atomic)
            } catch {
                Log.actions.error("Could not save recent-searches.json: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
