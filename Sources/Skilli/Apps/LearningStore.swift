import Foundation
import SkilliCore

/// Persists `QueryLearning` in `~/Library/Application Support/skil.li/`.
/// Writes are coalesced so picking results never waits on disk.
@MainActor
final class LearningStore {
    private var learning: QueryLearning
    private let fileURL: URL?
    private var saveScheduled = false

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true)
            .appendingPathComponent("learning.json")
    }

    /// `fileURL == nil` keeps everything in memory.
    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            do {
                learning = try JSONDecoder().decode(QueryLearning.self, from: data)
            } catch {
                Log.actions.error("learning.json unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
                learning = QueryLearning()
            }
        } else {
            learning = QueryLearning()
        }
    }

    func record(query: String, item: String) {
        learning.record(query: query, item: item, at: .now)
        scheduleSave()
    }

    func boost(query: String, item: String) -> Int {
        learning.boost(query: query, item: item, at: .now)
    }

    func learnedItems(query: String) -> [(item: String, boost: Int)] {
        learning.learnedItems(query: query, at: .now)
    }

    /// How much each item of a kind was picked ("contact:" → by contact id).
    func picks(prefix: String) -> [String: Double] {
        learning.picks(prefix: prefix, at: .now)
    }

    func forgetAll() {
        learning = QueryLearning()
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
                try JSONEncoder().encode(self.learning).write(to: fileURL, options: .atomic)
            } catch {
                Log.actions.error("Could not save learning.json: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
