import AppKit
import Carbon.HIToolbox
import SkilliCore

/// Types a snippet where its keyword was typed (";addr" → the address), and
/// inserts snippets picked in the launcher or by an agent.
///
/// It sees the keys the event tap lets through to the app in front. Only
/// the last few characters stay in memory, never stored or sent, and they
/// are dropped by anything that moves the caret elsewhere: a click, another
/// app, a shortcut, an arrow, five seconds without typing. Never in a
/// password field (secure input) or the apps Settings → Snippets leaves
/// out. When it waits for a space or ↩ (Settings → Snippets → Expand), a
/// ↩ that ends a keyword is held back: a chat would send the keyword.
@MainActor
final class SnippetExpander {
    private let library: SnippetLibrary
    private let selection: SelectionService
    private let preferences: Preferences
    private var matcher = SnippetMatcher()
    private var lastKey = ContinuousClock.now
    private var mouseMonitor: Any?
    private var activation: NSObjectProtocol?
    private var expanding = false
    /// Self-test hooks: snippets typed so far, and one being typed now.
    private(set) var expansions = 0
    var isExpanding: Bool { expanding }

    init(library: SnippetLibrary, selection: SelectionService, preferences: Preferences) {
        self.library = library
        self.selection = selection
        self.preferences = preferences
    }

    func start() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.matcher.reset() }
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.matcher.reset() }
        }
    }

    /// From the event tap: a key on its way to the app in front. True
    /// holds it back (↩ that ends a keyword).
    func keyDown(_ event: CGEvent) -> Bool {
        guard preferences.snippetExpansion, !expanding else { return false }
        let now = ContinuousClock.now
        if now - lastKey > .seconds(5) { matcher.reset() }
        lastKey = now
        if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty {
            matcher.reset()
            return false
        }
        let mode = preferences.snippetExpansionMode
        switch Int(event.getIntegerValueField(.keyboardEventKeycode)) {
        case kVK_Delete:
            matcher.deleteBackward()
            return false
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // ↩ alone, as the app would read it: ⇧↩ and ⌥↩ are something
            // else (a new line in a chat), never pressed again as ↩.
            guard mode.waitsForDelimiter, event.flags.intersection([.maskShift, .maskAlternate]).isEmpty else {
                matcher.reset()
                return false
            }
            matcher.type("\n")
            return expandIfKeyword(mode: mode)
        case kVK_Tab, kVK_Escape, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
            matcher.reset()
            return false
        default:
            break
        }
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &characters)
        let typed = String(utf16CodeUnits: characters, count: length)
        guard !typed.isEmpty, !typed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            matcher.reset()
            return false
        }
        matcher.type(typed)
        return expandIfKeyword(mode: mode)
    }

    /// A keyword just ended: its snippet goes in, unless the field is a
    /// password's or the app is left out. True when its ↩ is held back.
    private func expandIfKeyword(mode: SnippetExpansionMode) -> Bool {
        guard let expansion = matcher.match(library.all, mode: mode) else {
            // ↩ with no keyword before it: the line is over.
            if matcher.buffer.last == "\n" { matcher.reset() }
            return false
        }
        matcher.reset()
        // A password field, or an app left out: never.
        guard !IsSecureEventInputEnabled() else { return false }
        if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, preferences.snippetExcludedApps.contains(app) { return false }
        Task { await expand(expansion) }
        return expansion.holdsKey
    }

    /// The keyword (and the space that ended it) go, the snippet takes
    /// their place, then that space again, or ↩, when it stays.
    private func expand(_ expansion: SnippetExpansion) async {
        expanding = true
        defer { expanding = false }
        let snippet = expansion.snippet
        // The app first takes the keyword's last key: seen before the caret
        // when Accessibility shows it, else the time an app takes. A ↩
        // held back never reaches it.
        let typed = snippet.keyword + (expansion.holdsKey ? "" : expansion.delimiter)
        var seen = false
        let deadline = ContinuousClock.now + .milliseconds(300)
        while ContinuousClock.now < deadline, let before = selection.textBeforeCaret() {
            if before.hasSuffix(typed) {
                seen = true
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if !seen { try? await Task.sleep(for: .milliseconds(30)) }
        for _ in 0..<expansion.erase { selection.press(code: kVK_Delete) }
        await type(snippet, then: expansion.typedAfter, pressingReturn: expansion.pressesReturnAfter)
        Log.trace("Snippet “\(snippet.name)” expanded from its keyword (\(preferences.snippetExpansionMode.rawValue))")
    }

    /// From the launcher or an agent: at the caret of the app in front.
    func insert(_ snippet: Snippet) async {
        expanding = true
        defer { expanding = false }
        await type(snippet)
        Log.trace("Snippet “\(snippet.name)” inserted")
    }

    /// The snippet's text with its variables, for ⌘↩ in the launcher.
    func text(of snippet: Snippet) -> String {
        snippet.expanded(values(for: snippet)).text
    }

    private func type(_ snippet: Snippet, then delimiter: String = "", pressingReturn: Bool = false) async {
        let (text, back) = snippet.expanded(values(for: snippet))
        guard !text.isEmpty else { return }
        await selection.replace(with: text + delimiter)
        // The ↩ held back, as the user pressed it: after the snippet (a
        // chat sends it, an editor starts a line).
        if pressingReturn { selection.press(code: kVK_Return) }
        // The caret goes back to {cursor}, past the space or line typed
        // after it; without {cursor} it stays after everything.
        let steps = snippet.text.contains(Snippet.cursorToken) ? back + delimiter.count + (pressingReturn ? 1 : 0) : 0
        for _ in 0..<steps { selection.press(code: kVK_LeftArrow) }
        expansions += 1
    }

    /// The clipboard only when the snippet asks for it: reading it may ask
    /// the user (Paste from Other Apps).
    private func values(for snippet: Snippet) -> [PromptTemplate.Variable: String] {
        let usesClipboard = PromptTemplate(snippet.text).uses(.clipboard)
        return AIActionController.values(
            selection: "",
            clipboard: usesClipboard ? NSPasteboard.general.string(forType: .string) ?? "" : "",
            app: NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
            window: "",
            profile: ""
        )
    }
}
