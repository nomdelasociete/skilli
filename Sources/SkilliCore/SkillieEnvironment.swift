import Foundation

/// What skil.li tells each skillie it runs, so a step can wait for its
/// answer (`"$SKILLI_CLI" call do_in_app app=… goal=…`;
/// docs/do-it-here-from-anywhere.md): its command line, where its tools
/// listen, and which run it is. Read back by `Skilli call` and `Skilli mcp`.
public enum SkillieEnvironment {
    /// The skil.li binary running the skillie.
    public static let cli = "SKILLI_CLI"
    /// Its tool server's socket.
    public static let socket = "SKILLI_SOCKET"
    /// This run's id: the card names the skillie and lends it its card.
    public static let skillie = "SKILLI_SKILLIE"

    /// The three, or none when skil.li's tools do not listen: a call would
    /// reach another skil.li.
    public static func variables(cli: String?, socket: String?, run: String) -> [String: String] {
        guard let cli, !cli.isEmpty, let socket, !socket.isEmpty else { return [:] }
        return [Self.cli: cli, Self.socket: socket, skillie: run]
    }

    /// Where `Skilli call` and `Skilli mcp` connect: `--socket`, else the
    /// skillie's skil.li, else the usual one, which alone is started when
    /// it is not running.
    public static func socket(flag: String?, environment: [String: String], defaultPath: String) -> (path: String, startsApp: Bool) {
        if let flag { return (flag, false) }
        if let path = environment[socket], !path.isEmpty { return (path, false) }
        return (defaultPath, true)
    }

    /// `app=TextEdit goal="exporte en PDF"` (the shell took the quotes) →
    /// the call's arguments, each a string; nil when a word is not
    /// `name=value` or a name comes twice.
    public static func arguments(_ words: [String]) -> [String: String]? {
        var arguments: [String: String] = [:]
        for word in words {
            guard let equals = word.firstIndex(of: "=") else { return nil }
            let name = String(word[..<equals])
            guard let first = name.first, first.isLetter || first == "_",
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), arguments[name] == nil else { return nil }
            arguments[name] = String(word[word.index(after: equals)...])
        }
        return arguments
    }
}
