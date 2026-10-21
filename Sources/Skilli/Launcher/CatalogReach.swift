import SkilliCore

// How a Catalog entry is reached besides its prefix: the shortcut action
// both the "?" and Settings → Catalog show and edit, from one place.

extension CatalogEntry {
    /// The action a global shortcut runs for it, when one can: every
    /// launcher command (into its mode, or what its row does), Mac command
    /// and window place, and what the user made — a snippet typed, a
    /// quicklink's keyword in the launcher, a skillie only when it needs no
    /// argument (as Settings → Keys → Add Shortcut lists them). None for
    /// what types the start of words (Timer), where the first of something
    /// is made, nor Do It Here and Ask on a Schedule: ways of saying what
    /// Ask does, their shortcut would be Ask's own.
    func shortcutAction(skillies: [ScriptCommand]) -> SkilliAction? {
        switch run {
        case .command(let command): return .command(command)
        case .system(let command): return .mac(.system(command))
        case .window(let layout): return .mac(.window(layout))
        case .ask: return id.hasPrefix("catalog.") ? nil : .aiPrompt(PromptLibrary.askID)
        case .askByVoice: return .askByVoice
        case .dictate: return .dictate
        case .transform(let transform): return .transformSelection(transform)
        case .prompt(let prompt): return .aiPrompt(prompt)
        case .snippet(let snippet): return .snippet(snippet)
        case .quicklink(let link): return .quicklink(link)
        case .layout(let layout): return .windowLayout(layout)
        case .appLink(let link): return LinkedApp.command(id: link).map { .mac(.appLink($0, variant: nil)) }
        case .shortcut(let shortcut): return .mac(.shortcut(AppleShortcuts.current(AppleShortcut(id: shortcut, name: "")), withSelection: false))
        case .skillie(let path):
            guard let command = skillies.first(where: { $0.path == path }), command.arguments.allSatisfy(\.optional) else { return nil }
            return .mac(.script(command))
        case .type, .settings: return nil
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
