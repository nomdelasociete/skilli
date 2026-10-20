import AppKit
import Darwin
import SkilliCore

/// Reopening skil.li after System Settings quits it to apply a permission
/// (see `QuitSender`). skil.li leaves a watcher behind, its own binary as a
/// command-line tool:
///
///     Skilli relaunch <pid> <app path>
///         Waits for <pid> to end (the kernel says when: no polling), then
///         opens the app.
enum Relaunch {
    /// The exit status when the arguments ask for the watcher, nil to start
    /// the app.
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == "relaunch" else { return nil }
        guard arguments.count == 4, let pid = pid_t(arguments[2]), pid > 0 else {
            FileHandle.standardError.write(Data("usage: Skilli relaunch <pid> <app path>\n".utf8))
            return 2
        }
        let app = arguments[3]
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { open(app) }
        source.resume()
        // Already gone before the watch began: no exit event will come.
        if kill(pid, 0) != 0, errno == ESRCH { open(app) }
        dispatchMain()
    }

    /// The Quit being handled came from System Settings.
    @MainActor
    static func quitBySystemSettings() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEQuitApplication),
              let sender = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, sender > 0,
              let path = executable(of: sender) else { return false }
        Log.trace("Quit sent by \(path)")
        return QuitSender.reopensAfter(path)
    }

    /// Leaves the watcher that opens this app again once this process ends.
    @MainActor
    static func afterExit() {
        guard let binary = Bundle.main.executableURL else { return }
        let watcher = Process()
        watcher.executableURL = binary
        watcher.arguments = ["relaunch", String(getpid()), Bundle.main.bundlePath]
        do {
            try watcher.run()
            Log.actions.notice("Quit by System Settings: skil.li reopens once it has quit")
        } catch {
            Log.actions.notice("Quit by System Settings: no watcher (\(error.localizedDescription, privacy: .public))")
        }
    }

    private static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func open(_ app: String) -> Never {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [app]
        try? open.run()
        open.waitUntilExit()
        exit(open.terminationStatus)
    }
}
