import AppKit
import ScreenCaptureKit
import Vision

/// The words a window shows and where, read on screen: for apps that tell
/// Accessibility little (a canvas, some Electron apps). Needs Screen
/// Recording. The words are read on this Mac; the capture itself leaves it
/// only as "do it here"'s one picture of that window, to TypeSafe Jev,
/// when the words say too little (`WindowPicture`).
enum ScreenSight {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// One window as it is on screen: never the whole screen, never the
    /// pointer. A CF image, handed between tasks as is.
    struct Capture: @unchecked Sendable {
        let image: CGImage
        /// Where the window is on screen, in points, top-left origin.
        let frame: CGRect
    }

    /// `pid`'s window at `frame` (top-left origin, as Accessibility gives
    /// it), else its largest, at the screen's scale.
    static func capture(pid: pid_t, window frame: CGRect) async -> Capture? {
        guard isAllowed else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
            guard let window = windows.min(by: { distance($0.frame, frame) < distance($1.frame, frame) }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return Capture(image: image, frame: window.frame)
        } catch {
            Log.actions.error("Capturing the window failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Each line of words in `pid`'s window at `frame`, with its frame on
    /// screen; and the capture they were read in.
    static func lines(pid: pid_t, window frame: CGRect) async -> (lines: [(text: String, frame: CGRect)], capture: Capture?) {
        guard let capture = await capture(pid: pid, window: frame) else { return ([], nil) }
        return (await lines(in: capture), capture)
    }

    static func lines(in capture: Capture) async -> [(text: String, frame: CGRect)] {
        let image = capture.image, window = capture.frame
        let scale = window.width > 0 ? CGFloat(image.width) / window.width : 1
        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = false
            let size = CGSize(width: image.width, height: image.height)
            return try await request.perform(on: image).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                let box = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
                return (text, CGRect(x: window.minX + box.minX / scale, y: window.minY + box.minY / scale,
                                     width: box.width / scale, height: box.height / scale))
            }
        } catch {
            Log.actions.error("Reading the screen failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
