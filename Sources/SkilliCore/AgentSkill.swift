import Foundation

/// A skill for Ask's agent: a folder holding a SKILL.md, whose front matter
/// names it and says when to use it, and whose text says how ("how I write
/// the weekly report"). The format Claude Code reads; skil.li hands the
/// folders to it, nothing more.
public struct AgentSkill: Equatable, Sendable {
    /// As the front matter names it, else the folder's name.
    public let name: String
    public let description: String
    /// The skill's folder (the one holding SKILL.md).
    public let folder: URL

    public init(name: String, description: String, folder: URL) {
        self.name = name
        self.description = description
        self.folder = folder
    }

    public static let fileName = "SKILL.md"

    /// The front matter's name and description ("---" lines first).
    public static func frontMatter(_ text: String) -> (name: String?, description: String?) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, nil) }
        var name: String?
        var description: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            switch key {
            case "name": name = value.isEmpty ? nil : value
            case "description": description = value.isEmpty ? nil : value
            default: break
            }
        }
        return (name, description)
    }

    /// The skills in `folder`: each subfolder with a SKILL.md, and one level
    /// further ("synced/…"); hidden folders left out. By name; the first
    /// of a name wins.
    public static func find(in folder: URL) -> [AgentSkill] {
        let manager = FileManager.default
        func children(_ url: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        func skill(at url: URL) -> AgentSkill? {
            let file = url.appendingPathComponent(fileName)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let front = frontMatter(text)
            return AgentSkill(name: front.name ?? url.lastPathComponent, description: front.description ?? "", folder: url)
        }
        var found: [AgentSkill] = []
        for child in children(folder) {
            if let skill = skill(at: child) {
                found.append(skill)
            } else {
                found += children(child).compactMap(skill(at:))
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.name.lowercased()).inserted }
    }

    /// The skills of several folders, the first folder's first: a name
    /// taken already is left out.
    public static func find(in folders: [URL]) -> [AgentSkill] {
        var seen = Set<String>()
        return folders.flatMap(find(in:)).filter { seen.insert($0.name.lowercased()).inserted }
    }

    public struct Problem: LocalizedError, Equatable, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// A name Claude Code takes: lowercase letters, digits and hyphens, 64
    /// at most ("weekly-report").
    public static func checkName(_ name: String) throws {
        guard !name.isEmpty, name.count <= 64,
              name.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            throw Problem(message: "A skill's name is lowercase letters, digits and hyphens, 64 at most: “weekly-report”.")
        }
    }

    /// "Weekly Report!" → "weekly-report".
    public static func name(from title: String) -> String {
        let folded = title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let words = folded.split { !($0.isLetter || $0.isNumber) || !$0.isASCII }
        return String(words.joined(separator: "-").prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// SKILL.md's text: the front matter, then the instructions.
    public static func markdown(name: String, description: String, instructions: String) -> String {
        let oneLine = description.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return "---\nname: \(name)\ndescription: \(oneLine)\n---\n\n" + instructions.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
