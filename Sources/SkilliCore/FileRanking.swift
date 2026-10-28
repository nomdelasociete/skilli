import Foundation

/// Which of Spotlight's matches are the user's files, and in what order.
/// On a developer's Mac most names matching "readme" or "logo" are in
/// dependency folders and cloned projects: left out or put behind here,
/// from the path and the dates macOS keeps. docs/file-search.md.
public enum FileRanking {
    /// Why a path is not shown at all.
    public enum Exclusion: Equatable, Sendable {
        /// Outside the home, or in its Library (cloud drives excepted).
        case outside
        /// A folder whose name starts with a dot, or a file that does.
        case hidden
        /// node_modules, Pods, a venv…: installed, not written.
        case dependency
        /// Inside an app, a framework, a Photos library…
        case package
    }

    /// Installed code and caches: never what a person looks for by name.
    static let dependencyFolders: Set<String> = [
        "node_modules", "bower_components", "jspm_packages", "web_modules", "pods", "carthage", "vendor",
        "site-packages", "dist-packages", "__pycache__", "venv", "virtualenv", "deriveddata", "sourcepackages",
        "miniconda3", "anaconda3", "miniforge3", "gems"
    ]

    /// Folders macOS shows as one file: what is inside is theirs.
    static let packageExtensions: Set<String> = [
        "app", "framework", "xcframework", "bundle", "plugin", "kext", "appex", "photoslibrary", "musiclibrary",
        "imovielibrary", "tvlibrary", "fcpbundle", "logicx", "band", "xcassets", "imageset", "appiconset", "colorset",
        "lproj", "xcodeproj", "xcworkspace", "xcarchive", "docarchive", "playground", "pkg", "mpkg", "dsym", "rtfd",
        "scnassets", "sdk", "lrdata"
    ]

    /// A code project's build output, left out unless the user opened the file.
    static let buildFolders: Set<String> = ["build", "dist", "out", "target", "coverage", "obj"]

    /// Names that make a folder a code project's root.
    public static let projectMarkers: Set<String> = [
        ".git", "package.json", "Package.swift", "Cargo.toml", "go.mod", "pyproject.toml", "setup.py", "Gemfile",
        "composer.json", "pom.xml", "build.gradle", "CMakeLists.txt", "project.yml"
    ]

    /// The folders searched besides the home's own: cloud drives live in
    /// the Library, which is otherwise left out.
    public static let cloudFolders = ["Library/CloudStorage/", "Library/Mobile Documents/"]

    /// Nil when the path may be shown.
    public static func exclusion(of path: String, home: String) -> Exclusion? {
        guard path.hasPrefix(home + "/") else { return .outside }
        let relative = String(path.dropFirst(home.count + 1))
        if relative.hasPrefix("Library/"), !cloudFolders.contains(where: relative.hasPrefix) { return .outside }
        let components = relative.split(separator: "/")
        if components.contains(where: { $0.hasPrefix(".") }) { return .hidden }
        // "go/pkg/mod/github.com/…": Go's module cache, right in the home.
        if relative.hasPrefix("go/pkg/") { return .dependency }
        for component in components.dropLast() {
            let lower = component.lowercased()
            if dependencyFolders.contains(lower) { return .dependency }
            let ext = (lower as NSString).pathExtension
            if !ext.isEmpty, packageExtensions.contains(ext) { return .package }
        }
        return nil
    }

    /// "Projects/site/dist/logo.png" with the project at "Projects/site":
    /// in its build output.
    public static func isBuildOutput(_ path: String, projectRoot: String) -> Bool {
        guard path.hasPrefix(projectRoot + "/") else { return false }
        let inside = path.dropFirst(projectRoot.count + 1).split(separator: "/").dropLast()
        return inside.contains { buildFolders.contains($0.lowercased()) }
    }

    /// "config.ts", "main.swift": an extension typed says a code file is
    /// wanted, so projects are not put behind.
    public static func isCodeQuery(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains { word in
            // "14.32.11", a capture's time: digits alone are no extension.
            guard let dot = word.lastIndex(of: ".") else { return false }
            let ext = word[word.index(after: dot)...]
            return (1...5).contains(ext.count) && ext.allSatisfy { $0.isLetter || $0.isNumber } && ext.contains(where: \.isLetter)
        }
    }

    /// The words typed, folded the way Spotlight's "cd" compares them.
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }.filter { !$0.isEmpty }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Every word in the name or in a folder above it, one at least in the
    /// name: "martin invoice" → "Clients/Margot Martin/Invoice.pdf".
    public static func matchesFolderWords(_ words: [String], name: String, folder: String) -> Bool {
        let name = fold(name), folder = fold(folder)
        return words.contains { name.contains($0) } && words.allSatisfy { name.contains($0) || folder.contains($0) }
    }

    /// Higher first. Nil when the words do not all fit (see
    /// `matchesFolderWords`).
    public static func score(name: String, folder: String, words: [String], used: Date?, modified: Date?,
                             inProject: Bool, codeQuery: Bool, now: Date = .now) -> Int? {
        guard !words.isEmpty, matchesFolderWords(words, name: name, folder: folder) else { return nil }
        var score = matchScore(name: name, words: words)
        if let used {
            let days = now.timeIntervalSince(used) / 86_400
            score += days <= 2 ? 55 : days <= 7 ? 50 : days <= 30 ? 40 : days <= 365 ? 25 : 15
        }
        if let modified {
            let days = now.timeIntervalSince(modified) / 86_400
            score += days <= 7 ? 8 : days <= 30 ? 4 : 0
        }
        // A project's files the user never opened: its code behind what
        // they look for by name ("logo": the picture, not logo.tsx); its
        // other files behind too once nobody changed them for a month
        // (a cloned repository's README, not the one being written).
        if inProject, used == nil, !codeQuery {
            let stale = modified.map { now.timeIntervalSince($0) > 30 * 86_400 } ?? true
            score -= isCode(name) ? 40 : stale ? 20 : 0
        }
        return score
    }

    /// Source, configuration and generated files: what a project is made of.
    static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "cs", "java", "kt", "kts", "gradle", "go", "rs", "py", "rb", "php",
        "js", "jsx", "mjs", "cjs", "ts", "tsx", "vue", "svelte", "css", "scss", "less", "html", "json", "yml", "yaml", "toml",
        "xml", "plist", "sh", "zsh", "lock", "map", "sql", "dart", "lua", "ex", "exs", "tsbuildinfo"
    ]

    static func isCode(_ name: String) -> Bool {
        codeExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// The name is what was typed (60), starts with it (45), has every word
    /// at a word's start (30), has every word (15); some words only in a
    /// folder (5).
    static func matchScore(name: String, words: [String]) -> Int {
        let folded = fold(name)
        let ext = (folded as NSString).pathExtension
        let base = ext.isEmpty || ext.contains(" ") ? folded : (folded as NSString).deletingPathExtension
        let typed = words.joined(separator: " ")
        if base == typed || folded == typed { return 60 }
        if folded.hasPrefix(typed) { return 45 }
        guard words.allSatisfy({ folded.contains($0) }) else { return 5 }
        return words.allSatisfy { startsWord($0, in: name) } ? 30 : 15
    }

    /// "invoice" at a word's start in "aws-invoices" or "AwsInvoices".
    static func startsWord(_ word: String, in name: String) -> Bool {
        let characters = Array(name)
        func isStart(_ index: Int) -> Bool {
            index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber)
                || (characters[index - 1].isLowercase && characters[index].isUppercase)
                || (characters[index - 1].isLetter != characters[index].isLetter)
        }
        // Folded once, compared in place: one character per character
        // almost always.
        let folded = Array(fold(name)), target = Array(word)
        if folded.count == characters.count {
            guard target.count <= folded.count else { return false }
            return (0...(folded.count - target.count)).contains { isStart($0) && folded[$0..<$0 + target.count].elementsEqual(target) }
        }
        // A character folding into another count of them ("ß", a
        // ligature): each folded alone, so indices stay the name's.
        let each = characters.map { fold(String($0)) }
        return characters.indices.contains { isStart($0) && each[$0...].joined().hasPrefix(word) }
    }
}
