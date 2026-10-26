import CryptoKit
import Foundation
import Observation
import SkilliCore

/// Better transcription (docs/meeting-recorder-views.md, phase 4): whisper
/// large-v3-turbo and its VAD's model, downloaded only from Settings →
/// Recorder's button, at a fixed revision of huggingface.co, each file's
/// SHA-256 checked before it is kept, into Application Support's
/// skil.li/Models (never in a backup). A download only: nothing is sent
/// with it. skil.li quits meanwhile: what came is kept, Resume goes on
/// from there. For the recorder only.
@MainActor
@Observable
final class BetterTranscription {
    /// A file of the download.
    struct File: Sendable, Equatable {
        let name: String
        let url: URL
        let size: Int64
        let sha256: String
    }

    /// whisper's VAD (Silero, MIT) first, it is small; then the model
    /// (MIT), as measured.
    nonisolated static let files: [File] = [
        File(name: "ggml-silero-v5.1.2.bin",
             url: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v5.1.2.bin")!,
             size: 885_098, sha256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf"),
        File(name: "ggml-large-v3-turbo.bin",
             url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo.bin")!,
             size: 1_624_555_275, sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"),
    ]

    #if SKILLI_SELFTEST
    /// Self-test: the models' folder in its own scratch (the Mac's own
    /// Better transcription left alone), and the files from a stand-in
    /// server.
    nonisolated(unsafe) static var testFolder: URL?
    nonisolated(unsafe) static var testFiles: [File]?
    #endif

    /// Where they are kept.
    nonisolated static var standardFolder: URL {
        #if SKILLI_SELFTEST
        if let testFolder { return testFolder }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true).appendingPathComponent(BackupPlan.modelsFolder, isDirectory: true)
    }

    /// Downloaded: each file there, its size the expected one (checked by
    /// its SHA-256 as it came). Read from disk, cheap.
    nonisolated static func isReady(in folder: URL = standardFolder, files: [File] = files) -> Bool {
        files.allSatisfy { file in
            (try? folder.appendingPathComponent(file.name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) == file.size
        }
    }

    /// The model's and the VAD's files, for the helper; nil until
    /// downloaded.
    nonisolated static func paths(in folder: URL = standardFolder) -> (model: URL, vad: URL)? {
        guard isReady(in: folder) else { return nil }
        return (folder.appendingPathComponent(files[1].name), folder.appendingPathComponent(files[0].name))
    }

    enum State: Equatable {
        case notDownloaded
        case downloading(received: Int64, total: Int64, line: String)
        case checking
        /// Stopped by a failure or a quit; `resumable` when what came is kept.
        case stopped(String, resumable: Bool)
        /// A file not the one expected: nothing kept.
        case wrongFile
        case downloaded
    }

    let folder: URL
    let files: [File]
    private(set) var state: State = .notDownloaded
    /// Settings → Recorder shows the row: a failure is said there, else
    /// once in the card.
    var isShown = false
    /// A failure while the row is not shown (out of sight), said once.
    var onFailureOutOfSight: (String) -> Void = { _ in }
    /// Downloaded and checked: what said to download it goes.
    var onDownloaded: () -> Void = {}
    private var task: Task<Void, Never>?
    private var current: URLSessionDownloadTask?
    private var speed: (bytes: Int64, at: ContinuousClock.Instant)?
    private var bytesPerSecond: Double?
    private let session: URLSession

    init(folder: URL = BetterTranscription.standardFolder, files: [File]? = nil) {
        self.folder = folder
        #if SKILLI_SELFTEST
        self.files = files ?? Self.testFiles ?? Self.files
        #else
        self.files = files ?? Self.files
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
        refresh()
    }

    var total: Int64 { files.reduce(0) { $0 + $1.size } }

    /// "1.7 GB free needed on this Mac: 0.9 GB left." when the disk cannot
    /// hold what is left to download; nil when it can.
    var roomLine: String? {
        let left = files.filter { !onDisk($0) }.reduce(Int64(0)) { $0 + $1.size }
        guard left > 0 else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let available = (try? base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return ModelDownload.roomLine(needed: left, available: available)
    }

    /// The state as the disk says it, when nothing is downloading.
    func refresh() {
        guard task == nil else { return }
        if Self.isReady(in: folder, files: files) {
            state = .downloaded
        } else if case .stopped = state {
            return
        } else if case .wrongFile = state {
            return
        } else {
            state = files.contains { resumeData(for: $0) != nil } ? .stopped("The download stopped before the end.", resumable: true) : .notDownloaded
        }
    }

    // MARK: - Downloading

    /// Download (or Resume): each file not there yet, from where it
    /// stopped, checked, kept.
    func download() {
        guard task == nil, roomLine == nil else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        state = .downloading(received: received(), total: total, line: ModelDownload.progress(received: received(), total: total, bytesPerSecond: nil))
        speed = nil
        bytesPerSecond = nil
        task = Task { [weak self] in
            guard let self else { return }
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.tick()
                }
            }
            defer { ticker.cancel() }
            do {
                for file in self.files where !self.onDisk(file) {
                    try await self.fetch(file)
                }
                self.task = nil
                self.current = nil
                self.state = Self.isReady(in: self.folder, files: self.files) ? .downloaded : .notDownloaded
                Log.trace("Better transcription: downloaded")
                if self.state == .downloaded { self.onDownloaded() }
            } catch is CancellationError {
                self.task = nil
                self.current = nil
                self.refreshAfterCancel()
            } catch let error as Wrong {
                self.task = nil
                self.current = nil
                self.state = .wrongFile
                self.fail("The file downloaded is not the one expected (\(error.file)): nothing was kept.")
            } catch {
                self.task = nil
                self.current = nil
                let reason = (error as? URLError).map(Self.reason) ?? error.localizedDescription
                self.state = .stopped("The download stopped: \(reason)", resumable: self.files.contains { self.resumeData(for: $0) != nil })
                self.fail("Better transcription stopped downloading: \(reason) Settings → Recorder resumes it.")
            }
        }
    }

    /// Cancel: stopped, what came kept for the next Download.
    func cancel() {
        guard let current else {
            task?.cancel()
            return
        }
        let file = files.first { $0.url == current.originalRequest?.url }
        current.cancel { [weak self] data in
            Task { @MainActor in
                if let data, let file { self?.keepResumeData(data, for: file) }
                self?.task?.cancel()
            }
        }
    }

    /// skil.li quits while downloading: what came is kept (a second at
    /// most), Resume goes on from there.
    nonisolated func keepForQuit() {
        MainActor.assumeIsolated {
            guard let current, let file = files.first(where: { $0.url == current.originalRequest?.url }) else { return }
            let done = DispatchSemaphore(value: 0)
            let box = ResumeBox()
            current.cancel { data in
                box.data = data
                done.signal()
            }
            _ = done.wait(timeout: .now() + 1.5)
            if let data = box.data { keepResumeData(data, for: file) }
        }
    }

    private final class ResumeBox: @unchecked Sendable {
        var data: Data?
    }

    private struct Wrong: Error {
        let file: String
    }

    /// Cancelled by the user: Download again goes on from what came.
    private func refreshAfterCancel() {
        state = Self.isReady(in: folder, files: files) ? .downloaded : .notDownloaded
    }

    private func fail(_ line: String) {
        Log.actions.error("Better transcription: \(line, privacy: .public)")
        if !isShown { onFailureOutOfSight(line) }
    }

    private static func reason(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: "the network went away."
        case .timedOut: "huggingface.co stopped answering."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: "huggingface.co could not be reached."
        case .badServerResponse: "huggingface.co answered with an error (busy, or the file moved)."
        default: error.localizedDescription
        }
    }

    /// One file: downloaded (resumed when what came before is kept),
    /// checked by its SHA-256, moved in place.
    private func fetch(_ file: File) async throws {
        // Each file downloading in turn (the one before was "checking").
        let got = received()
        state = .downloading(received: got, total: total, line: ModelDownload.progress(received: got, total: total, bytesPerSecond: bytesPerSecond))
        let delegate = TaskCatcher { [weak self] task in
            Task { @MainActor in self?.current = task as? URLSessionDownloadTask }
        }
        let downloaded: URL
        let response: URLResponse
        let resumed = resumeData(for: file)
        do {
            if let resumed {
                (downloaded, response) = try await session.download(resumeFrom: resumed, delegate: delegate)
            } else {
                (downloaded, response) = try await session.download(from: file.url, delegate: delegate)
            }
        } catch {
            let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            if let data = (error as? URLError)?.downloadTaskResumeData {
                keepResumeData(data, for: file)
            } else if resumed != nil, !cancelled {
                // What came before could not be resumed (its file purged,
                // the data refused): the next Download starts afresh.
                dropResumeData(for: file)
            }
            if cancelled { throw CancellationError() }
            throw error
        }
        dropResumeData(for: file)
        // An error page (429, 503, 404) comes as a file too: said as the
        // server's, not as a wrong file; the next Download starts afresh.
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            try? FileManager.default.removeItem(at: downloaded)
            Log.trace("Better transcription: \(file.name) answered \(status)")
            throw URLError(.badServerResponse)
        }
        let part = folder.appendingPathComponent(file.name + ".part")
        try? FileManager.default.removeItem(at: part)
        try FileManager.default.moveItem(at: downloaded, to: part)
        state = .checking
        let digest = await Task.detached(priority: .userInitiated) { Self.sha256(of: part) }.value
        guard digest == file.sha256 else {
            try? FileManager.default.removeItem(at: part)
            throw Wrong(file: file.name)
        }
        let final = folder.appendingPathComponent(file.name)
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: part, to: final)
        speed = nil
    }

    /// Every half second while downloading: the row's line.
    private func tick() {
        guard case .downloading = state else { return }
        let now = ContinuousClock.now
        let got = received() + (current?.countOfBytesReceived ?? 0)
        if let last = speed {
            let seconds = (now - last.at) / .seconds(1)
            if seconds > 0 {
                let rate = Double(got - last.bytes) / seconds
                bytesPerSecond = bytesPerSecond.map { $0 * 0.8 + rate * 0.2 } ?? rate
            }
        }
        speed = (got, now)
        state = .downloading(received: got, total: total, line: ModelDownload.progress(received: got, total: total, bytesPerSecond: bytesPerSecond))
    }

    /// The bytes of the files already there.
    private func received() -> Int64 {
        files.filter(onDisk).reduce(0) { $0 + $1.size }
    }

    private func onDisk(_ file: File) -> Bool {
        (try? folder.appendingPathComponent(file.name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) == file.size
    }

    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - What came before a stop

    private func resumeURL(for file: File) -> URL {
        folder.appendingPathComponent(".\(file.name).resume")
    }

    private func resumeData(for file: File) -> Data? {
        try? Data(contentsOf: resumeURL(for: file))
    }

    private func keepResumeData(_ data: Data, for file: File) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: resumeURL(for: file), options: .atomic)
    }

    private func dropResumeData(for file: File) {
        try? FileManager.default.removeItem(at: resumeURL(for: file))
    }

    // MARK: - Remove

    /// Remove: the files to the Trash at once (`UndoableDeletes` offers
    /// them back); where each went, to put it back.
    func moveToTrash() throws -> [(from: URL, trashed: URL)] {
        var moved: [(from: URL, trashed: URL)] = []
        do {
            for file in files {
                let url = folder.appendingPathComponent(file.name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                var trashed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                if let trashed = trashed as URL? { moved.append((url, trashed)) }
            }
        } catch {
            // One file could not go: those gone already come back, all or
            // nothing.
            try? putBack(moved)
            throw error
        }
        // What a cancelled download kept goes too: the next Download starts
        // afresh, not from data for files no longer there.
        for file in files { dropResumeData(for: file) }
        state = .notDownloaded
        return moved
    }

    /// ⌘Z: the files back from the Trash.
    func putBack(_ moved: [(from: URL, trashed: URL)]) throws {
        for (from, trashed) in moved {
            try? FileManager.default.createDirectory(at: from.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: trashed, to: from)
        }
        refresh()
    }

    #if SKILLI_SELFTEST
    /// Self-test: the download as it is now, its line.
    var line: String {
        switch state {
        case .notDownloaded: "not downloaded"
        case .downloading(_, _, let line): line
        case .checking: "checking"
        case .stopped(let why, let resumable): why + (resumable ? " (resumable)" : "")
        case .wrongFile: "wrong file"
        case .downloaded: "downloaded"
        }
    }
    #endif
}

/// The download task, as soon as it is made (its bytes are read from it).
private final class TaskCatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let made: @Sendable (URLSessionTask) -> Void

    init(_ made: @escaping @Sendable (URLSessionTask) -> Void) {
        self.made = made
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        made(task)
    }
}
