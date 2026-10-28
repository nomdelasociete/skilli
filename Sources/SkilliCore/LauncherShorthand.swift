import Foundation

/// "awa 2h", "tim 10 tea", "vo 30", "a 2h" (an alias): a command that reads
/// a value takes it after a space, its word typed whole, cut short or
/// replaced by the user's alias. The text comes back with the word whole
/// ("awake 2h") for that command's own parser; nothing is read here.
public enum LauncherShorthand {
    /// The words that may be cut short: their value is strict (a duration,
    /// a time, a level), so "visual st" never becomes a command. Free-text
    /// values ("event", "remind me", "rec") only after the word or an alias.
    static let shortened = [AwakeRequest.word, TimerRequest.word, VolumeRequest.word]
    /// The rows that read a value, by `learningID`: their alias carries it,
    /// free text included ("r Weekly sync").
    static let aliased: [String: String] = ["system:keepAwake": AwakeRequest.word, "cmd:recordMeeting": RecordRequest.word]
    /// Fewer letters say too little ("t 5").
    static let minimum = 2

    /// The text with its first word written whole, or nil when it is
    /// neither an alias of a row that reads a value nor the start of one
    /// word above, or nothing follows the space yet.
    public static func expand(_ text: String, aliases: [LauncherAlias]) -> String? {
        guard let space = text.firstIndex(of: " ") else { return nil }
        let rest = text[text.index(after: space)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        // The user's alias wins: on a row that reads a value it carries it;
        // on anything else ("aw" for an app) the word is not cut short.
        if let (alias, _) = LauncherAliases.split(text, among: aliases) { return aliased[alias.id].map { $0 + " " + rest } }
        let typed = text[..<space].lowercased()
        guard typed.count >= minimum, typed.allSatisfy(\.isLetter) else { return nil }
        let words = shortened.filter { $0.count > typed.count && $0.hasPrefix(typed) }
        guard words.count == 1, let word = words.first else { return nil }
        return word + " " + rest
    }
}
