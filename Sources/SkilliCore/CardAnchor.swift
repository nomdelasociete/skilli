import CoreGraphics

/// Where Ask's card may go beside the focused element when the app does
/// not say where the selection or the caret is: a field or a compose box,
/// never a whole document or web area. Codex on a second screen gave its
/// 1285 × 1034 pt web area: the card went above or below that, wherever it
/// landed (JB 2026-10-16, Ask by Voice, nothing selected). Taller than
/// `tallestField`, the card takes the launcher's place.
public enum CardAnchor {
    /// A compose box at its tallest (Claude's grew to 180 pt).
    public static let tallestField: CGFloat = 320

    public static func isAPlace(field: CGRect) -> Bool {
        field.width > 0 && field.height > 0 && field.height <= tallestField
    }
}
