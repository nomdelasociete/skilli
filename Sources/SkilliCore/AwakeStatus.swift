import Foundation

/// The Mac kept awake now, as skil.li shows it: the time left beside the
/// cup (the menu bar, the launcher's chip), the launcher's running row, and
/// one hour more from that row's ⌘K.
public enum AwakeStatus {
    /// What "1 h Longer" adds.
    public static let longer = 3_600
    /// The words for stopping it, everywhere a person reads them (the
    /// launcher, the menu bar's cup, the status menu); 2026-10-22: "Allow
    /// Sleep" did not say it clearly. "allow sleep" still works typed.
    public static let turnOff = "Turn Off Keep Awake"
    /// The chip's own, under the pointer: "42 min · Turn Off".
    public static let chipTurnOff = "Turn Off"

    /// "59 min", "1 h 20", "3 h": the time left, rounded up to the minute.
    public static func left(until: Date, now: Date = .now) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    /// The running row, its state and its end plainly: "Keep Awake on ·
    /// until 14:05 (42 min left)"; untimed, "Keep Awake on · until you turn
    /// it off". `time`: "14:05" in the user's format.
    public static func title(until: Date?, now: Date = .now, time: (Date) -> String) -> String {
        guard let until else { return "Keep Awake on · until you turn it off" }
        return "Keep Awake on · until \(time(until)) (\(left(until: until, now: now)) left)"
    }

    /// The chip: the time left, and under the pointer what a click does
    /// ("42 min · Turn Off"; untimed, the cup alone or "Turn Off").
    public static func chip(left: String, hovered: Bool) -> String {
        guard hovered else { return left }
        return left.isEmpty ? chipTurnOff : "\(left) · \(chipTurnOff)"
    }

    /// Seconds from now to an hour past `until` (an hour from now when it
    /// already ended).
    public static func secondsLonger(until: Date, now: Date = .now) -> Int {
        max(0, Int(until.timeIntervalSince(now).rounded())) + longer
    }
}
