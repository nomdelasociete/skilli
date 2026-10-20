import AppKit
import Sparkle

/// Updates of the Developer ID build, by Sparkle (`script/release`): the
/// feed (skil.li/appcast.xml) is checked once a day; a new version asks
/// before it installs. Development builds carry no feed or key: no updater
/// at all, so they never replace themselves with a release.
@MainActor
final class SoftwareUpdate: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    /// A feed and its key in this build: the menu offers Check for Updates….
    static var isConfigured: Bool {
        configured("SUFeedURL") != nil && configured("SUPublicEDKey") != nil
    }

    override init() {
        super.init()
        guard Self.isConfigured else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// skil.li has no Dock icon: its update window comes forward first.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    private static func configured(_ key: String) -> String? {
        guard let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
