import Foundation
import SkilliCore

/// `skil.li Transcriber`, the recorder's helper beside skil.li's executable
/// (docs/meeting-recorder-views.md, phase 4): started for one transcript's
/// models, gone once it is done, so their memory never counts against
/// skil.li's. It reads the recording's files where they are and writes its
/// answer to a file; nothing leaves the Mac.
enum TranscriberHelper {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var executable: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "skil.li Transcriber")
    }

    /// SpeakerKit's models, shipped in the app (`script/speakerkit_models.sh`).
    static var speakerModels: URL? {
        Bundle.main.url(forResource: "SpeakerKit", withExtension: nil)
    }

    /// One track's voices: where each speaks, as SpeakerKit hears it. Nil
    /// when this build has no helper or no models (the voices are then not
    /// told apart).
    static func voices(of audio: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [MeetingVoices.Stretch]? {
        guard let models = speakerModels else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-voices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: out) }
        guard try await run(["voices", audio.path, models.path, out.path], progress: progress) else { return nil }
        return try JSONDecoder().decode([MeetingVoices.Stretch].self, from: Data(contentsOf: out))
    }

    /// One track's words by Better transcription's whisper (its model and
    /// VAD as downloaded); nil when this build has no helper.
    static func whisper(of audio: URL, language: String, prompt: String,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> WhisperTranscript.Run? {
        guard let paths = BetterTranscription.paths() else { throw Failure(message: "Better transcription isn't downloaded: Settings → Recorder offers it.") }
        let id = UUID().uuidString
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-whisper-\(id).json")
        // The names as written: an argument reaches the helper decomposed
        // (the file system's form), and whisper would not know "Maëlys".
        let names = FileManager.default.temporaryDirectory.appendingPathComponent("skilli-whisper-\(id).txt")
        defer {
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.removeItem(at: names)
        }
        try Data(prompt.precomposedStringWithCanonicalMapping.utf8).write(to: names)
        guard try await run(["whisper", audio.path, paths.model.path, paths.vad.path, language, names.path, out.path], progress: progress) else { return nil }
        return try JSONDecoder().decode(WhisperTranscript.Run.self, from: Data(contentsOf: out))
    }

    /// Runs the helper with `arguments` until it ends, its "progress 0.42"
    /// lines to `progress`. False when it is not in this build; a failure
    /// throws its last line. Cancelled, the helper is stopped.
    static func run(_ arguments: [String], progress: @escaping @Sendable (Double) -> Void) async throws -> Bool {
        guard let executable else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let lines = LineReader { line in
            if line.hasPrefix("progress "), let done = Double(line.dropFirst(9)) { progress(done) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in lines.append(handle.availableData) }
        let said = LineReader { _ in }
        errors.fileHandleForReading.readabilityHandler = { handle in said.append(handle.availableData) }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { ended in continuation.resume(returning: ended.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        lines.append(output.fileHandleForReading.readDataToEndOfFile())
        said.append(errors.fileHandleForReading.readDataToEndOfFile())
        lines.finish()
        said.finish()
        try Task.checkCancellation()
        guard status == 0 else {
            throw Failure(message: said.last ?? "skil.li Transcriber stopped (\(status)).")
        }
        return true
    }

    /// Lines as they come, handed over one by one; the last one kept.
    private final class LineReader: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()
        private(set) var last: String?
        private let handle: @Sendable (String) -> Void

        init(_ handle: @escaping @Sendable (String) -> Void) {
            self.handle = handle
        }

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            pending.append(data)
            var lines: [String] = []
            while let end = pending.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...end)
            }
            if let line = lines.last(where: { !$0.isEmpty }) { last = line }
            lock.unlock()
            lines.forEach(handle)
        }

        /// The last line, when it had no line break.
        func finish() {
            append(Data([0x0A]))
        }
    }
}
