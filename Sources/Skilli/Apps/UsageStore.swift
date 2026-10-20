import Foundation

/// Launch counts per app, used as a ranking boost so frequently used apps win
/// ties and show first on an empty query.
@MainActor
final class UsageStore {
    private static let defaultsKey = "UsageStore.launchCounts"
    private var counts: [String: Int]
    /// Bumped on every change so callers can cache usage-based orderings.
    private(set) var version = 0

    init() {
        counts = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
    }

    /// Logarithmic so a daily-driver app does not drown out a precise query.
    func boost(for url: URL) -> Int {
        guard let count = counts[url.path], count > 0 else { return 0 }
        return Int((log2(Double(count) + 1) * 6).rounded())
    }

    func recordLaunch(of url: URL) {
        counts[url.path, default: 0] += 1
        version += 1
        UserDefaults.standard.set(counts, forKey: Self.defaultsKey)
    }
}
