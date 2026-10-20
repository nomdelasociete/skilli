import AppKit
import Carbon.HIToolbox
import Observation
import SkilliCore

/// Owns `ShortcutConfig`: loads and saves it, validates edits, builds the
/// binding engine the router uses, and records new shortcuts from the
/// keyboard for Settings.
@MainActor
@Observable
final class ShortcutStore {
    /// Pseudo entry id for the launcher's own "Open Settings" shortcut.
    static let launcherOpenSettingsID = "launcher.openSettings"
    /// How long recording waits for the next chord of a chain before it
    /// saves what was typed (Return saves at once).
    static let sequencePause: TimeInterval = 1.5
    static let maxChords = 3

    private(set) var config: ShortcutConfig
    /// A shortcut's ⓧ and Keys' Delete go through it: ⌘Z gives the keys
    /// back for 10 s (`UndoableDeletes.shortcut`).
    @ObservationIgnored var deletes: UndoableDeletes?
    /// Entries a hand-edited file made unusable, with why.
    private(set) var problems: [String: String] = [:]
    /// Entries that work but share their keys with something else, which
    /// they take first (macOS's own, the launcher's): read from a file,
    /// or macOS's turned on after they were recorded.
    private(set) var warnings: [String: Warning] = [:]

    struct Warning: Equatable {
        let message: String
        /// Where System Settings frees the keys, when it can.
        var keyboardSection: String?
        /// Said plainly, not a warning: the keys replace macOS's own on
        /// purpose ("Replaces macOS's Emoji & Symbols.").
        var isNote = false
    }

    /// Why the keys just pressed were refused.
    struct Refusal: Equatable {
        let id: String
        let message: String
        /// Where System Settings frees the keys, when macOS has them.
        var keyboardSection: String?
    }

    private(set) var recordingID: String?
    private(set) var recordedChords: [Chord] = []
    /// When recording saves on its own unless another chord comes; drives
    /// the countdown in Settings.
    private(set) var recordingDeadline: Date?
    private(set) var lastError: Refusal?

    @ObservationIgnored var onEngineChange: (@MainActor (BindingEngine<SkilliAction>) -> Void)?
    @ObservationIgnored var onRecordingChange: (@MainActor (Bool) -> Void)?
    /// Hardware key code → layout key, from `KeyboardLayout`.
    @ObservationIgnored var resolveKey: (@MainActor (UInt16) -> Key?) = { _ in nil }
    /// macOS's shortcuts as System Settings keeps them, read afresh each
    /// time: one turned off there can be recorded at once. The self-test
    /// swaps it (Spotlight's ⌘Space on, without touching macOS).
    @ObservationIgnored var readSystemHotKeys: @MainActor () -> [String: Any]? = {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
    }
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var commitTimer: Timer?

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true)
            .appendingPathComponent("shortcuts.json")
    }

    /// `fileURL == nil` keeps everything in memory (benchmark).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        config = Self.load(from: fileURL)
    }

    // MARK: - Engine

    func makeEngine() -> BindingEngine<SkilliAction> {
        var engine = BindingEngine<SkilliAction>()
        var problems: [String: String] = [:]
        for entry in config.shortcuts {
            guard let keys = entry.keys else { continue }
            do {
                try engine.bind(Chord.sequence(keys), label: entry.title, to: entry.action)
            } catch {
                problems[entry.id] = "Ignored: “\(keys)” conflicts with another shortcut or cannot be read."
            }
        }
        for group in config.groups {
            if let prefix = try? Chord.sequence(group.keys) {
                try? engine.labelGroup(prefix, group.label)
            }
        }
        self.problems = problems
        refreshWarnings()
        return engine
    }

    /// The keys macOS and the launcher answer, as `KeyOwner`s: what a
    /// shortcut may not take. The launcher's own Open Settings is left out
    /// when `id` is it.
    func owners(excluding id: String? = nil) -> [KeyOwner] {
        var launcher = LauncherKeys.all
        if id != Self.launcherOpenSettingsID, let chord = launcherOpenSettingsChord {
            launcher.append(KeyOwner(chord: chord, name: LauncherKeys.openSettingsName, kind: .launcher))
        }
        return launcher + SystemShortcuts.owners(in: readSystemHotKeys(), resolve: { self.resolveKey($0) })
    }

    /// Who else answers the key `chords` start with, if anyone: not one
    /// `action` replaces (Emoji & Symbols for skil.li's emoji search).
    func owner(of chords: [Chord], excluding id: String? = nil, for action: SkilliAction? = nil) -> KeyOwner? {
        KeyOwner.owner(of: chords, in: owners(excluding: id), for: action?.id)
    }

    /// Says which shortcuts share their keys with macOS or the launcher,
    /// read afresh (Settings calls it as it appears: a shortcut turned off
    /// in System Settings meanwhile is no longer said).
    func refreshWarnings() {
        let owners = owners()
        var warnings: [String: Warning] = [:]
        for entry in config.shortcuts where problems[entry.id] == nil {
            guard let chords = entry.chords else { continue }
            if let owner = KeyOwner.owner(of: chords, in: owners, for: entry.action.id) {
                warnings[entry.id] = Warning(message: owner.sharing, keyboardSection: owner.section)
            } else if let replaced = KeyOwner.replaced(by: entry.action.id, with: chords, in: owners) {
                warnings[entry.id] = Warning(message: replaced.replaced, isNote: true)
            }
        }
        if let chord = launcherOpenSettingsChord {
            if let entry = config.shortcuts.first(where: { problems[$0.id] == nil && $0.chords?.first == chord }) {
                warnings[Self.launcherOpenSettingsID] = Warning(message: "“\(title(of: entry))” has these keys too and runs instead, even in the launcher.")
            } else if let owner = KeyOwner.owner(of: [chord], in: owners.filter { $0.kind != .launcher }) {
                warnings[Self.launcherOpenSettingsID] = Warning(message: owner.sharing, keyboardSection: owner.section)
            }
        }
        if warnings != self.warnings { self.warnings = warnings }
    }

    /// The launcher's name where its keys are shown (General, Keys,
    /// Launcher, the status menu) and in a refusal.
    static let launcherTitle = "Open skil.li"

    /// What a refusal calls `entry`: the launcher by its name in Settings.
    func title(of entry: ShortcutConfig.Entry) -> String {
        entry.id == launcherEntry?.id ? Self.launcherTitle : entry.title
    }

    /// The launcher's own entry: the first of the shortcuts that open it
    /// (a user may add more). General, Keys, Launcher and the status menu
    /// show this one.
    var launcherEntry: ShortcutConfig.Entry? {
        config.shortcuts.first { $0.action == .toggleLauncher }
    }

    var launcherOpenSettingsChord: Chord? {
        config.launcherOpenSettings.flatMap { try? Chord(parsing: $0) }
    }

    /// Group title for entries under `chords`' prefix, if any.
    func group(containing chords: [Chord]) -> (prefix: [Chord], label: String)? {
        for group in config.groups {
            guard let prefix = try? Chord.sequence(group.keys) else { continue }
            if chords.count > prefix.count, chords.starts(with: prefix) {
                return (prefix, group.label)
            }
        }
        return nil
    }

    // MARK: - Editing

    /// Saves `chords` for `id` (nil or none: no keys), once `validated`. A
    /// shortcut the command editor holds keeps them until its Save.
    func setKeys(_ chords: [Chord]?, for id: String) throws {
        if let index = staged?.entries.firstIndex(where: { $0.id == id }) {
            let keys = try chords.flatMap { $0.isEmpty ? nil : Chord.spec(try validated($0, for: id)) }
            staged?.entries[index].keys = keys
            lastError = nil
            return
        }
        if id == Self.launcherOpenSettingsID {
            guard let chords, !chords.isEmpty else {
                config.launcherOpenSettings = nil
                return commit()
            }
            config.launcherOpenSettings = Chord.spec(try validated(chords, for: id))
            return commit()
        }
        guard let index = config.shortcuts.firstIndex(where: { $0.id == id }) else { return }
        guard let chords, !chords.isEmpty else {
            config.shortcuts[index].keys = nil
            return commit()
        }
        config.shortcuts[index].keys = Chord.spec(try validated(chords, for: id))
        commit()
    }

    /// The keys as `id` would keep them, or why it cannot: two actions
    /// never share keys. Refused when they equal or start another of
    /// skil.li's shortcuts, or when macOS or the launcher answers their
    /// first key (`KeyOwner`), unless the action (`id`'s, or `action` for
    /// one not added yet) replaces it. The launcher's Open Settings (one
    /// key, only while it is open) is refused on a key a shortcut starts
    /// with. The recorder, Settings' fields and the settings tools all ask
    /// here.
    func validated(_ chords: [Chord], for id: String?, action: SkilliAction? = nil) throws -> [Chord] {
        if id == Self.launcherOpenSettingsID {
            guard chords.count == 1, let chord = chords.first else { throw ShortcutError.invalid }
            guard !chord.modifiers.intersection([.command, .control, .option]).isEmpty else {
                throw ShortcutError.needsModifier
            }
            if let other = config.shortcuts.first(where: { $0.chords?.first == chord }) {
                throw ShortcutError.conflict(with: title(of: other))
            }
            if let owner = owner(of: [chord], excluding: id) {
                throw ShortcutError.taken(owner)
            }
            return [chord]
        }
        // Written as the engine matches it: `cmd+space cmd+space` is
        // `cmd+space space`.
        let chain = Chord.chain(chords)
        guard let first = chain.first else { throw ShortcutError.invalid }
        guard !first.modifiers.intersection([.command, .control, .option]).isEmpty else {
            throw ShortcutError.needsModifier
        }
        if let other = conflict(for: chain, excluding: id) {
            throw ShortcutError.conflict(with: title(of: other))
        }
        let action = action ?? id.flatMap { entry($0) }?.action
        if let owner = owner(of: chain, excluding: id, for: action) {
            throw ShortcutError.taken(owner)
        }
        return chain
    }

    /// Back to the default keys (and label) for a built-in entry.
    func reset(_ id: String) {
        if let index = staged?.entries.firstIndex(where: { $0.id == id }) {
            // Held by the command editor: nothing else is changed for it,
            // so keys another shortcut took are refused instead.
            guard let original = config.defaultEntry(id: id) else { return }
            do {
                var entry = original
                entry.keys = try original.chords.map { Chord.spec(try validated($0, for: id)) }
                staged?.entries[index] = entry
                lastError = nil
            } catch {
                fail(id, error)
            }
            return
        }
        if id == Self.launcherOpenSettingsID {
            config.launcherOpenSettings = ShortcutConfig.defaults.launcherOpenSettings
            return commit()
        }
        guard let index = config.shortcuts.firstIndex(where: { $0.id == id }),
              let original = config.defaultEntry(id: id)
        else { return }
        // Free the default keys first if another entry took them.
        if let keys = original.keys, let chords = try? Chord.sequence(keys),
           let other = conflict(for: chords, excluding: id),
           let otherIndex = config.shortcuts.firstIndex(where: { $0.id == other.id }) {
            config.shortcuts[otherIndex].keys = nil
        }
        config.shortcuts[index] = original
        commit()
    }

    func resetAll() {
        config = .defaults
        commit()
    }

    /// What Restore Defaults takes back: the shortcuts the user added, and
    /// the built-in ones whose keys (or name) differ, the launcher's Open
    /// Settings and a chain's name among them. Order alone is no change.
    var changesFromDefaults: (custom: Int, changed: Int) {
        let defaults = ShortcutConfig.defaults
        let custom = config.shortcuts.filter { config.defaultEntry(id: $0.id) == nil }.count
        var changed = defaults.shortcuts.filter { original in config.shortcuts.first { $0.id == original.id } != original }.count
        if config.launcherOpenSettings != defaults.launcherOpenSettings { changed += 1 }
        let groups = { (groups: [ShortcutConfig.Group]) in groups.map { "\($0.keys)=\($0.label)" }.sorted() }
        if groups(config.groups) != groups(defaults.groups) { changed += 1 }
        return (custom, changed)
    }

    /// Keys' Restore Defaults dialog: what goes; nil when nothing differs
    /// (the button is off).
    var restoreDefaultsMessage: String? {
        let changes = changesFromDefaults
        return RestoreDefaults.message(custom: changes.custom, changed: changes.changed)
    }

    /// Self-test hook: `config` in place as a hand-edited file is read
    /// (nothing checked before), the engine rebuilt from it.
    func replaceForSelfTest(_ config: ShortcutConfig) {
        self.config = config
        commit()
    }

    /// The ⓧ in Settings: an extra shortcut (another entry runs the same
    /// action) goes away; otherwise the entry stays, without keys, so the
    /// command keeps its row and can be recorded again.
    func clear(_ id: String) {
        guard let entry = entry(id) else {
            if id == Self.launcherOpenSettingsID { try? setKeys(nil, for: id) }
            return
        }
        let siblings = staged?.entries.contains { $0.id == id } == true ? staged?.entries ?? [] : config.shortcuts
        let others = siblings.contains { $0.id != id && $0.action == entry.action }
        if isCustom(id), others {
            remove(id)
        } else {
            try? setKeys(nil, for: id)
        }
    }

    /// Custom entries are deleted; built-in ones lose their keys.
    func remove(_ id: String) {
        if let index = staged?.entries.firstIndex(where: { $0.id == id }) {
            if config.defaultEntry(id: id) == nil {
                staged?.entries.remove(at: index)
            } else {
                staged?.entries[index].keys = nil
            }
            lastError = nil
            return
        }
        guard let index = config.shortcuts.firstIndex(where: { $0.id == id }) else { return }
        if config.defaultEntry(id: id) == nil {
            config.shortcuts.remove(at: index)
        } else {
            config.shortcuts[index].keys = nil
        }
        commit()
    }

    /// Drops every entry running `action` (a deleted AI command).
    func removeEntries(for action: SkilliAction) {
        guard config.shortcuts.contains(where: { $0.action == action }) else { return }
        // Built-in entries stay (keys cleared below); custom ones go.
        let builtInIDs = Set(ShortcutConfig.defaults.shortcuts.map(\.id))
        config.shortcuts.removeAll { $0.action == action && !builtInIDs.contains($0.id) }
        for index in config.shortcuts.indices where config.shortcuts[index].action == action {
            config.shortcuts[index].keys = nil
        }
        commit()
    }

    /// Puts back entries removed with what they ran (a window layout's,
    /// on Undo); one whose id or keys are taken meanwhile stays out.
    func restore(_ entries: [ShortcutConfig.Entry]) {
        for entry in entries where !config.shortcuts.contains(where: { $0.id == entry.id }) {
            if let chords = entry.chords, conflict(for: chords, excluding: entry.id) != nil { continue }
            config.shortcuts.append(entry)
        }
        commit()
    }

    /// Adds an unbound entry for `action` and returns its id, ready to record.
    @discardableResult
    func add(_ action: SkilliAction, label: String? = nil) -> String {
        let id = "custom.\(UUID().uuidString.prefix(8).lowercased())"
        config.shortcuts.append(.init(id: id, action: action, keys: nil, label: label))
        commit()
        return id
    }

    func isModified(_ id: String) -> Bool {
        if id == Self.launcherOpenSettingsID {
            return config.launcherOpenSettings != ShortcutConfig.defaults.launcherOpenSettings
        }
        guard let original = config.defaultEntry(id: id) else { return false }
        return entry(id) != original
    }

    func isCustom(_ id: String) -> Bool {
        id != Self.launcherOpenSettingsID && config.defaultEntry(id: id) == nil
    }

    /// The shortcut `chords` would equal or start (or that starts them),
    /// `id`'s own aside: Settings' recorder and the settings tools refuse it.
    func conflict(for chords: [Chord], excluding id: String?) -> ShortcutConfig.Entry? {
        let chords = Chord.chain(chords)
        return others(than: id).first { entry in
            guard entry.id != id, let other = entry.chords.map(Chord.chain) else { return false }
            return other.starts(with: chords) || chords.starts(with: other)
        }
    }

    /// What `id`'s keys may not equal or start: every shortcut, and while
    /// the command editor holds some, those too; for one it holds, not the
    /// saved ones it began with (Save replaces them).
    private func others(than id: String?) -> [ShortcutConfig.Entry] {
        guard let staged else { return config.shortcuts }
        guard let id, staged.entries.contains(where: { $0.id == id }) else { return config.shortcuts + staged.entries }
        let replaced = Set(staged.original.map(\.id))
        return config.shortcuts.filter { !replaced.contains($0.id) } + staged.entries
    }

    /// `id`'s entry as Settings shows it: the command editor's while it
    /// holds it, else the saved one.
    private func entry(_ id: String) -> ShortcutConfig.Entry? {
        staged?.entries.first { $0.id == id } ?? config.shortcuts.first { $0.id == id }
    }

    // MARK: - The command editor's shortcuts

    /// A command's shortcuts while its editor is open (Settings →
    /// Commands): recorded, checked and shown like the others, but neither
    /// saved nor bound until Save (`commitStaged`); Cancel drops them
    /// (`discardStaged`).
    struct Staged: Equatable {
        let action: SkilliAction
        /// The saved shortcuts it began with.
        let original: [ShortcutConfig.Entry]
        var entries: [ShortcutConfig.Entry]
    }

    private(set) var staged: Staged?

    /// The editor opens on `action`: its saved shortcuts, to change until
    /// Save. A new command (`empty`) starts with one row ready to record.
    func stage(_ action: SkilliAction, empty: Bool = false) {
        endRecording()
        lastError = nil
        let saved = config.shortcuts.filter { $0.action == action }
        staged = Staged(action: action, original: saved, entries: saved)
        if empty, saved.isEmpty { addStaged() }
    }

    /// Add Shortcut in the editor: an empty row for its command, kept with
    /// the others until Save. Its id, ready to record.
    @discardableResult
    func addStaged() -> String {
        let id = "custom.\(UUID().uuidString.prefix(8).lowercased())"
        if let action = staged?.action {
            staged?.entries.append(.init(id: id, action: action, keys: nil, label: nil))
        }
        return id
    }

    /// The editor's shortcuts for `action`, or the saved ones when it is
    /// not open on it.
    func editorEntries(for action: SkilliAction) -> [ShortcutConfig.Entry] {
        staged?.action == action ? staged?.entries ?? [] : config.shortcuts.filter { $0.action == action }
    }

    /// Save in the editor: its shortcuts take the place of those it began
    /// with. Keys another shortcut took meanwhile (an agent, the launcher)
    /// are left empty.
    func commitStaged(_ action: SkilliAction) {
        guard let staged, staged.action == action else { return }
        endRecording()
        self.staged = nil
        let replaced = Set(staged.original.map(\.id))
        let kept = config.shortcuts.filter { !replaced.contains($0.id) }
        var placed: [ShortcutConfig.Entry] = []
        var shortcuts: [ShortcutConfig.Entry] = []
        func checked(_ entry: ShortcutConfig.Entry) -> ShortcutConfig.Entry {
            guard let chords = entry.chords.map(Chord.chain) else { return entry }
            let taken = (kept + placed).contains { other in
                guard let keys = other.chords.map(Chord.chain) else { return false }
                return keys.starts(with: chords) || chords.starts(with: keys)
            }
            var entry = entry
            if taken { entry.keys = nil }
            placed.append(entry)
            return entry
        }
        // Where they were, so Keys keeps its order; new ones at the end.
        for entry in config.shortcuts {
            if replaced.contains(entry.id) {
                if let edited = staged.entries.first(where: { $0.id == entry.id }) { shortcuts.append(checked(edited)) }
            } else {
                shortcuts.append(entry)
            }
        }
        for entry in staged.entries where !replaced.contains(entry.id) {
            shortcuts.append(checked(entry))
        }
        guard shortcuts != config.shortcuts else { return }
        config.shortcuts = shortcuts
        commit()
    }

    /// Cancel, esc or the window closed: the editor's shortcuts go, the
    /// saved ones stay as they were. Nothing when it holds another
    /// command's (`action`) or none.
    func discardStaged(_ action: SkilliAction? = nil) {
        guard let staged, action == nil || staged.action == action else { return }
        if let id = recordingID, staged.entries.contains(where: { $0.id == id }) { endRecording() }
        if lastError.map({ error in staged.entries.contains { $0.id == error.id } }) == true { lastError = nil }
        self.staged = nil
    }

    private func commit() {
        lastError = nil
        onEngineChange?(makeEngine())
        save()
    }

    // MARK: - Recording

    /// Records the next shortcut typed. Keys come from the event tap
    /// (`handleRecording`), ahead of other apps' global hotkeys: a chord
    /// another app registered would otherwise never reach skil.li.
    func beginRecording(_ id: String) {
        if recordingID != nil { endRecording() }
        recordingID = id
        recordedChords = []
        lastError = nil
        onRecordingChange?(true)
    }

    /// Called by the router for every key-down while recording, with Hyper
    /// already applied. Returns `true` when the key was used.
    func handleRecording(_ event: CGEvent) -> Bool {
        guard recordingID != nil, let keyEvent = NSEvent(cgEvent: event), keyEvent.type == .keyDown else { return false }
        return handle(keyEvent)
    }

    func cancelRecording() {
        endRecording()
    }

    /// Returns `true` when the event was used for recording.
    private func handle(_ event: NSEvent) -> Bool {
        guard let id = recordingID else { return false }
        if event.isARepeat { return true }

        var modifiers = Modifiers(event.modifierFlags)
        // Same rule as the engine (`Chord.inChain`): inside a chain, what is
        // still held from its first chord does not count, nor Hyper, so ✦K
        // then ✦Y (Caps Lock kept down) is saved as `hyper+k y`, and ⌘Space
        // then Space with ⌘ kept down as `cmd+space space`.
        if let first = recordedChords.first {
            modifiers = modifiers.inChain(after: first.modifiers)
        }
        let code = Int(event.keyCode)
        if modifiers.isEmpty {
            if code == kVK_Escape {
                endRecording()
                return true
            }
            if code == kVK_Delete || code == kVK_ForwardDelete, recordedChords.isEmpty {
                apply(nil, to: id)
                return true
            }
            if code == kVK_Return || code == kVK_ANSI_KeypadEnter, !recordedChords.isEmpty {
                apply(recordedChords, to: id)
                return true
            }
        }

        guard let key = resolveKey(event.keyCode) else {
            fail(id, ShortcutError.invalid)
            return true
        }
        let chord = Chord(key, modifiers)
        if recordedChords.isEmpty, modifiers.intersection([.command, .control, .option]).isEmpty {
            fail(id, ShortcutError.needsModifier)
            return true
        }
        recordedChords.append(chord)

        if recordedChords.count >= Self.maxChords || id == Self.launcherOpenSettingsID {
            apply(recordedChords, to: id)
        } else {
            // A pause ends the sequence.
            commitTimer?.invalidate()
            recordingDeadline = Date(timeIntervalSinceNow: Self.sequencePause)
            commitTimer = Timer.scheduledTimer(withTimeInterval: Self.sequencePause, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let id = self.recordingID else { return }
                    self.apply(self.recordedChords, to: id)
                }
            }
        }
        return true
    }

    private func apply(_ chords: [Chord]?, to id: String) {

        do {
            try setKeys(chords, for: id)
            endRecording()
        } catch {
            fail(id, error)
        }
    }

    private func fail(_ id: String, _ error: Error) {
        endRecording()
        var section: String?
        if case .taken(let owner) = error as? ShortcutError { section = owner.section }
        lastError = Refusal(id: id, message: (error as? LocalizedError)?.errorDescription ?? "\(error)", keyboardSection: section)
    }

    private func endRecording() {
        commitTimer?.invalidate()
        commitTimer = nil
        recordingDeadline = nil
        let wasRecording = recordingID != nil
        recordingID = nil
        recordedChords = []
        if wasRecording { onRecordingChange?(false) }
    }

    // MARK: - Persistence

    private static func load(from url: URL?) -> ShortcutConfig {
        guard let url, let data = try? Data(contentsOf: url) else { return .defaults }
        do {
            return try JSONDecoder().decode(ShortcutConfig.self, from: data).addingMissingDefaults().normalizingChains()
        } catch {
            // A hand-edit gone wrong must not be overwritten by the next save:
            // keep it next to the new file so nothing typed is lost.
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent().appendingPathComponent("shortcuts.broken-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            Log.input.error("shortcuts.json unreadable (\(error.localizedDescription, privacy: .public)); moved to \(backup.lastPathComponent, privacy: .public), using defaults")
            return .defaults
        }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            Log.input.error("Could not save shortcuts.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}
