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
    /// way (1 s at most: a source gone sends none), pads the track to the
    /// stop, closes the file. Its length in seconds.
    func finish(at stop: Double) async -> Double {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                self.timeline.finish(at: stop)
                done.resume()
            }
        }
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            let arrived = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
                queue.async {
                    self.drain()
                    done.resume(returning: self.newest >= stop)
                }
            }
            if arrived { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await withCheckedContinuation { (done: CheckedContinuation<Double, Never>) in
            queue.async {
                self.timer?.cancel()
                self.timer = nil
                self.drain()
                let over = self.timeline.overshoot()
                if over > 0 { self.pending.removeLast(min(over, self.pending.count)) }
                if let tail = self.timeline.tail() { self.apply([tail], from: []) }
                self.flush(all: true)
                self.input.markAsFinished()
                let seconds = Double(self.appended) / Self.rate
                self.writer.finishWriting {
                    done.resume(returning: seconds)
                }
            }
        }
    }

    /// Nothing kept: the recording was never started for real.
    func cancel() {
        queue.sync {
            timer?.cancel()
            timer = nil
            writer.cancelWriting()
        }
    }

    // MARK: - On the writer's queue

    private func drain() {
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
        flush(all: false)
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
    private func flush(all: Bool) {
        var start = 0
        // What went is taken off once, after (a long silence is many pieces).
        defer { pending.removeFirst(start) }
        while pending.count - start >= Self.piece + (all ? 0 : Self.heldBack) || (all && start < pending.count) {
            guard writer.status == .writing else { return fail() }
            guard input.isReadyForMoreMediaData else {
                // The encoder is behind: kept for the next turn, never lost
                // (at the end, waited for).
                guard all else { return }
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            let count = min(Self.piece, pending.count - start)
            guard let buffer = sampleBuffer(from: start, count: count) else { return fail() }
            guard input.append(buffer) else { return fail() }
            appended += count
            start += count
        }
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
