import Foundation

/// What an image shows, as Jev tags it once (Settings → Clipboard → Images):
/// one kind among a few, and whether there is a person in it. Kept as words
/// beside the text read in it, so "the invoice", "le graphique", "the photo
/// of Paul" find it later on this Mac, nothing sent.
public struct ImageTags: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case screenshot, code, chat, document, invoice, chart, diagram, photo, design, other

        /// What Jev reads to pick it.
        public var criteria: String {
            switch self {
            case .screenshot: "A screenshot of an app or a website: windows, buttons, menus, settings"
            case .code: "Source code or a terminal"
            case .chat: "A chat or messages conversation"
            case .document: "A document or a page of text"
            case .invoice: "An invoice, a receipt, a bill or a ticket"
            case .chart: "A chart or a graph of numbers"
            case .diagram: "A diagram, a schema or a flowchart"
            case .photo: "A photo of the real world: people, places, landscapes, objects"
            case .design: "A design, a logo, an illustration or a mockup"
            case .other: "Anything else"
            }
        }

        /// The words people search it with, in English and French.
        public var words: [String] {
            switch self {
            case .screenshot: ["screenshot", "screen", "capture", "écran"]
            case .code: ["code", "terminal", "programme"]
            case .chat: ["chat", "conversation", "message", "messages", "discussion"]
            case .document: ["document", "page", "texte", "doc"]
            case .invoice: ["invoice", "receipt", "bill", "ticket", "facture", "reçu", "note"]
            case .chart: ["chart", "graph", "graphique", "courbe", "diagramme"]
            case .diagram: ["diagram", "schema", "flowchart", "schéma"]
            case .photo: ["photo", "picture", "image"]
            case .design: ["design", "logo", "illustration", "mockup", "maquette"]
            case .other: []
            }
        }

        /// What it shows, as a sentence says it after "SI sees".
        public var seen: String {
            switch self {
            case .screenshot: "a screenshot of an app or a website"
            case .code: "code or a terminal"
            case .chat: "a chat or a conversation"
            case .document: "a document or a page of text"
            case .invoice: "an invoice, a receipt or a bill"
            case .chart: "a chart or a graph of numbers"
            case .diagram: "a diagram or a flowchart"
            case .photo: "a photo"
            case .design: "a design, a logo or an illustration"
            case .other: "an image"
            }
        }

        /// "Invoice": shown in the clipboard history.
        public var title: String {
            switch self {
            case .screenshot: "Screenshot"
            case .code: "Code"
            case .chat: "Chat"
            case .document: "Document"
            case .invoice: "Invoice"
            case .chart: "Chart"
            case .diagram: "Diagram"
            case .photo: "Photo"
            case .design: "Design"
            case .other: "Image"
            }
        }
    }

    public var kind: Kind
    public var person: Bool

    public init(kind: Kind, person: Bool) {
        self.kind = kind
        self.person = person
    }

    /// The question names Jev answers, and the image's name in the state.
    public static let kindQuestion = "kind"
    public static let personQuestion = "person"
    public static let imageField = "image"
    public static let kindInstructions = "What kind of picture is `image`?"
    public static let personInstructions = "Is there a person, a face or people in `image`?"

    /// From Jev's answers: the kind it picked when it is fairly sure (else
    /// "other"), a person when likely.
    public init(kind: String?, kindProbability: Double, personProbability: Double?) {
        let picked = kind.flatMap(Kind.init(rawValue:)) ?? .other
        self.kind = kindProbability >= 0.5 ? picked : .other
        person = (personProbability ?? 0) >= 0.6
    }

    /// What SI saw, in one sentence for the clipboard history's preview
    /// ("SI sees an invoice, a receipt or a bill."); nil when it could not
    /// tell (another kind, no one in it).
    public var sentence: String? {
        switch (kind, person) {
        case (.other, false): nil
        case (.other, true): "SI sees a person in it."
        default: "SI sees \(kind.seen)\(person ? ", with a person in it" : "")."
        }
    }

    /// Stored and searched, the kind first: "invoice receipt bill …
    /// facture", "other person people …".
    public var words: String {
        ([kind.rawValue] + kind.words.filter { $0 != kind.rawValue } + (person ? Self.personWords : [])).joined(separator: " ")
    }

    /// Read back from what was stored; nil for anything else.
    public init?(words: String) {
        let list = words.split(separator: " ").map(String.init)
        guard let first = list.first, let kind = Kind(rawValue: first) else { return nil }
        self.kind = kind
        person = list.contains(Self.personWords[0])
    }

    private static let personWords = ["person", "people", "face", "personne", "visage"]
}
