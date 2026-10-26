import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SkilliCore

/// A picture as a source hands it over: the frame and the host time
/// (seconds) it was shown at. A CF buffer, passed between queues as is.
struct Picture: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let time: Double
}

/// One picture track's file (`webcam.mp4`, `screen.mp4`;
/// docs/meeting-recorder-views.md, phase 3, "The files"): H.264 at the
/// size given, written as it comes in fragments of a second (a crash keeps
/// what was recorded, as the sound's), each picture at its own host time,
/// cut where the sound is cut (`PictureTimeline`). A picture is held until
/// the next, so a source that gives none (a still slide) costs nothing,
/// and the picture on screen at a cut (the start, a resume) is placed
/// again where recording goes on. On its own queue.
final class PictureTrackWriter: @unchecked Sendable {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let url: URL
    let width: Int
    let height: Int
    private let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var timeline: PictureTimeline
    /// The latest picture the source gave, recorded or not: held over a cut.
    private var latest: CVPixelBuffer?
    private var black: CVPixelBuffer?
    private var failed = false
    private var finished = false
    /// When the source last went off: a picture shown before it, arriving
    /// late, is not written after the black one.
    private var blankedAt: Double?
    /// Once closed, its length and whether it is whole; those waiting for
    /// a close under way.
    private var closedLength: (seconds: Double, complete: Bool)?
    private var closeWaiters: [@Sendable (Double, Bool) -> Void] = []
    /// Pictures written, and left out while the encoder was behind.
    private(set) var written = 0
    private(set) var dropped = 0
    /// The file could not be written (the disk full): on the writer's
    /// queue, once.
    var onFailure: (@Sendable (Error) -> Void)?

    /// A file at `url` whose 0 is the host time `start`; `held` is the
    /// picture the source shows at host time `heldAt` (the start, or when a
    /// source turned on later joined: nothing before it).
    init(url: URL, width: Int, height: Int, perSecond: Int, bitRate: Int, start: Double, held: CVPixelBuffer?, heldAt: Double? = nil,
         label: String) throws {
        self.url = url
        // H.264 wants even sizes.
        self.width = max(16, width / 2 * 2)
        self.height = max(16, height / 2 * 2)
        queue = DispatchQueue(label: "com.nomdelasociete.Skilli.recorder.\(label)", qos: .userInitiated)
        timeline = PictureTimeline(start: start)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: self.width,
            AVVideoHeightKey: self.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: perSecond,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw Failure(message: "“\(url.lastPathComponent)” could not be written.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure(message: "“\(url.lastPathComponent)” could not be written.") }
        writer.startSession(atSourceTime: .zero)
        latest = held
        let moment = heldAt ?? start
        queue.async { self.placeHeld(at: moment) }
    }

    /// A picture from the source (any queue).
    func append(_ picture: Picture) {
        queue.async {
            if let blankedAt = self.blankedAt, picture.time <= blankedAt { return }
            self.latest = picture.pixels
            guard let time = self.timeline.place(picture.time) else { return }
            self.write(picture.pixels, at: time, waiting: false)
        }
    }

    /// The source went off at host time `time`: black from then on, until
    /// its next picture.
    func blank(at time: Double) {
        queue.async {
            guard let black = self.blackPicture() else { return }
            self.blankedAt = time
            self.latest = black
            guard let at = self.timeline.place(time) else { return }
            self.write(black, at: at, waiting: true)
        }
    }

    func pause(at time: Double) {
        queue.async { self.timeline.pause(at: time) }
    }

    /// Recording goes on: the picture on screen now held from before.
    func resume(at time: Double) {
        queue.async {
            self.timeline.resume(at: time)
            self.placeHeld(at: time)
        }
    }

    /// Stopped at host time `stop`: the file ends there, its last picture
    /// held to it, waited for until `deadline` at most. Its length in
    /// seconds (0: none written, the file removed), and whether it was
    /// finished whole (`complete`: in time, the writer saying so; a file
    /// never made is complete).
    func finish(at stop: Double, closeBy deadline: DispatchTime) async -> (seconds: Double, complete: Bool) {
        let finished = DispatchSemaphore(value: 0)
        let result = Closed()
        queue.async {
            self.close(at: stop) { seconds, complete in
                result.set(seconds, complete)
                finished.signal()
            }
        }
        return await withCheckedContinuation { (done: CheckedContinuation<(seconds: Double, complete: Bool), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let inTime = finished.wait(timeout: deadline) == .success
                let closed = result.value
                done.resume(returning: (closed.seconds, inTime && closed.complete))
            }
        }
    }

    /// The stop's moment, at once: no picture placed past it.
    func markStop(at stop: Double) {
        queue.sync { _ = timeline.finish(at: stop) }
    }

    /// skil.li quits: closed at `stop` now, waited for until `deadline` at
    /// most (the main thread held, as the sound's). Its length; nil when
    /// the file was not finished whole by then (it plays up to its last
    /// fragment, as after a crash).
    func closeNow(at stop: Double, until deadline: DispatchTime) -> Double? {
        let finished = DispatchSemaphore(value: 0)
        let result = Closed()
        queue.sync {
            close(at: stop) { seconds, complete in
                result.set(seconds, complete)
                finished.signal()
            }
        }
        guard finished.wait(timeout: deadline) == .success, result.value.complete else { return nil }
        return result.value.seconds
    }

    private final class Closed: @unchecked Sendable {
        private let lock = NSLock()
        private var closed = (seconds: 0.0, complete: false)
        var value: (seconds: Double, complete: Bool) { lock.withLock { closed } }
        func set(_ seconds: Double, _ complete: Bool) { lock.withLock { closed = (seconds, complete) } }
    }

    /// On the writer's queue: the file ended at `stop`, `done` told its
    /// length and whether it is whole once finished (a close already under
    /// way: once it is).
    private func close(at stop: Double, done: @escaping @Sendable (Double, Bool) -> Void) {
        guard !finished else {
            if let closedLength { done(closedLength.seconds, closedLength.complete) } else { closeWaiters.append(done) }
            return
        }
        finished = true
        let end = timeline.finish(at: stop)
        latest = nil
        guard written > 0, !failed, writer.status == .writing else {
            if written == 0 {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
            }
            // None written: nothing to be whole. One that failed: it plays
            // up to its last fragment, not whole.
            closed(written > 0 ? end : 0, complete: written == 0, done)
            return
        }
        writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 600))
        input.markAsFinished()
        writer.finishWriting {
            // Finished is not whole: the writer says which (Apple's rule).
            self.queue.async { self.closed(end, complete: self.writer.status == .completed, done) }
        }
    }

    private func closed(_ length: Double, complete: Bool, _ done: @Sendable (Double, Bool) -> Void) {
        closedLength = (length, complete)
        done(length, complete)
        let waiting = closeWaiters
        closeWaiters = []
        waiting.forEach { $0(length, complete) }
    }

    /// Nothing kept: the recording never started for real.
    func cancel() {
        queue.sync {
            finished = true
            latest = nil
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - On the writer's queue

    private func placeHeld(at moment: Double) {
        guard let latest, let time = timeline.placeHeld(at: moment) else { return }
        write(latest, at: time, waiting: true)
    }

    /// `waiting`: a picture that must be in the file (held over a cut,
    /// black): the encoder is waited for a moment; any other is left out
    /// while it is behind (the next one comes a frame later).
    private func write(_ pixels: CVPixelBuffer, at time: Double, waiting: Bool) {
        guard !failed, !finished else { return }
        guard writer.status == .writing else { return fail() }
        var tries = 0
        while !input.isReadyForMoreMediaData {
            guard waiting, tries < 20 else {
                dropped += 1
                return
            }
            tries += 1
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard adaptor.append(pixels, withPresentationTime: CMTime(seconds: time, preferredTimescale: 90000)) else { return fail() }
        written += 1
    }

    private func blackPicture() -> CVPixelBuffer? {
        if let black { return black }
        var made: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &made) == kCVReturnSuccess,
              let made else { return nil }
        CVPixelBufferLockBaseAddress(made, [])
        if let base = CVPixelBufferGetBaseAddress(made) {
            // Black, opaque: BGRA 0, 0, 0, 255.
            let row = CVPixelBufferGetBytesPerRow(made)
            let pixels = base.assumingMemoryBound(to: UInt32.self)
            let count = row / 4 * height
            pixels.update(repeating: UInt32(0xFF00_0000).littleEndian, count: count)
        }
        CVPixelBufferUnlockBaseAddress(made, [])
        black = made
        return made
    }

    private func fail() {
        guard !failed else { return }
        failed = true
        let error = writer.error ?? Failure(message: "“\(url.lastPathComponent)” could not be written.")
        Log.actions.error("Recorder: \(self.url.lastPathComponent, privacy: .public) not written (\(error.localizedDescription, privacy: .public))")
        onFailure?(error)
    }
}
