import AppKit
import SkilliCore

/// The next meeting in the menu bar, and joined (or offered) as it starts,
/// as set in Settings → Calendar. Its moments look apart (`MeetingBar`):
/// coming, started and not joined (red), on (the ring). A call the user is
/// in already, told the same way, gets no alert and is not joined again,
/// and its alert, still up, goes (`MeetingBar.inCall`). Nothing polls: one
/// timer waits for the next moment something changes (the title shows, a
/// minute goes, the meeting starts, it leaves); it is set again when the
/// calendars change, the Mac wakes, the day, the clock or a setting
/// changes, a call is joined from skil.li or another app takes the
/// microphone.
@MainActor
final class MeetingWatch: NSObject, NSMenuDelegate {
    private let calendar: CalendarBook
    private let preferences: Preferences
    /// Whether a call is on on this Mac (another app on the microphone).
    let microphone = MicrophoneUse()
    /// Occurrences seen joined (a call begun around their start): they stay
    /// joined when the microphone stops a moment.
    private var seenInCall: Set<String> = []
    /// "Show Calendar" (the launcher's calendar) in its menu.
    var onOpenAgenda: (() -> Void)?
    /// An alert has come (before a meeting or on time): the event, the
    /// alert.
    var onAlert: ((AgendaEvent, MeetingAlert) -> Void)?
    /// The calls the user is in already (`MeetingBar.key`), told at each
    /// refresh: an alert still up for one of them goes.
    var onInCall: ((Set<String>) -> Void)?
    /// Record in the meeting's menu, once in its call: whether it is
    /// offered now (no recording on), and what it does.
    var canRecord: () -> Bool = { false }
    var onRecord: ((AgendaEvent) -> Void)?
    private var item: NSStatusItem?
    private var shown: AgendaEvent?
    /// The next one, beside the meeting on now.
    private var shownNext: AgendaEvent?
    private var timer: Timer?
    /// Dismissed from the menu bar until the next meeting.
    private var dismissed: Set<String> = []
    /// Already joined or offered as it started.
    private var started: Set<String> = []
    /// Alerts already shown (`MeetingAlerts.due`'s keys).
    private var alerted: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    /// Self-test hooks: the menu bar's text, its help and menu, whether it
    /// is red, its window, and when the timer fires next.
    var shownTitle: String? { item?.button?.title }
    var shownHelp: String? { item?.button?.toolTip }
    var shownUrgent: Bool { item?.button?.image?.isTemplate == false }
    var shownMenu: [String] {
        guard let menu = item?.menu else { return [] }
        menuNeedsUpdate(menu)
        return menu.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "—" : $0.title }
    }
    var itemButton: NSStatusBarButton? { item?.button }
    var itemMenu: NSMenu? { item?.menu }
    var nextChange: Date? { timer?.fireDate }

    init(calendar: CalendarBook, preferences: Preferences) {
        self.calendar = calendar
        self.preferences = preferences
        super.init()
        microphone.onChange = { [weak self] in self?.refresh() }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    /// Reads the coming meetings again and sets the one timer.
    func refresh(now: Date = .now) {
        timer?.invalidate()
        timer = nil
        guard calendar.isAllowed else {
            hide()
            return
        }
        let events = calendar.soonEvents(now: now).filter { !$0.isAllDay && !$0.declined }
        var next: Date?
        func wait(until date: Date) {
            if date > now, date < (next ?? .distantFuture) { next = date }
        }

        let alerts = preferences.agendaAlerts
        let joining = preferences.agendaAutoJoin == .join

        // The menu bar: joined from skil.li, or a call begun on this Mac
        // around its start, else "started" (red when this Mac can tell).
        let options = MeetingBar.Options(preferences)
        // The microphone is watched from a minute before a call's join lead
        // (a call already on then is another one) to the end of its late
        // window, for the calls the menu bar shows, alerts or joins at once:
        // CoreAudio comes into skil.li then, not at launch.
        if !microphone.isStarted {
            let calls = events.filter { $0.meeting != nil && ((options.lead != nil && !dismissed.contains($0.id)) || !alerts.isEmpty || joining) }
            let from = { (event: AgendaEvent) in event.start.addingTimeInterval(-MeetingBar.joinLead - 60) }
            if calls.contains(where: { now >= from($0) && now < $0.start.addingTimeInterval(MeetingBar.lateWindow) }) {
                microphone.start()
            } else {
                calls.map(from).forEach(wait)
            }
        }
        let presence = MeetingBar.Presence(joined: calendar.joined.union(seenInCall), microphone: microphone.microphone)
        let plan = MeetingBar.plan(events, now: now, options: options, presence: presence, dismissed: dismissed)
        if let shown = plan.shown, shown.start <= now, case .inUse = presence.microphone, MeetingBar.joined(shown, presence, among: events) {
            seenInCall.insert(MeetingBar.key(shown))
        }
        if let shown = plan.shown, let state = plan.state {
            show(shown, state: state, next: plan.next)
        } else {
            hide()
        }
        plan.changes.forEach(wait)
        // In a call already: its alert, still up, goes (the screens dark
        // around it come back).
        onInCall?(Set(events.filter { MeetingBar.inCall($0, presence, among: events) }.map(MeetingBar.key)))

        // Joined at once as it starts (within its first minute), when set:
        // its call opens, so no alert On time for it. Not when the user is
        // in it already.
        if joining {
            for event in events where event.meeting != nil && !started.contains(event.id) {
                if event.start <= now, now.timeIntervalSince(event.start) < 60 {
                    started.insert(event.id)
                    if MeetingAlerts.joinsAtOnce(event, among: events, presence: presence) { calendar.join(event) }
                } else {
                    wait(until: event.start)
                }
            }
        }

        // Alerts, before a meeting and on time, each once at its minute (the
        // Mac asleep then: nothing late), none for a call the user is in
        // already. Events without a call too when asked.
        if !alerts.isEmpty {
            let watched = events.filter { $0.meeting != nil || preferences.agendaAlertWithoutCall }
            for due in MeetingAlerts.due(watched, alerts: alerts, now: now, shown: alerted) {
                alerted.formUnion(due.keys)
                if MeetingAlerts.shows(due.alert, for: due.event, among: events, joining: joining, presence: presence) { onAlert?(due.event, due.alert) }
            }
            if let moment = MeetingAlerts.next(watched, alerts: alerts, now: now) { wait(until: moment) }
        }

        guard let next else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The item's image, words and help for `event` in `state`, the next
    /// one beside it: a calendar while it comes, the ring while it is on,
    /// a camera once the call started (red while no one joined it from
    /// this Mac). Settings → Calendar's preview draws it too.
    static func appearance(of event: AgendaEvent, state: MeetingBar.State, next: AgendaEvent?) -> (image: NSImage?, title: String, help: String) {
        let look = MeetingBar.look(of: event, state: state, next: next)
        let image: NSImage?
        switch look.glyph {
        case .calendar:
            image = Theme.symbol("calendar", pointSize: 12, weight: .medium)
        case .ring(let remaining):
            image = ring(remaining: remaining)
        case .call:
            image = Theme.symbol("video.fill", pointSize: 12, weight: .medium)
        }
        return (look.urgent ? image.map(red) : image, " \(look.title)", look.help)
    }

    /// The symbol in the system's red (a color the menu bar keeps, as for
    /// the meeting card's "STARTED … AGO"): not a template.
    private static func red(_ symbol: NSImage) -> NSImage {
        let colored = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed])) ?? symbol
        colored.isTemplate = false
        return colored
    }

    /// `event` on now or coming; `next`: the one after, shown short beside it.
    private func show(_ event: AgendaEvent, state: MeetingBar.State, next: AgendaEvent?) {
        let item = self.item ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        shown = event
        shownNext = next
        let look = Self.appearance(of: event, state: state, next: next)
        item.button?.image = look.image
        item.button?.title = look.title
        item.button?.toolTip = look.help
        item.button?.imagePosition = .imageLeading
        item.menu = menu(for: event, next: next)
        item.isVisible = true
    }

    /// A ring for the menu bar, full at the start, empty at the end
    /// (template: the menu bar colors it).
    static func ring(remaining: Double) -> NSImage {
        let fraction = min(max(remaining, 0), 1)
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: 5.5, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.6
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: 5.5, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
            arc.lineWidth = 1.6
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func hide() {
        shown = nil
        shownNext = nil
        if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    /// Whether the user is in `event`'s call already, as the menu bar tells
    /// it (`MeetingBar.inCall`).
    func isInCall(_ event: AgendaEvent, now: Date = .now) -> Bool {
        let presence = MeetingBar.Presence(joined: calendar.joined.union(seenInCall), microphone: microphone.microphone)
        return MeetingBar.inCall(event, presence, among: calendar.soonEvents(now: now))
    }

    private func menu(for event: AgendaEvent, next: AgendaEvent?) -> NSMenu {
        let menu = NSMenu()
        if let meeting = event.meeting {
            menu.addItem(item("Join \(meeting.service)", #selector(join)))
        }
        // In its call and not recorded: Record, ⌘R as everywhere; told as
        // the menu opens (`menuNeedsUpdate`).
        if event.meeting != nil {
            let record = item("Record “\(MeetingBar.short(event.title, 32))”", #selector(record))
            record.keyEquivalent = "r"
            record.keyEquivalentModifierMask = .command
            record.tag = Self.recordTag
            record.isHidden = !recordable(event)
            menu.addItem(record)
            menu.delegate = self
        }
        menu.addItem(item("Show in Calendar", #selector(showInCalendar)))
        if let next {
            menu.addItem(.separator())
            let title = NSMenuItem(title: "Next: \(MeetingBar.short(next.title, 40)) · \(MeetingBar.clock(next.start))", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            if let meeting = next.meeting {
                menu.addItem(item("Join \(meeting.service)", #selector(joinNext)))
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Show Calendar", #selector(openAgenda)))
        menu.addItem(item("Dismiss", #selector(dismiss)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func join() {
        if let shown { calendar.join(shown) }
    }

    @objc private func record() {
        if let shown { onRecord?(shown) }
    }

    private static let recordTag = 7_001

    /// Record shows in `event`'s menu: in its call, no recording on.
    private func recordable(_ event: AgendaEvent) -> Bool {
        MeetingMoment.isRecordable(event, now: .now) && isInCall(event) && canRecord()
    }

    @objc private func joinNext() {
        if let shownNext { calendar.join(shownNext) }
    }

    @objc private func openAgenda() {
        onOpenAgenda?()
    }

    @objc private func showInCalendar() {
        if let shown { calendar.openInCalendar(shown) }
    }

    @objc private func dismiss() {
        if let shown { dismissed.insert(shown.id) }
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let shown, let record = menu.item(withTag: Self.recordTag) else { return }
        record.isHidden = !recordable(shown)
    }

    /// Self-test hook: forget what was dismissed, offered or joined.
    func resetForTest() {
        dismissed = []
        started = []
        alerted = []
        seenInCall = []
        calendar.forgetJoins()
    }
}

extension MeetingBar.Options {
    @MainActor
    init(_ preferences: Preferences) {
        self.init(lead: preferences.agendaMenuBar.lead, callsOnly: preferences.agendaMenuBarCallsOnly, countdown: preferences.agendaCountdown,
                  hideAfter: preferences.agendaHideAfter, nextDuringMeeting: preferences.agendaNextDuringMeeting)
    }
}
