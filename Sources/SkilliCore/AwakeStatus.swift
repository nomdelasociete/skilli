import Foundation

/// The Mac kept awake now, as skil.li shows it: the time left beside the
/// cup (the menu bar, the launcher's chip), the launcher's running row, and
/// one hour more from that row's ⌘K.
public enum AwakeStatus {
    /// What "1 h Longer" adds.
    public static let longer = 3_600

    /// "59 min", "1 h 20", "3 h": the time left, rounded up to the minute.
    public static func left(until: Date, now: Date = .now) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    /// The running row: "Keeping Awake · 42 min left (until 14:05)", as
    /// "Keep Awake · 1 h (until 14:05)" asks for it; untimed, "Keeping
    /// Awake · until you allow sleep". `time`: "14:05" in the user's format.
    public static func title(until: Date?, now: Date = .now, time: (Date) -> String) -> String {
        guard let until else { return "Keeping Awake · until you allow sleep" }
        return "Keeping Awake · \(left(until: until, now: now)) left (until \(time(until)))"
    }

    /// Seconds from now to an hour past `until` (an hour from now when it
    /// already ended).
    public static func secondsLonger(until: Date, now: Date = .now) -> Int {
        max(0, Int(until.timeIntervalSince(now).rounded())) + longer
    }
}
