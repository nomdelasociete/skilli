import Foundation

/// A Homebrew formula or cask, as the launcher shows it.
public struct BrewPackage: Hashable, Sendable {
    public let name: String
    public let isCask: Bool
    public var description: String?
    /// The version installed, nil when it is not.
    public var installed: String?
    /// A newer version, when there is one.
    public var update: String?

    public init(name: String, isCask: Bool, description: String? = nil, installed: String? = nil, update: String? = nil) {
        self.name = name
        self.isCask = isCask
        self.description = description
        self.installed = installed
        self.update = update
    }

    /// formulae.brew.sh's page for it.
    public var page: URL {
        URL(string: "https://formulae.brew.sh/\(isCask ? "cask" : "formula")/\(name)")!
    }

    /// "Installed 7.1", "Update 7.1 → 7.2", "Cask".
    public var status: String {
        if let installed, let update { return "Update \(installed) → \(update)" }
        if let installed { return installed.isEmpty ? "Installed" : "Installed \(installed)" }
        return isCask ? "Cask" : "Formula"
    }
}

/// Homebrew's names searched the way people type them, and what `brew`
/// prints read back.
public enum BrewSearch {
    /// Names that fit, best first: the name itself, then names starting
    /// with it, then a part of a name ("ffmpeg" in "ffmpeg@6"), then any
    /// name containing it; shorter first among equals.
    public static func rank(_ query: String, _ names: [String], limit: Int = 30) -> [String] {
        let wanted = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return [] }
        var scored: [(name: String, score: Int)] = []
        for name in names {
            let lower = name.lowercased()
            let score: Int
            if lower == wanted {
                score = 4
            } else if lower.hasPrefix(wanted) {
                score = 3
            } else if lower.split(whereSeparator: { "-@._".contains($0) }).contains(where: { $0.hasPrefix(wanted) }) {
                score = 2
            } else if lower.contains(wanted) {
                score = 1
            } else {
                continue
            }
            scored.append((name, score))
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.name.count != $1.name.count ? $0.name.count < $1.name.count : $0.name < $1.name }
            .prefix(limit).map(\.name)
    }

    /// `brew outdated --json=v2`: name → (installed, newest).
    public static func outdated(_ json: Data) -> [String: (installed: String, current: String)] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [:] }
        var found: [String: (String, String)] = [:]
        for key in ["formulae", "casks"] {
            for item in root[key] as? [[String: Any]] ?? [] {
                guard let name = item["name"] as? String, let current = item["current_version"] as? String else { continue }
                let installed = (item["installed_versions"] as? [String])?.last ?? ""
                found[name] = (installed, current)
            }
        }
        return found
    }

    /// `brew desc`: "ffmpeg: Play, record…", a cask's "(Mozilla Firefox) Web browser".
    public static func descriptions(_ output: String) -> [String: String] {
        var found: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            var text = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // A cask's app name in parentheses first: kept, without them.
            if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
                let app = text[text.index(after: text.startIndex)..<close]
                let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
                text = rest.isEmpty ? String(app) : "\(app) — \(rest)"
            }
            // Package names are lowercase: "Warning: …" is brew talking.
            if !name.isEmpty, !name.contains(" "), name == name.lowercased(), !text.isEmpty { found[name] = text }
        }
        return found
    }

    /// The last lines a `brew` run printed that say something: what the
    /// card shows.
    public static func summary(_ output: String, lines: Int = 3) -> String {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==> Downloading") && !$0.hasPrefix("####") }
            .suffix(lines).joined(separator: "\n")
    }
}
