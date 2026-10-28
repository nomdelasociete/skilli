import AppKit
import EventKit
import SkilliCore

/// The user's calendars, read through EventKit once allowed (every account
/// the Calendar app has: iCloud, Google, Exchange…). Read on this Mac only.
/// An account of the Calendar app and its calendars (Settings → Calendar).
struct CalendarAccount: Identifiable {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let color: NSColor
    }

    let id: String
    /// "iCloud", "camille@nimbus.example", "On My Mac".
    let name: String
    let calendars: [Entry]
    /// Subscribed calendars and birthdays: listed after the accounts.
    var isLast = false
}

@MainActor
final class CalendarBook {
    /// The self-test's events instead of the user's (never read then).
    var testEvents: [AgendaEvent]? {
        didSet {
            soon = nil
            if testEvents == nil { createdForTest = [] }
        }
    }
    /// False in the self-test: the Mac's own calendars are never read,
    /// whatever was allowed there.
    var readsTheMac = true
    /// How links open; the self-test records them instead.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Self-test hook: events shown in Calendar, recorded instead.
    var shownInCalendar: ((AgendaEvent) -> Void)?
    /// Calendars left out (Settings → Calendar), by identifier (the
    /// self-test's events: by calendar name).
    var hiddenCalendars: Set<String> = [] {
        didSet { soon = nil }
    }
    /// The empty launcher shows the meeting from this many minutes before
    /// it starts to as many after.
    var launcherMinutes = 10
    /// The app ⌘↩ opens events in, and the browser for Google Meet ("" the
    /// default one).
    var calendarApp = "com.apple.iCal"
    var meetBrowser = ""
    /// The calendars changed (an event added, moved, synced).
    var onChange: (() -> Void)?
    /// A call was joined from skil.li (the card, the menu bar, the launcher,
    /// Ask, as it starts).
    var onJoin: (() -> Void)?
    /// The occurrences joined from skil.li (`MeetingBar.key`) and when each
    /// ends: the menu bar's meeting counts down once joined, rather than
    /// saying it started. Kept a day.
    private var joinedUntil: [String: Date] = [:]
    var joined: Set<String> { Set(joinedUntil.keys) }
    /// Made when first used: a store starts EventKit (most of a megabyte),
    /// for nothing while the calendars are not used.
    private lazy var store: EKEventStore = {
        let store = EKEventStore()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.soon = nil
                self?.writable = nil
                self?.onChange?()
            }
        }
        return store
    }()
    /// Today's and tomorrow's events, for the next meeting: kept until the
    /// calendars change or the day does.
    private var soon: (day: Date, events: [AgendaEvent])?
    /// The calendars events can be added to, by name: kept until the
    /// calendars change.
    private var writable: [String]?
    private var observer: NSObjectProtocol?

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var isAllowed: Bool {
        testEvents != nil || readsTheMac && EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Never asked: the first use shows macOS's prompt.
    var canAsk: Bool {
        testEvents == nil && readsTheMac && EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    /// Allowed, asking macOS the first time (its own prompt).
    func allow() async -> Bool {
        if isAllowed { return true }
        guard canAsk else { return false }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        soon = nil
        if granted { onChange?() }
        return granted
    }

    /// Events overlapping these dates, earliest first.
    func events(from start: Date, to end: Date) -> [AgendaEvent] {
        let events: [AgendaEvent]
        if let testEvents {
            events = testEvents.filter { $0.end > start && $0.start < end && !hiddenCalendars.contains($0.calendar) }
        } else {
            guard isAllowed else { return [] }
            let shown = store.calendars(for: .event).filter { !hiddenCalendars.contains($0.calendarIdentifier) }
            guard !shown.isEmpty else { return [] }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: shown)
            events = store.events(matching: predicate).map(Self.event)
        }
        return events.sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }
    }

    /// Today's and tomorrow's, from memory once read.
    func soonEvents(now: Date = .now) -> [AgendaEvent] {
        let today = Calendar.current.startOfDay(for: now)
        if let soon, soon.day == today { return soon.events }
        let end = Calendar.current.date(byAdding: .day, value: 2, to: today) ?? now.addingTimeInterval(2 * 86_400)
        let events = self.events(from: today, to: end)
        // Not allowed yet: read again once it is.
        if isAllowed { soon = (today, events) }
        return events
    }

    func nextMeeting(now: Date = .now) -> AgendaEvent? {
        Agenda.next(soonEvents(now: now), now: now)
    }

    /// The meeting a Record key is for now: the one on now (the latest
    /// started), else the next starting within 10 minutes
    /// (`MeetingMoment.isRecordable`).
    func recordableMeeting(now: Date = .now) -> AgendaEvent? {
        let recordable = soonEvents(now: now).filter { MeetingMoment.isRecordable($0, now: now) }
        return recordable.filter { $0.start <= now }.max { $0.start < $1.start } ?? recordable.min { $0.start < $1.start }
    }

    /// The app `event`'s call opens in when joined from skil.li (`join`):
    /// its service's app, else the browser set for Meet, else the default
    /// browser. Nil without a call.
    func appJoining(_ event: AgendaEvent) -> (bundleID: String, name: String)? {
        guard let meeting = event.meeting else { return nil }
        let workspace = NSWorkspace.shared
        let url = meeting.appURL.flatMap { workspace.urlForApplication(toOpen: $0) }
            ?? (meeting.service == "Google Meet" && !meetBrowser.isEmpty ? workspace.urlForApplication(withBundleIdentifier: meetBrowser) : nil)
            ?? workspace.urlForApplication(toOpen: meeting.url)
        guard let url, let bundle = Bundle(url: url) else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (bundle.bundleIdentifier ?? "", name)
    }

    /// The next meeting when it is about to start or just started: what the
    /// launcher shows before anything is typed.
    func meetingNow(now: Date = .now) -> AgendaEvent? {
        guard let next = nextMeeting(now: now), Agenda.isNear(next, now: now, minutes: launcherMinutes) else { return nil }
        return next
    }

    /// Every calendar with events, read-only ones too (Settings → Calendar).
    /// Every calendar by account (iCloud, each Google account, Exchange, this
    /// Mac…), for Settings → Calendar: the accounts by name, subscribed
    /// calendars and birthdays last.
    func calendarAccounts() -> [CalendarAccount] {
        if let testEvents {
            let names = Array(Set(testEvents.map(\.calendar).filter { !$0.isEmpty })).sorted()
            return names.isEmpty ? [] : [CalendarAccount(id: "test", name: "On This Mac", calendars: names.map { .init(id: $0, title: $0, color: .systemBlue) })]
        }
        guard isAllowed else { return [] }
        let bySource = Dictionary(grouping: store.calendars(for: .event)) { $0.source.sourceIdentifier }
        func last(_ source: EKSource) -> Bool { [.subscribed, .birthdays].contains(source.sourceType) }
        return bySource.values.compactMap { calendars -> CalendarAccount? in
            guard let source = calendars.first?.source else { return nil }
            let entries = calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .map { CalendarAccount.Entry(id: $0.calendarIdentifier, title: $0.title, color: NSColor(cgColor: $0.cgColor) ?? .systemGray) }
            return CalendarAccount(id: source.sourceIdentifier, name: source.title, calendars: entries, isLast: last(source))
        }
        .sorted { $0.isLast != $1.isLast ? !$0.isLast : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// What `hiddenCalendars` holds, from what was saved: identifiers kept;
    /// a name from before becomes every calendar with that name; anything
    /// else stays (an account away for now).
    func calendarIdentifiers(for saved: [String]) -> Set<String> {
        guard testEvents == nil, isAllowed else { return Set(saved) }
        let calendars = store.calendars(for: .event)
        let known = Set(calendars.map(\.calendarIdentifier))
        return Set(saved.flatMap { entry -> [String] in
            if known.contains(entry) { return [entry] }
            let named = calendars.filter { $0.title == entry }.map(\.calendarIdentifier)
            return named.isEmpty ? [entry] : named
        })
    }

    /// The names of the calendars events can be added to, the default first.
    func calendarNames() -> [String] {
        if let testEvents {
            return Array(Set(testEvents.map(\.calendar).filter { !$0.isEmpty })).sorted()
        }
        // Kept until the calendars change: a key does not ask macOS again.
        if let writable { return writable }
        guard isAllowed else { return [] }
        let all = store.calendars(for: .event).filter(\.allowsContentModifications).map(\.title)
        let first = store.defaultCalendarForNewEvents?.title
        let names = (first.map { [$0] } ?? []) + all.filter { $0 != first }.sorted()
        writable = names
        return names
    }

    /// Adds it to the named calendar (else the default one); what it became.
    func create(_ request: EventRequest) throws -> AgendaEvent {
        let title = request.title
        if testEvents != nil {
            let event = AgendaEvent(id: "created-\(UUID().uuidString)", title: title, start: request.start, end: request.end, isAllDay: request.isAllDay,
                                    calendar: request.calendar ?? "Work", notes: request.notes, url: request.url)
            testEvents?.append(event)
            createdForTest.append(request)
            return event
        }
        guard isAllowed else { throw Failure(message: "skil.li may not use your calendars yet.") }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = request.start
        event.endDate = request.end
        event.isAllDay = request.isAllDay
        let calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
        event.calendar = request.calendar.flatMap { name in calendars.first { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame } }
            ?? store.defaultCalendarForNewEvents
        guard event.calendar != nil else { throw Failure(message: "Calendar has no calendar to add events to.") }
        if !request.notes.isEmpty { event.notes = request.notes }
        if let url = request.url { event.url = URL(string: url) }
        if let minutes = request.alertMinutes { event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60))) }
        if let recurrence = request.recurrence { event.addRecurrenceRule(Self.rule(recurrence)) }
        try store.save(event, span: .thisEvent, commit: true)
        soon = nil
        Log.trace("Event added to \(event.calendar?.title ?? "?")")
        return Self.event(event)
    }

    /// Self-test hook: what was added while its events were in memory.
    private(set) var createdForTest: [EventRequest] = []

    /// Removes this occurrence (a repeating event keeps the others).
    func delete(_ event: AgendaEvent) throws {
        try delete(id: event.id)
    }

    /// Removes it by its id; its title, to say what went.
    @discardableResult
    func delete(id: String) throws -> String {
        if testEvents != nil {
            guard let found = testEvents?.first(where: { $0.id == id }) else { throw Failure(message: "No event with that id.") }
            testEvents?.removeAll { $0.id == id }
            return found.title
        }
        guard let found = store.calendarItem(withIdentifier: id) as? EKEvent else { throw Failure(message: "That event is not there anymore.") }
        let title = found.title ?? ""
        try store.remove(found, span: .thisEvent, commit: true)
        soon = nil
        return title
    }

    /// An event deleted (that occurrence), every field this Mac can write
    /// back (its calendar, times and time zone, place, notes, link,
    /// alerts, availability), for ⌘Z: `restore` makes it again. Never for
    /// an event with invitees (EventKit cannot invite them again). Held in
    /// memory only.
    struct Deleted {
        let event: AgendaEvent
        fileprivate let index: Int?
        fileprivate let calendarID: String?
        fileprivate let alarms: [EKAlarm]
        fileprivate let timeZone: TimeZone?
        fileprivate let availability: EKEventAvailability
        fileprivate let location: EKStructuredLocation?
    }

    /// Deletes this occurrence as `delete` does; what `restore` puts back.
    func remove(_ event: AgendaEvent) throws -> Deleted {
        if testEvents != nil {
            guard let index = testEvents?.firstIndex(where: { $0.id == event.id }), let found = testEvents?[index] else {
                throw Failure(message: "No event with that id.")
            }
            testEvents?.remove(at: index)
            return Deleted(event: found, index: index, calendarID: nil, alarms: [], timeZone: nil, availability: .notSupported, location: nil)
        }
        guard let found = store.calendarItem(withIdentifier: event.id) as? EKEvent else { throw Failure(message: "That event is not there anymore.") }
        let deleted = Deleted(event: event, index: nil, calendarID: found.calendar?.calendarIdentifier,
                              alarms: (found.alarms ?? []).compactMap { $0.copy() as? EKAlarm }, timeZone: found.timeZone,
                              availability: found.availability, location: found.structuredLocation?.copy() as? EKStructuredLocation)
        try store.remove(found, span: .thisEvent, commit: true)
        soon = nil
        return deleted
    }

    /// ⌘Z: made again at the same time with every field it had, in its
    /// calendar (the default one if that went meanwhile); one occurrence of
    /// a repeating event comes back as an event of its own. What it is now.
    @discardableResult
    func restore(_ deleted: Deleted) throws -> AgendaEvent {
        let shown = deleted.event
        if testEvents != nil {
            if var list = testEvents, !list.contains(where: { $0.id == shown.id }) {
                list.insert(shown, at: min(deleted.index ?? .max, list.count))
                testEvents = list
            }
            return shown
        }
        guard isAllowed else { throw Failure(message: "skil.li may not use your calendars any more.") }
        let event = EKEvent(eventStore: store)
        event.title = shown.title
        event.calendar = deleted.calendarID.flatMap { store.calendar(withIdentifier: $0) }.flatMap { $0.allowsContentModifications ? $0 : nil }
            ?? store.defaultCalendarForNewEvents
        guard event.calendar != nil else { throw Failure(message: "Calendar has no calendar to put it back in.") }
        event.timeZone = deleted.timeZone
        event.isAllDay = shown.isAllDay
        event.startDate = shown.start
        event.endDate = shown.end
        if let location = deleted.location { event.structuredLocation = location } else if !shown.location.isEmpty { event.location = shown.location }
        if !shown.notes.isEmpty { event.notes = shown.notes }
        event.url = shown.url.flatMap(URL.init(string:))
        if deleted.availability != .notSupported { event.availability = deleted.availability }
        deleted.alarms.forEach { event.addAlarm($0) }
        try store.save(event, span: .thisEvent, commit: true)
        soon = nil
        return Self.event(event)
    }

    /// Changes what is given; the rest stays.
    func update(id: String, title: String?, start: Date?, end: Date?, location: String?, notes: String?) throws -> AgendaEvent {
        if testEvents != nil {
            guard let index = testEvents?.firstIndex(where: { $0.id == id }), var event = testEvents?[index] else {
                throw Failure(message: "No event with that id.")
            }
            if let title { event.title = title }
            if let start { event.start = start }
            if let end { event.end = end }
            if let location { event.location = location }
            if let notes { event.notes = notes }
            testEvents?[index] = event
            return event
        }
        guard let found = store.calendarItem(withIdentifier: id) as? EKEvent else { throw Failure(message: "No event with that id.") }
        if let title { found.title = title }
        if let start {
            let length = found.endDate.timeIntervalSince(found.startDate)
            found.startDate = start
            if end == nil { found.endDate = start.addingTimeInterval(length) }
        }
        if let end { found.endDate = end }
        if let location { found.location = location }
        if let notes { found.notes = notes }
        try store.save(found, span: .thisEvent, commit: true)
        soon = nil
        return Self.event(found)
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

    /// Into the call: Zoom's and Teams' own app when installed, else the
    /// link; an event without a call opens in Calendar.
    func join(_ event: AgendaEvent) {
        guard let meeting = event.meeting else {
            openInCalendar(event)
            return
        }
        if let app = meeting.appURL, NSWorkspace.shared.urlForApplication(toOpen: app) != nil {
            openURL(app)
        } else if meeting.service == "Google Meet", !meetBrowser.isEmpty, testEvents == nil,
                  let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: meetBrowser) {
            NSWorkspace.shared.open([meeting.url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
        } else {
            openURL(meeting.url)
        }
        Log.trace("Joined \(meeting.service) for an event")
        joinedUntil = joinedUntil.filter { $0.value > Date.now.addingTimeInterval(-86_400) }
        joinedUntil[MeetingBar.key(event)] = event.end
        onJoin?()
    }

    /// Self-test hook: nothing joined.
    func forgetJoins() {
        joinedUntil = [:]
    }

    /// A new mail to everyone invited (nothing sent).
    func mailAttendees(_ event: AgendaEvent) -> Bool {
        let addresses = event.attendees.compactMap(\.email)
        guard !addresses.isEmpty, let url = ContactBook.mailURL(to: addresses, subject: event.title) else { return false }
        openURL(url)
        return true
    }

    /// Calendar on the event's day: Calendar has no link to one event, so
    /// it is told through its scripting dictionary (macOS asks once).
    func openInCalendar(_ event: AgendaEvent) {
        if let shownInCalendar {
            shownInCalendar(event)
            return
        }
        // Another calendar app chosen in Settings: opened, as it has no
        // link to an event either.
        if calendarApp != "com.apple.iCal", let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: calendarApp) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: event.start)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        let source = """
            set theDay to current date
            set day of theDay to 1
            set year of theDay to \(year)
            set month of theDay to \(month)
            set day of theDay to \(day)
            set time of theDay to 0
            tell application "Calendar"
                activate
                switch view to day view
                view calendar at theDay
            end tell
            """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.actions.error("Calendar not shown at the event's day: \(error[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public)")
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private static func event(_ event: EKEvent) -> AgendaEvent {
        let attendees = (event.attendees ?? []).filter { !$0.isCurrentUser }.map { participant in
            AgendaEvent.Attendee(name: participant.name ?? "",
                                 email: participant.url.absoluteString.lowercased().hasPrefix("mailto:")
                                     ? String(participant.url.absoluteString.dropFirst(7)) : nil)
        }
        let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        return AgendaEvent(id: event.calendarItemIdentifier, externalID: event.calendarItemExternalIdentifier, title: event.title ?? "", start: event.startDate, end: event.endDate,
                           isAllDay: event.isAllDay, calendar: event.calendar?.title ?? "", location: event.location ?? "",
                           notes: event.notes ?? "", url: event.url?.absoluteString, attendees: attendees, declined: declined)
    }
}
