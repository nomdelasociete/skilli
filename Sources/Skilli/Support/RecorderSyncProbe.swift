// The meeting recorder's sync measurement (docs/meeting-recorder.md,
// "Measured"): a throwaway probe, compiled only with SKILLI_SELFTEST.
#if SKILLI_SELFTEST
import AppKit
import AVFoundation
import CoreAudio
import CoreMedia
import ScreenCaptureKit

/// `recorderprobe sync`: every 10 s this probe's window flashes white and
/// `afplay` plays a click at the same moment. The window goes to
/// `screen.mp4` (ScreenCaptureKit, each frame at its own time, pauses taken
/// out), the Mac's sound to `them.wav` (a process tap on Core Audio's
/// real-time thread, each sample at its place by the device's sample time,
/// as an audio file is written), the microphone's clock is followed when
/// it is allowed. At the end, where each flash and click landed in the
/// files: if the sound's clock and the screen's drift apart, the offset
/// grows. `queue` as last argument: the tap's IO on a dispatch queue
/// instead, as first measured (it fell behind).
@MainActor
final class RecorderSyncProbe {
    let directory: URL
    let seconds: Double
    let pauseEvery: Double
    let pauseFor: Double
    static let every = 10.0

    private let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
    private let counter = NSTextField(labelWithString: "0")
    /// The microphone's engine stopped by a change of the audio setup and
    /// started again.
    private var micRestarts = 0

    let realtime: Bool

    init(directory: URL, seconds: Double, pauseEvery: Double, pauseFor: Double, realtime: Bool = true) {
        self.directory = directory
        self.seconds = seconds
        self.pauseEvery = pauseEvery
        self.pauseFor = pauseFor
        self.realtime = realtime
    }

    /// Paused at host time `t` (seconds since the start)?
    nonisolated static func paused(_ t: Double, every: Double, for length: Double) -> Bool {
        guard every > 0, length > 0, t > every else { return false }
        return t.truncatingRemainder(dividingBy: every + length) >= every
    }

    /// Writes the screen's frames, retimed: the pauses taken out.
    final class VideoSink: NSObject, SCStreamOutput, @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let start: Double
        let pauseEvery: Double
        let pauseFor: Double
        private let lock = NSLock()
        private var began = false
        private(set) var frames = 0
        private(set) var dropped = 0

        init(url: URL, start: Double, pauseEvery: Double, pauseFor: Double) throws {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 480,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            writer.startWriting()
            self.start = start
            self.pauseEvery = pauseEvery
            self.pauseFor = pauseFor
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let t = pts - start
            if RecorderSyncProbe.paused(t, every: pauseEvery, for: pauseFor) { return }
            // The file's time: the time since the start, less the pauses before.
            let cycles = pauseEvery > 0 && pauseFor > 0 && t > pauseEvery ? floor(t / (pauseEvery + pauseFor)) : 0
            let fileTime = CMTime(seconds: t - cycles * pauseFor, preferredTimescale: 90000)
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: fileTime, decodeTimeStamp: .invalid)
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sampleBuffer, sampleTimingEntryCount: 1,
                                                  sampleTimingArray: &timing, sampleBufferOut: &copy)
            lock.lock()
            defer { lock.unlock() }
            guard let copy else { return }
            if !began {
                writer.startSession(atSourceTime: .zero)
                began = true
            }
            if input.isReadyForMoreMediaData {
                input.append(copy)
                frames += 1
            } else {
                dropped += 1
            }
        }
    }

    /// The microphone's clock: (sample time, host time) per buffer.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var pairs: [(Double, UInt64)] = []
        func add(_ sample: Double, _ host: UInt64) {
            lock.lock()
            pairs.append((sample, host))
            lock.unlock()
        }
        var all: [(Double, UInt64)] {
            lock.lock()
            defer { lock.unlock() }
            return pairs
        }
    }

    nonisolated static func micTap(_ clock: Clock) -> AVAudioNodeTapBlock {
        { _, time in clock.add(Double(time.sampleTime), time.hostTime) }
    }

    nonisolated static func hostSeconds(_ host: UInt64) -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(host) * Double(info.numer) / Double(info.denom) / 1e9
    }

    func run(into report: inout [String: Any]) async throws {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        report["privacy"] = RecorderProbe.privacy()
        // What a recording would hold: no App Nap, no idle sleep.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                                                             reason: "recorder sync probe")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        // The window: black, a counter that changes every frame, white at
        // each flash. Behind other windows (it is captured all the same).
        counter.font = .monospacedDigitSystemFont(ofSize: 40, weight: .bold)
        counter.textColor = .gray
        counter.frame = NSRect(x: 20, y: 90, width: 280, height: 60)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView?.addSubview(counter)
        window.orderBack(nil)
        // An hour in the background: no Dock icon, the app in front stays.
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()

        // The click: 10 ms of 2 kHz, played by `afplay` (another process,
        // its own audio setup).
        let click = directory.appendingPathComponent("click.wav")
        RecorderProbe.writeWAV((0..<480).map { 0.3 * sin(Float($0) * 2 * .pi * 2000 / 48000) }, rate: 48000, to: click)

        // The microphone's clock, when it is allowed (never asked here).
        let mic = Clock()
        var micEngine: AVAudioEngine?
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            let e = AVAudioEngine()
            e.inputNode.installTap(onBus: 0, bufferSize: 4096, format: e.inputNode.outputFormat(forBus: 0), block: Self.micTap(mic))
            try? e.start()
            micEngine = e
            // A change of the audio setup stops the engine: started again.
            NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { _ in
                MainActor.assumeIsolated {
                    self.micRestarts += 1
                    try? e.start()
                }
            }
            report["microphone"] = ["rate": e.inputNode.outputFormat(forBus: 0).sampleRate]
        } else {
            report["microphone"] = "not allowed for skil.li on this Mac: its clock not measured"
        }

        // The Mac's sound.
        let capture = RecorderProbe.Capture(reserve: Int(48000 * (seconds + 60)))
        var tapReport: [String: Any] = [:]
        let tap = try RecorderProbe.startTap("everything", capture: capture, realtime: realtime, report: &tapReport)
        report["tap"] = tapReport

        // The screen.
        let start = Self.hostSeconds(mach_absolute_time())
        let sink = try VideoSink(url: directory.appendingPathComponent("screen.mp4"), start: start, pauseEvery: pauseEvery, pauseFor: pauseFor)
        let content = try await SCShareableContent.currentProcess
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw NSError(domain: "probe window not shareable", code: 1)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = 640
        configuration.height = 480
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "recorder-probe.video"))
        try await stream.startCapture()

        // Flash and click every 10 s, the counter every frame.
        var events: [Double] = []
        var frame = 0
        var next = 2.0
        while true {
            let now = Self.hostSeconds(mach_absolute_time()) - start
            if now >= seconds { break }
            frame += 1
            counter.stringValue = "\(frame)"
            if now >= next {
                let host = mach_absolute_time()
                window.contentView?.layer?.backgroundColor = NSColor.white.cgColor
                let play = Process()
                play.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                play.arguments = [click.path]
                try? play.run()
                if !Self.paused(now, every: pauseEvery, for: pauseFor) { events.append(Self.hostSeconds(host) - start) }
                next += Self.every
                try await Task.sleep(for: .milliseconds(150))
                window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
            }
            try await Task.sleep(for: .milliseconds(33))
        }
        try await stream.stopCapture()
        RecorderProbe.stopTap(tap)
        micEngine?.stop()
        sink.input.markAsFinished()
        await sink.writer.finishWriting()

        // The tap's samples, the pauses taken out, as an audio file.
        let (samples, clock, _) = capture.snapshot()
        let rate = tap.rate
        var kept: [Float] = []
        kept.reserveCapacity(samples.count)
        var offset = 0
        for (index, pair) in clock.enumerated() {
            let end = index + 1 < clock.count ? Int(clock[index + 1].0 - clock[0].0) : samples.count
            let length = max(0, min(samples.count, end) - offset)
            let t = Self.hostSeconds(pair.1) - start
            if !Self.paused(t, every: pauseEvery, for: pauseFor) {
                kept.append(contentsOf: samples[offset..<offset + length])
            }
            offset += length
        }
        RecorderProbe.writeWAV(kept, rate: rate, to: directory.appendingPathComponent("them.wav"))

        report["events"] = events.count
        report["frames"] = sink.frames
        report["framesDropped"] = sink.dropped
        report["tapClock"] = Self.drift(clock, rate: rate)
        report["tapCyclesMissed"] = ["gaps": capture.gaps, "seconds": Double(capture.missing) / rate, "realtime": realtime]
        report["micRestarts"] = micRestarts
        report["micClock"] = Self.drift(mic.all, rate: micEngine?.inputNode.outputFormat(forBus: 0).sampleRate ?? 0)
        report["clicks"] = Self.clicks(kept, rate: rate)
        report["flashes"] = await Self.flashes(directory.appendingPathComponent("screen.mp4"))
    }

    /// The device's real rate against the host clock: how far a file
    /// written sample after sample is from the wall clock at the end.
    nonisolated static func drift(_ pairs: [(Double, UInt64)], rate: Double) -> [String: Any] {
        guard pairs.count > 2, rate > 0, let first = pairs.first, let last = pairs.last else { return ["buffers": pairs.count] }
        let samples = last.0 - first.0
        let host = hostSeconds(last.1) - hostSeconds(first.1)
        let measured = samples / host
        // Gaps: buffers whose sample time jumps more than one buffer.
        var gaps = 0
        for i in 1..<pairs.count where pairs[i].0 - pairs[i - 1].0 > 4 * (pairs[1].0 - pairs[0].0) { gaps += 1 }
        return ["nominalRate": rate, "measuredRate": measured, "ppm": (measured / rate - 1) * 1e6,
                "msOffAfterAnHour": (measured / rate - 1) * 3_600_000, "seconds": host, "gaps": gaps, "buffers": pairs.count]
    }

    /// Times (s) of the clicks in a track: onsets over -40 dBFS, 5 s apart at least.
    nonisolated static func clicks(_ samples: [Float], rate: Double) -> [Double] {
        var out: [Double] = []
        var last = -10.0
        let threshold: Float = 0.01
        for (i, s) in samples.enumerated() where abs(s) > threshold {
            let t = Double(i) / rate
            if t - last > 5 {
                out.append((t * 1000).rounded() / 1000)
                last = t
            }
        }
        return out
    }

    /// Times (s) of the white frames' starts in the video.
    nonisolated static func flashes(_ url: URL) async -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        var out: [Double] = []
        var wasWhite = false
        while let buffer = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(pixels)
            // The picture's mean brightness (green, every 8th pixel): the
            // window black but for its counter, or white. Not one pixel:
            // the window's place in the picture changes with the display's
            // scale (measured: halfway through an hour).
            let height = CVPixelBufferGetHeight(pixels), width = CVPixelBufferGetWidth(pixels)
            var sum = 0, count = 0
            for y in stride(from: 0, to: height, by: 8) {
                for x in stride(from: 0, to: width, by: 8) {
                    sum += Int(base[y * row + x * 4 + 1])
                    count += 1
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
            let white = sum / max(1, count) > 40
            if white && !wasWhite {
                out.append((CMSampleBufferGetPresentationTimeStamp(buffer).seconds * 1000).rounded() / 1000)
            }
            wasWhite = white
        }
        return out
    }
}

#endif
