import Foundation

/// A built-in command the launcher lists next to apps, e.g. "skil.li
/// Settings". Matched on its title and keywords.
public struct LauncherCommand: Sendable {
    public enum ID: String, CaseIterable, Sendable {
        case openSettings
        case quit
        /// Turns the launcher into Kill Process ("kill ").
        case killProcess
        /// Turns the launcher into the clipboard history (✦C).
        case clipboardHistory
        /// Each run pastes the next older copy (✦K V again and again).
        case pasteInSequence
        /// Turns the launcher into the user's snippets ("snip "), by name
        /// or, with ⇥, by what they need.
        case searchSnippets
        /// Turns the launcher into the emoji picker (":").
        case emoji
        /// Turns the launcher into the GIF picker ("gif "): Klipy's GIFs
        /// and the ones on this Mac.
        case searchGIFs
        /// Turns the launcher into every open window.
        case switchWindow
        /// Turns the launcher into the menu items of the app in front
        /// ("m "), found by name without a model.
        case searchMenus
        /// Every window open, in the layout editor, to save as a layout.
        case newWindowLayout
        /// The layout editor with no window: apps added by hand.
        case newEmptyWindowLayout
        /// Settings → Snippets, its editor open on a new snippet.
        case newSnippet
        /// Settings → Catalog → Quicklinks, its editor open on a new one.
        case newQuicklink
        /// Settings → Commands, its editor open on a new command.
        case newCommand
        /// Turns the launcher into every browser tab ("tab ").
        case searchTabs
        /// Turns the launcher into the editors' recent projects.
        case searchProjects
        /// Turns the launcher into the browsers' history ("history ").
        case searchHistory
        /// Turns the launcher into Homebrew ("brew ").
        case homebrew
        /// Turns the launcher into Spotlight's files ("f ").
        case searchFiles
        /// Turns the launcher into the user's contacts ("@").
        case searchContacts
        /// Turns the launcher into the coming events ("cal ").
        case agenda
        /// Free time in the coming working days, in the card to copy.
        case copyAvailability
        /// The Record card: a meeting recorded, the microphone and the
        /// Mac's sound, transcribed on this Mac (docs/meeting-recorder.md).
        case recordMeeting
        /// Turns the launcher into the reminders ("todo ").
        case reminders
        /// Turns the launcher into GitHub: pull requests and notifications
        /// ("pr "; "gh " stays GitHub's search quicklink).
        case github
        /// The launcher opens in the middle again, wherever it was dragged.
        case resetLauncherPosition
        /// A backup now, to the folder chosen in Settings → Backup.
        case backUpNow
        /// Turns the launcher into the Catalog, everything skil.li does
        /// ("?").
        case catalog
        /// The first launch's welcome again (docs/onboarding.md).
        case welcome
    }

    public let id: ID
    public let title: String
    public let symbol: String
    /// Other words people type, in English and French.
    public let keywords: [String]
    public let candidates: [FuzzyCandidate]

    public init(id: ID, title: String, symbol: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.keywords = keywords
        candidates = ([title] + keywords).map(FuzzyCandidate.init)
    }

    public static let all: [LauncherCommand] = [
        LauncherCommand(
            id: .openSettings,
            title: "skil.li Settings",
            symbol: "gearshape",
            keywords: ["settings", "preferences", "réglages", "paramètres", "config"]
        ),
        LauncherCommand(
            id: .quit,
            title: "Quit skil.li",
            symbol: "power",
            keywords: ["quit", "exit", "quitter"]
        ),
        LauncherCommand(
            id: .killProcess,
            title: "Kill a Process",
            symbol: "xmark.octagon.fill",
            keywords: ["kill", "force quit", "port", "process", "tuer", "processus", "activity monitor"]
        ),
        LauncherCommand(
            id: .clipboardHistory,
            title: "Clipboard History",
            symbol: "doc.on.clipboard",
            keywords: ["clipboard", "paste", "copied", "history", "presse-papier", "historique", "coller", "copié"]
        ),
        LauncherCommand(
            id: .pasteInSequence,
            title: "Paste in Sequence",
            symbol: "list.number",
            keywords: ["paste next", "paste sequentially", "paste one after another", "coller à la suite", "coller l'un après l'autre",
                       "coller le suivant", "clipboard"]
        ),
        LauncherCommand(
            id: .searchSnippets,
            title: "Search Snippets",
            symbol: "text.quote",
            keywords: ["snippet", "snippets", "text", "texte", "extrait", "modèle", "template", "signature", "auto snippet"]
        ),
        LauncherCommand(
            id: .emoji,
            title: "Search Emoji",
            symbol: "face.smiling",
            keywords: ["emoji", "smiley", "émoticône", "emoticon", "symbols", "symbole", "caractère", "character", "unicode"]
        ),
        LauncherCommand(
            id: .searchGIFs,
            title: "Search GIFs",
            symbol: "photo.on.rectangle.angled",
            keywords: ["gif", "gifs", "klipy", "giphy", "tenor", "reaction", "meme", "animated", "animation", "réaction", "animé"]
        ),
        LauncherCommand(
            id: .switchWindow,
            title: "Switch Window",
            symbol: "macwindow.on.rectangle",
            keywords: ["window", "windows", "fenêtre", "fenêtres", "switch", "basculer", "aller à"]
        ),
        LauncherCommand(
            id: .searchMenus,
            title: "Search Menu Items",
            symbol: "filemenu.and.selection",
            keywords: ["menu", "menus", "menu bar", "navigation", "barre des menus", "commande de menu"]
        ),
        LauncherCommand(
            id: .newWindowLayout,
            title: "New Window Layout",
            symbol: "rectangle.3.group",
            keywords: ["save layout", "save window layout", "window layout", "workspace", "preset", "enregistrer disposition",
                       "sauver disposition", "disposition des fenêtres", "espace de travail"]
        ),
        LauncherCommand(
            id: .newEmptyWindowLayout,
            title: "New Empty Window Layout",
            symbol: "rectangle.dashed",
            keywords: ["empty layout", "blank layout", "layout from scratch", "new layout", "disposition vide", "nouvelle disposition",
                       "partir de zéro", "à zéro"]
        ),
        LauncherCommand(
            id: .newSnippet,
            title: "New Snippet",
            symbol: "text.badge.plus",
            keywords: ["add snippet", "create snippet", "new text", "nouveau snippet", "ajouter un snippet", "créer un snippet",
                       "nouvel extrait", "nouveau texte"]
        ),
        LauncherCommand(
            id: .newQuicklink,
            title: "New Quicklink",
            symbol: "link.badge.plus",
            keywords: ["add quicklink", "create quicklink", "new web search", "nouveau quicklink", "ajouter un quicklink",
                       "créer un quicklink", "nouveau lien rapide"]
        ),
        LauncherCommand(
            id: .newCommand,
            title: "New Command",
            symbol: "sparkles",
            keywords: ["add command", "create command", "new prompt", "nouvelle commande", "ajouter une commande", "créer une commande",
                       "nouveau prompt"]
        ),
        LauncherCommand(
            id: .searchTabs,
            title: "Search Tabs",
            symbol: "rectangle.stack",
            keywords: ["tab", "tabs", "onglet", "onglets", "browser", "navigateur", "chrome", "safari", "arc"]
        ),
        LauncherCommand(
            id: .searchProjects,
            title: "Search Projects",
            symbol: "chevron.left.forwardslash.chevron.right",
            keywords: ["project", "projects", "projet", "projets", "repo", "code", "cursor", "vscode", "zed", "editor", "éditeur"]
        ),
        LauncherCommand(
            id: .searchHistory,
            title: "Search Browser History",
            symbol: "clock.arrow.circlepath",
            keywords: ["history", "historique", "visited", "pages", "chrome", "arc", "firefox", "zen", "déjà vu", "site"]
        ),
        LauncherCommand(
            id: .homebrew,
            title: "Homebrew",
            symbol: "shippingbox",
            keywords: ["brew", "install", "installer", "formula", "cask", "package", "paquet", "upgrade", "mettre à jour", "cli"]
        ),
        LauncherCommand(
            id: .searchFiles,
            title: "Search Files",
            symbol: "doc.text.magnifyingglass",
            keywords: ["file", "files", "fichier", "fichiers", "document", "spotlight", "find", "chercher"]
        ),
        LauncherCommand(
            id: .searchContacts,
            title: "Search Contacts",
            symbol: "person.crop.circle",
            keywords: ["contact", "contacts", "people", "person", "personne", "carnet", "annuaire", "address book", "email", "téléphone"]
        ),
        LauncherCommand(
            id: .agenda,
            title: "Calendar",
            symbol: "calendar",
            keywords: ["agenda", "calendrier", "schedule", "my schedule", "planning", "events", "événements", "meetings", "réunions",
                       "rendez-vous", "rdv", "upcoming"]
        ),
        LauncherCommand(
            id: .copyAvailability,
            title: "Copy Availability",
            symbol: "calendar.badge.clock",
            keywords: ["availability", "free time", "disponibilités", "dispos", "créneaux", "libre", "free slots"]
        ),
        LauncherCommand(
            id: .recordMeeting,
            title: "Record Meeting",
            symbol: "record.circle",
            keywords: ["rec", "record", "recorder", "record call", "meeting recorder", "transcribe", "transcript", "enregistrer",
                       "enregistrement", "enregistrer la réunion", "enregistreur", "transcription"]
        ),
        LauncherCommand(
            id: .reminders,
            title: "Reminders",
            symbol: "checklist",
            keywords: ["my reminders", "rappels", "mes rappels", "todo", "to do", "tâches", "tasks", "à faire", "checklist"]
        ),
        LauncherCommand(
            id: .github,
            title: "GitHub Inbox",
            symbol: "arrow.triangle.pull",
            keywords: ["github", "pull requests", "prs", "pr", "notifications", "inbox", "reviews", "merge", "github notifications"]
        ),
        LauncherCommand(
            id: .resetLauncherPosition,
            title: "Reset Launcher Position",
            symbol: "rectangle.center.inset.filled",
            keywords: ["center launcher", "move launcher", "launcher position", "recentrer", "centrer", "position du lanceur",
                       "remettre au milieu", "déplacer"]
        ),
        LauncherCommand(
            id: .backUpNow,
            title: "Back Up skil.li Now",
            symbol: "clock.arrow.circlepath",
            keywords: ["backup", "back up", "export settings", "sauvegarde", "sauvegarder", "exporter les réglages", "copie de sécurité"]
        ),
        LauncherCommand(
            id: .catalog,
            title: "What skil.li Can Do",
            symbol: "questionmark.circle",
            keywords: ["help", "catalog", "features", "what can skilli do", "everything", "aide", "fonctionnalités", "que sait faire",
                       "tout ce que", "commandes"]
        ),
        LauncherCommand(
            id: .welcome,
            title: "Welcome to skil.li",
            symbol: "hand.wave",
            keywords: ["welcome", "onboarding", "tour", "get started", "set up", "setup", "tutorial", "bienvenue", "découvrir",
                       "prise en main", "premiers pas"]
        )
    ]

    /// Its title is its name, the rest keywords (`LauncherRank`).
    public func score(_ query: FuzzyMatcher.Query) -> Int? {
        LauncherRank.score(query, names: candidates.prefix(1), keywords: candidates.dropFirst())
    }
}

extension LauncherCommand.ID {
    /// What a shortcut on it runs, as `shortcuts.json` names it: the id it
    /// had before every command took a shortcut ("clipboard.history" for
    /// ✦C), else "cmd." and its own ("cmd.searchSnippets"). Never changed:
    /// the user's file names them.
    public var shortcutID: String {
        switch self {
        case .openSettings: "settings.open"
        case .clipboardHistory: "clipboard.history"
        case .pasteInSequence: "clipboard.sequence"
        case .emoji: SystemShortcuts.emojiSearch
        case .searchGIFs: "gifs.search"
        case .searchMenus: "menus.search"
        default: "cmd." + rawValue
        }
    }

    /// The command a shortcut's id names (`shortcutID`).
    public init?(shortcutID: String) {
        guard let command = Self.allCases.first(where: { $0.shortcutID == shortcutID }) else { return nil }
        self = command
    }
}
