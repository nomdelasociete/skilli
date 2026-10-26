import AVFoundation
import Foundation
import SkilliCore
import Speech

/// A recording's transcript, made on this Mac at Stop (docs/meeting-recorder.md,
/// "Transcription"): macOS's `SpeechTranscriber`, given no names (it reads
/// none: Measured), each track alone, every word with its time. Then the
/// other side's words the microphone heard again are taken out of the
/// user's (no headphones), the voices of the track that holds several
/// people told apart (SpeakerKit, in `skil.li Transcriber`: phase 4), and
/// the tracks become one transcript by time: `transcript.md`,
/// `transcript.json`. Audio never leaves the Mac; macOS downloads a
/// language's model once.
enum MeetingTranscriber {
    static let engine = TranscriptEngine.macOS.rawValue

    /// The share of the progress the voices take, when a track is split
    /// (SpeakerKit runs at about 380 times real time: Measured).
    private static let voicesShare = 0.15

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
    /// first this Mac can transcribe (macOS's engine, or Better
    /// transcription once downloaded); none: the first asked, kept as it is
    /// (the transcript waits).
    @MainActor
    static func defaultLanguage(asked: String) async -> String {
        let wanted = [asked, VoiceInput.keyboardLanguage, Locale.preferredLanguages.first].compactMap { $0 }.filter { !$0.isEmpty }
        for identifier in wanted {
            if let locale = await locale(for: identifier) { return locale.identifier(.bcp47) }
            if BetterTranscription.isReady(), WhisperTranscript.code(for: identifier) != nil { return identifier }
        }
        return wanted.first ?? "en-US"
    }

    /// macOS's engine's locale for a language, nil when it cannot
    /// transcribe it on this Mac.
    static func locale(for identifier: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }

    /// Every language this Mac transcribes, by name: macOS's engine's,
    /// and Better transcription's once downloaded.
    static func languages() async -> [(id: String, name: String)] {
        let apple = await languages(for: .macOS)
        guard BetterTranscription.isReady() else { return apple }
        let codes = Set(apple.compactMap { Locale(identifier: $0.id).language.languageCode?.identifier })
        return (apple + (await languages(for: .whisper)).filter { !codes.contains($0.id) }).sorted { $0.name < $1.name }
    }

    /// The languages one engine transcribes on this Mac, by name.
    static func languages(for engine: TranscriptEngine) async -> [(id: String, name: String)] {
        switch engine {
        case .macOS:
            let locales = await SpeechTranscriber.supportedLocales
            return locales.map { ($0.identifier(.bcp47), name(of: $0.identifier(.bcp47))) }.sorted { $0.name < $1.name }
        case .whisper:
            return WhisperTranscript.languages.map { ($0, name(of: $0)) }.sorted { $0.name < $1.name }
        }
    }

    /// `language` among `languages` (the same id, or Better
    /// transcription's code for it: "it-IT" in its "it", "nb-NO" in its
    /// "no").
    static func canTranscribe(_ language: String, in languages: [(id: String, name: String)]) -> Bool {
        let code = WhisperTranscript.code(for: language)
        return languages.contains { $0.id == language || ($0.id == code && !$0.id.contains("-")) }
    }

    /// What the engines need besides the recording: the default, whether
    /// Better transcription is downloaded, the contacts' names for its
    /// prompt.
    struct Setup: Sendable {
        var standard: TranscriptEngine = .macOS
        var whisperReady = false
        var contacts: [String] = []
    }

    /// The engine a transcript is made with (docs/meeting-recorder.md,
    /// "A language this Mac cannot transcribe"): the one picked, as picked,
    /// or a failure saying why it cannot be; none picked, the default,
    /// then the others, the first that has the language.
    static func engine(for language: String, picked: TranscriptEngine?, setup: Setup) async throws -> TranscriptEngine {
        func has(_ engine: TranscriptEngine) async -> Bool {
            switch engine {
            case .macOS: await locale(for: language) != nil
            case .whisper: setup.whisperReady && WhisperTranscript.code(for: language) != nil
            }
        }
        if let picked {
            if picked == .whisper, !setup.whisperReady {
                throw Failure(message: "Better transcription isn't downloaded: Settings → Recorder offers it.")
            }
            guard await has(picked) else {
                throw Failure(message: "\(name(of: language)) can't be transcribed by \(picked.title) on this Mac.")
            }
            return picked
        }
        for engine in TranscriptEngine.order(standard: setup.standard, whisperReady: setup.whisperReady) {
            if await has(engine) { return engine }
        }
        throw Failure(message: "\(name(of: language)) can't be transcribed on this Mac yet.")
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
    static func transcribe(_ folder: URL, record: MeetingRecord, picked: TranscriptEngine? = nil, setup: Setup = Setup(),
                           step: @escaping @Sendable (Step) -> Void) async throws -> MeetingRecord {
        let engine = try await self.engine(for: record.language, picked: picked, setup: setup)
        let locale = await locale(for: record.language)
        if engine == .macOS, let locale { try await install(locale, step: step) }
        let prompt = WhisperTranscript.prompt(attendees: record.attendees, contacts: setup.contacts, language: record.language)
        let words: @Sendable (URL, @escaping @Sendable (Double) -> Void) async throws -> [[TranscriptWord]] = { url, progress in
            switch engine {
            case .macOS:
                guard let locale else { return [] }
                return try await phrases(of: url, locale: locale, progress: progress)
            case .whisper:
                guard let run = try await TranscriberHelper.whisper(of: url, language: WhisperTranscript.code(for: record.language) ?? "en",
                                                                     prompt: prompt, progress: progress) else {
                    throw Failure(message: "This build has no Better transcription.")
                }
                return WhisperTranscript.phrases(of: run, attendees: record.attendees)
            }
        }
        let me = folder.appendingPathComponent(Speaker.me.file), them = folder.appendingPathComponent(Speaker.them.file)
        // A track never on (in person, the Mac's sound) is silence: left out.
        let unused = Set(record.unused ?? [])
        let lengths = [(Speaker.me, me), (.them, them)].map { speaker, url in
            unused.contains(speaker) ? 0 : (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        }
        let total = max(1, lengths.reduce(0, +))
        let split = splitTrack(record)
        let share = split == nil ? 1 : 1 - voicesShare
        step(.transcribing(0))
        let mine = unused.contains(.me) ? [] : try await words(me) { done in step(.transcribing(share * done * lengths[0] / total)) }
        let theirs = unused.contains(.them) ? [] : try await words(them) { done in step(.transcribing(share * (lengths[0] + done * lengths[1]) / total)) }
        let (kept, dropped) = MeetingTranscript.droppingEcho(mine, heard: theirs.flatMap { $0 })
        var voiced = kept.map { (Voice.me, $0) } + theirs.map { (Voice.them, $0) }
        var names = MeetingVoices.names(of: [.me, .them])
        if let split {
            let phrases = split == .me ? kept : theirs
            let id: (Int) -> Voice = split == .me ? { Voice.single($0) } : { Voice.them($0) }
            let track = folder.appendingPathComponent(split.file)
            let wordsDone: Double = share
            let progress: @Sendable (Double) -> Void = { done in step(.transcribing(wordsDone + (1 - wordsDone) * done)) }
            let stretches = await voices(of: track, progress: progress)
            var (told, found) = MeetingVoices.split(phrases, stretches: stretches ?? [], id: id)
            // In person, one voice alone stays the room's (Me's lane, "Room").
            if split == .me, found.count == 1, record.imported == nil {
                told = told.map { (Voice.me, $0.1) }
                found = [.me]
            }
            voiced = (split == .me ? [] : kept.map { (Voice.me, $0) }) + told
            names = MeetingVoices.names(of: found)
        }
        let lines = MeetingTranscript.lines(voiced)
        var done = record
        done.state = .done
        done.engine = engine.rawValue
        done.echoDropped = dropped
        done.recorder = nil
        done.edited = nil
        done.speakers = MeetingVoices.keepingGiven(record.speakers, fresh: names.merging([Voice.me.rawValue: Speaker.me.title]) { a, _ in a })
        let file = MeetingTranscript.File(language: record.language, engine: engine.rawValue, lines: lines)
        try file.encoded().write(to: folder.appendingPathComponent("transcript.json"), options: .atomic)
        try markdown(done, lines: lines).write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        Log.trace("Recorder: transcript of “\(record.title)” (\(engine.rawValue)): \(lines.count) lines, \(dropped) words heard again left out")
        return done
    }

    /// The track whose voices are told apart: in a call, the Mac's sound
    /// (the microphone is the user); in person and in an import, the one
    /// track. Nil when neither is used.
    static func splitTrack(_ record: MeetingRecord) -> Speaker? {
        let unused = Set(record.unused ?? [])
        if unused.contains(.them) { return unused.contains(.me) ? nil : .me }
        return .them
    }

    /// A track's voices (SpeakerKit, in `skil.li Transcriber`); nil when
    /// they could not be told apart (the track then stays one voice).
    private static func voices(of track: URL, progress: @escaping @Sendable (Double) -> Void) async -> [MeetingVoices.Stretch]? {
        do {
            return try await TranscriberHelper.voices(of: track, progress: progress)
        } catch {
            Log.actions.error("Recorder: voices not told apart in \(track.lastPathComponent, privacy: .public) (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    /// `transcript.md`, with the line saying when, how long, which language.
    static func markdown(_ record: MeetingRecord, lines: [TranscriptLine]) -> String {
        MeetingTranscript.markdown(title: record.title, about: about(record), lines: lines, names: record.speakers)
    }

    /// "Wednesday 22 October 2026, 14:00 · 32 min · English · with Paul,
    /// Anna and 2 others"; an import starts with "Imported from Board
    /// call.m4a".
    static func about(_ record: MeetingRecord) -> String {
        let when = record.started.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        let people = MeetingPeople.sentence(record.attendees)
        let source = record.imported.map { ["Imported from \($0)"] } ?? []
        return (source + [when, length(record.seconds), shortName(of: record.language)] + (people.isEmpty ? [] : ["with \(people)"]))
            .joined(separator: " · ")
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
