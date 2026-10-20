import AppKit
import ImageIO
import SkilliCore
import UniformTypeIdentifiers

/// Link previews in the clipboard history (Settings → Clipboard → Show
/// link previews): when a copied link shows in the preview, and only then,
/// skil.li reads the page's head (a plain GET: no cookies, no sign-in, no
/// cache shared with anything, http(s) only, at most `LinkPreviews.headLimit`)
/// for its Open Graph tags, then its picture and icon. Kept in the
/// history's `previews` folder by the copy's id (`LinkPreviewCache`),
/// removed with the copy; read again after a week, a failure after ten
/// minutes, while it is looked at. Never logs the link.
@MainActor
final class ClipboardLinks {
    let folder: URL
    /// Settings → Clipboard → Show link previews.
    var isOn: () -> Bool = { true }
    private var records: [Int64: LinkPreviewRecord] = [:]
    private var running: [Int64: Task<LinkPreviewRecord?, Never>] = [:]

    init(folder: URL) {
        self.folder = folder
    }

    /// What is known now, without reading anything.
    func known(_ id: Int64) -> LinkPreviewRecord? {
        records[id]
    }

    /// The preview kept for `id` (read from disk once), then, `fetching`,
    /// the page read again when it is due and allowed. One request at a
    /// time per copy.
    func preview(for id: Int64, url: URL, fetching: Bool) async -> LinkPreviewRecord? {
        if let task = running[id] { return await task.value }
        let folder = self.folder
        let kept = records[id]
        let allowed = fetching && isOn()
        let task = Task<LinkPreviewRecord?, Never> {
            var record = kept
            if record == nil {
                record = await Task.detached(priority: .userInitiated) { Self.read(id: id, folder: folder) }.value
            }
            guard allowed, LinkPreviewCache.needsFetch(record, for: url, now: .now) else { return record }
            let earlier = record
            return await Task.detached(priority: .userInitiated) { await Self.fetch(url, id: id, folder: folder, earlier: earlier) }.value
        }
        running[id] = task
        let record = await task.value
        running[id] = nil
        if let record { records[id] = record }
        return record
    }

    func fileURL(_ name: String?) -> URL? {
        name.map { folder.appendingPathComponent($0) }
    }

    /// The copy is gone (its files go with it, `ClipboardStore`).
    func forget(_ id: Int64) {
        records[id] = nil
    }

    func forgetAll() {
        records.removeAll()
    }

    // MARK: - Disk

    nonisolated private static func read(id: Int64, folder: URL) -> LinkPreviewRecord? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(LinkPreviewCache.recordName(id))) else { return nil }
        return try? JSONDecoder().decode(LinkPreviewRecord.self, from: data)
    }

    nonisolated private static func write(_ record: LinkPreviewRecord, id: Int64, folder: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: folder.appendingPathComponent(LinkPreviewCache.recordName(id)), options: .atomic)
    }

    // MARK: - The request

    /// One session for previews only: nothing stored, nothing shared with
    /// the user's browsers or skil.li's other requests.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = LinkPreviews.timeout
        configuration.timeoutIntervalForResource = LinkPreviews.timeout * 2
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    nonisolated private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15 skil.li/\(version)"
    }()

    /// Reads the page and keeps what it says, its picture and its icon.
    /// No answer: what an earlier read found stays, tried again later.
    nonisolated static func fetch(_ url: URL, id: Int64, folder: URL, earlier: LinkPreviewRecord? = nil) async -> LinkPreviewRecord {
        let start = ContinuousClock.now
        var record = LinkPreviewRecord(url: url, fetched: .now, outcome: .failed)
        defer {
            if record.outcome == .failed, var kept = earlier, kept.url == url, kept.outcome == .found {
                // Due again once a failure would be.
                kept.fetched = record.fetched.addingTimeInterval(LinkPreviewCache.retryAfter - LinkPreviewCache.refreshAfter)
                record = kept
            }
            write(record, id: id, folder: folder)
        }
        guard LinkPreviews.isFetchable(url) else {
            record.outcome = .found
            return record
        }
        guard let page = await get(url, accept: "text/html,application/xhtml+xml;q=0.9,image/*;q=0.8,*/*;q=0.5",
                                   limit: LinkPreviews.imageLimit, page: true) else {
            Log.trace("Link preview: no answer in \((ContinuousClock.now - start).compact)")
            return record
        }
        // An answer, even "not found": not asked again before a week.
        record.outcome = page.status >= 500 ? .failed : .found
        guard (200..<300).contains(page.status) else {
            Log.trace("Link preview: the page answered \(page.status)")
            return record
        }
        let mime = page.mimeType ?? ""
        if mime.hasPrefix("image/") {
            // A link to a picture: the picture is the preview.
            var preview = LinkPreview(title: url.lastPathComponent.removingPercentEncoding, isImage: true)
            if page.complete, save(page.data, as: LinkPreviewCache.imageName(id), folder: folder, longest: 800, format: .jpeg) {
                record.image = LinkPreviewCache.imageName(id)
            } else {
                preview.isImage = false
            }
            record.preview = preview
            return record
        }
        guard mime.contains("html") || mime.isEmpty else {
            record.preview = LinkPreview()
            return record
        }
        let html = LinkPreviews.decode(page.data, contentType: page.contentType)
        let preview = LinkPreviews.parse(html: html, base: page.url ?? url)
        record.preview = preview
        async let picture = fetchImage(preview.imageURL, id: id, folder: folder)
        async let icon = fetchIcon(preview.iconURLs, id: id, folder: folder)
        record.image = await picture
        record.icon = await icon
        // What was found, never the link nor what the page says.
        Log.trace("Link preview: read in \((ContinuousClock.now - start).compact): title \(preview.title != nil), "
                  + "description \(preview.summary != nil), picture \(record.image != nil), icon \(record.icon != nil)")
        return record
    }

    nonisolated private static func fetchImage(_ url: URL?, id: Int64, folder: URL) async -> String? {
        guard let url, let answer = await get(url, accept: "image/*", limit: LinkPreviews.imageLimit),
              (200..<300).contains(answer.status), answer.complete,
              save(answer.data, as: LinkPreviewCache.imageName(id), folder: folder, longest: 800, format: .jpeg)
        else { return nil }
        return LinkPreviewCache.imageName(id)
    }

    /// The first icon that draws, best first.
    nonisolated private static func fetchIcon(_ urls: [URL], id: Int64, folder: URL) async -> String? {
        for url in urls {
            guard let answer = await get(url, accept: "image/*", limit: LinkPreviews.iconLimit),
                  (200..<300).contains(answer.status), answer.complete else { continue }
            if save(answer.data, as: LinkPreviewCache.iconName(id), folder: folder, longest: 64, format: .png) {
                return LinkPreviewCache.iconName(id)
            }
        }
        return nil
    }

    private struct Answer: Sendable {
        let status: Int
        let url: URL?
        let mimeType: String?
        let contentType: String?
        let data: Data
        /// All of it was read (not cut at the limit nor at the head's end).
        let complete: Bool
    }

    /// A GET, read up to `limit` bytes; a `page` that is not a picture up
    /// to its head's end, `LinkPreviews.headLimit` at most. Nil when no
    /// answer came.
    nonisolated private static func get(_ url: URL, accept: String, limit: Int, page: Bool = false) async -> Answer? {
        guard LinkPreviews.isFetchable(url) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ", "), forHTTPHeaderField: "Accept-Language")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectGuard())
            guard let http = response as? HTTPURLResponse else {
                bytes.task.cancel()
                return nil
            }
            let isPage = page && !(http.mimeType ?? "").hasPrefix("image/")
            let cap = isPage ? LinkPreviews.headLimit : limit
            // Too big to keep: not read at all.
            if !isPage, response.expectedContentLength > Int64(cap) {
                bytes.task.cancel()
                return Answer(status: http.statusCode, url: http.url, mimeType: http.mimeType,
                              contentType: http.value(forHTTPHeaderField: "Content-Type"), data: Data(), complete: false)
            }
            var data = Data()
            data.reserveCapacity(min(cap, max(0, Int(response.expectedContentLength)) + 1))
            var complete = true
            for try await byte in bytes {
                data.append(byte)
                if data.count >= cap {
                    complete = false
                    break
                }
                if isPage, data.count % 4_096 == 0, LinkPreviews.headEnded(data) {
                    complete = false
                    break
                }
            }
            if !complete { bytes.task.cancel() }
            return Answer(status: http.statusCode, url: http.url, mimeType: http.mimeType,
                          contentType: http.value(forHTTPHeaderField: "Content-Type"), data: data, complete: complete)
        } catch {
            return nil
        }
    }

    /// Decodes a picture and keeps it small: its longest side `longest`
    /// pixels; the largest frame of an icon file.
    nonisolated private static func save(_ data: Data, as name: String, folder: URL, longest: Int, format: UTType) -> Bool {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return false }
        var best = 0
        var bestWidth = 0
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if width > bestWidth {
                best = index
                bestWidth = width
            }
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, best, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary), image.width >= 8, image.height >= 8 else { return false }
        let url = folder.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary : nil)
        return CGImageDestinationFinalize(destination)
    }
}

/// Redirects only to http(s), a few at most; no sign-in ever answered.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        let allowed = lock.withLock {
            count += 1
            return count <= LinkPreviews.redirectLimit
        }
        guard allowed, let url = request.url, LinkPreviews.isFetchable(url) else { return nil }
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // The server's certificate is checked as usual; a page asking for
        // a password gets none.
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? (.performDefaultHandling, nil) : (.cancelAuthenticationChallenge, nil)
    }
}
