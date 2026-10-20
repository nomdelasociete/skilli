import AppKit
import ApplicationServices

/// The tabs open in Safari, Chrome, Arc, Brave, Edge and the like, read
/// through Accessibility (no Automation prompt): each window's tab group,
/// or the window itself when it shows no tabs. Choosing one presses it.
@MainActor
enum BrowserTabs {
    struct Tab {
        let app: NSRunningApplication
        let window: AXUIElement
        /// The tab's button; nil when the window is the tab.
        let element: AXUIElement?
        let title: String
        let selected: Bool

        var browser: String { app.localizedName ?? "Browser" }
    }

    static let browsers = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac", "org.chromium.Chromium",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.mozilla.firefox", "app.zen-browser.zen"
    ]

    /// Every tab of every running browser, front window first.
    static func all() -> [Tab] {
        var tabs: [Tab] = []
        for app in NSWorkspace.shared.runningApplications where browsers.contains(app.bundleIdentifier ?? "") {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.4)
            for window in children(element, kAXWindowsAttribute) where string(window, kAXSubroleAttribute) == "AXStandardWindow" {
                let found = tabsOf(window, app: app)
                tabs += found.isEmpty
                    ? [Tab(app: app, window: window, element: nil, title: string(window, kAXTitleAttribute) ?? "", selected: true)]
                    : found
            }
        }
        return tabs
    }

    /// The window's tab buttons: Safari 26 lists them as radio buttons
    /// with the AXTabButton subrole in an opaque provider list (its only
    /// AXTabGroup is the page); Chrome and friends under a tab group. Never
    /// inside the page itself, whose own radio buttons are not tabs.
    private static func tabsOf(_ window: AXUIElement, app: NSRunningApplication) -> [Tab] {
        var tabs: [Tab] = []
        var queue: [(node: AXUIElement, depth: Int, parentRole: String)] = [(window, 0, "")]
        var visited = 0
        while !queue.isEmpty, visited < 800 {
            let (node, depth, parentRole) = queue.removeFirst()
            visited += 1
            let role = string(node, kAXRoleAttribute) ?? ""
            let subrole = string(node, kAXSubroleAttribute) ?? ""
            if role == "AXWebArea" { continue }
            let tabLike = subrole == "AXTabButton" || role == "AXTab"
                || (role == "AXRadioButton" && ["AXTabGroup", "AXOpaqueProviderGroup"].contains(parentRole))
            if tabLike {
                let title = string(node, kAXTitleAttribute) ?? string(node, kAXDescriptionAttribute) ?? ""
                if !title.isEmpty {
                    let value = attribute(node, kAXValueAttribute)
                    let selected = (value as? NSNumber)?.boolValue ?? false
                    tabs.append(Tab(app: app, window: window, element: node, title: title, selected: selected))
                }
                continue
            }
            if depth < 8 { queue += children(node, kAXChildrenAttribute).map { ($0, depth + 1, role) } }
        }
        return tabs
    }

    /// The page in front when a browser is: its window's title and the
    /// address its web area gives Accessibility (AXURL).
    static func frontPage() -> (title: String, url: URL)? {
        guard let app = NSWorkspace.shared.frontmostApplication, browsers.contains(app.bundleIdentifier ?? "") else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard let focused = attribute(element, kAXFocusedWindowAttribute), CFGetTypeID(focused as CFTypeRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let window = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)
        guard let url = pageURL(of: window) else { return nil }
        return (string(window, kAXTitleAttribute) ?? url.host ?? url.absoluteString, url)
    }

    /// The address a browser window's web area gives Accessibility (AXURL):
    /// the page its tab in front shows. 600 elements read at most.
    static func pageURL(of window: AXUIElement) -> URL? {
        var queue: [(node: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 600 {
            let (node, depth) = queue.removeFirst()
            visited += 1
            if string(node, kAXRoleAttribute) == "AXWebArea", let url = attribute(node, "AXURL") as? URL,
               let scheme = url.scheme, ["http", "https", "file"].contains(scheme) {
                return url
            }
            if depth < 12 { queue += children(node, kAXChildrenAttribute).map { ($0, depth + 1) } }
        }
        return nil
    }

    /// Its browser forward, its window raised, the tab pressed.
    static func focus(_ tab: Tab) {
        tab.app.activate()
        AXUIElementSetAttributeValue(tab.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(tab.window, kAXRaiseAction as CFString)
        if let element = tab.element { AXUIElementPerformAction(element, kAXPressAction as CFString) }
        Log.trace("Tab focused in \(tab.browser)")
    }

    // MARK: - Accessibility

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func children(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        (attribute(element, name) as? [AXUIElement]) ?? []
    }
}
