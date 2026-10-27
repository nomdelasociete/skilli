import Foundation

/// A recording's folder (docs/meeting-recorder.md, "Where it lives"): its
/// name is the date and the title, never another recording's.
///
///     ~/Library/Application Support/skil.li/Recordings/2026-10-22 14.00 Weekly sync/
public enum RecordingFolder {
    /// The longest title a folder's name keeps.
    public static let longestTitle = 80

    /// "2026-10-22 14.00 Weekly sync": the date and time it started, then
    /// the title as a folder may hold it (`cleaned`).
    public static func name(title: String, started: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: started)
        let date = String(format: "%04d-%02d-%02d %02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
        return date + " " + cleaned(title)
    }

    /// The title as a folder's name holds it: `/` and `:` become `-`,
    /// control characters go (a line break or a tab as a space, so words
    /// stay apart), and so does a leading dot (a hidden folder); cut at 80
    /// characters. Nothing left: "Meeting".
    public static func cleaned(_ title: String) -> String {
        var text = ""
        for scalar in title.unicodeScalars {
            if scalar == "/" || scalar == ":" {
                text.unicodeScalars.append("-")
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                text.unicodeScalars.append(" ")
            } else if !CharacterSet.controlCharacters.contains(scalar) {
                text.unicodeScalars.append(scalar)
            }
        }
        var words = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while words.first == "." || words.first == " " { words.removeFirst() }
        let cut = String(words.prefix(longestTitle)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? "Meeting" : cut
    }

    /// `name`, else "name 2", "name 3"…: the first that `isTaken` does not
    /// hold. Nothing is ever written into another recording's folder.
    public static func free(_ name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        var number = 2
        while isTaken("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    /// The name a recording starts with when nothing names it: "Meeting
    /// 14:30", the time as this Mac writes it.
    public static func defaultTitle(at date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = timeZone
        format.dateStyle = .none
        format.timeStyle = .short
        return "Meeting " + format.string(from: date)
    }
}

/// "rec Weekly sync" in the launcher: the Record card with that name. The
/// launcher's typed grammar only (Ask reads its own way).
public enum RecordRequest {
    public static let word = "rec"

    /// The name after "rec ", as typed; nil for anything else ("rec"
    /// alone finds Record Meeting by its name).
    public static func name(_ text: String) -> String? {
        let lower = text.lowercased()
        guard lower.hasPrefix(word + " ") else { return nil }
        let rest = text.dropFirst(word.count + 1).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// Words about a recording: the one on now shows first ("rec",
    /// "record…", "enregistr…").
    public static func mentions(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == word || lower.hasPrefix(word + " ") || lower.hasPrefix("stop rec") { return true }
        // A word on its way ("reco", "enre"), not another one ("recipe").
        return ["recording", "enregistrement", "enregistreur"].contains { whole in
            lower.count >= 4 && (whole.hasPrefix(lower) || lower.hasPrefix(String(whole.prefix(6))))
        }
    }
}

/// `meeting.json`: what a recording is, beside its tracks. Written as soon
/// as it starts and whenever it changes, so a recording never stopped is
/// found again (`isUnfinished`).
public struct MeetingRecord: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        /// Being recorded, or paused.
        case recording, paused
        /// Stopped; its transcript being made.
        case transcribing
        case done
        /// Kept without a transcript: no engine of this Mac has its
        /// language (`engine` nil).
        case pending
        /// Stopped whole as skil.li quit: its transcript is made at the
        /// next launch, nothing asked (docs/meeting-recorder.md, "Quit and
        /// sleep").
        case stopped
    }

    /// Who records it: a process, told from another that later got the same
    /// number by its start.
    public struct Owner: Codable, Equatable, Sendable {
        public var pid: Int32
        public var launched: Date

        public init(pid: Int32, launched: Date) {
            self.pid = pid
            self.launched = launched
        }
    }

    /// A pause: where it is in the tracks, and how long it lasted.
    public struct Pause: Codable, Equatable, Sendable {
        public var at: Double
        public var seconds: Double

        public init(at: Double, seconds: Double) {
            self.at = at
            self.seconds = seconds
        }
    }

    /// A part of the meeting, by the user's AI (phase 5): its title, and
    /// the start of the line it starts on (seconds).
    public struct Chapter: Codable, Equatable, Sendable {
        public var title: String
        public var start: Double

        public init(title: String, start: Double) {
            self.title = title
            self.start = start
        }
    }

    /// When `summary.md` was written, and who wrote it ("Claude · Haiku").
    public struct Summarized: Codable, Equatable, Sendable {
        public var at: Date
        public var by: String

        public init(at: Date, by: String) {
            self.at = at
            self.by = by
        }
    }

    public var version = 1
    public var title: String
    public var started: Date
    /// Its length, the pauses taken out.
    public var seconds: Double
    public var state: State
    /// The language it is transcribed in ("en-US").
    public var language: String
    /// The engine that made the transcript ("SpeechTranscriber"); nil
    /// while there is none.
    public var engine: String?
    /// The speakers' names: "me" and "them" until the user names them.
    public var speakers: [String: String]
    public var attendees: [String]
    public var chapters: [Chapter]
    public var pauses: [Pause]
    /// The other side's words the microphone heard again (no headphones),
    /// taken out of the user's lines.
    public var echoDropped: Int?
    /// While it is recorded.
    public var recorder: Owner?
    /// When the last part was written.
    public var stopped: Date?
    /// The meeting's case (docs/meeting-recorder-views.md, "The five
    /// cases"); nil before phase 2.
    public var kind: MeetingMoment.Kind?
    /// The calendar's event it records, when one was on.
    public var event: EventLink?
    /// The call's app, by name, as last picked.
    public var app: String?
    /// The location, when it is a place (in person).
    public var place: String?
    /// Tracks never on while it was recorded (in person: the Mac's
    /// sound): no lane, nothing transcribed.
    public var unused: [Speaker]?
    /// A line changed by hand in its window (phase 4): Transcribe Again
    /// says it replaces the changes.
    public var edited: Bool?
    /// An import's file name ("Board call.m4a"): made from a file, not
    /// recorded here.
    public var imported: String?
    /// The summary written (phase 5), when there is one.
    public var summarized: Summarized?
    /// The attendees' mail addresses, from the event: the recap mail's (phase
    /// 5). Never sent anywhere else.
    public var addresses: [String]?
    /// The skillies run on it (phase 5): from ⌘K, or on their own after its
    /// transcript; the last 20.
    public var skillies: [SkillieRun]?
    /// A Transcribe Again not made as skil.li quit (waiting its turn, or
    /// being made): made at the next launch in that language, with that
    /// engine; nil once it is made, or failed.
    public var madeAgain: MadeAgain?

    /// What Transcribe Again was asked with.
    public struct MadeAgain: Codable, Equatable, Sendable {
        public var language: String
        /// A `TranscriptEngine`'s stored name.
        public var engine: String

        public init(language: String, engine: String) {
            self.language = language
            self.engine = engine
        }
    }

    /// A skillie run on a recording: which, when, how it went.
    public struct SkillieRun: Codable, Equatable, Sendable {
        public var title: String
        public var path: String
        public var at: Date
        /// After the transcript, on its own (the one marked), not from ⌘K.
        public var automatic: Bool
        public var status: Int32
        /// Its last line.
        public var line: String

        public init(title: String, path: String, at: Date, automatic: Bool, status: Int32, line: String) {
            self.title = title
            self.path = path
            self.at = at
            self.automatic = automatic
            self.status = status
            self.line = line
        }
    }

    /// This record with the skillies' runs of `latest` (the record as it is
    /// on disk now): a skillie may finish while a transcript is made from a
    /// record read before, and its run is kept.
    public func keepingRuns(of latest: MeetingRecord?) -> MeetingRecord {
        guard let runs = latest?.skillies else { return self }
        var record = self
        record.skillies = runs
        return record
    }

    /// The calendar's event a recording is of: which occurrence, and when
    /// it ends (the call's end is watched from then).
    public struct EventLink: Codable, Equatable, Sendable {
        public var id: String
        public var start: Date
        public var end: Date

        public init(id: String, start: Date, end: Date) {
            self.id = id
            self.start = start
            self.end = end
        }
    }

    public init(title: String, started: Date, language: String, recorder: Owner?) {
        self.title = title
        self.started = started
        seconds = 0
        state = .recording
        self.language = language
        engine = nil
        speakers = [Speaker.me.rawValue: Speaker.me.title, Speaker.them.rawValue: Speaker.them.title]
        attendees = []
        chapters = []
        pauses = []
        self.recorder = recorder
    }

    /// Never stopped: still `recording` or `paused` (or its transcript
    /// started and never finished) while no process with its owner's
    /// number and start runs (`isRunning`). skil.li crashed, or the Mac
    /// lost power; a quit closes it (`stopped`).
    public func isUnfinished(isRunning: (Owner) -> Bool) -> Bool {
        switch state {
        case .recording, .paused, .transcribing:
            guard let recorder else { return true }
            return !isRunning(recorder)
        case .done, .pending, .stopped:
            return false
        }
    }

    public static func decode(_ data: Data) throws -> MeetingRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeetingRecord.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// The engine a transcript is made with (docs/meeting-recorder.md,
/// "Transcription"): macOS's own `SpeechTranscriber`, or whisper
/// large-v3-turbo once Better transcription is downloaded. `meeting.json`
/// keeps its raw value; phase 1 wrote "SpeechTranscriber" for macOS's.
public enum TranscriptEngine: String, Codable, CaseIterable, Sendable {
    case macOS
    case whisper = "whisper-large-v3-turbo"

    /// As `meeting.json` and Settings keep it, nil for none.
    public init?(stored: String?) {
        guard let stored else { return nil }
        if stored == "SpeechTranscriber" {
            self = .macOS
        } else if let engine = TranscriptEngine(rawValue: stored) {
            self = engine
        } else {
            return nil
        }
    }

    /// As the user reads it.
    public var title: String {
        switch self {
        case .macOS: "macOS"
        case .whisper: "Better transcription"
        }
    }

    /// The engine a transcript is made with when the user picked none
    /// (Settings → Recorder's, `preferred`): Better transcription once
    /// downloaded, the default from then on; macOS's otherwise.
    public static func standard(preferred: TranscriptEngine?, whisperReady: Bool) -> TranscriptEngine {
        guard whisperReady else { return .macOS }
        return preferred ?? .whisper
    }

    /// The engines to try for a language, in order (docs/meeting-recorder.md,
    /// "A language this Mac cannot transcribe"): the default first, then
    /// the others this Mac has.
    public static func order(standard: TranscriptEngine, whisperReady: Bool) -> [TranscriptEngine] {
        let available = allCases.filter { $0 == .macOS || whisperReady }
        return [standard] + available.filter { $0 != standard }
    }
}

/// Who spoke: the microphone is the user, the Mac's sound the others.
public enum Speaker: String, Codable, Sendable, CaseIterable {
    case me, them

    /// Its name until the user gives one.
    public var title: String {
        switch self {
        case .me: "Me"
        case .them: "Them"
        }
    }

    /// The track it is heard on.
    public var file: String {
        switch self {
        case .me: "me.m4a"
        case .them: "them.m4a"
        }
    }
}

/// One track's time, kept by its device's clock (docs/meeting-recorder.md,
/// "In step over an hour"): where each buffer the device hands over goes in
/// the file. Inside a run the device's sample time places it, a missed
/// cycle written as silence of its length; a run starts (the first
/// buffer, after a pause, after the audio setup changed and the engine
/// started again) at its place by the host clock. Pauses, the start and
/// the stop are moments of the host clock, the same for every track, so a
/// pause is cut from all of them at the same moment, to the sample. A
/// device whose clock runs fast or slow against the host's (a USB or
/// Bluetooth microphone: tens to hundreds of ppm) would slide away from the
/// other tracks over a run: past a quarter of a millisecond off (smoothed
/// over a second, so one late buffer moves nothing), one frame is left out
/// or played twice per buffer until it is back, and a run started again
/// after a pause jumps by less than half a millisecond.
public struct TrackTimeline: Sendable {
    /// What to write next: silence of that many frames, or that part of the
    /// buffer.
    public enum Piece: Equatable, Sendable {
        case silence(Int)
        case frames(Range<Int>)
    }

    /// Frames a second.
    public let rate: Double
    /// Frames in the file so far.
    public private(set) var written = 0
    /// The host time (seconds) the recording started: frame 0.
    public let start: Double
    private var pauses: [(from: Double, to: Double?)] = []
    private var stop: Double?
    /// The device's sample time of the next frame, while a run goes on.
    private var next: Double?
    /// The part of the recording (between pauses) the run is in.
    private var part = -1
    /// A jump of the sample time past this is a new timeline (a device
    /// that started over), placed by the host clock.
    private static let longestGap = 5.0
    /// How far a run may be from the host clock (seconds), and over how
    /// long that is smoothed, before a frame is left out or played twice.
    private static let driftTolerance = 0.00025
    private static let driftWindow = 1.0
    /// Frames the run is ahead of the host clock (behind: below zero),
    /// smoothed.
    private var drift = 0.0
    /// How far each run after a pause was moved to its place by the host
    /// clock (frames: silence added, or frames left out): the track's own
    /// slip over the run before.
    public private(set) var resumeJumps: [Int] = []

    public init(rate: Double, start: Double) {
        self.rate = rate
        self.start = start
    }

    public mutating func pause(at time: Double) {
        guard !isPaused, stop == nil else { return }
        pauses.append((time, nil))
    }

    public mutating func resume(at time: Double) {
        guard let last = pauses.last, last.to == nil else { return }
        pauses[pauses.count - 1].to = max(time, last.from)
    }

    public mutating func finish(at time: Double) {
        if stop == nil { stop = time }
    }

    public var isPaused: Bool { pauses.last.map { $0.to == nil } ?? false }

    /// Once finished, how many frames the track holds past the stop (a
    /// device whose clock ran ahead, buffers stamped late): taken off its
    /// end, so every track ends at the same moment.
    public mutating func overshoot() -> Int {
        guard let stop else { return 0 }
        let end = Int((fileTime(of: stop) * rate).rounded())
        guard written > end else { return 0 }
        defer { written = end }
        return written - end
    }

    /// Once finished, the silence that brings the track to the stop when
    /// its device gave less (it went away, or its last buffers never
    /// came): every track ends at the same moment.
    public mutating func tail() -> Piece? {
        guard let stop else { return nil }
        let end = Int((fileTime(of: stop) * rate).rounded())
        guard end > written else { return nil }
        defer { written = end }
        return .silence(end - written)
    }

    /// The engine started again (a change of the audio setup): its sample
    /// time is a new one, the next buffer is placed by the host clock.
    public mutating func restarted() {
        next = nil
    }

    /// Where `time` (host seconds) falls in the file, in seconds: the time
    /// since the start, less the pauses before it.
    public func fileTime(of time: Double) -> Double {
        var paused = 0.0
        for pause in pauses where pause.from < time {
            paused += min(pause.to ?? time, time) - pause.from
        }
        return time - start - paused
    }

    /// A buffer of `frames` frames whose first is at the device's
    /// `sampleTime` and the host's `hostTime` (seconds): what goes in the
    /// file, in order.
    public mutating func place(sampleTime: Double, hostTime: Double, frames: Int) -> [Piece] {
        guard frames > 0, rate > 0 else { return [] }
        var pieces: [Piece] = []
        // A frame is recorded when its middle is: a moment of the host clock
        // falls between two frames, never on one.
        func first(from moment: Double) -> Int {
            Int(((moment - hostTime) * rate - 0.5).rounded(.up))
        }
        var index = 0
        while index < frames {
            let middle = hostTime + (Double(index) + 0.5) / rate
            guard let (part, end) = activePart(at: middle) else {
                // Not recorded (before the start, paused, after the stop):
                // skipped to where recording goes on, if in this buffer.
                guard let resumes = nextActive(after: middle) else { break }
                index = max(index + 1, first(from: resumes))
                continue
            }
            let last = end.map { min(frames, first(from: $0)) } ?? frames
            var from = index
            let to = max(from + 1, last)
            var keep: Int = 0
            if let next, part == self.part, abs(sampleTime + Double(from) - next) <= Self.longestGap * rate {
                let gap = Int((sampleTime + Double(from) - next).rounded())
                if gap > 0 {
                    pieces.append(.silence(gap))
                    written += gap
                } else if gap < 0 {
                    from = min(to, from - gap)
                }
                // How far the device's clock took the run from the host's.
                let expected = fileTime(of: hostTime + Double(from) / rate) * rate
                let weight = min(1, Double(to - from) / rate / Self.driftWindow)
                drift += (Double(written) - expected - drift) * weight
                let limit = max(1, Self.driftTolerance * rate)
                keep = drift > limit && to - from > 2 ? -1 : drift < -limit && to > from ? 1 : 0
            } else {
                let target = Int((fileTime(of: hostTime + Double(from) / rate) * rate).rounded())
                if next != nil, self.part >= 0, part != self.part { resumeJumps.append(target - written) }
                if target > written {
                    pieces.append(.silence(target - written))
                    written = target
                } else if target < written {
                    from = min(to, from + written - target)
                }
                drift = 0
            }
            if from < to {
                let middle = from + (to - from) / 2
                switch keep {
                case -1:
                    // Ahead: one frame left out.
                    pieces.append(.frames(from..<middle))
                    pieces.append(.frames(middle + 1..<to))
                case 1:
                    // Behind: one frame played twice.
                    pieces.append(.frames(from..<middle + 1))
                    pieces.append(.frames(middle..<to))
                default:
                    pieces.append(.frames(from..<to))
                }
                written += to - from + keep
                drift += Double(keep)
            }
            next = sampleTime + Double(to)
            self.part = part
            index = to
        }
        return pieces
    }

    /// The part of the recording `time` is in, and when it ends (nil: not
    /// yet known); nil when it is not recorded.
    private func activePart(at time: Double) -> (Int, Double?)? {
        guard time >= start else { return nil }
        if let stop, time >= stop { return nil }
        for (index, pause) in pauses.enumerated() {
            if time < pause.from { return (index, min(pause.from, stop ?? .infinity)) }
            // Paused now, or inside this pause.
            guard let to = pause.to, time >= to else { return nil }
        }
        return (pauses.count, stop)
    }

    /// When recording goes on after `time`, if it is known to.
    private func nextActive(after time: Double) -> Double? {
        if time < start { return start }
        if let stop, time >= stop { return nil }
        for pause in pauses where time >= pause.from {
            guard let to = pause.to else { return nil }
            if time < to { return to }
        }
        return nil
    }
}
