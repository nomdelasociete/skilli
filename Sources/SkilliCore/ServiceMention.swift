import Foundation

/// The user's connected services (MCP servers) as Ask's decision sees
/// them: their names and a few tool names go with the request, and a
/// request that names one ("j'ai des tâches nimbus deployment ?") is noticed
/// without a model, so that the agent is at least offered.
public enum ServiceMention {
    /// Lowercased words without accents: "Nimbus-Deployment" → nimbus,
    /// deployment; "listDeployments" → list, deployments.
    public static func words(_ text: String) -> [String] {
        var spaced = ""
        var previous: Character?
        for character in text {
            // camelCase: a capital after a lowercase letter starts a word.
            if character.isUppercase, previous?.isLowercase == true { spaced.append(" ") }
            spaced.append(character)
            previous = character
        }
        return spaced.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// First words too common to stand for a service on their own.
    private static let common: Set<String> = [
        "google", "apple", "microsoft", "open", "mcp", "server", "local", "test", "demo", "api", "app", "data",
        "file", "files", "web", "search", "notes", "mail", "calendar", "my", "the", "remote", "cloud", "server"
    ]

    /// The services the request names: their whole name ("nimbus
    /// deployment"); else their first word when it stands out (four letters
    /// or more, not a common word: "nimbus" names every nimbus-… service).
    public static func named(in request: String, services: [String]) -> [String] {
        let said = words(request)
        let whole = services.filter { contains(said, words($0)) }
        guard whole.isEmpty else { return whole }
        return services.filter { service in
            let name = words(service)
            guard let first = name.first else { return false }
            return name.count > 1 && first.count >= 4 && !common.contains(first) && said.contains(first)
        }
    }

    /// The names the request says whole, as consecutive words ("ouvre mon
    /// portfolio" says the project "portfolio"; "relance le wifi" does not
    /// say "Restart Wi-Fi"). A one-word name counts from four letters and
    /// when it is not a common word. For the user's own things (projects,
    /// skillies, shortcuts): what the decision is told, never what decides.
    public static func said(in request: String, names: [String]) -> [String] {
        let words = words(request)
        return names.filter { name in
            let name = Self.words(name)
            guard name.count > 1 || name.first.map({ $0.count >= 4 && !common.contains($0) }) == true else { return false }
            return contains(words, name)
        }
    }

    /// Words of the request that are also the subject of a tool
    /// ("deployments" in listDeployments), plural or not: a hint, not a
    /// proof ("tasks" is a common word).
    public static func toolWords(in request: String, tools: [String]) -> [String] {
        let said = Set(words(request).map(stem))
        var found: [String] = []
        for tool in tools {
            for word in words(tool).dropFirst() where word.count >= 4 && !verbs.contains(word) && said.contains(stem(word)) && !found.contains(stem(word)) {
                found.append(stem(word))
            }
        }
        return found
    }

    /// What the decision is told: each service and some of its tools.
    public static func describe(_ services: [(name: String, tools: [String])], toolsEach: Int = 12) -> String {
        guard !services.isEmpty else { return "" }
        let lines = services.map { service in
            service.tools.isEmpty ? "- \(service.name)" : "- \(service.name): " + service.tools.prefix(toolsEach).joined(separator: ", ")
        }
        return "Connected services the agent can use, with some of their tools:\n" + lines.joined(separator: "\n")
    }

    private static let verbs: Set<String> = ["list", "get", "create", "update", "delete", "set", "add", "remove", "search", "find", "fetch",
                                             "read", "write", "run", "link", "unlink", "grant", "revoke", "replace", "revert", "upsert"]

    private static func stem(_ word: String) -> String {
        word.count > 4 && word.hasSuffix("s") ? String(word.dropLast()) : word
    }

    /// `needle` as consecutive words of `haystack`.
    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}
