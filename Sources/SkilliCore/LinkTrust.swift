import Foundation

/// An entry the user lets `skilli://` links run without asking: Always
/// (⌘↩) in a link's card (D6, 2026-10-17: "Always from links, per
/// entry, after the first ↩"). Kept with the tools' rights (`tools.json`),
/// listed in Settings → Catalog → Trusted Links, each one removable.
public struct TrustedLink: Codable, Hashable, Sendable, Identifiable {
    /// The Catalog entry's id, as links name it ("system:lockScreen",
    /// "snippet:addr", "script:/…/deploy.sh" for a skillie).
    public var entry: String
    /// A skillie's arguments as the link gave them: the same skillie with
    /// other arguments asks again (a page could pick them). Empty for
    /// every other entry.
    public var arguments: [String]
    /// Its name when it was trusted: Settings shows it if the entry is gone.
    public var title: String

    public init(entry: String, arguments: [String] = [], title: String) {
        self.entry = entry
        self.arguments = arguments
        self.title = title
    }

    public var id: String { ([entry] + arguments).joined(separator: "\u{1F}") }

    /// As Settings lists it: "deploy · “prod”".
    public var shown: String {
        arguments.isEmpty ? title : title + " · " + arguments.map { "“\($0)”" }.joined(separator: ", ")
    }
}

/// Whether a link runs what it names at once, asks in the card with
/// Always, or asks without it; and the entries the user trusted.
public struct LinkTrust: Equatable, Sendable {
    public enum Ask: Equatable, Sendable {
        /// At once: it only opens or reads (`SkilliLink.asksFirst`), it
        /// asks by itself (a skillie that says so), or the user trusted it.
        case runs
        /// In the card first: Allow ↩, Deny esc, and Always ⌘↩ only when
        /// `offersAlways`.
        case asks(offersAlways: Bool)
    }

    /// In the order they were trusted.
    public private(set) var links: [TrustedLink]

    public init(_ links: [TrustedLink] = []) {
        var seen: Set<String> = []
        self.links = links.filter { seen.insert($0.id).inserted }
    }

    /// Never trusted, whatever the user chose: what asks in its own card
    /// anyway (Empty Trash, Restart, Shut Down, Log Out, Quit All, Quit
    /// Other Apps: `SystemCommand.asksAnyway`), a linked app's command that
    /// asks first, skil.li's own settings (a
    /// pane, Reset Launcher Position: a change of settings asks every
    /// time, as agents' do), and what hands the user's copies to the app
    /// in front (Paste in Sequence, Paste Latest Screenshot: a page that
    /// opened the link could read them in its field).
    public static func neverTrusted(_ run: CatalogEntry.Run) -> Bool {
        switch run {
        case .system(let command): command.asksAnyway || command == .pasteLatestScreenshot
        case .command(let id): id == .pasteInSequence || id == .resetLauncherPosition
        case .settings: true
        // A linked app's command that asks first asks every time (CleanShot's
        // upload, docs/apps.md).
        case .appLink(let id): LinkedApp.command(id: id)?.asksFirst ?? false
        case .window, .type, .ask, .askByVoice, .dictate, .transform, .prompt, .snippet, .skillie, .quicklink, .layout, .shortcut: false
        }
    }

    /// Always is offered in its card: it asks first from a link, and it is
    /// not among `neverTrusted`.
    public static func canTrust(_ run: CatalogEntry.Run) -> Bool {
        SkilliLink.asksFirst(run) && !neverTrusted(run)
    }

    /// Trusted already, with these arguments (a skillie's; none for the rest).
    public func trusts(_ entry: String, arguments: [String] = []) -> Bool {
        links.contains { $0.entry == entry && $0.arguments == arguments }
    }

    /// What a link to `entry` does before it runs. `asksItself`: a skillie
    /// that asks in its own card, which a link never asks again nor skips.
    /// A trust read from the file for what can no longer be trusted (an
    /// edited file, a command that came to ask anyway) does nothing.
    public func ask(_ run: CatalogEntry.Run, entry: String, arguments: [String] = [], asksItself: Bool = false) -> Ask {
        guard SkilliLink.asksFirst(run), !asksItself else { return .runs }
        let trustable = Self.canTrust(run)
        if trustable, trusts(entry, arguments: Self.kept(arguments, for: run)) { return .runs }
        return .asks(offersAlways: trustable)
    }

    /// Always pressed in the card: links run it at once from now on. False
    /// (nothing kept) for what is never trusted.
    @discardableResult
    public mutating func trust(_ run: CatalogEntry.Run, entry: String, title: String, arguments: [String] = []) -> Bool {
        guard Self.canTrust(run) else { return false }
        let kept = Self.kept(arguments, for: run)
        if !trusts(entry, arguments: kept) { links.append(TrustedLink(entry: entry, arguments: kept, title: title)) }
        return true
    }

    /// Asks again from the next link on.
    public mutating func remove(_ link: TrustedLink) {
        links.removeAll { $0.id == link.id }
    }

    /// As Settings lists them: by name, case and accents aside.
    public var byTitle: [TrustedLink] {
        links.sorted { $0.shown.compare($1.shown, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending }
    }

    // MARK: - Do it here

    /// The entry a "do it here" link is trusted under (`SkilliLink.doHere`):
    /// its goal and its app are its arguments, as a skillie's are.
    public static let doEntry = "do"

    /// A "do it here" link acts out of the user's hands, from words a page
    /// could write: always asked first, Always offered. Trusted, that very
    /// goal in that very app runs at once; another goal, or the same in
    /// another app, asks again.
    public func askDo(goal: String, app: String?) -> Ask {
        trusts(Self.doEntry, arguments: Self.doArguments(goal: goal, app: app)) ? .runs : .asks(offersAlways: true)
    }

    /// Always pressed in a "do it here" link's card.
    public mutating func trustDo(goal: String, app: String?, title: String) {
        let arguments = Self.doArguments(goal: goal, app: app)
        if !trusts(Self.doEntry, arguments: arguments) { links.append(TrustedLink(entry: Self.doEntry, arguments: arguments, title: title)) }
    }

    /// The goal, then the app when the link names one.
    static func doArguments(goal: String, app: String?) -> [String] {
        [goal] + (app.map { [$0] } ?? [])
    }

    /// Only a skillie's arguments count: every other entry takes none.
    private static func kept(_ arguments: [String], for run: CatalogEntry.Run) -> [String] {
        if case .skillie = run { return arguments }
        return []
    }
}
