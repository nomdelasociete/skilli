import AppKit
import SkilliCore

/// Timers: "timer 10 min pâtes" in the launcher, "mets un minuteur de 10
/// minutes" to Ask, or an agent. The nearest counts down in the menu bar;
/// at the end a sound and a card. They survive a relaunch.
@MainActor
final class TimerCenter: NSObject {
    struct Running: Codable, Identifiable, Equatable {
        let id: UUID
        let label: String
        let seconds: Int
        let end: Date

        /// "Pâtes · 10 min", "Timer · 10 min".
        var title: String { (label.isEmpty ? "Timer" : label) + " · " + TimerRequest.spoken(seconds) }
    }

    private(set) var timers: [Running] = []
    private var statusItem: NSStatusItem?
    private var ticker: Timer?
    private let defaults: UserDefaults
    private static let key = "TimerCenter.timers"
    /// A timer ended: the card says it.
    var onDone: ((Running) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    /// Timers saved before a relaunch; one that ended meanwhile says so.
    func restore() {
        guard let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([Running].self, from: data) else { return }
        timers = saved
        refresh()
    }

    @discardableResult
    func start(_ request: TimerRequest) -> Running {
        let timer = Running(id: UUID(), label: request.label, seconds: request.seconds, end: .now.addingTimeInterval(TimeInterval(request.seconds)))
        timers.append(timer)
        timers.sort { $0.end < $1.end }
        save()
        refresh()
        Log.trace("Timer started: \(timer.title)")
        return timer
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        save()
        refresh()
    }

    func remaining(_ timer: Running) -> Int {
        max(0, Int(timer.end.timeIntervalSinceNow.rounded(.up)))
    }

    // MARK: - Menu bar and ticking

    private func refresh() {
        guard !timers.isEmpty else {
            ticker?.invalidate()
            ticker = nil
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = Theme.symbol("timer", pointSize: 13, weight: .medium)
            item.button?.imagePosition = .imageLeading
            item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        if ticker == nil {
            let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            ticker.tolerance = 0.1
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        }
        tick()
    }

    /// Self-test hook: what the menu bar says.
    var menuBarTitle: String? { statusItem?.button?.title }

    private func tick() {
        let ended = timers.filter { $0.end <= .now }
        if !ended.isEmpty {
            timers.removeAll { $0.end <= .now }
            save()
            for timer in ended {
                NSSound(named: "Glass")?.play()
                Log.trace("Timer ended: \(timer.title)")
                onDone?(timer)
            }
            if timers.isEmpty {
                refresh()
                return
            }
        }
        guard let next = timers.first else { return }
        statusItem?.button?.title = " " + TimerRequest.clock(remaining(next)) + (timers.count > 1 ? " +\(timers.count - 1)" : "")
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(timers), forKey: Self.key)
    }

    @objc private func cancelFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        cancel(id)
    }
}

extension TimerCenter: NSMenuDelegate {
    /// Each timer and what is left; choosing one cancels it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for timer in timers {
            let item = NSMenuItem(title: "Cancel \(timer.label.isEmpty ? "Timer" : "“\(timer.label)”") — \(TimerRequest.clock(remaining(timer))) left",
                                  action: #selector(cancelFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = timer.id
            menu.addItem(item)
        }
    }
}
