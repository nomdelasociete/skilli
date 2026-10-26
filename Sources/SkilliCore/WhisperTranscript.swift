import Foundation

/// Better transcription's engine, whisper large-v3-turbo (docs/meeting-recorder.md,
/// "Transcription"; docs/meeting-recorder-views.md, phase 4, "The engine
/// at work"): what `skil.li Transcriber` hands back, made words; the two
/// failures Measured found taken out; the names given as its prompt; the
/// languages it has. Pure parts.
public enum WhisperTranscript {
    /// A token as whisper.cpp gives it: its bytes (a character may be cut
    /// between two tokens), its time on the recording's clock (its VAD's
    /// cuts added back by whisper.cpp), in seconds.
    public struct Token: Codable, Equatable, Sendable {
        public var bytes: [UInt8]
        public var start: Double
        public var end: Double

        public init(_ bytes: [UInt8], start: Double, end: Double) {
            self.bytes = bytes
            self.start = start
            self.end = end
        }

        public init(_ text: String, start: Double, end: Double) {
            self.init(Array(text.utf8), start: start, end: end)
        }
    }

    /// A segment of whisper's, its tokens (special ones left out).
    public struct Segment: Codable, Equatable, Sendable {
        public var tokens: [Token]

        public init(tokens: [Token]) {
            self.tokens = tokens
        }
    }

    /// What `skil.li Transcriber whisper` writes.
    public struct Run: Codable, Equatable, Sendable {
        public var segments: [Segment]

        public init(segments: [Segment]) {
            self.segments = segments
        }
    }

    // MARK: - Words

    /// A segment's words: a token that starts with a space starts a word,
    /// the others (the rest of a word, punctuation) carry it on; each word's
    /// text from its tokens' bytes together, its time from its first
    /// token's start to its last's end. Empty words go.
    public static func words(of segment: Segment) -> [TranscriptWord] {
        var words: [TranscriptWord] = []
        var bytes: [UInt8] = []
        var start = 0.0, end = 0.0
        func close() {
            let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { words.append(TranscriptWord(text, start: start, end: max(end, start))) }
            bytes = []
        }
        for token in segment.tokens {
            if token.bytes.first == 0x20 || bytes.isEmpty {
                close()
                start = token.start
            }
            bytes += token.bytes
            end = token.end
        }
        close()
        return words
    }

    /// The run as phrases (a segment each, its words), whisper's two
    /// measured failures taken out (Measured: 10.8 → 10.4 errors per
    /// hundred words): a segment the same as the one before it (whisper
    /// looping, up to 52 times in a track), and an attendee's name written
    /// as a speaker label ("Camille Kerjean : …").
    public static func phrases(of run: Run, attendees: [String]) -> [[TranscriptWord]] {
        var phrases: [[TranscriptWord]] = []
        var before: String?
        for segment in run.segments {
            let words = self.words(of: segment)
            let text = MeetingTranscript.joined(words)
            defer { before = text }
            guard text != before else { continue }
            let kept = withoutLabels(words, attendees: attendees)
            if kept.contains(where: { !MeetingTranscript.folded($0.text).isEmpty }) { phrases.append(kept) }
        }
        return phrases
    }

    /// `words` without an attendee's name followed by a colon (the name's
    /// last word ending with ":", or a ":" after it), case and accents
    /// aside.
    public static func withoutLabels(_ words: [TranscriptWord], attendees: [String]) -> [TranscriptWord] {
        let names = attendees.map { $0.split(whereSeparator: \.isWhitespace).map { MeetingTranscript.folded(String($0)) }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return words }
        var kept: [TranscriptWord] = []
        var index = 0
        outer: while index < words.count {
            for name in names where index + name.count <= words.count {
                guard zip(name, words[index..<(index + name.count)]).allSatisfy({ $0 == MeetingTranscript.folded($1.text) }) else { continue }
                if words[index + name.count - 1].text.hasSuffix(":") {
                    index += name.count
                    continue outer
                }
                if index + name.count < words.count, words[index + name.count].text.hasPrefix(":"),
                   MeetingTranscript.folded(words[index + name.count].text).isEmpty {
                    index += name.count + 1
                    continue outer
                }
            }
            kept.append(words[index])
            index += 1
        }
        return kept
    }

    // MARK: - The names, its prompt

    /// The longest prompt (Measured: 450 characters, about 20 contacts
    /// after the attendees).
    public static let longestPrompt = 450

    /// whisper's prompt: the attendees, then the contacts no attendee is,
    /// as many as fit in 450 characters ("Attendees: Paul Arnaud, Anna
    /// Lindqvist. Also: Margot Martin."; in French "Participants : …
    /// Aussi : …."). Empty when there is no name.
    public static func prompt(attendees: [String], contacts: [String], language: String) -> String {
        let french = Locale(identifier: language).language.languageCode?.identifier == "fr"
        let (head, also) = french ? ("Participants : ", "Aussi : ") : ("Attendees: ", "Also: ")
        let fold = { (name: String) in name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        var seen: Set<String> = []
        func fitting(_ names: [String], after start: String, head: String) -> [String] {
            var kept: [String] = []
            for name in names.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty && !seen.contains(fold(name)) {
                guard (start + head + (kept + [name]).joined(separator: ", ") + ".").count <= longestPrompt else { break }
                seen.insert(fold(name))
                kept.append(name)
            }
            return kept
        }
        let people = fitting(attendees, after: "", head: head)
        var prompt = people.isEmpty ? "" : head + people.joined(separator: ", ") + "."
        let start = prompt.isEmpty ? "" : prompt + " "
        let others = fitting(contacts, after: start, head: also)
        if !others.isEmpty { prompt = start + also + others.joined(separator: ", ") + "." }
        return prompt
    }

    // MARK: - Languages

    /// The languages whisper transcribes (whisper.cpp's list), by code.
    public static let languages: [String] = """
        en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms cs ro da hu ta no th ur hr bg lt la mi ml cy sk te fa \
        lv bn sr az sl kn et mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so af oc ka be tg sd gu am yi lo uz fo ht ps tk nn \
        mt sa lb my bo tl mg as tt haw ln ha ba jw su yue
        """.split(whereSeparator: \.isWhitespace).map(String.init)

    /// whisper's code for a language ("en-US" → "en"); nil when whisper
    /// has none.
    public static func code(for language: String) -> String? {
        guard var code = Locale(identifier: language).language.languageCode?.identifier else { return nil }
        // Norwegian Bokmål is whisper's "no", Javanese its "jw".
        if code == "nb" { code = "no" }
        if code == "jv" { code = "jw" }
        return languages.contains(code) ? code : nil
    }
}

/// Better transcription's download (docs/meeting-recorder-views.md, phase
/// 4): what its row says while it comes. Pure parts.
public enum ModelDownload {
    /// "412 MB", "1.6 GB": a size as the row says it.
    public static func size(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes >= 999.5 { return String(format: "%.1f GB", megabytes / 1000) }
        return "\(Int(megabytes.rounded())) MB"
    }

    /// "412 MB of 1.6 GB · about 3 min left" (the time once the speed is
    /// known: less than a minute, then minutes).
    public static func progress(received: Int64, total: Int64, bytesPerSecond: Double?) -> String {
        var line = "\(size(received)) of \(size(total))"
        if let bytesPerSecond, bytesPerSecond > 0, total > received {
            let seconds = Double(total - received) / bytesPerSecond
            line += seconds < 60 ? " · less than a minute left" : " · about \(Int((seconds / 60).rounded())) min left"
        }
        return line
    }

    /// The room a download of `needed` bytes wants: itself and 100 MB.
    public static func wanted(_ needed: Int64) -> Int64 {
        needed + 100_000_000
    }

    /// "1.7 GB free needed on this Mac: 0.9 GB left." when `available`
    /// cannot hold `needed` and 100 MB more; nil when it can.
    public static func roomLine(needed: Int64, available: Int64) -> String? {
        guard available < wanted(needed) else { return nil }
        return "\(size(wanted(needed))) free needed on this Mac: \(size(available)) left."
    }
}
