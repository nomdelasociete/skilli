import AppKit
import ImageIO
import SkilliCore
import UniformTypeIdentifiers

/// Search GIFs' side away from the launcher: Klipy asked from this Mac
/// (its rule: no server of ours in between), Recently Used kept as ids,
/// the GIF on the clipboard for a paste. Klipy's GIFs are never kept on
/// disk (its rule): a paste writes one temp file, removed with the next.
@MainActor
final class GIFLibrary {
    /// The Keychain account of the user's own Klipy key (Settings → GIFs).
    static let keyAccount = "klipy"
    /// skil.li's own key, put in the Release build by
    /// `script/release/publish.sh` (`SKILLI_KLIPY_KEY`); empty in a
    /// build without it.
    nonisolated static let bundledKey: String = (Bundle.main.object(forInfoDictionaryKey: "SkilliKlipyKey") as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    enum Failure: Error, Equatable {
        case noKey
        /// No answer, or not Klipy's: what to say.
        case unreachable
        case tooLarge
    }

    /// Klipy's address; the self-test's stand-in on 127.0.0.1.
    var base = Klipy.base
    /// The self-test's key, else the user's, else skil.li's.
    var keyOverride: String?
    private let recentsURL: URL?
    private(set) var recents: GIFRecents
    private var saveScheduled = false
    /// The last GIF written for a paste, gone with the next one.
    private var pasted: URL?

    /// The Keychain account read: the self-test's never touches the user's.
    private let keychainAccount: String
    /// Read once: never the Keychain on a key typed.
    private var cachedOwnKey: String??

    /// `recentsURL == nil` keeps Recently Used in memory (self-test).
    init(recentsURL: URL?, keychainAccount: String = GIFLibrary.keyAccount) {
        self.recentsURL = recentsURL
        self.keychainAccount = keychainAccount
        if let recentsURL, let data = try? Data(contentsOf: recentsURL), let kept = try? JSONDecoder().decode(GIFRecents.self, from: data) {
            recents = kept
        } else {
            recents = GIFRecents()
        }
    }

    static var defaultRecentsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true).appendingPathComponent("gif-recents.json")
    }

    // MARK: - The key

    /// The user's own key (Settings → GIFs → Advanced).
    var ownKey: String? {
        if let cachedOwnKey { return cachedOwnKey }
        let read = Keychain.read(account: keychainAccount).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        cachedOwnKey = .some(read)
        return read
    }

    /// Saves the user's own key; false when it cannot be Klipy's.
    func saveOwnKey(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try Keychain.save(key, account: keychainAccount)
        cachedOwnKey = .some(key)
    }

    /// Removes the user's own key; the one removed, for ⌘Z.
    func removeOwnKey() -> String? {
        let old = ownKey
        Keychain.delete(account: keychainAccount)
        cachedOwnKey = .some(nil)
        return old
    }

    /// Where the key comes from, as Settings → GIFs says it.
    enum KeySource { case own, skilli, none }

    var keySource: KeySource {
        if ownKey != nil { return .own }
        return Self.bundledKey.isEmpty ? .none : .skilli
    }

    /// What Klipy is asked with; nil: Klipy is not asked.
    var key: String? {
        if let keyOverride { return keyOverride.isEmpty ? nil : keyOverride }
        return ownKey ?? (Self.bundledKey.isEmpty ? nil : Self.bundledKey)
    }

    var canSearchKlipy: Bool { key != nil }

    /// A random id made once on this Mac, never tied to the person: Klipy
    /// asks for one to count shares (`customer_id`).
    private static var customerID: String {
        let name = "GIFs.customerID"
        if let id = UserDefaults.standard.string(forKey: name) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: name)
        return id
    }

    private static var locale: String? { Klipy.locale(region: Locale.current.region?.identifier) }

    // MARK: - Klipy

    func search(_ text: String, page: Int = 1) async throws -> Klipy.Page {
        guard let key else { throw Failure.noKey }
        guard let url = Klipy.searchURL(text, key: key, page: page, customerID: Self.customerID, locale: Self.locale, base: base) else {
            throw Failure.noKey
        }
        return try await Self.page(url)
    }

    func trending() async throws -> Klipy.Page {
        guard let key else { throw Failure.noKey }
        guard let url = Klipy.trendingURL(key: key, customerID: Self.customerID, locale: Self.locale, base: base) else { throw Failure.noKey }
        return try await Self.page(url)
    }

    /// Recently Used in its order: Klipy's read back in one request, the
    /// files still on disk.
    func recentGIFs() async -> [GIF] {
        var klipy: [KlipyGIF] = []
        let slugs = recents.slugs
        if !slugs.isEmpty, let key, let url = Klipy.itemsURL(slugs, key: key, base: base) {
            klipy = (try? await Self.page(url).gifs) ?? []
        }
        return recents.resolve(klipy: klipy) { FileManager.default.fileExists(atPath: $0) }
    }

    /// Klipy counts a GIF pasted or copied (its rule: never in the way of
    /// that), with the words that found it. Nothing said if it fails.
    func shared(_ gif: KlipyGIF, query: String) {
        guard let key, let url = Klipy.shareURL(gif.slug, key: key, base: base) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Klipy.shareBody(customerID: Self.customerID, query: query)
        Task.detached { _ = try? await Self.session.data(for: request) }
    }

    func used(_ gif: GIF) {
        recents.used(gif.recent)
        scheduleSave()
    }

    /// Self-test hook: starts from nothing.
    func forgetRecents() {
        recents = GIFRecents()
        scheduleSave()
    }

    // MARK: - Pictures

    /// Its bytes, from Klipy or from disk; nil when it cannot be read.
    nonisolated static func data(_ url: URL, limit: Int) async -> Data? {
        if url.isFileURL {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }
        // Read as it comes, stopped past the limit: never a larger body in memory.
        guard let (bytes, response) = try? await session.bytes(from: url), (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= Int64(limit) else { return nil }
        var data = Data()
        data.reserveCapacity(Int(max(0, min(response.expectedContentLength, Int64(limit)))))
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { return nil }
            }
        } catch {
            return nil
        }
        return data
    }

    /// Its first frame at `pixels` on its longer side, decoded off the
    /// main thread: never the whole GIF in memory.
    nonisolated static func still(_ data: Data, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - The clipboard

    /// The GIF on the clipboard as a file and as GIF data: chat apps take
    /// the file, mail and notes the data, both animated (an `NSImage`
    /// would keep one frame). Klipy's is fetched first (15 MB at most).
    func putOnClipboard(_ gif: GIF) async throws {
        let file: URL
        let data: Data
        switch gif {
        case .file(let url):
            guard let read = await Self.data(url, limit: 50_000_000) else { throw Failure.unreachable }
            file = url
            data = read
        case .klipy(let klipy):
            guard klipy.size <= 15_000_000 else { throw Failure.tooLarge }
            guard let read = await Self.data(klipy.full, limit: 15_000_000) else { throw Failure.unreachable }
            file = try writeForPaste(read, name: klipy.title.isEmpty ? klipy.slug : klipy.title)
            data = read
        }
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        item.setString(file.absoluteString, forType: .fileURL)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { throw Failure.unreachable }
    }

    /// One temp file named after the GIF; the one before it removed.
    private func writeForPaste(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-gifs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let pasted { try? FileManager.default.removeItem(at: pasted) }
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/:\\\0")).joined(separator: "-").prefix(80)
        let url = folder.appendingPathComponent((safe.isEmpty ? "GIF" : String(safe)) + ".gif")
        try data.write(to: url, options: .atomic)
        pasted = url
        return url
    }

    /// What is left from a paste of a run before: Klipy's GIFs are not kept.
    static func removePasteFiles() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("skilli-gifs", isDirectory: true))
    }

    // MARK: - Private

    /// Its own session: no cookies, no cache, nothing shared with the
    /// user's browsers or skil.li's other requests.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    nonisolated private static func page(_ url: URL) async throws -> Klipy.Page {
        let start = ContinuousClock.now
        guard let (data, response) = try? await session.data(from: url) else {
            Log.trace("GIFs: Klipy did not answer in \((ContinuousClock.now - start).compact)")
            throw Failure.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let page = try? Klipy.parse(data) else {
            Log.trace("GIFs: Klipy answered \(status)")
            throw Failure.unreachable
        }
        // Never the words searched (rule: logs never hold what is typed).
        Log.trace("GIFs: \(page.gifs.count) from Klipy in \((ContinuousClock.now - start).compact)")
        return page
    }

    private func scheduleSave() {
        guard let recentsURL, !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.saveScheduled = false
            do {
                try FileManager.default.createDirectory(at: recentsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(self.recents).write(to: recentsURL, options: .atomic)
            } catch {
                Log.actions.error("Could not save gif-recents.json: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// What the launcher asks of a GIF (↩, ⌘↩, ⇧⌘C, ⌘K).
enum GIFUse: Equatable, Sendable {
    /// ↩: animated in the app in front, or its Markdown there (`GIFPaste`).
    case paste
    case copy
    case copyLink
    case copyMarkdown
    /// Klipy's in the browser; a file shown in Finder.
    case open
}
