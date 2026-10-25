import AppKit
import ApplicationServices
import SkilliCore

/// Arrange Windows (docs/smart-layout.md): every window open where the
/// user usually puts it. A saved layout for what is open comes first (the
/// user's own words); else each window goes to the place learned for its
/// app, its title or file, these displays and the apps beside it
/// (`WindowArrangement`); a window nothing was learned for stays. Run
/// again within 10 s, every window goes back where it was.
@MainActor
final class WindowArrange {
    struct Report: Equatable {
        /// Windows moved (or put back).
        var placed = 0
        /// Windows nothing was learned for: left where they are.
        var unknown = 0
        /// Apps whose window refused to move.
        var refused: [String] = []
        /// Run again soon: put back.
        var restored = false
        /// The saved layout applied instead.
        var layout: String?
        var layoutMessage: String?

        /// What the card says, when there is something to say: the windows
        /// moving are the answer otherwise.
        var message: String? {
            if let layoutMessage { return layoutMessage }
            if !refused.isEmpty {
                let line = "\(ListFormatter.localizedString(byJoining: refused)) did not let skil.li move \(refused.count == 1 ? "its window" : "their windows")"
                return restored ? line + " back: Arrange Windows again tries once more." : line + "."
            }
            if placed == 0, unknown > 0, !restored {
                return "skil.li does not know where these windows go yet: put them where you want once, it learns."
            }
            return nil
        }
    }

    private struct Moved {
        let name: String
        let app: AXUIElement
        let window: AXUIElement
        let before: CGRect
    }

    /// How soon "again" puts the windows back.
    static let again: Duration = .seconds(10)

    private let arranger: WindowArranger
    private let learner: WindowLearner
    private let manager: WindowManager
    /// Apps never placed (Settings → Windows).
    var leftOut: () -> Set<String> = { [] }
    var gap: () -> CGFloat = { 0 }
    private var last: (at: ContinuousClock.Instant, moved: [Moved])?

    init(arranger: WindowArranger, learner: WindowLearner, manager: WindowManager) {
        self.arranger = arranger
        self.learner = learner
        self.manager = manager
    }

    func run() async -> Report {
        let start = ContinuousClock.now
        if let last, start - last.at <= Self.again, !last.moved.isEmpty {
            return putBack(last.moved)
        }
        await learner.catchUp()
        let leftOut = leftOut()
        let open = arranger.windows(all: true).filter {
            $0.state == .normal && !$0.app.isHidden && !leftOut.contains($0.app.bundleIdentifier ?? "")
        }
        let displays = Displays.current()
        var report = Report()
        let apps = Set(open.compactMap(\.app.bundleIdentifier))
        let documents = Set(open.compactMap(\.document))
        if let layout = WindowArrangement.layout(for: apps, documents: documents, among: arranger.layouts(), on: displays) {
            let before = open.map { Moved(name: $0.appName, app: $0.appElement, window: $0.element, before: $0.frame) }
            let applied = await arranger.apply(layout)
            report.layout = layout.name
            report.placed = applied.placed
            report.layoutMessage = applied.hasFailures ? applied.message : nil
            last = (.now, before)
            Log.trace("Arrange Windows: the layout “\(layout.name)”, \(applied.placed) windows, in \((ContinuousClock.now - start).compact)")
            return report
        }
        let keyed = displays.map { WindowArrangement.Display(key: WindowPlacements.displayKey($0.fingerprint), visible: $0.visible) }
        func display(of frame: CGRect) -> Int? {
            let areas = displays.map { $0.frame.intersection(frame) }.map { $0.isNull ? 0 : $0.width * $0.height }
            return areas.indices.max { areas[$0] < areas[$1] }.flatMap { areas[$0] > 0 ? $0 : nil }
        }
        let onDisplay = open.map { display(of: $0.frame) }
        let items = open.indices.map { index in
            let window = open[index]
            let bundleID = window.app.bundleIdentifier ?? ""
            let beside = open.indices.filter { $0 != index && onDisplay[$0] == onDisplay[index] && open[$0].app.bundleIdentifier != bundleID }
                .compactMap { open[$0].app.bundleIdentifier }
            // Its rank among its app's windows shown, as the learner counts.
            let rank = open[..<index].filter { $0.app.processIdentifier == window.app.processIdentifier }.count
            return WindowArrangement.Item(window: .init(bundleID: bundleID, title: window.title, document: window.document,
                                                        rank: rank, with: beside),
                                          frame: window.frame)
        }
        let targets = WindowArrangement.targets(of: items, on: keyed, placements: learner.placements, gap: gap())
        var moved: [Moved] = []
        var lines: [String] = []
        for (window, target) in zip(open, targets) {
            guard let target else {
                report.unknown += 1
                continue
            }
            guard !WindowLayout.matches(window.frame, target, tolerance: 4) else { continue }
            do {
                try WindowManager.place(window.element, of: window.appElement, at: target)
                manager.remember(window.element, pid: window.app.processIdentifier, placed: target, before: window.frame)
                moved.append(Moved(name: window.appName, app: window.appElement, window: window.element, before: window.frame))
                report.placed += 1
                lines.append(window.appName)
            } catch {
                if !report.refused.contains(window.appName) { report.refused.append(window.appName) }
            }
        }
        last = moved.isEmpty ? nil : (.now, moved)
        Log.trace("Arrange Windows: \(report.placed) moved (\(lines.joined(separator: ", "))), \(report.unknown) unknown, \(report.refused.count) refused, of \(open.count), in \((ContinuousClock.now - start).compact)")
        return report
    }

    /// Every window back where it was before the last Arrange. One that
    /// refuses is named and kept: Arrange again once more tries it again.
    private func putBack(_ moved: [Moved]) -> Report {
        var report = Report(restored: true)
        var refused: [Moved] = []
        for item in moved {
            if (try? WindowManager.place(item.window, of: item.app, at: item.before)) != nil {
                report.placed += 1
            } else {
                refused.append(item)
                if !report.refused.contains(item.name) { report.refused.append(item.name) }
            }
        }
        last = refused.isEmpty ? nil : (.now, refused)
        Log.trace("Arrange Windows again: \(report.placed) of \(moved.count) windows put back\(refused.isEmpty ? "" : ", \(refused.count) refused")")
        return report
    }
}
