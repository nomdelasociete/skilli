import Foundation

/// Ask about one of the user's contacts, read by the decision model: who
/// they are, or a mail to write them; the person as the request names them
/// (a span of its own words, searched in Contacts by code); whether it says
/// what the mail should say.
extension AskValues {
    public enum ContactAsk: Equatable, Sendable {
        /// Who they are: the card. `person`: as the request names them.
        case who(person: String)
        /// A mail to them; `says`: the request tells what it should say.
        case mail(person: String, says: Bool)
        /// Who, or what about them, was not read: asked in the card.
        case missing(Missing)
    }

    static let contactKind = Question(
        name: "contact",
        instructions: "What does the request ask about the person?",
        options: [
            Option("who", "Who they are, or their number, email or address: qui est Jean-François de chez Lumière, le numéro de Paul, Anna's email"),
            Option("mail", "Write them an email: crée un mail à François, écris à Paul pour lui dire…, email Anna about the contract")
        ])

    static let mailSays = Question(
        name: "says",
        instructions: "Does the request say what the mail should say or be about (pour lui dire que la commande arrive lundi, l'objet c'est un nouveau contrat, about the contract), or only who it goes to (crée un mail à François)?",
        options: [Option("yes", "It says what to write or its subject"), Option("no", "Only who it goes to")])

    /// The questions of a request about a contact.
    public static func contactQuestions(words: [String]) -> [Question] {
        [contactKind, personQuestion(words: words), mailSays]
    }

    /// Who the person is, as a phrase of `words` (the request's, or the
    /// answer's in the card).
    static func personQuestion(words: [String]) -> Question {
        phraseQuestion(name: "person",
                       instructions: "Who is the person, as the request names them: their whole name, and their company when it says one? qui est le contact Jean-François qui travaille chez Lumière → “Jean-François”; c'est qui Paul Durand → “Paul Durand”; le numéro de François Leroy → “François Leroy”; écris à François de chez Horizon pour lui dire… → “François de chez Horizon”.",
                       phrases: phrases(of: words), none: "It names no one")
    }

    /// What the answers ask.
    public static func contact(_ answers: [String: Answer], words: [String]) -> ContactAsk {
        guard let person = phrase(answers, "person", phrases: phrases(of: words))?.text else { return .missing(.person) }
        switch answers[contactKind.name]?.choice {
        case "who": return .who(person: person)
        case "mail": return .mail(person: person, says: answers[mailSays.name]?.choice == "yes")
        default: return .missing(.contactKind)
        }
    }
}
