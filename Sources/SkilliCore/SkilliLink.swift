import Foundation

/// skil.li's own links, one for every Catalog entry, quicklink, window
/// layout and skillie, and "do it here" with a goal: opened from another
/// app, Shortcuts, a Stream Deck, a skillie or a web page, they run it.
///
///     skilli://run/cmd:emoji                  a Catalog entry, by its id
///     skilli://quicklink/g?q=skilli           a quicklink, by keyword (or id), and its query
///     skilli://layout/coding                  a window layout, by its id
///     skilli://skillie/tools/deploy.sh?arg=x  a skillie, by its place in the skillies folder
///     skilli://do?app=TextEdit&goal=…         "do it here" toward a goal, in that app (else the one in front)
///     skilli://record?title=Weekly%20sync     the Record card, that name in it (nothing recorded before ↩)
///     skilli://record/stop                    the recording on now: pause, resume or stop (asked first)
///     skilli://record/import?file=/Users/me/Call.m4a  Import Recording's panel, on that file (imported on ↩)
///     skilli://record/open?recording=2026-10-22%2014.00%20Weekly%20sync&at=724  a recording's window, playing from there
///
/// `skilli://commands/import` stays `CommandLink`'s.
public enum SkilliLink: Equatable, Sendable {
    /// A Catalog entry by its id (`CatalogEntry.id`): what its row does.
    case run(String)
    /// A quicklink by its keyword, else its id; no query: the selection's.
    case quicklink(String, query: String?)
    case layout(String)
    /// A skillie by its path inside the skillies folder, and its arguments
    /// in order.
    case skillie(String, arguments: [String])
    /// "Do it here" toward `goal` (as typed in Ask), in the app named (its
    /// name or bundle id), else the app in front
    /// (docs/do-it-here-from-anywhere.md). An empty goal is still this
    /// link: the card says it has nothing to do.
    case doHere(goal: String, app: String?)
    /// The Record card (docs/meeting-recorder.md), its name given or not:
    /// what the launcher's Record Meeting opens. It records nothing before
    /// ↩ in it.
    case record(title: String?)
    /// The recording on now, paused, resumed or stopped.
    case recording(RecordingControl)
    /// Import Recording's open panel (docs/meeting-recorder-views.md, phase
    /// 4), on the file named when one is: nothing is imported before the
    /// user's ↩ there.
    case importRecording(file: String?)
    /// A recording's window (phase 5: a reminder's link back to its
    /// meeting), by its folder's name, else its title; `at` seconds in, the
    /// line said then.
    case openRecording(String, at: Double?)

    public enum RecordingControl: String, CaseIterable, Sendable {
        case pause, resume, stop

        /// "Pause the recording", as the card asks it.
        public var title: String {
            switch self {
            case .pause: "Pause the recording"
            case .resume: "Resume the recording"
            case .stop: "Stop the recording"
            }
        }
    }

    /// The longest goal a `do` link may carry: its card shows the goal
    /// whole before it runs, and a page could hide words past what fits.
    public static let longestGoal = 300

    public static let scheme = CommandLink.scheme

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        var items: [URLQueryItem] = []
        switch self {
        case .run(let id):
            components.host = "run"
            components.percentEncodedPath = "/" + Self.encode(id, keeping: ":.")
        case .quicklink(let name, let query):
            components.host = "quicklink"
            components.percentEncodedPath = "/" + Self.encode(name, keeping: ".")
            if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        case .layout(let id):
            components.host = "layout"
            components.percentEncodedPath = "/" + Self.encode(id, keeping: ".")
        case .skillie(let path, let arguments):
            components.host = "skillie"
            components.percentEncodedPath = "/" + path.split(separator: "/").map { Self.encode(String($0), keeping: ".") }.joined(separator: "/")
            items += arguments.map { URLQueryItem(name: "arg", value: $0) }
        case .doHere(let goal, let app):
            components.host = "do"
            if let app, !app.isEmpty { items.append(URLQueryItem(name: "app", value: app)) }
            items.append(URLQueryItem(name: "goal", value: goal))
        case .record(let title):
            components.host = "record"
            if let title, !title.isEmpty { items.append(URLQueryItem(name: "title", value: title)) }
        case .recording(let control):
            components.host = "record"
            components.percentEncodedPath = "/" + control.rawValue
        case .importRecording(let file):
            components.host = "record"
            components.percentEncodedPath = "/import"
            if let file, !file.isEmpty { items.append(URLQueryItem(name: "file", value: file)) }
        case .openRecording(let recording, let at):
            components.host = "record"
            components.percentEncodedPath = "/open"
            items.append(URLQueryItem(name: "recording", value: recording))
            if let at { items.append(URLQueryItem(name: "at", value: String(Int(max(0, at).rounded(.down))))) }
        }
        if !items.isEmpty {
            // `+`, `&`, `=` and `#` encoded too: pages read `+` as a space.
            components.percentEncodedQuery = items.map { "\($0.name)=\(Self.encode($0.value ?? "", keeping: ""))" }.joined(separator: "&")
        }
        return components.url ?? URL(string: "\(Self.scheme)://run")!
    }

    /// Nil for anything that is not one of these links with a target.
    public static func parse(_ url: URL) -> SkilliLink? {
        guard url.scheme?.lowercased() == scheme, let host = url.host()?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // No path: what to do is in the query.
        if host == "do" {
            func value(_ name: String) -> String? {
                let text = items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.isEmpty ? nil : text
            }
            return .doHere(goal: value("goal") ?? "", app: value("app"))
        }
        let path = url.path(percentEncoded: false)
        let target = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if host == "record" {
            guard !target.isEmpty else {
                let title = items.first { $0.name == "title" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .record(title: title.isEmpty ? nil : title)
            }
            if target.lowercased() == "import" {
                let file = items.first { $0.name == "file" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .importRecording(file: file.isEmpty ? nil : file)
            }
            if target.lowercased() == "open" {
                let recording = items.first { $0.name == "recording" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !recording.isEmpty else { return nil }
                return .openRecording(recording, at: items.first { $0.name == "at" }?.value.flatMap(Double.init).map { max(0, $0) })
            }
            return RecordingControl(rawValue: target.lowercased()).map(Self.recording)
        }
        guard !target.isEmpty else { return nil }
        switch host {
        case "run":
            return .run(target)
        case "quicklink":
            let query = items.first { $0.name == "q" }?.value.flatMap { $0.isEmpty ? nil : $0 }
            return .quicklink(target, query: query)
        case "layout":
            return .layout(target)
        case "skillie":
            return .skillie(target, arguments: items.filter { $0.name == "arg" }.map { $0.value ?? "" })
        default:
            return nil
        }
    }

    /// Percent-encodes all but letters, digits, `-`, `_`, `~` and `keeping`.
    static func encode(_ text: String, keeping: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_~")
        allowed.insert(charactersIn: keeping)
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    // MARK: - Which link

    /// The link to `entry`: its quicklink by keyword (its id when it has no
    /// keyword or shares it), its layout, its skillie by its place in the
    /// folder (`skilliePath`), else the entry by its id.
    public static func link(for entry: CatalogEntry, quicklinks: [Quicklink] = [], skilliePath: (String) -> String = { $0 }) -> SkilliLink {
        switch entry.run {
        case .quicklink(let id):
            guard let link = quicklinks.first(where: { $0.id == id }) else { return .run(entry.id) }
            return .quicklink(link.linkName(among: quicklinks), query: nil)
        case .layout(let id):
            return .layout(id)
        case .skillie(let path):
            return .skillie(skilliePath(path), arguments: [])
        default:
            return .run(entry.id)
        }
    }

    /// The quicklink a link names: its id, else its keyword, else its name
    /// (case aside).
    public static func quicklink(named name: String, in links: [Quicklink]) -> Quicklink? {
        if let id = UUID(uuidString: name), let link = links.first(where: { $0.id == id }) { return link }
        let folded = name.lowercased()
        return links.first { !$0.keyword.isEmpty && $0.keyword.lowercased() == folded } ?? links.first { $0.name.lowercased() == folded }
    }

    /// A skillie's path inside the folder that holds it ("deploy.sh",
    /// "tools/deploy.sh"); its file's name when no folder holds it.
    public static func skilliePath(_ path: String, folders: [String]) -> String {
        for folder in folders {
            let root = folder.hasSuffix("/") ? folder : folder + "/"
            if path.hasPrefix(root) { return String(path.dropFirst(root.count)) }
        }
        return (path as NSString).lastPathComponent
    }

    /// The skillie at `relative` among `paths`: the same place in a folder,
    /// else the only one with that file's name.
    public static func skillie(at relative: String, among paths: [String], folders: [String]) -> String? {
        if let exact = paths.first(where: { skilliePath($0, folders: folders) == relative }) { return exact }
        let name = (relative as NSString).lastPathComponent
        let named = paths.filter { ($0 as NSString).lastPathComponent == name }
        return named.count == 1 ? named[0] : nil
    }

    // MARK: - Asked first

    /// Whether a link to it asks in the card before it runs. A link can
    /// come from any app or web page, so what runs at once only opens or
    /// reads (a mode, Settings, a page, the launcher with words, a window
    /// placed, a layout put back, sound and music, a reading). Asked first:
    /// what the user's own code, text or SI does on what is selected
    /// (skillies, snippets typed, commands, case changes, the microphone
    /// for Ask by Voice and Dictate), quitting skil.li, a paste of the
    /// user's copies (Paste in Sequence: a page could read them in its
    /// field), and the Mac commands that take the Mac away, can lose work or
    /// paste (`SystemCommand.asksFromALink`).
    /// Empty Trash, Restart, Quit All Apps… ask in the card anyway: not
    /// twice. Always in that card lets links run the entry at once
    /// (`LinkTrust`), except what `LinkTrust.neverTrusted` names.
    public static func asksFirst(_ run: CatalogEntry.Run) -> Bool {
        switch run {
        case .command(let id): id == .quit || id == .pasteInSequence
        case .system(let command): command.asksFromALink
        // A shortcut can do anything an app lets Shortcuts do: asked as a
        // skillie is.
        case .askByVoice, .dictate, .transform, .prompt, .snippet, .skillie, .shortcut: true
        // A linked app's command opens it, seen at once: a capture, the
        // editor, desktop icons, its history (docs/apps.md); one its file
        // says asks first (`AppLinkCommand.asksFirst`) asks.
        case .appLink(let id): LinkedApp.command(id: id)?.asksFirst ?? false
        case .window, .type, .ask, .settings, .layout, .quicklink: false
        }
    }
}

extension SystemCommand {
    /// Asked first when a link runs it (`SkilliLink.asksFirst`): it takes
    /// the Mac away from the user (locked, asleep, displays or keyboard
    /// off, every window moved aside or arranged), cuts them off (Wi-Fi off), can lose
    /// work (disks ejected during a copy, Finder restarted
    /// for hidden files), turns the microphone on or pastes the last
    /// screenshot (into a page that asked for it). Those that ask in the
    /// card anyway (`needsConfirmation`, Quit All and Quit Other Apps) are
    /// not asked twice; the rest is seen at once and undone as easily.
    public var asksFromALink: Bool {
        switch self {
        case .lockScreen, .sleep, .sleepDisplays, .ejectDisks, .toggleHiddenFiles, .cleanKeyboard, .toggleMicrophone, .pasteLatestScreenshot,
             .wifiOff, .showDesktop, .arrangeWindows: true
        case .emptyTrash, .restart, .shutDown, .logOut, .quitAllApps, .quitOtherApps: false
        case .toggleDarkMode, .keepAwake, .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute, .speedTest, .pickColor,
             .systemInfo, .hideOtherApps, .showAllApps, .wifiOn: false
        }
    }

    /// Asks in the card whatever starts it.
    public var asksAnyway: Bool {
        needsConfirmation || self == .quitAllApps || self == .quitOtherApps
    }
}

extension Quicklink {
    /// What its link names it by: its keyword when it has one no other
    /// quicklink shares, else its id.
    public func linkName(among links: [Quicklink]) -> String {
        let keyword = keyword.lowercased()
        guard !keyword.isEmpty, links.filter({ $0.keyword.lowercased() == keyword }).count <= 1 else { return id.uuidString }
        return self.keyword
    }
}
