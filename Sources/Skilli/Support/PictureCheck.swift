// The recorder's phase 3 check (docs/meeting-recorder.md, Phases): a test
// window shows slides with known text at known times and flashes white
// with each beep of the stand-in microphone. Compiled only with
// SKILLI_SELFTEST.
#if SKILLI_SELFTEST
import AppKit
import AVFoundation

/// The test's slides: a dark window, its text large, white for a moment
/// at each flash. Never key (the keys stay in the test window).
@MainActor
final class SlidesWindow {
    let window: NSWindow
    private let text = NSTextField(wrappingLabelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private var flashes = 0

    init(frame: NSRect) {
        window = NSPanel(contentRect: frame, styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Slides"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .normal
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        text.font = .systemFont(ofSize: 42, weight: .semibold)
        text.textColor = .white
        text.frame = NSRect(x: 60, y: 120, width: frame.width - 120, height: frame.height - 220)
        counter.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        counter.textColor = NSColor(white: 0.35, alpha: 1)
        counter.frame = NSRect(x: 60, y: 30, width: 200, height: 20)
        content.addSubview(text)
        content.addSubview(counter)
        window.contentView = content
    }

    func show(_ lines: [String]) {
        text.stringValue = lines.joined(separator: "\n")
    }

    /// A small change in a corner: the window gives a new picture (a
    /// call's video moving), not a slide.
    func tick(_ count: Int) {
        counter.stringValue = "\(count)"
    }

    /// White for `seconds`, then dark again.
    func flash(for seconds: Double = 0.2) {
        flashes += 1
        let flash = flashes
        window.contentView?.layer?.backgroundColor = NSColor.white.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.flashes == flash else { return }
                self.window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
            }
        }
    }
}

enum PictureCheck {
    /// Where each flash starts in a picture file (seconds): the picture's
    /// mean brightness jumping past a third.
    static func flashes(in url: URL) async -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { return [] }
        var found: [Double] = []
        var wasWhite = false
        while let buffer = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            let white = brightness(pixels) > 85
            if white, !wasWhite { found.append(CMSampleBufferGetPresentationTimeStamp(buffer).seconds) }
            wasWhite = white
        }
        return found
    }

    /// The picture's mean brightness (0…255), every eighth pixel.
    static func brightness(_ pixels: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        let row = CVPixelBufferGetBytesPerRow(pixels), height = CVPixelBufferGetHeight(pixels), width = CVPixelBufferGetWidth(pixels)
        var sum = 0, count = 0
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                sum += Int(base[y * row + x * 4 + 1])
                count += 1
            }
        }
        return sum / max(1, count)
    }

    /// Each of `marks` (the sound's beeps) with the first of `seen` (the
    /// pictures' flashes) within `window` seconds after it, less a little
    /// before: the picture's offset from the sound, per beep.
    static func offsets(_ marks: [Double], _ seen: [Double], window: Double = 0.5) -> [Double] {
        marks.compactMap { mark in
            seen.filter { $0 >= mark - 0.1 && $0 <= mark + window }.min().map { $0 - mark }
        }
    }

    /// A length in seconds, a file of any kind.
    static func length(_ url: URL) async -> Double {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return 0 }
        return duration.seconds.isFinite ? duration.seconds : 0
    }
}
#endif
