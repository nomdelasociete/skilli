import AppKit
import Darwin
import SkilliCore

/// The images saved in a folder (Settings → Clipboard → Images saved in a
/// folder; macOS's screenshots by default) handed to the clipboard history
/// as they arrive, to be read and tagged like a copy. The kernel says when
/// the folder changes: nothing polls. A file is taken once its size stops
/// changing (a screenshot is written in a moment); hidden files never.
@MainActor
final class ImageFolderWatcher {
    /// A new image in the folder, and when it was made.
    var onImage: ((URL, Date) -> Void)?
    private(set) var folder: URL?
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var waiting: Set<String> = []

    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]

    /// Where macOS saves screenshots: its own setting, else the Desktop.
    static var screenshotsFolder: URL {
        let saved = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
            .map { ($0 as NSString).expandingTildeInPath }
        if let saved, FileManager.default.fileExists(atPath: saved) { return URL(fileURLWithPath: saved, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Watches `folder` (nil stops). The images already there are known;
    /// the newest `backfill` of them are handed over once per folder.
    /// False when macOS does not let skil.li read it.
    @discardableResult
    func watch(_ folder: URL?, backfill: Int = 0) -> Bool {
        guard folder?.standardizedFileURL != self.folder?.standardizedFileURL || source == nil else { return true }
        stop()
        guard let folder else { return true }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.actions.notice("Image folder: cannot watch \(folder.lastPathComponent, privacy: .public) (\(errno))")
            return false
        }
        self.folder = folder
        let images = Self.images(in: folder)
        known = Set(images.map(\.url.lastPathComponent))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        Log.trace("Image folder: watching \(folder.lastPathComponent), \(images.count) images there")
        for image in images.prefix(backfill).reversed() { onImage?(image.url, image.date) }
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        folder = nil
        known = []
        waiting = []
    }

    /// What is new since last time, each taken once its size holds still.
    private func scan() {
        guard let folder else { return }
        for image in Self.images(in: folder) where !known.contains(image.url.lastPathComponent) && !waiting.contains(image.url.lastPathComponent) {
            waiting.insert(image.url.lastPathComponent)
            settle(image.url, size: -1)
        }
    }

    private func settle(_ url: URL, size previous: Int) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size == previous else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated { self?.settle(url, size: size) }
            }
            return
        }
        let name = url.lastPathComponent
        waiting.remove(name)
        guard url.deletingLastPathComponent().standardizedFileURL == folder?.standardizedFileURL else { return }
        known.insert(name)
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
        onImage?(url, date)
    }

    /// The newest screenshot in `folders`: an image macOS marked as a
    /// screen capture (`kMDItemIsScreenCapture`, which `screencapture`
    /// writes), or named as macOS and CleanShot X name theirs.
    static func latestScreenshot(in folders: [URL]) -> URL? {
        var seen = Set<String>()
        return folders.filter { seen.insert($0.standardizedFileURL.path).inserted }
            .flatMap { images(in: $0) }
            .filter { isScreenCapture($0.url) || ScreenshotName.looksLikeScreenshot($0.url.lastPathComponent) }
            .max { $0.date < $1.date }?.url
    }

    /// macOS's own mark on what it captured, read from the file itself.
    static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    /// The folder's images, newest first; hidden files left out.
    static func images(in folder: URL) -> [(url: URL, date: Date)] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return files.compactMap { url -> (URL, Date)? in
            guard extensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return (url, values.creationDate ?? .distantPast)
        }
        .sorted { $0.1 > $1.1 }
    }
}
