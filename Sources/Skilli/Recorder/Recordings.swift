import Foundation
import SkilliCore
import Synchronization

/// Where recordings are kept (docs/meeting-recorder.md, "Where it lives"):
/// a folder each in `~/Library/Application Support/skil.li/Recordings`
/// (0700, the user's alone), or the folder Settings → Recorder names,
/// each named by its date and title, never written into another's. The
/// self-test keeps its own.
final class Recordings: Sendable {
    private let place: Mutex<URL>

    /// The folder they are in: another once Settings → Recorder moved them.
    var root: URL {
        get { place.withLock { $0 } }
        set { place.withLock { $0 = newValue } }
    }

    /// A recording made, transcribed, deleted or put back: the lists
    /// (Settings → Recorder, the launcher) read again.
    static let changed = Notification.Name("com.nomdelasociete.Skilli.recordingsChanged")

    init(root: URL = Recordings.standard) {
        place = Mutex(root)
    }

    static var standard: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true).appendingPathComponent("Recordings", isDirectory: true)
    }

    static let record = "meeting.json"

    /// A new recording's folder, made now: its name the date and the title,
    /// " 2" after it when one of that name is there.
    func makeFolder(title: String, started: Date) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = RecordingFolder.free(RecordingFolder.name(title: title, started: started)) {
            manager.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let folder = root.appendingPathComponent(name, isDirectory: true)
        // Never into another's: one made meanwhile throws.
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    func read(_ folder: URL) -> MeetingRecord? {
        (try? Data(contentsOf: folder.appendingPathComponent(Self.record))).flatMap { try? MeetingRecord.decode($0) }
    }

    func write(_ record: MeetingRecord, to folder: URL) throws {
        try record.encoded().write(to: folder.appendingPathComponent(Self.record), options: .atomic)
    }

    /// The transcript's lines, once made.
    func transcript(_ folder: URL) -> MeetingTranscript.File? {
        (try? Data(contentsOf: folder.appendingPathComponent("transcript.json"))).flatMap { try? MeetingTranscript.File.decode($0) }
    }

    /// Recordings never stopped (skil.li crashed, the Mac lost power),
    /// newest first. Off the main thread: a few small files read.
    func unfinished() -> [(folder: URL, record: MeetingRecord)] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder in read(folder).map { (folder, $0) } }
            .filter { $0.record.isUnfinished(isRunning: Self.isRunning) }
            .sorted { $0.record.started > $1.record.started }
    }

    /// Recordings closed as skil.li quit, their transcript to make, newest
    /// first. Off the main thread.
    func stopped() -> [(folder: URL, record: MeetingRecord)] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder in read(folder).map { (folder, $0) } }
            .filter { $0.record.state == .stopped }
            .sorted { $0.record.started > $1.record.started }
    }

    /// A title given later renames its folder by the same rules (its date
    /// kept); the folder it is in now.
    func rename(_ folder: URL, to title: String, started: Date) throws -> URL {
        let manager = FileManager.default
        let wanted = RecordingFolder.name(title: title, started: started)
        guard wanted != folder.lastPathComponent else { return folder }
        let name = RecordingFolder.free(wanted) { $0 != folder.lastPathComponent && manager.fileExists(atPath: root.appendingPathComponent($0).path) }
        let renamed = root.appendingPathComponent(name, isDirectory: true)
        try manager.moveItem(at: folder, to: renamed)
        return renamed
    }

    // MARK: - Who records

    /// This process, as `meeting.json` names its recorder.
    static var ownProcess: MeetingRecord.Owner {
        let pid = getpid()
        return MeetingRecord.Owner(pid: pid, launched: launched(pid) ?? .now)
    }

    /// Whether `owner` still runs: a process of its number, started when it
    /// was (to the second: `meeting.json` keeps no less).
    static func isRunning(_ owner: MeetingRecord.Owner) -> Bool {
        guard kill(owner.pid, 0) == 0 || errno == EPERM, let launched = launched(owner.pid) else { return false }
        return abs(launched.timeIntervalSince(owner.launched)) < 1.5
    }

    /// When the process `pid` started (the kernel's own record).
    static func launched(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
    }
}
