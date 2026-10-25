import Foundation

/// A skillie as a file of its own (docs/skillie-files.md): `.skilli`, the
/// script itself under skil.li's extension, opened in skil.li to be added.
/// `check` reads it as the skillies folder will, before the sheet shows
/// it whole; nothing is added from a file alone.
public enum SkillieFile {
    public static let fileExtension = "skilli"
    /// The type skil.li exports for it (`Config/Info.plist`).
    public static let typeIdentifier = "com.nomdelasociete.skilli.skillie"
    /// The largest a skillie file may be.
    public static let largest = 256 * 1024

    public struct Problem: LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }

        public init(message: String) {
            self.message = message
        }
    }

    /// A skillie ready to add: what its header says, its text, and the
    /// name it is added under in the skillies folder.
    public struct Checked: Sendable {
        public let command: ScriptCommand
        public let text: String
        public let fileName: String
    }

    /// `name`: the file's name, or the last part of the address it came
    /// from ("week-number.skilli", "week-number.sh").
    public static func check(_ data: Data, name: String) throws -> Checked {
        guard data.count <= largest else { throw Problem(message: "It is over \(largest / 1024) KB: not a skillie.") }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw Problem(message: "It is not text: not a skillie.")
        }
        guard let program = program(of: text) else {
            throw Problem(message: "Its first line does not say what runs it (#!/bin/bash, #!/usr/bin/env python3…): not a skillie.")
        }
        // The header as the folder reads it: its first 8 KB.
        guard let command = ScriptCommand.parse(String(decoding: data.prefix(8_192), as: UTF8.self), path: "") else {
            throw Problem(message: "Its first lines do not say “@skilli.title” and “@skilli.mode”: not a skillie.")
        }
        return Checked(command: command, text: text, fileName: fileName(name, title: command.title, program: program))
    }

    /// The installed skillie a new one replaces: the one with its title,
    /// as the launcher lists them (case aside).
    public static func replaced(by command: ScriptCommand, among installed: [ScriptCommand]) -> ScriptCommand? {
        installed.first { $0.title.localizedCaseInsensitiveCompare(command.title) == .orderedSame }
    }

    /// What its shebang runs: `#!/usr/bin/env python3` → "python3",
    /// `#!/bin/bash` → "bash". Nil without one naming an absolute path,
    /// which skil.li needs to run a file that is not executable.
    static func program(of text: String) -> String? {
        guard text.hasPrefix("#!"), let line = text.dropFirst(2).split(whereSeparator: \.isNewline).first else { return nil }
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first, first.hasPrefix("/") else { return nil }
        let name = (first as NSString).lastPathComponent
        guard name == "env" else { return name }
        // `env -S node --flag`: the first word that is not an option.
        return parts.dropFirst().first { !$0.hasPrefix("-") && !$0.contains("=") }.map { ($0 as NSString).lastPathComponent }
    }

    /// "Week Number.skilli" → "week-number.sh": the file's name without
    /// `.skilli` (or the title's when it has none), the extension its
    /// program's scripts have.
    static func fileName(_ name: String, title: String, program: String) -> String {
        var base = (name as NSString).lastPathComponent
        // ".skilli" alone: an extension, no name (NSString sees a hidden file).
        if base.hasPrefix("."), scriptExtensions.contains(base.dropFirst().lowercased()) { base = "" }
        for _ in 0..<2 where scriptExtensions.contains((base as NSString).pathExtension.lowercased()) {
            base = (base as NSString).deletingPathExtension
        }
        let slug = ScriptCommand.slug(base).isEmpty ? ScriptCommand.slug(title) : ScriptCommand.slug(base)
        let ext = fileExtension(for: program)
        return (slug.isEmpty ? "skillie" : slug) + (ext.isEmpty ? "" : ".\(ext)")
    }

    /// Extensions taken off a name before its own is put back.
    private static let scriptExtensions: Set<String> = [fileExtension, "sh", "bash", "zsh", "py", "js", "mjs", "rb", "swift", "txt"]

    /// bash, sh, zsh → "sh"; python3 → "py"; node → "js"; swift; ruby →
    /// "rb"; another program: none.
    static func fileExtension(for program: String) -> String {
        switch program {
        case "bash", "sh", "zsh", "dash": "sh"
        case "node": "js"
        case "swift": "swift"
        case "ruby": "rb"
        default: program.hasPrefix("python") ? "py" : ""
        }
    }
}

/// Links that add skillies (docs/skillie-files.md):
/// `skilli://skillies/import?url=https://…` (repeatable). Settings →
/// Skillies shows each whole before Add, as `AppFileLink` does for apps;
/// nothing is added from a link alone.
public enum SkillieImportLink {
    /// The https addresses it names; nil for anything that is not an
    /// import link with at least one.
    public static func parse(_ url: URL) -> [URL]? {
        guard url.scheme?.lowercased() == CommandLink.scheme, url.host()?.lowercased() == "skillies",
              url.path() == "/import" || url.path() == "/import/",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let urls = items.compactMap { item -> URL? in
            guard item.name == "url", let value = item.value, let remote = URL(string: value),
                  remote.scheme?.lowercased() == "https", remote.host() != nil else { return nil }
            return remote
        }
        return urls.isEmpty ? nil : urls
    }

    /// A link to the skillies at these addresses.
    public static func importLink(for urls: [URL]) -> URL {
        // `+` and `&` encoded too: web pages read `+` as a space.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        let query = urls
            .map { "url=" + ($0.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }
            .joined(separator: "&")
        return URL(string: "\(CommandLink.scheme)://skillies/import?\(query)")!
    }
}
