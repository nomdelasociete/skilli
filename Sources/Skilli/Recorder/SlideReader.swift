import CoreVideo
import Foundation
import SkilliCore
import Vision

/// The text the screen shows, read on this Mac (docs/meeting-recorder-views.md,
/// phase 3, "Reading the slides"): from the screen's own pictures, sampled
/// four times a second as a small grid of their brightness, read by
/// Vision's text recognition when the picture changed (`SlideSchedule`),
/// the lines new since the readings before kept as a slide at the time it
/// changed (`SlideLog`), in `slides.json` as they come. A still window
/// gives no new picture: its last one is sampled again as time goes on,
/// so a change seen while a reading waited is read all the same. Nothing
/// of the pictures is kept, nothing leaves the Mac. On its own queue, one
/// reading at a time.
final class SlideReader: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "com.nomdelasociete.Skilli.recorder.slides", qos: .utility)
    private var timeline: PictureTimeline
    private var schedule = SlideSchedule()
    private var log = SlideLog()
    private var lastSample = -Double.infinity
    private var reading: Task<Void, Never>?
    private var finished = false
    /// The last picture given, sampled again while no other comes.
    private var latest: Picture?
    private var timer: DispatchSourceTimer?
    /// Pictures narrower than this (the card's small ones) are not read.
    private let smallest: Int

    /// Readings made, and the seconds they took in all (the self-test's
    /// cost).
    private(set) var readings = 0
    private(set) var readingSeconds = 0.0

    init(url: URL, start: Double, smallest: Int = 0) {
        self.url = url
        self.smallest = smallest
        timeline = PictureTimeline(start: start)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + SlideSchedule.sampleEvery, repeating: SlideSchedule.sampleEvery, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.sampleAgain() }
        timer.resume()
        self.timer = timer
    }

    /// A picture of the screen (the stream's queue): sampled four times a
    /// second while recording, read when it changed.
    func offer(_ picture: Picture) {
        queue.async { self.sample(picture) }
    }

    func pause(at time: Double) {
        queue.async { self.timeline.pause(at: time) }
    }

    func resume(at time: Double) {
        queue.async { self.timeline.resume(at: time) }
    }

    /// Stopped at host time `stop`: the reading under way finished, then
    /// the slides as kept (the window's own lines out), written.
    func finish(at stop: Double) async -> [SlideLog.Slide] {
        let (task, end) = await withCheckedContinuation { (done: CheckedContinuation<(Task<Void, Never>?, Double), Never>) in
            queue.async {
                let end = self.timeline.finish(at: stop)
                self.timer?.cancel()
                self.timer = nil
                self.latest = nil
                done.resume(returning: (self.reading, end))
            }
        }
        await task?.value
        return await withCheckedContinuation { (done: CheckedContinuation<[SlideLog.Slide], Never>) in
            queue.async {
                self.finished = true
                let kept = self.log.kept().filter { $0.start <= end }
                self.write(kept)
                Log.trace("Recorder: \(kept.count) slides read in \(self.readings) readings (\(String(format: "%.1f", self.readingSeconds)) s)")
                done.resume(returning: kept)
            }
        }
    }

    /// skil.li quits: the slides as kept now, a reading under way left out.
    @discardableResult
    func finishNow(at stop: Double) -> Int {
        queue.sync {
            guard !finished else { return 0 }
            let end = timeline.finish(at: stop)
            timer?.cancel()
            timer = nil
            latest = nil
            finished = true
            let kept = log.kept().filter { $0.start <= end }
            write(kept)
            return kept.count
        }
    }

    // MARK: - On the reader's queue

    /// No new picture for a while (a still window): the last one again, at
    /// the time it is now.
    private func sampleAgain() {
        let now = HostClock.now
        guard let latest, now - lastSample >= SlideSchedule.sampleEvery - 0.01 else { return }
        sample(Picture(pixels: latest.pixels, time: now))
    }

    private func sample(_ picture: Picture) {
        guard !finished, CVPixelBufferGetWidth(picture.pixels) >= smallest else { return }
        latest = picture
        guard picture.time - lastSample >= SlideSchedule.sampleEvery - 0.01, timeline.records(picture.time) else { return }
        lastSample = picture.time
        let grid = Self.grid(picture.pixels)
        let time = timeline.fileTime(of: picture.time)
        guard let start = schedule.sample(grid, at: time), reading == nil else { return }
        let pixels = picture.pixels
        let began = ContinuousClock.now
        nonisolated(unsafe) let buffer = pixels
        // Held until it is read (a second at most): `finish` waits for it.
        reading = Task.detached(priority: .utility) {
            let lines = await Self.lines(in: buffer)
            self.queue.async { self.read(lines, start: start, grid: grid, at: time, took: ContinuousClock.now - began) }
        }
    }

    private func read(_ lines: [String], start: Double, grid: [UInt8], at time: Double, took: Duration) {
        readings += 1
        readingSeconds += took.milliseconds / 1000
        let slide = finished ? nil : log.read(lines, at: start)
        schedule.read(grid, at: time, foundNew: slide != nil)
        reading = nil
        if slide != nil, !finished { write(log.kept()) }
    }

    private func write(_ slides: [SlideLog.Slide]) {
        do {
            try SlideLog.encoded(slides).write(to: url, options: .atomic)
        } catch {
            Log.actions.error("Recorder: slides.json not written (\(error.localizedDescription, privacy: .public))")
        }
    }

    /// The picture's lines, top to bottom, as Vision reads them.
    private static func lines(in pixels: CVPixelBuffer) async -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: pixels) else { return [] }
        return observations
            .sorted { a, b in
                // Top first (Vision's origin is at the bottom), then left.
                abs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.01 ? a.boundingBox.origin.y > b.boundingBox.origin.y
                    : a.boundingBox.origin.x < b.boundingBox.origin.x
            }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// The picture's brightness on `SlideSchedule`'s grid: each cell the
    /// mean of 16 of its pixels.
    static func grid(_ pixels: CVPixelBuffer) -> [UInt8] {
        let columns = SlideSchedule.columns, rows = SlideSchedule.rows
        var grid = [UInt8](repeating: 0, count: columns * rows)
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA else { return grid }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return grid }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels), row = CVPixelBufferGetBytesPerRow(pixels)
        guard width >= columns, height >= rows else { return grid }
        for cellY in 0..<rows {
            for cellX in 0..<columns {
                var sum = 0
                for dy in 0..<4 {
                    let y = (cellY * 8 + 2 * dy + 1) * height / (rows * 8)
                    for dx in 0..<4 {
                        let x = (cellX * 8 + 2 * dx + 1) * width / (columns * 8)
                        let pixel = base + min(y, height - 1) * row + min(x, width - 1) * 4
                        // BGRA: the eye's weights, in 256ths.
                        sum += (Int(pixel[2]) * 77 + Int(pixel[1]) * 150 + Int(pixel[0]) * 29) >> 8
                    }
                }
                grid[cellY * columns + cellX] = UInt8(sum / 16)
            }
        }
        return grid
    }
}
