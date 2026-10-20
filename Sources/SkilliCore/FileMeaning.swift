import Foundation

/// Files searched the way a person remembers them: "the lease I signed
/// last month", "my EDF bill". The decision model picks among recent
/// files, each described in one line: kind, name, folder, when.
public enum FileMeaning {
    public static let candidateLimit = 240

    /// "PDF document “Contrat location” in Documents/Admin, modified yesterday 18:02".
    public static func describe(name: String, kind: String, folder: String, modified: Date?, now: Date = .now,
                                calendar: Calendar = .current) -> String {
        var line = "\(kind.isEmpty ? "File" : kind) “\(readable(name))”"
        if !folder.isEmpty { line += " in \(folder)" }
        if let modified { line += ", modified \(ClipboardMeaning.when(modified, now: now, calendar: calendar))" }
        return line
    }

    /// "Contrat-location_appartement-2026-10-01.pdf" → "Contrat location
    /// appartement 2026-10-01": words a model reads as words; the kind
    /// says the extension, dates keep their dashes.
    public static func readable(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        var base = ext.isEmpty || ext.count > 5 || ext.contains(" ") ? name : (name as NSString).deletingPathExtension
        base = base.replacingOccurrences(of: #"(?<![0-9])[-_]+|[-_]+(?![0-9])"#, with: " ", options: .regularExpression)
        let words = base.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.isEmpty ? name : words
    }

    /// "~/Documents/Admin/x.pdf" → "Documents/Admin": the folders a person
    /// names, without the home.
    public static func folder(of path: String, home: String = NSHomeDirectory()) -> String {
        var folder = (path as NSString).deletingLastPathComponent
        if folder.hasPrefix(home) { folder = String(folder.dropFirst(home.count)) }
        return folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func input(_ request: String, now: Date = .now, calendar: Calendar = .current) -> String {
        ClipboardMeaning.input(request, now: now, calendar: calendar).replacingOccurrences(of: "copied earlier", with: "saved on this Mac")
    }

    public static let instructions = "Which of these files is the user looking for? Judge what each file is from its name, kind and folder. The user describes it as a person remembers it: what it is (in their own words: a synonym, a more common word, or another language than the file's name), roughly when, where it is. Answer none when no file fits."

    /// The words worth looking for in names: "mon contrat de location" →
    /// "contrat", "location". Short words and a few common ones left out.
    public static func significantWords(_ request: String) -> [String] {
        let common: Set<String> = ["dans", "pour", "avec", "mois", "dernier", "derniere", "dernière", "that", "this", "with", "from",
                                   "last", "the", "file", "fichier", "document", "copie", "copy", "envoyé", "envoyée"]
        var seen = Set<String>()
        // Apostrophes split too: "d'électricité" → "d", "électricité".
        return request.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 && !common.contains($0) && seen.insert($0).inserted }
    }

    /// "f contrat", "file contrat", "fichier contrat" → "contrat".
    public static func modeFilter(_ text: String) -> String? {
        LauncherPrefix.rest(of: text, after: LauncherPrefix.prefixes(for: .searchFiles))
    }
}
