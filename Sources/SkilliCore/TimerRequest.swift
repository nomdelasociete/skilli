import Foundation

/// "timer 10 min pâtes", "minuteur 1h30", "mets un minuteur de 10 minutes
/// pour les pâtes", "pomodoro": how long, and what for.
public struct TimerRequest: Equatable, Sendable {
    public let seconds: Int
    public let label: String

    public init(seconds: Int, label: String) {
        self.seconds = seconds
        self.label = label
    }

    /// The word the Catalog teaches: "timer 10 min".
    public static let word = "timer"
    private static let keywords = [word, "minuteur", "chrono", "compte à rebours", "countdown", "pomodoro", "rappelle-moi dans", "remind me in"]
    private static let fillers: Set<String> = ["de", "d'", "pour", "for", "a", "an", "un", "une", "le", "la", "les", "the", "mets", "met", "lance",
                                                "start", "set", "moi", "me", "dans", "in", "of", "s'il", "te", "plait", "plaît", "please", "et", "and"]

    /// Nil when the text does not ask for a timer, or says no duration.
    public static func parse(_ text: String) -> TimerRequest? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyword = keywords.first(where: { lower.contains($0) }) else { return nil }
        if keyword == "pomodoro", !lower.contains(where: \.isNumber) { return TimerRequest(seconds: 25 * 60, label: "Pomodoro") }
        var rest = lower.replacingOccurrences(of: keyword, with: " ")
        guard let (seconds, range) = duration(in: rest), seconds > 0, seconds <= 24 * 3_600 else { return nil }
        rest.replaceSubrange(range, with: " ")
        let words = rest.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !fillers.contains($0) && !$0.hasPrefix("d'") }
        // The label as typed, its first letter up.
        let label = words.joined(separator: " ")
        return TimerRequest(seconds: seconds, label: label.prefix(1).uppercased() + label.dropFirst())
    }

    /// "1h30", "1 h 30", "10 min", "10m", "90s", "2 minutes 30", "1:30",
    /// "10": the first duration and where it is.
    static func duration(in text: String) -> (Int, Range<String.Index>)? {
        let units: [(names: [String], seconds: Int)] = [
            (["heures", "heure", "hours", "hour", "hrs", "hr", "h"], 3_600),
            (["minutes", "minute", "mins", "min", "mn", "m"], 60),
            (["secondes", "seconde", "seconds", "second", "secs", "sec", "s"], 1)
        ]
        // "1:30" is minutes and seconds; "1:02:03" hours too.
        if let match = text.range(of: #"\b\d{1,2}(:\d{2}){1,2}\b"#, options: .regularExpression) {
            let parts = text[match].split(separator: ":").compactMap { Int($0) }
            let seconds = parts.count == 3 ? parts[0] * 3_600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1]
            return (seconds, match)
        }
        let unitPattern = units.flatMap(\.names).joined(separator: "|")
        // "1h30": a unit may touch the digits after it, not a letter.
        let pattern = #"(\d+(?:[.,]\d+)?)\s*("# + unitPattern + #")(?![a-zà-ÿ])(?:\s*(\d+)(?:\s*("# + unitPattern + #")(?![a-zà-ÿ]))?)?"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            let piece = String(text[match])
            let regex = try? NSRegularExpression(pattern: pattern)
            guard let result = regex?.firstMatch(in: piece, range: NSRange(piece.startIndex..., in: piece)) else { return nil }
            func group(_ index: Int) -> String? {
                Range(result.range(at: index), in: piece).map { String(piece[$0]) }
            }
            func seconds(of unit: String?) -> Int { units.first { $0.names.contains(unit ?? "") }?.seconds ?? 60 }
            let amount = Double(group(1)?.replacingOccurrences(of: ",", with: ".") ?? "") ?? 0
            let first = seconds(of: group(2))
            var total = Int((amount * Double(first)).rounded())
            if let extra = group(3).flatMap(Int.init) {
                // "1h30" is 30 minutes more; "2 min 30" 30 seconds more.
                total += extra * (group(4).map(seconds(of:)) ?? first / 60)
            }
            return (total, match)
        }
        // A bare number is minutes: "timer 10".
        if let match = text.range(of: #"\b\d+\b"#, options: .regularExpression), let minutes = Int(text[match]) {
            return (minutes * 60, match)
        }
        return nil
    }

    /// "9:41", "1:02:03".
    public static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3_600, minutes = (seconds % 3_600) / 60, rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// "10 min", "1 h 30", "45 s".
    public static func spoken(_ seconds: Int) -> String {
        let hours = seconds / 3_600, minutes = (seconds % 3_600) / 60, rest = seconds % 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(hours) h" }
        if minutes > 0 { return rest > 0 ? "\(minutes) min \(rest) s" : "\(minutes) min" }
        return "\(rest) s"
    }
}
