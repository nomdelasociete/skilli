import AppKit
import IOKit
import IOKit.ps
import LocalAuthentication
import SkilliCore
import UniformTypeIdentifiers

/// The panes of System Settings on this Mac, read from the Settings
/// extensions macOS ships (`/System/Library/ExtensionKit/Extensions`):
/// each pane's name in the user's languages, what it holds (Settings' own
/// search terms: "Night Shift" is in Displays) and its icon. Read once,
/// about 50 ms: warm it off the main thread.
enum SystemSettingsPanes {
    private static let cache = Cache()

    static func all() -> [SystemSettingsPane] {
        cache.panes()
    }

    static func pane(id: String) -> SystemSettingsPane? {
        all().first { $0.id == id }
    }

    /// The icon the Settings sidebar shows, as a small bitmap (like the
    /// apps' icons): never the full `NSWorkspace` icon.
    @MainActor
    static func icon(for pane: SystemSettingsPane) -> NSImage {
        if let icon = icons[pane.id] { return icon }
        let image = pane.iconType.flatMap { UTType($0) }.map { NSWorkspace.shared.icon(for: $0) }
            ?? NSWorkspace.shared.icon(forFile: pane.path)
        let icon = AppIndex.smallIcon(image, size: NSSize(width: 32, height: 32))
        icons[pane.id] = icon
        return icon
    }

    @MainActor private static var icons: [String: NSImage] = [:]

    /// Opens System Settings on the pane; throws when macOS would not.
    static func open(_ pane: SystemSettingsPane) throws {
        guard let url = pane.url, NSWorkspace.shared.open(url) else {
            throw SystemCommands.Failure(message: "System Settings did not open on \(pane.name).")
        }
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var read: [SystemSettingsPane]?

        func panes() -> [SystemSettingsPane] {
            lock.withLock {
                if let read { return read }
                let start = ContinuousClock.now
                let panes = SystemSettingsPanes.scan()
                Log.perf.notice("System Settings panes: \(panes.count) read in \((ContinuousClock.now - start).compact, privacy: .public)")
                read = panes
                return panes
            }
        }
    }

    private static let extensionPoint = "com.apple.Settings.extension.ui"

    /// Panes Settings shows only in a school (Classroom) or as setup
    /// reminders (FollowUps): nothing a person asks for by name.
    private static let leftOut: Set<String> = ["com.apple.Classroom-Settings.extension", "com.apple.FollowUpSettings.FollowUpSettingsExtension"]

    private static func scan() -> [SystemSettingsPane] {
        let folder = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let facts = facts()
        return items.filter { $0.pathExtension == "appex" }
            .compactMap { pane(at: $0, facts: facts) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func pane(at url: URL, facts: [String: Bool]) -> SystemSettingsPane? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              let point = bundle.infoDictionary?["EXAppExtensionAttributes"] as? [String: Any],
              point["EXExtensionPointIdentifier"] as? String == extensionPoint,
              let attributes = point["SettingsExtensionAttributes"] as? [String: Any],
              attributes["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true, !leftOut.contains(id) else { return nil }
        let development = bundle.developmentLocalization ?? "en"
        // The user's languages as this bundle has them ("fr"), and English
        // after them: "display" is typed on a French Mac too.
        let languages = (Locale.preferredLanguages.prefix(3).compactMap {
            Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [$0]).first
        } + [development]).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let infoTable = table("InfoPlist", in: bundle)
        let stringsTable = table("Localizable", in: bundle)

        // Battery or Energy, Touch ID or Login Password: the sidebar's face
        // on this Mac names the pane; the others are other names.
        let representations = attributes["representations"] as? [[String: Any]] ?? []
        let shown = SystemSettingsPane.representation(representations, facts: facts)
        // Not on this Mac: no CD drive, no game controller.
        if shown?["hidden"] as? Bool == true { return nil }
        func sidebarName(_ representation: [String: Any]?, _ language: String) -> String? {
            guard let key = representation?["sidebar-name"] as? String, !key.isEmpty else { return nil }
            return stringsTable[language]?[key] ?? infoTable[language]?[key] ?? (SystemSettingsPane.isReadable(key) ? key : nil)
        }
        func displayName(_ language: String) -> String? {
            if let name = sidebarName(shown, language) { return name }
            if let name = infoTable[language]?["CFBundleDisplayName"], SystemSettingsPane.isReadable(name) { return name }
            // The development language's names stay in the Info.plist.
            guard language == development else { return nil }
            return [bundle.infoDictionary?["CFBundleDisplayName"], bundle.infoDictionary?["CFBundleName"]]
                .compactMap { $0 as? String }.first(where: SystemSettingsPane.isReadable)
        }
        let names = languages.compactMap(displayName)
        guard let name = names.first else { return nil }
        var others = names.dropFirst().filter { $0 != name }
        for representation in representations {
            for language in languages {
                if let other = sidebarName(representation, language), other != name, !others.contains(other) { others.append(other) }
            }
        }

        // English first: Ask's decision reads the first ones.
        var sections: [String] = []
        if let file = attributes["searchTermsFileName"] as? String, !file.isEmpty {
            for language in [development] + languages.filter({ $0 != development }) {
                guard let path = bundle.path(forResource: file, ofType: "searchTerms", inDirectory: nil, forLocalization: language),
                      let terms = NSDictionary(contentsOfFile: path) as? [String: Any] else { continue }
                for title in SystemSettingsPane.sectionTitles(terms) where !sections.contains(title) { sections.append(title) }
            }
        }
        return SystemSettingsPane(id: id, name: name, otherNames: Array(others), sections: sections, path: url.path,
                                  iconType: shown?["sidebar-iconUTTypeIdentifier"] as? String)
    }

    /// A `.loctable`: every language's strings in one plist.
    private static func table(_ name: String, in bundle: Bundle) -> [String: [String: String]] {
        guard let url = bundle.url(forResource: name, withExtension: "loctable"),
              let table = NSDictionary(contentsOf: url) as? [String: Any] else { return [:] }
        return table.compactMapValues { $0 as? [String: String] }
    }

    /// What the panes' predicates ask about this Mac; one skil.li cannot
    /// read counts as yes (a mouse, a trackpad).
    private static func facts() -> [String: Bool] {
        var facts = [
            "user.isguest": NSUserName() == "Guest",
            // A school's, or a game controller's: rare, left out.
            "showClassKitPrefsPane": false,
            "showGCPrefsPane": false,
            "device.cddvd": hasService("IODVDServices") || hasService("IOCompactDiscServices")
        ]
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            facts["powersource.battery"] = sources.contains { source in
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
                return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            }
        }
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        facts["device.touchID"] = context.biometryType == .touchID
        return facts
    }

    /// A device of this IOKit class is connected (an optical drive).
    private static func hasService(_ name: String) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
        defer { if service != 0 { IOObjectRelease(service) } }
        return service != 0
    }
}
