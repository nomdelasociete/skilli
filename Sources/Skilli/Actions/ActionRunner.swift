import AppKit
import SkilliCore

@MainActor
final class ActionRunner {
    private let launcher: LauncherController
    private let selection: SelectionService
    private let ai: AIActionController
    private var transformInFlight = false

    /// Self-test hooks: record instead of opening URLs, expose the last
    /// transform's read path and user-visible latency.
    var dryRunURLs = false
    private(set) var lastURL: String?
    private(set) var lastTransform: (source: SelectionService.Read.Source, visible: Duration)?
    private(set) var transformCount = 0
    /// Self-test hook: transforms that found nothing to change.
    private(set) var unchangedCount = 0

    init(launcher: LauncherController, selection: SelectionService, ai: AIActionController) {
        self.launcher = launcher
        self.selection = selection
        self.ai = ai
    }

    var onOpenSettings: (() -> Void)?
    /// Runs a Mac command or puts the front window somewhere.
    var onMac: ((MacAction) -> Void)?
    /// Puts a saved window layout back.
    var onWindowLayout: ((String) -> Void)?
    /// Pastes the next older copy of the clipboard history.
    var onPasteInSequence: (() -> Void)?
    /// A launcher command that opens no mode: what its row does
    /// (`AppDelegate.run`).
    var onCommand: ((LauncherCommand.ID) -> Void)?
    /// Types a snippet in the app in front.
    var onSnippet: ((Snippet) -> Void)?

    func perform(_ action: SkilliAction, triggeredAt: ContinuousClock.Instant) {
        switch action {
        case .toggleLauncher:
            launcher.toggle(triggeredAt: triggeredAt)
        case .openSettings:
            onOpenSettings?()
        case .openApp(let path):
            openApp(at: path)
        case .transformSelection(let transform):
            Task { await self.transformSelection(transform, triggeredAt: triggeredAt) }
        case .openURL(let string):
            open(string)
        case .aiPrompt(let prompt):
            ai.run(prompt, triggeredAt: triggeredAt)
        case .askByVoice:
            ai.run(PromptLibrary.askID, triggeredAt: triggeredAt, voice: true)
        case .dictate:
            ai.dictate()
        case .clipboardHistory:
            launcher.toggle(into: .clipboard, triggeredAt: triggeredAt)
        case .searchEmoji:
            launcher.toggle(into: .emoji, triggeredAt: triggeredAt)
        case .searchMenus:
            launcher.toggle(into: .menus, triggeredAt: triggeredAt)
        case .searchGIFs:
            launcher.toggle(into: .gifs, triggeredAt: triggeredAt)
        case .pasteInSequence:
            onPasteInSequence?()
        case .mac(let action):
            onMac?(action)
        case .windowLayout(let id):
            onWindowLayout?(id)
        case .launcherCommand(let id):
            if let mode = LauncherController.mode(for: id) {
                launcher.toggle(into: mode, triggeredAt: triggeredAt)
            } else {
                onCommand?(id)
            }
        case .snippet(let id):
            guard let snippet = launcher.snippets?().first(where: { $0.id == id }) else { return gone(action, "The snippet “\(id)”") }
            onSnippet?(snippet)
        case .quicklink(let id):
            guard let link = launcher.quicklinks?().first(where: { $0.id == id }) else { return gone(action, "This shortcut's quicklink") }
            launcher.toggle(into: link, triggeredAt: triggeredAt)
        }
    }

    /// A shortcut on a snippet or quicklink deleted since (by hand in its
    /// file): it says so, and where to change it.
    private func gone(_ action: SkilliAction, _ what: String) {
        Log.actions.notice("Shortcut on something deleted: \(action.id, privacy: .public)")
        ai.notify("\(what) is no longer in skil.li: change the shortcut in Settings → Keys.", caller: "skil.li", run: nil)
    }

    private func transformSelection(_ transform: TextTransform, triggeredAt: ContinuousClock.Instant) async {
        // A second trigger while one is pasting would read our own paste.
        guard !transformInFlight else { return }
        transformInFlight = true
        defer { transformInFlight = false }

        guard let read = await selection.read(takingInputIfEmpty: true) else {
            Log.actions.notice("No selected text to transform")
            ai.notify("Select some text first: \(transform.title) changes the selected text.", caller: "skil.li", run: nil)
            return
        }
        let readAt = ContinuousClock.now
        let transformed = transform.apply(read.text)
        guard transformed != read.text else {
            // Nothing to paste: say so rather than put the same text back.
            unchangedCount += 1
            ai.notify("Nothing to change: it is already \(transform.state).", caller: "skil.li", run: nil)
            Log.actions.notice("\(transform.rawValue, privacy: .public): nothing to change")
            return
        }
        let pastedAt = await selection.replace(with: transformed)
        lastTransform = (read.source, pastedAt - triggeredAt)
        transformCount += 1
        Log.actions.notice(
            "\(transform.rawValue, privacy: .public) via \(read.source.rawValue, privacy: .public): \(read.text.count) chars, visible in \((pastedAt - triggeredAt).compact, privacy: .public) (read \((readAt - triggeredAt).compact, privacy: .public)), clipboard restored at \((ContinuousClock.now - triggeredAt).compact, privacy: .public)"
        )
    }

    private func openApp(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            Log.actions.error("App not found at \(path, privacy: .public)")
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            ai.notify("\(name) is no longer at \(path): set its shortcut again in Settings → Keys.", caller: "skil.li", run: nil)
            return
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.actions.error("Launch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func open(_ string: String) {
        lastURL = string
        if dryRunURLs { return }
        guard let url = URL(string: string) else {
            Log.actions.error("Invalid action URL \(string, privacy: .public)")
            return
        }
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            Log.actions.error("No app handles \(url.scheme ?? "?", privacy: .public):// (is it installed?)")
            ai.notify("No app on this Mac opens \(url.scheme ?? "these"): links: install the app the shortcut is for, or change it in Settings → Keys.",
                      caller: "skil.li", run: nil)
            return
        }
        NSWorkspace.shared.open(url)
    }
}
