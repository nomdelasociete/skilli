import AppKit
import SkilliCore
import SwiftUI

// What a display option will look like, beside it in Settings, drawn by the
// same code as the real thing from sample data: the menu bar items
// (`MeetingWatch`, `ReminderWatch`) and the launcher's GitHub strip.

/// A slice of the menu bar: an item, then the status icons and the clock,
/// which tells the moment shown.
struct MenuBarMock: View {
    let image: NSImage?
    /// Nil: nothing of skil.li's there then.
    let title: String?
    let clock: String

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let title {
                HStack(spacing: 2) {
                    if let image {
                        // A template follows the menu bar; the red camera
                        // (a call started, not joined) keeps its color.
                        Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
                    }
                    Text(title).lineLimit(1)
                }
            } else {
                Text("not shown").italic().foregroundStyle(.tertiary)
            }
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(clock).monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}

/// The meeting in the menu bar at the moments that matter, as the options
/// set it: two sample meetings with a call, back to back. Each moment looks
/// apart: coming (a calendar), started and not joined (red), joined (the
/// ring), the next one beside it.
struct MeetingMenuBarPreview: View {
    let options: MeetingBar.Options

    private struct Moment: Identifiable {
        let id: String
        let image: NSImage?
        let title: String?
        let clock: String
    }

    private static let today = Calendar.current.startOfDay(for: .now)
    private static func at(_ hour: Int, _ minute: Int) -> Date {
        today.addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
    }
    private static let sync = AgendaEvent(id: "preview-sync", title: "Weekly sync", start: at(14, 0), end: at(14, 30),
                                          notes: "https://meet.google.com/abc-defg-hij")
    private static let standup = AgendaEvent(id: "preview-standup", title: "Standup", start: at(14, 30), end: at(14, 45),
                                             notes: "https://meet.google.com/xyz-abcd-efg")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview").font(.caption).foregroundStyle(.secondary)
            ForEach(moments) { moment in
                HStack(spacing: 12) {
                    Text(moment.id).font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                    MenuBarMock(image: moment.image, title: moment.title, clock: moment.clock)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Before the first one (when it shows that early), started and not
    /// joined, joined, past the time it leaves (without the countdown), as
    /// the next one comes.
    private var moments: [Moment] {
        guard let lead = options.lead else { return [] }
        let sync = Self.sync, standup = Self.standup
        let notJoined = MeetingBar.Presence(microphone: .idle)
        let joined = MeetingBar.Presence(joined: [MeetingBar.key(sync)], microphone: .idle)
        var times: [(String, Date, MeetingBar.Presence)] = []
        if lead > 0 {
            let minutes = lead == .max ? 10 : min(lead, 10)
            times.append(("\(minutes) min before", sync.start.addingTimeInterval(-TimeInterval(minutes * 60)), notJoined))
        }
        times.append(("Started, not joined", sync.start.addingTimeInterval(2 * 60), notJoined))
        times.append(("Joined", sync.start.addingTimeInterval(8 * 60), joined))
        if !options.countdown, options.hideAfter > 0 {
            times.append(("\(options.hideAfter + 1) min in", sync.start.addingTimeInterval(TimeInterval((options.hideAfter + 1) * 60)), joined))
        }
        if lead > 0 {
            let minutes = lead == .max ? 6 : min(lead, 6)
            times.append(("\(minutes) min before the next", standup.start.addingTimeInterval(-TimeInterval(minutes * 60)), joined))
        }
        return times.sorted { $0.1 < $1.1 }.map { caption, time, presence in
            let plan = MeetingBar.plan([sync, standup], now: time, options: options, presence: presence)
            let look = plan.shown.flatMap { shown in plan.state.map { MeetingWatch.appearance(of: shown, state: $0, next: plan.next) } }
            return Moment(id: caption, image: look?.image, title: look?.title, clock: MeetingBar.clock(time))
        }
    }
}

/// Today's reminders in the menu bar as the option sets it: two due.
struct RemindersMenuBarPreview: View {
    let mode: RemindersMenuBar

    var body: some View {
        let due = [ReminderItem(id: "preview-bill", title: "Payer la facture", due: Calendar.current.startOfDay(for: .now)),
                   ReminderItem(id: "preview-call", title: "Appeler Paul", due: Calendar.current.startOfDay(for: .now))]
        let look = ReminderWatch.appearance(due, mode: mode)
        HStack(spacing: 12) {
            Text("Preview").font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            MenuBarMock(image: look.image, title: look.title, clock: MeetingBar.clock(Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3_600)))
        }
        .padding(.vertical, 4)
    }
}

/// The launcher's top as it opens with the GitHub strip under the field:
/// sample pull requests and notifications.
struct GitHubStripPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // Laid out for 520 pt, then follows the width the pane gives it.
        let width: CGFloat = 520
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 84))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        let field = NSTextField(labelWithString: "Search")
        field.font = .systemFont(ofSize: 20)
        field.textColor = .tertiaryLabelColor
        field.frame = NSRect(x: 44, y: 46, width: 200, height: 26)
        root.addSubview(field)
        if let glass = Theme.symbol("magnifyingglass", pointSize: 15, weight: .medium) {
            let icon = NSImageView(image: glass)
            icon.contentTintColor = .secondaryLabelColor
            icon.frame = NSRect(x: 16, y: 48, width: 20, height: 22)
            root.addSubview(icon)
        }
        let line = NSView(frame: NSRect(x: 12, y: 38, width: width - 24, height: 1))
        line.autoresizingMask = [.width]
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        root.addSubview(line)
        let strip = GitHubStripView(frame: NSRect(x: 0, y: 4, width: width, height: 32))
        strip.autoresizingMask = [.width]
        strip.show(pullRequests: Self.samples, unread: 3, problem: nil, reading: false)
        root.addSubview(strip)
        return root
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 520, height: 84)
    }

    private static let samples: [PullRequest] = [
        sample(1, .ready), sample(2, .ready), sample(3, .blocked), sample(4, .testing)
    ]

    private static func sample(_ number: Int, _ group: PullRequestGroup) -> PullRequest {
        PullRequest(id: number, repository: "skilli", repositoryFullName: "nomdelasociete/skilli", number: number, title: "Sample \(number)",
                    group: group, reason: "", statusLabel: "", needsUserAction: false, isAuthor: true, createdAt: .now, updatedAt: .now,
                    url: URL(string: "https://github.com/nomdelasociete/skilli/pull/\(number)")!, headSHA: "", defaultMergeMethod: nil,
                    canUpdateBranch: false)
    }
}

/// A meeting alert as it shows, drawn by the card's own view on glass:
/// alone, or on the dark of "Card, screens dark"; as wide as the pane gives
/// (never wider: the form would run past the window).
struct MeetingCardPreview: NSViewRepresentable {
    let dark: Bool
    let minutes: Int

    func makeNSView(context: Context) -> MeetingCardPreviewView {
        MeetingCardPreviewView()
    }

    func updateNSView(_ view: MeetingCardPreviewView, context: Context) {
        view.configure(dark: dark, minutes: minutes)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MeetingCardPreviewView, context: Context) -> CGSize? {
        let width = proposal.width ?? 480
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }
}

/// The preview's frame: the pane's tint or the dark, the card on glass in
/// its middle, laid out at the width it is given.
final class MeetingCardPreviewView: NSView {
    private static let padding: CGFloat = 18
    private let card = MeetingCardView(frame: .zero)
    /// Measures for SwiftUI's sizing: the card on screen is never laid out
    /// outside its own layout pass.
    private let measure = MeetingCardView(frame: .zero)
    private let glass: NSGlassEffectView

    init() {
        glass = Theme.glass(cornerRadius: Theme.Radius.card, content: card)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(dark: Bool, minutes: Int) {
        layer?.backgroundColor = (dark ? NSColor.black.withAlphaComponent(0.82) : NSColor.labelColor.withAlphaComponent(0.05)).cgColor
        let sample = MeetingCardView.sample(startingIn: TimeInterval(minutes * 60) - 1)
        card.show(sample, now: .now)
        measure.show(sample, now: .now)
        needsLayout = true
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        measure.cardWidth = Self.cardWidth(in: width)
        return measure.fittingHeight + 2 * Self.padding
    }

    override func layout() {
        super.layout()
        card.cardWidth = Self.cardWidth(in: bounds.width)
        let height = card.fittingHeight
        glass.frame = NSRect(x: ((bounds.width - card.cardWidth) / 2).rounded(), y: Self.padding, width: card.cardWidth, height: height)
        card.frame = glass.bounds
    }

    private static func cardWidth(in width: CGFloat) -> CGFloat {
        min(MeetingCardView.width, max(360, width - 2 * padding))
    }
}

/// Settings → Windows → Space between windows: a screen with three windows
/// where ✦W puts them (the left half, the right quarters), placed by
/// `WindowLayout`'s own geometry with the gap chosen. The sample screen is
/// 960 × 600 points, drawn at 0.3 of it.
struct WindowGapPreview: View {
    let gap: CGFloat

    private static let screen = CGRect(x: 0, y: 0, width: 960, height: 600)
    private static let menuBar: CGFloat = 24
    private static let scale: CGFloat = 0.3

    var body: some View {
        let visible = CGRect(x: 0, y: Self.menuBar, width: Self.screen.width, height: Self.screen.height - Self.menuBar)
        let windows: [(WindowLayout, Color)] = [(.leftHalf, .teal), (.topRight, .indigo), (.bottomRight, .orange)]
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color.teal.opacity(0.35), Color.blue.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: Self.menuBar * Self.scale)
            ForEach(windows.indices, id: \.self) { index in
                if let frame = windows[index].0.frame(in: visible, gap: gap) {
                    MiniWindow(tint: windows[index].1)
                        .frame(width: frame.width * Self.scale, height: frame.height * Self.scale)
                        .offset(x: frame.minX * Self.scale, y: frame.minY * Self.scale)
                }
            }
        }
        .frame(width: Self.screen.width * Self.scale, height: Self.screen.height * Self.scale)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: gap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gap == 0 ? "Windows side by side, touching" : "Windows side by side, \(Int(gap)) points apart")
    }

    /// A window: its title bar with the three buttons, its content.
    private struct MiniWindow: View {
        let tint: Color

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.primary.opacity(0.25)).frame(width: 4, height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .frame(height: 10)
                .background(tint.opacity(0.35))
                Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
        }
    }
}
