import Foundation

/// Local, instant transforms applied to the selected text. They exercise the
/// read → transform → replace pipeline that AI presets will plug into.
public enum TextTransform: String, CaseIterable, Hashable, Sendable, Codable {
    case uppercase
    case lowercase
    case capitalized

    public func apply(_ text: String, locale: Locale = .current) -> String {
        switch self {
        case .uppercase: text.uppercased(with: locale)
        case .lowercase: text.lowercased(with: locale)
        case .capitalized: text.capitalized(with: locale)
        }
    }

    /// Its name in Settings, the leader overlay and the Catalog.
    public var title: String {
        switch self {
        case .uppercase: "UPPERCASE Selection"
        case .lowercase: "lowercase Selection"
        case .capitalized: "Title Case Selection"
        }
    }

    /// What the text already is when there is nothing to change: "in
    /// UPPERCASE".
    public var state: String {
        switch self {
        case .uppercase: "in UPPERCASE"
        case .lowercase: "in lowercase"
        case .capitalized: "in Title Case"
        }
    }
}
