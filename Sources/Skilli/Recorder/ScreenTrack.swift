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
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id else {
            return PictureWatch.Look(exists: false)
        }
        let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        guard onScreen else {
            let hidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
            return PictureWatch.Look(onScreen: false, minimized: !hidden && hasMinimizedWindow(pid), appHidden: hidden)
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
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
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
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first
        // Only a picture that changed: an idle one repeats the last.
        guard let raw = info?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let time = (info?[.displayTime] as? UInt64).map(HostClock.seconds) ?? CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let picture = Picture(pixels: pixels, time: time)
        let (writer, reader) = lock.withLock { () -> (PictureTrackWriter?, SlideReader?) in
            latest = pixels
            lastPicture = time
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

/// The screen, the call's window (docs/meeting-recorder-views.md, phase 3):
/// ScreenCaptureKit on one window, small while the card shows it, at the
/// file's size once recording. Another window picked during the call is
/// recorded in the same file from then on. Once a second while it runs,
/// the window list says whether the window still gives pictures
/// (`PictureWatch`).
@MainActor
final class ScreenTrack {
    enum State: Equatable {
        case off
        /// Screen Recording not given (or not applied yet: macOS applies
        /// it once skil.li reopens).
        case denied
        case on(ScreenWindow)
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
    /// The file's size, set by the first window recorded.
    private(set) var fileSize: (width: Int, height: Int)?
    /// The window's own size in pixels, as the stream started.
    private var windowPixels: (width: Int, height: Int)?
    private var recording = false
    private var watch = PictureWatch()
    private var watchTimer: Timer?
    private var lastSeen: Double?
    /// The state or the problem changed: the card, the menu bar.
    var onChange: (() -> Void)?

    var window: ScreenWindow? {
        if case .on(let window) = state { return window }
        return nil
    }

    /// Why the window gives no picture now; nil while it does.
    var problem: PictureWatch.Problem? { window == nil ? nil : watch.problem }

    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Starts `window`'s pictures (another one before: stopped). Screen
    /// Recording never asked: macOS asks now.
    func start(_ window: ScreenWindow) async {
        stopStream()
        guard Self.isAllowed || CGRequestScreenCaptureAccess() || Self.ownWindow(window) else {
            state = .denied
            onChange?()
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let target = content.windows.first(where: { $0.windowID == window.id }) else {
                state = .failed("the window closed")
                onChange?()
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: target)
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
            self.stream = stream
            state = .on(window)
            watch = PictureWatch()
            lastSeen = nil
            startWatching()
            Log.trace("Recorder: the screen records a window of \(window.app)")
        } catch {
            state = Self.isAllowed ? .failed(error.localizedDescription) : .denied
            Log.actions.error("Recorder: the screen did not start (\(error.localizedDescription, privacy: .public))")
        }
        onChange?()
    }

    /// The pictures stop, the window let go.
    func stop() {
        stopStream()
        state = .off
        onChange?()
    }

    /// Recording from now: the pictures at the file's size (the window's,
    /// 1920 wide at most), to `writer` and `reader`.
    func record(into writer: PictureTrackWriter, reading reader: SlideReader?) async {
        recording = true
        sink.record(into: writer, reading: reader)
        if fileSize == nil { fileSize = (writer.width, writer.height) }
        guard let stream else { return }
        try? await stream.updateConfiguration(configuration(width: writer.width, height: writer.height))
    }

    /// The file's size for a window of `width` × `height` pixels.
    static func fileSize(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (1280, 800) }
        let scale = min(1, Double(widest) / Double(width))
        return (Int(Double(width) * scale) / 2 * 2, Int(Double(height) * scale) / 2 * 2)
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
        configuration.showsCursor = false
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
        // The window gone: the watch says so; anything else, as a failure.
        if let window, ScreenWindows.window(window.id) == nil {
            watch.update(PictureWatch.Look(exists: false), lastPicture: sink.lastPictureTime, now: HostClock.now + PictureWatch.holdFor)
        } else {
            state = .failed(error.localizedDescription)
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
        guard let window else { return }
        let before = watch.problem
        let seen = sink.lastPictureTime
        if let seen, seen != lastSeen {
            lastSeen = seen
            watch.pictured()
        }
        watch.update(ScreenWindows.look(window.id, pid: window.pid), lastPicture: seen, now: HostClock.now)
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
