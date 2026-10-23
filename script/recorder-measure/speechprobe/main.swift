// Measurement probe, not app code: transcribes an audio file with macOS's
// SpeechTranscriber or DictationTranscriber and writes the words with
// their times as JSON.
//
//   speechprobe --engine st|dt --locale fr_FR --file call.wav --out out.json [--words names.txt] [--install|--install-only]
import AVFoundation
import Foundation
import Speech

struct Word: Codable { let w: String; let start: Double; let end: Double }
struct Output: Codable {
    let engine: String
    let locale: String
    let file: String
    let audioSeconds: Double
    let wallSeconds: Double
    let contextualStrings: Int
    let maxRSSMB: Double
    let text: String
    let words: [Word]
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), a.indices.contains(i + 1) else { return nil }
    return a[i + 1]
}

func maxRSSMB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576 // bytes on macOS
}

@main
enum Probe {
    static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write(Data("speechprobe: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let engine = arg("--engine") ?? "st"
        let localeID = arg("--locale") ?? "en_US"
        guard let path = arg("--file"), let out = arg("--out") else {
            FileHandle.standardError.write(Data("usage: speechprobe --engine st|dt --locale fr_FR --file in.wav --out out.json [--words names.txt] [--install|--install-only]\n".utf8))
            exit(2)
        }
        let words: [String] = try arg("--words").map {
            try String(contentsOfFile: $0, encoding: .utf8).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } ?? []

        let module: any SpeechModule
        let collect: () -> Task<[(String, Double, Double)], Error>
        switch engine {
        case "st":
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else { throw NSError(domain: "no locale", code: 1) }
            let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            module = t
            collect = { Task { try await gather(t.results) { ($0.text, $0.isFinal) } } }
        case "dt":
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else { throw NSError(domain: "no locale", code: 1) }
            let t = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [], attributeOptions: [.audioTimeRange])
            module = t
            collect = { Task { try await gather(t.results) { ($0.text, $0.isFinal) } } }
        default:
            throw NSError(domain: "engine st|dt", code: 2)
        }

        let status = await AssetInventory.status(forModules: [module])
        if status != .installed {
            guard CommandLine.arguments.contains("--install") || CommandLine.arguments.contains("--install-only") else {
                throw NSError(domain: "model not installed (\(status)); run with --install", code: 3)
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                FileHandle.standardError.write(Data("installing the \(localeID) model…\n".utf8))
                try await request.downloadAndInstall()
            }
        }
        if CommandLine.arguments.contains("--install-only") { print("installed"); return }

        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let audioSeconds = Double(file.length) / file.processingFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        if !words.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = words
            try await analyzer.setContext(context)
        }
        let started = Date()
        let results = collect()
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let runs = try await results.value
        let wall = Date().timeIntervalSince(started)

        let output = Output(engine: engine, locale: localeID, file: path, audioSeconds: audioSeconds, wallSeconds: wall,
                            contextualStrings: words.count, maxRSSMB: maxRSSMB(),
                            text: runs.map(\.0).joined(),
                            words: runs.map { Word(w: $0.0, start: $0.1, end: $0.2) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(output).write(to: URL(fileURLWithPath: out))
        print(String(format: "%@ %@ %.0fs audio in %.1fs (x%.0f), %d words, rss %.0f MB", engine, localeID, audioSeconds, wall, audioSeconds / wall, runs.count, maxRSSMB()))
    }

    /// Every run of the final results' text with its audio time range.
    static func gather<S: AsyncSequence>(_ results: S, _ parts: @escaping (S.Element) -> (AttributedString, Bool)) async throws -> [(String, Double, Double)] {
        var out: [(String, Double, Double)] = []
        for try await result in results {
            let (text, isFinal) = parts(result)
            guard isFinal else { continue }
            for run in text.runs {
                let piece = String(text[run.range].characters)
                if let range = run.audioTimeRange {
                    out.append((piece, range.start.seconds, range.end.seconds))
                } else {
                    out.append((piece, -1, -1))
                }
            }
        }
        return out
    }
}
