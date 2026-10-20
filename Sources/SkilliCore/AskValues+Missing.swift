import Foundation

/// A value Ask needs that the request did not give, or gave in words the
/// model could not read ("mets un minuteur pour les pâtes": how long?).
/// Asked in the card in one question, never a failure that makes the user
/// say it all again (rule 6): a small fixed set as keycaps, nothing read;
/// else typed, and that answer alone read by the decision model the way
/// the request was (a choice among fixed options, a phrase of its own
/// words), then joined to what was read already.
extension AskValues {
    public struct Missing: Equatable, Sendable {
        public enum Value: String, Equatable, Sendable {
            /// How long a timer lasts.
            case length
            /// How loud.
            case level
            /// The app to quit or uninstall.
            case app
            /// Who a contact is.
            case person
            /// Who they are, or a mail to them.
            case contactKind
            /// What is asked of Calendar and Reminders.
            case planKind
            /// What a reminder says.
            case reminderTitle
            /// When a reminder rings or an event is.
            case when
            /// How often an ask on a schedule comes back.
            case repeats
            /// The days of the week it comes back on.
            case weekdays
            /// The day of the month it comes back on.
            case dayOfMonth
            /// What skil.li does each time.
            case scheduledAsk
        }

        public let value: Value
        /// The card's question, ways to say it after it.
        public let question: String
        /// A small fixed set, as keycaps: each option's value is the one
        /// the model would pick, its description the keycap. Empty: typed.
        public let options: [Option]
        /// What happened first ("No app named “Slak” on this Mac."), shown
        /// above the question in place of the request.
        public private(set) var note: String?

        init(_ value: Value, _ question: String, options: [Option] = []) {
            self.value = value
            self.question = question
            self.options = options
        }

        /// The same question, after what happened.
        public func noting(_ note: String) -> Missing {
            var copy = self
            copy.note = note
            return copy
        }
    }
}

extension AskValues.Missing {
    public static let length = Self(.length, "How long? (“10 minutes”, “une heure trente”)")
    public static let level = Self(.level, "Which level? (“30 %”, “à la moitié”, “à fond”)")
    public static let app = Self(.app, "Which app? (“Slack”, “Creative Cloud”)")
    public static let person = Self(.person, "Who? (“Paul Martin”, “François de chez Horizon”)")
    public static let contactKind = Self(.contactKind, "What about them?",
                                         options: [.init("who", "Who they are"), .init("mail", "Write them a mail")])
    public static let planKind = Self(.planKind, "What should I do with your calendar or reminders? (“ajoute un rappel”, “mon agenda de demain”)")
    public static let reminderTitle = Self(.reminderTitle, "What should the reminder say? (“appeler Paul”)")
    public static let reminderWhen = Self(.when, "When? (“demain à 9h”, “dans une heure”, “none”)")
    public static let eventDay = Self(.when, "Which day? (“demain à 14h”, “vendredi”)")
    public static let freeWhen = Self(.when, "When? (“jeudi après-midi”, “demain à 15h”)")
    public static let repeats = Self(.repeats, "How often?",
                                     options: [.init("every day", "Every day"), .init("every weekday", "Every weekday"),
                                               .init("every weekend", "Every weekend"), .init("some days", "Some days of the week"),
                                               .init("every month", "Every month")])
    public static let weekdays = Self(.weekdays, "Which days? (“le lundi”, “lundi et jeudi”)")
    public static let dayOfMonth = Self(.dayOfMonth, "Which day of the month? (“le 1er”, “le 15”)")
    public static let scheduledAsk = Self(.scheduledAsk, "What should I do each time? (“résume mes PR”)")

    /// The questions that read the user's answer to it, alone: those the
    /// request was read with, over the answer's own words.
    public func questions(reply: String) -> [AskValues.Question] {
        let words = AskValues.words(of: reply)
        switch value {
        case .length: return AskValues.durationQuestions
        case .level: return AskValues.levelQuestions
        case .app: return AskValues.targetQuestions(words: words)
        case .person: return [AskValues.personQuestion(words: words)]
        case .contactKind: return [AskValues.contactKind]
        case .planKind: return [AskValues.planKind]
        case .reminderTitle: return AskValues.reminderTitleQuestions(words: words)
        case .when: return AskValues.whenQuestions
        case .repeats: return [AskValues.repeatKind]
        case .weekdays: return (0..<3).map(AskValues.namedDay)
        case .dayOfMonth: return [AskValues.dayOfMonth]
        case .scheduledAsk: return [AskValues.scheduledAskQuestion(words: words)]
        }
    }

    /// What the answer gives, to join the request's answers (it wins
    /// there): the choices read, only its own questions'; words it picked
    /// carried as said (`Answer.said`), since they are not the request's.
    /// Empty when it gives nothing (a phrase the model found none of).
    public func answers(_ read: [String: AskValues.Answer], reply: String) -> [String: AskValues.Answer] {
        let words = AskValues.words(of: reply)
        func said(_ name: String, _ picked: (text: String, confidence: Double)?) -> [String: AskValues.Answer] {
            picked.map { [name: AskValues.Answer(choice: "said", confidence: $0.confidence, said: $0.text)] } ?? [:]
        }
        switch value {
        case .app:
            return said("target", AskValues.phrase(read, "target", phrases: AskValues.phrases(of: words, longest: 4)))
        case .person:
            return said("person", AskValues.phrase(read, "person", phrases: AskValues.phrases(of: words)))
        case .scheduledAsk:
            return said("ask", AskValues.phrase(read, "ask", phrases: AskValues.phrases(of: words, longest: 8)))
        case .reminderTitle:
            // The words saying when left out, as in the request.
            return AskValues.title(read, words: words).map {
                ["title_start": AskValues.Answer(choice: "said", confidence: $0.confidence, said: $0.title)]
            } ?? [:]
        default:
            let names = Set(questions(reply: reply).map(\.name))
            return read.filter { names.contains($0.key) }
        }
    }

    /// One of its keycaps picked: the user's own choice, sure. Empty for
    /// an option it does not offer.
    public func answers(picking option: String) -> [String: AskValues.Answer] {
        guard options.contains(where: { $0.value == option }), let name = questions(reply: "").first?.name else { return [:] }
        return [name: AskValues.Answer(choice: option, confidence: 1)]
    }
}
