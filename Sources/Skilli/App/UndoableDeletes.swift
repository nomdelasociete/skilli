import AppKit
import SkilliCore

/// Rule 2 (AGENTS.md, "Interactions: the six rules"): a delete of the
/// user's data happens at once, nothing asked, and the undo card
/// (`AIActionController.offerUndo`: Undo ⌘Z, Close esc; it never takes ↩)
/// brings it back for 10 s. Every such delete is here, so Settings, the
/// launcher and the self-test run the same code. Secrets (API keys,
/// tokens, a locked form value) wait in memory only for those 10 s and are
/// never logged.
@MainActor
final class UndoableDeletes {
    typealias Offer = @MainActor (_ title: String, _ details: String, _ undo: @escaping @MainActor () throws -> Void) -> Void

    private let offer: Offer

    init(offer: @escaping Offer) {
        self.offer = offer
    }

    /// Settings' lists that keep their own copy (snippets, quicklinks, the
    /// words learned) read again once something came back.
    private static func shownAgain() {
        NotificationCenter.default.post(name: SettingTools.changed, object: nil)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - The launcher

    /// ⌘⌫ in the clipboard history (or ⌘K → Forget): the copy, its image
    /// and its link preview gone from disk at once; ⌘Z puts it back where
    /// it was. `shown` draws the history again.
    func clip(_ item: ClipboardStore.Item, in history: ClipboardHistory, shown: @escaping @MainActor () -> Void) {
        guard let forgotten = history.forget(item) else { return }
        offer("Copy Forgotten", UndoDelete.details(item.title)) {
            try history.restore(forgotten)
            shown()
        }
    }

    /// ⌘K → Move to Trash on a file, once the Finder's Trash has it: ⌘Z
    /// moves it back where it was (under a free name if another file took
    /// its name meanwhile; never over it).
    func movedToTrash(_ original: URL, now trashed: URL) {
        let folder = original.deletingLastPathComponent()
        offer("Moved to Trash", UndoDelete.details(original.lastPathComponent, " from \(FileManager.default.displayName(atPath: folder.path))")) {
            let manager = FileManager.default
            guard manager.fileExists(atPath: trashed.path) else {
                throw Failure(message: "“\(original.lastPathComponent)” is no longer in the Trash.")
            }
            let name = UndoDelete.freeName(for: original.lastPathComponent) { manager.fileExists(atPath: folder.appendingPathComponent($0).path) }
            try manager.moveItem(at: trashed, to: folder.appendingPathComponent(name))
        }
    }

    /// ⌘⌫ in a recording's window, Discard on one never stopped: its
    /// folder (the tracks, the transcript) to the Trash at once; ⌘Z moves
    /// it back where it was (under a free name if another took its place).
    func recording(_ folder: URL, title: String) throws {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: folder, resultingItemURL: &trashed)
        guard let trashed = trashed as URL? else { return }
        Log.trace("Recorder: “\(title)” moved to the Trash")
        NotificationCenter.default.post(name: Recordings.changed, object: nil)
        offer("Recording Deleted", UndoDelete.details(title, ": moved to the Trash.")) {
            let manager = FileManager.default
            guard manager.fileExists(atPath: trashed.path) else {
                throw Failure(message: "“\(title)” is no longer in the Trash.")
            }
            let root = folder.deletingLastPathComponent()
            let name = RecordingFolder.free(folder.lastPathComponent) { manager.fileExists(atPath: root.appendingPathComponent($0).path) }
            try manager.moveItem(at: trashed, to: root.appendingPathComponent(name))
            NotificationCenter.default.post(name: Recordings.changed, object: nil)
        }
    }

    /// ⌘⌫ on a line of a recording's window (phase 4): gone at once (the
    /// window wrote it); ⌘Z brings it back where it was, even after later
    /// changes there (`undo` says false when the window is closed).
    func transcriptLine(_ words: String, undo: @escaping @MainActor () -> Bool) {
        let first = words.split(separator: " ").prefix(8).joined(separator: " ")
        offer("Line Deleted", UndoDelete.details(first + (first.count < words.count ? "…" : ""), "")) {
            guard undo() else { throw Failure(message: "The line can't come back: its recording's window was closed.") }
        }
    }

    /// Settings → Recorder → Remove: Better transcription's files to the
    /// Trash at once (1.6 GB, downloaded again otherwise); ⌘Z moves them
    /// back.
    func betterTranscription(_ store: BetterTranscription) throws {
        let moved = try store.moveToTrash()
        guard !moved.isEmpty else { return }
        Log.trace("Better transcription: moved to the Trash")
        offer("Better Transcription Removed", UndoDelete.details("whisper large-v3-turbo", ": moved to the Trash, macOS's engine from now on.")) {
            try store.putBack(moved)
        }
    }

    /// ⌘K → Delete Layout and Settings → Windows: the layout and its
    /// shortcuts; ⌘Z puts both back.
    func layout(_ layout: SavedWindowLayout, in arranger: WindowArranger, shortcuts: ShortcutStore) {
        let entries = shortcuts.config.shortcuts.filter { $0.action == .windowLayout(layout.id) }
        arranger.delete(layout.id)
        shortcuts.removeEntries(for: .windowLayout(layout.id))
        Log.trace("Window layout “\(layout.name)” deleted")
        offer("Layout Deleted", UndoDelete.details(layout.name, ": its windows stay where they are.")) {
            try arranger.store(layout)
            shortcuts.restore(entries)
            Log.trace("Window layout “\(layout.name)” put back")
        }
    }

    /// Settings → Windows → Forget What skil.li Learned: every place
    /// learned gone at once; ⌘Z brings them back.
    func placements(in learner: WindowLearner) {
        let count = learner.placements.apps.count
        guard count > 0 else { return }
        let forgotten = learner.forget()
        Log.trace("Windows learned: forgotten")
        offer("Window Places Forgotten", UndoDelete.details(count == 1 ? "1 app's places" : "\(count) apps' places",
                                                            ": Arrange Windows learns again from where you put them.")) {
            learner.restore(forgotten)
            Log.trace("Windows learned: put back")
        }
    }

    /// ⌘K → Remove Alias, and an alias removed in Settings → Catalog.
    func alias(of id: String, in preferences: Preferences, shown: @escaping @MainActor () -> Void = {}) {
        guard let removed = RemovedElement.take(from: &preferences.launcherAliases, where: { $0.id == id }) else { return }
        offer("Alias Removed", UndoDelete.details(removed.element.alias, " for \(removed.element.title)")) {
            // Given to another item meanwhile, it stays there.
            removed.putBack(into: &preferences.launcherAliases) { $0.alias == removed.element.alias || $0.id == id }
            shown()
        }
    }

    // MARK: - Settings

    /// Settings → Snippets → Delete: its file and its shortcuts go; ⌘Z
    /// puts both back.
    func snippet(_ snippet: Snippet, in library: SnippetLibrary, shortcuts: ShortcutStore) {
        let entries = shortcuts.config.shortcuts.filter { $0.action == .snippet(snippet.id) }
        guard let deleted = library.delete(snippet.id) else { return }
        shortcuts.removeEntries(for: .snippet(snippet.id))
        offer("Snippet Deleted", UndoDelete.details(snippet.name, snippet.keyword.isEmpty ? "" : " (\(snippet.keyword))")) {
            library.restore(deleted)
            shortcuts.restore(entries)
            Self.shownAgain()
        }
    }

    /// Settings → Commands → Delete (one of the user's): the command and
    /// its shortcuts; ⌘Z puts both back.
    func command(_ id: String, in model: AICommandsModel) {
        let entries = model.shortcuts.config.shortcuts.filter { $0.action == .aiPrompt(id) }
        // Never saved: nothing to bring back, its shortcut rows go.
        guard let deleted = model.library.deleteForUndo(id) else { return model.delete(id) }
        model.shortcuts.removeEntries(for: .aiPrompt(id))
        model.refresh()
        let keys = entries.contains { $0.keys != nil }
        offer("Command Deleted", UndoDelete.details(deleted.command.title, keys ? ": its shortcut too." : "")) {
            let command = model.library.restore(deleted)
            if command.id == id { model.shortcuts.restore(entries) }
            model.refresh()
        }
    }

    /// Settings → Catalog → Quicklinks → Delete: the quicklink and its
    /// shortcuts; ⌘Z puts both back.
    func quicklink(_ link: Quicklink, in store: QuicklinkStore, shortcuts: ShortcutStore) {
        let entries = shortcuts.config.shortcuts.filter { $0.action == .quicklink(link.id) }
        guard let removed = store.delete(link.id) else { return }
        shortcuts.removeEntries(for: .quicklink(link.id))
        offer("Quicklink Deleted", UndoDelete.details(link.name, link.keyword.isEmpty ? "" : " (\(link.keyword))")) {
            store.restore(removed)
            shortcuts.restore(entries)
            Self.shownAgain()
        }
    }

    /// Settings → Your Details: one of the user's other details (an IBAN):
    /// gone with its Keychain value; ⌘Z puts back both.
    func myDetail(_ extra: FormExtra, in preferences: Preferences) {
        let secret = extra.isSensitive ? FormSecrets.value(of: extra) : nil
        guard let removed = RemovedElement.take(extra.id, from: &preferences.formProfiles.mine) else { return }
        FormSecrets.forget(extra)
        offer("Field Forgotten", UndoDelete.details(extra.label.isEmpty ? "A field" : extra.label)) {
            // The value first: the row shown again reads it.
            if let secret { FormSecrets.save(secret, for: extra) }
            removed.putBack(into: &preferences.formProfiles.mine)
        }
    }

    /// A field of a person or company kept in Your Details.
    func detail(_ extra: FormExtra, of person: UUID, in preferences: Preferences) {
        guard let index = preferences.formProfiles.others.firstIndex(where: { $0.id == person }) else { return }
        let secret = extra.isSensitive ? FormSecrets.value(of: extra) : nil
        guard let removed = RemovedElement.take(extra.id, from: &preferences.formProfiles.others[index].extras) else { return }
        FormSecrets.forget(extra)
        let name = preferences.formProfiles.others[index].name
        offer("Field Forgotten", UndoDelete.details(extra.label.isEmpty ? "A field" : extra.label, name.isEmpty ? "" : " of \(name)")) {
            guard let index = preferences.formProfiles.others.firstIndex(where: { $0.id == person }) else { return }
            if let secret { FormSecrets.save(secret, for: extra) }
            removed.putBack(into: &preferences.formProfiles.others[index].extras)
        }
    }

    /// A person or company removed from Your Details, with their fields
    /// and the locked values in the Keychain.
    func person(_ person: FormPerson, in preferences: Preferences) {
        let secrets = person.extras.filter(\.isSensitive).compactMap { extra in FormSecrets.value(of: extra).map { (extra, $0) } }
        guard let removed = RemovedElement.take(person.id, from: &preferences.formProfiles.others) else { return }
        person.extras.forEach(FormSecrets.forget)
        let fields = person.extras.count
        offer("Removed from Your Details", UndoDelete.details(person.name.isEmpty ? "Someone" : person.name,
                                                               fields == 0 ? "" : fields == 1 ? " and their field" : " and their \(fields) fields")) {
            for (extra, secret) in secrets { FormSecrets.save(secret, for: extra) }
            removed.putBack(into: &preferences.formProfiles.others)
        }
    }

    /// Settings → SI Accounts → Remove on the Claude API key.
    func apiKey(in ai: AIStore) {
        guard let key = ai.removeAPIKey() else { return }
        offer("Key Removed", UndoDelete.details("Claude API key")) {
            try ai.saveAPIKey(key)
        }
    }

    /// Settings → SI Accounts → Remove on a deciding key (OpenAI, TypeSafe).
    func decisionKey(_ provider: DecisionProvider, in ai: AIStore) {
        guard let key = ai.removeDecisionKey(for: provider) else { return }
        offer("Key Removed", UndoDelete.details(provider == .openAI ? "OpenAI API key" : "TypeSafe Jev key")) {
            try ai.saveDecisionKey(key, for: provider)
        }
    }

    /// Settings → Tools → a connected server's −: its config, token or
    /// sign-in, its tools' rights and list; ⌘Z puts all back.
    func server(_ name: String, in settings: ToolSettings) {
        guard let removed = settings.removeServer(named: name) else { return }
        offer("Server Removed", UndoDelete.details(name, removed.signIn.isEmpty ? "" : ": its sign-in too.")) {
            settings.restore(removed)
        }
    }

    /// Settings → Tools → Your Tools → −: the tool, its right, its token.
    func customTool(_ name: String, in settings: ToolSettings) {
        guard let removed = settings.removeCustomTool(named: name) else { return }
        offer("Tool Removed", UndoDelete.details(name)) {
            settings.restore(removed)
        }
    }

    /// Settings → Ask → Your Rules → −.
    func rule(_ id: String, in settings: ToolSettings) {
        guard let removed = settings.removeRule(id) else { return }
        // A rule never written (empty) goes without a word.
        guard !removed.element.said.isEmpty else { return }
        offer("Rule Removed", UndoDelete.details(removed.element.text)) {
            settings.restoreRule(removed)
        }
    }

    /// Settings → Ask → On a Schedule → −.
    func scheduledAsk(_ id: UUID, in scheduler: AskScheduler) {
        guard let removed = scheduler.remove(id) else { return }
        offer("Scheduled Ask Deleted", UndoDelete.details(removed.element.schedule.spoken, ": \(UndoDelete.escaped(UndoDelete.shortened(removed.element.ask)))")) {
            scheduler.restore(removed)
        }
    }

    /// Settings → Reminders → a place's −.
    func place(_ place: SavedPlace, in preferences: Preferences) {
        guard let removed = RemovedElement.take(place.id, from: &preferences.reminderPlaces) else { return }
        offer("Place Forgotten", UndoDelete.details(place.name, place.address.isEmpty ? "" : ": \(UndoDelete.escaped(UndoDelete.shortened(place.address)))")) {
            removed.putBack(into: &preferences.reminderPlaces)
        }
    }

    /// Settings → Emoji → Words learned → Forget: none asked first, ⌘Z
    /// brings them back.
    func wordsLearned(in emoji: EmojiLibrary) {
        let count = emoji.saidCount
        guard count > 0 else { return }
        let forgotten = emoji.forgetSaid()
        Self.shownAgain()
        offer("Words Forgotten", UndoDelete.details(count == 1 ? "1 phrase" : "\(count) phrases", " learned from your picks")) {
            emoji.restoreSaid(forgotten)
            Self.shownAgain()
        }
    }

    /// Settings → GitHub → Live updates token → Remove.
    /// Settings → GIFs: the user's own Klipy key; ⌘Z saves it again.
    func klipyKey(in gifs: GIFLibrary) {
        guard let key = gifs.removeOwnKey() else { return }
        offer("Key Removed", UndoDelete.details("Your Klipy key")) {
            try gifs.saveOwnKey(key)
        }
    }

    func relayToken(in github: GitHubBook) {
        guard let token = github.clearRelayToken() else { return }
        offer("Token Removed", UndoDelete.details("Live updates token")) {
            try github.saveRelayToken(token)
        }
    }

    /// A shortcut's ⓧ (an extra one goes with its row, the last is
    /// emptied: `ShortcutStore.clear`) or Delete in Keys: ⌘Z gives its keys
    /// back, unless another shortcut took them meanwhile (said in the card).
    func shortcut(_ id: String, in store: ShortcutStore, deleting: Bool = false) {
        // In the command editor, a draft's: nothing is removed until Save,
        // Cancel takes it back; no card.
        if store.staged?.entries.contains(where: { $0.id == id }) == true {
            if deleting { store.remove(id) } else { store.clear(id) }
            return
        }
        if id == ShortcutStore.launcherOpenSettingsID {
            guard let chord = store.launcherOpenSettingsChord else { return }
            store.clear(id)
            offer("Shortcut Removed", UndoDelete.details(chord.keycaps.joined(), " for Open Settings in the launcher")) {
                try store.setKeys([chord], for: id)
            }
            return
        }
        guard let entry = store.config.shortcuts.first(where: { $0.id == id }), let chords = entry.chords else {
            if deleting { store.remove(id) }
            return
        }
        if deleting { store.remove(id) } else { store.clear(id) }
        offer("Shortcut Removed", UndoDelete.details(chords.map { $0.keycaps.joined() }.joined(separator: " "), " for \(store.title(of: entry))")) {
            if store.config.shortcuts.contains(where: { $0.id == id }) {
                try store.setKeys(chords, for: id)
            } else {
                if let other = store.conflict(for: chords, excluding: id) {
                    throw Failure(message: "Its keys run \(store.title(of: other)) now.")
                }
                store.restore([entry])
            }
        }
    }
}
