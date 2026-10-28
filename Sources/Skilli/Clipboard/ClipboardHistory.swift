import AppKit
import CryptoKit
import Observation
import SkilliCore
import Vision

/// Keeps what the user copies (Settings → Clipboard), searchable from the
/// launcher with ✦C. Reads the clipboard only once skil.li is set to Allow
/// in Privacy & Security → Paste from Other Apps: otherwise macOS would ask
/// on every copy. Secrets marked by password managers, skil.li's own
/// borrowing and excluded apps are never kept.
@MainActor
@Observable
final class ClipboardHistory {
    /// What Return does with a row.
    enum Use {
        case paste
        /// Text only (an image's text, read by OCR).
        case pastePlain
        case copy
    }

    @ObservationIgnored let store: ClipboardStore?
    /// Link previews, kept beside the history (Show link previews).
    @ObservationIgnored let links: ClipboardLinks?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var lastPrune = Date.distantPast
    /// Changes when something is kept or read, so Settings recounts.
    private(set) var revision = 0
    /// TypeSafe's key, for Jev to tag images; nil without one (nothing is
    /// sent then).
    @ObservationIgnored var imageKey: () -> String? = { nil }

    init(preferences: Preferences, store: ClipboardStore?, pasteboard: NSPasteboard = .general) {
        self.preferences = preferences
        self.store = store
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        links = store.map { ClipboardLinks(folder: $0.previewsFolder) }
        links?.isOn = { [preferences] in preferences.clipboardLinkPreviews }
    }

    /// The user's choice for skil.li in Paste from Other Apps.
    var access: NSPasteboard.AccessBehavior { pasteboard.accessBehavior }
    var mayRead: Bool { access == .alwaysAllow }
    var isRecording: Bool { preferences.clipboardHistory && mayRead && store != nil }

    func start() {
        // What was there before skil.li started was not copied just now.
        lastChangeCount = pasteboard.changeCount
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        prune()
        // Previews whose copy went while skil.li was not running.
        let store = self.store
        Task.detached(priority: .utility) { store?.sweepPreviews() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The change count costs nothing and asks nothing; the content is read
    /// only when it changed and the user allowed it.
    func poll() {
        if Date.now.timeIntervalSince(lastPrune) > 3600 { prune() }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        // skil.li is reading a selection through ⌘C: not the user's copy.
        guard !PasteboardSnapshot.isBorrowing else { return }
        lastChangeCount = count
        guard isRecording else { return }
        capture()
    }

    /// Keeps what is on the clipboard now. Self-test hook too.
    @discardableResult
    func capture() -> ClipboardStore.Item? {
        guard let store else { return nil }
        let front = NSWorkspace.shared.frontmostApplication
        guard let new = Self.read(pasteboard, app: front?.bundleIdentifier, appName: front?.localizedName,
                                  excluded: Set(preferences.clipboardExcludedApps))
        else { return nil }
        do {
            let (item, isNew) = try store.add(new)
            revision += 1
            // Never what was copied, even in Debug: only its shape.
            Log.trace("Clipboard: kept \(item.kind.rawValue), \(item.text.count) characters, from \(item.appName ?? "?")\(isNew ? "" : ", again")")
            if isNew, item.kind == .image, let url = store.imageURL(item) {
                if preferences.clipboardOCR { readText(in: url, id: item.id) }
                if preferences.imageTagsClipboard { tag(url, id: item.id) }
            }
            return item
        } catch {
            Log.actions.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// An image saved in the folder Settings watches (Keep screenshots
    /// too): kept as if copied when it was made, its words read on this Mac
    /// (Read text in images), Jev told only with Screenshots, by what they
    /// show.
    /// Nil when it is not an image or already kept.
    @discardableResult
    func keepImage(at url: URL, made date: Date, from source: String) -> ClipboardStore.Item? {
        guard let store, preferences.clipboardHistory, let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let png = url.pathExtension.lowercased() == "png" ? (try? Data(contentsOf: url)) : rep.representation(using: .png, properties: [:])
        guard let png, png.count <= 40_000_000 else { return nil }
        let new = ClipboardStore.NewItem(kind: .image, text: "", imageData: png, size: "\(rep.pixelsWide)×\(rep.pixelsHigh)",
                                         app: nil, appName: source, hash: Self.hash("image", png))
        do {
            let (item, isNew) = try store.add(new, at: date)
            revision += 1
            guard isNew, let kept = store.imageURL(item) else { return item }
            Log.trace("Image folder: kept an image from \(source)")
            if preferences.clipboardOCR { readText(in: kept, id: item.id) }
            if preferences.imageTagsFolder { tag(kept, id: item.id) }
            return item
        } catch {
            Log.actions.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Images kept before tagging (or while there was no key): the newest
    /// `limit` tagged now, one after the other, each only while its switch
    /// is on: a copy (the app it came from is known) with "Images you
    /// copy", one from the watched folder (no app) with "Images saved in a
    /// folder".
    func tagUntagged(limit: Int = 60) {
        guard let store, imageKey() != nil, preferences.imageTagsClipboard || preferences.imageTagsFolder else { return }
        let waiting = store.untaggedImages(limit: limit).filter { item in
            item.app == nil ? preferences.imageTagsFolder : preferences.imageTagsClipboard
        }
        guard !waiting.isEmpty else { return }
        Task { [weak self] in
            for item in waiting {
                guard let self, let url = store.imageURL(item) else { return }
                await self.tagNow(url, id: item.id)
            }
        }
    }

    /// Drops what is older than Settings keeps: at launch, then once an
    /// hour (`poll`). Changing Keep copies for never calls it: the pane
    /// says first what the next pass removes (`pendingRemoval`).
    func prune() {
        lastPrune = .now
        guard let store, let cutoff = preferences.clipboardRetention.cutoff() else { return }
        if let removed = try? store.prune(before: cutoff), !removed.isEmpty {
            Log.trace("Clipboard: \(removed.count) items older than \(preferences.clipboardRetention.rawValue) removed")
            for id in removed { links?.forget(id) }
            revision += 1
        }
    }

    /// How many copies the next hourly pass removes, as Keep copies for is
    /// now; recounted when the history changes.
    var pendingRemoval: Int {
        _ = revision
        guard let store, let cutoff = preferences.clipboardRetention.cutoff() else { return 0 }
        return store.count(before: cutoff)
    }

    func clear() {
        try? store?.clear()
        links?.forgetAll()
        revision += 1
    }

    func delete(_ item: ClipboardStore.Item) {
        try? store?.delete(item.id)
        links?.forget(item.id)
        revision += 1
    }

    /// ⌘⌫ in the history: gone at once, held in memory for ⌘Z
    /// (`UndoableDeletes.clip`).
    func forget(_ item: ClipboardStore.Item) -> ClipboardStore.Forgotten? {
        let forgotten = try? store?.forget(item.id)
        links?.forget(item.id)
        revision += 1
        return forgotten ?? nil
    }

    /// ⌘Z: the copy back in the history, where it was.
    func restore(_ forgotten: ClipboardStore.Forgotten) throws {
        guard let store else { return }
        try store.restore(forgotten)
        revision += 1
    }

    func search(_ text: String) -> [ClipboardStore.Item] {
        store?.search(text) ?? []
    }

    /// What a search by meaning found: the copies that fit, best first,
    /// and who decided ("Jev · 0.42 s"). `unanswered`: no model answered
    /// in time ("Jev did not answer"), and nothing was found.
    struct MeaningResult: Sendable {
        let items: [ClipboardStore.Item]
        let label: String
        var unanswered: String?
    }

    /// How long a search by meaning waits for each model: Jev answers 240
    /// copies in well under a second; past this, the next key is tried.
    static let answerLimit: Duration = .seconds(5)

    /// "The electricity bill I copied yesterday": the recent copies, one
    /// line each (what, where from, when, 200 characters), go to the
    /// decision model, which picks. Only on ⇥ (Settings → Clipboard);
    /// typing never sends anything. Nil when no key; `unanswered` when no
    /// model answered within `answerLimit`, or every one failed.
    func searchByMeaning(_ request: String, keys: [DecisionProvider: String], now: Date = .now) async -> MeaningResult? {
        guard let store else { return nil }
        let candidates = store.search("", limit: ClipboardMeaning.candidateLimit)
        guard !candidates.isEmpty else { return MeaningResult(items: [], label: "") }
        // Off the main thread: each text is read for what it is (Apple's data
        // detectors). A newer search or a closed history cancels it, and
        // then nothing is sent.
        let work = Task.detached(priority: .userInitiated) { () -> [DecisionQuestion.Option]? in
            var options: [DecisionQuestion.Option] = []
            for item in candidates {
                if Task.isCancelled { return nil }
                options.append(DecisionQuestion.Option(value: "c\(item.id)", description: ClipboardMeaning.describe(
                    kind: ClipboardMeaning.Kind(rawValue: item.kind.rawValue) ?? .text, text: item.text, ocr: item.ocr,
                    appName: item.appName, copiedAt: item.copiedAt, tags: item.tags, now: now)))
            }
            return options
        }
        guard let options = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() }),
              !Task.isCancelled else { return nil }
        let question = DecisionQuestion(name: "copy", instructions: ClipboardMeaning.instructions,
                                        options: options + [.init(value: "none", description: "No copy fits what the user describes")])
        let input = ClipboardMeaning.input(request, now: now)
        var asked: [String] = []
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let name = provider == .typeSafe ? "Jev" : "Decisions"
            asked.append(name)
            let start = ContinuousClock.now
            do {
                // The request's own timeout is reset by each packet; this
                // one is the whole wait.
                let answers = try await withThrowingTaskGroup(of: [String: DecisionResult]?.self) { group in
                    group.addTask {
                        try await DecisionClient.decide([question], input: input, provider: provider, key: key,
                                                        timeout: Self.answerLimit.milliseconds / 1_000)
                    }
                    group.addTask {
                        try await Task.sleep(for: Self.answerLimit)
                        return nil
                    }
                    defer { group.cancelAll() }
                    return try await group.next() ?? nil
                }
                guard let answers else {
                    Log.actions.error("Clipboard by meaning with \(provider.rawValue, privacy: .public): no answer in \(Self.answerLimit.compact, privacy: .public)")
                    continue
                }
                guard let answer = answers[question.name] else { continue }
                let byID = Dictionary(uniqueKeysWithValues: candidates.map { ("c\($0.id)", $0) })
                // The likely ones, best first; a long tail of 1 % guesses is noise.
                let ranked = answer.probabilities
                    .filter { $0.key != "none" && $0.value >= 0.04 }
                    .sorted { $0.value > $1.value }
                    .prefix(8)
                    .compactMap { byID[$0.key] }
                let elapsed = ContinuousClock.now - start
                // The request and what was picked; never what was copied.
                Log.trace("Clipboard by meaning “\(request)”: \(candidates.count) copies, \(name) picked \(answer.probabilities.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \(Int($0.value * 100))%" }) in \(elapsed.compact)")
                return MeaningResult(items: answer.choice == "none" && (answer.probabilities[answer.choice] ?? 0) > 0.6 ? [] : ranked,
                                     label: "\(name) · \(String(format: "%.2f s", elapsed.milliseconds / 1_000))")
            } catch {
                // A newer search or a closed history: nothing to say.
                if Task.isCancelled { return nil }
                Log.actions.error("Clipboard by meaning with \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard !asked.isEmpty, !Task.isCancelled else { return nil }
        return MeaningResult(items: [], label: "", unanswered: "\(asked.joined(separator: " and ")) did not answer")
    }

    /// Puts an item back on the clipboard: every format it was copied with,
    /// or only its text. False when there is nothing to put.
    @discardableResult
    func write(_ item: ClipboardStore.Item, plain: Bool) -> Bool {
        let entry = NSPasteboardItem()
        var urls: [NSURL] = []
        switch item.kind {
        case .text:
            if !plain, let formats = store?.formats(of: item.id) {
                for (type, data) in formats {
                    entry.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
            }
            entry.setString(item.text, forType: .string)
        case .image:
            if plain {
                guard let text = item.ocr, !text.isEmpty else { return false }
                entry.setString(text, forType: .string)
            } else {
                guard let url = store?.imageURL(item), let data = try? Data(contentsOf: url) else { return false }
                entry.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation {
                    entry.setData(tiff, forType: .tiff)
                }
            }
        case .files:
            if plain {
                entry.setString(item.text, forType: .string)
            } else {
                urls = item.text.split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) }
            }
        }
        pasteboard.clearContents()
        return urls.isEmpty ? pasteboard.writeObjects([entry]) : pasteboard.writeObjects(urls)
    }

    // MARK: - Paste in Sequence

    @ObservationIgnored private var sequence = PasteSequence()
    /// The copies of the sequence under way, by id, as it began.
    @ObservationIgnored private var sequenceItems: [Int64: ClipboardStore.Item] = [:]

    /// Paste in Sequence: the next older copy put on the clipboard for ⌘V,
    /// the newest when a sequence begins (`PasteSequence`). Nil once it is
    /// there; else why nothing is, in one line.
    func putNextInSequence(now: Date = .now) -> String? {
        guard preferences.clipboardHistory, let store else { return "Clipboard History is off: turn it on in Settings → Clipboard." }
        let id = sequence.next(now: now, changeCount: pasteboard.changeCount) {
            let items = store.search("", limit: PasteSequence.length)
            sequenceItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            return items.map(\.id)
        }
        guard let id, let item = sequenceItems[id] else {
            return sequenceItems.isEmpty ? "Nothing copied yet." : "That was the oldest copy. Again starts from the newest."
        }
        guard write(item, plain: false) else { return "That copy is gone from the history." }
        // Whatever changes the clipboard after this is the user's own copy.
        sequence.wrote(changeCount: pasteboard.changeCount)
        Log.trace("Paste in Sequence: copy \(sequence.position + 1) of \(sequence.ids.count), \(item.kind.rawValue)")
        return nil
    }

    // MARK: - Reading the clipboard

    /// Formats worth keeping to paste a text back as it was copied.
    private static let richTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html]
    private static let imageTypes: Set<String> = [
        NSPasteboard.PasteboardType.png.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        "public.jpeg",
        "public.heic"
    ]

    /// What is on the clipboard, as the history keeps it; nil for nothing
    /// worth keeping, secrets and excluded apps.
    static func read(_ pasteboard: NSPasteboard, app: String?, appName: String?, excluded: Set<String>) -> ClipboardStore.NewItem? {
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard ClipboardPolicy.shouldRecord(types: types, app: app, excluded: excluded) else { return nil }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path).joined(separator: "\n")
            return ClipboardStore.NewItem(kind: .files, text: paths, app: app, appName: appName, hash: hash("files", Data(paths.utf8)))
        }

        let string = pasteboard.string(forType: .string)
        // Office apps put a picture of the cells after their text: text
        // first means text.
        let imageFirst = types.first.map(imageTypes.contains) ?? false
        if let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !imageFirst {
            guard string.utf8.count <= 5_000_000 else { return nil }
            var formats: [String: Data] = [:]
            var total = 0
            if let first = pasteboard.pasteboardItems?.first {
                for type in richTypes where first.types.contains(type) {
                    if let data = first.data(forType: type), total + data.count <= 2_000_000 {
                        formats[type.rawValue] = data
                        total += data.count
                    }
                }
            }
            return ClipboardStore.NewItem(kind: .text, text: string, formats: formats.isEmpty ? nil : formats,
                                          app: app, appName: appName, hash: hash("text", Data(string.utf8)))
        }

        guard let image = pngData(from: pasteboard) else { return nil }
        // A copied web image keeps its address: searchable too.
        return ClipboardStore.NewItem(kind: .image, text: string ?? "", imageData: image.png, size: image.size,
                                      app: app, appName: appName, hash: hash("image", image.png))
    }

    /// The clipboard's image as PNG, with its size in pixels.
    private static func pngData(from pasteboard: NSPasteboard) -> (png: Data, size: String)? {
        let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation
        guard let data, data.count <= 40_000_000, let rep = NSBitmapImageRep(data: data) else { return nil }
        let png = pasteboard.data(forType: .png) ?? rep.representation(using: .png, properties: [:])
        guard let png else { return nil }
        return (png, "\(rep.pixelsWide)×\(rep.pixelsHigh)")
    }

    /// Same content, same hash, whoever copied it (the self-test too).
    static func hash(_ kind: String, _ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Tags

    /// Jev sees a small copy of the image once and says what it shows; the
    /// words are kept beside its text.
    private func tag(_ url: URL, id: Int64) {
        Task { [weak self] in await self?.tagNow(url, id: id) }
    }

    private func tagNow(_ url: URL, id: Int64) async {
        guard let key = imageKey(), let store else { return }
        let start = ContinuousClock.now
        guard let tags = await ImageTagger.tags(for: url, key: key) else { return }
        try? store.setTags(tags.words, for: id)
        revision += 1
        // Never what the image shows: only that it was tagged.
        Log.trace("Clipboard: an image tagged in \((ContinuousClock.now - start).compact)")
    }

    // MARK: - OCR

    /// Vision reads the image's text on this Mac; search finds it after.
    private func readText(in url: URL, id: Int64) {
        let store = self.store
        Task.detached(priority: .utility) { [weak self] in
            let start = ContinuousClock.now
            guard let text = await Self.recognizeText(in: url) else { return }
            try? store?.setOCR(text, for: id)
            Log.trace("Clipboard: OCR read \(text.count) characters in \((ContinuousClock.now - start).compact)")
            await MainActor.run { self?.revision += 1 }
        }
    }

    /// The image's text, line by line, in whatever language it is.
    nonisolated static func recognizeText(in url: URL) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: url) else { return nil }
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
