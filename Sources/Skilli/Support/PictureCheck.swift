// The recorder's phase 3 check (docs/meeting-recorder.md, Phases): a test
// window shows slides with known text at known times and flashes white
// with each beep of the stand-in microphone. Compiled only with
// SKILLI_SELFTEST.
#if SKILLI_SELFTEST
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// The test's slides: a dark window, its text large; at each flash a small
/// square in its bottom left corner white for a moment (a corner's clock
/// to the slides' reader, under its change: the slides are timed by
/// their own change, the flashes measure the step with the sound). A
/// normal window (another covers it, it minimizes), never made key (the
/// keys stay in the test window).
@MainActor
final class SlidesWindow {
    let window: NSWindow
    private let text = NSTextField(wrappingLabelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let corner = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
    private var flashes = 0

    init(frame: NSRect) {
        window = NSWindow(contentRect: frame, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Slides"
        window.isReleasedWhenClosed = false
        window.level = .normal
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        text.font = .systemFont(ofSize: 42, weight: .semibold)
        text.textColor = .white
        text.frame = NSRect(x: 60, y: 120, width: frame.width - 120, height: frame.height - 220)
        counter.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        counter.textColor = NSColor(white: 0.35, alpha: 1)
        counter.frame = NSRect(x: 60, y: 46, width: 200, height: 20)
        corner.wantsLayer = true
        corner.layer?.backgroundColor = NSColor.black.cgColor
        content.addSubview(text)
        content.addSubview(counter)
        content.addSubview(corner)
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

    /// The corner white for `seconds`, then dark again.
    func flash(for seconds: Double = 0.2) {
        flashes += 1
        let flash = flashes
        corner.layer?.backgroundColor = NSColor.white.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.flashes == flash else { return }
                self.corner.layer?.backgroundColor = NSColor.black.cgColor
            }
        }
    }

    /// Where the flashing corner is in a picture of the window: its share
    /// from the left, and from the top down to the bottom.
    static let flashRegion = (right: 0.025, top: 0.96)

    /// Where the flashing corner is on screen (AppKit's coordinates): its
    /// place in a picture of the whole screen.
    var flashFrame: NSRect { window.convertToScreen(corner.convert(corner.bounds, to: nil)) }
}

enum PictureCheck {
    /// Where each flash starts in a picture file (seconds): the mean
    /// brightness of the picture (or of its bottom left `corner`: shares
    /// of the width from the left, of the height from the top) jumping
    /// past a third.
    static func flashes(in url: URL, corner: (right: Double, top: Double)? = nil) async -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { return [] }
        var found: [Double] = []
        var wasWhite = false
        while let buffer = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            let white = brightness(pixels, corner: corner) > 85
            if white, !wasWhite { found.append(CMSampleBufferGetPresentationTimeStamp(buffer).seconds) }
            wasWhite = white
        }
        return found
    }

    /// The picture's mean brightness (0…255), every eighth pixel (in its
    /// bottom left `corner` only, every second one).
    static func brightness(_ pixels: CVPixelBuffer, corner: (right: Double, top: Double)? = nil) -> Int {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        let row = CVPixelBufferGetBytesPerRow(pixels), height = CVPixelBufferGetHeight(pixels), width = CVPixelBufferGetWidth(pixels)
        let xs = corner.map { 0..<max(1, Int(Double(width) * $0.right)) } ?? 0..<width
        let ys = corner.map { min(height - 1, Int(Double(height) * $0.top))..<height } ?? 0..<height
        let step = corner == nil ? 8 : 2
        var sum = 0, count = 0
        for y in stride(from: ys.lowerBound, to: ys.upperBound, by: step) {
            for x in stride(from: xs.lowerBound, to: xs.upperBound, by: step) {
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

    /// When a picture file's first picture shows, as it plays (seconds;
    /// nil: none): where its first segment with pictures starts. A file
    /// begun later in a recording starts with an empty segment, and a
    /// reader's sample times are the media's own, not the playing time.
    static func firstPicture(in url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let segments = try? await track.load(.segments) else { return nil }
        return segments.first { !$0.isEmpty }?.timeMapping.target.start.seconds
    }

    /// Where `frame` (AppKit's coordinates) is in a picture of the screen
    /// `display` (its frame): shares of the picture's width and height
    /// from its top left, a quarter of its size in from each edge.
    static func region(of frame: NSRect, in display: NSRect) -> CGRect {
        let inner = frame.insetBy(dx: frame.width / 4, dy: frame.height / 4)
        return CGRect(x: (inner.minX - display.minX) / display.width, y: (display.maxY - inner.maxY) / display.height,
                      width: inner.width / display.width, height: inner.height / display.height)
    }

    /// What `each` reads of every picture of a file (with its time), in
    /// order; the pictures' size (nil: none read).
    static func pictures<T: Sendable>(in url: URL, _ each: @Sendable (CVPixelBuffer, Double) -> T) async -> (size: CGSize?, read: [T]) {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return (nil, []) }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { return (nil, []) }
        var size: CGSize?
        var read: [T] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
            read.append(each(pixels, CMSampleBufferGetPresentationTimeStamp(buffer).seconds))
        }
        return (size, read)
    }

    /// The mean color of `region` (shares from the top left) in a
    /// picture: red, green, blue, 0…255.
    static func color(_ pixels: CVPixelBuffer, in region: CGRect) -> (red: Int, green: Int, blue: Int) {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return (0, 0, 0) }
        let row = CVPixelBufferGetBytesPerRow(pixels), height = CVPixelBufferGetHeight(pixels), width = CVPixelBufferGetWidth(pixels)
        let xs = max(0, Int(Double(width) * region.minX))..<min(width, max(Int(Double(width) * region.minX) + 1, Int(Double(width) * region.maxX)))
        let ys = max(0, Int(Double(height) * region.minY))..<min(height, max(Int(Double(height) * region.minY) + 1, Int(Double(height) * region.maxY)))
        var sum = (0, 0, 0), count = 0
        for y in ys {
            for x in xs {
                let pixel = base + y * row + x * 4
                sum = (sum.0 + Int(pixel[2]), sum.1 + Int(pixel[1]), sum.2 + Int(pixel[0]))
                count += 1
            }
        }
        let n = max(1, count)
        return (sum.0 / n, sum.1 / n, sum.2 / n)
    }

    /// The share of a picture's pixels (every eighth one, each way) whose
    /// color `matches` (red, green, blue, 0…255).
    static func share(_ pixels: CVPixelBuffer, matching matches: (Int, Int, Int) -> Bool) -> Double {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        let row = CVPixelBufferGetBytesPerRow(pixels), height = CVPixelBufferGetHeight(pixels), width = CVPixelBufferGetWidth(pixels)
        var hits = 0, count = 0
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                let pixel = base + y * row + x * 4
                if matches(Int(pixel[2]), Int(pixel[1]), Int(pixel[0])) { hits += 1 }
                count += 1
            }
        }
        return Double(hits) / Double(max(1, count))
    }

    /// A picture of one color, `width` × `height` pixels, as a PNG file.
    static func writeSolid(_ url: URL, width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// A length in seconds, a file of any kind.
    static func length(_ url: URL) async -> Double {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return 0 }
        return duration.seconds.isFinite ? duration.seconds : 0
    }
}
#endif
