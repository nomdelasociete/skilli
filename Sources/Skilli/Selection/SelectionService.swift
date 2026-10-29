import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SkilliCore

/// Reads and replaces the selected text in the frontmost app.
///
/// Read: Accessibility first (instant, no clipboard churn); if the app does not
/// expose its selection (Electron, terminals, web views), fall back to a
/// synthetic ⌘C and restore the clipboard. Replace: paste with ⌘V, so the
/// target app records a normal edit and its own ⌘Z undoes it.
///
/// ⌘C/⌘V go straight to the frontmost app's event queue, so nothing has to
/// wait for the user to release Caps Lock or the chord's keys.
@MainActor
final class SelectionService {
    struct Read {
        enum Source: String {
            case accessibility
            case clipboard
        }

        let text: String
        let source: Source
        /// Nothing was selected: skil.li selected the text being edited
        /// (`InputScope`) and took it.
        var tookInput = false
    }

    /// Whether a paste can land where the selection is.
    enum PasteTarget {
        case editable
        /// The app says the text cannot be edited (a web page, a PDF).
        case readOnly
        /// The app does not say (no Accessibility): paste and hope.
        case unknown
    }

    private let layout: KeyboardLayout
    /// Self-test hook to exercise the ⌘C fallback in apps that support AX.
    var accessibilityReadEnabled = true
    /// Self-test hook: what Accessibility says is selected, in place of the
    /// app's answer.
    var accessibilitySelectionOverride: String?
    /// Self-test hook: the answer `pasteTarget(after:)` gives.
    var pasteTargetOverride: PasteTarget?

    private static let copyTimeout: Duration = .milliseconds(350)
    /// No signal tells us when the target app has consumed a paste.
    private static let pasteSettleDelay: Duration = .milliseconds(250)
    private static let accessibilityTimeout: Float = 0.25

    init(layout: KeyboardLayout) {
        self.layout = layout
    }

    /// `takingInputIfEmpty`: with nothing selected, select and take the
    /// text being edited — the whole field, or the paragraph at the cursor
    /// in a long document (`InputScope`) — so the user sees what will be
    /// replaced. Never in password fields or terminals.
    func read(takingInputIfEmpty: Bool = false) async -> Read? {
        // Blanks alone are no selection: Arc answered a lone no-break space
        // through Accessibility, and Claude, given nothing to fix, answered
        // nothing. ⌘C then reads what the app shows selected.
        if accessibilityReadEnabled, let text = accessibilitySelectionOverride ?? readViaAccessibility(), !InputScope.isBlank(text) {
            return Read(text: text, source: .accessibility)
        }
        if takingInputIfEmpty, accessibilityReadEnabled, let taken = await takeInput() {
            return taken
        }
        if let text = await readViaCopy() {
            return Read(text: text, source: .clipboard)
        }
        return nil
    }

    /// A paste with a line break would run a command there.
    private static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "io.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm"
    ]
    /// Apps whose accessibility skil.li already turned on.
    private var accessibleApps: Set<pid_t> = []

    private func takeInput() async -> Read? {
        guard let app = NSWorkspace.shared.frontmostApplication, !Self.terminals.contains(app.bundleIdentifier ?? "") else { return nil }
        let appID = app.bundleIdentifier ?? "?"
        var element = focusedElement()
        if element.flatMap({ Self.attribute($0, kAXValueAttribute) as String? }) == nil, !accessibleApps.contains(app.processIdentifier) {
            // Electron apps (Slack, Discord, VS Code) build their
            // accessibility only when asked, as Raycast and Rectangle do.
            accessibleApps.insert(app.processIdentifier)
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            let manual = AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            Log.trace("Take input in \(appID): accessibility asked for (AXError \(manual.rawValue))")
            if manual == .success {
                for _ in 0..<4 where element.flatMap({ Self.attribute($0, kAXValueAttribute) as String? }) == nil {
                    try? await Task.sleep(for: .milliseconds(40))
                    element = focusedElement()
                }
            }
        }
        // Each way this can fail, in the dev log: lengths and roles only,
        // never the text.
        guard let element else { return notTaken("no focused element", in: appID) }
        let role = [Self.attribute(element, kAXRoleAttribute) as String?, Self.attribute(element, kAXSubroleAttribute) as String?]
            .compactMap { $0 }.joined(separator: "/")
        guard (Self.attribute(element, kAXSubroleAttribute) as String?) != kAXSecureTextFieldSubrole else {
            return notTaken("a password field", in: appID)
        }
        guard let text: String = Self.attribute(element, kAXValueAttribute) else {
            return notTaken("\(role) gives no text value", in: appID)
        }
        let length = (text as NSString).length
        guard let cursor = Self.selectedRange(element) else {
            return notTaken("\(role) (\(length) characters) gives no cursor", in: appID)
        }
        guard cursor.length == 0 else {
            return notTaken("\(role) (\(length) characters) has \(cursor.length) selected, but no selected text", in: appID)
        }
        guard let range = InputScope.range(in: text, cursor: cursor.location) else {
            return notTaken("\(role) (\(length) characters) holds only blanks", in: appID)
        }
        var selection = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &selection) else { return nil }
        let selected = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        guard selected == .success else {
            return notTaken("\(role) (\(length) characters) refused to select \(range.location)+\(range.length) (AXError \(selected.rawValue))", in: appID)
        }
        // The app must now show it selected: what the app says is selected
        // is what the paste replaces, so that text is taken. Some apps
        // select a moment later (Chromium and Electron: the page's own
        // process does), waited for as long as a ⌘C would take; some count
        // other characters than their value holds (Front: 1110 selected of
        // 1115 asked), so the app's own selected text, not the range asked.
        let asked = ContinuousClock.now
        var now: CFRange?
        var taken: String?
        while true {
            now = Self.selectedRange(element)
            if let now, now.length > 0 {
                if let shown: String = Self.attribute(element, kAXSelectedTextAttribute), !InputScope.isBlank(shown) {
                    taken = shown
                } else if now.location == range.location, now.length == range.length {
                    taken = (text as NSString).substring(with: range)
                }
            }
            guard taken == nil, ContinuousClock.now < asked + Self.copyTimeout else { break }
            try? await Task.sleep(for: .milliseconds(8))
        }
        let shown = now.map { "\($0.location)+\($0.length)" } ?? "none"
        guard let taken else {
            // Late or never: whether the selection lands in the next 3 s,
            // and the app's own count of characters, for the dev log.
            let count: Int? = Self.attribute(element, kAXNumberOfCharactersAttribute)
            Task { @MainActor in
                let deadline = asked + .seconds(3)
                var late = Self.selectedRange(element)
                while late.map({ $0.length > 0 }) != true, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                    late = Self.selectedRange(element)
                }
                let landed = late.map { "\($0.location)+\($0.length)" } ?? "none"
                Log.trace("Take input in \(appID): after \(ContinuousClock.now - asked), shows \(landed)")
            }
            return notTaken("\(role) (\(length) characters, \(count.map(String.init) ?? "no count") by the app's count) asked to select \(range.location)+\(range.length), shows \(shown)", in: appID)
        }
        Log.trace("Take input in \(appID): \(role) (\(length) characters) asked to select \(range.location)+\(range.length), shows \(shown) after \(ContinuousClock.now - asked)")
        return Read(text: taken, source: .accessibility, tookInput: true)
    }

    /// Why the text at the cursor was not taken, for the dev log.
    private func notTaken(_ reason: String, in app: String) -> Read? {
        Log.trace("Take input in \(app): \(reason)")
        return nil
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range)
        else { return nil }
        return range
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Returns when ⌘V was sent: the moment the new text appears. The
    /// clipboard is restored after that, off the user-visible path.
    @discardableResult
    func replace(with text: String) async -> ContinuousClock.Instant {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        PasteboardSnapshot.borrowing += 1
        defer { PasteboardSnapshot.borrowing -= 1 }

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        PasteboardSnapshot.markTransient(item)
        pasteboard.writeObjects([item])

        // The field's text before, when Accessibility reads it: the clipboard
        // goes back as soon as the field shows the pasted text, not on a
        // guess. Any change is not enough: keys sent just before (a snippet
        // keyword's deletes) land late in Safari or an Electron app, and the
        // clipboard back then is what the app would paste.
        let field = focusedElement()
        let before: String? = field.flatMap { Self.attribute($0, kAXValueAttribute) }
        let probe = PasteCheck.probe(text)
        SyntheticKeys.press(keyCode(for: "v", fallback: kVK_ANSI_V), flags: .maskCommand, to: frontmostPID)
        let pastedAt = ContinuousClock.now
        if let field, let before, before.utf16.count < 200_000 {
            let deadline = pastedAt + .seconds(1)
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(15))
                if let now: String = Self.attribute(field, kAXValueAttribute), PasteCheck.landed(before: before, now: now, probe: probe) { break }
            }
        } else {
            // Nothing to watch (a web page, an Electron app without
            // Accessibility): the time apps take.
            try? await Task.sleep(for: Self.pasteSettleDelay)
        }
        snapshot.restore(to: pasteboard)
        return pastedAt
    }

    /// The focused element's text, nil when Accessibility does not give
    /// it (or it is a password).
    func focusedText() -> String? {
        guard let element = focusedElement(), (Self.attribute(element, kAXSubroleAttribute) as String?) != kAXSecureTextFieldSubrole else { return nil }
        return Self.attribute(element, kAXValueAttribute)
    }

    /// What is before the caret in the focused field.
    func textBeforeCaret() -> String? {
        guard let element = focusedElement(), (Self.attribute(element, kAXSubroleAttribute) as String?) != kAXSecureTextFieldSubrole,
              let text: String = Self.attribute(element, kAXValueAttribute), let caret = Self.selectedRange(element),
              caret.location >= 0, caret.location <= (text as NSString).length
        else { return nil }
        return (text as NSString).substring(to: caret.location)
    }

    /// Whether the focus is somewhere text is typed (a field, a text area,
    /// a web or Electron text box).
    func focusIsTextInput() -> Bool {
        guard let element = focusedElement() else { return false }
        let role: String? = Self.attribute(element, kAXRoleAttribute)
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role ?? "")
            || (Self.attribute(element, kAXValueAttribute) as String?) != nil && role != kAXStaticTextRole
    }

    /// The focused element now, to tell later whether the focus moved.
    func focusNow() -> AXUIElement? { focusedElement() }

    /// Whether the focus is on another element than `previous`.
    func focusMoved(from previous: AXUIElement?) -> Bool {
        guard let current = focusedElement() else { return false }
        guard let previous else { return true }
        return !CFEqual(current, previous)
    }

    /// Whether Accessibility can see the focus at all in that app (Electron
    /// apps build it only when asked: asked here).
    func focusIsObservable(in pid: pid_t) -> Bool {
        if focusedElement() != nil { return true }
        guard !accessibleApps.contains(pid) else { return false }
        accessibleApps.insert(pid)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return focusedElement() != nil
    }

    /// Only trusted when Accessibility gave the selection: apps that do not
    /// expose it (Electron, terminals) say nothing useful about editing
    /// either, and a paste there usually works.
    func pasteTarget(after read: Read?) -> PasteTarget {
        if let pasteTargetOverride { return pasteTargetOverride }
        guard read?.source == .accessibility, let element = focusedElement() else { return .unknown }
        return Self.editability(of: element)
    }

    /// Where text typed now would land, from the focused element alone
    /// (nothing read first): Dictate's words. No focused element (an app
    /// without Accessibility): unknown, it pastes.
    func insertTarget() -> PasteTarget {
        if let pasteTargetOverride { return pasteTargetOverride }
        guard let element = focusedElement() else { return .unknown }
        return Self.editability(of: element)
    }

    /// Whether the caret is in a password field, as Accessibility says.
    func focusIsSecure() -> Bool {
        guard let element = focusedElement() else { return false }
        return (Self.attribute(element, kAXSubroleAttribute) as String?) == kAXSecureTextFieldSubrole
    }

    private static func editability(of element: AXUIElement) -> PasteTarget {
        var settable = DarwinBoolean(false)
        for attribute in [kAXSelectedTextAttribute, kAXValueAttribute] {
            if AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success, settable.boolValue {
                return .editable
            }
        }
        var value: CFTypeRef?
        // Web content inside a contenteditable (WebKit, Chromium).
        if AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &value) == .success, value != nil {
            return .editable
        }
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
           let role = value as? String, [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) {
            return .editable
        }
        return .readOnly
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.accessibilityTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(focused, to: AXUIElement.self)
    }

    /// The element with the keyboard focus now, before a panel of skil.li's
    /// takes it. One quick Accessibility call (50 ms at most).
    nonisolated static func focusedElementNow() -> FocusedElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return FocusedElement(element: unsafeDowncast(focused, to: AXUIElement.self))
    }

    /// An element's selected text, through Accessibility only (no ⌘C, no
    /// clipboard): for the launcher's preview. Any thread.
    nonisolated static func selectedText(in focused: FocusedElement) -> String? {
        AXUIElementSetMessagingTimeout(focused.element, 0.2)
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused.element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    /// `AXUIElement` is a CF reference, safe to hand between threads.
    struct FocusedElement: @unchecked Sendable {
        let element: AXUIElement

        /// In skil.li itself: read it on the main thread only. Accessibility
        /// into our own process from another thread deadlocks with the
        /// main thread's own Accessibility calls.
        var isOwn: Bool {
            var pid: pid_t = 0
            return AXUIElementGetPid(element, &pid) == .success && pid == getpid()
        }
    }

    private func readViaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.accessibilityTimeout)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeDowncast(focused, to: AXUIElement.self)

        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String,
              !text.isEmpty
        else { return nil }
        return text
    }

    private func readViaCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        PasteboardSnapshot.borrowing += 1
        defer { PasteboardSnapshot.borrowing -= 1 }
        let before = pasteboard.changeCount

        SyntheticKeys.press(keyCode(for: "c", fallback: kVK_ANSI_C), flags: .maskCommand, to: frontmostPID)

        let deadline = ContinuousClock.now + Self.copyTimeout
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(8))
        }
        // Nothing copied: no selection. The clipboard is untouched.
        guard pasteboard.changeCount != before else { return nil }

        let text = pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)
        guard let text, !InputScope.isBlank(text) else { return nil }
        return text
    }

    /// The app the user is working in. The launcher panel never activates
    /// skil.li, so this is still the right target while it is open.
    private var frontmostPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Presses a key in the app in front: "the key that types `character`"
    /// on the current layout (⌘K in Slack), or a named key code (Return).
    func press(_ character: Character, flags: CGEventFlags = []) {
        SyntheticKeys.press(keyCode(for: character, fallback: kVK_ANSI_K), flags: flags, to: frontmostPID)
    }

    func press(code: Int, flags: CGEventFlags = []) {
        SyntheticKeys.press(CGKeyCode(code), flags: flags, to: frontmostPID)
    }

    /// ⌘C must be "the key that types c" on the current layout.
    private func keyCode(for character: Character, fallback: Int) -> CGKeyCode {
        layout.keyCode(for: .character(character)) ?? CGKeyCode(fallback)
    }
}

/// Full copy of the clipboard (every item, every type) to put back after we
/// borrow it.
@MainActor
struct PasteboardSnapshot {
    /// nspasteboard.org conventions: clipboard managers skip these writes.
    private static let transientTypes = [
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    ]

    /// While skil.li borrows the clipboard (⌘C to read a selection, ⌘V to
    /// paste a result), the clipboard history looks away.
    static var borrowing = 0
    static var isBorrowing: Bool { borrowing > 0 }

    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                data[type] = item.data(forType: type)
            }
            return data
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            Self.markTransient(item)
            return item
        }
        pasteboard.writeObjects(restored)
    }

    static func markTransient(_ item: NSPasteboardItem) {
        for type in transientTypes {
            item.setData(Data(), forType: type)
        }
    }
}
