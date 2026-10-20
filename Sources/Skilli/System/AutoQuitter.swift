import AppKit
import ApplicationServices
import CoreAudio
import SkilliCore

/// Auto Quit (Settings → Windows → Quit apps you stopped using): an app not
/// in front for the time set is quit, without a word (what is seen done is
/// not said); one that does not go is said. `AutoQuit` (SkilliCore) picks
/// who may go; here what only the live Mac tells keeps an app: a window
/// with unsaved work or a question open (Accessibility), sound or the
/// microphone in use (CoreAudio's processes), work going on (its CPU). Then,
/// with a deciding key, Jev reads each one's name and windows' titles: a
/// call, a download, a command running keep it. Nothing polls: one timer
/// for when the next app is due, set again when apps come forward, launch
/// or quit, and when the settings change.
@MainActor
final class AutoQuitter {
    private let preferences: Preferences
    /// When each app was last in front, by process.
    private var lastUsed: [pid_t: Date] = [:]
    private let started = Date.now
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var checking = false
    /// The deciding keys, Jev first; none: the rules alone decide.
    var decisionKeys: () -> [DecisionProvider: String] = { [:] }
    /// An app that did not quit, said in the card.
    var onFailure: ((String) -> Void)?
    /// Self-test: everything is decided, nothing is quit.
    var dryRun = false
    /// Self-test hooks: the last look's apps quit (or that would be) and
    /// kept, with why.
    private(set) var lastQuit: [String] = []
    private(set) var lastKept: [(name: String, why: String)] = []
    /// Self-test: when an app was last used, whatever it did since.
    private var pretended: [pid_t: Date] = [:]

    func pretendUnused(_ pid: pid_t, since date: Date?) {
        pretended[pid] = date
    }

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                                          NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                MainActor.assumeIsolated { self?.noticed(name, pid: pid) }
            })
        }
        schedule()
    }

    private func noticed(_ name: Notification.Name, pid: pid_t?) {
        guard let pid else { return }
        if name == NSWorkspace.didTerminateApplicationNotification {
            lastUsed[pid] = nil
        } else {
            // In front, just left the front, or just opened: in use now.
            lastUsed[pid] = .now
        }
        schedule()
    }

    /// The open apps as `AutoQuit` reads them.
    private func apps() -> [AutoQuit.App] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated, let id = app.bundleIdentifier else { return nil }
            let used = pretended[app.processIdentifier] ?? [lastUsed[app.processIdentifier], app.launchDate, started].compactMap { $0 }.max() ?? started
            return AutoQuit.App(bundleID: id, name: app.localizedName ?? id, pid: app.processIdentifier, lastUsed: used,
                                isFront: app.processIdentifier == front)
        }
    }

    private var delay: TimeInterval { TimeInterval(max(preferences.autoQuitMinutes, 1) * 60) }

    /// One timer, for when the next app reaches the delay; none while off.
    func schedule() {
        timer?.invalidate()
        timer = nil
        guard preferences.autoQuit, let next = AutoQuit.nextCheck(apps(), now: .now, delay: delay, never: Set(preferences.autoQuitNever)) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                Task { await self?.check() }
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Looks now: who is due, who is kept, then quits the rest.
    func check() async {
        guard !checking, preferences.autoQuit || dryRun else { return }
        checking = true
        defer {
            checking = false
            schedule()
        }
        let due = AutoQuit.candidates(apps(), now: .now, delay: delay, never: Set(preferences.autoQuitNever))
        lastQuit = []
        lastKept = []
        guard !due.isEmpty else { return }
        // Without Accessibility unsaved work cannot be seen: nothing goes.
        guard AXIsProcessTrusted() else {
            lastKept = due.map { ($0.name, "Accessibility is off: unsaved work cannot be seen") }
            for app in due { lastUsed[app.pid] = .now }
            return
        }
        let looked = await Self.look(at: due)
        var safe: [(app: AutoQuit.App, titles: [String])] = []
        for (app, state) in zip(due, looked) {
            if let why = state.keeps {
                lastKept.append((app.name, why))
            } else {
                safe.append((app, state.titles))
            }
        }
        safe = await judge(safe)
        // Kept for being in use counts as used: looked at again after a
        // whole delay, not every minute.
        let going = Set(safe.map(\.app.pid))
        for app in due where !going.contains(app.pid) { lastUsed[app.pid] = .now }
        for (app, _) in safe {
            lastQuit.append(app.name)
            guard !dryRun, let running = NSRunningApplication(processIdentifier: app.pid), !running.isTerminated else { continue }
            Log.actions.notice("Auto Quit: \(app.name, privacy: .public), unused for \(Int(Date.now.timeIntervalSince(app.lastUsed) / 60), privacy: .public) min")
            running.terminate()
            Task { [weak self] in await self?.confirmGone(running, name: app.name) }
        }
    }

    /// Gone within 10 s is the answer; still there, it refused (or asks
    /// something): said, and left open.
    private func confirmGone(_ app: NSRunningApplication, name: String) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !app.isTerminated, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !app.isTerminated else { return }
        lastUsed[app.processIdentifier] = .now
        onFailure?("Auto Quit: “\(name)” did not quit. It stays open; it may be asking you something.")
    }

    // MARK: - What keeps an app

    /// What the live Mac says of an app: why it stays, else its windows'
    /// titles for Jev.
    struct State: Sendable {
        var keeps: String?
        var titles: [String] = []
    }

    /// Off the main thread: Accessibility can wait on a busy app.
    private static func look(at apps: [AutoQuit.App]) async -> [State] {
        let targets = apps.map { (pid: $0.pid, bundleID: $0.bundleID) }
        return await Task.detached(priority: .utility) {
            let sounding = soundingProcesses()
            let before = targets.map { cpuSeconds($0.pid) }
            try? await Task.sleep(for: .seconds(2))
            return targets.enumerated().map { index, target -> State in
                if sounding.pids.contains(target.pid) || sounding.bundles.contains(where: { $0 == target.bundleID || $0.hasPrefix(target.bundleID + ".") }) {
                    return State(keeps: "sound or the microphone in use")
                }
                if let start = before[index], let end = cpuSeconds(target.pid), AutoQuit.isBusy(cpuSeconds: end - start, over: 2) {
                    return State(keeps: "busy")
                }
                return windows(of: target.pid)
            }
        }.value
    }

    /// Its windows through Accessibility: one with unsaved work (the dot in
    /// its close button: AppKit says it there, not on the window) or a
    /// modal window or sheet open (a question waiting) keeps it; else their
    /// titles. A window's dialog subrole alone says nothing: Calculator's
    /// and Chess's main windows are "dialogs". Internal for the self-test.
    nonisolated static func windows(of pid: pid_t) -> State {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if status == .cannotComplete || status == .apiDisabled { return State(keeps: "its windows could not be read") }
        guard status == .success, let windows = value as? [AXUIElement] else { return State() }
        var titles: [String] = []
        for window in windows {
            if bool(window, kAXEditedAttribute) == true || bool(window, kAXModalAttribute) == true {
                return State(keeps: "unsaved work or a question open")
            }
            // AppKit says a window's unsaved changes on its close button
            // (the dot in it), as VoiceOver reads it.
            var close: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &close) == .success, let close,
               CFGetTypeID(close) == AXUIElementGetTypeID(), bool(close as! AXUIElement, kAXEditedAttribute) == true {
                return State(keeps: "unsaved work")
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement], children.contains(where: { string($0, kAXRoleAttribute) == kAXSheetRole }) {
                return State(keeps: "a sheet open")
            }
            if let title = string(window, kAXTitleAttribute) { titles.append(title) }
        }
        return State(titles: titles)
    }

    nonisolated private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// The processes CoreAudio says play or record now (macOS 14's process
    /// objects): a call, music, a video. Their pids and bundle ids (a
    /// browser plays from a helper of its own).
    nonisolated private static func soundingProcesses() -> (pids: Set<pid_t>, bundles: [String]) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return ([], []) }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return ([], []) }
        var pids = Set<pid_t>()
        var bundles: [String] = []
        for id in ids {
            let input: UInt32 = read(id, kAudioProcessPropertyIsRunningInput) ?? 0
            let output: UInt32 = read(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            guard input != 0 || output != 0 else { continue }
            if let pid: pid_t = read(id, kAudioProcessPropertyPID) { pids.insert(pid) }
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
                                                           mElement: kAudioObjectPropertyElementMain)
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundle: Unmanaged<CFString>?
            let status = withUnsafeMutablePointer(to: &bundle) { AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, $0) }
            if status == noErr, let bundle { bundles.append(bundle.takeRetainedValue() as String) }
        }
        return (pids, bundles)
    }

    nonisolated private static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    /// The CPU time a process used so far, in seconds (`proc_pid_rusage`).
    nonisolated private static func cpuSeconds(_ pid: pid_t) -> Double? {
        var usage = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard status == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(usage.ri_user_time + usage.ri_system_time)
        return ticks * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    // MARK: - Jev

    /// With a deciding key: one request, a yes or no each, from the apps'
    /// names and windows' titles only; unsure (under 70 %) stays. Without a
    /// key, or when it fails, the rules above decided.
    private func judge(_ apps: [(app: AutoQuit.App, titles: [String])]) async -> [(app: AutoQuit.App, titles: [String])] {
        guard !apps.isEmpty else { return apps }
        let keys = decisionKeys()
        guard !keys.isEmpty else { return apps }
        let described = apps.map { AutoQuit.describe(name: $0.app.name, titles: $0.titles) }
        let questions = described.enumerated().map { index, line in
            DecisionQuestion(name: "app\(index)", instructions: AutoQuit.instructions + " The app: \(line)", options: [
                .init(value: "quit", description: "Safe to quit now: idle, nothing going on in it"),
                .init(value: "keep", description: "Keep it open: something is going on in it, or work is not saved")
            ])
        }
        let input = described.joined(separator: "\n")
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            do {
                let answers = try await DecisionClient.decide(questions, input: input, provider: provider, key: key)
                Log.trace("Auto Quit asked \(provider == .typeSafe ? "Jev" : "Decisions"): \(described.joined(separator: " | "))")
                return apps.enumerated().filter { index, entry in
                    let safe = answers["app\(index)"]?.probabilities["quit"] ?? 0
                    if safe < AutoQuit.safeThreshold { lastKept.append((entry.app.name, "Jev: \(Int(safe * 100)) % safe")) }
                    return safe >= AutoQuit.safeThreshold
                }.map(\.element)
            } catch {
                Log.actions.error("Auto Quit: \(provider.rawValue, privacy: .public) did not answer: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Asked and no answer: nothing is quit on a guess.
        lastKept += apps.map { ($0.app.name, "no answer from the deciding key") }
        return []
    }
}
