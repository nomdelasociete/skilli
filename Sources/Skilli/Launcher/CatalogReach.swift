import SkilliCore

// How a Catalog entry is reached besides its prefix: the shortcut action
// both the "?" and Settings → Catalog show and edit, from one place.

extension CatalogEntry {
    /// The action a global shortcut runs for it, when one can: a skillie
    /// only when it needs no argument, as Settings → Keys → Add Shortcut
    /// lists them. Modes and what types words first have none.
    func shortcutAction(skillies: [ScriptCommand]) -> SkilliAction? {
        switch run {
        case .command(.clipboardHistory): return .clipboardHistory
        case .command(.emoji): return .searchEmoji
        case .command(.searchMenus): return .searchMenus
        case .command(.searchGIFs): return .searchGIFs
        case .command(.pasteInSequence): return .pasteInSequence
        case .command(.openSettings): return .openSettings
        case .system(let command): return .mac(.system(command))
        case .window(let layout): return .mac(.window(layout))
        case .ask: return .aiPrompt(PromptLibrary.askID)
        case .askByVoice: return .askByVoice
        case .dictate: return .dictate
        case .transform(let transform): return .transformSelection(transform)
        case .prompt(let id): return .aiPrompt(id)
        case .layout(let id): return .windowLayout(id)
        case .appLink(let id): return LinkedApp.command(id: id).map { .mac(.appLink($0, variant: nil)) }
        case .skillie(let path):
            guard let command = skillies.first(where: { $0.path == path }), command.arguments.allSatisfy(\.optional) else { return nil }
            return .mac(.script(command))
        case .command, .type, .snippet, .quicklink, .settings: return nil
        }
    }
}

extension ShortcutStore {
    /// The shortcut a Catalog row shows and records: the first for
    /// `action` that works, else the first without keys ("settings"). Nil
    /// when none exists yet: recording adds one.
    func entryID(for action: SkilliAction) -> String? {
        let id = action.id
        let entries = config.shortcuts.filter { $0.action.id == id }
        return (entries.first { $0.chords != nil && problems[$0.id] == nil } ?? entries.first)?.id
    }
}
