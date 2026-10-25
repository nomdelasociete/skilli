import Foundation

/// How often skil.li copies what it keeps to the folder chosen in
/// Settings → Backup.
public enum BackupSchedule: String, CaseIterable, Codable, Sendable {
    case off
    case daily
    case weekly
    case monthly

    public var title: String {
        switch self {
        case .off: "Only when I ask"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }
}

/// The pure part of backups: when the next one is due, which old ones go,
/// how one is named and dated, what one holds. The copying lives in the
/// app (`BackupCenter`).
public enum BackupPlan {
    /// "skil.li Backup 2026-10-15 at 09.05.12.zip": a plain zip, so anyone
    /// can open it and see their files.
    public static func name(at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d.%02d.%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return "\(prefix)\(day) at \(time).zip"
    }

    /// The moment a backup's name tells, nil for any other file.
    public static func date(fromName name: String, calendar: Calendar = .current) -> Date? {
        guard name.hasPrefix(prefix), name.hasSuffix(".zip") else { return nil }
        let stamp = name.dropFirst(prefix.count).dropLast(4)
        let pieces = stamp.split(whereSeparator: { "- .".contains($0) }).filter { $0 != "at" }.compactMap { Int($0) }
        guard pieces.count == 6 else { return nil }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2], hour: pieces[3], minute: pieces[4],
                                                  second: pieces[5]))
    }

    /// When the next backup is due: one period after the last, or now when
    /// none was made or the Mac was off when it fell due. Nil when off.
    public static func nextDue(after last: Date?, schedule: BackupSchedule, now: Date, calendar: Calendar = .current) -> Date? {
        let step: DateComponents
        switch schedule {
        case .off: return nil
        case .daily: step = DateComponents(day: 1)
        case .weekly: step = DateComponents(day: 7)
        case .monthly: step = DateComponents(month: 1)
        }
        guard let last, let due = calendar.date(byAdding: step, to: last) else { return now }
        return max(due, now)
    }

    /// Who syncs a folder, by where it is: iCloud Drive (`Library/Mobile
    /// Documents`) or an app under `Library/CloudStorage` ("Dropbox",
    /// "GoogleDrive-…", "OneDrive-…"). Nil when the path does not say
    /// (Desktop and Documents in iCloud: the app asks macOS).
    public static func syncService(ofPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let library = parts.firstIndex(of: "Library"), library + 1 < parts.count else { return nil }
        switch parts[library + 1] {
        case "Mobile Documents":
            return "iCloud"
        case "CloudStorage":
            guard library + 2 < parts.count, let provider = parts[library + 2].split(separator: "-").first.map(String.init) else { return nil }
            return switch provider {
            case "GoogleDrive": "Google Drive"
            default: provider
            }
        default:
            return nil
        }
    }

    /// The backups to delete so that only the newest `keep` stay; none when
    /// every one is kept (nil).
    public static func expired(_ backups: [(url: URL, date: Date)], keep: Int?) -> [URL] {
        guard let keep, keep >= 0 else { return [] }
        return backups.sorted { $0.date > $1.date }.dropFirst(keep).map(\.url)
    }

    /// What a backup's folder holds, in the user's words, for the card
    /// before a restore: "12 snippets", "3 window layouts"…
    public static func summary(of folder: URL, preferenceCount: Int) -> [String] {
        let files = FileManager.default
        func count(_ path: String, kind: String) -> String? {
            let url = folder.appendingPathComponent(path)
            let items = (try? files.contentsOfDirectory(atPath: url.path))?.filter { !$0.hasPrefix(".") } ?? []
            return items.isEmpty ? nil : "\(items.count) \(kind)\(items.count == 1 ? "" : "s")"
        }
        func entries(_ path: String, kind: String) -> String? {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(path)),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [Any], !list.isEmpty else { return nil }
            return "\(list.count) \(kind)\(list.count == 1 ? "" : "s")"
        }
        let lines: [String?] = [
            preferenceCount > 0 ? "\(preferenceCount) setting\(preferenceCount == 1 ? "" : "s")" : nil,
            count("snippets", kind: "snippet"),
            count("prompts", kind: "command"),
            count("skillies", kind: "skillie"),
            entries("quicklinks.json", kind: "quicklink"),
            count("layouts", kind: "window layout"),
            files.fileExists(atPath: folder.appendingPathComponent("shortcuts.json").path) ? "your shortcuts" : nil,
            files.fileExists(atPath: folder.appendingPathComponent("tools.json").path) ? "your tools' rights" : nil,
        ]
        return lines.compactMap { $0 }
    }

    /// Items of skil.li's folder a backup never holds and a restore never
    /// touches: the live socket agents use, the clipboard history (asked
    /// 2026-10-15: settings, skillies and the rest of the folder, never
    /// what was copied), the meeting recordings (2026-10-24: hours of
    /// audio and video, other people's words; a restore removed the
    /// recordings made since the backup), and the index of the words said
    /// in them with SQLite's files beside it (2026-10-25: every
    /// transcript's text). Each by its exact name: an item merely named
    /// like one is the user's and is backed up.
    public static let neverCopied: Set<String> = Set(["mcp.sock", "Clipboard", "Recordings"] + RecordingSearch.indexFiles)

    /// A restore, by item of skil.li's folder: what goes from the folder
    /// now (all but `neverCopied`), then what comes back from the backup
    /// (all but `neverCopied`: an older backup's clipboard history is left
    /// in it, the one on this Mac stays).
    public static func restore(current: [String], backup: [String]) -> (remove: [String], copy: [String]) {
        (current.filter { !neverCopied.contains($0) }, backup.filter { !neverCopied.contains($0) })
    }

    private static let prefix = "skil.li Backup "
}
