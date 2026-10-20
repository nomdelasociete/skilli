import AppKit
import SkilliCore

/// Asks on a schedule (Settings → Ask → On a Schedule): "every Monday at
/// 9:00 sum up my pull requests". Kept in `scheduled-asks.json`; one timer
/// for the next one due, never a poll. Each runs once at its time, as Ask
/// would (`AIActionController.runScheduled`); a time missed while the Mac
/// slept or skil.li was off runs once, a minute after it wakes or starts,
/// however many were missed. Its run starts by noting it ran: one run per
/// time, never two.
@MainActor
@Observable
final class AskScheduler {
    /// Every scheduled ask, in the order made.
    private(set) var asks: [ScheduledAsk] = []
    /// Those running now.
    private(set) var running: Set<UUID> = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Runs one as Ask would: its answer, or why it failed.
    @ObservationIgnored var run: ((ScheduledAsk) async -> (answer: String, failed: Bool))?
    /// Self-test hook: the clock, moved ahead to fire one early.
    @ObservationIgnored var clock: () -> Date = { .now }

    /// When the timer fires next (self-tests).
    var nextFire: Date? { timer?.fireDate }

    static let defaultFileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("skil.li/scheduled-asks.json")

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(caughtUp: true) }
        })
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    /// At launch: the times missed while skil.li was off run a minute later.
    func start() {
        refresh(caughtUp: true)
    }

    // MARK: - The list

    /// Kept, and counted from now.
    @discardableResult
    func add(_ ask: String, schedule: AskSchedule) -> ScheduledAsk {
        let made = ScheduledAsk(ask: ask.trimmingCharacters(in: .whitespacesAndNewlines), schedule: schedule, created: clock())
        asks.append(made)
        save()
        refresh()
        Log.actions.notice("Scheduled an ask: \(schedule.spoken, privacy: .public)")
        return made
    }

    /// Gone at once; what ⌘Z puts back where it was (`restore`).
    @discardableResult
    func remove(_ id: UUID) -> RemovedElement<ScheduledAsk>? {
        let removed = RemovedElement.take(id, from: &asks)
        save()
        refresh()
        return removed
    }

    /// Back with its times; one due meanwhile runs, as after a wake.
    func restore(_ removed: RemovedElement<ScheduledAsk>) {
        guard removed.putBack(into: &asks) else { return }
        save()
        refresh()
    }

    /// Off: it waits; on again: the times while off are not caught up.
    func setOn(_ id: UUID, _ on: Bool) {
        guard let index = asks.firstIndex(where: { $0.id == id }) else { return }
        asks[index].turn(on: on, now: clock())
        save()
        refresh()
    }

    func ask(_ id: UUID) -> ScheduledAsk? { asks.first { $0.id == id } }

    /// Its next time, while it is on.
    func next(_ ask: ScheduledAsk) -> Date? {
        ask.due().map { max($0, clock()) }
    }

    // MARK: - Running

    /// Sets the one timer: the next time due, or, for one already due
    /// (missed), now; a minute from now after a start or a wake.
    func refresh(caughtUp: Bool = false) {
        timer?.invalidate()
        timer = nil
        let now = clock()
        var fire = ScheduledAsks.next(asks, now: now)
        if !ScheduledAsks.due(asks.filter { !running.contains($0.id) }, now: now).isEmpty {
            let missed = now.addingTimeInterval(caughtUp ? ScheduledAsks.catchUpDelay : 0)
            fire = min(fire ?? missed, missed)
        }
        guard let fire else { return }
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireDue() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Every one due now, each once.
    func fireDue() {
        let now = clock()
        for ask in ScheduledAsks.due(asks, now: now) where !running.contains(ask.id) {
            begin(ask, at: now)
        }
        refresh()
    }

    /// Runs one now, whatever its time (a row's Run Now; self-tests).
    func runNow(_ id: UUID) {
        guard let ask = ask(id), !running.contains(id) else { return }
        begin(ask, at: clock())
        refresh()
    }

    private func begin(_ ask: ScheduledAsk, at now: Date) {
        update(ask.id) { $0.lastRun = now }
        running.insert(ask.id)
        Log.actions.notice("Scheduled ask runs: \(ask.schedule.spoken, privacy: .public)")
        Task {
            let outcome: (answer: String, failed: Bool) = await run?(ask) ?? (answer: "skil.li could not run it.", failed: true)
            running.remove(ask.id)
            update(ask.id) {
                $0.lastAnswer = outcome.answer
                $0.lastFailed = outcome.failed
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout ScheduledAsk) -> Void) {
        guard let index = asks.firstIndex(where: { $0.id == id }) else { return }
        change(&asks[index])
        save()
    }

    // MARK: - The file

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            asks = try decoder.decode([ScheduledAsk].self, from: data)
        } catch {
            Log.actions.error("Scheduled asks unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(asks).write(to: fileURL, options: .atomic)
        } catch {
            Log.actions.error("Scheduled asks not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
