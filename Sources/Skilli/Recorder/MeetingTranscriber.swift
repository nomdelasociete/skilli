import AVFoundation
import Foundation
import SkilliCore
import Speech

/// A recording's transcript, made on this Mac at Stop (docs/meeting-recorder.md,
/// "Transcription"): macOS's `SpeechTranscriber`, given no names (it reads
/// none: Measured), each track alone, every word with its time. Then the
/// other side's words the microphone heard again are taken out of the
/// user's (no headphones), and the two tracks become one transcript by
/// time: `transcript.md`, `transcript.json`. Audio never leaves the Mac;
/// macOS downloads a language's model once.
enum MeetingTranscriber {
    static let engine = "SpeechTranscriber"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// What it is doing, for the menu bar.
    enum Step: Equatable, Sendable {
        case downloading(String)
        case transcribing(Double)
    }

    /// The language a recording starts in: Ask's (Settings → Ask), else
    /// the keyboard's, else the Mac's first, as Ask by Voice hears it. The
    /// first this Mac can transcribe; none: the first asked, kept as it is
    /// (the transcript waits).
    @MainActor
    static func defaultLanguage(asked: String) async -> String {
        let wanted = [asked, VoiceInput.keyboardLanguage, Locale.preferredLanguages.first].compactMap { $0 }.filter { !$0.isEmpty }
        for identifier in wanted {
            if let locale = await locale(for: identifier) { return locale.identifier(.bcp47) }
        }
        return wanted.first ?? "en-US"
    }

    /// The engine's locale for a language, nil when this Mac cannot
    /// transcribe it.
    static func locale(for identifier: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }

    /// Every language this Mac transcribes, by name.
    static func languages() async -> [(id: String, name: String)] {
        let locales = await SpeechTranscriber.supportedLocales
        return locales.map { ($0.identifier(.bcp47), name(of: $0.identifier(.bcp47))) }.sorted { $0.name < $1.name }
    }

    /// "English (United States)", "French (France)".
    static func name(of identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// The language alone, as the window and `transcript.md` say it
    /// ("English"; the card names the region when this Mac has several).
    static func shortName(of identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        return locale.language.languageCode.flatMap { Locale.current.localizedString(forLanguageCode: $0.identifier) } ?? name(of: identifier)
    }

    /// Both tracks of `folder` transcribed, put together and written; the
    /// record as it is then (`done`, its engine and the words dropped).
    static func transcribe(_ folder: URL, record: MeetingRecord, step: @escaping @Sendable (Step) -> Void) async throws -> MeetingRecord {
        guard let locale = await locale(for: record.language) else {
            throw Failure(message: "\(name(of: record.language)) can't be transcribed on this Mac yet.")
        }
        try await install(locale, step: step)
        let me = folder.appendingPathComponent(Speaker.me.file), them = folder.appendingPathComponent(Speaker.them.file)
        let lengths = [me, them].map { (try? AVAudioFile(forReading: $0)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0 }
        let total = max(1, lengths.reduce(0, +))
        step(.transcribing(0))
        let mine = try await phrases(of: me, locale: locale) { done in step(.transcribing(done * lengths[0] / total)) }
        let theirs = try await phrases(of: them, locale: locale) { done in step(.transcribing((lengths[0] + done * lengths[1]) / total)) }
        let (kept, dropped) = MeetingTranscript.droppingEcho(mine, heard: theirs.flatMap { $0 })
        let lines = MeetingTranscript.lines(me: kept, them: theirs)
        var done = record
        done.state = .done
        done.engine = engine
        done.echoDropped = dropped
        done.recorder = nil
        let file = MeetingTranscript.File(language: record.language, engine: engine, lines: lines)
        try file.encoded().write(to: folder.appendingPathComponent("transcript.json"), options: .atomic)
        try markdown(done, lines: lines).write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        Log.trace("Recorder: transcript of “\(record.title)”: \(lines.count) lines, \(dropped) words heard again left out")
        return done
    }

    /// `transcript.md`, with the line saying when, how long, which language.
    static func markdown(_ record: MeetingRecord, lines: [TranscriptLine]) -> String {
        MeetingTranscript.markdown(title: record.title, about: about(record), lines: lines, names: record.speakers)
    }

    /// "Wednesday 22 October 2026, 14:00 · 32 min · English".
    static func about(_ record: MeetingRecord) -> String {
        let when = record.started.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        return [when, length(record.seconds), shortName(of: record.language)].joined(separator: " · ")
    }

    /// "45 s", "32 min", "1 h 05".
    static func length(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole) s" }
        if whole < 3600 { return "\(whole / 60) min" }
        return String(format: "%d h %02d", whole / 3600, whole / 60 % 60)
    }

    /// macOS's model for the language, downloaded the first time.
    private static func install(_ locale: Locale, step: @Sendable (Step) -> Void) async throws {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        step(.downloading(shortName(of: locale.identifier(.bcp47))))
        try await request.downloadAndInstall()
    }

    /// One track's phrases: each of the engine's results, its words with
    /// their times in the track.
    static func phrases(of url: URL, locale: Locale, progress: @escaping @Sendable (Double) -> Void) async throws -> [[TranscriptWord]] {
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        guard seconds > 0.2 else { return [] }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        let results = transcriber.results
        let collect = Task { () throws -> [[TranscriptWord]] in
            var phrases: [[TranscriptWord]] = []
            for try await result in results where result.isFinal {
                let text = result.text
                var words: [TranscriptWord] = []
                for run in text.runs {
                    let piece = String(text[run.range].characters)
                    guard let range = run.audioTimeRange, !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    words.append(TranscriptWord(piece.trimmingCharacters(in: .whitespacesAndNewlines), start: range.start.seconds, end: range.end.seconds))
                }
                if !words.isEmpty { phrases.append(words) }
                progress(min(1, result.range.end.seconds / seconds))
            }
            return phrases
        }
        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        } catch {
            collect.cancel()
            throw error
        }
        let phrases = try await collect.value
        progress(1)
        return phrases
    }
}
