import Foundation

/// An app running the microphone's input, as skil.li names it: the
/// process Core Audio says runs it, or the app it belongs to (a
/// browser's helper is its browser).
public struct MicrophoneApp: Equatable, Hashable, Sendable {
    /// Its bundle identifier ("" when it has none).
    public var bundleID: String
    /// As the Dock names it ("Google Chrome").
    public var name: String
    /// The app's own process (its helper's parent, for a browser).
    public var pid: Int32

    public init(bundleID: String, name: String, pid: Int32) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }
}

/// Who runs the microphone's input now, skil.li left out: the apps it
/// could name, and how many processes it could not (a system service,
/// as WebKit's for Safari: no app among its parents).
public struct MicrophoneHolders: Equatable, Sendable {
    public var apps: [MicrophoneApp]
    public var unnamed: Int

    public init(apps: [MicrophoneApp] = [], unnamed: Int = 0) {
        self.apps = apps
        self.unnamed = unnamed
    }

    public static let none = MicrophoneHolders()

    public var isEmpty: Bool { apps.isEmpty && unnamed == 0 }

    /// Whether the app of process `pid` runs it.
    public func runs(_ pid: Int32) -> Bool { apps.contains { $0.pid == pid } }
}

/// The recorder's moment (docs/meeting-recorder.md, Moment; its views in
/// docs/meeting-recorder-views.md, "The five cases"): which meeting this
/// is, told apart by code from the event, the apps on the microphone and
/// the window list, never by a model. Read when a Record key is offered,
/// and again when it is pressed.
public enum MeetingMoment {
    /// The five cases.
    public enum Kind: String, Codable, Equatable, Sendable {
        /// The event has a call link.
        case callLink
        /// No link; an app runs the microphone at the meeting's time.
        case inApp
        /// No link; the location is a place; no app on the microphone.
        case inPerson
        /// No meeting on; a known call app runs the microphone.
        case callWithoutEvent
        /// Anything else: the default sources.
        case nothing
    }

    /// The sources a recording starts with. The webcam and the screen
    /// (phase 3) are never on by a case: only as Settings → Recorder sets
    /// them, the screen never in person.
    public struct Sources: Equatable, Sendable {
        public var microphone: Bool
        public var macSound: Bool
        public var webcam: Bool
        public var screen: Bool

        public init(microphone: Bool, macSound: Bool, webcam: Bool = false, screen: Bool = false) {
            self.microphone = microphone
            self.macSound = macSound
            self.webcam = webcam
            self.screen = screen
        }

        public static let both = Sources(microphone: true, macSound: true)

        /// The sound as a case sets it, the pictures as `defaults` do.
        func sound(microphone: Bool, macSound: Bool, inPerson: Bool = false) -> Sources {
            Sources(microphone: microphone, macSound: macSound, webcam: webcam, screen: screen && !inPerson)
        }
    }

    /// The moment as read: the case, the meeting (if any), the call's app
    /// to watch for its end, the sources, the name.
    public struct Reading: Equatable, Sendable {
        public var kind: Kind
        public var event: AgendaEvent?
        /// The call's app, watched for the call's end (nil: none known
        /// yet, or in person).
        public var app: MicrophoneApp?
        public var sources: Sources
        /// What the recording is named: the event's title, "Discord call
        /// 14:30", or nil for the default ("Meeting 14:30").
        public var title: String?
        /// The location, when it is a place.
        public var place: String?

        public init(kind: Kind, event: AgendaEvent?, app: MicrophoneApp?, sources: Sources, title: String?, place: String? = nil) {
            self.kind = kind
            self.event = event
            self.app = app
            self.sources = sources
            self.title = title
            self.place = place
        }

        /// The attendees' names, as the event lists them.
        public var attendees: [String] { event?.attendees.map(\.name).filter { !$0.isEmpty } ?? [] }

        /// The key's label: "Record", or "Record (in person)" for a place.
        public var recordLabel: String { kind == .inPerson ? "Record (in person)" : "Record" }
    }

    /// A meeting the Record keys are for: on now, or starting within 10
    /// minutes; never all day or declined.
    public static func isRecordable(_ event: AgendaEvent, now: Date) -> Bool {
        !event.isAllDay && !event.declined && now >= event.start.addingTimeInterval(-10 * 60) && now < event.end
    }

    /// The case, from the meeting (`event`: on now or starting soon), the
    /// apps on the microphone, and `linkOpensIn`: the app the event's call
    /// link opens in (its service's app, else the browser), which only the
    /// app can tell. `defaults`: the sources when nothing says otherwise
    /// (Settings → Recorder).
    public static func read(event: AgendaEvent?, microphone: MicrophoneHolders, linkOpensIn: MicrophoneApp? = nil,
                            defaults: Sources = .both) -> Reading {
        let event = event.flatMap { $0.isAllDay || $0.declined ? nil : $0 }
        let titled = event.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        guard let event else {
            if let app = microphone.apps.first(where: isCallApp) {
                return Reading(kind: .callWithoutEvent, event: nil, app: app, sources: defaults.sound(microphone: true, macSound: true), title: nil)
            }
            return Reading(kind: .nothing, event: nil, app: nil, sources: defaults, title: nil)
        }
        if event.meeting != nil {
            // The app the user joined in, else the one the link opens in.
            let joined = microphone.apps.first { $0.bundleID == linkOpensIn?.bundleID } ?? microphone.apps.first
            return Reading(kind: .callLink, event: event, app: joined ?? linkOpensIn, sources: defaults.sound(microphone: true, macSound: true),
                           title: titled)
        }
        if !microphone.apps.isEmpty {
            let named = microphone.apps.first { names(event.location, $0) }
            let app = named ?? microphone.apps.first(where: isCallApp) ?? microphone.apps[0]
            return Reading(kind: .inApp, event: event, app: app, sources: defaults.sound(microphone: true, macSound: true), title: titled)
        }
        if microphone.isEmpty, let place = place(event.location) {
            return Reading(kind: .inPerson, event: event, app: nil, sources: defaults.sound(microphone: true, macSound: false, inPerson: true),
                           title: titled, place: place)
        }
        return Reading(kind: .nothing, event: event, app: nil, sources: defaults, title: titled)
    }

    // MARK: - Call apps

    /// The call apps by bundle identifier, as each app's Info.plist has it
    /// (checked on the test Mac, 2026-10-24).
    public static let callAppIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime", "com.hnc.Discord", "com.tinyspeck.slackmacgap",
        "net.whatsapp.WhatsApp", "org.whispersystems.signal-desktop"
    ]

    /// Call apps and services by the names people write and apps carry,
    /// lowercased: an app named so is a call app, a location naming one is
    /// not a place. Never a common word ("meet in the lobby", "around the
    /// corner" are places).
    public static let callNames: [String] = [
        "zoom", "zoom.us", "teams", "microsoft teams", "facetime", "discord", "slack", "huddle", "webex", "skype", "whatsapp", "signal",
        "telegram", "tuple", "gather", "whereby", "jitsi", "google meet", "chime", "bluejeans"
    ]

    /// A known call app (by its bundle identifier, else its name). A
    /// browser is not one.
    public static func isCallApp(_ app: MicrophoneApp) -> Bool {
        callAppIDs.contains(app.bundleID) || callNames.contains(app.name.lowercased())
    }

    /// Whether `location` names `app` (its name, or its name's first word
    /// as a word: "Discord", "Slack huddle", "Gather · Lumière HQ").
    static func names(_ location: String, _ app: MicrophoneApp) -> Bool {
        let words = Set(wordsOf(location))
        let name = wordsOf(app.name)
        guard let first = name.first else { return false }
        return words.contains(first) || (!name.isEmpty && name.allSatisfy(words.contains))
    }

    // MARK: - A place

    /// Words for a meeting with no place: online, by phone, not decided.
    static let notPlaces: Set<String> = [
        "online", "remote", "virtual", "visio", "visioconference", "visioconférence", "en ligne", "distanciel", "a distance", "à distance",
        "call", "appel", "phone", "telephone", "téléphone", "tbd", "tba", "a definir", "à définir", "n/a", "-", "none", "aucun"
    ]

    /// The location when it is a place: something written, holding no web
    /// address or phone number, naming no call app, not a word for
    /// "online". Nil otherwise.
    public static func place(_ location: String) -> String? {
        let text = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if notPlaces.contains(lower) || notPlaces.contains(lower.folding(options: .diacriticInsensitive, locale: nil)) { return nil }
        let words = wordsOf(text)
        if words.count <= 3, words.allSatisfy({ notPlaces.contains($0) }) { return nil }
        // A call app or service named ("Gather", "Slack huddle").
        let joined = " " + words.joined(separator: " ") + " "
        if callNames.contains(where: { joined.contains(" \($0) ") }) { return nil }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue),
           detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return nil
        }
        // An address without its scheme ("lumiere.example.com/salon").
        if words.contains(where: isAddress) { return nil }
        return text
    }

    /// "app.example.town/room": a host of two labels or more, the last
    /// one letters (a top-level domain), then maybe a path.
    static func isAddress(_ word: String) -> Bool {
        let host = word.split(separator: "/").first.map(String.init) ?? word
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let last = labels.last else { return false }
        return last.count >= 2 && last.allSatisfy(\.isLetter) && labels[0].contains(where: \.isLetter)
    }

    /// Lowercased words, punctuation aside (a dot kept inside a word:
    /// "zoom.us").
    static func wordsOf(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "./")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "./")) }
            .filter { !$0.isEmpty }
    }

    /// "Discord call 14:30": a call with no event, named by its app and
    /// the time, as "Meeting 14:30".
    public static func callTitle(_ app: MicrophoneApp, at date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = timeZone
        format.dateStyle = .none
        format.timeStyle = .short
        return "\(app.name) call \(format.string(from: date))"
    }
}

/// When a call being recorded ends (docs/meeting-recorder-views.md, "The
/// call ends: Stop"): its app leaves the call (it no longer runs the
/// microphone, for 5 s: a reconnect is not an end), or the meeting is over
/// and the sound has been quiet for a minute. An offer the call's return
/// withdrew comes again at the next end; Keep Recording (`kept`) ends that
/// reason's offers. Fed once a second while recording, from memory.
public struct CallEndWatch: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The call's app left the call (its name).
        case appLeft(String)
        /// The meeting ended at that time and the sound has been quiet.
        case quietAfterEnd(Date)
    }

    /// The app no longer on the microphone this long: its call ended.
    public let appGrace: TimeInterval
    /// Quiet this long past the meeting's end: it is over.
    public let quietFor: TimeInterval

    private var appSeen = false
    private var appOffSince: Date?
    private var quietSince: Date?
    private var offeredAppLeft = false
    private var offeredQuiet = false
    /// Keep Recording answered: that reason is not offered again.
    private var keptAppLeft = false

    /// 5 s and a minute; the self-test waits less.
    public init(appGrace: TimeInterval = 5, quietFor: TimeInterval = 60) {
        self.appGrace = appGrace
        self.quietFor = quietFor
    }

    /// `app`: the call's app and whether it runs the microphone now (nil:
    /// no call app watched). `quiet`: every source on is under the
    /// threshold now. `eventEnd`: the meeting's end, when there is one.
    /// The reason to offer Stop now, once each.
    public mutating func update(now: Date, app: (name: String, onMicrophone: Bool)?, quiet: Bool, eventEnd: Date?) -> Reason? {
        if let app {
            if app.onMicrophone {
                appSeen = true
                appOffSince = nil
                // Back in the call: a later end is offered again.
                if !keptAppLeft { offeredAppLeft = false }
            } else if appSeen {
                let since = appOffSince ?? now
                appOffSince = since
                if !offeredAppLeft, now.timeIntervalSince(since) >= appGrace {
                    offeredAppLeft = true
                    return .appLeft(app.name)
                }
            }
        } else {
            appOffSince = nil
        }
        quietSince = quiet ? (quietSince ?? now) : nil
        if !offeredQuiet, let eventEnd, now >= eventEnd, let quietSince, now.timeIntervalSince(max(quietSince, eventEnd)) >= quietFor {
            offeredQuiet = true
            return .quietAfterEnd(eventEnd)
        }
        return nil
    }

    /// The app picked again (the red dot's menu): it has to be seen on the
    /// microphone before it can leave.
    public mutating func appChanged() {
        appSeen = false
        appOffSince = nil
        offeredAppLeft = false
        keptAppLeft = false
    }

    /// Keep Recording answered to `reason`: not offered again.
    public mutating func kept(_ reason: Reason) {
        if case .appLeft = reason { keptAppLeft = true }
    }

    /// Whether an offer for `reason` still stands: the app back on the
    /// microphone withdraws "it left".
    public func stillTrue(_ reason: Reason) -> Bool {
        switch reason {
        case .appLeft: appOffSince != nil
        case .quietAfterEnd: quietSince != nil
        }
    }

    /// The card's line: "Google Chrome left the call.", "The meeting ended
    /// at 14:30, and it has been quiet for a minute."
    public static func line(_ reason: Reason, clock: (Date) -> String = MeetingBar.clock) -> String {
        switch reason {
        case .appLeft(let name): "\(name) left the call."
        case .quietAfterEnd(let end): "The meeting ended at \(clock(end)), and it has been quiet for a minute."
        }
    }
}

/// "Paul", "Paul and Anna", "Paul, Anna and 4 others": first names, as
/// the meeting card and the recorder say who is in a meeting.
public enum MeetingPeople {
    public static func sentence(_ names: [String]) -> String {
        let first = names.map { String($0.split(separator: " ").first ?? Substring($0)) }
        switch first.count {
        case 0: return ""
        case 1: return first[0]
        case 2: return "\(first[0]) and \(first[1])"
        default:
            let others = first.count - 2
            return "\(first[0]), \(first[1]) and \(others) other\(others == 1 ? "" : "s")"
        }
    }
}

/// Settings → Recorder → Delete after: how long recordings are kept. As
/// the clipboard's: pruned at launch and then each hour, never as the
/// setting changes; an expired recording goes to the Trash.
public enum RecordingRetention: Equatable, Hashable, Sendable {
    case never
    case week
    case month
    case quarter
    case year
    case days(Int)

    /// What Settings stores: "never", "week", "month", "quarter", "year",
    /// "days:10".
    public var rawValue: String {
        switch self {
        case .never: "never"
        case .week: "week"
        case .month: "month"
        case .quarter: "quarter"
        case .year: "year"
        case .days(let days): "days:\(days)"
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "week": self = .week
        case "month": self = .month
        case "quarter": self = .quarter
        case "year": self = .year
        default:
            if rawValue.hasPrefix("days:"), let days = Int(rawValue.dropFirst(5)), days > 0 {
                self = .days(days)
            } else {
                self = .never
            }
        }
    }

    public var days: Int? {
        switch self {
        case .never: nil
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .days(let days): days
        }
    }

    /// Recordings started before this date go; nil keeps them all.
    public func cutoff(now: Date = .now) -> Date? {
        days.map { now.addingTimeInterval(-Double($0) * 86_400) }
    }

    /// Custom, from this choice's days, so picking Custom keeps what was
    /// kept; from Never, a year.
    public var asCustom: RecordingRetention { .days(days ?? 365) }

    /// "a week", "3 months", "10 days"; nil for Never.
    public var spoken: String? {
        switch self {
        case .never: nil
        case .week, .days(7): "a week"
        case .month: "a month"
        case .quarter: "3 months"
        case .year: "a year"
        case .days(1): "a day"
        case .days(let days): "\(days) days"
        }
    }

    /// Under Delete after, before the hourly pass: "2 recordings are older
    /// than a month: they go to the Trash within the hour." Nil when none
    /// would go.
    public func removalLine(older count: Int) -> String? {
        guard count > 0, let spoken else { return nil }
        return count == 1
            ? "1 recording is older than \(spoken): it goes to the Trash within the hour."
            : "\(count) recordings are older than \(spoken): they go to the Trash within the hour."
    }

    /// The recordings that go now: started before the cutoff and done
    /// (transcribed or waiting for a language); never one being made or
    /// transcribed, nor one never stopped.
    public func expired<Folder>(_ recordings: [(folder: Folder, record: MeetingRecord)], now: Date = .now) -> [Folder] {
        guard let cutoff = cutoff(now: now) else { return [] }
        return recordings.filter { ($0.record.state == .done || $0.record.state == .pending) && $0.record.started < cutoff }.map(\.folder)
    }
}

/// A recording as the launcher and Settings list it: what its
/// `meeting.json` says, never its words.
public struct RecordingSummary: Equatable, Sendable {
    /// Its folder's name in the Recordings folder.
    public var folder: String
    public var title: String
    public var started: Date
    public var seconds: Double
    public var attendees: [String]
    public var state: MeetingRecord.State

    public init(folder: String, title: String, started: Date, seconds: Double, attendees: [String], state: MeetingRecord.State) {
        self.folder = folder
        self.title = title
        self.started = started
        self.seconds = seconds
        self.attendees = attendees
        self.state = state
    }

    public init(folder: String, record: MeetingRecord) {
        self.init(folder: folder, title: record.title, started: record.started, seconds: record.seconds, attendees: record.attendees,
                  state: record.state)
    }
}

/// Finding recordings by what the launcher keeps of them: title, date and
/// attendees (the words said come from the index, `RecordingIndex`).
public enum RecordingSearch {
    /// The index of the words said, in skil.li's folder beside the
    /// Recordings folder: a copy of every transcript's words, so never in a
    /// backup (`BackupPlan.neverCopied`).
    public static let indexFile = "recordings-index.sqlite"
    /// The index and the files SQLite keeps beside it, each by its exact
    /// name: the write-ahead log and its shared memory (the index is in WAL
    /// mode), a rollback journal.
    public static let indexFiles = [indexFile, indexFile + "-wal", indexFile + "-shm", indexFile + "-journal"]

    /// The words a recording is found by, besides its title: its
    /// attendees, its date as written ("wednesday wed 22 october oct
    /// 2026").
    public static func dateWords(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> [String] {
        let format = DateFormatter()
        format.locale = locale
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        return ["EEEE", "EEE", "d", "MMMM", "MMM", "yyyy"].map { pattern in
            format.dateFormat = pattern
            return fold(format.string(from: date)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }

    /// Whether every word typed starts a word of the title, the
    /// attendees' names or the date; nil when one does not. The score:
    /// higher for words found in the title.
    public static func score(_ query: String, _ recording: RecordingSummary, locale: Locale = .current, calendar: Calendar = .current) -> Int? {
        let typed = words(query)
        guard !typed.isEmpty else { return 0 }
        let title = words(recording.title)
        let people = recording.attendees.flatMap(words)
        let date = dateWords(recording.started, locale: locale, calendar: calendar)
        var score = 0
        for word in typed {
            if title.contains(where: { $0.hasPrefix(word) }) {
                score += title.contains(word) ? 3 : 2
            } else if people.contains(where: { $0.hasPrefix(word) }) {
                score += 1
            } else if date.contains(where: { $0.hasPrefix(word) }) {
                score += 1
            } else {
                return nil
            }
        }
        return score
    }

    /// The row's second line: "Wed 22 Oct · 32 min · Paul, Anna and 2
    /// others".
    public static func detail(_ recording: RecordingSummary, length: String) -> String {
        let day = recording.started.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let people = MeetingPeople.sentence(recording.attendees)
        return ([day, recording.seconds > 0 ? length : nil, people.isEmpty ? nil : people] as [String?]).compactMap { $0 }.joined(separator: " · ")
    }

    static func words(_ text: String) -> [String] {
        fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
