import AVFoundation
import CoreMedia
import Foundation
import SkilliCore

/// The camera's pictures on their own queue: each at its host time (the
/// capture session's clock converted to the host's, so it stays in step
/// with the sound), to the file once recording, the latest kept for the
/// card's picture and for a cut.
final class WebcamSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var writer: PictureTrackWriter?
    private var latest: CVPixelBuffer?
    private var clock: CMClock?

    func record(into writer: PictureTrackWriter?) {
        lock.withLock { self.writer = writer }
    }

    /// The session's clock: its pictures' times are told in it.
    func use(_ clock: CMClock?) {
        lock.withLock { self.clock = clock }
    }

    var latestPicture: CVPixelBuffer? { lock.withLock { latest } }

    func forget() {
        lock.withLock { latest = nil }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let clock = lock.withLock { self.clock }
        let host = clock.map { CMSyncConvertTime(stamp, from: $0, to: CMClockGetHostTimeClock()) } ?? stamp
        deliver(Picture(pixels: pixels, time: host.seconds))
    }

    func deliver(_ picture: Picture) {
        let writer = lock.withLock { () -> PictureTrackWriter? in
            latest = picture.pixels
            return self.writer
        }
        writer?.append(picture)
    }
}

/// The webcam (docs/meeting-recorder-views.md, phase 3): macOS's preferred
/// camera, through `AVCaptureSession`, 1280 × 720 at most, 30 pictures a
/// second. Asked for the first time it is turned on; off, the camera is
/// released (its light goes off). A call's app using it too is fine:
/// macOS shares a camera.
@MainActor
final class WebcamTrack {
    enum State: Equatable {
        case off
        case denied
        /// No camera on this Mac.
        case none
        case on(String)
    }

    static let widest = 1280
    static let tallest = 720
    static let perSecond = 30

    private(set) var state: State = .off
    let sink = WebcamSink()
    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "com.nomdelasociete.Skilli.recorder.webcam", qos: .userInitiated)
    /// The file's size: the camera's, 1280 × 720 at most.
    private(set) var size = (width: 1280, height: 720)
    var onChange: (() -> Void)?
    #if SKILLI_SELFTEST
    /// Self-test: pictures drawn here stand in for a camera (the test Mac
    /// has none), timed by the host clock as a built-in camera's are.
    var standIn: StandInCamera?
    #endif

    var isOn: Bool {
        if case .on = state { return true }
        return false
    }

    /// Runs the camera when it is allowed; macOS asks once when it never
    /// did.
    func start() async {
        guard !isOn else { return }
        #if SKILLI_SELFTEST
        if let standIn {
            size = (standIn.width, standIn.height)
            standIn.start(into: sink)
            state = .on("FaceTime HD Camera")
            onChange?()
            return
        }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                onChange?()
                return
            }
        default:
            state = .denied
            onChange?()
            return
        }
        guard let device = AVCaptureDevice.systemPreferredCamera ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            state = .none
            onChange?()
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 } else { session.sessionPreset = .high }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(sink, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            state = .none
            onChange?()
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        size = Self.fileSize(width: Int(dimensions.width), height: Int(dimensions.height))
        sink.use(session.synchronizationClock)
        self.session = session
        state = .on(device.localizedName)
        nonisolated(unsafe) let running = session
        queue.async { running.startRunning() }
        Log.trace("Recorder: the webcam on (\(size.width)×\(size.height))")
        onChange?()
    }

    /// The camera released.
    func stop() {
        #if SKILLI_SELFTEST
        standIn?.stop()
        #endif
        if let session {
            nonisolated(unsafe) let running = session
            queue.async { running.stopRunning() }
        }
        session = nil
        sink.forget()
        if isOn { state = .off }
        onChange?()
    }

    func record(into writer: PictureTrackWriter?) {
        sink.record(into: writer)
    }

    /// The camera's `width` × `height`, 1280 × 720 at most, its shape kept.
    static func fileSize(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (widest, tallest) }
        let scale = min(1, Double(widest) / Double(width), Double(tallest) / Double(height))
        return (Int(Double(width) * scale) / 2 * 2, Int(Double(height) * scale) / 2 * 2)
    }
}

#if SKILLI_SELFTEST
/// Self-test: a camera drawn here (the test Mac has none), 30 pictures a
/// second, each timed by the host clock as it is made: dark grey, white
/// for 150 ms from each of `flashes` (host seconds), so where each landed
/// in `webcam.mp4` tells how it kept in step with the sound.
final class StandInCamera: @unchecked Sendable {
    let width = 640
    let height = 360
    let flashes: [Double]
    private let queue = DispatchQueue(label: "com.nomdelasociete.Skilli.selftest.camera", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var pool: CVPixelBufferPool?
    private(set) var made = 0

    init(flashes: [Double]) {
        self.flashes = flashes
    }

    func start(into sink: WebcamSink) {
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey: width,
                                           kCVPixelBufferHeightKey: height, kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self, weak sink] in
            guard let self, let sink, let picture = self.picture(at: HostClock.now) else { return }
            sink.deliver(picture)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func picture(at time: Double) -> Picture? {
        guard let pool else { return nil }
        var made: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess, let made else { return nil }
        let white = flashes.contains { time >= $0 && time < $0 + 0.15 }
        CVPixelBufferLockBaseAddress(made, [])
        if let base = CVPixelBufferGetBaseAddress(made) {
            let level: UInt32 = white ? 0xFF : 0x30
            let pixel = 0xFF00_0000 | level << 16 | level << 8 | level
            base.assumingMemoryBound(to: UInt32.self).update(repeating: pixel, count: CVPixelBufferGetBytesPerRow(made) / 4 * height)
        }
        CVPixelBufferUnlockBaseAddress(made, [])
        self.made += 1
        return Picture(pixels: made, time: time)
    }
}
#endif
