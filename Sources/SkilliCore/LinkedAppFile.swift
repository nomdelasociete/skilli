import Foundation

/// A linked app written in a file (docs/apps.md, "App files"): the user's,
/// in `~/Library/Application Support/skil.li/Apps/*.json`, or one skil.li
/// ships. Read strictly: a key it does not know, a value of the wrong kind
/// or past its bounds, or an app skil.li drives already, and the whole
/// file is left out, said in Settings → Apps.
///
///     {
///       "id": "warp",
///       "name": "Warp",
///       "bundleID": "dev.warp.Warp-Stable",
///       "scheme": "warp",
///       "documentation": "https://docs.warp.dev/…",
///       "commands": [
///         {
///           "id": "new-window",
///           "path": "action/new_window",
///           "title": "New Warp Window",
///           "description": "Opens a new Warp window",
///           "words": ["terminal", "window", "fenêtre"],
///           "symbol": "macwindow.badge.plus",
///           "query": [{ "name": "path", "value": "~" }],
///           "variants": [{ "id": "…", "title": "…", "label": "…", "query": [{ "name": "…", "value": "…" }] }],
///           "group": "Windows"
///         }
///       ]
///     }
///
/// Optional: `shortName`, `minimumVersion`, `documentation`, `note` (what
/// the app needs, on its page); a command's `words`, `symbol`, `query`,
/// `variants`, `since`, `asksFirst`, `group`; a variant's `symbol`,
/// `since`, `asksFirst`.
public enum LinkedAppFile {
    /// What is wrong with a file, in the user's words.
    public struct Problem: Error, Equatable, Sendable {
        /// The file's name ("Zed.json").
        public let file: String
        public let message: String

        public init(file: String, message: String) {
            self.file = file
            self.message = message
        }
    }

    /// One file to read: its name, its bytes, and whether skil.li ships it.
    public struct Source: Sendable {
        public let name: String
        public let data: Data
        public let shipped: Bool

        public init(name: String, data: Data, shipped: Bool) {
            self.name = name
            self.data = data
            self.shipped = shipped
        }
    }

    /// The apps the files define, and the files left out.
    public struct Loaded: Sendable {
        public var apps: [LinkedApp] = []
        public var problems: [Problem] = []
    }

    /// The largest file read.
    public static let largest = 64 * 1024
    /// Schemes no app file may claim: the web's, the system's, skil.li's.
    public static let reservedSchemes: Set<String> = ["http", "https", "file", "ftp", "mailto", "tel", "sms", "data", "javascript", "about",
                                                      "blob", CommandLink.scheme]
    /// Ids that name something else in skil.li's actions ("text.uppercase").
    public static let reservedIDs: Set<String> = ["text", "skilli", "shortcuts", "system"]
    /// The group of a command that names none.
    public static let defaultGroup = "Commands"

    /// Every file, skil.li's own first, then the user's by name; each one
    /// that clashes with an app known already (by id, bundle id or scheme:
    /// the built-in ones first, then the files read before it) left out.
    public static func load(_ sources: [Source], builtIn: [LinkedApp] = LinkedApp.builtIn,
                            symbolExists: (String) -> Bool = { _ in true }) -> Loaded {
        var loaded = Loaded()
        let ordered = sources.filter(\.shipped) + sources.filter { !$0.shipped }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for source in ordered {
            do {
                let app = try read(source.data, file: source.shipped ? nil : source.name, symbolExists: symbolExists)
                if let clash = clash(app, builtIn: builtIn, read: loaded.apps) {
                    loaded.problems.append(Problem(file: source.name, message: clash))
                } else {
                    loaded.apps.append(app)
                }
            } catch {
                loaded.problems.append(Problem(file: source.name, message: error.message))
            }
        }
        return loaded
    }

    /// Why `app` cannot join the apps known already; nil when it can.
    public static func clash(_ app: LinkedApp, builtIn: [LinkedApp] = LinkedApp.builtIn, read: [LinkedApp]) -> String? {
        for other in builtIn + read {
            let whose = other.file.map { "your “\($0)”" } ?? "skil.li's own"
            if other.id == app.id { return "Its id “\(app.id)” is \(other.name)'s already (\(whose))." }
            if other.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame { return "\(other.name) is driven already (\(whose))." }
            if other.scheme == app.scheme { return "Its scheme “\(app.scheme)” is \(other.name)'s already (\(whose))." }
        }
        return nil
    }

    /// The text written for `object` (an agent's app, an import): keys
    /// sorted, slashes kept, as people read it.
    public static func text(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: - Reading

    struct Failure: Error {
        let message: String
    }

    /// The app one file defines; throws what is wrong, the first thing
    /// found. `file`: the user's file name, nil for skil.li's own.
    public static func read(_ data: Data, file: String?, symbolExists: (String) -> Bool = { _ in true }) throws(Problem) -> LinkedApp {
        do {
            guard data.count <= largest else { throw Failure(message: "Over \(largest / 1024) KB: not an app file.") }
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw Failure(message: "Not JSON: \(Self.jsonError(error))")
            }
            guard let top = object as? [String: Any] else { throw Failure(message: "Not an app: the file must hold one JSON object.") }
            return try app(Fields(top, at: nil), file: file, symbolExists: symbolExists)
        } catch let failure as Failure {
            throw Problem(file: file ?? "", message: failure.message)
        } catch {
            throw Problem(file: file ?? "", message: error.localizedDescription)
        }
    }

    private static func app(_ fields: Fields, file: String?, symbolExists: (String) -> Bool) throws -> LinkedApp {
        try fields.only(["id", "name", "shortName", "bundleID", "scheme", "minimumVersion", "documentation", "note", "commands"])
        let id = try fields.identifier("id", length: 32)
        guard !reservedIDs.contains(id) else { throw Failure(message: "“id” “\(id)” names something else in skil.li: pick another.") }
        let name = try fields.text("name", length: 40)
        let shortName = try fields.optionalText("shortName", length: 24) ?? name
        let bundleID = try fields.text("bundleID", length: 155)
        guard bundleID.wholeMatch(of: /[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+/) != nil else {
            throw Failure(message: "“bundleID” “\(bundleID)” is not a bundle id (com.example.App).")
        }
        guard bundleID.caseInsensitiveCompare("com.nomdelasociete.Skilli") != .orderedSame else {
            throw Failure(message: "“bundleID” is skil.li's own.")
        }
        let scheme = try fields.text("scheme", length: 40).lowercased()
        guard scheme.wholeMatch(of: /[a-z][a-z0-9+.\-]*/) != nil else { throw Failure(message: "“scheme” “\(scheme)” is not a link scheme.") }
        guard !reservedSchemes.contains(scheme) else {
            throw Failure(message: "“scheme” “\(scheme)” is not one app's own: an app file names the scheme its app documents.")
        }
        let minimum = try fields.version("minimumVersion")
        let documentation = try fields.optionalText("documentation", length: 300)
        if let documentation {
            guard let url = URL(string: documentation), url.scheme == "https", url.host() != nil else {
                throw Failure(message: "“documentation” must be the https address where the app documents its links.")
            }
        }
        let note = try fields.optionalText("note", length: 200)
        let list = try fields.objects("commands", most: 60)
        guard !list.isEmpty else { throw Failure(message: "“commands” is empty: an app file gives at least one command.") }
        var commands: [AppLinkCommand] = []
        var groups: [(title: String, commands: [String])] = []
        for command in list {
            let read = try self.command(command, app: id, name: name, minimum: minimum, symbolExists: symbolExists)
            guard !commands.contains(where: { $0.id == read.command.id }) else {
                throw Failure(message: "\(command.place): another command has the id “\(read.command.id.dropFirst(id.count + 1))”.")
            }
            commands.append(read.command)
            let name = String(read.command.id.dropFirst(id.count + 1))
            if let index = groups.firstIndex(where: { $0.title == read.group }) {
                groups[index].commands.append(name)
            } else {
                groups.append((read.group, [name]))
            }
        }
        return LinkedApp(id: id, name: name, shortName: shortName, bundleID: bundleID, scheme: scheme, commands: commands,
                         groups: groups.map { LinkedApp.CommandGroup(title: $0.title, commands: $0.commands) }, allowance: note,
                         minimumVersion: minimum, documentation: documentation, file: file)
    }

    private static func command(_ fields: Fields, app: String, name: String, minimum: String?,
                                symbolExists: (String) -> Bool) throws -> (command: AppLinkCommand, group: String) {
        try fields.only(["id", "path", "title", "description", "words", "symbol", "query", "variants", "since", "asksFirst", "group"])
        let id = try fields.identifier("id", length: 48)
        let path = try fields.text("path", length: 200)
        guard path.wholeMatch(of: /[A-Za-z0-9\-._~!$&'()*+,;=:@\/]+/) != nil, !path.hasPrefix("//"), !path.contains("..") else {
            throw Failure(message: "\(fields.place): “path” “\(path)” is not a link's path (its parameters go in “query”).")
        }
        let title = try fields.text("title", length: 50)
        var oneLine = try fields.text("description", length: 70)
        if oneLine.hasSuffix(".") { oneLine.removeLast() }
        let words = try fields.words("words")
        let symbol = try fields.symbol("symbol", exists: symbolExists) ?? "link"
        let query = try fields.query("query", optional: true)
        let since = latest(minimum, try fields.version("since"))
        let asksFirst = try fields.flag("asksFirst")
        let group = try fields.optionalText("group", length: 30) ?? defaultGroup
        var variants: [AppLinkCommand.Variant] = []
        for variant in try fields.objects("variants", most: 12, optional: true) {
            try variant.only(["id", "title", "label", "symbol", "query", "since", "asksFirst"])
            let variantID = try variant.identifier("id", length: 32)
            guard !variants.contains(where: { $0.id == variantID }) else {
                throw Failure(message: "\(variant.place): another variant has the id “\(variantID)”.")
            }
            let variantQuery = try variant.query("query", optional: false)
            guard !variantQuery.isEmpty else { throw Failure(message: "\(variant.place): “query” is empty: a variant says more than its command.") }
            variants.append(AppLinkCommand.Variant(
                id: variantID, title: try variant.text("title", length: 50), label: try variant.text("label", length: 30),
                symbol: try variant.symbol("symbol", exists: symbolExists) ?? symbol, query: variantQuery,
                since: latest(since, try variant.version("since")), asksFirst: try variant.flag("asksFirst")
            ))
        }
        // Found by the app's name too, as CleanShot's are by "cleanshot".
        var keywords = [name.lowercased()]
        for word in words where !keywords.contains(word.lowercased()) { keywords.append(word.lowercased()) }
        let command = AppLinkCommand(id: "\(app).\(id)", path: path, title: title, oneLine: oneLine, symbol: symbol, keywords: keywords,
                                     variants: variants, since: since, query: query, asksFirst: asksFirst)
        return (command, group)
    }

    /// The later of two versions; nil only when both are.
    private static func latest(_ one: String?, _ other: String?) -> String? {
        guard let one else { return other }
        guard let other else { return one }
        return AppVersion.isAtLeast(one, other) ? one : other
    }

    private static func jsonError(_ error: Error) -> String {
        let said = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
        return said.hasSuffix(".") ? String(said.dropLast()) : said
    }

    /// One JSON object's fields, read by kind, and where it is in the file
    /// ("Command 2 (“join”)") for what is said.
    struct Fields {
        let values: [String: Any]
        let place: String

        init(_ values: [String: Any], at place: String?) {
            self.values = values
            self.place = place ?? "The app"
        }

        func only(_ keys: Set<String>) throws {
            if let unknown = values.keys.sorted().first(where: { !keys.contains($0) }) {
                throw Failure(message: "\(place): “\(unknown)” is not a key skil.li reads (\(keys.sorted().joined(separator: ", "))).")
            }
        }

        func optionalText(_ key: String, length: Int) throws -> String? {
            guard values[key] != nil else { return nil }
            return try text(key, length: length)
        }

        func text(_ key: String, length: Int) throws -> String {
            guard let value = values[key] else { throw Failure(message: "\(place): “\(key)” is missing.") }
            guard let text = value as? String else { throw Failure(message: "\(place): “\(key)” must be text.") }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Failure(message: "\(place): “\(key)” is empty.") }
            guard trimmed.count <= length else { throw Failure(message: "\(place): “\(key)” is longer than \(length) characters.") }
            guard !trimmed.contains(where: { $0.isNewline }) else { throw Failure(message: "\(place): “\(key)” is on more than one line.") }
            return trimmed
        }

        func identifier(_ key: String, length: Int) throws -> String {
            let id = try text(key, length: length)
            guard id.wholeMatch(of: /[a-z0-9][a-z0-9\-]*/) != nil else {
                throw Failure(message: "\(place): “\(key)” “\(id)” takes lowercase letters, digits and hyphens.")
            }
            return id
        }

        func version(_ key: String) throws -> String? {
            guard let version = try optionalText(key, length: 20) else { return nil }
            guard version.wholeMatch(of: /[0-9]+(\.[0-9]+){0,3}/) != nil else {
                throw Failure(message: "\(place): “\(key)” “\(version)” is not a version (4.7, 5.0.1).")
            }
            return version
        }

        func flag(_ key: String) throws -> Bool {
            guard let value = values[key] else { return false }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw Failure(message: "\(place): “\(key)” must be true or false.")
            }
            return number.boolValue
        }

        func symbol(_ key: String, exists: (String) -> Bool) throws -> String? {
            guard let symbol = try optionalText(key, length: 60) else { return nil }
            guard exists(symbol) else { throw Failure(message: "\(place): “\(key)” “\(symbol)” is not an SF Symbol.") }
            return symbol
        }

        func words(_ key: String) throws -> [String] {
            guard let value = values[key] else { return [] }
            guard let words = value as? [Any], words.allSatisfy({ $0 is String }) else {
                throw Failure(message: "\(place): “\(key)” must be a list of words.")
            }
            let trimmed = words.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard trimmed.count <= 40 else { throw Failure(message: "\(place): more than 40 “\(key)”.") }
            guard trimmed.allSatisfy({ !$0.isEmpty && $0.count <= 40 }) else {
                throw Failure(message: "\(place): each of “\(key)” has 1 to 40 characters.")
            }
            return trimmed
        }

        /// `[{"name": "…", "value": "…"}]`, in the order the link gives them.
        func query(_ key: String, optional: Bool) throws -> [AppLinkCommand.Parameter] {
            guard let value = values[key] else {
                if optional { return [] }
                throw Failure(message: "\(place): “\(key)” is missing.")
            }
            guard let list = value as? [Any] else { throw Failure(message: "\(place): “\(key)” must be a list of {\"name\", \"value\"}.") }
            guard list.count <= 12 else { throw Failure(message: "\(place): more than 12 parameters in “\(key)”.") }
            return try list.enumerated().map { index, item in
                guard let item = item as? [String: Any] else { throw Failure(message: "\(place): “\(key)” must be a list of {\"name\", \"value\"}.") }
                let fields = Fields(item, at: "\(place), parameter \(index + 1)")
                try fields.only(["name", "value"])
                let name = try fields.text("name", length: 40)
                guard name.wholeMatch(of: /[A-Za-z0-9_.\-\[\]]+/) != nil else {
                    throw Failure(message: "\(fields.place): “name” “\(name)” is not a parameter's name.")
                }
                guard let value = item["value"] as? String else {
                    throw Failure(message: "\(fields.place): “value” must be text" + (item["value"] == nil ? " (it is missing)." : "."))
                }
                guard value.count <= 500, !value.contains(where: { $0.isNewline }) else {
                    throw Failure(message: "\(fields.place): “value” is one line of 500 characters at most.")
                }
                return AppLinkCommand.Parameter(name, value)
            }
        }

        func objects(_ key: String, most: Int, optional: Bool = false) throws -> [Fields] {
            guard let value = values[key] else {
                if optional { return [] }
                throw Failure(message: "\(place): “\(key)” is missing.")
            }
            guard let list = value as? [Any], list.allSatisfy({ $0 is [String: Any] }) else {
                throw Failure(message: "\(place): “\(key)” must be a list of objects.")
            }
            guard list.count <= most else { throw Failure(message: "\(place): more than \(most) \(key).") }
            let noun = key == "commands" ? "Command" : "\(place), variant"
            return list.enumerated().map { index, item in
                let object = item as? [String: Any] ?? [:]
                let id = (object["id"] as? String).map { " (“\($0)”)" } ?? ""
                return Fields(object, at: "\(noun) \(index + 1)\(id)")
            }
        }
    }
}

private extension Error {
    var message: String {
        (self as? LinkedAppFile.Problem)?.message ?? (self as? LinkedAppFile.Failure)?.message ?? localizedDescription
    }
}
