import AVFoundation
import Carbon
import SkilliCore
import Speech

/// Speech to text on this Mac (macOS 26 `SpeechAnalyzer`): what the user
/// says becomes Ask's instruction, or text typed into the app in front
/// (Dictate), shown live while they speak. Audio never leaves the Mac; the
/// language model is downloaded once by macOS.
@MainActor
final class VoiceInput {
    /// What the words are for. Ask: `SpeechTranscriber`, the newer model.
    /// Dictation: `DictationTranscriber`, the model of macOS's own
    /// dictation, the one that takes a vocabulary
    /// (`AnalysisContext.contextualStrings`, which `SpeechTranscriber` does
    /// not read), with punctuation.
    enum Use {
        case ask
        case dictation
    }

    var use: Use = .ask
    /// Dictation: the names the recognizer should expect (the user's
    /// contacts), given to it on this Mac. Asked once the microphone runs,
    /// so no word is lost while the contacts are read.
    var vocabulary: (() async -> [String])?

    struct Failure: LocalizedError {
        let message: String
        /// Return opens the microphone's privacy settings.
        var opensPrivacy = false
        var errorDescription: String? { message }
    }

    static let microphonePrivacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    /// The text so far: what is settled, then what is still being heard.
    var onText: ((String) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var settled = ""
    private var hearing = ""
    /// What the transcriber reads, for the trailing silence.
    private var format: AVAudioFormat?

    var text: String { DictationText.joined(settled, hearing).trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The chosen language (Settings → Ask), else the keyboard's: people
    /// speak the language they type in (AZERTY → French), which their first
    /// system language may not be.
    var language = ""

    func locale<Module: LocaleDependentSpeechModule>(for module: Module.Type) async -> Locale? {
        for identifier in [language, Self.keyboardLanguage, Locale.preferredLanguages.first].compactMap({ $0 }) where !identifier.isEmpty {
            if let locale = await module.supportedLocale(equivalentTo: Locale(identifier: identifier)) { return locale }
        }
        return nil
    }

    /// The language of the keyboard layout in use ("fr" for AZERTY).
    static var keyboardLanguage: String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return nil }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        return languages?.first
    }

    /// Listens to the microphone (macOS asks once). `status` tells the card
    /// about a first-time model download.
    func start(status: @escaping (String) -> Void) async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied:
            throw Failure(message: "The microphone is off for skil.li. Turn it on in System Settings → Privacy & Security → Microphone.", opensPrivacy: true)
        case .restricted:
            throw Failure(message: "This Mac's settings do not allow the microphone.")
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw Failure(message: "Without the microphone, skil.li cannot hear you. You can turn it on in System Settings → Privacy & Security → Microphone.", opensPrivacy: true)
            }
        case .authorized:
            break
        @unknown default:
            break
        }
        let (stream, format) = try await prepare(status: status)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let natural = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: natural, to: format) else {
            throw Failure(message: "The microphone's audio cannot be read.")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: natural, block: Self.tap(converter: converter, format: format, into: continuation))
        engine.prepare()
        try engine.start()
        self.engine = engine
        // The microphone runs (its audio waits in the stream): now the names.
        await giveVocabulary()
        try await analyzer?.start(inputSequence: stream)
    }

    /// Self-test: an audio file instead of the microphone, then the text.
    func transcribe(file url: URL, status: @escaping (String) -> Void = { _ in }) async throws -> String {
        let (stream, format) = try await prepare(status: status)
        let file = try AVAudioFile(forReading: url)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw Failure(message: "The audio file cannot be read.")
        }
        await giveVocabulary()
        try await analyzer?.start(inputSequence: stream)
        // `read` throws at the end of the file instead of reading nothing.
        while file.framePosition < file.length {
            let frames = AVAudioFrameCount(min(4096, file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
            try file.read(into: buffer, frameCount: frames)
            if let converted = Self.convert(buffer, with: converter, to: format) {
                continuation?.yield(AnalyzerInput(buffer: converted))
            }
        }
        return await stop()
    }

    /// Stops listening, waits for the last words, returns the text.
    @discardableResult
    func stop() async -> String {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        // A moment of silence lets the last word settle: Return often comes
        // right after it.
        if let format, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 0.4)) {
            silence.frameLength = silence.frameCapacity
            continuation?.yield(AnalyzerInput(buffer: silence))
        }
        continuation?.finish()
        continuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        analyzer = nil
        results = nil
        return text
    }

    func cancel() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        continuation?.finish()
        continuation = nil
        let analyzer = self.analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        self.analyzer = nil
        results?.cancel()
        results = nil
    }

    // MARK: - Setup

    private func prepare(status: @escaping (String) -> Void) async throws -> (AsyncStream<AnalyzerInput>, AVAudioFormat) {
        settled = ""
        hearing = ""
        let module: any SpeechModule
        let locale: Locale
        // Followed once the analyzer exists (a failure before leaves no
        // task waiting on a transcriber that never runs).
        let follow: () -> Task<Void, Never>
        switch use {
        case .ask:
            guard let found = await self.locale(for: SpeechTranscriber.self) else { throw Self.noModel }
            let transcriber = SpeechTranscriber(locale: found, preset: .progressiveTranscription)
            (module, locale) = (transcriber, found)
            follow = { self.follow(transcriber) { String($0.text.characters) } }
        case .dictation:
            guard let found = await self.locale(for: DictationTranscriber.self) else { throw Self.noModel }
            let transcriber = DictationTranscriber(locale: found, preset: .progressiveLongDictation)
            (module, locale) = (transcriber, found)
            follow = { self.follow(transcriber) { String($0.text.characters) } }
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            status("Downloading the \(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier) speech model…")
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Failure(message: "No audio format for speech.")
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.continuation = continuation
        self.format = format
        analyzer = SpeechAnalyzer(modules: [module])
        results = follow()
        return (stream, format)
    }

    private static let noModel = Failure(message: "macOS has no speech model for your language.")

    /// The transcriber's results, settled then still heard, as they come.
    private func follow<Module: SpeechModule>(_ module: Module, text: @escaping @Sendable (Module.Result) -> String) -> Task<Void, Never> {
        let results = module.results
        return Task { [weak self] in
            do {
                for try await result in results {
                    let words = text(result)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self else { return }
                        if isFinal {
                            self.settled = DictationText.joined(self.settled, words)
                            self.hearing = ""
                        } else {
                            self.hearing = words
                        }
                        self.onText?(self.text)
                    }
                }
            } catch {
                Log.actions.error("Speech failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Dictation: the names, for the analyzer only; nothing is logged but
    /// how many.
    private func giveVocabulary() async {
        guard use == .dictation, let vocabulary, let analyzer else { return }
        let phrases = await vocabulary()
        guard !phrases.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings[.general] = phrases
        do {
            try await analyzer.setContext(context)
            Log.trace("Dictation: \(phrases.count) names given to the recognizer")
        } catch {
            Log.actions.error("Dictation vocabulary refused: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// What the microphone's tap runs, on AVFoundation's audio queue. Made
    /// here, outside the main actor: a block written inside `start` was
    /// main-actor isolated, and Swift 6 stopped the app the first time
    /// audio came in on that queue.
    private nonisolated static func tap(converter: AVAudioConverter, format: AVAudioFormat,
                                        into continuation: AsyncStream<AnalyzerInput>.Continuation?) -> AVAudioNodeTapBlock {
        { buffer, _ in
            if let converted = convert(buffer, with: converter, to: format) {
                continuation?.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    /// Audio thread: resamples a buffer to what the transcriber wants.
    private nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        // Room for what the resampler held back from the last buffer.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
