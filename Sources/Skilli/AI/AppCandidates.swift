import Foundation

/// Installed apps as decision options: the name, and the kind the app
/// declares (`LSApplicationCategoryType`, "graphics design") so "my vector
/// drawing app" can find VectorCraft. Categories are read once per app.
enum AppCandidates {
    struct App: Sendable {
        let name: String
        let url: URL
        /// "graphics design", or empty.
        let kind: String
    }

    private static let cache = Cache()

    /// Reads Info.plists: call it off the main thread.
    static func apps(_ entries: [(name: String, url: URL)]) -> [App] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard seen.insert(entry.name.lowercased()).inserted else { return nil }
            return App(name: entry.name, url: entry.url, kind: cache.kind(of: entry.url))
        }
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var kinds: [URL: String] = [:]

        func kind(of url: URL) -> String {
            if let known = lock.withLock({ kinds[url] }) { return known }
            let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String ?? ""
            let kind = category
                .replacingOccurrences(of: "public.app-category.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            lock.withLock { kinds[url] = kind }
            return kind
        }
    }
}
