/// Keys → Restore Defaults asks first and says what goes (JB 2026-10-17:
/// one click erased every custom shortcut): the shortcuts the user added,
/// and the built-in ones whose keys were changed.
public enum RestoreDefaults {
    public static let title = "Restore the default shortcuts?"

    /// "Your 3 custom shortcuts and 2 changed keys are removed."; nil when
    /// nothing differs from the defaults (the button is off then).
    public static func message(custom: Int, changed: Int) -> String? {
        let parts = [
            custom > 0 ? "\(custom) custom \(custom == 1 ? "shortcut" : "shortcuts")" : nil,
            changed > 0 ? "\(changed) changed \(changed == 1 ? "key" : "keys")" : nil
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let one = parts.count == 1 && custom + changed == 1
        return "Your \(parts.joined(separator: " and ")) \(one ? "is" : "are") removed."
    }
}
