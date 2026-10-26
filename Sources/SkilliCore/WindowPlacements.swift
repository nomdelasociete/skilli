import CoreGraphics
import Foundation

/// Where the user puts each app's windows, learned from their own moves
/// (docs/smart-layout.md): for each app and set of displays connected,
/// its last placements, each with the place, the display, the window's
/// title and file, and the apps beside it. Arrange Windows asks it where
/// each window goes now. Kept on the Mac (`placements.json`), never sent.
public struct WindowPlacements: Codable, Equatable, Sendable {
    /// A place on a display, kept so it carries to another resolution: a
    /// named place (the left two thirds) stays that place with the gap of
    /// the moment; any other frame keeps its proportions.
    public struct Place: Codable, Equatable, Sendable {
        /// Of the display's usable area, 0…1 across and down.
        public var fraction: CGRect
        /// The `WindowLayout` it was within 24 points of, and its size.
        public var layout: String?
        public var size: Int

        public init(fraction: CGRect, layout: String? = nil, size: Int = 0) {
            self.fraction = fraction
            self.layout = layout
            self.size = size
        }

        /// How far from a named place a frame still is that place: apps
        /// round sizes to their own steps, a hand's drag is never exact.
        public static let snap: CGFloat = 24

        /// The place of `frame` on a display whose usable area is `visible`.
        public static func of(_ frame: CGRect, in visible: CGRect, gap: CGFloat = 0) -> Place {
            for layout in WindowLayout.allCases {
                for (size, fraction) in layout.sizes.enumerated() {
                    if let named = layout.frame(in: visible, gap: gap, size: size), WindowLayout.matches(frame, named, tolerance: snap) {
                        return Place(fraction: fraction, layout: layout.rawValue, size: size)
                    }
                }
            }
            guard visible.width > 0, visible.height > 0 else { return Place(fraction: CGRect(x: 0, y: 0, width: 1, height: 1)) }
            let x = min(max((frame.minX - visible.minX) / visible.width, 0), 1)
            let y = min(max((frame.minY - visible.minY) / visible.height, 0), 1)
            let width = min(frame.width / visible.width, 1 - x)
            let height = min(frame.height / visible.height, 1 - y)
            return Place(fraction: Self.rounded(CGRect(x: x, y: y, width: width, height: height)))
        }

        /// Where it is on a display whose usable area is `visible`.
        public func frame(in visible: CGRect, gap: CGFloat = 0) -> CGRect {
            if let layout = layout.flatMap(WindowLayout.init(rawValue:)), let frame = layout.frame(in: visible, gap: gap, size: size) {
                return frame
            }
            return WindowLayout.place(fraction, in: visible)
        }

        /// The same place, a few points apart.
        public func near(_ other: Place) -> Bool {
            if let layout, layout == other.layout { return size == other.size }
            let a = fraction, b = other.fraction
            return abs(a.minX - b.minX) <= 0.02 && abs(a.minY - b.minY) <= 0.02
                && abs(a.width - b.width) <= 0.02 && abs(a.height - b.height) <= 0.02
        }

        /// To a thousandth: the file stays readable, nothing a hand can see
        /// is lost.
        private static func rounded(_ rect: CGRect) -> CGRect {
            func r(_ value: CGFloat) -> CGFloat { (value * 1_000).rounded() / 1_000 }
            return CGRect(x: r(rect.minX), y: r(rect.minY), width: r(rect.width), height: r(rect.height))
        }
    }

    /// One window where the user put it.
    public struct Placement: Codable, Equatable, Sendable {
        public enum How: String, Codable, Sendable {
            /// Moved or resized by hand, seen when its app left the front.
            case hand
            /// Placed with ✦W (or a place from the launcher): on purpose.
            case key
        }

        public var place: Place
        /// The display it was on (`displayKey`).
        public var display: String
        /// Its title's first 80 characters, to tell the app's windows apart.
        public var title: String
        /// The file it showed (AXDocument), when it said.
        public var document: String?
        /// Its rank among its app's windows, front first.
        public var rank: Int
        /// The other apps with a window on the same display, by bundle id.
        public var with: [String]
        public var how: How
        public var at: Date

        public init(place: Place, display: String, title: String, document: String? = nil, rank: Int = 0,
                    with: [String] = [], how: How = .hand, at: Date) {
            self.place = place
            self.display = display
            self.title = String(title.prefix(WindowPlacements.titleLength))
            self.document = document
            self.rank = rank
            self.with = Array(Set(with)).sorted()
            self.how = how
            self.at = at
        }
    }

    /// A window open now, as Arrange asks about it.
    public struct Window: Equatable, Sendable {
        public var bundleID: String
        public var title: String
        public var document: String?
        public var rank: Int
        /// The other apps with a window on the same display now.
        public var with: [String]

        public init(bundleID: String, title: String, document: String? = nil, rank: Int = 0, with: [String] = []) {
            self.bundleID = bundleID
            self.title = title
            self.document = document
            self.rank = rank
            self.with = with
        }
    }

    /// A place a window can go, with what speaks for it.
    public struct Choice: Equatable, Sendable {
        public var place: Place
        public var display: String
        /// The weight of the placements there, faded and weighed.
        public var weight: Double
        /// Of the window's whole weight in this context, 0…1.
        public var share: Double
        /// How many placements are there.
        public var count: Int
    }

    public static let titleLength = 80
    /// Placements kept for each app and set of displays, the newest.
    public static let kept = 48
    /// Habits change: a placement counts half after a month.
    public static let halfLife: TimeInterval = 30 * 24 * 3_600

    /// "bundle id\ndisplays key" → its placements, oldest first.
    public private(set) var entries: [String: [Placement]]

    public init(entries: [String: [Placement]] = [:]) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }

    // MARK: - Keys

    /// Who a display is, for placements: the Mac's own screen, or an
    /// external one by its maker, model and serial (macOS's id for it when
    /// it has no serial).
    public static func displayKey(_ display: DisplayFingerprint) -> String {
        if display.builtIn { return builtIn }
        let serial = display.serialText.flatMap { $0.isEmpty ? nil : $0 } ?? (display.serial != 0 ? String(display.serial) : display.uuid)
        return "\(display.vendor)-\(display.model)-\(serial)"
    }

    public static let builtIn = "built-in"

    /// The displays connected, in any order.
    public static func displaysKey(_ displays: [String]) -> String {
        displays.sorted().joined(separator: "+")
    }

    private static func key(_ bundleID: String, _ displays: [String]) -> String {
        "\(bundleID)\n\(displaysKey(displays))"
    }

    // MARK: - Learning

    /// One more placement of `bundleID`'s window, with `displays` connected.
    public mutating func record(_ placement: Placement, bundleID: String, displays: [String]) {
        guard !bundleID.isEmpty, !displays.isEmpty else { return }
        let key = Self.key(bundleID, displays)
        var list = entries[key, default: []]
        list.append(placement)
        if list.count > Self.kept { list.removeFirst(list.count - Self.kept) }
        entries[key] = list
    }

    /// The apps something was learned about, by bundle id.
    public var apps: Set<String> {
        Set(entries.keys.map { String($0.prefix { $0 != "\n" }) })
    }

    // MARK: - Choosing

    /// Where `window` can go with `displays` connected (the menu bar's
    /// first), best first: its app's placements with these displays, each
    /// faded with age, doubled when placed with ✦W, weighed by how alike
    /// the apps beside it were and how alike the window was (its file, its
    /// title's words, else its rank). With nothing for these displays, the
    /// app's placements with other displays, on a display connected now
    /// (the same one, else one of the same kind), at half their weight.
    /// Placements a few points apart are one place.
    public func choices(for window: Window, displays: [String], at now: Date) -> [Choice] {
        guard !displays.isEmpty else { return [] }
        var weighed: [(placement: Placement, display: String, weight: Double)] = []
        let here = entries[Self.key(window.bundleID, displays)] ?? []
        if !here.isEmpty {
            let common = Self.commonWords(here.map(\.title) + [window.title])
            let uniform = Set(here.map(\.title) + [window.title]).count == 1
            for placement in here where displays.contains(placement.display) {
                weighed.append((placement, placement.display, weight(placement, for: window, common: common, uniform: uniform, at: now)))
            }
        } else {
            let prefix = "\(window.bundleID)\n"
            let elsewhere = entries.filter { $0.key.hasPrefix(prefix) }.flatMap(\.value)
            let common = Self.commonWords(elsewhere.map(\.title) + [window.title])
            let uniform = Set(elsewhere.map(\.title) + [window.title]).count == 1
            let externals = displays.filter { $0 != Self.builtIn }
            for placement in elsewhere {
                let display: String? = displays.contains(placement.display) ? placement.display
                    : placement.display == Self.builtIn ? nil : externals.first
                guard let display else { continue }
                weighed.append((placement, display, weight(placement, for: window, common: common, uniform: uniform, at: now) / 2))
            }
        }
        let total = weighed.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        var choices: [Choice] = []
        for item in weighed.sorted(by: { $0.weight > $1.weight }) {
            if let index = choices.firstIndex(where: { $0.display == item.display && $0.place.near(item.placement.place) }) {
                choices[index].weight += item.weight
                choices[index].count += 1
            } else {
                choices.append(Choice(place: item.placement.place, display: item.display, weight: item.weight, share: 0, count: 1))
            }
        }
        for index in choices.indices { choices[index].share = choices[index].weight / total }
        return choices.sorted { $0.weight > $1.weight }
    }

    /// The place Usual places may put `window` in without asking: the best
    /// choice with these very displays, held by at least 3 placements and
    /// 70 % of the weight, and the last 3 placements of the windows most
    /// like it all there (moved elsewhere lately: not sure until the place
    /// is confirmed again). An empty title is never enough, unless the
    /// app's windows are told apart by rank.
    public func sure(for window: Window, displays: [String], at now: Date) -> Choice? {
        let here = entries[Self.key(window.bundleID, displays)] ?? []
        guard here.count >= Self.sureCount else { return nil }
        let titles = here.map(\.title) + [window.title]
        let uniform = Set(titles).count == 1
        if window.title.isEmpty, !uniform { return nil }
        guard let best = choices(for: window, displays: displays, at: now).first,
              best.count >= Self.sureCount, best.share >= Self.sureShare else { return nil }
        // The windows most like this one, newest first.
        let common = Self.commonWords(titles)
        let likeness = here.map { Self.alike($0, window, common: common, uniform: uniform) }
        let most = likeness.max() ?? 0
        let latest = here.indices.filter { likeness[$0] >= most }.sorted { here[$0].at > here[$1].at }.prefix(Self.sureCount)
        guard latest.allSatisfy({ here[$0].display == best.display && here[$0].place.near(best.place) }) else { return nil }
        return best
    }

    /// Enough placements of this app on these very displays for one of its
    /// windows to ever be sure: whether a new window of it is worth
    /// watching for.
    public func mayBeSure(bundleID: String, displays: [String]) -> Bool {
        (entries[Self.key(bundleID, displays)]?.count ?? 0) >= Self.sureCount
    }

    /// How many placements, and how much of the weight, a sure place holds.
    public static let sureCount = 3
    public static let sureShare = 0.7

    private func weight(_ placement: Placement, for window: Window, common: Set<String>, uniform: Bool, at now: Date) -> Double {
        let age = max(now.timeIntervalSince(placement.at), 0)
        var weight = pow(0.5, age / Self.halfLife)
        if placement.how == .key { weight *= 2 }
        weight *= max(Self.alike(Set(placement.with), Set(window.with)) ?? 1, 0.2)
        weight *= Self.alike(placement, window, common: common, uniform: uniform)
        return weight
    }

    /// How alike a placement's window is to this one: the same file ×3;
    /// else, when the app's titles tell its windows apart, ×1 to ×3 by the
    /// words they share (the words every title of the app has left out);
    /// else the same rank ×2.
    static func alike(_ placement: Placement, _ window: Window, common: Set<String>, uniform: Bool) -> Double {
        if let document = placement.document, document == window.document { return 3 }
        if uniform { return placement.rank == window.rank ? 2 : 1 }
        let a = words(placement.title).subtracting(common)
        let b = words(window.title).subtracting(common)
        return 1 + 2 * (alike(a, b) ?? 0)
    }

    /// Shared over all, 0…1; nil when both are empty.
    static func alike(_ a: Set<String>, _ b: Set<String>) -> Double? {
        let all = a.union(b)
        guard !all.isEmpty else { return nil }
        return Double(a.intersection(b).count) / Double(all.count)
    }

    /// A title's words, lowercased: none under 3 letters, no numbers.
    static func words(_ title: String) -> Set<String> {
        Set(title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) })
    }

    /// The words every one of these titles has ("Google", "Chrome"), when
    /// there are at least two different titles: they tell nothing apart.
    static func commonWords(_ titles: [String]) -> Set<String> {
        let distinct = Set(titles)
        guard distinct.count > 1 else { return [] }
        var common: Set<String>?
        for title in distinct { common = common.map { $0.intersection(words(title)) } ?? words(title) }
        return common ?? []
    }
}

/// Where Arrange Windows puts each window open now.
public enum WindowArrangement {
    /// A window open now and where it is.
    public struct Item: Equatable, Sendable {
        public var window: WindowPlacements.Window
        public var frame: CGRect

        public init(window: WindowPlacements.Window, frame: CGRect) {
            self.window = window
            self.frame = frame
        }
    }

    /// A display connected now: who it is (`WindowPlacements.displayKey`)
    /// and its usable area.
    public struct Display: Equatable, Sendable {
        public var key: String
        public var visible: CGRect

        public init(key: String, visible: CGRect) {
            self.key = key
            self.visible = visible
        }
    }

    /// For each window, where it goes; nil where nothing was learned for
    /// it, or where its app's other windows took every place it has (two
    /// windows of an app never get the same place: the one whose title or
    /// file fits it better does; windows of different apps may share one,
    /// as the user stacks them).
    public static func targets(of items: [Item], on displays: [Display], placements: WindowPlacements,
                               gap: CGFloat = 0, at now: Date = .now) -> [CGRect?] {
        let keys = displays.map(\.key)
        let choices = items.map { placements.choices(for: $0.window, displays: keys, at: now) }
        var chosen = [WindowPlacements.Choice?](repeating: nil, count: items.count)
        var byApp: [String: [Int]] = [:]
        for index in items.indices { byApp[items[index].window.bundleID, default: []].append(index) }
        for indices in byApp.values {
            // The strongest claims first.
            let claims = indices.flatMap { index in choices[index].map { (index: index, choice: $0) } }
                .sorted { $0.choice.weight > $1.choice.weight }
            var taken: [WindowPlacements.Choice] = []
            for claim in claims where chosen[claim.index] == nil {
                guard !taken.contains(where: { $0.display == claim.choice.display && $0.place.near(claim.choice.place) }) else { continue }
                chosen[claim.index] = claim.choice
                taken.append(claim.choice)
            }
        }
        return chosen.map { choice in
            guard let choice, let display = displays.first(where: { $0.key == choice.display }) else { return nil }
            return choice.place.frame(in: display.visible, gap: gap)
        }
    }

    /// The saved layout for what is open now, when there is one: its
    /// displays the ones connected (each surely itself), its apps the apps
    /// with a window open, and nothing for it to open (no file, folder or
    /// link it opens, each file it shows among `documents`, the files open
    /// now): Arrange again only puts windows back, it cannot close what a
    /// layout opened. The newest when several are.
    public static func layout(for apps: Set<String>, documents: Set<String> = [], among layouts: [SavedWindowLayout],
                              on displays: [LayoutDisplay]) -> SavedWindowLayout? {
        guard !apps.isEmpty else { return nil }
        return layouts.filter { layout in
            guard layout.displays.count == displays.count, Set(layout.windows.map(\.bundleID)) == apps,
                  layout.windows.allSatisfy({ $0.opens == nil && ($0.document.map(documents.contains) ?? true) }) else { return false }
            let pairs = DisplayPairing.pair(saved: layout.displays, current: displays)
            return pairs.count == layout.displays.count && pairs.allSatisfy { $0.match == .same(.unit) || $0.match == .same(.model) }
        }.max { $0.saved < $1.saved }
    }
}

/// Arrange as Usual in the question a display plugged in asks
/// (docs/smart-layout.md → Display plugged in): offered when what was
/// learned places at least half of the windows open, on displays the user
/// has not refused it for.
public enum ArrangeOffer {
    /// A set of displays connected together, as Never Arrange on These
    /// Displays keeps it: who they are, and their names for Settings.
    public struct DisplaySet: Codable, Equatable, Sendable {
        /// `WindowPlacements.displaysKey` of the displays' keys.
        public var key: String
        public var names: [String]

        public init(key: String, names: [String]) {
            self.key = key
            self.names = names
        }

        /// "Example 27 and Built-in Retina Display".
        public var label: String { names.joined(separator: " and ") }
    }

    /// The displays connected, as one set.
    public static func displaySet(_ displays: [DisplayFingerprint]) -> DisplaySet {
        DisplaySet(key: WindowPlacements.displaysKey(displays.map(WindowPlacements.displayKey)), names: displays.map(\.name))
    }

    /// Worth asking: some windows have a place, at least half of them.
    public static func offered(placed: Int, of total: Int) -> Bool {
        placed > 0 && placed * 2 >= total
    }

    /// The row for these displays, unless refused for them.
    public static func refused(_ displays: DisplaySet, in never: [DisplaySet]) -> Bool {
        never.contains { $0.key == displays.key }
    }
}

/// Usual places (docs/smart-layout.md): a window an app just opened goes to
/// its usual place only while the user has not touched it.
public enum UsualPlace {
    /// How long a new window is still untouched, at most.
    public static let fresh: TimeInterval = 1.5

    /// Opened less than `fresh` ago, no key typed and no click since, the
    /// mouse button up. Times are seconds ago.
    public static func untouched(appearedAgo: TimeInterval, keyAgo: TimeInterval, clickAgo: TimeInterval, mouseDown: Bool) -> Bool {
        appearedAgo <= fresh && keyAgo > appearedAgo && clickAgo > appearedAgo && !mouseDown
    }
}
