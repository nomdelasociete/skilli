import AppKit
import SkilliCore

/// Today's reminders in the menu bar, as set in Settings → Reminders: how
/// many are due today or overdue (and the next one), hidden when none; its
/// menu checks one off, opens them in skil.li or in Reminders. Nothing
/// polls: read again when the reminders change, the Mac wakes, the day
/// changes, or the next one falls due.
@MainActor
final class ReminderWatch: NSObject {
    private let reminders: ReminderBook
    private let preferences: Preferences
    /// "Show in skil.li": the Reminders mode.
    var onOpenReminders: (() -> Void)?
    private var item: NSStatusItem?
    private var due: [ReminderItem] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var reading: Task<Void, Never>?
    /// Self-test hook: the menu bar's text.
    var shownTitle: String? { item?.button?.title }

    init(reminders: ReminderBook, preferences: Preferences) {
        self.reminders = reminders
        self.preferences = preferences
        super.init()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        timer?.invalidate()
        timer = nil
        reading?.cancel()
        guard preferences.remindersMenuBar != .never, reminders.isAllowed else {
            hide()
            return
        }
        reading = Task { [weak self] in
            guard let self else { return }
            let items = await self.reminders.items()
            guard !Task.isCancelled else { return }
            self.show(Reminders.dueToday(items, now: .now))
            // The next one to fall due today moves into "overdue": the
            // title says it, so read again then.
            if let next = items.compactMap({ $0.isCompleted || !$0.hasTime ? nil : $0.due }).filter({ $0 > .now }).min() {
                let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
                timer.tolerance = 1
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        }
    }

    private func show(_ items: [ReminderItem]) {
        due = items
        guard !items.isEmpty else {
            hide()
            return
        }
        let item = self.item ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        let look = Self.appearance(items, mode: preferences.remindersMenuBar)
        item.button?.image = look.image
        item.button?.imagePosition = .imageLeading
        item.button?.title = look.title
        item.menu = menu()
        item.isVisible = true
    }

    /// The item's image and title for the reminders due (Settings →
    /// Reminders' preview draws it too): " 2 · Payer la facture".
    static func appearance(_ due: [ReminderItem], mode: RemindersMenuBar) -> (image: NSImage?, title: String) {
        var title = " \(due.count)"
        if mode == .countAndNext, let next = due.first {
            title += " · " + (next.title.count > 24 ? String(next.title.prefix(23)) + "…" : next.title)
        }
        return (Theme.symbol("checklist", pointSize: 12, weight: .medium), title)
    }

    private func hide() {
        due = []
        if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Due today or overdue — click to check off", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (index, reminder) in due.prefix(20).enumerated() {
            let when = Reminders.when(reminder, now: .now)
            let marks = reminder.marks.isEmpty ? "" : "\(reminder.marks) "
            let row = NSMenuItem(title: "\(marks)\(reminder.title)" + (when.isEmpty ? "" : "  ·  \(when)"), action: #selector(check(_:)), keyEquivalent: "")
            row.target = self
            row.tag = index
            row.image = Theme.symbol("circle", pointSize: 12, weight: .regular)
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Show in skil.li", action: #selector(showInSkilli), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let app = NSMenuItem(title: "Open Reminders", action: #selector(openApp), keyEquivalent: "")
        app.target = self
        menu.addItem(app)
        return menu
    }

    @objc private func check(_ sender: NSMenuItem) {
        guard due.indices.contains(sender.tag) else { return }
        try? reminders.complete(id: due[sender.tag].id, done: true)
        refresh()
    }

    @objc private func showInSkilli() {
        onOpenReminders?()
    }

    @objc private func openApp() {
        reminders.openReminders()
    }
}
