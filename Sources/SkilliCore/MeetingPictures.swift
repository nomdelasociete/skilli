import CoreGraphics
import Foundation

/// A picture track's time (`webcam.mp4`, `screen.mp4`;
/// docs/meeting-recorder-views.md, phase 3, "The files"): each picture at
/// its own moment of the host clock, cut where the sound is cut: the
/// start, each pause, the stop, the same host moments as `TrackTimeline`'s.
/// A source gives a picture only when something changed, and a file holds
/// each one until the next: a cut holds the picture on screen at that
/// moment, placed again where recording goes on (`placeHeld`).
public struct PictureTimeline: Sendable {
    /// The host time (seconds) the recording started: the file's 0.
    public let start: Double
    private var pauses: [(from: Double, to: Double?)] = []
    private var stop: Double?
    /// The file time of the last picture placed.
    public private(set) var last: Double?
    /// The least a picture comes after the one before: a file's times rise.
    public static let step = 1.0 / 600

    public init(start: Double) {
        self.start = start
    }

    public var isPaused: Bool { pauses.last.map { $0.to == nil } ?? false }

    public mutating func pause(at time: Double) {
        guard !isPaused, stop == nil, time >= start else { return }
        pauses.append((time, nil))
    }

    public mutating func resume(at time: Double) {
        guard let pause = pauses.last, pause.to == nil else { return }
        pauses[pauses.count - 1].to = max(time, pause.from)
    }

    /// Stopped at host time `time`: where the file ends.
    @discardableResult
    public mutating func finish(at time: Double) -> Double {
        if stop == nil { stop = max(time, start) }
        return fileTime(of: stop ?? time)
    }

    /// Where `time` (host seconds) falls in the file: the time since the
    /// start, less the pauses before it.
    public func fileTime(of time: Double) -> Double {
        var paused = 0.0
        for pause in pauses where pause.from < time {
            paused += min(pause.to ?? time, time) - pause.from
        }
        return max(0, time - start - paused)
    }

    /// Whether host time `time` is recorded: after the start, not paused,
    /// before the stop.
    public func records(_ time: Double) -> Bool {
        guard time >= start else { return false }
        if let stop, time >= stop { return false }
        return !pauses.contains { time >= $0.from && time < ($0.to ?? .infinity) }
    }

    /// A picture shown at host time `time`: its time in the file; nil when
    /// it is not recorded (before the start, paused, after the stop). Two
    /// pictures at the same moment: the later one just after.
    public mutating func place(_ time: Double) -> Double? {
        guard records(time) else { return nil }
        return placing(fileTime(of: time))
    }

    /// The picture on screen at host moment `moment` (the start, a resume),
    /// held from before it: placed exactly there; nil when the file is
    /// already past it.
    public mutating func placeHeld(at moment: Double) -> Double? {
        guard moment >= start, stop.map({ moment < $0 }) ?? true, !isPaused else { return nil }
        let time = fileTime(of: moment)
        if let last, time < last + Self.step { return nil }
        last = time
        return time
    }

    private mutating func placing(_ time: Double) -> Double? {
        let placed = last.map { max(time, $0 + Self.step) } ?? time
        if let stop, placed >= fileTime(of: stop) { return nil }
        last = placed
        return placed
    }
}

/// How much of a window the windows in front of it leave in sight
/// (docs/meeting-recorder.md, Measured: Chrome's window, covered whole,
/// stops painting). Rectangles in one coordinate space, as the window
/// list gives them.
public enum WindowCover {
    /// The share of `window` no rectangle of `fronts` covers, 0…1.
    public static func visibleFraction(of window: CGRect, under fronts: [CGRect]) -> Double {
        let area = window.width * window.height
        guard area > 0 else { return 0 }
        let covers = fronts.map { $0.intersection(window) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        guard !covers.isEmpty else { return 1 }
        // The rectangles' edges cut the window into cells, each covered or
        // not as a whole.
        let xs = Set([window.minX, window.maxX] + covers.flatMap { [$0.minX, $0.maxX] }).sorted()
        let ys = Set([window.minY, window.maxY] + covers.flatMap { [$0.minY, $0.maxY] }).sorted()
        var seen = 0.0
        for x in 0..<(xs.count - 1) {
            for y in 0..<(ys.count - 1) {
                let middle = CGPoint(x: (xs[x] + xs[x + 1]) / 2, y: (ys[y] + ys[y + 1]) / 2)
                if !covers.contains(where: { $0.contains(middle) }) { seen += (xs[x + 1] - xs[x]) * (ys[y + 1] - ys[y]) }
            }
        }
        return min(1, max(0, seen / area))
    }
}

/// Whether the window recorded still gives pictures (docs/meeting-recorder-views.md,
/// phase 3, "The menu bar while recording"), from what the window list
/// says once a second and when the last new picture came. Measured: a
/// minimized or hidden window gives none; Chrome's, covered whole, the
/// same one again and again (Arc's keeps painting, and a still slide in
/// sight is no failure).
public struct PictureWatch: Sendable {
    public enum Problem: String, Equatable, Sendable {
        case minimized, hidden
        /// Not on this screen (another desktop), neither of the two.
        case offScreen
        /// Covered whole, no new picture for `stillFor`.
        case stoppedPainting
        case closed
    }

    /// The window, as the window list says it.
    public struct Look: Equatable, Sendable {
        public var exists: Bool
        public var onScreen: Bool
        public var minimized: Bool
        public var appHidden: Bool
        public var coveredWhole: Bool

        public init(exists: Bool = true, onScreen: Bool = true, minimized: Bool = false, appHidden: Bool = false, coveredWhole: Bool = false) {
            self.exists = exists
            self.onScreen = onScreen
            self.minimized = minimized
            self.appHidden = appHidden
            self.coveredWhole = coveredWhole
        }
    }

    /// A window covered whole is a problem once it gave no new picture
    /// for this long since it was covered.
    public static let stillFor = 5.0
    /// Anything else is one once it held this long (a window being
    /// minimized, a moment off screen as a desktop changes).
    public static let holdFor = 1.0

    public private(set) var problem: Problem?
    private var candidate: (problem: Problem, since: Double)?
    private var coveredSince: Double?

    public init() {}

    /// The window as it looks at `now` (seconds, any clock), and when the
    /// last new picture came (same clock): the problem now, nil when none.
    @discardableResult
    public mutating func update(_ look: Look, lastPicture: Double?, now: Double) -> Problem? {
        coveredSince = look.exists && look.onScreen && look.coveredWhole ? coveredSince ?? now : nil
        let found: Problem?
        if !look.exists {
            found = .closed
        } else if !look.onScreen {
            found = look.appHidden ? .hidden : look.minimized ? .minimized : .offScreen
        } else if let coveredSince, now - max(coveredSince, lastPicture ?? -.infinity) >= Self.stillFor {
            found = .stoppedPainting
        } else {
            found = nil
        }
        guard let found else {
            candidate = nil
            problem = nil
            return nil
        }
        if candidate?.problem != found { candidate = (found, now) }
        // Painting stopped already waited its own while.
        if found == .stoppedPainting || now - (candidate?.since ?? now) >= Self.holdFor { problem = found }
        return problem
    }

    /// The window's stream stopped with the window gone: said at once.
    public mutating func closed() {
        candidate = (.closed, -.infinity)
        problem = .closed
    }

    /// A new picture came: a window painting again is no problem.
    public mutating func pictured() {
        if problem == .stoppedPainting {
            problem = nil
            candidate = nil
        }
    }

    /// The menu's words for it: "Google Chrome is minimized: nothing
    /// recorded until it's back".
    public static func line(_ problem: Problem, app: String) -> String {
        switch problem {
        case .minimized: "\(app) is minimized: nothing recorded until it's back"
        case .hidden: "\(app) is hidden: nothing recorded until it's back"
        case .offScreen: "\(app) isn't on screen: nothing recorded until it's back"
        case .stoppedPainting: "\(app) stopped painting: keep some of its window in sight"
        case .closed: "the window closed: pick another"
        }
    }

    /// The menu's words for the whole screen: it never minimizes or
    /// hides, it can only go.
    public static let disconnectedLine = "the screen was disconnected: pick another"
}

/// The whole screen (docs/meeting-recorder-views.md, "The whole screen"):
/// which of the Mac's screens the lists offer first, how each is named,
/// and the one a tool or a link names. Code, from the window list and the
/// displays: nothing leaves the Mac.
public enum WholeScreen {
    public struct Display: Equatable, Sendable {
        public let id: UInt32
        public let name: String
        /// Its frame in the window list's coordinates.
        public let frame: CGRect

        public init(id: UInt32, name: String, frame: CGRect) {
            self.id = id
            self.name = name
            self.frame = frame
        }
    }

    /// The pick's words: "Whole Screen" when the Mac has one screen,
    /// "Whole Screen · LG UltraFine" when it has several.
    public static func title(_ name: String, several: Bool) -> String {
        several && !name.isEmpty ? "Whole Screen · \(name)" : "Whole Screen"
    }

    /// The screens as the lists show them: the one holding most of
    /// `window` (the meeting's) first, none: the `main` one (the menu
    /// bar's); the others after, as macOS lists them.
    public static func ordered(_ displays: [Display], main: UInt32, window: CGRect?) -> [Display] {
        let first = holding(window, in: displays) ?? displays.first { $0.id == main } ?? displays.first
        guard let first else { return [] }
        return [first] + displays.filter { $0.id != first.id }
    }

    /// The screen holding most of `window`; nil when none holds any.
    static func holding(_ window: CGRect?, in displays: [Display]) -> Display? {
        guard let window, !window.isEmpty else { return nil }
        let shares = displays.map { display -> (Display, Double) in
            let part = display.frame.intersection(window)
            return (display, part.isNull ? 0 : Double(part.width * part.height))
        }
        guard let best = shares.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    /// The screen a tool's or a link's `display` names: `main` (the menu
    /// bar's), `meeting` (the one the meeting's window is on, else the
    /// main one: the lists' first), or a screen's name, case and accents
    /// aside (else the only one whose name starts so). Nil: none.
    public static func named(_ text: String, in displays: [Display], main: UInt32, window: CGRect?) -> Display? {
        let wanted = folded(text)
        switch wanted {
        case "main": return displays.first { $0.id == main } ?? displays.first
        case "meeting": return ordered(displays, main: main, window: window).first
        case "": return nil
        default:
            if let exact = displays.first(where: { folded($0.name) == wanted }) { return exact }
            let starting = displays.filter { folded($0.name).hasPrefix(wanted) }
            return starting.count == 1 ? starting[0] : nil
        }
    }

    /// The names macOS gives, told apart: a second "DELL U2720Q" is
    /// "DELL U2720Q (2)"; a screen with none is "Screen 2".
    public static func distinctNames(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.enumerated().map { index, name in
            let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Screen \(index + 1)" : name
            let count = (seen[base] ?? 0) + 1
            seen[base] = count
            return count == 1 ? base : "\(base) (\(count))"
        }
    }

    private static func folded(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension PictureChange {
    /// The share of the two thumbnails' pixels (gray levels) that differ by
    /// more than `threshold` levels: how much of the picture changed.
    public static func changedFraction(_ a: [UInt8], _ b: [UInt8], threshold: Int = 12) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var count = 0
        for index in a.indices where abs(Int(a[index]) - Int(b[index])) > threshold { count += 1 }
        return Double(count) / Double(a.count)
    }
}

/// When the screen's text is read (docs/meeting-recorder-views.md, phase 3,
/// "Reading the slides"): the picture sampled four times a second as a
/// grid of its brightness, fine enough that a slide whose text alone
/// changes shows (a 64 × 40 grid: a line of text is many of its cells); read
/// when it changed since the last reading, at most once a second, every
/// two seconds at most while readings find nothing new (a video moving),
/// so a slide is never read more than two seconds late. The slide is timed
/// at the last change before the reading (a sample unlike the one before):
/// between the two readings, so within their interval of the truth. A
/// still window gives no new picture: its reader samples the last one
/// again as time goes on.
public struct SlideSchedule: Sendable {
    /// Grid size, sampled every this many seconds.
    public static let columns = 64
    public static let rows = 40
    public static let sampleEvery = 0.25
    /// A change: this share of the grid's cells, each by more than
    /// `level` of 255 (a corner's clock ticking is less).
    public static let change = 0.015
    public static let level = 8
    /// Seconds between readings: one at least, two while readings find
    /// nothing new.
    public static let soonest = 1.0
    public static let latest = 2.0

    private var lastRead: (grid: [UInt8], at: Double)?
    private var previous: [UInt8]?
    /// The last change since the last reading.
    private var jumpAt: Double?
    private var wait = SlideSchedule.soonest

    public init() {}

    static func changed(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        PictureChange.changedFraction(a, b, threshold: level) >= change
    }

    /// A sample of the picture at `time` (the file's clock): when its text
    /// should be read now, the time the slide began; nil: not now.
    public mutating func sample(_ grid: [UInt8], at time: Double) -> Double? {
        defer { previous = grid }
        if let previous, Self.changed(grid, previous) { jumpAt = time }
        guard let lastRead else { return time }
        guard Self.changed(grid, lastRead.grid), time - lastRead.at >= wait else { return nil }
        return max(lastRead.at, jumpAt ?? time)
    }

    /// The text of `grid` read at `time`; whether it held lines new since
    /// the reading before.
    public mutating func read(_ grid: [UInt8], at time: Double, foundNew: Bool) {
        lastRead = (grid, time)
        // A change seen while it was read (a later picture) is kept.
        if jumpAt.map({ $0 <= time }) ?? true { jumpAt = nil }
        wait = foundNew ? Self.soonest : Self.latest
    }
}

/// The text the screen showed, as `slides.json` keeps it: each reading's
/// lines new since the readings just before are a slide, at its time.
/// Lines on screen through the whole recording (a browser's tabs, the
/// call's own buttons) are taken out at Stop (`kept`).
public struct SlideLog: Sendable {
    public struct Slide: Codable, Equatable, Sendable {
        /// On the recording's clock (pauses out), seconds.
        public var start: Double
        public var lines: [String]

        public init(start: Double, lines: [String]) {
            self.start = start
            self.lines = lines
        }
    }

    /// A line read again within this many readings is not new (one reading
    /// may miss a line another reads).
    public static let memory = 3
    /// Lines in this share of the readings, the first and the last among
    /// them, are the window's own, not a slide's.
    public static let everywhere = 0.9

    public private(set) var slides: [Slide] = []
    public private(set) var readings = 0
    private var recent: [Set<String>] = []
    private var seen: [String: Int] = [:]
    private var first: Set<String> = []
    private var latest: Set<String> = []

    public init() {}

    /// The screen's lines read at `time`: those new since the readings just
    /// before, as a slide (nil when none is new).
    @discardableResult
    public mutating func read(_ lines: [String], at time: Double) -> Slide? {
        var folded: Set<String> = []
        var fresh: [String] = []
        let shown = recent.reduce(into: Set<String>()) { $0.formUnion($1) }
        for line in lines {
            let text = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = Self.folded(text)
            // Text has words: a number alone (a call's clock, a counter)
            // is not a slide's.
            guard text.unicodeScalars.filter(CharacterSet.letters.contains).count >= 2, folded.insert(key).inserted else { continue }
            if !shown.contains(key) { fresh.append(text) }
        }
        readings += 1
        if readings == 1 { first = folded }
        latest = folded
        for key in folded { seen[key, default: 0] += 1 }
        recent.append(folded)
        if recent.count > Self.memory { recent.removeFirst() }
        guard !fresh.isEmpty else { return nil }
        let slide = Slide(start: time, lines: fresh)
        slides.append(slide)
        return slide
    }

    /// The slides as kept: the window's own lines out of every one, those
    /// left with none gone.
    public func kept() -> [Slide] {
        let own: Set<String> = readings < 3 ? [] : Set(seen.compactMap { key, count in
            Double(count) >= Self.everywhere * Double(readings) && first.contains(key) && latest.contains(key) ? key : nil
        })
        return slides.compactMap { slide in
            let lines = slide.lines.filter { !own.contains(Self.folded($0)) }
            return lines.isEmpty ? nil : Slide(start: slide.start, lines: lines)
        }
    }

    /// A line as compared: its letters and digits alone, case and accents
    /// aside ("Revenue up 12 %" and "Revenue up 12%" are one).
    public static func folded(_ line: String) -> String {
        let plain = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(plain.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    public static func encoded(_ slides: [Slide]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(slides)
    }

    public static func decode(_ data: Data) throws -> [Slide] {
        try JSONDecoder().decode([Slide].self, from: data)
    }
}

/// The meeting's tab in a browser (docs/meeting-recorder.md, "A browser
/// tab"): the tab on the call link's meeting, never another meeting on
/// the same site. A meeting's page moves once joined (Zoom's `/j/123` to
/// `/wc/123/join`, Meet adds `?authuser=0`), so the meeting is told by its
/// room: Meet's code, Zoom's number, Teams' thread; elsewhere the page.
public enum MeetingTab {
    /// The site (host, `www.` aside) and the room a call link names.
    public static func room(_ address: URL) -> (site: String, room: String)? {
        guard let host = Quicklink.site(address) else { return nil }
        let path = address.path().removingPercentEncoding ?? address.path()
        if host == "meet.google.com" {
            guard let code = path.split(separator: "/").map({ $0.lowercased() }).first(where: isMeetCode) else { return nil }
            return (host, code)
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            guard let number = path.split(separator: "/").first(where: { $0.count >= 9 && $0.allSatisfy(\.isNumber) }) else { return nil }
            return ("zoom.us", String(number))
        }
        if host.hasPrefix("teams.") {
            let whole = (address.absoluteString.removingPercentEncoding ?? address.absoluteString)
            guard let thread = whole.range(of: #"19:meeting_[A-Za-z0-9_=+\-]+@thread\.v2"#, options: .regularExpression) else { return nil }
            return ("teams", String(whole[thread]))
        }
        var page = path
        while page.hasSuffix("/") { page.removeLast() }
        return page.isEmpty ? nil : (host, page)
    }

    /// The tab on `link`'s meeting among `tabs`: the one in front of its
    /// window first, then the first. Nil when none is.
    public static func find(_ link: URL, among tabs: [Quicklink.OpenTab]) -> Quicklink.OpenTab? {
        guard let wanted = room(link) else { return nil }
        let matching = tabs.filter { tab in
            guard let url = URL(string: tab.url), let found = room(url) else { return false }
            return found.site == wanted.site && found.room == wanted.room
        }
        return matching.first(where: \.active) ?? matching.first
    }

    /// "abc-defg-hij".
    private static func isMeetCode(_ part: String) -> Bool {
        let pieces = part.split(separator: "-", omittingEmptySubsequences: false)
        return pieces.map(\.count) == [3, 4, 3] && part.allSatisfy { $0 == "-" || ("a"..."z").contains($0) }
    }
}
