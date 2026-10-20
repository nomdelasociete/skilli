import Foundation

/// When an agent says a reminder is due: ISO 8601 as models write it —
/// `2026-10-11T21:00`, with seconds or an offset, or a day alone.
public enum ReminderDate {
    public struct Due: Equatable, Sendable {
        public let date: Date
        /// A day alone: due that day, no alert time.
        public let hasTime: Bool
    }

    public static func parse(_ text: String, timeZone: TimeZone = .current) -> Due? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        // With an offset or Z: the moment is exact.
        let exact = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            exact.formatOptions = options
            if let date = exact.date(from: text) { return Due(date: date, hasTime: true) }
        }
        // Without: the user's own clock.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timeZone
        for (format, hasTime) in [("yyyy-MM-dd'T'HH:mm:ss", true), ("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd", false)] {
            local.dateFormat = format
            if let date = local.date(from: text) { return Due(date: date, hasTime: hasTime) }
        }
        return nil
    }
}
