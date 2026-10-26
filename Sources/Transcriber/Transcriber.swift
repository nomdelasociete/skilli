import AVFoundation
import Foundation
import SkilliCore
import SpeakerKit

/// `skil.li Transcriber`, the meeting recorder's helper (docs/meeting-recorder-views.md,
/// phase 4): skil.li starts it for a transcript and it is gone after, so
/// the models' memory (SpeakerKit's 0.8 GB at most) never counts against
/// skil.li's. Nothing it hears or writes leaves the Mac.
///
///     skil.li Transcriber voices <audio> <models folder> <out.json>
///
/// Tells the voices of one track apart (SpeakerKit, the count found by
/// itself) and writes their stretches (`[MeetingVoices.Stretch]`). Prints
/// "progress 0.42" lines as it goes; a failure is its last line on
/// standard error, exit 1.
@main
enum Transcriber {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            switch arguments.first {
            case "voices" where arguments.count == 4:
                try await voices(audio: URL(fileURLWithPath: arguments[1]), models: arguments[2], out: URL(fileURLWithPath: arguments[3]))
            default:
                throw Failure("usage: skil.li Transcriber voices <audio> <models folder> <out.json>")
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
            if let data = output.floatChannelData?[0], output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
        }
        return samples
    }
}
