// Measurements for the meeting recorder (docs/meeting-recorder.md,
// "Measured"): not the recorder, only what it must know before it is
// built. Compiled only with SKILLI_SELFTEST, never in a release.
#if SKILLI_SELFTEST
import AppKit
import AVFoundation
import CoreAudio
import CoreMedia
import ScreenCaptureKit
import Vision

/// `Skilli recorderprobe <what> <out.json> …`, opened through LaunchServices
/// (`open -W -n Skilli.app --args recorderprobe …`) so skil.li, not the
/// shell, is the app macOS asks about:
///
/// - `tap <out.json> <seconds> [global|<bundle id>]`: a Core Audio process
///   tap on every process but this one (or on one app's processes), its
///   level every 100 ms, what macOS's privacy checks answer before and after,
///   and which processes were playing sound meanwhile.
/// - `screenaudio <out.json> <seconds>`: the same sound through
///   ScreenCaptureKit (`capturesAudio`), the other way to hear the Mac.
/// - `window <out.json> <bundle id> <seconds> <front|asis|half|covered|minimized|hidden> [ext:<address part>]`:
///   one app's window through ScreenCaptureKit while it is in front, as it
///   is, half or fully under this probe's window, minimized or hidden;
///   every frame's status and the page's frame count read on it (Vision),
///   to tell a window that keeps painting from one that froze. With `ext:`,
///   halfway, the shell that started the probe brings a tab forward
///   (`<out.json>.go` appears; it acts, then removes it).
/// - `sync <outdir> <seconds> <pause every s> <pause for s>`: the screen (a
///   window that flashes), the Mac's sound (a click at each flash) and the
///   microphone written as the recorder would, with pauses; then where each
///   flash and click landed in the files.
@MainActor
enum RecorderProbe {
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == "recorderprobe", arguments.count >= 4 else { return nil }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let args = Array(arguments.dropFirst(2))
        Task { @MainActor in
            var report: [String: Any] = ["probe": args[0], "arguments": args]
            do {
                switch args[0] {
                case "tap": try await tap(args, into: &report)
                case "screenaudio": try await screenAudio(args, into: &report)
                case "window": try await window(args, into: &report)
                case "sync": try await sync(args, into: &report)
                default: report["error"] = "unknown probe"
                }
            } catch {
                report["error"] = "\(error)"
            }
            let out = URL(fileURLWithPath: args[0] == "sync" ? args[1] + "/sync.json" : args[1])
            // A report that cannot be written is a failed run, whatever the probe found.
            var written = false
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: out)
                written = true
            } catch {
                FileHandle.standardError.write(Data("recorderprobe: report not written to \(out.path): \(error)\n".utf8))
            }
            exit(written && report["error"] == nil ? 0 : 1)
        }
        app.run()
        return 0
    }

    // MARK: - Privacy

    /// What TCC answers for a service, without asking (private TCC call,
    /// the probe only): 0 allowed, 1 denied, 2 not decided yet.
    static func preflight(_ service: String) -> Int {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return -1 }
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        return unsafeBitCast(symbol, to: Preflight.self)(service as CFString, nil)
    }

    static func privacy() -> [String: Int] {
        ["audioCapture": preflight("kTCCServiceAudioCapture"), "screenCapture": preflight("kTCCServiceScreenCapture"),
         "microphone": preflight("kTCCServiceMicrophone"), "camera": preflight("kTCCServiceCamera")]
    }

    // MARK: - Core Audio

    static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        var out = value
        let status = withUnsafeMutablePointer(to: &out) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? out : nil
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Every process Core Audio knows: its bundle id, pid, and whether it is
    /// playing sound now.
    static func audioProcesses() -> [(id: AudioObjectID, bundle: String, pid: Int32, output: Bool)] {
        objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).map { id in
            (id, string(id, kAudioProcessPropertyBundleID) ?? "",
             property(id, kAudioProcessPropertyPID, Int32(0)) ?? 0,
             (property(id, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0)
        }
    }

    static func ownProcessObject() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    /// Samples the IO block hands over, kept off the main actor, each at
    /// its place by the device's sample time: cycles the block missed are
    /// silence of their length, so the track keeps the device's time.
    final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        private(set) var callbacks = 0
        /// Cycles missed, and their frames.
        private(set) var gaps = 0
        private(set) var missing = 0
        /// (sample time, host time) of the first frame of each buffer.
        private var clock: [(Double, UInt64)] = []

        /// `frames`: room made at once, so the real-time thread never
        /// copies a growing array.
        init(reserve frames: Int = 0) {
            samples.reserveCapacity(frames)
            clock.reserveCapacity(frames / 256)
        }

        func append(_ list: UnsafePointer<AudioBufferList>, at time: UnsafePointer<AudioTimeStamp>) {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            guard let first = buffers.first, let data = first.mData else { return }
            let channels = max(1, Int(first.mNumberChannels))
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
            let floats = data.assumingMemoryBound(to: Float.self)
            lock.lock()
            callbacks += 1
            if let start = clock.first?.0 {
                let expected = samples.count, at = Int(time.pointee.mSampleTime - start)
                if at > expected {
                    gaps += 1
                    missing += at - expected
                    samples.append(contentsOf: repeatElement(0, count: at - expected))
                }
            }
            clock.append((time.pointee.mSampleTime, time.pointee.mHostTime))
            samples.reserveCapacity(samples.count + frames)
            for frame in 0..<frames { samples.append(floats[frame * channels]) }
            lock.unlock()
        }

        func snapshot() -> (samples: [Float], clock: [(Double, UInt64)], callbacks: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (samples, clock, callbacks)
        }
    }

    /// Built here, not in an `@MainActor` function: Core Audio calls it on
    /// its own queue.
    nonisolated static func ioBlock(_ capture: Capture) -> AudioDeviceIOBlock {
        { _, input, inputTime, _, _ in capture.append(input, at: inputTime) }
    }

    struct Tap {
        let tap: AudioObjectID
        let aggregate: AudioObjectID
        let proc: AudioDeviceIOProcID
        let rate: Double
    }

    /// `realtime`: the IO block on Core Audio's real-time thread; else on a
    /// dispatch queue, which macOS may let fall behind (App Nap, the
    /// display asleep: measured, cycles missed).
    static func startTap(_ target: String, capture: Capture, realtime: Bool = false, report: inout [String: Any]) throws -> Tap {
        let description: CATapDescription
        if target == "global" {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcessObject().map { [$0] } ?? [])
        } else if target == "everything" {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        } else {
            let ids = audioProcesses().filter { $0.bundle.hasPrefix(target) }.map(\.id)
            report["tappedProcesses"] = ids.count
            description = CATapDescription(stereoMixdownOfProcesses: ids)
        }
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        let created = AudioHardwareCreateProcessTap(description, &tap)
        report["createTapStatus"] = Int(created)
        guard created == noErr else { throw NSError(domain: "AudioHardwareCreateProcessTap", code: Int(created)) }
        let output = property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, AudioObjectID(0)) ?? 0
        let outputUID = string(output, kAudioDevicePropertyDeviceUID) ?? ""
        report["outputDevice"] = string(output, kAudioObjectPropertyName) ?? outputUID
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "skil.li recorder probe",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        let made = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        report["createAggregateStatus"] = Int(made)
        guard made == noErr else { throw NSError(domain: "AudioHardwareCreateAggregateDevice", code: Int(made)) }
        var format = AudioStreamBasicDescription()
        if let f = property(tap, kAudioTapPropertyFormat, format) { format = f }
        report["tapFormat"] = ["rate": format.mSampleRate, "channels": format.mChannelsPerFrame, "bits": format.mBitsPerChannel]
        var proc: AudioDeviceIOProcID?
        let queue = realtime ? nil : DispatchQueue(label: "recorder-probe.tap")
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue, ioBlock(capture))
        report["createIOProcStatus"] = Int(ioStatus)
        guard ioStatus == noErr, let proc else { throw NSError(domain: "AudioDeviceCreateIOProcIDWithBlock", code: Int(ioStatus)) }
        let started = AudioDeviceStart(device, proc)
        report["startStatus"] = Int(started)
        guard started == noErr else { throw NSError(domain: "AudioDeviceStart", code: Int(started)) }
        return Tap(tap: tap, aggregate: device, proc: proc, rate: format.mSampleRate > 0 ? format.mSampleRate : 48000)
    }

    static func stopTap(_ tap: Tap) {
        AudioDeviceStop(tap.aggregate, tap.proc)
        AudioDeviceDestroyIOProcID(tap.aggregate, tap.proc)
        AudioHardwareDestroyAggregateDevice(tap.aggregate)
        AudioHardwareDestroyProcessTap(tap.tap)
    }

    /// dBFS of each 100 ms.
    static func levels(_ samples: [Float], rate: Double) -> [Double] {
        let step = max(1, Int(rate / 10))
        return stride(from: 0, to: samples.count, by: step).map { start in
            let slice = samples[start..<min(samples.count, start + step)]
            let rms = sqrt(slice.reduce(0) { $0 + Double($1 * $1) } / Double(max(1, slice.count)))
            return rms > 0 ? (20 * log10(rms) * 10).rounded() / 10 : -200
        }
    }

    /// Mono samples as a WAV file; one that cannot be made or written
    /// throws, so the run fails (its report says why).
    static func writeWAV(_ samples: [Float], rate: Double, to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            throw NSError(domain: "no audio format at \(rate) Hz", code: 1)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw NSError(domain: "no audio buffer for \(samples.count) samples", code: 2)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    static func tap(_ args: [String], into report: inout [String: Any]) async throws {
        let seconds = Double(args[2]) ?? 10
        let target = args.count > 3 ? args[3] : "global"
        report["privacyBefore"] = privacy()
        let capture = Capture()
        let tap = try startTap(target, capture: capture, report: &report)
        var playing: [String: Int] = [:]
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            for process in audioProcesses() where process.output {
                playing["\(process.bundle.isEmpty ? "pid \(process.pid)" : process.bundle)", default: 0] += 1
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        stopTap(tap)
        let (samples, _, callbacks) = capture.snapshot()
        let db = levels(samples, rate: tap.rate)
        report["privacyAfter"] = privacy()
        report["callbacks"] = callbacks
        report["seconds"] = Double(samples.count) / tap.rate
        report["levels"] = db
        report["loudest"] = db.max() ?? -200
        report["heard"] = db.filter { $0 > -60 }.count
        report["playing"] = playing
        try writeWAV(samples, rate: tap.rate, to: URL(fileURLWithPath: args[1]).deletingPathExtension().appendingPathExtension("wav"))
    }

    // MARK: - ScreenCaptureKit

    final class Frames: NSObject, SCStreamOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [String: Int] = [:]
        private var images: [(Double, CGImage)] = []
        private var audio: [Float] = []
        let started = CACurrentMediaTime()

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            if type == .audio {
                appendAudio(sampleBuffer)
                return
            }
            guard type == .screen,
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return }
            let name = switch status {
            case .complete: "complete"
            case .idle: "idle"
            case .blank: "blank"
            case .suspended: "suspended"
            case .started: "started"
            case .stopped: "stopped"
            @unknown default: "other"
            }
            var image: CGImage?
            if status == .complete, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) {
                image = CIContext().createCGImage(CIImage(cvPixelBuffer: pixels), from: CGRect(x: 0, y: 0,
                    width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels)))
            }
            lock.lock()
            statuses[name, default: 0] += 1
            if let image { images.append((CACurrentMediaTime() - started, image)) }
            lock.unlock()
        }

        private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
            var list = AudioBufferList()
            var block: CMBlockBuffer?
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
                bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                flags: 0, blockBufferOut: &block) == noErr, let data = list.mBuffers.mData else { return }
            let floats = data.assumingMemoryBound(to: Float.self)
            let count = Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
            lock.lock()
            audio.append(contentsOf: UnsafeBufferPointer(start: floats, count: count))
            lock.unlock()
        }

        func snapshot() -> (statuses: [String: Int], images: [(Double, CGImage)], audio: [Float]) {
            lock.lock()
            defer { lock.unlock() }
            return (statuses, images, audio)
        }
    }

    /// The page's words, read on a frame.
    nonisolated static func read(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    static func screenAudio(_ args: [String], into report: inout [String: Any]) async throws {
        let seconds = Double(args[2]) ?? 10
        report["privacyBefore"] = privacy()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw NSError(domain: "no display", code: 1) }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 1
        configuration.width = 64
        configuration.height = 64
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let frames = Frames()
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration, delegate: nil)
        try stream.addStreamOutput(frames, type: .audio, sampleHandlerQueue: DispatchQueue(label: "recorder-probe.audio"))
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        let audio = frames.snapshot().audio
        let db = levels(audio, rate: 48000)
        report["privacyAfter"] = privacy()
        report["seconds"] = Double(audio.count) / 48000
        report["levels"] = db
        report["loudest"] = db.max() ?? -200
        report["heard"] = db.filter { $0 > -60 }.count
    }

    static func window(_ args: [String], into report: inout [String: Any]) async throws {
        let bundle = args[2], seconds = Double(args[3]) ?? 20, mode = args.count > 4 ? args[4] : "covered"
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            throw NSError(domain: "\(bundle) not running", code: 1)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let all = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundle && $0.windowLayer == 0 && $0.frame.width > 300 }
        // The test pages' window when there is one ("Probe clock", "Meeting", "Other").
        let pages = all.filter { title in ["Probe clock", "Meeting", "Other"].contains { (title.title ?? "").contains($0) } }
        let windows = pages.isEmpty ? all : pages
        guard let target = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw NSError(domain: "no window of \(bundle)", code: 2)
        }
        report["window"] = ["title": target.title ?? "", "frame": "\(target.frame)", "onScreen": target.isOnScreen]
        var cover: NSWindow?
        switch mode {
        case "front":
            app.activate()
        case "covered":
            let screen = NSScreen.screens.first { $0.frame.intersects(target.frame) } ?? NSScreen.main!
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.backgroundColor = .systemGray
            window.isOpaque = true
            // Over every normal window, whichever app is active (macOS
            // may refuse this probe the activation).
            window.level = .floating
            window.orderFrontRegardless()
            NSApp.activate()
            cover = window
        case "minimized":
            setMinimized(app.processIdentifier, true)
        case "hidden":
            app.hide()
        case "half":
            // Half the window under another window, the rest in sight.
            let screen = NSScreen.screens.first ?? NSScreen.main!
            // SCWindow frames are top-left based; AppKit's bottom-left.
            let f = target.frame
            let rect = NSRect(x: f.minX, y: screen.frame.maxY - f.maxY, width: f.width / 2, height: f.height)
            let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.backgroundColor = .systemGray
            window.isOpaque = true
            window.level = .floating
            window.orderFrontRegardless()
            cover = window
        default:
            break
        }
        try await Task.sleep(for: .seconds(1.5))
        report["frontmost"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let configuration = SCStreamConfiguration()
        let filter = SCContentFilter(desktopIndependentWindow: target)
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale) / 2)
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale) / 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 4)
        configuration.showsCursor = false
        let frames = Frames()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "recorder-probe.screen"))
        try await stream.startCapture()
        if args.count > 5 {
            // Halfway, the meeting's tab brought forward in its window, as
            // `BrowserTabReuse` scripts it ("tab:<part of its address>"),
            // the browser left behind; "tabfront:…" also brings the window
            // and the browser forward, as `BrowserTabReuse` does.
            try await Task.sleep(for: .seconds(seconds / 2))
            let parts = args[5].split(separator: ":", maxSplits: 1).map(String.init)
            let kind = parts[0], part = parts.count > 1 ? parts[1] : ""
            let state = await Task.detached { AutomationAccess.state(of: bundle) }.value
            report["automation"] = "\(state)"
            if kind == "ext" {
                // Done by the shell that started the probe (its own
                // Automation right): `<out>.go` appears, it acts, removes it.
                let go = URL(fileURLWithPath: args[1] + ".go")
                report["actionAt"] = CACurrentMediaTime() - frames.started
                FileManager.default.createFile(atPath: go.path, contents: Data(part.utf8))
                for _ in 0..<50 where FileManager.default.fileExists(atPath: go.path) {
                    try await Task.sleep(for: .milliseconds(20))
                }
                report["actionDoneAt"] = CACurrentMediaTime() - frames.started
                try await Task.sleep(for: .milliseconds(500))
                report["frontmostAfter"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            } else if state == .granted {
                let front = kind == "tabfront" ? "set index of w to 1\nactivate" : ""
                let source = """
                tell application id "\(bundle)"
                    set w to window 1
                    repeat with i from 1 to count of tabs of w
                        if URL of tab i of w contains "\(part)" then set active tab index of w to i
                    end repeat
                    \(front)
                end tell
                return "ok"
                """
                report["actionAt"] = CACurrentMediaTime() - frames.started
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                report["actionResult"] = error.map { "\($0[NSAppleScript.errorNumber] ?? "error")" } ?? result?.stringValue ?? ""
            }
            try await Task.sleep(for: .seconds(seconds / 2))
        } else {
            try await Task.sleep(for: .seconds(seconds))
        }
        try await stream.stopCapture()
        cover?.orderOut(nil)
        if mode == "minimized" { setMinimized(app.processIdentifier, false) }
        if mode == "hidden" { app.unhide() }
        let (statuses, images) = { let s = frames.snapshot(); return (s.statuses, s.images) }()
        report["statuses"] = statuses
        // What the page said on each picture (its clock and frame count).
        let readings = await Task.detached { images.map { (t: $0.0, text: read($0.1)) } }.value
        report["readings"] = readings.map { ["t": ($0.t * 100).rounded() / 100, "text": $0.text] }
        let base = URL(fileURLWithPath: args[1]).deletingPathExtension()
        for (index, image) in [images.first, images.last].compactMap({ $0 }).enumerated() {
            if let png = NSBitmapImageRep(cgImage: image.1).representation(using: .png, properties: [:]) {
                try? png.write(to: base.appendingPathExtension(index == 0 ? "first.png" : "last.png"))
            }
        }
    }

    static func setMinimized(_ pid: pid_t, _ minimized: Bool) {
        let app = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return }
        for window in list {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized as CFBoolean)
        }
    }

    // MARK: - Sync

    static func sync(_ args: [String], into report: inout [String: Any]) async throws {
        try await RecorderSyncProbe(directory: URL(fileURLWithPath: args[1]), seconds: Double(args[2]) ?? 60,
                                    pauseEvery: Double(args[3]) ?? 0, pauseFor: Double(args[4]) ?? 0,
                                    realtime: args.last != "queue").run(into: &report)
    }
}
#endif
