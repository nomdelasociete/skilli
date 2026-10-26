import AppKit
import SkilliCore

/// The two picture sources, as the card's rows and the red dot's menu
/// turn them on or off.
enum PictureSource {
    case webcam, screen
}

/// The recorder's pictures (docs/meeting-recorder-views.md, phase 3): the
/// webcam and the screen, each off until turned on, their files written
/// by the same host moments as the sound's (the start, each pause, the
/// stop), the screen's text read into `slides.json`. `MeetingRecorder`
/// starts and stops them with the sound; the card and the red dot's menu
/// turn them on or off.
@MainActor
final class RecorderPictures {
    nonisolated static let webcamFile = "webcam.mp4"
    nonisolated static let screenFile = "screen.mp4"
    nonisolated static let slidesFile = "slides.json"

    let webcam = WebcamTrack()
    let screen = ScreenTrack()
    private var webcamWriter: PictureTrackWriter?
    private var screenWriter: PictureTrackWriter?
    private var slides: SlideReader?
    /// The files a stop under way is closing: a quit meanwhile waits for
    /// them too.
    private var closing: [PictureTrackWriter] = []
    private var closingSlides: SlideReader?
    private var folder: URL?
    private var start = 0.0
    /// The recording's pauses so far (host times): a file made later in
    /// the recording (a source turned on then) is cut the same way.
    private var pauses: [(from: Double, to: Double?)] = []
    /// Each recording's start and stop, and the screen turned off: a
    /// screen file being set up across an await gives up when it moved.
    private var session = 0
    /// A source changed, or the screen's window gives no picture: the
    /// card, the menu bar.
    var onChange: (() -> Void)?
    /// A file could not be written (the disk full): the recording stops.
    var onFailure: ((String) -> Void)?

    init() {
        webcam.onChange = { [weak self] in self?.onChange?() }
        screen.onChange = { [weak self] in self?.onChange?() }
    }

    var isRecording: Bool { folder != nil }

    /// The sources on as the card opens, or ⌘R records: their pictures
    /// run (the card shows them), nothing written.
    func listen(webcam on: Bool, screen window: ScreenWindow?) async {
        if on { await webcam.start() }
        if let window { await screen.start(window) }
    }

    /// The webcam on or off, in the card or the red dot's menu. While
    /// recording, off writes black from that moment; on again goes on in
    /// the same file.
    func setWebcam(_ on: Bool) async {
        if on {
            await webcam.start()
            guard isRecording, webcam.isOn else { return }
            if webcamWriter == nil { webcamWriter = makeWriter(Self.webcamFile, size: webcam.size, perSecond: WebcamTrack.perSecond, held: nil) }
            webcam.record(into: webcamWriter)
        } else {
            // Detached first: no picture after the black one.
            webcam.record(into: nil)
            webcamWriter?.blank(at: HostClock.now)
            webcam.stop()
        }
    }

    /// The screen's window (nil: off), in the card or the red dot's menu.
    /// While recording, another window goes on in the same file, scaled
    /// to its size; off writes black from that moment.
    func setScreen(_ window: ScreenWindow?) async {
        guard let window else {
            session += 1
            // Detached first: no picture after the black one.
            screen.sink.record(into: nil, reading: nil)
            screenWriter?.blank(at: HostClock.now)
            screen.stop()
            return
        }
        await screen.start(window)
        guard isRecording, screen.window != nil else { return }
        await recordScreen(held: nil)
    }

    /// Recording from host time `start`, into `folder`: each source on
    /// (`webcam`, `screen`: as the recorder has them) gets its file, the
    /// picture it shows now at 0.
    func begin(folder: URL, start: Double, webcam webcamOn: Bool, screen screenOn: Bool) throws {
        self.folder = folder
        self.start = start
        pauses = []
        session += 1
        if webcamOn, webcam.isOn {
            webcamWriter = makeWriter(Self.webcamFile, size: webcam.size, perSecond: WebcamTrack.perSecond, held: webcam.sink.latestPicture)
            webcam.record(into: webcamWriter)
        }
        if screenOn, screen.window != nil {
            let held = screen.sink.latestPicture
            Task { await self.recordScreen(held: held) }
        }
    }

    private func recordScreen(held: CVPixelBuffer?) async {
        guard let folder else { return }
        let mine = session
        if screenWriter == nil {
            // The window at the file's size for its first picture; the
            // card's small one only when it cannot be had.
            let full = await screen.fullPicture()
            // Stopped, or the screen turned off, meanwhile: nothing set up.
            guard session == mine, self.folder == folder else { return }
            if screenWriter == nil {
                screenWriter = makeWriter(Self.screenFile, size: screen.plannedSize, perSecond: ScreenTrack.perSecond, held: full ?? held)
            }
        }
        if slides == nil {
            // Pictures far smaller than the file's (the card's) are not read.
            let reader = SlideReader(url: folder.appendingPathComponent(Self.slidesFile), start: start, smallest: screen.plannedSize.width / 2)
            for pause in pauses {
                reader.pause(at: pause.from)
                if let to = pause.to { reader.resume(at: to) }
            }
            slides = reader
        }
        guard let screenWriter, session == mine else { return }
        await screen.record(into: screenWriter, reading: slides)
    }

    /// A file for a source on now, its time the recording's (its pauses
    /// so far replayed). Nil: it could not be made (said, the recording
    /// goes on without it).
    private func makeWriter(_ name: String, size: (width: Int, height: Int), perSecond: Int, held: CVPixelBuffer?) -> PictureTrackWriter? {
        guard let folder else { return nil }
        // About 0.07 bits a pixel at the rate: 1.5 Mb/s for a 1280 × 720
        // webcam at 30, a 1920 × 1200 window at 15.
        let bitRate = max(500_000, min(2_500_000, Int(Double(size.width * size.height * perSecond) * 0.055)))
        do {
            let writer = try PictureTrackWriter(url: folder.appendingPathComponent(name), width: size.width, height: size.height, perSecond: perSecond,
                                                bitRate: bitRate, start: start, held: held, label: name)
            for pause in pauses {
                writer.pause(at: pause.from)
                if let to = pause.to { writer.resume(at: to) }
            }
            writer.onFailure = { [weak self] error in
                let said = error.localizedDescription
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.onFailure?(said) } }
            }
            return writer
        } catch {
            Log.actions.error("Recorder: \(name, privacy: .public) not started (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    func pause(at time: Double) {
        pauses.append((time, nil))
        webcamWriter?.pause(at: time)
        screenWriter?.pause(at: time)
        slides?.pause(at: time)
    }

    func resume(at time: Double) {
        if let last = pauses.indices.last, pauses[last].to == nil { pauses[last].to = time }
        webcamWriter?.resume(at: time)
        screenWriter?.resume(at: time)
        slides?.resume(at: time)
    }

    /// Stopped at host time `stop`: every file ends there, the slides
    /// kept, waited for until `closeBy` at most. Each file's length (0:
    /// none written), and whether every file was finished whole.
    func finish(at stop: Double, closeBy: DispatchTime) async -> (webcam: Double, screen: Double, slides: Int, complete: Bool) {
        session += 1
        // Not recording from now on: a source turned on while the files
        // close gets no file of its own (nothing would close it).
        let folder = self.folder
        self.folder = nil
        let (webcamWriter, screenWriter, slides) = (webcamWriter, screenWriter, slides)
        self.webcamWriter = nil
        self.screenWriter = nil
        self.slides = nil
        closing = [webcamWriter, screenWriter].compactMap { $0 }
        closingSlides = slides
        defer {
            closing = []
            closingSlides = nil
        }
        webcam.record(into: nil)
        screen.stopRecording()
        let none: (seconds: Double, complete: Bool) = (0, true)
        async let webcamClosed = webcamWriter?.finish(at: stop, closeBy: closeBy) ?? none
        async let screenClosed = screenWriter?.finish(at: stop, closeBy: closeBy) ?? none
        let kept = await slides?.finish(at: stop) ?? []
        let (webcamFile, screenFile) = await (webcamClosed, screenClosed)
        if let folder, kept.isEmpty { try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.slidesFile)) }
        pauses = []
        return (webcamFile.seconds, screenFile.seconds, kept.count, webcamFile.complete && screenFile.complete)
    }

    /// skil.li quits: every file closed at `stop` now, waited for until
    /// `deadline` at most (the main thread held, as the sound's). Whether
    /// each was finished by then.
    func finishNow(at stop: Double, until deadline: DispatchTime) -> Bool {
        session += 1
        markStop(at: stop)
        let writers = [webcamWriter, screenWriter].compactMap { $0 } + closing
        let finished = writers.allSatisfy { $0.closeNow(at: stop, until: deadline) != nil }
        let kept = (slides ?? closingSlides)?.finishNow(at: stop) ?? 0
        if let folder, kept == 0, slides != nil { try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.slidesFile)) }
        webcamWriter = nil
        screenWriter = nil
        slides = nil
        folder = nil
        pauses = []
        return finished
    }

    /// The stop's moment, at once: no picture placed past it (the files
    /// closed after).
    func markStop(at stop: Double) {
        webcam.record(into: nil)
        screen.stopRecording()
        for writer in [webcamWriter, screenWriter].compactMap({ $0 }) { writer.markStop(at: stop) }
    }

    /// Nothing kept: a recording that never started for real.
    func cancel() {
        session += 1
        webcamWriter?.cancel()
        screenWriter?.cancel()
        webcamWriter = nil
        screenWriter = nil
        slides = nil
        folder = nil
        screen.stopRecording()
        webcam.record(into: nil)
    }

    /// Every picture stops, the camera and the window let go.
    func stopAll() {
        webcam.stop()
        screen.stop()
    }
}
