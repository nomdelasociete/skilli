import Darwin
import Foundation
import os
import SkilliCore

/// skil.li with its main thread held is in the menu bar and answers
/// nothing: no key, no click, and macOS's Force Quit window does not list a
/// menu bar app. From its own queue, this asks the main run loop to answer
/// every few seconds (`HangWatch`). Unanswered for 30 s, every thread's
/// stack is written to `~/Library/Logs/skil.li/` (`/usr/bin/sample`: what
/// held it, to fix it), then skil.li starts again by itself.
///
/// Not while a meeting records (its files are written off the main thread;
/// the stacks are still captured), not twice within ten minutes, not under
/// a debugger. The app as launched by its user only: the benchmark and the
/// self-tests hold the main thread on purpose.
final class MainThreadWatchdog: Sendable {
    static let shared = MainThreadWatchdog()

    /// Where the stacks go, the ten latest kept.
    static let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("skil.li", isDirectory: true)
    private static let relaunchedKey = "watchdogRelaunchedAt"
    private static let kept = 10

    private struct State {
        var watch = HangWatch()
        var timer: DispatchSourceTimer?
    }

    private let queue = DispatchQueue(label: "com.nomdelasociete.Skilli.watchdog", qos: .userInitiated)
    /// Read and written on `queue` only.
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private let recording = OSAllocatedUnfairLock(initialState: false)

    /// A meeting is being recorded (said by `MeetingRecorder`).
    var isRecording: Bool {
        get { recording.withLock { $0 } }
        set { recording.withLock { $0 = newValue } }
    }

    func start() {
        queue.async { [self] in
            guard state.withLock({ $0.timer == nil }) else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            // Uptime: neither runs nor counts while the Mac sleeps.
            timer.schedule(deadline: .now() + HangWatch.tick, repeating: HangWatch.tick, leeway: .seconds(1))
            timer.setEventHandler { [self] in tick() }
            state.withLock { $0.timer = timer }
            timer.resume()
        }
    }

    private func tick() {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        let relaunched = UserDefaults.standard.double(forKey: Self.relaunchedKey)
        let since = relaunched > 0 ? Date.now.timeIntervalSince1970 - relaunched : nil
        let recording = isRecording
        switch state.withLock({ $0.watch.tick(now: now, recording: recording, sinceRelaunch: since) }) {
        case .ask: ask()
        case .wait: break
        case .capture: capture(recording: recording)
        case .relaunch: relaunch()
        }
    }

    /// On the main run loop itself, in the mode it runs now and in the
    /// common ones: its blocks run inside a menu's or a modal session's
    /// loop, where the main queue may not.
    private func ask() {
        let main = CFRunLoopGetMain()
        let answer = { [self] in queue.async { [self] in state.withLock { $0.watch.answered() } } }
        CFRunLoopPerformBlock(main, CFRunLoopMode.commonModes.rawValue, answer)
        if let mode = CFRunLoopCopyCurrentMode(main) { CFRunLoopPerformBlock(main, mode.rawValue, answer) }
        CFRunLoopWakeUp(main)
    }

    private func capture(recording: Bool) {
        // Stopped at a breakpoint: nothing held.
        guard !Self.isDebugged else { return }
        let folder = Self.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // This Mac's time, as its logs say it.
        let stamp = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let file = folder.appendingPathComponent("hang \(stamp).txt")
        let sample = Process()
        sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        sample.arguments = [String(getpid()), "3", "-file", file.path]
        sample.standardOutput = FileHandle.nullDevice
        sample.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        sample.terminationHandler = { _ in done.signal() }
        var written = false
        if (try? sample.run()) != nil {
            // 3 s of samples, then their symbols: never waited for longer.
            if done.wait(timeout: .now() + 30) == .timedOut { sample.terminate() }
            written = FileManager.default.fileExists(atPath: file.path)
        }
        Log.actions.error("""
            Main thread held for \(Int(HangWatch.held), privacy: .public) s\(recording ? " (a meeting records: not relaunched)" : "", privacy: .public): \
            \(written ? "stacks in Logs/skil.li/\(file.lastPathComponent)" : "its stacks could not be written", privacy: .public)
            """)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("hang ") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(Self.kept) { try? FileManager.default.removeItem(at: old) }
    }

    /// The watcher that opens skil.li once this process is gone, then gone:
    /// nothing asked of the main thread, which does not answer.
    private func relaunch() {
        guard !Self.isDebugged else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.relaunchedKey)
        do {
            try Relaunch.leaveWatcher()
        } catch {
            // Left as it is: no skil.li at all would be worse.
            Log.actions.error("Main thread still held: not relaunched, no watcher (\(error.localizedDescription, privacy: .public))")
            return
        }
        Log.actions.error("Main thread still held: skil.li starts again")
        _exit(EXIT_FAILURE)
    }

    #if SKILLI_SELFTEST
    /// `remote-watchdog`: never returns; its name is looked for in the
    /// stacks written.
    @inline(never)
    static func holdMainForSelfTest() -> Never {
        while true { Thread.sleep(forTimeInterval: 3600) }
    }
    #endif

    private static var isDebugged: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}
