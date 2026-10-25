import AppKit
import ApplicationServices
import SkilliCore

/// Learns where the user puts windows (docs/smart-layout.md → Learning):
/// an app's windows are read when it comes to the front and again when it
/// leaves it, and a window that moved in between was moved by the user,
/// one placement. A place given with ✦W is one too, counted double. What
/// skil.li moved itself (Arrange, a layout, ✦W) is never taken for the
/// user's move. No observer on every window: the moments are the ones
/// macOS already tells. Read off the main thread; kept in
/// `placements.json`, on the Mac only.
@MainActor
final class WindowLearner {
    private struct Key: Hashable {
        let pid: pid_t
        let window: Int
    }

    /// A window as it is read off the main thread.
    fileprivate struct Reading: Sendable {
        let window: Int
        let title: String
        let document: String?
        let frame: CGRect
        let rank: Int
    }

    /// A window on screen, by its app (CoreGraphics' list: no permission).
    fileprivate struct OnScreen: Sendable {
        let pid: pid_t
        let frame: CGRect
    }

    private(set) var placements: WindowPlacements
    let file: URL?
    /// Settings → Windows, Learn where you put windows.
    var isOn: () -> Bool = { true }
    /// Settings → Windows, Never place: nothing learned from them.
    var leftOut: () -> Set<String> = { [] }
    /// Points between windows: a place with the gap is still that place.
    var gap: () -> CGFloat = { 0 }

    /// Where each window was at the last reading.
    private var seen: [Key: CGRect] = [:]
    /// Where skil.li last put a window itself.
    private var placedBySkilli: [Key: CGRect] = [:]
    private var displays: [LayoutDisplay] = []
    private var observers: [NSObjectProtocol] = []
    private var saving: Task<Void, Never>?

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li/placements.json")
    }

    init(file: URL?) {
        self.file = file
        placements = file.flatMap { try? JSONDecoder.placements.decode(WindowPlacements.self, from: Data(contentsOf: $0)) } ?? WindowPlacements()
    }

    func start() {
        guard observers.isEmpty else { return }
        displays = Displays.current()
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, learning) in [(NSWorkspace.didActivateApplicationNotification, false), (NSWorkspace.didDeactivateApplicationNotification, true)] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    if let pid, let app = NSRunningApplication(processIdentifier: pid) { self?.read(app, learning: learning) }
                }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let front = NSWorkspace.shared.frontmostApplication { self?.read(front, learning: true) }
                self?.save()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.seen = self.seen.filter { $0.key.pid != pid }
                self.placedBySkilli = self.placedBySkilli.filter { $0.key.pid != pid }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displays = Displays.current() }
        })
        // Where every window is now: the first move from here is learned.
        for app in NSWorkspace.shared.runningApplications where Self.counts(app) { read(app, learning: false) }
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        save()
    }

    private static func counts(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid() && app.bundleIdentifier != nil
    }

    // MARK: - Readings

    /// The app's windows read, off the main thread; with `learning`, each
    /// one that moved since the last reading (not by skil.li) is learned.
    private func read(_ app: NSRunningApplication, learning: Bool) {
        guard isOn(), Self.counts(app), let bundleID = app.bundleIdentifier, !leftOut().contains(bundleID) else { return }
        let pid = app.processIdentifier
        Task { [weak self] in
            let (readings, onScreen) = await Task.detached(priority: .utility) { (Self.windows(pid: pid), Self.onScreen()) }.value
            self?.take(readings, pid: pid, bundleID: bundleID, onScreen: onScreen, learning: learning)
        }
    }

    private func take(_ readings: [Reading], pid: pid_t, bundleID: String, onScreen: [OnScreen], learning: Bool) {
        var learned = 0
        for reading in readings {
            let key = Key(pid: pid, window: reading.window)
            let before = seen[key]
            seen[key] = reading.frame
            guard learning, let before, !WindowLayout.matches(before, reading.frame, tolerance: 8) else { continue }
            // Where skil.li asked, as the app rounded it.
            if let put = placedBySkilli[key], WindowLayout.matches(put, reading.frame, tolerance: WindowPlacements.Place.snap) { continue }
            placedBySkilli[key] = nil
            if record(reading, pid: pid, bundleID: bundleID, onScreen: onScreen, how: .hand) { learned += 1 }
        }
        if learned > 0 { Log.trace("Windows learned: \(learned) of \(bundleID)'s windows moved by hand") }
    }

    @discardableResult
    private func record(_ reading: Reading, pid: pid_t, bundleID: String, onScreen: [OnScreen],
                        how: WindowPlacements.Placement.How) -> Bool {
        guard let index = Self.display(of: reading.frame, among: displays) else { return false }
        let display = displays[index]
        let beside = Set(onScreen.filter { $0.pid != pid && Self.display(of: $0.frame, among: displays) == index }.map(\.pid))
            .compactMap { NSRunningApplication(processIdentifier: $0) }.filter(Self.counts).compactMap(\.bundleIdentifier)
        let placement = WindowPlacements.Placement(
            place: .of(reading.frame, in: display.visible, gap: gap()), display: WindowPlacements.displayKey(display.fingerprint),
            title: reading.title, document: reading.document, rank: reading.rank, with: beside, how: how, at: .now)
        placements.record(placement, bundleID: bundleID, displays: displays.map { WindowPlacements.displayKey($0.fingerprint) })
        saveSoon()
        return true
    }

    /// The display showing most of `frame`.
    private static func display(of frame: CGRect, among displays: [LayoutDisplay]) -> Int? {
        let areas = displays.map { $0.frame.intersection(frame) }.map { $0.isNull ? 0 : $0.width * $0.height }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    // MARK: - What skil.li moved

    /// skil.li put this window there itself: not the user's move.
    func placed(_ window: AXUIElement, at frame: CGRect) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        placedBySkilli[Key(pid: pid, window: Int(CFHash(window)))] = frame
    }

    /// The user gave this window a place with ✦W: learned at once, counted
    /// double.
    func placedWithKey(_ window: AXUIElement, at frame: CGRect) {
        var owner: pid_t = 0
        guard isOn(), AXUIElementGetPid(window, &owner) == .success, let app = NSRunningApplication(processIdentifier: owner), Self.counts(app),
              let bundleID = app.bundleIdentifier, !leftOut().contains(bundleID) else { return }
        let pid = owner
        let hash = Int(CFHash(window))
        Task { [weak self] in
            let (readings, onScreen) = await Task.detached(priority: .utility) { (Self.windows(pid: pid), Self.onScreen()) }.value
            guard let self, let reading = readings.first(where: { $0.window == hash }) else { return }
            let key = Key(pid: pid, window: hash)
            self.seen[key] = reading.frame
            self.placedBySkilli[key] = reading.frame
            self.record(reading, pid: pid, bundleID: bundleID, onScreen: onScreen, how: .key)
        }
    }

    /// Before Arrange moves anything: the moves made since the last
    /// readings are learned first (the app in front has not left it yet).
    func catchUp() async {
        guard isOn(), let front = NSWorkspace.shared.frontmostApplication, Self.counts(front), let bundleID = front.bundleIdentifier,
              !leftOut().contains(bundleID) else { return }
        let pid = front.processIdentifier
        let (readings, onScreen) = await Task.detached(priority: .userInitiated) { (Self.windows(pid: pid), Self.onScreen()) }.value
        take(readings, pid: pid, bundleID: bundleID, onScreen: onScreen, learning: true)
    }

    // MARK: - Forget, keep

    /// Forget what skil.li learned; what it was, for Undo.
    func forget() -> WindowPlacements {
        let was = placements
        placements = WindowPlacements()
        save()
        return was
    }

    func restore(_ placements: WindowPlacements) {
        self.placements = placements
        save()
    }

    /// Never place: nothing kept about these apps either.
    func forget(apps: Set<String>) {
        guard !apps.isEmpty else { return }
        let before = placements
        placements.forget(apps)
        if placements != before { saveSoon() }
    }

    /// Written at most once every 10 s.
    private func saveSoon() {
        guard saving == nil else { return }
        saving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.save()
        }
    }

    func save() {
        saving?.cancel()
        saving = nil
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if placements.isEmpty {
                try? FileManager.default.removeItem(at: file)
            } else {
                try JSONEncoder.placements.encode(placements).write(to: file, options: .atomic)
            }
        } catch {
            Log.trace("Windows learned: not written (\(error.localizedDescription))")
        }
    }

    // MARK: - Off the main thread

    /// The app's standard, visible windows, front first.
    nonisolated private static func windows(pid: pid_t) -> [Reading] {
        let app = AXUIElementCreateApplication(pid)
        // A busy app must not hold the reading up.
        AXUIElementSetMessagingTimeout(app, 0.2)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success, let list = raw as? [AXUIElement] else { return [] }
        var readings: [Reading] = []
        for window in list {
            guard string(window, kAXSubroleAttribute) == "AXStandardWindow", bool(window, kAXMinimizedAttribute) != true,
                  bool(window, "AXFullScreen") != true, let frame = frame(window) else { continue }
            let document = string(window, kAXDocumentAttribute).flatMap { URL(string: $0)?.isFileURL == true ? $0 : nil }
            readings.append(Reading(window: Int(CFHash(window)), title: string(window, kAXTitleAttribute) ?? "", document: document,
                                    frame: frame, rank: readings.count))
        }
        return readings
    }

    /// The apps' windows on screen now, at the normal level.
    nonisolated private static func onScreen() -> [OnScreen] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0, let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 40, frame.height > 40 else { return nil }
            return OnScreen(pid: pid, frame: frame)
        }
    }

    nonisolated private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    nonisolated private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    nonisolated private static func frame(_ window: AXUIElement) -> CGRect? {
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

private extension JSONEncoder {
    static var placements: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var placements: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
