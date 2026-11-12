import AppKit
import CryptoKit
import Observation
import QuickLookThumbnailing
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
        // A picture dragged out before the app last quit: its copy goes.
        ClipboardDragExports.removeAll()
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
        Task.detached(priority: .utility) {
            store?.sweepPreviews()
            store?.fillKinds()
        }
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
        keep()
    }

    /// A copy that took time to keep is in the history (the launcher's
    /// list takes it if it shows).
    @ObservationIgnored var onKeptLater: (() -> Void)?
    /// Self-test hook: the copies being made off the main thread.
    @ObservationIgnored private(set) var keepingLater = 0

    /// Keeps what is on the clipboard now. The clipboard is read here, on
    /// the main thread; a picture (sized, converted to PNG, hashed) or a
    /// long text (hashed, indexed) is made and stored off it: 100 ms for
    /// a screen copied as TIFF, 40 ms for 1.6 MB of text, measured
    /// 2026-11-11, during which no key was drawn. Its place in the
    /// history is when it was copied, whatever was kept meanwhile.
    /// Self-test hook too.
    func keep() {
        guard let store else { return }
        let front = NSWorkspace.shared.frontmostApplication
        switch Self.look(pasteboard, app: front?.bundleIdentifier, appName: front?.localizedName,
                         excluded: Set(preferences.clipboardExcludedApps), keepsSecrets: !preferences.clipboardSkipSecrets) {
        case nil:
            return
        case .item(let new):
            keepNow(new)
        case .notKept(let reason):
            note(reason, from: front?.localizedName)
        case .later(let make):
            let date = Date.now
            let appName = front?.localizedName
            // Clear History while it is made: not kept after it.
            let clears = store.clears
            keepingLater += 1
            Task.detached(priority: .userInitiated) { [weak self] in
                var added: (item: ClipboardStore.Item, isNew: Bool)?
                switch make() {
                case .item(let new):
                    do {
                        added = try store.add(new, at: date, ifClears: clears)
                    } catch {
                        Log.actions.error("\(error.localizedDescription, privacy: .public)")
                    }
                case .notKept(let reason):
                    await self?.notedLater(reason, from: appName, at: date)
                case nil:
                    break
                }
                await self?.keptLater(added)
            }
        }
    }

    /// The last copy not kept and why, until the history says it
    /// (`takeNotKept`). In memory only, never what was copied.
    @ObservationIgnored private(set) var notKept: ClipboardNotKept?

    /// A copy that took time to look at is not kept: the history says it
    /// now if it is open (the launcher asked before this was known).
    @ObservationIgnored var onNotKeptLater: (() -> Void)?

    private func notedLater(_ reason: ClipboardNotKept.Reason, from appName: String?, at date: Date) {
        note(reason, from: appName, at: date)
        onNotKeptLater?()
    }

    private func note(_ reason: ClipboardNotKept.Reason, from appName: String?, at date: Date = .now) {
        notKept = ClipboardNotKept(reason: reason, appName: appName, date: date)
        // Its shape only, as for the copies kept.
        Log.trace("Clipboard: a copy not kept (\(String(describing: reason))), from \(appName ?? "?")")
    }

    /// The copy not kept since this was last asked, when it is still of
    /// today's use (a day); said once.
    func takeNotKept() -> ClipboardNotKept? {
        defer { notKept = nil }
        return notKept.flatMap { $0.isRecent(now: .now) ? $0 : nil }
    }

    private func keptLater(_ added: (item: ClipboardStore.Item, isNew: Bool)?) {
        keepingLater -= 1
        guard let added else { return }
        kept(added.item, isNew: added.isNew, onClipboard: false)
        onKeptLater?()
    }

    /// Keeps what is on the clipboard now, all of it before it returns:
    /// the self-test's hook.
    @discardableResult
    func capture() -> ClipboardStore.Item? {
        let front = NSWorkspace.shared.frontmostApplication
        guard let new = Self.read(pasteboard, app: front?.bundleIdentifier, appName: front?.localizedName,
                                  excluded: Set(preferences.clipboardExcludedApps), keepsSecrets: !preferences.clipboardSkipSecrets)
        else { return nil }
        return keepNow(new)
    }

    @discardableResult
    private func keepNow(_ new: ClipboardStore.NewItem) -> ClipboardStore.Item? {
        guard let store else { return nil }
        do {
            let (item, isNew) = try store.add(new)
            kept(item, isNew: isNew, onClipboard: true)
            return item
        } catch {
            Log.actions.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// A copy is in the history: its words read, Jev told, as Settings
    /// say. `onClipboard`: the clipboard still holds this copy (kept at
    /// once), so the picture an app put beside a file can be read there.
    private func kept(_ item: ClipboardStore.Item, isNew: Bool, onClipboard: Bool) {
        revision += 1
        // Never what was copied, even in Debug: only its shape.
        Log.trace("Clipboard: kept \(item.kind.rawValue), \(item.text.count) characters, from \(item.appName ?? "?")\(isNew ? "" : ", again")")
        if isNew, item.kind == .image, let url = store?.imageURL(item) {
            if preferences.clipboardOCR { readText(in: url, id: item.id) }
            if preferences.imageTagsClipboard { tag(url, id: item.id) }
        }
        // The same picture copied as its file: read now when the app
        // put the picture itself beside its file. Never from the
        // file here: nobody asked to see it, and macOS would ask for
        // its folder in skil.li's name (`readText(inPictureFile:)`).
        if item.ocr == nil, preferences.clipboardOCR, onClipboard, item.pictureFile != nil, let data = Self.pictureData(on: pasteboard) {
            readText(inCopied: data, id: item.id)
        }
    }

    /// An image saved in the folder Settings watches (Keep screenshots
    /// too): kept as if copied when it was made, its words read on this Mac
    /// (Read text in images), Jev told only with Screenshots, by what they
    /// show.
    /// Nil when it is not an image or already kept. All of it before it
    /// returns: the self-test's hook (`keepImageLater` is the app's).
    @discardableResult
    func keepImage(at url: URL, made date: Date, from source: String) -> ClipboardStore.Item? {
        guard let store, preferences.clipboardHistory, let new = Self.picture(at: url, from: source) else { return nil }
        do {
            return keptImage(try store.add(new, at: date), from: source)
        } catch {
            Log.actions.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The same, the picture read, converted and stored off the main
    /// thread (a screenshot is as heavy as a copied picture).
    func keepImageLater(at url: URL, made date: Date, from source: String) {
        guard let store, preferences.clipboardHistory else { return }
        let clears = store.clears
        keepingLater += 1
        Task.detached(priority: .utility) { [weak self] in
            var added: (item: ClipboardStore.Item, isNew: Bool)?
            if let new = Self.picture(at: url, from: source) {
                do {
                    added = try store.add(new, at: date, ifClears: clears)
                } catch {
                    Log.actions.error("\(error.localizedDescription, privacy: .public)")
                }
            }
            await self?.keptImageLater(added, from: source)
        }
    }

    private func keptImageLater(_ added: (item: ClipboardStore.Item, isNew: Bool)?, from source: String) {
        keepingLater -= 1
        guard let added else { return }
        keptImage(added, from: source)
        onKeptLater?()
    }

    /// A picture's file as the history keeps it: PNG, its size in pixels.
    nonisolated private static func picture(at url: URL, from source: String) -> ClipboardStore.NewItem? {
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let png = url.pathExtension.lowercased() == "png" ? (try? Data(contentsOf: url)) : rep.representation(using: .png, properties: [:])
        guard let png, png.count <= 40_000_000 else { return nil }
        return ClipboardStore.NewItem(kind: .image, text: "", imageData: png, size: "\(rep.pixelsWide)×\(rep.pixelsHigh)",
                                      app: nil, appName: source, hash: hash("image", png))
    }

    @discardableResult
    private func keptImage(_ added: (item: ClipboardStore.Item, isNew: Bool), from source: String) -> ClipboardStore.Item {
        revision += 1
        guard added.isNew, let kept = store?.imageURL(added.item) else { return added.item }
        Log.trace("Image folder: kept an image from \(source)")
        if preferences.clipboardOCR { readText(in: kept, id: added.item.id) }
        if preferences.imageTagsFolder { tag(kept, id: added.item.id) }
        return added.item
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
            for id in removed {
                links?.forget(id)
                ClipboardDragExports.remove(id)
            }
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
        ClipboardDragExports.removeAll()
        revision += 1
    }

    func delete(_ item: ClipboardStore.Item) {
        try? store?.delete(item.id)
        links?.forget(item.id)
        ClipboardDragExports.remove(item.id)
        revision += 1
    }

    /// ⌘⌫ in the history: gone at once, held in memory for ⌘Z
    /// (`UndoableDeletes.clip`).
    func forget(_ item: ClipboardStore.Item) -> ClipboardStore.Forgotten? {
        let forgotten = try? store?.forget(item.id)
        links?.forget(item.id)
        ClipboardDragExports.remove(item.id)
        revision += 1
        return forgotten ?? nil
    }

    /// ⌘Z: the copy back in the history, where it was.
    func restore(_ forgotten: ClipboardStore.Forgotten) throws {
        guard let store else { return }
        try store.restore(forgotten)
        revision += 1
    }

    func search(_ text: String, before: Date? = nil) -> [ClipboardStore.Item] {
        store?.search(text, before: before) ?? []
    }

    /// The launcher's list: a page of the history. With no words its
    /// first page starts with the pinned copies, in the order pinned,
    /// and the pages by date leave them out; with words, one list by
    /// date.
    /// `only` (⌘K → Show Only…): one list by date, with the words or
    /// without.
    func page(_ text: String, before: Date? = nil, only: ClipboardStore.Only? = nil) -> [ClipboardStore.Item] {
        guard let store else { return [] }
        guard only == nil, text.trimmingCharacters(in: .whitespaces).isEmpty else { return store.search(text, before: before, only: only) }
        return (before == nil ? store.pinned() : []) + store.search("", before: before, unpinnedOnly: true)
    }

    /// ⌘K → Pin, Unpin. The copy as it is now.
    @discardableResult
    func setPinned(_ pinned: Bool, _ item: ClipboardStore.Item) -> ClipboardStore.Item? {
        let now = try? store?.setPinned(pinned, for: item.id)
        revision += 1
        return now ?? nil
    }

    /// What a search by meaning found: the copies that fit, best first,
    /// and who decided ("Jev · 0.42 s"). `unanswered`: no model answered
    /// in time ("Jev did not answer"), and nothing was found.
    struct MeaningResult: Sendable {
        /// `var`: a copy pinned while they show is shown as it is now.
        var items: [ClipboardStore.Item]
        let label: String
        var unanswered: String?
        /// The copies the model read (the history narrowed), and the
        /// questions it took.
        var candidates = 0
        var questions = 0
    }

    /// How long a search by meaning waits for each question: Jev answers
    /// 240 copies in well under a second; past this, the next key is
    /// tried (a part of a long history is left out).
    nonisolated static let answerLimit: Duration = .seconds(5)

    /// "The electricity bill I copied yesterday": every kept copy, one line
    /// each (what, where from, when, 200 characters), goes to the decision
    /// model, which picks. A history longer than one question holds is
    /// first narrowed to the days and kinds the request names
    /// (`MeaningNarrowing`), then asked in parts of 240 at once and once
    /// more among their likely picks (`MeaningRounds`). Only on ⇥
    /// (Settings → Clipboard); typing never sends anything. Nil when no
    /// key; `unanswered` when no model answered within `answerLimit`, or
    /// every one failed.
    func searchByMeaning(_ request: String, keys: [DecisionProvider: String], now: Date = .now) async -> MeaningResult? {
        guard let store else { return nil }
        // Off the main thread: the whole history read and narrowed. A newer
        // search or a closed history cancels it, and then nothing is sent.
        let narrowing = MeaningNarrowing(request, now: now)
        let work = Task.detached(priority: .userInitiated) { () -> [ClipboardStore.Item] in
            narrowing.narrowed(store.meaningCandidates(), date: \.copiedAt) { item, kind in
                MeaningNarrowing.holds(kind, copy: ClipboardMeaning.Kind(rawValue: item.kind.rawValue) ?? .text, text: item.text, ocr: item.ocr)
            }
        }
        let candidates = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        guard !Task.isCancelled else { return nil }
        guard !candidates.isEmpty else { return MeaningResult(items: [], label: "") }
        let byValue = Dictionary(uniqueKeysWithValues: candidates.map { ("c\($0.id)", $0) })
        let input = ClipboardMeaning.input(request, now: now)
        var asked: [String] = []
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let name = provider == .typeSafe ? "Jev" : "Decisions"
            asked.append(name)
            let start = ContinuousClock.now
            do {
                let outcome = try await MeaningRounds.decide(candidates.map { "c\($0.id)" }) { values in
                    // Each text is read for what it is (Apple's data
                    // detectors), each part on its own thread.
                    let options = values.compactMap { value in byValue[value].map { item in
                        DecisionQuestion.Option(value: value, description: ClipboardMeaning.describe(
                            kind: ClipboardMeaning.Kind(rawValue: item.kind.rawValue) ?? .text, text: item.text, ocr: item.ocr,
                            appName: item.appName, copiedAt: item.copiedAt, tags: item.tags, now: now))
                    } }
                    try Task.checkCancellation()
                    let question = DecisionQuestion(name: "copy", instructions: ClipboardMeaning.instructions,
                                                    options: options + [.init(value: "none", description: "No copy fits what the user describes")])
                    return try await Self.ask(question, input: input, provider: provider, key: key)
                }
                guard let outcome else {
                    Log.actions.error("Clipboard by meaning with \(provider.rawValue, privacy: .public): no answer in \(Self.answerLimit.compact, privacy: .public)")
                    continue
                }
                let answer = outcome.answer
                // The likely ones, best first; a long tail of 1 % guesses is noise.
                let ranked = answer.choice == "none" && (answer.probabilities[answer.choice] ?? 0) > 0.6 ? [] : MeaningRounds.kept(answer.probabilities)
                let items = store.items(ranked.compactMap { byValue[$0]?.id })
                let elapsed = ContinuousClock.now - start
                // The request and what was picked; never what was copied.
                Log.trace("Clipboard by meaning “\(request)”: \(candidates.count) copies, \(outcome.questions) questions in \(outcome.rounds) rounds"
                          + (outcome.unanswered > 0 ? " (\(outcome.unanswered) unanswered)" : "")
                          + ", \(name) picked \(answer.probabilities.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \(Int($0.value * 100))%" }) in \(elapsed.compact)")
                let parts = outcome.unanswered > 0 ? " · \(outcome.parts - outcome.unanswered) of \(outcome.parts) parts" : ""
                return MeaningResult(items: items, label: "\(name) · \(String(format: "%.2f s", elapsed.milliseconds / 1_000))\(parts)",
                                     candidates: candidates.count, questions: outcome.questions)
            } catch {
                // A newer search or a closed history: nothing to say.
                if Task.isCancelled { return nil }
                Log.actions.error("Clipboard by meaning with \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard !asked.isEmpty, !Task.isCancelled else { return nil }
        return MeaningResult(items: [], label: "", unanswered: "\(asked.joined(separator: " and ")) did not answer")
    }

    /// One question, waiting `answerLimit` at most; nil past it. The
    /// request's own timeout is reset by each packet; this one is the whole
    /// wait.
    nonisolated private static func ask(_ question: DecisionQuestion, input: String, provider: DecisionProvider,
                                        key: String) async throws -> MeaningRounds.Answer? {
        let answers = try await withThrowingTaskGroup(of: [String: DecisionResult]?.self) { group in
            group.addTask {
                try await DecisionClient.decide([question], input: input, provider: provider, key: key,
                                                timeout: answerLimit.milliseconds / 1_000)
            }
            group.addTask {
                try await Task.sleep(for: answerLimit)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
        return answers?[question.name].map { MeaningRounds.Answer(choice: $0.choice, probabilities: $0.probabilities) }
    }

    /// Puts an item back on the clipboard: every format it was copied with,
    /// or only its text. False when there is nothing to put.
    @discardableResult
    func write(_ item: ClipboardStore.Item, plain: Bool) -> Bool {
        let entry = NSPasteboardItem()
        var urls: [NSURL] = []
        switch item.kind {
        case .text:
            if !plain { set(store?.formats(of: item.id), on: entry) }
            entry.setString(item.text, forType: .string)
        case .image:
            if plain {
                guard let text = item.ocr, !text.isEmpty else { return false }
                entry.setString(text, forType: .string)
            } else {
                guard let url = store?.imageURL(item), let data = try? Data(contentsOf: url) else { return false }
                // What the app copied with the picture (a slide's object,
                // a drawing's shapes) first, as it was: the app pasted
                // into takes the first it knows.
                set(store?.formats(of: item.id), on: entry)
                entry.setData(data, forType: .png)
                // The TIFF only if the app pasted into asks for it (most
                // take the PNG): making it here was 30 ms before ⌘V.
                let late = LateTIFF(file: url)
                if entry.setDataProvider(late, forTypes: [.tiff]) { lateTIFF = late }
            }
        case .files:
            if plain {
                // A picture's file whose text was read: its text, as an
                // image's; else the paths.
                entry.setString(item.imageText ?? item.text, forType: .string)
            } else {
                // Only the files still there: a path to nothing pastes
                // nothing, and Finder refuses the lot.
                urls = files(of: item).there.map { NSURL(fileURLWithPath: $0) }
                guard !urls.isEmpty else { return false }
            }
        }
        pasteboard.clearContents()
        return urls.isEmpty ? pasteboard.writeObjects([entry]) : pasteboard.writeObjects(urls)
    }

    /// The formats kept with a copy, on the item to paste, in their order.
    private func set(_ formats: [ClipboardFormats.Format]?, on entry: NSPasteboardItem) {
        for format in formats ?? [] {
            entry.setData(format.data, forType: NSPasteboard.PasteboardType(format.type))
        }
    }

    /// A files copy's paths: those still there, and the names of those
    /// moved or deleted since. Looked for when the copy is used (pasted,
    /// copied, shown), never while the list is drawn.
    func files(of item: ClipboardStore.Item) -> (there: [String], gone: [String]) {
        guard item.kind == .files else { return ([], []) }
        var there: [String] = []
        var gone: [String] = []
        for path in item.text.split(separator: "\n").map(String.init) {
            if FileManager.default.fileExists(atPath: path) {
                there.append(path)
            } else {
                gone.append((path as NSString).lastPathComponent)
            }
        }
        return (there, gone)
    }

    /// Several copies as one, put on the clipboard: one text, or the
    /// files still there (`gone`: the names of the others). False when
    /// nothing could be put there.
    func write(_ paste: ClipboardSelection.Paste, plain: Bool) -> (written: Bool, gone: [String]) {
        switch paste {
        case .text(let text):
            return (write(text: text), [])
        case .files(let paths):
            if plain { return (write(text: paths.joined(separator: "\n")), []) }
            let there = paths.filter { FileManager.default.fileExists(atPath: $0) }
            let gone = paths.filter { !there.contains($0) }.map { ($0 as NSString).lastPathComponent }
            guard !there.isEmpty else { return (false, gone) }
            pasteboard.clearContents()
            return (pasteboard.writeObjects(there.map { NSURL(fileURLWithPath: $0) }), gone)
        case .none:
            return (false, [])
        }
    }

    /// A text put on the clipboard for ⌘V: a copy pasted another way
    /// (`ClipboardTransform`). It joins the history as any copy.
    func write(text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// The picture last put on the clipboard, for the TIFF asked later.
    @ObservationIgnored private var lateTIFF: LateTIFF?

    /// A kept picture's TIFF, made from its PNG when an app asks the
    /// clipboard for it. Not asked before skil.li quits: the clipboard
    /// keeps the PNG alone.
    private final class LateTIFF: NSObject, NSPasteboardItemDataProvider {
        /// The kept picture's PNG file.
        private let file: URL

        init(file: URL) {
            self.file = file
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            guard type == .tiff, let data = try? Data(contentsOf: file), let tiff = NSImage(data: data)?.tiffRepresentation else { return }
            item.setData(tiff, forType: .tiff)
        }
    }

    // MARK: - Paste in Sequence

    @ObservationIgnored private var sequence = PasteSequence()
    /// The copies of the sequence under way, by id, as it began.
    @ObservationIgnored private var sequenceItems: [Int64: ClipboardStore.Item] = [:]
    /// What to say with the copy just put there: its files moved or
    /// deleted since (the others are pasted). Nil for nothing.
    @ObservationIgnored private(set) var sequenceNote: String?

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
        return put(id)
    }

    /// Paste in Sequence on the copies selected in the history, in the
    /// order they paste (the order copied): the first one put on the
    /// clipboard for ⌘V, each Paste in Sequence after it the next. Nil
    /// once it is there; else why nothing is, in one line.
    func putFirstInSequence(of items: [ClipboardStore.Item], now: Date = .now) -> String? {
        guard preferences.clipboardHistory, store != nil else { return "Clipboard History is off: turn it on in Settings → Clipboard." }
        sequenceItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return put(sequence.begin(with: items.map(\.id), now: now))
    }

    /// The sequence's copy on the clipboard; nil once it is there
    /// (`sequenceNote`: what to say with it).
    private func put(_ id: Int64?) -> String? {
        sequenceNote = nil
        guard let id, let item = sequenceItems[id] else {
            return sequenceItems.isEmpty ? "Nothing copied yet." : sequence.end
        }
        let files = files(of: item)
        guard write(item, plain: false) else {
            // Selected copies: the next key goes on with the next one,
            // the first as any other (the clipboard as it is now is the
            // sequence's, not a copy of the user's own).
            if sequence.chosen { sequence.wrote(changeCount: pasteboard.changeCount) }
            return ClipboardFiles.line(gone: files.gone, of: files.gone.count, done: "pasted") ?? "That copy is gone from the history."
        }
        sequenceNote = ClipboardFiles.line(gone: files.gone, of: files.there.count + files.gone.count, done: "pasted")
        // Whatever changes the clipboard after this is the user's own copy.
        sequence.wrote(changeCount: pasteboard.changeCount)
        Log.trace("Paste in Sequence: copy \(sequence.position + 1) of \(sequence.ids.count)\(sequence.chosen ? " selected" : ""), \(item.kind.rawValue)")
        return nil
    }

    // MARK: - Reading the clipboard

    /// Every format of the clipboard's first item worth keeping with the
    /// copy (`ClipboardFormats`): read in the app's order, each one asked
    /// of the app copied from, until they no longer fit or took too long.
    /// Nil for none.
    private static func formats(on pasteboard: NSPasteboard) -> [ClipboardFormats.Format]? {
        guard let first = pasteboard.pasteboardItems?.first else { return nil }
        let start = ContinuousClock.now
        var kept: [ClipboardFormats.Format] = []
        var total = 0
        for type in first.types where ClipboardFormats.keeps(type.rawValue) {
            guard ContinuousClock.now - start < ClipboardFormats.readBudget else { break }
            guard let data = first.data(forType: type), !data.isEmpty, total + data.count <= ClipboardFormats.limit else { continue }
            kept.append(.init(type: type.rawValue, data: data))
            total += data.count
        }
        return kept.isEmpty ? nil : kept
    }

    private static let imageTypes: Set<String> = [
        NSPasteboard.PasteboardType.png.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        "public.jpeg",
        "public.heic"
    ]

    /// What is on the clipboard, as the history keeps it; nil for nothing
    /// worth keeping, secrets and excluded apps.
    static func read(_ pasteboard: NSPasteboard, app: String?, appName: String?, excluded: Set<String>,
                     keepsSecrets: Bool = false) -> ClipboardStore.NewItem? {
        switch look(pasteboard, app: app, appName: appName, excluded: excluded, keepsSecrets: keepsSecrets) {
        case nil, .notKept: nil
        case .item(let new): new
        case .later(let make): if case .item(let new) = make() { new } else { nil }
        }
    }

    /// What `look` read on the clipboard: a copy ready to keep, one not
    /// kept that the history says, or one whose making is heavy and can
    /// run on any thread (then one of the first two, or nil: not worth
    /// keeping after all).
    enum Looked {
        case item(ClipboardStore.NewItem)
        case notKept(ClipboardNotKept.Reason)
        case later(@Sendable () -> Made?)
    }

    /// What a heavy copy turned out to be.
    enum Made: Sendable {
        case item(ClipboardStore.NewItem)
        case notKept(ClipboardNotKept.Reason)
    }

    /// A text longer than this is hashed and stored off the main thread.
    static let longText = 100_000
    /// With keys looked for in it (Never keep keys and tokens, on), a
    /// text longer than this: under a millisecond on the main thread.
    static let longTextForKeys = 20_000

    /// Reads the clipboard: only the pasteboard's own calls and what is
    /// short. Nil for nothing worth keeping, what a password manager
    /// marks secret and excluded apps. `keepsSecrets`: keys and tokens known
    /// by their shape are kept too (Settings → Clipboard → Advanced, off).
    static func look(_ pasteboard: NSPasteboard, app: String?, appName: String?, excluded: Set<String>, keepsSecrets: Bool = false) -> Looked? {
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard ClipboardPolicy.shouldRecord(types: types, app: app, excluded: excluded) else { return nil }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path).joined(separator: "\n")
            return .item(ClipboardStore.NewItem(kind: .files, text: paths, app: app, appName: appName, hash: hash("files", Data(paths.utf8))))
        }

        let string = pasteboard.string(forType: .string)
        // Office apps put a picture of the cells after their text: text
        // first means text.
        let imageFirst = types.first.map(imageTypes.contains) ?? false
        // Stops at the first character that is not a space: a long text is
        // not copied whole to be trimmed.
        if let string, string.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }), !imageFirst {
            let kept = formats(on: pasteboard)
            // A key or a token by its shape (a few patterns on one word,
            // a private key's header), then the size, then the copy.
            let make: @Sendable () -> Made? = {
                if !keepsSecrets {
                    if let name = ClipboardSecret.name(of: string) { return .notKept(.secret(name)) }
                    if let name = ClipboardSecret.held(in: string) { return .notKept(.holdsSecret(name)) }
                }
                guard string.utf8.count <= ClipboardPolicy.textLimit else { return .notKept(.longText) }
                return .item(ClipboardStore.NewItem(kind: .text, text: string, formats: kept, app: app, appName: appName,
                                                    hash: hash("text", Data(string.utf8))))
            }
            // `utf16.count` costs nothing on a string the pasteboard gave.
            // Looked through for a key, a shorter one already: 100,000
            // characters take 4 to 6 ms (`ClipboardSecret.held`).
            if string.utf16.count > (keepsSecrets ? longText : longTextForKeys) { return .later(make) }
            switch make() {
            case .item(let new): return .item(new)
            case .notKept(let reason): return .notKept(reason)
            case nil: return nil
            }
        }

        // The picture as it is there; what is made of it is heavy.
        let png = pasteboard.data(forType: .png)
        guard let data = png ?? pasteboard.data(forType: .tiff) ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation else { return nil }
        guard data.count <= ClipboardPolicy.pictureLimit else { return .notKept(.bigPicture) }
        // What the app put with the picture: a shape or a slide's object
        // pastes back as one, not as its picture.
        let kept = formats(on: pasteboard)
        return .later {
            guard let rep = NSBitmapImageRep(data: data), let png = png ?? rep.representation(using: .png, properties: [:]) else { return nil }
            // A copied web image keeps its address: searchable too.
            return .item(ClipboardStore.NewItem(kind: .image, text: string ?? "", imageData: png, size: "\(rep.pixelsWide)×\(rep.pixelsHigh)",
                                                formats: kept, app: app, appName: appName, hash: hash("image", png)))
        }
    }

    /// The clipboard's image as it is there, for Vision to read
    /// (`get_clipboard`): PNG, TIFF, a JPEG or a HEIC as copied (the 40 MB
    /// bound is on what was copied, not on a TIFF made from it), else
    /// whatever AppKit reads as an image.
    static func imageData(on pasteboard: NSPasteboard) -> Data? {
        let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
            ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.heic"))
            ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation
        guard let data, data.count <= 40_000_000 else { return nil }
        return data
    }

    /// Same content, same hash, whoever copied it (the self-test too).
    nonisolated static func hash(_ kind: String, _ data: Data) -> String {
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

    /// The picture an app put on the clipboard beside its file, as data
    /// (PNG, TIFF, JPEG, HEIC). Only what is there as data: nothing here
    /// opens the file.
    static func pictureData(on pasteboard: NSPasteboard) -> Data? {
        let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
            ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.heic"))
        guard let data, data.count <= 40_000_000 else { return nil }
        return data
    }

    /// A picture's file copied with the picture beside it: its text, when
    /// the data holds some. None found says nothing about the file (Finder
    /// puts an icon there): it stays unread.
    private func readText(inCopied data: Data, id: Int64) {
        let store = self.store
        Task.detached(priority: .utility) { [weak self] in
            guard let text = await Self.recognizeText(in: data) else { return }
            try? store?.setOCR(text, for: id)
            Log.trace("Clipboard: OCR read \(text.count) characters in a picture copied beside its file")
            await MainActor.run { self?.revision += 1 }
        }
    }

    /// The picture files tried since launch: one try a run.
    @ObservationIgnored private var pictureFilesTried: Set<Int64> = []

    /// A picture copied as its file, never read, shown in the history's
    /// preview: its text read then, from the picture Quick Look draws of
    /// it, and `then` given the copy as it is now. Only then: the preview
    /// asks Quick Look for that file anyway, so nothing new is asked of
    /// macOS; read at copy or at launch, a file in Downloads or on the
    /// Desktop made macOS ask for the folder in skil.li's name, out of
    /// nowhere (seen 2026-11-10). Read with no text in it: kept as read.
    /// Not read (Quick Look or Vision failed): left unread, tried again
    /// the next time skil.li runs and it is shown.
    func readText(inPictureFile item: ClipboardStore.Item, then: @escaping @MainActor (ClipboardStore.Item) -> Void) {
        guard let store, preferences.clipboardOCR, item.ocr == nil, let file = item.pictureFile,
              pictureFilesTried.insert(item.id).inserted else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let start = ContinuousClock.now
            guard let text = await Self.recognizeText(inFile: file) else {
                Log.trace("Clipboard: a copied picture file could not be read for its text")
                return
            }
            try? store.setOCR(text, for: item.id)
            Log.trace("Clipboard: OCR read \(text.count) characters in a copied picture file in \((ContinuousClock.now - start).compact)")
            guard let read = store.items([item.id]).first else { return }
            await MainActor.run {
                self?.revision += 1
                then(read)
            }
        }
    }

    /// The text in a picture file, read in Quick Look's picture of it, up
    /// to 3,000 pixels a side: "" when it was read and holds none, nil
    /// when it could not be read (no picture from Quick Look, or Vision
    /// failed).
    nonisolated static func recognizeText(inFile url: URL) async -> String? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 3_000, height: 3_000), scale: 1,
                                                   representationTypes: .thumbnail)
        guard let picture = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
              let observations = try? await textRequest.perform(on: picture.cgImage) else { return nil }
        return text(of: observations) ?? ""
    }

    /// The image's text, line by line, in whatever language it is.
    nonisolated static func recognizeText(in url: URL) async -> String? {
        text(of: try? await textRequest.perform(on: url))
    }

    /// The same from an image's data (the clipboard's: no file written).
    nonisolated static func recognizeText(in image: Data) async -> String? {
        text(of: try? await textRequest.perform(on: image))
    }

    nonisolated private static var textRequest: RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        return request
    }

    nonisolated private static func text(of observations: [RecognizedTextObservation]?) -> String? {
        guard let observations else { return nil }
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}

/// A picture copy dragged out of the history is given as a file under a
/// name a person reads: a copy of the history's own, in the temporary
/// folder, in a folder of its own named by the copy's id. It lives as
/// long as the history keeps that picture and no longer: removed when
/// that copy is forgotten or removed by Keep copies for, when its drag is
/// let go over nothing, when the history is cleared, and when the app
/// starts. Another copy dragged or removed leaves it: an app that reads
/// the dropped file a moment later still finds it.
enum ClipboardDragExports {
    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("skilli-drag", isDirectory: true)
    }

    private static func folder(of id: Int64) -> URL {
        folder.appendingPathComponent(String(id), isDirectory: true)
    }

    /// The picture of copy `id`, at `stored`, as a file under `name`:
    /// the one made for an earlier drag of it when it is still there
    /// (`made` false: an app may be reading it, it is not this drag's to
    /// remove), else a new copy. Nil when it could not be made.
    static func make(from stored: URL, named name: String, id: Int64) -> (file: URL, made: Bool)? {
        let named = folder(of: id).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: named.path) { return (named, false) }
        do {
            try FileManager.default.createDirectory(at: folder(of: id), withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try FileManager.default.copyItem(at: stored, to: named)
            return (named, true)
        } catch {
            return nil
        }
    }

    /// The file made for copy `id`, gone.
    static func remove(_ id: Int64) {
        try? FileManager.default.removeItem(at: folder(of: id))
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}
