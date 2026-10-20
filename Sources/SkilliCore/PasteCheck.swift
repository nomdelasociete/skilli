import Foundation

/// After skil.li pastes (⌘V with its text on the clipboard): whether the
/// field shows the pasted text yet, so the user's clipboard goes back only
/// then. Keys sent just before the paste (a snippet keyword's deletes)
/// change the field too, later in a web page or Electron app than in a
/// native one: only the pasted words say the paste landed.
public enum PasteCheck {
    /// The pasted text's first words as a field shows them: its first line
    /// with words, trimmed, 24 characters at most; empty when it has none.
    public static func probe(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return String(line.prefix(24))
    }

    /// The field now shows the pasted text once more than before it; with
    /// no words to look for, any change does.
    public static func landed(before: String, now: String, probe: String) -> Bool {
        guard now != before else { return false }
        guard !probe.isEmpty else { return true }
        return occurrences(of: probe, in: now) > occurrences(of: probe, in: before)
    }

    static func occurrences(of probe: String, in text: String) -> Int {
        text.components(separatedBy: probe).count - 1
    }
}
