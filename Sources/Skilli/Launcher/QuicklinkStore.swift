import Foundation
import SkilliCore

/// Quicklinks in `~/Library/Application Support/skil.li/quicklinks.json`:
/// the shipped ones until the user changes them in Settings → Launcher.
@MainActor
final class QuicklinkStore {
    let fileURL: URL?
    private(set) var links: [Quicklink]

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li/quicklinks.json")
    }

    /// `nil` keeps them in memory (benchmark, self-test).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        links = fileURL.flatMap { try? JSONDecoder().decode([Quicklink].self, from: Data(contentsOf: $0)) } ?? Quicklink.defaults
    }

    func save(_ link: Quicklink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) { links[index] = link } else { links.append(link) }
        write()
    }

    /// Gone at once; what ⌘Z puts back where it was (`restore`).
    @discardableResult
    func delete(_ id: UUID) -> RemovedElement<Quicklink>? {
        let removed = RemovedElement.take(id, from: &links)
        write()
        return removed
    }

    func restore(_ removed: RemovedElement<Quicklink>) {
        guard removed.putBack(into: &links) else { return }
        write()
    }

    /// Raycast's quicklinks export: each one a quicklink here, without a
    /// keyword (Raycast has none); one already here (same address) or one
    /// skil.li cannot fill is left out. Nil when the file is not one.
    func importRaycast(_ data: Data) -> (imported: Int, skipped: [String])? {
        guard let (items, skipped) = RaycastImport.quicklinks(data) else { return nil }
        var imported = 0
        for item in items where !links.contains(where: { $0.url == item.url }) {
            links.append(Quicklink(name: item.name, keyword: "", url: item.url))
            imported += 1
        }
        write()
        return (imported, skipped)
    }

    func resetToDefaults() {
        links = Quicklink.defaults
        write()
    }

    private func write() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(links).write(to: fileURL, options: .atomic)
    }
}
