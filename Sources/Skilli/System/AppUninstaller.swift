import AppKit
import SkilliCore

/// A clean uninstall, as Raycast does it: the app and what it left in the
/// user's Library (`AppLeftovers`), measured, then moved to the Trash after
/// the user's OK. Never macOS's own apps, never skil.li.
enum AppUninstaller {
    struct Item: Sendable {
        let url: URL
        let bytes: Int64

        /// "Application Support/Slack", "Slack.app".
        var shown: String {
            let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path + "/"
            return url.path.hasPrefix(library) ? String(url.path.dropFirst(library.count)) : url.lastPathComponent
        }
    }

    /// The app, then its leftovers that exist, each measured. Off the main
    /// thread: big folders take a moment.
    static func items(for app: URL) async -> (bundleID: String?, items: [Item]) {
        await Task.detached(priority: .userInitiated) {
            let bundleID = Bundle(url: app)?.bundleIdentifier
            let name = (app.lastPathComponent as NSString).deletingPathExtension
            var urls = [app]
            if let bundleID {
                let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
                urls += AppLeftovers.paths(bundleID: bundleID, name: name).map { library.appendingPathComponent($0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                for folder in AppLeftovers.listedFolders {
                    let base = library.appendingPathComponent(folder)
                    let entries = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
                    urls += entries.filter { AppLeftovers.belongs($0, bundleID: bundleID) }.map { base.appendingPathComponent($0) }
                }
            }
            var seen = Set<String>()
            let items = urls.filter { seen.insert($0.standardizedFileURL.path).inserted }.map { Item(url: $0, bytes: size(of: $0)) }
            return (bundleID, items)
        }.value
    }

    /// On disk, a folder with everything in it.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return 0 }
        if !isFolder.boolValue {
            return Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let file = walker?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static func shown(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
