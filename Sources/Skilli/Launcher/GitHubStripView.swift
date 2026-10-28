import AppKit
import SkilliCore

/// The GitHub strip under the launcher's search field: the pull requests by
/// group in Git Island's colors ("● 2 Ready  ● 1 Blocked"), the unread
/// notifications on the right. A click on a group opens the GitHub mode on
/// it, anywhere else on everything. Drawn, not laid out: it redraws only when
/// GitHub said something new.
final class GitHubStripView: NSView {
    /// A group clicked, or nil for everything.
    var onOpen: ((PullRequestGroup?) -> Void)?
    private var groups: [(group: PullRequestGroup, count: Int)] = []
    private var unread = 0
    /// False when GitHub had more unread notifications than were read: "+".
    private var unreadComplete = true
    private var problem: String?
    private var reading = false
    /// Server sync waits with nothing for the user to do ("Checking this
    /// Mac…", "Sync paused, retrying at 19:16"): said in grey.
    private var wait: String?
    /// Where each group was drawn, for clicks.
    private var zones: [(rect: NSRect, group: PullRequestGroup?)] = []

    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let inset: CGFloat = 22

    /// Self-test hook: what the strip says.
    private(set) var shownText = ""

    func show(pullRequests: [PullRequest], unread: Int, unreadComplete: Bool = true, problem: String?, reading: Bool, wait: String? = nil) {
        let counts = GitHubInbox.counts(pullRequests)
        groups = PullRequestGroup.allCases.compactMap { group in counts[group].map { (group, $0) } }
        self.unread = unread
        self.unreadComplete = unreadComplete
        self.problem = problem
        self.reading = reading
        self.wait = wait
        let left = groups.isEmpty ? (reading || wait != nil ? "" : "No open pull request") : groups.map { "\($0.count) \($0.group.title)" }.joined(separator: " · ")
        let right = problem.map { "GitHub: \($0)" } ?? wait ?? (reading ? "Reading GitHub…" : unreadText ?? "")
        shownText = [left, right].filter { !$0.isEmpty }.joined(separator: " — ")
        setAccessibilityLabel("GitHub: " + shownText)
        needsDisplay = true
    }

    /// "3 unread", "3+ unread" when the read was cut (even "0+": some may
    /// ask the user, past what was read); nil for none.
    private var unreadText: String? {
        unread > 0 || !unreadComplete ? "\(unread)\(unreadComplete ? "" : "+") unread" : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        zones = []
        let midY = bounds.midY
        var x = Self.inset
        if let mark = Theme.symbol("arrow.triangle.pull", pointSize: 12, weight: .medium)?.tinted(.secondaryLabelColor) {
            mark.draw(in: NSRect(x: x, y: midY - mark.size.height / 2, width: mark.size.width, height: mark.size.height))
            x += mark.size.width + 10
        }
        if groups.isEmpty, !reading, wait == nil {
            x += drawText("No open pull request", at: x, color: .secondaryLabelColor)
        }
        for (group, count) in groups {
            let start = x
            let dot = NSRect(x: x, y: midY - 3.5, width: 7, height: 7)
            CommandIcon.color(group).setFill()
            NSBezierPath(ovalIn: dot).fill()
            x += 7 + 6
            x += drawText("\(count) \(group.title)", at: x, color: .labelColor)
            zones.append((NSRect(x: start - 4, y: 0, width: x - start + 8, height: bounds.height), group))
            x += 16
        }
        // The notifications, or what is wrong, on the right.
        let right: (text: String, color: NSColor, symbol: String?)? = if let problem {
            ("GitHub: \(problem)", .systemOrange, nil)
        } else if let wait {
            (wait, .secondaryLabelColor, nil)
        } else if reading {
            ("Reading GitHub…", .secondaryLabelColor, nil)
        } else if let unreadText {
            (unreadText, .secondaryLabelColor, "bell")
        } else {
            nil
        }
        guard let right else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: right.color]
        let maxWidth = bounds.width - x - Self.inset - 20
        guard maxWidth > 40 else { return }
        let text = NSAttributedString(string: right.text, attributes: attributes)
        let width = min(text.size().width, maxWidth)
        var end = bounds.width - Self.inset
        let textRect = NSRect(x: end - width, y: midY - text.size().height / 2, width: width, height: text.size().height)
        text.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        end -= width + 6
        if let name = right.symbol, let bell = Theme.symbol(name, pointSize: 11, weight: .medium)?.tinted(right.color) {
            bell.draw(in: NSRect(x: end - bell.size.width, y: midY - bell.size.height / 2, width: bell.size.width, height: bell.size.height))
        }
    }

    /// Draws `string` from `x`, centered; its width.
    private func drawText(_ string: String, at x: CGFloat, color: NSColor) -> CGFloat {
        let text = NSAttributedString(string: string, attributes: [.font: Self.font, .foregroundColor: color])
        let size = text.size()
        text.draw(at: NSPoint(x: x, y: bounds.midY - size.height / 2))
        return size.width
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onOpen?(zones.first { $0.rect.contains(point) }?.group)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
}
