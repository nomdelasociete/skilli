import Foundation

/// The voices of a recording (docs/meeting-recorder-views.md, phase 4):
/// a track that holds several people told apart by SpeakerKit, each word
/// given to the voice heard at its time; the speakers' names, renamed and
/// merged by the user. Pure parts.
public enum MeetingVoices {
    /// A stretch of one voice in a track, as the speaker separation found
    /// it: the voice's number there (any, in no order), from, to (s).
    public struct Stretch: Codable, Equatable, Sendable {
        public var voice: Int
        public var start: Double
        public var end: Double

        public init(voice: Int, start: Double, end: Double) {
            self.voice = voice
            self.start = start
            self.end = end
        }
    }

    // MARK: - Words to voices

    /// One track's phrases given to its voices: each word to the voice
    /// whose stretch holds its middle (two do: the one that holds more of
    /// the word); none does: the nearest within `reach` s; else the voice
    /// of the words around it. A lone word between two of another voice
    /// goes with them (a stretch's edge is not a turn). A phrase is cut
    /// where the voice changes. The voices are numbered by their first
    /// word (1, 2…), and `id` names each; no stretch at all: one voice.
    /// Returns the phrases, in order, and the voices found, in that order.
    public static func split(_ phrases: [[TranscriptWord]], stretches: [Stretch], reach: Double = 1.0,
                             id: (Int) -> Voice) -> (phrases: [(Voice, [TranscriptWord])], voices: [Voice]) {
        let words = phrases.flatMap { $0 }
        guard !words.isEmpty else { return ([], []) }
        let sorted = stretches.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var heard: [Int?] = words.map { voice(at: $0, in: sorted, reach: reach) }
        // Words no stretch reaches: the voice of the words before, else after.
        var last: Int?
        for index in heard.indices {
            if let voice = heard[index] { last = voice } else { heard[index] = last }
        }
        var next: Int?
        for index in heard.indices.reversed() {
            if let voice = heard[index] { next = voice } else { heard[index] = next }
        }
        var voices = heard.map { $0 ?? 0 }
        // A lone word between two of the same other voice, inside a phrase.
        var offset = 0
        for phrase in phrases {
            if phrase.count >= 3 {
                for index in (offset + 1)..<(offset + phrase.count - 1)
                where voices[index - 1] == voices[index + 1] && voices[index] != voices[index - 1] {
                    voices[index] = voices[index - 1]
                }
            }
            offset += phrase.count
        }
        // Numbered as they first speak.
        var number: [Int: Int] = [:]
        for voice in voices where number[voice] == nil { number[voice] = number.count + 1 }
        let found = number.sorted { $0.value < $1.value }.map { id($0.value) }
        var split: [(Voice, [TranscriptWord])] = []
        offset = 0
        for phrase in phrases {
            var current: (Voice, [TranscriptWord])?
            for (index, word) in phrase.enumerated() {
                let voice = id(number[voices[offset + index]] ?? 1)
                if let open = current, open.0 == voice {
                    current?.1.append(word)
                } else {
                    if let open = current { split.append(open) }
                    current = (voice, [word])
                }
            }
            if let open = current { split.append(open) }
            offset += phrase.count
        }
        return (split, found)
    }

    /// The voice heard at a word's time, nil when none is within reach.
    private static func voice(at word: TranscriptWord, in stretches: [Stretch], reach: Double) -> Int? {
        let middle = word.time
        var best: (voice: Int, overlap: Double)?
        var nearest: (voice: Int, distance: Double)?
        for stretch in stretches {
            if stretch.start > middle + reach { break }
            if stretch.start <= middle, middle <= stretch.end {
                let overlap = min(stretch.end, word.end) - max(stretch.start, word.start)
                if best == nil || overlap > best!.overlap { best = (stretch.voice, overlap) }
            } else {
                let distance = middle < stretch.start ? stretch.start - middle : middle - stretch.end
                if distance <= reach, nearest == nil || distance < nearest!.distance { nearest = (stretch.voice, distance) }
            }
        }
        return best?.voice ?? nearest?.voice
    }

    // MARK: - Names

    /// The names voices start with (docs/meeting-recorder-views.md, "Names
    /// until the user gives one"): the other side's, "Them" alone, else
    /// "Them 1", "Them 2"…; a one-track recording's, "Speaker 1",
    /// "Speaker 2"….
    public static func names(of voices: [Voice]) -> [String: String] {
        let others = voices.filter { $0 != .me && $0.track == .them }
        var names: [String: String] = [:]
        for voice in voices where voice != .me {
            if voice.track == .them {
                names[voice.rawValue] = others.count == 1 ? Speaker.them.title
                    : "\(Speaker.them.title) \((others.firstIndex(of: voice) ?? 0) + 1)"
            } else {
                names[voice.rawValue] = voice.title
            }
        }
        return names
    }

    /// A name skil.li gave, not the user: "Me", "Them", "Them 2",
    /// "Speaker 1", "Room", "Sound".
    public static func isStandard(_ name: String) -> Bool {
        let words = name.split(separator: " ")
        switch words.count {
        case 1: return ["Me", "Them", "Room", "Sound"].contains(String(words[0]))
        case 2: return ["Them", "Speaker"].contains(String(words[0])) && Int(words[1]) != nil
        default: return false
        }
    }

    /// The names after a transcript is made again: the voices found named
    /// as they start (`fresh`), except a name the user had given a voice of
    /// the same id, which stays; Me's and the lanes' names (`me`) as they
    /// were.
    public static func keepingGiven(_ previous: [String: String], fresh: [String: String]) -> [String: String] {
        var names = fresh
        for (id, name) in previous where id == Voice.me.rawValue || (fresh[id] != nil && !isStandard(name)) {
            names[id] = name
        }
        return names
    }

    /// The speakers in their order: Me first, then as they first speak.
    public static func order(of lines: [TranscriptLine]) -> [Voice] {
        var order: [Voice] = lines.contains { $0.speaker == .me } ? [.me] : []
        for line in lines where !order.contains(line.speaker) { order.append(line.speaker) }
        return order
    }

    /// The speaker after `voice` in `order` (`step` -1: before), around to
    /// the first; `voice` itself when it is the only one.
    public static func next(after voice: Voice, in order: [Voice], step: Int = 1) -> Voice {
        guard let index = order.firstIndex(of: voice), order.count > 1 else { return order.first ?? voice }
        let count = order.count
        return order[((index + step) % count + count) % count]
    }

    /// A speaker's name as it shows: the one given, else its own.
    public static func name(of voice: Voice, in names: [String: String]) -> String {
        names[voice.rawValue] ?? voice.title
    }

    /// The same name, case, accents and spaces aside.
    public static func sameName(_ a: String, _ b: String) -> Bool {
        let fold = { (text: String) in
            text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return !fold(a).isEmpty && fold(a) == fold(b)
    }

    /// What a rename changed, to undo it: the lines that went to another
    /// speaker (their place, the speaker they had) and the names before.
    public struct Renamed: Equatable, Sendable {
        public var moved: [Int: Voice]
        public var namesBefore: [String: String]
        public var namesAfter: [String: String]
        /// The speaker the renamed one joined, if any.
        public var joined: Voice?
    }

    /// `voice` given `name` (docs/meeting-recorder-views.md, "Rename"):
    /// every line of it renamed. A name another speaker of `lines` has
    /// (case and accents aside) makes the two one: the renamed one's lines
    /// go to the other, which keeps its name. When one of the two is Me, Me
    /// is kept: the user's own name is never given away. A speaker given
    /// `ownName` (the user's, from My Card) joins Me when Me has lines.
    /// Nil when nothing changes.
    public static func rename(_ voice: Voice, to name: String, lines: inout [TranscriptLine], names: inout [String: String],
                              ownName: String? = nil) -> Renamed? {
        let name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty else { return nil }
        let speakers = order(of: lines)
        let before = names
        var target = speakers.first { $0 != voice && sameName(Self.name(of: $0, in: names), name) }
        if target == nil, voice != .me, speakers.contains(.me), let ownName, sameName(ownName, name) { target = .me }
        guard let other = target else {
            guard Self.name(of: voice, in: names) != name else { return nil }
            names[voice.rawValue] = name
            return Renamed(moved: [:], namesBefore: before, namesAfter: names, joined: nil)
        }
        // Me is kept: renamed to another's name, that one's lines join Me
        // under the name given.
        let (gone, kept) = voice == .me ? (other, Voice.me) : (voice, other)
        if voice == .me { names[Voice.me.rawValue] = name }
        var moved: [Int: Voice] = [:]
        for index in lines.indices where lines[index].speaker == gone {
            moved[index] = gone
            lines[index].speaker = kept
        }
        names[gone.rawValue] = nil
        return Renamed(moved: moved, namesBefore: before, namesAfter: names, joined: kept)
    }

    /// The names a speaker is offered, in their order (docs/meeting-recorder-views.md,
    /// "Rename"): for Me, the user's own name first; then the attendees no
    /// speaker has yet; then the names already given (a merge), each once.
    public static func offered(for voice: Voice, lines: [TranscriptLine], names: [String: String], attendees: [String],
                               ownName: String?) -> (fresh: [String], given: [(name: String, voice: Voice)]) {
        let speakers = order(of: lines)
        let given = speakers.filter { $0 != voice }.map { (name: name(of: $0, in: names), voice: $0) }
        var fresh: [String] = []
        func add(_ candidate: String) {
            let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty, !sameName(candidate, name(of: voice, in: names)),
                  !given.contains(where: { sameName($0.name, candidate) }), !fresh.contains(where: { sameName($0, candidate) }) else { return }
            fresh.append(candidate)
        }
        if voice == .me, let ownName { add(ownName) }
        attendees.forEach(add)
        return (fresh, given)
    }
}
