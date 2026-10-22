import Foundation

/// "awake 1 hour", "do not sleep 1", "garde le mac éveillé 2h", "caffeinate
/// until 6pm", "pas de veille jusqu'à 18h30", "allow sleep": read without a
/// model, like a timer. A bare number is hours (keeping a Mac awake for
/// one minute is not what anyone means), unless it is above 24.
public enum AwakeRequest: Equatable, Sendable {
    /// Awake for that many seconds.
    case awake(seconds: Int)
    /// Back to normal sleep.
    case allowSleep

    /// The word the Catalog teaches: "awake 2h".
    public static let word = "awake"
    /// The words that ask for it, whole words without accents.
    private static let phrases: [[String]] = [
        [word], ["caffeinate"], ["caffeine"], ["cafeine"], ["amphetamine"], ["insomnia"],
        ["no", "sleep"], ["do", "not", "sleep"], ["don", "t", "sleep"], ["dont", "sleep"], ["prevent", "sleep"], ["never", "sleep"],
        ["eveille"], ["eveillee"], ["pas", "de", "veille"], ["sans", "veille"], ["empeche", "la", "veille"], ["ne", "dors", "pas"],
        ["ne", "pas", "dormir"], ["pas", "dormir"]
    ]
    private static let offPhrases: [[String]] = [
        ["allow", "sleep"], ["awake", "off"], ["stop", "awake"], ["let", "it", "sleep"], ["laisse", "dormir"], ["laisse", "le", "mac", "dormir"],
        ["autorise", "la", "veille"], ["veille", "normale"]
    ]

    /// Nil when the text does not ask to keep the Mac awake for a while
    /// (plain "keep awake" is the Keep Awake command). The launcher's typed
    /// words, its row showing what was read before ↩; Ask reads sentences
    /// with the decision model (`AskValues`), never this.
    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> AwakeRequest? {
        let folded = fold(text)
        let words = words(folded)
        if offPhrases.contains(where: { contains(words, $0) }) { return .allowSleep }
        guard phrases.contains(where: { contains(words, $0) }) else { return nil }
        if let seconds = untilTime(in: folded, now: now, calendar: calendar) { return .awake(seconds: seconds) }
        guard let (seconds, range) = TimerRequest.duration(in: folded) else { return nil }
        // A unit or a clock was written ("1 hour", "90 min", "1:30"); a
        // bare number is hours up to 24, minutes above.
        let written = folded[range]
        var total = seconds
        if !written.contains(where: { $0.isLetter || $0 == ":" }), let number = Int(written.trimmingCharacters(in: .whitespaces)) {
            total = number <= 24 ? number * 3_600 : number * 60
        }
        guard total > 0, total <= 7 * 24 * 3_600 else { return nil }
        return .awake(seconds: total)
    }

    /// Whether the words are about keeping the Mac awake at all, a length
    /// said or not ("awake", "keep awake", "caffeinate", "allow sleep"):
    /// while it is kept awake, the launcher then shows it running.
    public static func mentions(_ text: String) -> Bool {
        let words = words(fold(text))
        return (phrases + offPhrases).contains { contains(words, $0) }
    }

    private static func fold(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "’", with: "'")
    }

    private static func words(_ folded: String) -> [String] {
        folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// "until 6pm", "till 18:30", "jusqu'à 18h", "jusqu'a 18h30": seconds
    /// from now to that time, today or else tomorrow.
    static func untilTime(in text: String, now: Date, calendar: Calendar) -> Int? {
        let pattern = #"(?:until|till|jusqu'?\s?a|jusque)\s*(\d{1,2})(?:\s*(?:h|:)\s*(\d{2})?)?\s*(am|pm)?(?![\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
        guard var hour = group(1).flatMap(Int.init) else { return nil }
        let minute = group(2).flatMap(Int.init) ?? 0
        switch group(3) {
        case "pm" where hour < 12: hour += 12
        case "am" where hour == 12: hour = 0
        default: break
        }
        guard hour < 24, minute < 60,
              var target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        if target <= now { target = calendar.date(byAdding: .day, value: 1, to: target) ?? target }
        return Int(target.timeIntervalSince(now).rounded())
    }

    /// "1 h", "1 h 30", "45 min": how long, for the card and the menu.
    public static func spoken(_ seconds: Int) -> String {
        TimerRequest.spoken(seconds)
    }

    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}
