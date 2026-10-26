import AppKit
import ApplicationServices
import SkilliCore

/// Usual places (docs/smart-layout.md, off by default): a window an app
/// just opened is put where the user usually puts it, only when that place
/// is sure (`WindowPlacements.sure`) and the window still untouched
/// (`UsualPlace.untouched`). An app launched: its first window, waited on
/// with `AXWait` (an app reopening several windows is left to Arrange
/// Windows). An app already running: a window-created observer, only on
/// the apps with enough placements on these displays to ever be sure
/// (`WindowPlacements.mayBeSure`), added and removed as that changes.
/// ✦W R puts the window back where it opened.
@MainActor
final class UsualPlaces {
    private let learner: WindowLearner
    private let manager: WindowManager
    /// Settings → Windows, Place new windows where you usually put them.
    var isOn: () -> Bool = { false }
    /// Settings → Windows, Never place.
    var leftOut: () -> Set<String> = { [] }
    var gap: () -> CGFloat = { 0 }
    private var observers: [NSObjectProtocol] = []
    /// The apps observed for new windows, by process.
    private var watched: [pid_t: (observer: AXObserver, app: AXUIElement)] = [:]
    /// Windows being placed or just placed: one window-created notice each.
    private var handled: Set<Int> = []

    init(learner: WindowLearner, manager: WindowManager) {
        self.learner = learner
        self.manager = manager
    }

    /// The observer counts, for the self-test.
    var watchedCount: Int { watched.count }

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
                Task {
                    await self.placeFirstWindow(of: app)
                    self.refresh()
                }
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid { self?.unwatch(pid) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        for pid in Array(watched.keys) { unwatch(pid) }
    }

    // MARK: - Apps observed

    /// Observers on exactly the running apps that may have a sure place on
    /// these displays; none while off. Called when the setting, the
    /// placements, the apps or the displays change.
    func refresh() {
        var wanted: Set<pid_t> = []
        if isOn(), learner.isOn() {
            let keys = Displays.current().map { WindowPlacements.displayKey($0.fingerprint) }
            let leftOut = leftOut()
            for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != getpid() && app.isFinishedLaunching {
                guard let bundleID = app.bundleIdentifier, !leftOut.contains(bundleID),
                      learner.placements.mayBeSure(bundleID: bundleID, displays: keys) else { continue }
                wanted.insert(app.processIdentifier)
            }
        }
        for pid in watched.keys where !wanted.contains(pid) { unwatch(pid) }
        for pid in wanted where watched[pid] == nil { watch(pid) }
    }

    private func watch(_ pid: pid_t) {
        var made: AXObserver?
        guard AXObserverCreate(pid, usualWindowCreated, &made) == .success, let observer = made else { return }
        let element = AXUIElementCreateApplication(pid)
        // A busy app must not hold skil.li up when its new window is read.
        AXUIElementSetMessagingTimeout(element, 0.3)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        watched[pid] = (observer, element)
    }

    private func unwatch(_ pid: pid_t) {
        guard let entry = watched.removeValue(forKey: pid) else { return }
        AXObserverRemoveNotification(entry.observer, entry.app, kAXWindowCreatedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
    }

    /// A window an observed app just created.
    fileprivate func windowCreated(_ window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, let entry = watched[pid],
              let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier else { return }
        let appeared = ContinuousClock.now
        let owner = pid
        Task { await self.place(window, of: entry.app, pid: owner, bundleID: bundleID, appeared: appeared) }
    }

    // MARK: - Placing

    /// The app's first window, once it shows, to its usual place.
    private func placeFirstWindow(of app: NSRunningApplication) async {
        guard isOn(), learner.isOn(), app.activationPolicy == .regular, app.processIdentifier != getpid(),
              let bundleID = app.bundleIdentifier, !leftOut().contains(bundleID) else { return }
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var windows: [AXUIElement] = []
        var appeared: ContinuousClock.Instant?
        _ = await AXWait.until(pid: pid, element: element, notifications: [kAXWindowCreatedNotification], timeout: .seconds(4)) {
            windows = Self.standardWindows(of: element)
            if !windows.isEmpty, appeared == nil { appeared = .now }
            return !windows.isEmpty
        }
        guard let appeared, let window = windows.first else { return }
        await place(window, of: element, pid: pid, bundleID: bundleID, appeared: appeared, single: true)
    }

    /// `window` to its usual place when sure and untouched. `single`: an
    /// app just launched, whose other windows mean it reopened several.
    private func place(_ window: AXUIElement, of element: AXUIElement, pid: pid_t, bundleID: String, appeared: ContinuousClock.Instant,
                       single: Bool = false) async {
        guard isOn(), learner.isOn(), !leftOut().contains(bundleID) else { return }
        let id = Int(CFHash(window))
        guard !handled.contains(id) else { return }
        handled.insert(id)
        defer {
            // Kept a moment: the launch and an observer can both see it.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.handled.remove(id)
            }
        }
        // A title often comes a moment after the window (a page's): taken
        // when it changes, within the first second.
        var title = Self.string(window, kAXTitleAttribute) ?? ""
        if title.isEmpty {
            _ = await AXWait.until(pid: pid, element: window, notifications: [kAXTitleChangedNotification],
                                   timeout: max(.zero, appeared + .seconds(1) - .now)) {
                title = Self.string(window, kAXTitleAttribute) ?? ""
                return !title.isEmpty
            }
        }
        let windows = Self.standardWindows(of: element)
        guard let rank = windows.firstIndex(where: { CFEqual($0, window) }), let frame = Self.frame(window) else { return }
        // Several windows at launch (an app reopening its documents): Arrange's, not one by one.
        if single, windows.count > 1 {
            Log.trace("Usual places: \(bundleID) opened several windows, left to Arrange Windows")
            return
        }
        let appearedAgo = (ContinuousClock.now - appeared).milliseconds / 1_000
        let keyAgo = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let clickAgo = min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown),
                           CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown))
        guard UsualPlace.untouched(appearedAgo: appearedAgo, keyAgo: keyAgo, clickAgo: clickAgo, mouseDown: NSEvent.pressedMouseButtons != 0) else {
            Log.trace("Usual places: \(bundleID)'s window already touched (or too late), left where it opened")
            return
        }
        let displays = Displays.current()
        let keys = displays.map { WindowPlacements.displayKey($0.fingerprint) }
        let document = Self.string(window, kAXDocumentAttribute).flatMap { URL(string: $0)?.isFileURL == true ? $0 : nil }
        let asked = WindowPlacements.Window(bundleID: bundleID, title: title, document: document, rank: rank,
                                            with: Self.appsBeside(pid: pid, frame: frame, displays: displays))
        guard let choice = learner.placements.sure(for: asked, displays: keys, at: .now),
              let index = keys.firstIndex(of: choice.display) else { return }
        let target = choice.place.frame(in: displays[index].visible, gap: gap())
        guard !WindowLayout.matches(frame, target, tolerance: 4) else { return }
        do {
            try WindowManager.place(window, of: element, at: target)
            manager.remember(window, pid: pid, placed: target, before: frame)
            Log.trace("Usual places: \(bundleID)'s window put where it usually goes (\(choice.count) placements, \(Int(choice.share * 100)) %)")
        } catch {
            Log.trace("Usual places: \(bundleID)'s window did not move (\(error.localizedDescription))")
        }
    }

    // MARK: - Accessibility

    /// Standard windows, not minimized, not full screen.
    private static func standardWindows(of app: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success, let list = raw as? [AXUIElement] else { return [] }
        return list.filter {
            string($0, kAXSubroleAttribute) == "AXStandardWindow" && bool($0, kAXMinimizedAttribute) != true && bool($0, "AXFullScreen") != true
        }
    }

    /// The other apps with a window on the display showing most of `frame`
    /// (CoreGraphics' window list: no permission).
    private static func appsBeside(pid: pid_t, frame: CGRect, displays: [LayoutDisplay]) -> [String] {
        func display(of rect: CGRect) -> Int? {
            let areas = displays.map { $0.frame.intersection(rect) }.map { $0.isNull ? 0 : $0.width * $0.height }
            return areas.indices.max { areas[$0] < areas[$1] }.flatMap { areas[$0] > 0 ? $0 : nil }
        }
        guard let here = display(of: frame),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var apps: Set<String> = []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner != pid, owner != getpid(),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), display(of: rect) == here,
                  let app = NSRunningApplication(processIdentifier: owner), app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier else { continue }
            apps.insert(bundleID)
        }
        return apps.sorted()
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func frame(_ window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }
}

/// Accessibility calls it on the main run loop, where the observer's source
/// was added. A free function: a closure written in main-actor code would
/// be isolated to it.
private func usualWindowCreated(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    let address = UInt(bitPattern: refcon)
    guard address != 0 else { return }
    nonisolated(unsafe) let window = element
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<UsualPlaces>.fromOpaque(pointer).takeUnretainedValue().windowCreated(window)
    }
}
