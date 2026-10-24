import AVFoundation
import AppKit
import Contacts
import CoreBluetooth
import EventKit
import Observation

/// What skil.li asks macOS for, where it shows, and how to grant it.
enum Permission: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    /// Input Monitoring: asked only when the key tap fails with
    /// Accessibility on (`AppDelegate.startEventTap`).
    case inputMonitoring
    /// Screen Recording: words read on screen where an app tells
    /// Accessibility little, for "do it here".
    case screenRecording
    case microphone
    case calendar
    case reminders
    case contacts
    /// Paste from Other Apps: the clipboard history reads without asking.
    case pasteboard
    /// Full Disk Access: Safari's history (macOS keeps it behind it).
    case fullDiskAccess
    /// The camera: the meeting card's Check Camera & Mic, asked there.
    case camera
    /// Bluetooth: connecting AirPods and other devices paired with this
    /// Mac, asked where they are first named.
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .pasteboard: "Clipboard"
        case .fullDiskAccess: "Full Disk Access"
        case .inputMonitoring: "Input Monitoring"
        case .camera: "Camera"
        case .bluetooth: "Bluetooth"
        }
    }

    /// What it turns on, for "Allow Microphone — for Ask by Voice and Dictate".
    var feature: String {
        switch self {
        case .accessibility: "skil.li to work"
        case .screenRecording: "acting in your apps"
        case .microphone: "Ask by Voice and Dictate"
        case .calendar: "your next meeting"
        case .reminders: "reminders"
        case .contacts: "contacts"
        case .pasteboard: "clipboard history"
        case .fullDiskAccess: "Safari's history"
        case .inputMonitoring: "shortcuts"
        case .camera: "checking your camera before a meeting"
        case .bluetooth: "connecting your devices"
        }
    }

    /// Every feature it turns on, in the user's words (Settings → Privacy).
    var turnsOn: String {
        switch self {
        case .accessibility: "The Hyper Key and every shortcut, reading and replacing the text you select, snippets as you type, moving windows, menus and doing it here."
        case .screenRecording: "Doing it here reads the words a window shows when its app tells Accessibility little, and shows Jev one picture of that window when they say too little. A recorded meeting's other side, the Mac's sound, kept on this Mac."
        case .microphone: "Ask by Voice (✦V), Dictate (✦D) and your side of a recorded meeting. What you say becomes text on this Mac."
        case .calendar: "Your next meeting and its alerts, the agenda, events said in one sentence."
        case .reminders: "“Remind me…”, your to-dos to check off, today's in the menu bar."
        case .contacts: "Finding people (@), mails to them, forms filled from your card, their names known to Dictate."
        case .pasteboard: "Clipboard history (✦C) reads what you copy without macOS asking each time."
        case .fullDiskAccess: "Safari's pages in Browser History."
        case .inputMonitoring: "Shortcuts, only if they do not work with Accessibility on."
        case .camera: "Check Camera & Mic in the meeting card: you, before you join. Nothing is recorded."
        case .bluetooth: "Connecting and disconnecting AirPods, keyboards and speakers paired with this Mac."
        }
    }

    /// Why, in one line, as the user would put it.
    var reason: String {
        switch self {
        case .accessibility: "So ✦ shortcuts work everywhere, and commands can read and replace the text you select."
        case .screenRecording: "So “do it here” sees what an app shows when it tells Accessibility little, and clicks it for you. Read on this Mac: only the words of the window you act in go to your decision model, or one picture of it to TypeSafe Jev when they say too little."
        case .microphone: "So you can talk to skil.li: ✦V to ask, ✦D to dictate into any app. Speech is turned into text on this Mac."
        case .calendar: "So your next meeting is one key away, and “qu'est-ce que j'ai demain ?” is answered. Read on this Mac only."
        case .reminders: "So “rappelle-moi…” lands in your Reminders, and “todo” lists them to check off."
        case .contacts: "So you find people by anything you know of them (“@lumière”) and write to them. Read on this Mac only."
        case .pasteboard: "So what you copy stays at hand with ✦C, words in images included. Kept on this Mac only."
        case .fullDiskAccess: "So “history …” finds Safari's pages too, like the other browsers'. macOS keeps them behind this switch. Read on this Mac only."
        case .inputMonitoring: "So shortcuts work when Accessibility alone is not enough on this Mac."
        case .camera: "So you see yourself before you join a call. Shown on this Mac only, never recorded."
        case .bluetooth: "So “connecte mes AirPods” connects them, from the launcher or Ask."
        }
    }

    /// What to do in System Settings once it opened.
    var waitingHint: String {
        switch self {
        case .pasteboard: "In the list that opened, set skil.li to Allow. This ticks by itself."
        case .fullDiskAccess: "In the list that opened, turn on skil.li (or add it with +). This ticks by itself."
        case .screenRecording: "In the list that opened, turn on skil.li, then Quit & Reopen when macOS asks: skil.li comes back by itself."
        default: "In the list that opened, turn on skil.li. This ticks by itself."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .microphone: "mic.fill"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .contacts: "person.crop.circle"
        case .pasteboard: "doc.on.clipboard"
        case .fullDiskAccess: "internaldrive"
        case .inputMonitoring: "keyboard"
        case .camera: "video.fill"
        case .bluetooth: "dot.radiowaves.left.and.right"
        }
    }

    var isRequired: Bool { self == .accessibility }

    /// In the first-launch setup window, with the user's SI: only
    /// Accessibility (D7, 2026-10-17). Every other permission is asked
    /// where its feature first needs it (`askedFrom`).
    var showsInSetup: Bool { self == .accessibility }

    /// Where a launcher row "Allow …" (or a feature) asks for it.
    enum AskedFrom: Equatable {
        /// The setup window, which says why before macOS's prompt.
        case setup
        /// Settings → Privacy: it cannot be asked for, the pane says how
        /// to turn it on (Full Disk Access).
        case privacyPane
        /// Right there: macOS's own question when never asked, else its
        /// list in System Settings (`PermissionCenter.grant`).
        case inPlace
    }

    var askedFrom: AskedFrom {
        switch self {
        case .accessibility: .setup
        case .fullDiskAccess: .privacyPane
        case .inputMonitoring, .screenRecording, .microphone, .calendar, .reminders, .contacts, .pasteboard, .camera, .bluetooth: .inPlace
        }
    }

    /// Privacy & Security, at this permission's list.
    var settingsURL: URL {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .microphone: "Privacy_Microphone"
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .contacts: "Privacy_Contacts"
        case .pasteboard: "Privacy_Pasteboard"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .camera: "Privacy_Camera"
        case .bluetooth: "Privacy_Bluetooth"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

/// Where each permission stands, read live while someone looks: the setup
/// window and Settings refresh it every half second, so a switch turned on
/// in System Settings shows at once. Launch, the launcher and the status
/// menu read only what they show (`refreshAttention`): each permission is
/// asked through its own framework (AVFoundation, EventKit, Contacts…),
/// which stays in memory once asked.
@MainActor
@Observable
final class PermissionCenter {
    enum State: Equatable {
        case granted
        /// Never asked: the button asks macOS, which shows its own prompt.
        case notAsked
        /// Refused or turned off: only System Settings can change it.
        case denied
        /// Asked, waiting for the switch in System Settings (Accessibility).
        case waiting
    }

    private(set) var states: [Permission: State] = [:]
    @ObservationIgnored private var timer: Timer?
    /// How many views watch each permission: only those are read again.
    @ObservationIgnored private var watchers: [Permission: Int] = [:]
    @ObservationIgnored private var askedAccessibility = false
    @ObservationIgnored private var askedFullDiskAccess = false
    @ObservationIgnored private var askedScreenRecording = false
    @ObservationIgnored private var askedInputMonitoring = false
    /// Optional permissions a feature just needed and did not have (✦V
    /// with the microphone off): the launcher shows them until granted.
    @ObservationIgnored private var neededNow: Set<Permission> = []
    /// A permission changed state (granted, refused): the setup window
    /// comes back in front.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Allow was pressed: System Settings or macOS's prompt takes the front.
    @ObservationIgnored var onGrant: ((Permission) -> Void)?
    /// Calendar just allowed: the next meeting can show.
    @ObservationIgnored var onCalendarGranted: (() -> Void)?

    init() {
        refreshAttention()
    }

    func state(_ permission: Permission) -> State {
        states[permission] ?? .notAsked
    }

    /// Required permissions all granted.
    var isReady: Bool {
        Permission.allCases.filter(\.isRequired).allSatisfy { state($0) == .granted }
    }

    /// What the launcher lists under its search field: what is required and
    /// missing, and what a feature the user just tried needed. A permission
    /// refused on purpose and not needed since stays quiet.
    var needsAttention: [Permission] {
        Permission.allCases.filter { permission in
            state(permission) != .granted && (permission.isRequired || neededNow.contains(permission))
        }
    }

    /// A feature failed for lack of `permission`.
    func needed(_ permission: Permission) {
        neededNow.insert(permission)
    }

    /// Self-test hook: draw the setup in given states, without asking macOS.
    var frozenStates: [Permission: State]? {
        didSet {
            if let frozenStates {
                let changed = frozenStates != states
                states = frozenStates
                if changed { onChange?() }
            } else {
                refresh()
            }
        }
    }

    /// Every permission read again.
    func refresh() {
        refresh(Permission.allCases)
    }

    /// What `isReady` and `needsAttention` stand on: the required
    /// permissions and those a feature just needed. The others are read
    /// when something shows them.
    func refreshAttention() {
        refresh(Permission.allCases.filter { $0.isRequired || neededNow.contains($0) })
    }

    /// `permissions` read again, the others kept as last read.
    func refresh(_ permissions: [Permission]) {
        guard frozenStates == nil else { return }
        var next = states
        for permission in permissions { next[permission] = Self.read(permission, asked: asked(permission)) }
        // Waiting → notAsked is not a change the user made.
        let changed = permissions.contains { permission in
            let before = states[permission]
            let state = next[permission]
            return before != nil && before != state && !(before == .waiting && state == .notAsked)
        }
        let calendarGranted = states[.calendar] != nil && states[.calendar] != .granted && next[.calendar] == .granted
        if next != states { states = next }
        if changed { onChange?() }
        if calendarGranted { onCalendarGranted?() }
    }

    /// Asked already, for those macOS lists only once switched on.
    private func asked(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: askedAccessibility
        case .screenRecording: askedScreenRecording
        case .fullDiskAccess: askedFullDiskAccess
        case .inputMonitoring: askedInputMonitoring
        default: false
        }
    }

    private static func read(_ permission: Permission, asked: Bool) -> State {
        switch permission {
        case .accessibility:
            AXIsProcessTrusted() ? .granted : (asked ? .waiting : .notAsked)
        case .screenRecording:
            // Granted takes effect once skil.li reopens (macOS offers Quit & Reopen).
            CGPreflightScreenCaptureAccess() ? .granted : (asked ? .waiting : .notAsked)
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .reminders:
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .fullAccess: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .bluetooth:
            switch BluetoothDevices.authorization {
            case .allowedAlways: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .fullDiskAccess:
            readsSafari ? .granted : (asked ? .waiting : .notAsked)
        case .inputMonitoring:
            CGPreflightListenEventAccess() ? .granted : (asked ? .waiting : .notAsked)
        case .pasteboard:
            // skil.li appears in Paste from Other Apps after macOS asked once;
            // then the user picks Ask, Allow or Deny there.
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow: .granted
            case .default: .notAsked
            case .ask: .waiting
            default: .denied
            }
        }
    }

    /// Full Disk Access cannot be asked for, nor read: skil.li may read what
    /// it guards when it opens Safari's history folder.
    nonisolated static var readsSafari: Bool {
        !BrowserHistory.safariNeedsAccess(BrowserHistory.Source(installed: { _ in true }))
    }

    /// Asks macOS (its own prompt), or opens System Settings when only the
    /// user can change it there.
    func grant(_ permission: Permission) {
        onGrant?(permission)
        switch (permission, state(permission)) {
        case (.accessibility, _):
            askedAccessibility = true
            // macOS's prompt offers to open the list; open it too, so the
            // switch is one click away whatever the prompt does.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            NSWorkspace.shared.open(permission.settingsURL)
        case (.microphone, .notAsked):
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refresh()
            }
        case (.camera, .notAsked):
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                refresh()
            }
        case (.bluetooth, .notAsked):
            // macOS's question comes up; the half-second refresh reads the answer.
            BluetoothDevices.requestAccess()
        // The async forms: their answers come back here, not on the
        // arbitrary queue a completion block runs on (a block written here
        // would be main-actor isolated and stop the app there).
        case (.calendar, .notAsked):
            Task {
                _ = try? await EKEventStore().requestFullAccessToEvents()
                refresh()
            }
        case (.reminders, .notAsked):
            Task {
                _ = try? await EKEventStore().requestFullAccessToReminders()
                refresh()
            }
        case (.contacts, .notAsked):
            Task {
                _ = try? await CNContactStore().requestAccess(for: .contacts)
                refresh()
            }
        case (.screenRecording, _):
            // macOS's prompt the first time, which lists skil.li; the list
            // opens too, where the switch is.
            askedScreenRecording = true
            _ = CGRequestScreenCaptureAccess()
            NSWorkspace.shared.open(permission.settingsURL)
        case (.fullDiskAccess, _):
            // Only the user turns it on (or adds skil.li with +).
            askedFullDiskAccess = true
            NSWorkspace.shared.open(permission.settingsURL)
        case (.inputMonitoring, _):
            // macOS lists skil.li once asked; the list opens where the switch is.
            askedInputMonitoring = true
            _ = CGRequestListenEventAccess()
            NSWorkspace.shared.open(permission.settingsURL)
        case (.pasteboard, .notAsked):
            // macOS lists skil.li only after asking once: one read makes it
            // ask (off the main thread, the question may wait for an answer),
            // then the list opens to choose Allow.
            Task.detached { _ = NSPasteboard.general.string(forType: .string) }
            NSWorkspace.shared.open(permission.settingsURL)
        default:
            NSWorkspace.shared.open(permission.settingsURL)
        }
        refresh()
    }

    /// Refreshes `permissions` every half second while at least one view
    /// watches them (the setup window only Accessibility: each permission
    /// is read through its own framework, which stays in memory).
    func startWatching(_ permissions: [Permission] = Permission.allCases) {
        for permission in permissions { watchers[permission, default: 0] += 1 }
        // Read at once: what launch read is only what it needed.
        refresh(permissions)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh(Permission.allCases.filter { self.watchers[$0] != nil })
            }
        }
    }

    func stopWatching(_ permissions: [Permission] = Permission.allCases) {
        for permission in permissions {
            let left = (watchers[permission] ?? 0) - 1
            watchers[permission] = left > 0 ? left : nil
        }
        guard watchers.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }
}
