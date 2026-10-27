import Foundation

/// A word the engine heard, with where it is in its track (seconds).
public struct TranscriptWord: Codable, Equatable, Sendable {
    /// As written, its punctuation kept ("okay?").
    public var text: String
    public var start: Double
    public var end: Double

    public init(_ text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case text = "w", start = "s", end = "e"
    }

    /// Its middle: the moment it is said.
    public var time: Double { (start + end) / 2 }
}

/// Who said a line (docs/meeting-recorder-views.md, phase 4): the user
/// (`me`, the microphone in a call); a voice of the other side (`them`,
/// `them2`…: the Mac's sound, told apart by SpeakerKit); a voice of a
/// recording's one track (`s1`, `s2`…: in person, an import). Its id in
/// `transcript.json`; its name in `meeting.json`'s `speakers`.
public struct Voice: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let me: Voice = "me"
    public static let them: Voice = "them"

    /// The other side's `number`th voice, by the order they first speak:
    /// `them`, `them2`, `them3`…
    public static func them(_ number: Int) -> Voice {
        number <= 1 ? .them : Voice(rawValue: "them\(number)")
    }

    /// A one-track recording's `number`th voice: `s1`, `s2`…
    public static func single(_ number: Int) -> Voice {
        Voice(rawValue: "s\(number)")
    }

    /// The track it is heard on: the Mac's sound for the other side's
    /// voices, the microphone (or the one track) for the rest.
    public var track: Speaker {
        rawValue.hasPrefix(Speaker.them.rawValue) ? .them : .me
    }

    /// Its name until the user gives one: "Me", "Them", "Them 2",
    /// "Speaker 1" (`meeting.json` holds the names given, and those
    /// written as the voices were found).
    public var title: String {
        if self == .me { return Speaker.me.title }
        if self == .them { return Speaker.them.title }
        if rawValue.hasPrefix("them"), let number = Int(rawValue.dropFirst(4)) { return "\(Speaker.them.title) \(number)" }
        if rawValue.hasPrefix("s"), let number = Int(rawValue.dropFirst()) { return "Speaker \(number)" }
        return rawValue
    }
}

/// A line of the transcript: one speaker, from one moment to another.
public struct TranscriptLine: Codable, Equatable, Sendable {
    public var speaker: Voice
    public var start: Double
    public var end: Double
    public var words: [TranscriptWord]

    public init(speaker: Voice, words: [TranscriptWord]) {
        self.speaker = speaker
        self.words = words
        start = words.first?.start ?? 0
        end = words.last?.end ?? 0
    }

    public var text: String { MeetingTranscript.joined(words) }
}

/// What the recording's two tracks became, put together
/// (docs/meeting-recorder.md, "Who spoke", "No headphones"). Pure parts.
public enum MeetingTranscript {
    /// `transcript.json`: every line and its words with their times.
    public struct File: Codable, Equatable, Sendable {
        /// 2: a line's speaker is any voice (phase 4); 1 held `me` and
        /// `them` only, and reads the same.
        public var version = 2
        public var language: String
        public var engine: String
        public var lines: [TranscriptLine]

        public init(language: String, engine: String, lines: [TranscriptLine]) {
            self.language = language
            self.engine = engine
            self.lines = lines
        }

        public func encoded() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(self)
        }

        public static func decode(_ data: Data) throws -> File {
            try JSONDecoder().decode(File.self, from: data)
        }
    }

    // MARK: - No headphones

    /// The microphone's words the Mac's sound already has: without
    /// headphones the microphone hears the other side again from the
    /// speakers. A word of `phrases` (the microphone's) goes when `heard`
    /// (the Mac's sound) has the same word from `before` s before it to
    /// `after` s after, in runs of `run` such words or more: a lone "yes"
    /// the user says stays. The rule and its window were set before the
    /// measurement (Measured, "No headphones": 3 % of the other side left,
    /// at most 1.5 % of the user's words taken). Punctuation alone goes
    /// with the word before it. Returns the phrases left (empty ones out)
    /// and how many words went.
    public static func droppingEcho(_ phrases: [[TranscriptWord]], heard: [TranscriptWord], before: Double = 0.5, after: Double = 2.0,
                                    run: Int = 2) -> (kept: [[TranscriptWord]], dropped: Int) {
        // The Mac's words by their folded text, each with its times, sorted.
        var times: [String: [Double]] = [:]
        for word in heard {
            let key = folded(word.text)
            if !key.isEmpty { times[key, default: []].append(word.time) }
        }
        for key in times.keys { times[key]?.sort() }
        func isHeard(_ word: TranscriptWord) -> Bool {
            let key = folded(word.text)
            guard !key.isEmpty, let list = times[key] else { return false }
            // The Mac's word at `t` takes the microphone's from t - before to t + after.
            let low = word.time - after, high = word.time + before
            var lo = 0, hi = list.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if list[mid] < low { lo = mid + 1 } else { hi = mid }
            }
            return lo < list.count && list[lo] <= high
        }
        // Across phrases: a run goes on from one phrase to the next.
        let flat = phrases.flatMap { $0 }
        let isWord = flat.map { !folded($0.text).isEmpty }
        let hit = flat.map(isHeard)
        var drop = [Bool](repeating: false, count: flat.count)
        var index = 0
        while index < flat.count {
            guard isWord[index], hit[index] else {
                index += 1
                continue
            }
            // A run of heard words, punctuation inside it carried along.
            var end = index, words = 0
            while end < flat.count, !isWord[end] || hit[end] {
                if isWord[end] { words += 1 }
                end += 1
            }
            if words >= run {
                for k in index..<end { drop[k] = true }
            }
            index = end
        }
        // Punctuation alone goes with the word before it.
        for k in flat.indices where !isWord[k] && k > 0 && drop[k - 1] { drop[k] = true }
        var kept: [[TranscriptWord]] = []
        var offset = 0
        for phrase in phrases {
            let left = phrase.indices.filter { !drop[offset + $0] }.map { phrase[$0] }
            offset += phrase.count
            if left.contains(where: { !folded($0.text).isEmpty }) { kept.append(left) }
        }
        return (kept, drop.enumerated().filter { $0.element && isWord[$0.offset] }.count)
    }

    // MARK: - Lines

    /// The two tracks' phrases as one transcript, by time: a phrase starts
    /// a line, or carries on the speaker's line before it when nobody else
    /// spoke in between, it follows within `gap` s and the line stays under
    /// `longest` s. Someone talking over the other starts a line of their
    /// own where they start.
    public static func lines(me: [[TranscriptWord]], them: [[TranscriptWord]], gap: Double = 1.5, longest: Double = 60) -> [TranscriptLine] {
        lines(me.map { (Voice.me, $0) } + them.map { (Voice.them, $0) }, gap: gap, longest: longest)
    }

    /// Every voice's phrases as one transcript, by time (`lines(me:them:)`'s
    /// rule): the user's first when two start together.
    public static func lines(_ voiced: [(Voice, [TranscriptWord])], gap: Double = 1.5, longest: Double = 60) -> [TranscriptLine] {
        let phrases = voiced.enumerated()
            .filter { !$0.element.1.isEmpty }
            .sorted { a, b in
                let (startA, startB) = (a.element.1.first?.start ?? 0, b.element.1.first?.start ?? 0)
                if startA != startB { return startA < startB }
                let (meA, meB) = (a.element.0 == .me ? 0 : 1, b.element.0 == .me ? 0 : 1)
                return meA != meB ? meA < meB : a.offset < b.offset
            }
            .map(\.element)
        var lines: [TranscriptLine] = []
        for (speaker, words) in phrases {
            if var last = lines.last, last.speaker == speaker, let first = words.first, first.start - last.end <= gap,
               (words.last?.end ?? first.end) - last.start <= longest {
                last.words += words
                last.end = max(last.end, words.last?.end ?? last.end)
                lines[lines.count - 1] = last
            } else {
                lines.append(TranscriptLine(speaker: speaker, words: words))
            }
        }
        return lines
    }

    /// Each chapter by the line it starts on: the first line started at
    /// its start or after (a chapter past the last line is left out).
    public static func chapterLines(_ chapters: [MeetingRecord.Chapter], in lines: [TranscriptLine]) -> [Int: MeetingRecord.Chapter] {
        var starts: [Int: MeetingRecord.Chapter] = [:]
        for chapter in chapters {
            guard let line = lines.firstIndex(where: { $0.start >= chapter.start - 0.001 }), starts[line] == nil else { continue }
            starts[line] = chapter
        }
        return starts
    }

    /// The line playing at `time`: the last one started by then.
    public static func line(at time: Double, in lines: [TranscriptLine]) -> Int? {
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : lo - 1
    }

    // MARK: - Text

    /// `transcript.md`: the title, a line saying when, how long and in
    /// which language (`about`), then each line under its speaker's name
    /// and its time, a chapter's heading before the line it starts on.
    public static func markdown(title: String, about: String, lines: [TranscriptLine], names: [String: String] = [:],
                                chapters: [MeetingRecord.Chapter] = []) -> String {
        var text = "# \(title)\n\n\(about)\n"
        let starts = chapterLines(chapters, in: lines)
        for (index, line) in lines.enumerated() {
            if let chapter = starts[index] { text += "\n## \(chapter.title)\n" }
            let name = names[line.speaker.rawValue] ?? line.speaker.title
            text += "\n**\(name)** · \(clock(line.start))\n\(line.text)\n"
        }
        return text
    }

    /// "0:04", "12:04", "1:02:03".
    public static func clock(_ seconds: Double) -> String {
        // Never a crash on a time no recording has (a link's).
        let whole = seconds.isFinite ? Int(min(max(seconds, 0), 1e9).rounded(.down)) : 0
        return whole >= 3600 ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
            : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The words as one text: a space between them, none before
    /// punctuation that ends or follows a word ("okay?", "Paul,").
    public static func joined(_ words: [TranscriptWord]) -> String {
        var text = ""
        for word in words {
            let piece = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            let attaches = piece.first.map { ",.;:!?…)]}%".contains($0) || $0 == "'" || $0 == "’" } ?? false
            if !text.isEmpty, !attaches { text += " " }
            text += piece
        }
        return text
    }

    /// A word as it is matched: lowercase, accents and punctuation aside
    /// ("Okay," and "okay" are one word); empty for punctuation alone.
    public static func folded(_ text: String) -> String {
        let lowered = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(String.UnicodeScalarView(lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
}
