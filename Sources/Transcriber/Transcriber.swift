import AVFoundation
import Foundation
import SkilliCore
import SpeakerKit
import whisper

/// `skil.li Transcriber`, the meeting recorder's helper (docs/meeting-recorder-views.md,
/// phase 4): skil.li starts it for a transcript and it is gone after, so
/// the models' memory (SpeakerKit's 0.8 GB at most) never counts against
/// skil.li's. Nothing it hears or writes leaves the Mac.
///
///     skil.li Transcriber voices <audio> <models folder> <out.json>
///
/// Tells the voices of one track apart (SpeakerKit, the count found by
/// itself) and writes their stretches (`[MeetingVoices.Stretch]`).
///
///     skil.li Transcriber whisper <audio> <model> <VAD model> <language> <prompt file> <out.json>
///
/// Better transcription: one track's words by whisper large-v3-turbo
/// (whisper.cpp 1.9.5, Metal), as whisper-cli ran it when measured (beam
/// search of 5, its Silero VAD, the names as its prompt carried to every
/// window, token times), each token's time on the recording's clock
/// (the prompt in a UTF-8 file: an argument would reach the helper
/// decomposed, "Maëlys" as "Mae" and a mark, and whisper would not know it)
/// (whisper.cpp adds its VAD's cuts back); writes `WhisperTranscript.Run`.
///
/// Prints "progress 0.42" lines as it goes; a failure is its last line on
/// standard error, exit 1.
@main
enum Transcriber {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            switch arguments.first {
            case "voices" where arguments.count == 4:
                try await voices(audio: URL(fileURLWithPath: arguments[1]), models: arguments[2], out: URL(fileURLWithPath: arguments[3]))
            case "whisper" where arguments.count == 7:
                let prompt = try String(contentsOf: URL(fileURLWithPath: arguments[5]), encoding: .utf8)
                try whisperWords(audio: URL(fileURLWithPath: arguments[1]), model: arguments[2], vad: arguments[3], language: arguments[4],
                                 prompt: prompt, out: URL(fileURLWithPath: arguments[6]))
            default:
                throw Failure("usage: skil.li Transcriber voices <audio> <models folder> <out.json> | whisper <audio> <model> <VAD model> <language> <prompt file> <out.json>")
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static func progress(_ done: Double) {
        print(String(format: "progress %.3f", min(1, max(0, done))))
        fflush(stdout)
    }

    /// One track's voices, with SpeakerKit's models from `models` (shipped
    /// in the app: nothing downloaded).
    static func voices(audio: URL, models: String, out: URL) async throws {
        let samples = try monoSamples(audio)
        guard samples.count > 16000 else {
            return try JSONEncoder().encode([MeetingVoices.Stretch]()).write(to: out, options: .atomic)
        }
        let config = PyannoteConfig(modelFolder: models, download: false, verbose: false)
        let kit = try await SpeakerKit(config)
        progress(0.05)
        let result = try await kit.diarize(audioArray: samples, options: PyannoteDiarizationOptions()) { done in
            progress(0.05 + 0.95 * done.fractionCompleted)
        }
        let stretches = result.segments.compactMap { segment -> MeetingVoices.Stretch? in
            guard let voice = segment.speaker.speakerId ?? segment.speaker.speakerIds.first else { return nil }
            return MeetingVoices.Stretch(voice: voice, start: Double(segment.startTime), end: Double(segment.endTime))
        }
        await kit.unloadModels()
        try JSONEncoder().encode(stretches).write(to: out, options: .atomic)
        progress(1)
    }

    /// One track's words by whisper, as `WhisperTranscript.Run`.
    static func whisperWords(audio: URL, model: String, vad: String, language: String, prompt: String, out: URL) throws {
        let samples = try monoSamples(audio)
        guard samples.count > 1600 else {
            return try JSONEncoder().encode(WhisperTranscript.Run(segments: [])).write(to: out, options: .atomic)
        }
        whisper_log_set({ _, _, _ in }, nil)
        var context = whisper_context_default_params()
        context.use_gpu = true
        context.flash_attn = true
        guard let whisper = whisper_init_from_file_with_params(model, context) else {
            throw Failure("Better transcription's model could not be read: download it again in Settings → Recorder.")
        }
        defer { whisper_free(whisper) }
        progress(0.02)
        // whisper-cli's own defaults, as measured (`-ojf`: token times).
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        let beam = params.beam_search.beam_size
        params.greedy.best_of = whisper_full_default_params(WHISPER_SAMPLING_GREEDY).greedy.best_of
        params.beam_search.beam_size = beam
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))
        params.token_timestamps = true
        params.thold_pt = 0.01
        params.temperature = 0
        params.temperature_inc = 0.2
        params.entropy_thold = 2.4
        params.logprob_thold = -1
        params.no_speech_thold = 0.6
        params.carry_initial_prompt = true
        params.vad = true
        params.vad_params = whisper_vad_default_params()
        params.vad_params.threshold = 0.5
        params.vad_params.min_speech_duration_ms = 250
        params.vad_params.min_silence_duration_ms = 100
        params.vad_params.max_speech_duration_s = .greatestFiniteMagnitude
        params.vad_params.speech_pad_ms = 30
        params.vad_params.samples_overlap = 0.1
        params.progress_callback = { _, _, done, _ in Transcriber.progress(0.02 + 0.97 * Double(done) / 100) }
        let status = language.withCString { language in
            prompt.withCString { prompt in
                vad.withCString { vad in
                    var params = params
                    params.language = language
                    params.initial_prompt = prompt.pointee == 0 ? nil : prompt
                    params.vad_model_path = vad
                    return samples.withUnsafeBufferPointer { whisper_full(whisper, params, $0.baseAddress, Int32($0.count)) }
                }
            }
        }
        guard status == 0 else { throw Failure("Better transcription failed on \(audio.lastPathComponent) (\(status)).") }
        let end = whisper_token_eot(whisper)
        var segments: [WhisperTranscript.Segment] = []
        for segment in 0..<whisper_full_n_segments(whisper) {
            var tokens: [WhisperTranscript.Token] = []
            for token in 0..<whisper_full_n_tokens(whisper, segment) {
                guard whisper_full_get_token_id(whisper, segment, token) < end, let text = whisper_full_get_token_text(whisper, segment, token) else { continue }
                let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(text).assumingMemoryBound(to: UInt8.self), count: strlen(text)))
                tokens.append(WhisperTranscript.Token(bytes, start: Double(whisper_full_get_token_t0(whisper, segment, token)) / 100,
                                                      end: Double(whisper_full_get_token_t1(whisper, segment, token)) / 100))
            }
            if !tokens.isEmpty { segments.append(WhisperTranscript.Segment(tokens: tokens)) }
        }
        try JSONEncoder().encode(WhisperTranscript.Run(segments: segments)).write(to: out, options: .atomic)
        progress(1)
    }

    /// The file's sound as 16 kHz mono samples, what the models take.
    static func monoSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw Failure("\(url.lastPathComponent): its sound cannot be read.")
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * 16000 / file.processingFormat.sampleRate) + 16000)
        let chunk: AVAudioFrameCount = 65536
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(chunk) * 16000 / file.processingFormat.sampleRate) + 1024)
        else { throw Failure("\(url.lastPathComponent): its sound cannot be read.") }
        var finished = false
        // A read that fails before the end: thrown, not taken for the end
        // of the file (the voices would be told apart on part of it). At
        // the end, `read` throws too (eofErr): that one is the end.
        var readError: Error?
        while true {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if finished {
                    state.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input, frameCount: chunk)
                } catch {
                    if file.framePosition < file.length { readError = error }
                    finished = true
                    state.pointee = .endOfStream
                    return nil
                }
                if input.frameLength == 0 {
                    finished = true
                    state.pointee = .endOfStream
                    return nil
                }
                state.pointee = .haveData
                return input
            }
            if let error { throw error }
            if let readError { throw readError }
            if let data = output.floatChannelData?[0], output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
        }
        return samples
    }
}
