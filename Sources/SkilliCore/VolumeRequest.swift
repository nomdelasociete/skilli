import Foundation

/// "volume 30", "volume à 30 %", "mets le son à 30 %", "set the volume to
/// 30 percent", "son au max": the output volume to set, 0…100, read
/// without a model. A sound word and one level are needed, so "30 % de 85"
/// stays a calculation and "monte le son" a step (Ask's model picks Volume Up).
/// "Monte le son de 10" moves it by 10: not a level, nil.
public enum VolumeRequest {
    /// The word the Catalog teaches: "volume 30".
    public static let word = "volume"

    private static let soundWords: Set<String> = ["volume", "vol", "son", "sound", "audio"]
    /// Said instead of a number.
    private static let named: [String: Int] = ["max": 100, "maximum": 100, "fond": 100, "full": 100, "moitie": 50, "half": 50,
                                               "zero": 0, "min": 0, "minimum": 0]
    /// Words that may stand around the level and the sound word.
    private static let filler: Set<String> = [
        "mets", "met", "mettre", "regle", "regler", "baisse", "baisser", "monte", "monter", "le", "la", "les", "l", "du", "de", "d",
        "a", "au", "sur", "en", "pourcent", "pourcents", "pour", "cent", "percent", "pct", "set", "turn", "put", "change", "the", "to",
        "at", "my", "mon", "ma", "volume", "vol", "son", "sound", "audio", "please", "s", "il", "te", "plait", "stp", "sortie", "output",
        "max", "maximum", "fond", "full", "moitie", "half", "zero", "min", "minimum", "niveau", "level", "up", "down", "it", "of", "mac"
    ]

    /// The level asked for, 0…100; nil when the text asks for something
    /// else.
    public static func parse(_ text: String) -> Int? {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "’", with: "'")
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty, words.count <= 12, !Set(words).isDisjoint(with: soundWords) else { return nil }
        // Every other word must be one that stands around a level: "son
        // de la vidéo à 30" or "volume de Spotify" are not the Mac's.
        guard words.allSatisfy({ filler.contains($0) || Int($0) != nil }) else { return nil }
        let numbers = words.compactMap { Int($0) }
        let level: Int
        if numbers.count == 1 {
            level = numbers[0]
            // "monte le son de 10", "turn it up by 10": a step, not a level.
            if let index = words.firstIndex(of: String(level)), index > 0, ["de", "by"].contains(words[index - 1]) { return nil }
        } else if numbers.isEmpty, let word = words.first(where: { named[$0] != nil }), let value = named[word] {
            level = value
        } else {
            return nil
        }
        guard (0...100).contains(level) else { return nil }
        return level
    }

    /// "Set Volume to 30 %".
    public static func title(_ level: Int) -> String {
        "Set Volume to \(level) %"
    }
}
