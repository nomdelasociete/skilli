import AppKit
import ApplicationServices
import ScreenCaptureKit
import SkilliCore

/// A window that can be recorded, as rows and menus name it: its app and
/// its title (read on this Mac with Screen Recording, never sent anywhere).
struct ScreenWindow: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String

    /// "Google Chrome · Meet – Weekly design review".
    var name: String { title.isEmpty ? app : "\(app) · \(title)" }
}

/// One of the Mac's screens, for the whole screen
/// (docs/meeting-recorder-views.md, "The whole screen"): its display and
/// its name as macOS gives it, told apart from a twin's.
struct ScreenDisplay: Equatable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    /// The Mac had other screens when it was listed: its name is said.
    let several: Bool

    /// "Whole Screen", or "Whole Screen · LG UltraFine".
    var title: String { WholeScreen.title(name, several: several) }
}

/// What the screen records: one window, or a whole screen.
enum ScreenTarget: Equatable, Sendable {
    case window(ScreenWindow)
    case display(ScreenDisplay)

    /// As the row and the menus name it.
    var name: String {
        switch self {
        case .window(let window): window.name
        case .display(let display): display.title
        }
    }

    /// The same window or screen, whatever its title says now.
    func isSame(as other: ScreenTarget?) -> Bool {
        switch (self, other) {
        case (.window(let a), .window(let b)?): a.id == b.id
        case (.display(let a), .display(let b)?): a.id == b.id
        default: false
        }
    }
}

/// The Mac's screens, in the order the lists show them: the one the
/// meeting's window is on first, else the main one (`WholeScreen`).
@MainActor
enum ScreenDisplays {
    static func list(meeting window: CGWindowID? = nil) -> [ScreenDisplay] {
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return (id, screen.localizedName)
        }
        let names = WholeScreen.distinctNames(screens.map(\.1))
        let displays = zip(screens, names).map { WholeScreen.Display(id: $0.0, name: $1, frame: CGDisplayBounds($0.0)) }
        let ordered = WholeScreen.ordered(displays, main: CGMainDisplayID(), window: window.flatMap(ScreenWindows.bounds))
        return ordered.map { ScreenDisplay(id: $0.id, name: $0.name, several: ordered.count > 1) }
    }

    /// The screen a tool's or a link's `display` names (`main`,
    /// `meeting`, a name); nil: none.
    static func named(_ text: String, meeting window: CGWindowID?) -> ScreenDisplay? {
        let all = list(meeting: window)
        let displays = all.map { WholeScreen.Display(id: $0.id, name: $0.name, frame: CGDisplayBounds($0.id)) }
        guard let found = WholeScreen.named(text, in: displays, main: CGMainDisplayID(), window: window.flatMap(ScreenWindows.bounds)) else { return nil }
        return all.first { $0.id == found.id }
    }

    static func isConnected(_ id: CGDirectDisplayID) -> Bool {
        NSScreen.screens.contains { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }
}

/// What the screen's lists offer (the Record card's ⌃⌄, the red dot's
/// Screen ▸; docs/meeting-recorder-views.md, "The whole screen"): the
/// meeting's window, the whole screen (each screen by its name when the
/// Mac has several), then the other windows.
struct ScreenChoices {
    enum Entry {
        case header(String)
        /// Indented: under a header.
        case pick(ScreenTarget, title: String, indented: Bool)
        case separator
    }

    var meeting: ScreenWindow?
    var displays: [ScreenDisplay]
    var windows: [ScreenWindow]

    #if SKILLI_SELFTEST
    /// Self-test: the guides' invented windows and screens, in place of
    /// the Mac's.
    @MainActor static var standIn: ScreenChoices?
    #endif

    @MainActor static func now(meeting: ScreenWindow?) -> ScreenChoices {
        #if SKILLI_SELFTEST
        if let standIn { return standIn }
        #endif
        return ScreenChoices(meeting: meeting, displays: ScreenDisplays.list(meeting: meeting?.id), windows: ScreenWindows.list())
    }

    var entries: [Entry] {
        var entries: [Entry] = []
        if let meeting {
            entries += [.header("The Meeting's Window"), .pick(.window(meeting), title: meeting.name, indented: true), .separator]
        }
        if displays.count == 1 {
            entries.append(.pick(.display(displays[0]), title: displays[0].title, indented: false))
        } else if !displays.isEmpty {
            entries.append(.header("Whole Screen"))
            entries += displays.map { .pick(.display($0), title: $0.name, indented: true) }
        }
        let others = windows.filter { $0.id != meeting?.id }
        if !displays.isEmpty, !others.isEmpty { entries.append(.separator) }
        entries += others.map { .pick(.window($0), title: $0.name, indented: false) }
        return entries
    }

    /// The menu's items, the one recorded checked; each pick's `tag` its
    /// place in the targets returned, its action `action` on `target`.
    func items(recorded: ScreenTarget?, action: Selector, target: AnyObject) -> (items: [NSMenuItem], targets: [ScreenTarget]) {
        var targets: [ScreenTarget] = []
        let items = entries.map { entry -> NSMenuItem in
            switch entry {
            case .header(let title):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                return item
            case .pick(let pick, let title, let indented):
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = target
                item.tag = targets.count
                item.indentationLevel = indented ? 1 : 0
                item.state = pick.isSame(as: recorded) ? .on : .off
                targets.append(pick)
                return item
            case .separator:
                return .separator()
            }
        }
        return (items, targets)
    }
}

/// The windows the screen can record, from the window list (front to
/// back, no picture taken): each app's normal windows, skil.li's own left
/// out, none too small to be a call's.
@MainActor
enum ScreenWindows {
    #if SKILLI_SELFTEST
    /// Self-test: skil.li's own test window may be recorded (a window of
    /// its own needs no Screen Recording).
    static var includesOwn = false
    #endif

    static func list() -> [ScreenWindow] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return windows.compactMap(window(from:))
    }

    static func window(_ id: CGWindowID) -> ScreenWindow? {
        (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first.flatMap(window(from:))
    }

    /// Where window `id` is, in the window list's coordinates.
    static func bounds(_ id: CGWindowID) -> CGRect? {
        ((CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first?[kCGWindowBounds as String] as? NSDictionary)
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    }

    private static func window(from info: [String: Any]) -> ScreenWindow? {
        guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
              bounds.width >= 160, bounds.height >= 100, ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05
        else { return nil }
        #if SKILLI_SELFTEST
        if pid == getpid(), !includesOwn { return nil }
        #else
        if pid == getpid() { return nil }
        #endif
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? owner
        guard !app.isEmpty else { return nil }
        return ScreenWindow(id: id, pid: pid, app: app, title: info[kCGWindowName as String] as? String ?? "")
    }

    /// How window `id` of `pid` looks now: there or closed, on screen or
    /// minimized or hidden, covered whole by normal windows in front of it.
    static func look(_ id: CGWindowID, pid: pid_t) -> PictureWatch.Look {
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]])?
            .first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }
        let onScreen = info.flatMap { ($0[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue } ?? false
        guard let info, onScreen else {
            // Not on screen, or out of the list (a minimized window may
            // leave it): minimized, hidden, elsewhere, or closed.
            let app = NSRunningApplication(processIdentifier: pid)
            guard let app, !app.isTerminated else { return PictureWatch.Look(exists: false) }
            // skil.li's own (the self-test's): asked of AppKit, not of
            // Accessibility, which this same thread would have to answer.
            let minimized = pid == getpid() ? NSApp.windows.contains { $0.windowNumber == Int(id) && $0.isMiniaturized } : hasMinimizedWindow(pid)
            if info == nil, !minimized, !app.isHidden { return PictureWatch.Look(exists: false) }
            return PictureWatch.Look(onScreen: false, minimized: !app.isHidden && minimized, appHidden: app.isHidden)
        }
        let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
        // Normal windows in front of it, drawn opaque (a menu, the Dock, a
        // see-through overlay do not stop a browser painting).
        let above = (CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], id) as? [[String: Any]]) ?? []
        let fronts = above.compactMap { front -> CGRect? in
            guard (front[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((front[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) >= 0.9 else { return nil }
            return (front[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        }
        return PictureWatch.Look(coveredWhole: WindowCover.visibleFraction(of: bounds, under: fronts) < 0.002)
    }

    /// Whether one of `pid`'s windows is minimized (Accessibility: the
    /// window list says only that it is not on screen).
    private static func hasMinimizedWindow(_ pid: pid_t) -> Bool {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        // Once a second on the main thread: an app slow to answer is not
        // waited for.
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        return windows.contains { window in
            var minimized: CFTypeRef?
            return AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success && (minimized as? Bool) == true
        }
    }
}

/// ScreenCaptureKit's pictures of the window, on its own queue: to the
/// file and the slides' reader once recording, the latest kept for the
/// card's picture and for a cut. Only new pictures count (a still window
/// gives none).
final class ScreenSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var writer: PictureTrackWriter?
    private var reader: SlideReader?
    private var latest: CVPixelBuffer?
    private var lastPicture: Double?
    /// The last picture's brightness grid: a picture the same as the one
    /// before is no new picture (Chrome covered whole gives the same one
    /// again and again, Measured).
    private var lastGrid: [UInt8]?
    /// The stream stopped by itself (the window closed, the permission
    /// taken away): on the stream's queue.
    var onStopped: (@Sendable (Error) -> Void)?

    func record(into writer: PictureTrackWriter?, reading reader: SlideReader?) {
        lock.withLock {
            self.writer = writer
            self.reader = reader
        }
    }

    /// The latest picture, and the host time the last new one came.
    var latestPicture: CVPixelBuffer? { lock.withLock { latest } }
    var lastPictureTime: Double? { lock.withLock { lastPicture } }

    func forget() {
        lock.withLock {
            latest = nil
            lastPicture = nil
            lastGrid = nil
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first
        // Only a picture that changed: an idle one repeats the last.
        guard let raw = info?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let time = (info?[.displayTime] as? UInt64).map(HostClock.seconds) ?? CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let picture = Picture(pixels: pixels, time: time)
        let grid = SlideReader.grid(pixels)
        let (writer, reader) = lock.withLock { () -> (PictureTrackWriter?, SlideReader?) in
            latest = pixels
            if lastGrid.map({ PictureChange.changedFraction(grid, $0, threshold: 4) > 0 }) ?? true { lastPicture = time }
            lastGrid = grid
            return (self.writer, self.reader)
        }
        writer?.append(picture)
        reader?.offer(picture)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.actions.error("Recorder: the screen's stream stopped (\(error.localizedDescription, privacy: .public))")
        onStopped?(error)
    }
}

/// The screen, the call's window (docs/meeting-recorder-views.md, phase 3)
/// or a whole screen ("The whole screen"): ScreenCaptureKit on one window,
/// or on a display with skil.li's own windows left out, small while the
/// card shows it, at the file's size once recording. Another pick during
/// the call is recorded in the same file from then on. Once a second
/// while it runs, the window list says whether the window still gives
/// pictures, the displays whether the screen is still there
/// (`PictureWatch`).
@MainActor
final class ScreenTrack {
    enum State: Equatable {
        case off
        /// Screen Recording not given (or not applied yet: macOS applies
        /// it once skil.li reopens).
        case denied
        case on(ScreenTarget)
        /// The stream could not start, and why.
        case failed(String)
    }

    /// The file's largest width, and pictures a second.
    static let widest = 1920
    static let perSecond = 15
    /// While only the card shows it: small, four a second.
    private static let cardWidth = 184

    private(set) var state: State = .off
    let sink = ScreenSink()
    private var stream: SCStream?
    /// The window's or the screen's filter, as the stream started: a
    /// picture of it at the file's size on demand.
    private var filter: SCContentFilter?
    /// The file's size, set by the first window recorded.
    private(set) var fileSize: (width: Int, height: Int)?
    /// The window's or the screen's own size in pixels, as the stream
    /// started.
    private var windowPixels: (width: Int, height: Int)?
    private var recording = false
    /// The pictures show the pointer: the whole screen's.
    private var pointer = false
    private var watch = PictureWatch()
    private var watchTimer: Timer?
    /// Each start and stop: a start overtaken while it awaited gives up.
    private var generation = 0
    private var lastSeen: Double?
    private var lastLook: PictureWatch.Look?
    /// The state or the problem changed: the card, the menu bar.
    var onChange: (() -> Void)?

    /// The window or the screen recorded; nil: off, or not recorded.
    var target: ScreenTarget? {
        if case .on(let target) = state { return target }
        return nil
    }

    var window: ScreenWindow? {
        if case .window(let window)? = target { return window }
        return nil
    }

    /// Why the window or the screen gives no picture now; nil while it does.
    var problem: PictureWatch.Problem? { target == nil ? nil : watch.problem }

    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    #if SKILLI_SELFTEST
    /// Self-test: skil.li's own windows recorded with the whole screen
    /// all the same (its known picture), every other one of its own left
    /// out as for anyone.
    static var alsoRecorded: Set<CGWindowID> = []
    #endif

    /// The card's line each time the whole screen is the pick.
    static let wholeScreenNote = "The whole screen is recorded: notifications and other apps on it too. skil.li's own windows are left out."

    /// The whole screen when macOS gives skil.li no display: Screen
    /// Recording given, macOS's second question ("bypass the private
    /// window picker") not.
    static let noDisplays = "macOS doesn't let skil.li record the whole screen"

    /// Starts `target`'s pictures (another one before: stopped). Screen
    /// Recording never asked: macOS asks now.
    func start(_ target: ScreenTarget) async {
        generation += 1
        let mine = generation
        stopStream()
        // skil.li's own window needs no Screen Recording (the self-test's).
        let own = if case .window(let window) = target { Self.ownWindow(window) } else { false }
        guard own || Self.isAllowed || CGRequestScreenCaptureAccess() else {
            state = .denied
            onChange?()
            return
        }
        do {
            let filter: SCContentFilter
            switch target {
            case .window(let window):
                let content = own ? try await SCShareableContent.currentProcess
                    : try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard mine == generation else { return }
                guard let found = content.windows.first(where: { $0.windowID == window.id }) else {
                    state = .failed("the window closed")
                    onChange?()
                    return
                }
                filter = SCContentFilter(desktopIndependentWindow: found)
            case .display(let display):
                // Every window known, off screen too: skil.li's own are left
                // out by its app, whenever they show.
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard mine == generation else { return }
                guard let found = content.displays.first(where: { $0.displayID == display.id }) else {
                    state = .failed(content.displays.isEmpty ? Self.noDisplays : "the screen was disconnected")
                    onChange?()
                    return
                }
                let skilli = content.applications.filter { $0.processID == getpid() }
                if skilli.isEmpty { Log.actions.error("Recorder: skil.li is not among the apps to leave out of the whole screen") }
                #if SKILLI_SELFTEST
                let kept = content.windows.filter { Self.alsoRecorded.contains($0.windowID) }
                #else
                let kept: [SCWindow] = []
                #endif
                filter = SCContentFilter(display: found, excludingApplications: skilli, exceptingWindows: kept)
            }
            self.filter = filter
            self.pointer = if case .display = target { true } else { false }
            let scale = CGFloat(filter.pointPixelScale)
            let width = Int(filter.contentRect.width * scale), height = Int(filter.contentRect.height * scale)
            windowPixels = (width, height)
            if fileSize == nil, recording { fileSize = Self.fileSize(width: width, height: height) }
            let stream = SCStream(filter: filter, configuration: configuration(width: width, height: height), delegate: sink)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.nomdelasociete.Skilli.recorder.screen",
                                                                                               qos: .userInitiated))
            sink.onStopped = { [weak self] error in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.stopped(error) } }
            }
            try await stream.startCapture()
            // Stopped, or another window started, while this one started.
            guard mine == generation else {
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            state = .on(target)
            watch = PictureWatch()
            lastSeen = nil
            startWatching()
            switch target {
            case .window(let window): Log.trace("Recorder: the screen records a window of \(window.app)")
            case .display(let display): Log.trace("Recorder: the screen records the whole screen \(display.id) (\(width) × \(height) px)")
            }
        } catch {
            guard mine == generation else { return }
            state = Self.isAllowed ? .failed(error.localizedDescription) : .denied
            Log.actions.error("Recorder: the screen did not start (\(error.localizedDescription, privacy: .public))")
        }
        onChange?()
    }

    /// The pictures stop, the window let go.
    func stop() {
        generation += 1
        stopStream()
        state = .off
        onChange?()
    }

    /// Recording from now: the pictures at the file's size (the window's,
    /// 1920 wide at most), to `writer` and `reader`.
    func record(into writer: PictureTrackWriter, reading reader: SlideReader?) async {
        recording = true
        if fileSize == nil { fileSize = (writer.width, writer.height) }
        // At the file's size first: the card's small pictures are neither
        // written nor read.
        if let stream { try? await stream.updateConfiguration(configuration(width: writer.width, height: writer.height)) }
        guard recording else { return }
        sink.record(into: writer, reading: reader)
    }

    /// The file's size for a window of `width` × `height` pixels.
    static func fileSize(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (1280, 800) }
        let scale = min(1, Double(widest) / Double(width))
        return (Int(Double(width) * scale) / 2 * 2, Int(Double(height) * scale) / 2 * 2)
    }

    /// The window or the screen now at the file's size, at once (a still
    /// window gives the stream no new picture after its size changes: the
    /// file's first one would be the card's small one, blurred).
    func fullPicture() async -> CVPixelBuffer? {
        guard let filter, target != nil else { return nil }
        let size = plannedSize
        let configuration = configuration(width: size.width, height: size.height)
        configuration.width = size.width
        configuration.height = size.height
        guard let sample = try? await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: configuration) else { return nil }
        return CMSampleBufferGetImageBuffer(sample)
    }

    /// The size the file has, or will have if the window on now starts it.
    var plannedSize: (width: Int, height: Int) {
        fileSize ?? windowPixels.map { Self.fileSize(width: $0.width, height: $0.height) } ?? (1280, 800)
    }

    /// The recording ended: nothing written any more, the sizes forgotten.
    func stopRecording() {
        recording = false
        sink.record(into: nil, reading: nil)
        fileSize = nil
    }

    private func configuration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let size: (width: Int, height: Int)
        if recording {
            size = fileSize ?? Self.fileSize(width: width, height: height)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.perSecond))
        } else {
            let ratio = width > 0 ? Double(height) / Double(width) : 0.625
            size = (Self.cardWidth, max(2, Int(Double(Self.cardWidth) * ratio) / 2 * 2))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 4)
        }
        configuration.width = size.width
        configuration.height = size.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        // The whole screen with the pointer (a demo is followed by it), a
        // window without.
        configuration.showsCursor = pointer
        configuration.capturesAudio = false
        configuration.queueDepth = 6
        configuration.backgroundColor = .black
        return configuration
    }

    private func stopStream() {
        watchTimer?.invalidate()
        watchTimer = nil
        if let stream {
            Task { try? await stream.stopCapture() }
        }
        stream = nil
        sink.forget()
        watch = PictureWatch()
    }

    private func stopped(_ error: Error) {
        guard stream != nil else { return }
        stream = nil
        // The window or the screen gone: the watch says so; anything else,
        // as a failure.
        switch target {
        case .window(let window)? where ScreenWindows.window(window.id) == nil: watch.closed()
        case .display(let display)? where !ScreenDisplays.isConnected(display.id): watch.closed()
        default: state = .failed(error.localizedDescription)
        }
        onChange?()
    }

    /// Once a second: the window as the window list says it.
    private func startWatching() {
        watchTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickWatch() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func tickWatch() {
        guard let target else { return }
        let before = watch.problem
        let seen = sink.lastPictureTime
        if let seen, seen != lastSeen {
            lastSeen = seen
            watch.pictured()
        }
        let look: PictureWatch.Look
        switch target {
        case .window(let window):
            look = ScreenWindows.look(window.id, pid: window.pid)
            if look != lastLook {
                Log.trace("Recorder: the screen's window: \(look.exists ? look.onScreen ? look.coveredWhole ? "covered whole" : "in sight" : "not on screen" : "gone")")
            }
        case .display(let display):
            // A screen never minimizes, hides or is covered: it is there or gone.
            look = PictureWatch.Look(exists: ScreenDisplays.isConnected(display.id))
            if look != lastLook { Log.trace("Recorder: the whole screen \(look.exists ? "is there" : "was disconnected")") }
        }
        lastLook = look
        watch.update(look, lastPicture: seen, now: HostClock.now)
        if watch.problem != before {
            Log.trace("Recorder: the screen \(watch.problem.map { "gives no picture (\($0.rawValue))" } ?? "gives pictures again")")
            onChange?()
        }
    }

    private static func ownWindow(_ window: ScreenWindow) -> Bool {
        window.pid == getpid()
    }

    #if SKILLI_SELFTEST
    /// Self-test: how the window looked at its last check.
    var watchedProblem: PictureWatch.Problem? { watch.problem }
    #endif
}
