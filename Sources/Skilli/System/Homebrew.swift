import AppKit
import SkilliCore

/// Homebrew without a terminal: names searched in its own lists (no
/// network, instant), what is installed read from its folders, updates and
/// descriptions asked to `brew`, installs and upgrades run by `brew` after
/// the user says yes.
@MainActor
final class Homebrew {
    enum Action: String, Sendable {
        case install, upgrade, uninstall

        var working: String {
            switch self {
            case .install: "Installing"
            case .upgrade: "Upgrading"
            case .uninstall: "Uninstalling"
            }
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `brew` itself; nil when Homebrew is not installed.
    let brew: URL? = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile(atPath:))
        .map { URL(fileURLWithPath: $0) }
    /// The self-test passes --dry-run: nothing installed.
    var dryRun = false
    private var names: (formulae: [String], casks: [String], stamp: Date?)?
    private var outdatedCache: (packages: [String: (installed: String, current: String)], date: Date)?
    private var descriptionCache: [String: String] = [:]
    /// The brew running now: one at a time. Two at once fight over
    /// Homebrew's update lock ("Another `brew update` process is already
    /// running"), and an install could fail while the list was refreshing.
    private var running: Task<Void, Never>?

    private var prefix: URL? { brew?.deletingLastPathComponent().deletingLastPathComponent() }

    /// Every formula and cask name, from Homebrew's API cache; read again
    /// when it changed (after a `brew update`).
    func allNames() -> (formulae: [String], casks: [String]) {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Homebrew/api", isDirectory: true)
        let formulaFile = folder.appendingPathComponent("formula_names.txt")
        let stamp = (try? formulaFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let names, names.stamp == stamp { return (names.formulae, names.casks) }
        func lines(_ file: String) -> [String] {
            ((try? String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isNewline).map(String.init)
        }
        let loaded = (lines("formula_names.txt"), lines("cask_names.txt"))
        names = (loaded.0, loaded.1, stamp)
        return loaded
    }

    /// Installed formulae and casks with their version, from Cellar and
    /// Caskroom.
    func installed() -> (formulae: [String: String], casks: [String: String]) {
        guard let prefix else { return ([:], [:]) }
        func read(_ folder: String) -> [String: String] {
            let base = prefix.appendingPathComponent(folder, isDirectory: true)
            var found: [String: String] = [:]
            for name in (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [] where !name.hasPrefix(".") {
                let versions = ((try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(name).path)) ?? [])
                    .filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                found[name] = versions.last ?? ""
            }
            return found
        }
        return (read("Cellar"), read("Caskroom"))
    }

    /// Runs brew after the one already running. Lists and descriptions
    /// never start Homebrew's own update (only an install or an upgrade
    /// does, as in a terminal).
    private func brewRun(_ arguments: [String], readOnly: Bool, timeout: TimeInterval) async throws -> (output: String, status: Int32) {
        guard let brew else { throw Failure(message: "Homebrew is not installed: brew.sh") }
        let previous = running
        let work = Task { () async throws -> (output: String, status: Int32) in
            await previous?.value
            return try await ChildProcess.run(brew, arguments, environment: readOnly ? ["HOMEBREW_NO_AUTO_UPDATE": "1"] : [:],
                                              withErrors: !readOnly, timeout: timeout)
        }
        running = Task { _ = try? await work.value }
        return try await work.value
    }

    /// Formulae and casks with a newer version; asked again after 10 min.
    func outdated() async -> [String: (installed: String, current: String)] {
        if let outdatedCache, Date.now.timeIntervalSince(outdatedCache.date) < 600 { return outdatedCache.packages }
        guard let output = try? await brewRun(["outdated", "--json=v2"], readOnly: true, timeout: 60).output else { return [:] }
        let packages = BrewSearch.outdated(Data(output.utf8))
        outdatedCache = (packages, .now)
        return packages
    }

    /// What `brew desc` says of these names, remembered.
    func descriptions(_ packages: [BrewPackage]) async -> [String: String] {
        guard brew != nil else { return [:] }
        for isCask in [false, true] {
            let missing = packages.filter { $0.isCask == isCask && descriptionCache[$0.name] == nil }.map(\.name)
            guard !missing.isEmpty else { continue }
            let output = (try? await brewRun(["desc"] + (isCask ? ["--cask"] : ["--formula"]) + missing, readOnly: true, timeout: 20).output) ?? ""
            for (name, text) in BrewSearch.descriptions(output) { descriptionCache[name] = text }
            // Unknown names are not asked again.
            for name in missing where descriptionCache[name] == nil { descriptionCache[name] = "" }
        }
        return descriptionCache
    }

    /// The packages that fit `query`, installed ones marked; with no query,
    /// the installed ones with an update first.
    func search(_ query: String, outdated: [String: (installed: String, current: String)]) -> [BrewPackage] {
        let (formulae, casks) = allNames()
        let (installedFormulae, installedCasks) = installed()
        func package(_ name: String, cask: Bool) -> BrewPackage {
            let installed = cask ? installedCasks[name] : installedFormulae[name]
            return BrewPackage(name: name, isCask: cask, description: descriptionCache[name].flatMap { $0.isEmpty ? nil : $0 },
                               installed: installed, update: installed == nil ? nil : outdated[name]?.current)
        }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            let all = installedFormulae.keys.map { package($0, cask: false) } + installedCasks.keys.map { package($0, cask: true) }
            return all.sorted { ($0.update != nil) != ($1.update != nil) ? $0.update != nil : $0.name < $1.name }
        }
        let caskSet = Set(casks)
        let ranked = BrewSearch.rank(query, formulae + casks, limit: 30)
        return ranked.map { package($0, cask: caskSet.contains($0) && !formulae.contains($0)) }
    }

    /// Runs `brew install|upgrade|uninstall [--cask] name` (all outdated
    /// ones without a name); what it printed last. --dry-run in the self-test.
    func run(_ action: Action, _ package: BrewPackage?) async throws -> String {
        guard brew != nil else { throw Failure(message: "Homebrew is not installed: brew.sh") }
        var arguments = [action.rawValue]
        if dryRun, action != .uninstall { arguments.append("--dry-run") }
        if let package {
            if package.isCask { arguments.append("--cask") }
            arguments.append(package.name)
        }
        if dryRun, action == .uninstall { return "Would uninstall \(package?.name ?? "")." }
        Log.trace("brew \(arguments.joined(separator: " "))")
        let (output, status) = try await brewRun(arguments, readOnly: false, timeout: 1_800)
        outdatedCache = nil
        let summary = BrewSearch.summary(output)
        guard status == 0 else {
            Log.actions.error("brew \(action.rawValue, privacy: .public) failed (exit \(status, privacy: .public)): \(summary, privacy: .public)")
            throw Failure(message: summary.isEmpty ? "brew \(action.rawValue) failed (exit \(status))." : summary)
        }
        return summary.isEmpty ? "brew \(action.rawValue) \(package?.name ?? ""): done." : summary
    }
}
