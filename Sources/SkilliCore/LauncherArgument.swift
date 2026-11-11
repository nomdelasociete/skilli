import Foundation

/// The value a built-in command reads, said by the command itself: the
/// launcher turns into its chip (the user's alias then a space, or ↩ on it
/// in the Catalog) and the field holds only that value, read by the
/// command's own parser. Spec: `docs/launcher-arguments.md`.
public struct LauncherArgument: Hashable, Sendable {
    /// The alias's id: the launcher row's (`LauncherItem.learningID`) or,
    /// for what has no row of its own, the Catalog entry's.
    public let id: String
    /// The command's name, as the Catalog lists it.
    public let title: String
    /// The chip before the field.
    public let chip: String
    /// The word the command's parser reads before the value ("awake").
    public let word: String
    /// An example of the value, shown while the field is empty.
    public let placeholder: String
    /// ⌘K on the command's row, for a command that does something with no
    /// value (↩ toggles Keep Awake, records a meeting): the action that
    /// opens its chip. Nil where ↩ on the command opens the chip itself.
    public var ask: String?

    public static let all: [LauncherArgument] = [
        LauncherArgument(id: "system:keepAwake", title: "Keep Awake", chip: "Keep Awake", word: AwakeRequest.word, placeholder: "2h, 90 min, until 6pm",
                         ask: "Keep Awake for a While…"),
        LauncherArgument(id: "catalog.awake", title: "Keep Awake for a While", chip: "Keep Awake", word: AwakeRequest.word, placeholder: "2h, 90 min, until 6pm"),
        LauncherArgument(id: "catalog.timer", title: "Timer", chip: "Timer", word: TimerRequest.word, placeholder: "10 min tea, 1:30"),
        LauncherArgument(id: "catalog.volume", title: "Set Volume", chip: "Volume", word: VolumeRequest.word, placeholder: "30"),
        LauncherArgument(id: "cmd:recordMeeting", title: "Record Meeting", chip: "Record", word: RecordRequest.word, placeholder: "A name for the recording",
                         ask: "Name the Recording…"),
        LauncherArgument(id: "catalog.event", title: "Add an Event", chip: "Event", word: EventRequest.word, placeholder: "lunch with Paul tomorrow 1pm"),
        LauncherArgument(id: "catalog.remind", title: "Remind Me", chip: "Remind Me", word: ReminderRequest.word, placeholder: "call Paul at 9am")
    ]

    /// The argument of the command an alias names, when it reads one.
    public static func of(_ id: String) -> LauncherArgument? {
        all.first { $0.id == id }
    }

    /// What the command's parser reads for the value typed: "2h" →
    /// "awake 2h". Nil while nothing is typed.
    public func text(_ typed: String) -> String? {
        let value = typed.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : word + " " + value
    }
}
