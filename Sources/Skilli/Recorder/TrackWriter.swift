import AVFoundation
import CoreMedia
import Foundation
import SkilliCore

/// One track's file (`me.m4a`, `them.m4a`), written as it comes: AAC,
/// one channel at 48 kHz, in fragments of a second, so a crash, a logout
/// or a power cut leaves a file that plays up to its last second (an MP4
/// written whole at the end does not open at all then; the last half
/// second waits in memory, to be cut at the stop). Every 100 ms on its
/// own queue it takes what its source handed over and places it by the
/// track's own clock (`TrackTimeline`); a source at another rate (a
/// Bluetooth microphone at 16 kHz) is resampled first.
final class TrackWriter: @unchecked Sendable {
    static let rate = 48000.0
    /// What goes to the encoder at a time: 100 ms.
    private static let piece = 4800
    /// Kept back from the encoder while recording: what may still be cut
    /// off at the stop (`TrackTimeline.overshoot`).
    private static let heldBack = 24000

    let url: URL
    private let inbox: AudioInbox
    private let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let format: CMAudioFormatDescription
    private var timeline: TrackTimeline
    private var pending: [Float] = []
    private var appended = 0
    private var timer: DispatchSourceTimer?
    /// Resampling a source at another rate, and where it is.
    private var converter: AVAudioConverter?
    private var converterRate = 0.0
    private var inNext: Double?
    private var outNext = 0.0
    /// Frames given to the converter and frames it gave back: it holds some
    /// of each buffer, so what comes out is older than what went in.
    private var convertedIn = 0
    private var convertedOut = 0
    /// The host time the newest buffer taken ends at.
    private var newest = 0.0
    private var failed = false
    /// The file is being closed: what is left goes to the encoder.
    private var closingStarted = false
    /// Once closed (once, by Stop or by the quit, whichever comes first):
    /// its length in seconds, whether all of it went to the encoder, and
    /// left when the file is finished.
    private var closing: Closing?
    /// How long closing a file may take: what is left to encode, then the
    /// file finished. Past it, the file is left as a crash leaves it.
    static let closingTime: TimeInterval = 5

    private struct Closing {
        let seconds: Double
        let whole: Bool
        let finished: DispatchGroup
    }
    /// How far each run after a pause moved to its place (seconds; the
    /// track's own slip), once finished.
    private(set) var resumeJumps: [Double] = []
    /// The file could not be written (the disk full): on the writer's
    /// queue, once.
    var onFailure: (@Sendable (Error) -> Void)?

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Starts a file at `url` whose first frame is the host time `start`
    /// (seconds).
    init(url: URL, inbox: AudioInbox, start: Double, label: String) throws {
        self.url = url
        self.inbox = inbox
        queue = DispatchQueue(label: "com.nomdelasociete.Skilli.recorder.\(label)", qos: .userInitiated)
        timeline = TrackTimeline(rate: Self.rate, start: start)
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Self.rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        var description = AudioStreamBasicDescription(mSampleRate: Self.rate, mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
                                                      mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var made: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                       extensions: nil, formatDescriptionOut: &made)
        guard let made, writer.startWriting() else {
            throw writer.error ?? Failure(message: "“\(url.lastPathComponent)” could not be written.")
        }
        format = made
        writer.startSession(atSourceTime: .zero)
        pending.reserveCapacity(Self.piece * 4)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.drain() }
        timer.resume()
        self.timer = timer
    }

    func pause(at time: Double) {
        queue.async { self.timeline.pause(at: time) }
    }

    func resume(at time: Double) {
        queue.async { self.timeline.resume(at: time) }
    }

    /// Stops at the host time `stop`: waits for the buffers still on their
    /// way (1 s at most: a source gone sends none; none for a source turned
    /// off), pads the track to the stop, closes the file, by `closeBy` (the
    /// Stop's, shared by its tracks). Its length in seconds, and whether the
    /// file is whole and finished (not: it plays up to its last fragment, as
    /// after a crash).
    func finish(at stop: Double, waitingForSource: Bool = true,
                closeBy: DispatchTime = .now() + 1 + TrackWriter.closingTime) async -> (seconds: Double, complete: Bool) {
        await onQueue { self.timeline.finish(at: stop) }
        let deadline = ContinuousClock.now + .seconds(waitingForSource ? 1 : 0)
        while ContinuousClock.now < deadline {
            if await onQueue({ self.drained(upTo: stop) }) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let closed = await onQueue { self.close(until: closeBy) }
        // Finished, or past the deadline: never waits on a writer for good.
        let finished = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                done.resume(returning: closed.finished.wait(timeout: closeBy) == .success)
            }
        }
        return (closed.seconds, isComplete(closed, finished: finished))
    }

    // MARK: - Closing while skil.li quits

    // The quit may come from a job of the main queue, where no other job
    // runs until it ends: these hold the calling thread instead (never the
    // writer's queue).

    /// Nothing after the host time `stop` goes in.
    func markStop(at stop: Double) {
        queue.sync { timeline.finish(at: stop) }
    }

    /// Whether what the source handed over reaches `stop` (what came is
    /// encoded until `deadline` at most).
    func hasArrived(upTo stop: Double, until deadline: DispatchTime) -> Bool {
        queue.sync { drained(upTo: stop, until: deadline) }
    }

    /// Closes the file and waits until it is finished, until `deadline` at
    /// most (what is left to encode included: the encoder may never take it).
    /// Its length in seconds; nil when the file was not whole and finished
    /// by then (it plays up to its last fragment, as after a crash).
    func closeNow(until deadline: DispatchTime) -> Double? {
        let closed = queue.sync { close(until: deadline) }
        return isComplete(closed, finished: closed.finished.wait(timeout: deadline) == .success) ? closed.seconds : nil
    }

    /// A file whole, its finishing called back in time, and the writer
    /// done with it (`completed`: its finishing also calls back on a writer
    /// that failed). Not: what the writer said is logged.
    private func isComplete(_ closed: Closing, finished: Bool) -> Bool {
        guard closed.whole, finished else { return false }
        guard writer.status == .completed else {
            Log.actions.error("Recorder: \(self.url.lastPathComponent, privacy: .public) not completed (\(self.writer.error?.localizedDescription ?? "status \(self.writer.status.rawValue)", privacy: .public))")
            return false
        }
        return true
    }

    #if SKILLI_SELFTEST
    /// Self-test: what gets stuck as the file closes.
    enum Stall: String {
        /// The file's finishing never says it is done.
        case finishing
        /// The encoder never takes another sample.
        case encoder
        /// The encoder takes nothing while recording (a backlog builds),
        /// then each sample slowly at the close: the backlog would outlast
        /// the deadline.
        case slow
        /// The finishing ends without a completed file (the writer not
        /// `completed`, as one that failed).
        case failing
    }

    var stalls: Stall?
    #endif

    /// Nothing kept: the recording was never started for real.
    func cancel() {
        queue.sync {
            timer?.cancel()
            timer = nil
            writer.cancelWriting()
        }
    }

    // MARK: - On the writer's queue

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in queue.async { done.resume(returning: work()) } }
    }

    private func drained(upTo stop: Double, until deadline: DispatchTime = .distantFuture) -> Bool {
        drain(until: deadline)
        return newest >= stop
    }

    /// Pads or cuts the track to its stop, writes what is left (until
    /// `deadline`) and finishes the file, once.
    private func close(until deadline: DispatchTime) -> Closing {
        if let closing { return closing }
        timer?.cancel()
        timer = nil
        closingStarted = true
        drain(until: deadline)
        let over = timeline.overshoot()
        if over > 0 { pending.removeLast(min(over, pending.count)) }
        if let tail = timeline.tail() { apply([tail], from: []) }
        let whole = flush(all: true, until: deadline)
        resumeJumps = timeline.resumeJumps.map { Double($0) / Self.rate }
        let finished = DispatchGroup()
        finished.enter()
        // A writer that failed (the disk full), or whose encoder never took
        // the rest, is not finished: its file plays up to its last fragment
        // as it is.
        if whole, !failed, writer.status == .writing {
            input.markAsFinished()
            #if SKILLI_SELFTEST
            if stalls == .failing {
                // Ends without a completed file, as a writer that failed.
                writer.cancelWriting()
                finished.leave()
                let closed = Closing(seconds: Double(appended) / Self.rate, whole: whole, finished: finished)
                closing = closed
                return closed
            }
            #endif
            writer.finishWriting {
                #if SKILLI_SELFTEST
                if self.stalls == .finishing { return }
                #endif
                finished.leave()
            }
        } else {
            finished.leave()
        }
        let closed = Closing(seconds: Double(appended) / Self.rate, whole: whole, finished: finished)
        closing = closed
        return closed
    }

    /// What the source handed over placed on the track's clock, then to the
    /// encoder (until `deadline`: what is left stays pending).
    private func drain(until deadline: DispatchTime = .distantFuture) {
        guard !failed else { return }
        let (samples, chunks) = inbox.take()
        for chunk in chunks {
            if chunk.restarted {
                timeline.restarted()
                inNext = nil
            }
            let host = HostClock.seconds(chunk.hostTime)
            newest = max(newest, host + Double(chunk.frames) / chunk.rate)
            let slice = Array(samples[chunk.offset..<chunk.offset + chunk.frames])
            if abs(chunk.rate - Self.rate) < 1 {
                converter = nil
                let pieces = timeline.place(sampleTime: chunk.sampleTime, hostTime: host, frames: chunk.frames)
                trace(pieces, host: host, sampleTime: chunk.sampleTime, frames: chunk.frames)
                apply(pieces, from: slice)
            } else {
                // Another rate, the source started again, a gap in its own
                // time: a converter afresh, placed by the host clock (what the
                // old one still held is left out: a few milliseconds).
                let gap = inNext.map { abs(chunk.sampleTime - $0) > 1 } ?? true
                if converterRate != chunk.rate || converter == nil || chunk.restarted || gap {
                    converter = Self.converter(from: chunk.rate)
                    converterRate = chunk.rate
                    (convertedIn, convertedOut) = (0, 0)
                    timeline.restarted()
                }
                inNext = chunk.sampleTime + Double(chunk.frames)
                // What comes out now began this long before this buffer did.
                let held = Double(convertedIn) / chunk.rate - Double(convertedOut) / Self.rate
                let out = resampled(slice, rate: chunk.rate)
                convertedIn += chunk.frames
                convertedOut += out.count
                let pieces = timeline.place(sampleTime: outNext, hostTime: host - held, frames: out.count)
                trace(pieces, host: host - held, sampleTime: outNext, frames: out.count)
                apply(pieces, from: out)
                outNext += Double(out.count)
            }
        }
        flush(all: false, until: deadline)
    }

    /// Debug builds: where a run starts again (a gap filled, frames left
    /// out), to read how each track keeps its time.
    private func trace(_ pieces: [TrackTimeline.Piece], host: Double, sampleTime: Double, frames: Int) {
        #if DEBUG
        guard pieces.contains(where: { if case .silence = $0 { true } else if case .frames(let range) = $0 { range.lowerBound > 0 || range.count < frames } else { false } }) else { return }
        Log.trace("Recorder track \(url.deletingPathExtension().lastPathComponent): host \(String(format: "%.4f", host - timeline.start)) sample \(Int(sampleTime)) frames \(frames) → \(pieces), written \(timeline.written)")
        #endif
    }

    private func apply(_ pieces: [TrackTimeline.Piece], from source: [Float]) {
        for piece in pieces {
            switch piece {
            case .silence(let count): pending.append(contentsOf: repeatElement(0, count: count))
            case .frames(let range): pending.append(contentsOf: source[range])
            }
        }
    }

    /// What is pending to the encoder, 100 ms at a time (`all`: the rest
    /// too, at the end).
    /// What is pending to the encoder, 100 ms at a time (`all`: the rest
    /// too, at the end), until `deadline`: a backlog the encoder takes too
    /// slowly, or not at all, is left there. Whether all that was due went.
    @discardableResult
    private func flush(all: Bool, until deadline: DispatchTime = .distantFuture) -> Bool {
        var start = 0
        // What went is taken off once, after (a long silence is many pieces).
        defer { pending.removeFirst(start) }
        while pending.count - start >= Self.piece + (all ? 0 : Self.heldBack) || (all && start < pending.count) {
            // Never past the deadline (the quit's): the rest is left out, as
            // after a crash.
            if DispatchTime.now() >= deadline { return false }
            guard writer.status == .writing else {
                fail()
                return false
            }
            guard encoderIsReady else {
                // The encoder is behind: kept for the next turn, never lost
                // (at the end, waited for until the deadline).
                guard all else { return true }
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            #if SKILLI_SELFTEST
            if stalls == .slow, closingStarted { Thread.sleep(forTimeInterval: 0.2) }
            #endif
            let count = min(Self.piece, pending.count - start)
            guard let buffer = sampleBuffer(from: start, count: count), input.append(buffer) else {
                fail()
                return false
            }
            appended += count
            start += count
        }
        return true
    }

    private var encoderIsReady: Bool {
        #if SKILLI_SELFTEST
        if stalls == .encoder, closingStarted { return false }
        if stalls == .slow, !closingStarted { return false }
        #endif
        return input.isReadyForMoreMediaData
    }

    private func fail() {
        guard !failed else { return }
        failed = true
        timer?.cancel()
        timer = nil
        let error = writer.error ?? Failure(message: "“\(url.lastPathComponent)” could not be written.")
        Log.actions.error("Recorder: \(self.url.lastPathComponent, privacy: .public) not written (\(error.localizedDescription, privacy: .public))")
        onFailure?(error)
    }

    private func sampleBuffer(from start: Int, count: Int) -> CMSampleBuffer? {
        let bytes = count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr, let block
        else { return nil }
        let copied = pending.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress! + start * MemoryLayout<Float>.size, blockBuffer: block, offsetIntoDestination: 0,
                                          dataLength: bytes)
        }
        guard copied == noErr else { return nil }
        var buffer: CMSampleBuffer?
        let time = CMTime(value: CMTimeValue(appended), timescale: CMTimeScale(Self.rate))
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
                                                                   presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &buffer) == noErr
        else { return nil }
        return buffer
    }

    private static func converter(from rate: Double) -> AVAudioConverter? {
        guard let from = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let to = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 1) else { return nil }
        return AVAudioConverter(from: from, to: to)
    }

    private func resampled(_ samples: [Float], rate: Double) -> [Float] {
        guard let converter, let buffer = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                            frameCapacity: AVAudioFrameCount((Double(samples.count) * Self.rate / rate).rounded(.up)) + 1024)
        else { return [] }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        nonisolated(unsafe) var given = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if given {
                state.pointee = .noDataNow
                return nil
            }
            given = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
