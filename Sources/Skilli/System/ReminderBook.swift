import AppKit
import CoreLocation
import EventKit
import SkilliCore

/// The user's reminders, through EventKit once allowed (every account the
/// Reminders app has). Read on this Mac only.
@MainActor
final class ReminderBook {
    /// The self-test's reminders instead of the user's (never read then).
    var testItems: [ReminderItem]? {
        didSet {
            cache = nil
            if testItems == nil { addedForTest = [] }
        }
    }
    /// False in the self-test: the Mac's own reminders are never read,
    /// whatever was allowed there.
    var readsTheMac = true
    /// Self-test hook: what was added while its reminders were in memory.
    private(set) var addedForTest: [ReminderRequest] = []
    /// How links open; the self-test records them instead.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Self-test hook: the Reminders app opened, recorded instead.
    var openedReminders: (() -> Void)?
    /// The reminders changed (added, done, synced).
    var onChange: (() -> Void)?
    /// Where a reminder without "#list" goes (Settings → Reminders); empty
    /// for the Reminders app's default.
    var defaultList = ""
    /// Places saved for "en arrivant au bureau".
    var places: [SavedPlace] = []
    /// A place said that no saved place names: Home or Work from the user's
    /// card, found on Apple Maps (set by the app); nil when there is none.
    var cardPlace: ((String) async -> SavedPlace?)?
    /// Self-test hook: where the last reminder added rings, and whether on
    /// arriving.
    private(set) var lastPlace: (place: SavedPlace, arriving: Bool)?
    /// Made when first used: a store starts EventKit (most of a megabyte),
    /// for nothing while Reminders are not used.
    private lazy var store: EKEventStore = {
        let store = EKEventStore()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cache = nil
                self?.lists = nil
                self?.onChange?()
            }
        }
        return store
    }()
    /// Open ones and those done in the last week, until the store changes.
    private var cache: [ReminderItem]?
    /// The lists' names, until the store changes: the launcher asks on
    /// every key.
    private var lists: [String]?
    private var observer: NSObjectProtocol?

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var isAllowed: Bool {
        testItems != nil || readsTheMac && EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// Never asked: the first use shows macOS's prompt.
    var canAsk: Bool {
        testItems == nil && readsTheMac && EKEventStore.authorizationStatus(for: .reminder) == .notDetermined
    }

    func allow() async -> Bool {
        if isAllowed { return true }
        guard canAsk else { return false }
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        cache = nil
        if granted { onChange?() }
        return granted
    }

    /// The lists reminders can go to, the default first.
    func listNames() -> [String] {
        if let testItems {
            return ["Reminders"] + Array(Set(testItems.map(\.list)).subtracting(["Reminders"])).sorted()
        }
        // Kept until the lists change: a key does not ask macOS again.
        if let lists { return lists }
        guard isAllowed else { return [] }
        let all = store.calendars(for: .reminder).filter(\.allowsContentModifications).map(\.title)
        let first = store.defaultCalendarForNewReminders()?.title
        let names = (first.map { [$0] } ?? []) + all.filter { $0 != first }.sorted()
        lists = names
        return names
    }

    /// The open ones and those done in the last week; from memory once read.
    func items() async -> [ReminderItem] {
        if let testItems { return testItems }
        guard isAllowed else { return [] }
        if let cache { return cache }
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let open = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil))
        let done = await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: weekAgo, ending: nil, calendars: nil))
        let read = open + done
        cache = read
        return read
    }

    private func fetch(_ predicate: NSPredicate) async -> [ReminderItem] {
        let store = self.store
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate, completion: Self.collect(into: continuation))
        }
    }

    /// What EventKit calls with the reminders, on its own queue: made here,
    /// outside the main actor (a block written in `fetch` was main-actor
    /// isolated and would stop the app there).
    private nonisolated static func collect(into continuation: CheckedContinuation<[ReminderItem], Never>) -> ([EKReminder]?) -> Void {
        { reminders in continuation.resume(returning: (reminders ?? []).map(item)) }
    }

    /// Self-test hook: a real EventKit fetch that finds nothing (reminders
    /// done in a minute a day from now), so its callback runs on EventKit's
    /// queue without reading anything of the user's.
    func fetchNothing() async -> Int {
        let start = Date.now.addingTimeInterval(86_400)
        return await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: start.addingTimeInterval(60),
                                                                 calendars: nil)).count
    }

    /// Added to the named list (else the default one); what it became.
    func add(_ request: ReminderRequest) async throws -> ReminderItem {
        var request = request
        if request.list == nil, !defaultList.isEmpty { request.list = defaultList }
        // A saved place first; else, for home or work, the card's address.
        var place: (SavedPlace, Bool)?
        if let said = request.place {
            if let saved = SavedPlace.match(said.name, in: places) {
                place = (saved, said.arriving)
            } else if let card = await cardPlace?(said.name) {
                place = (card, said.arriving)
            } else {
                let card = SavedPlace.cardAddress(for: said.name).map { ", or a \($0 == .home ? "Home" : "Work") address on your card in Contacts" } ?? ""
                throw Failure(message: "No place named “\(said.name)”: add it in skil.li's Settings → Reminders\(card).")
            }
        }
        lastPlace = place.map { (place: $0.0, arriving: $0.1) }
        if testItems != nil {
            let item = ReminderItem(id: "added-\(UUID().uuidString)", title: request.title, due: request.due, hasTime: request.hasTime,
                                    list: request.list ?? "Reminders", priority: request.priority, notes: request.notes, url: request.url,
                                    repeats: request.recurrence != nil)
            testItems?.append(item)
            addedForTest.append(request)
            return item
        }
        guard isAllowed else { throw Failure(message: "skil.li may not use Reminders yet.") }
        let reminder = EKReminder(eventStore: store)
        reminder.title = request.title
        let lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        reminder.calendar = request.list.flatMap { name in lists.first { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame } }
            ?? store.defaultCalendarForNewReminders()
        guard reminder.calendar != nil else { throw Failure(message: "Reminders has no list to add to.") }
        Self.setDue(request.due, hasTime: request.hasTime, on: reminder)
        reminder.priority = request.priority
        if !request.notes.isEmpty { reminder.notes = request.notes }
        if let url = request.url { reminder.url = URL(string: url) }
        if let recurrence = request.recurrence, request.due != nil { reminder.addRecurrenceRule(Self.rule(recurrence)) }
        if let (saved, arriving) = place {
            // Rings there, as the Reminders app does: on arriving or leaving.
            let location = EKStructuredLocation(title: saved.name)
            location.geoLocation = CLLocation(latitude: saved.latitude, longitude: saved.longitude)
            location.radius = saved.radius
            let alarm = EKAlarm()
            alarm.structuredLocation = location
            alarm.proximity = arriving ? .enter : .leave
            reminder.addAlarm(alarm)
        }
        try store.save(reminder, commit: true)
        cache = nil
        Log.trace("Reminder added to \(reminder.calendar?.title ?? "?")")
        return Self.item(reminder)
    }

    /// Done, or not done again.
    func complete(id: String, done: Bool) throws {
        try change(id) { item in
            item.isCompleted = done
            item.completedAt = done ? .now : nil
        } real: { reminder in
            reminder.isCompleted = done
        }
    }

    /// Due then (nil: no date).
    func reschedule(id: String, due: Date?, hasTime: Bool) throws {
        try change(id) { item in
            item.due = due
            item.hasTime = due != nil && hasTime
        } real: { reminder in
            Self.setDue(due, hasTime: hasTime, on: reminder)
        }
    }

    func move(id: String, to list: String) throws {
        let target = isAllowed && testItems == nil
            ? store.calendars(for: .reminder).first { $0.allowsContentModifications && $0.title.localizedCaseInsensitiveCompare(list) == .orderedSame }
            : nil
        if testItems == nil, target == nil { throw Failure(message: "No list named “\(list)”.") }
        try change(id) { item in
            item.list = list
        } real: { reminder in
            if let target { reminder.calendar = target }
        }
    }

    /// 0 none, 1 high, 5 medium, 9 low.
    func setPriority(id: String, _ priority: Int) throws {
        try change(id) { item in
            item.priority = priority
        } real: { reminder in
            reminder.priority = priority
        }
    }

    func update(id: String, title: String?, notes: String?) throws {
        try change(id) { item in
            if let title { item.title = title }
            if let notes { item.notes = notes }
        } real: { reminder in
            if let title { reminder.title = title }
            if let notes { reminder.notes = notes }
        }
    }

    /// Removes it; its title, to say what went.
    @discardableResult
    func delete(id: String) throws -> String {
        if testItems != nil {
            guard let found = testItems?.first(where: { $0.id == id }) else { throw Failure(message: "No reminder with that id.") }
            testItems?.removeAll { $0.id == id }
            return found.title
        }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw Failure(message: "That reminder is not there anymore.") }
        let title = reminder.title ?? ""
        try store.remove(reminder, commit: true)
        cache = nil
        return title
    }

    /// A reminder deleted, every field it had (its list, due date, alarms
    /// and places, how it repeats, done or not), for ⌘Z: `restore` makes it
    /// again with them. Held in memory only.
    struct Deleted {
        let item: ReminderItem
        fileprivate let index: Int?
        fileprivate let calendarID: String?
        fileprivate let due: DateComponents?
        fileprivate let start: DateComponents?
        fileprivate let alarms: [EKAlarm]
        fileprivate let rules: [EKRecurrenceRule]
        fileprivate let timeZone: TimeZone?
    }

    /// Deletes it as `delete` does; what `restore` puts back.
    func remove(_ item: ReminderItem) throws -> Deleted {
        if testItems != nil {
            guard let index = testItems?.firstIndex(where: { $0.id == item.id }), let found = testItems?[index] else {
                throw Failure(message: "No reminder with that id.")
            }
            testItems?.remove(at: index)
            return Deleted(item: found, index: index, calendarID: nil, due: nil, start: nil, alarms: [], rules: [], timeZone: nil)
        }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            throw Failure(message: "That reminder is not there anymore.")
        }
        let deleted = Deleted(item: Self.item(reminder), index: nil, calendarID: reminder.calendar?.calendarIdentifier,
                              due: reminder.dueDateComponents, start: reminder.startDateComponents,
                              alarms: (reminder.alarms ?? []).compactMap { $0.copy() as? EKAlarm },
                              rules: (reminder.recurrenceRules ?? []).compactMap { $0.copy() as? EKRecurrenceRule },
                              timeZone: reminder.timeZone)
        try store.remove(reminder, commit: true)
        cache = nil
        return deleted
    }

    /// ⌘Z: made again with every field it had, in its list (the default
    /// one if that list went meanwhile). What it is now.
    @discardableResult
    func restore(_ deleted: Deleted) throws -> ReminderItem {
        let item = deleted.item
        if testItems != nil {
            if var list = testItems, !list.contains(where: { $0.id == item.id }) {
                list.insert(item, at: min(deleted.index ?? .max, list.count))
                testItems = list
            }
            return item
        }
        guard isAllowed else { throw Failure(message: "skil.li may not use Reminders any more.") }
        let reminder = EKReminder(eventStore: store)
        reminder.title = item.title
        reminder.calendar = deleted.calendarID.flatMap { store.calendar(withIdentifier: $0) }.flatMap { $0.allowsContentModifications ? $0 : nil }
            ?? store.defaultCalendarForNewReminders()
        guard reminder.calendar != nil else { throw Failure(message: "Reminders has no list to put it back in.") }
        reminder.timeZone = deleted.timeZone
        reminder.startDateComponents = deleted.start
        reminder.dueDateComponents = deleted.due
        reminder.priority = item.priority
        if !item.notes.isEmpty { reminder.notes = item.notes }
        reminder.url = item.url.flatMap(URL.init(string:))
        deleted.alarms.forEach { reminder.addAlarm($0) }
        deleted.rules.forEach { reminder.addRecurrenceRule($0) }
        if item.isCompleted {
            reminder.isCompleted = true
            reminder.completionDate = item.completedAt
        }
        try store.save(reminder, commit: true)
        cache = nil
        return Self.item(reminder)
    }

    /// The Reminders app (it has no link to one reminder).
    func openReminders() {
        if let openedReminders {
            openedReminders()
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func change(_ id: String, test: (inout ReminderItem) -> Void, real: (EKReminder) -> Void) throws {
        if testItems != nil {
            guard let index = testItems?.firstIndex(where: { $0.id == id }), var item = testItems?[index] else {
                throw Failure(message: "No reminder with that id.")
            }
            test(&item)
            testItems?[index] = item
            return
        }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw Failure(message: "That reminder is not there anymore.") }
        real(reminder)
        try store.save(reminder, commit: true)
        cache = nil
    }

    private static func setDue(_ due: Date?, hasTime: Bool, on reminder: EKReminder) {
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        guard let due else {
            reminder.dueDateComponents = nil
            return
        }
        let components: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        reminder.dueDateComponents = Calendar.current.dateComponents(components, from: due)
        // As the Reminders app does: a time rings.
        if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
    }

    private static func rule(_ recurrence: SpokenRecurrence) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch recurrence.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = recurrence.weekdays.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: max(1, recurrence.interval), daysOfTheWeek: days.isEmpty ? nil : days,
                                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    }

    private nonisolated static func item(_ reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        let due = components.flatMap { Calendar.current.date(from: $0) }
        return ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "", due: due, hasTime: components?.hour != nil,
                            list: reminder.calendar?.title ?? "", priority: reminder.priority, notes: reminder.notes ?? "",
                            url: reminder.url?.absoluteString, isCompleted: reminder.isCompleted, completedAt: reminder.completionDate,
                            repeats: reminder.hasRecurrenceRules)
    }
}
