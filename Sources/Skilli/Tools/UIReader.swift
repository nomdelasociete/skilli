import AppKit
import ApplicationServices
import SkilliCore

/// What an agent sees of the window in front, and how it acts on it: the
/// buttons, boxes, fields and links Accessibility exposes, each with an id
/// ("e12") it can press or fill. Secure fields are named, never read.
@MainActor
final class UIReader {
    /// `AXUIElement` is a CF reference, safe to hand between threads.
    struct Element: @unchecked Sendable {
        let id: String
        let role: String
        let label: String
        let value: String?
        let enabled: Bool
        let element: AXUIElement
        /// On screen, top-left origin; nil when the app does not say.
        var frame: CGRect?

        /// `e12 checkbox “Remember me” (on)`.
        var line: String {
            var text = "\(id) \(role)"
            if !label.isEmpty { text += " “\(label)”" }
            if let value, !value.isEmpty {
                text += role == "checkbox" || role == "radio" ? " (\(value == "1" ? "on" : "off"))" : " = “\(value)”"
            }
            if !enabled { text += " (disabled)" }
            return text
        }
    }

    /// The last snapshot's elements, by id: what press and fill act on.
    private var elements: [String: Element] = [:]
    /// The app of the last snapshot: what the card names.
    private var app = ""

    /// Containers of rows: only their first rows are read.
    nonisolated private static let lists: Set<String> = ["AXList", "AXTable", "AXOutline", "AXGrid", "AXColumn", "AXBrowser"]

    nonisolated private static let roles: [String: String] = [
        "AXButton": "button", "AXCheckBox": "checkbox", "AXRadioButton": "radio", "AXTextField": "text field",
        "AXTextArea": "text area", "AXComboBox": "combo box", "AXPopUpButton": "pop-up", "AXMenuButton": "menu button",
        "AXLink": "link", "AXSlider": "slider", "AXDisclosureTriangle": "disclosure", "AXIncrementor": "stepper",
        "AXStaticText": "text", "AXMenuItem": "menu item"
    ]

    /// The front window of `pid`: its title and its elements, in reading
    /// order. Bounded (4 000 nodes visited, 200 kept) so a web page stays
    /// fast.
    func read(pid: pid_t) -> (app: String, window: String, elements: [Element]) {
        let snapshot = Self.snapshot(pid: pid)
        elements = Dictionary(uniqueKeysWithValues: snapshot.elements.map { ($0.id, $0) })
        app = snapshot.app
        return (snapshot.app, snapshot.window, snapshot.elements)
    }

    /// `button “Desktop & Dock” in System Settings`: what the card says a
    /// press or a fill acts on, never its id. Nil for an id not read.
    func describe(_ id: String) -> String? {
        guard let element = elements[id] else { return nil }
        let name = element.label.isEmpty ? element.role : "\(element.role) “\(element.label)”"
        return app.isEmpty ? name : "\(name) in \(app)"
    }

    /// The element's label and its value now (not the snapshot's: a field
    /// filled since has text), for what may not be taken back ("Send", a
    /// field that has text).
    func label(_ id: String) -> (label: String, value: String?)? {
        elements[id].map { ($0.label, Self.value($0.element) ?? $0.value) }
    }

    /// The front window of `pid` as `read` sees it, with the window's frame
    /// and each element's. Off the main thread for other apps; skil.li's
    /// own windows on it (Accessibility into our own process from another
    /// thread deadlocks with the main one). `cutShort`: `budget` ran out
    /// before the whole window was read (an app slow to answer: Chess once
    /// gave 15 of its 73 elements in 2 s).
    nonisolated static func snapshot(pid: pid_t, budget: Duration = .seconds(2))
        -> (app: String, window: String, frame: CGRect?, elements: [Element], cutShort: Bool) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
        guard let window: AXUIElement = Self.attribute(app, kAXFocusedWindowAttribute) ?? Self.attribute(app, kAXMainWindowAttribute) else {
            return (name, "", nil, [], false)
        }
        let title: String = Self.attribute(window, kAXTitleAttribute) ?? ""
        var found: [Element] = []
        var texts = 0
        var stack: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        // An app slow to answer (a dialog changing folder): what was read in
        // its budget.
        let deadline = ContinuousClock.now + budget
        var cutShort = false
        while let (node, depth) = stack.popLast(), visited < 4_000, found.count < 200 {
            guard ContinuousClock.now < deadline else {
                cutShort = true
                break
            }
            visited += 1
            let role: String = Self.attribute(node, kAXRoleAttribute) ?? ""
            if let kind = Self.roles[role] {
                let subrole: String = Self.attribute(node, kAXSubroleAttribute) ?? ""
                let secure = subrole == "AXSecureTextField"
                let label = Self.label(node, role: role)
                let value = secure ? nil : Self.value(node)
                if kind == "text" {
                    // A few short texts give the buttons their context.
                    if let text = value ?? (label.isEmpty ? nil : label), !text.isEmpty, text.count <= 80, texts < 40 {
                        texts += 1
                        found.append(Element(id: "e\(found.count + 1)", role: kind, label: text, value: nil, enabled: true, element: node,
                                             frame: Self.frame(node)))
                    }
                } else if kind != "menu item" || !label.isEmpty {
                    // (A separator is a menu item without a title.)
                    let enabled: Bool = Self.attribute(node, kAXEnabledAttribute) ?? true
                    found.append(Element(id: "e\(found.count + 1)", role: secure ? "password field" : kind, label: label,
                                         value: value, enabled: enabled, element: node, frame: Self.frame(node)))
                }
            }
            guard depth < 40, var children: [AXUIElement] = Self.attribute(node, kAXChildrenAttribute) else { continue }
            // A list's first rows only (a save dialog's file browser lists a
            // whole folder): the controls after it must fit in too.
            if Self.lists.contains(role), children.count > 25 { children = Array(children.prefix(25)) }
            // Reading order: the first child is looked at first.
            for child in children.reversed() { stack.append((child, depth + 1)) }
        }
        // A menu open over the window (a pop-up's list, "File Format"):
        // its items, which Accessibility lists beside the window.
        let open: [AXUIElement] = (Self.attribute(app, kAXChildrenAttribute) ?? []).filter { child in
            (Self.attribute(child, kAXRoleAttribute) as String?) == "AXMenu"
        }
        for menu in open {
            for item in (Self.attribute(menu, kAXChildrenAttribute) as [AXUIElement]?) ?? [] where found.count < 260 && ContinuousClock.now < deadline {
                let label: String = Self.attribute(item, kAXTitleAttribute) ?? ""
                guard !label.isEmpty else { continue }
                let enabled: Bool = Self.attribute(item, kAXEnabledAttribute) ?? true
                found.append(Element(id: "e\(found.count + 1)", role: "menu item", label: Self.clipped(label), value: nil, enabled: enabled,
                                     element: item, frame: Self.frame(item)))
            }
        }
        return (name, title, frame(window), found, cutShort)
    }

    /// Where Accessibility says `node` is on screen (top-left origin).
    nonisolated static func frame(_ node: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(node, kAXPositionAttribute), let size: AXValue = attribute(node, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent), extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    func element(_ id: String) -> Element? {
        elements[id]
    }

    /// Presses a button, ticks a box, follows a link; a field gets the
    /// focus. Returns what it did.
    func press(_ id: String) throws -> String {
        guard let element = elements[id] else { throw Failure(message: "No element “\(id)”: read the screen again (list_ui).") }
        if element.role.hasSuffix("field") || element.role == "text area" || element.role == "combo box" {
            AXUIElementSetAttributeValue(element.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return "Focused \(element.role) “\(element.label)”."
        }
        for action in [kAXPressAction, kAXConfirmAction, kAXPickAction] {
            if AXUIElementPerformAction(element.element, action as CFString) == .success {
                return "Pressed \(element.role) “\(element.label)”."
            }
        }
        throw Failure(message: "\(element.role.capitalized) “\(element.label)” cannot be pressed.")
    }

    /// Fills a field: its value set directly, else focused for typing.
    /// True when the value now reads back.
    func setValue(_ id: String, _ text: String) throws -> Bool {
        guard let element = elements[id] else { throw Failure(message: "No element “\(id)”: read the screen again (list_ui).") }
        guard element.role != "password field" else { throw Failure(message: "skil.li does not fill password fields.") }
        AXUIElementSetAttributeValue(element.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element.element, kAXValueAttribute as CFString, text as CFString)
        return Self.value(element.element) == text
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Accessibility

    nonisolated private static func label(_ node: AXUIElement, role: String) -> String {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXHelpAttribute] {
            if let text: String = attribute(node, name), !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return clipped(text)
            }
        }
        // A field named by the label next to it.
        if let titleElement: AXUIElement = attribute(node, kAXTitleUIElementAttribute),
           let text: String = attribute(titleElement, kAXValueAttribute) {
            return clipped(text)
        }
        return ""
    }

    nonisolated private static func value(_ node: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, kAXValueAttribute as CFString, &raw) == .success, let raw else { return nil }
        if let text = raw as? String { return clipped(text) }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    nonisolated private static func clipped(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }

    nonisolated private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self { return (value as! T) }
        if T.self == [AXUIElement].self { return value as? T }
        return value as? T
    }
}
