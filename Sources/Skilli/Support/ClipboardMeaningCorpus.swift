// Copies and requests for the self-tests: compiled only with
// SKILLI_SELFTEST, never in a release (script/release/build.sh checks).
#if SKILLI_SELFTEST
import Foundation

/// One copy of the scratch history the clipboard is searched in by
/// meaning (`SelfTest.clipboardMeaningOnVolume`), `hours` before now.
struct ClipboardMeaningCopy: Sendable {
    let key: String
    let kind: ClipboardStore.Item.Kind
    let text: String
    let app: String
    let hours: Double
    var ocr: String?

    init(_ key: String, _ kind: ClipboardStore.Item.Kind, _ text: String, _ app: String, _ hours: Double, ocr: String? = nil) {
        self.key = key
        self.kind = kind
        self.text = text
        self.app = app
        self.hours = hours
        self.ocr = ocr
    }

    init(_ key: String, _ text: String, _ app: String, _ hours: Double) {
        self.init(key, .text, text, app, hours)
    }
}

/// A request and the copies it is after: `wanted` are the copies that
/// must come up (the first result one of them, or one of `fits`, which
/// answer it too without being asked for).
struct ClipboardMeaningCase: Sendable {
    let request: String
    let wanted: [String]
    var fits: [String] = []

    init(_ request: String, _ wanted: [String], fits: [String] = []) {
        self.request = request
        self.wanted = wanted
        self.fits = fits
    }
}

/// The clipboard searched by meaning on volume rather than on one
/// sentence: requests for a kind of copy ("email", "un lien", "the hex
/// color") and for what a copy was about, in French and English, among
/// ~110 copies. Two halves, as `AskRouteCorpus`: `tune` may be looked at
/// when a change to the descriptions or the question is made; `holdout`
/// is only counted, and decides whether the change holds.
enum ClipboardMeaningCorpus {
    static let emails = ["email.camille", "email.margot", "email.jf", "email.support", "email.mailto"]
    static let links = ["link.figma", "link.doc", "link.github", "link.youtube", "link.www"]
    static let phones = ["phone.mobile", "phone.office", "phone.us"]
    static let colors = ["color.hex", "color.rgb"]
    static let addresses = ["address.paris", "address.cupertino"]
    static let code = ["code.swift", "code.sql", "code.shell", "code.python"]

    static let copies: [ClipboardMeaningCopy] = values + about + filler

    /// Copies that are one value, whole.
    static let values: [ClipboardMeaningCopy] = [
        .init("email.camille", "camille.roux@example.com", "Mail", 2),
        .init("email.margot", "margot.martin@example.org", "Front", 26),
        .init("email.jf", "jf.martaing@example.net", "Slack", 50),
        .init("email.support", "support@nimbus.example", "Arc", 120),
        .init("email.mailto", "mailto:compta@example.fr", "Safari", 200),
        .init("link.figma", "https://www.figma.com/file/abc123/Onboarding", "Figma", 5),
        .init("link.doc", "https://docs.google.com/document/d/1x2y3z/edit", "Arc", 30),
        .init("link.github", "https://github.com/example/nimbus/pull/42", "Safari", 9),
        .init("link.youtube", "https://www.youtube.com/watch?v=aB3dEf9hIjK", "Messages", 75),
        .init("link.www", "www.example.com/tarifs", "Notes", 140),
        .init("phone.mobile", "06 12 34 56 78", "Contacts", 12),
        .init("phone.office", "+33 1 42 68 53 00", "Mail", 60),
        .init("phone.us", "(415) 555-0132", "Safari", 170),
        .init("color.hex", "#3E8E7E", "Figma", 15),
        .init("color.rgb", "rgb(255, 99, 71)", "Safari", 90),
        .init("address.paris", "12 rue des Lilas, 75011 Paris", "Messages", 40),
        .init("address.cupertino", "1 Infinite Loop, Cupertino, CA 95014", "Maps", 110),
        .init("code.swift", "guard let url = URL(string: text) else { return nil }\nlet request = URLRequest(url: url)", "Xcode", 3),
        .init("code.sql", "SELECT id, email FROM users WHERE created_at > '2026-10-01';", "TablePlus", 22),
        .init("code.shell", "#!/bin/bash\nset -e\nnpm run build\nrsync -av dist/ deploy@web:/var/www/", "Terminal", 55),
        .init("code.python", "def total(items):\n    return sum(item.price for item in items)", "Cursor", 95)
    ]

    /// Copies about something, some with a value inside a sentence.
    static let about: [ClipboardMeaningCopy] = [
        .init("bill", "EDF — Facture d'octobre 2026 : 82,40 € à régler avant le 25/10. Référence client 4002 118 230", "Mail", 46),
        .init("ticket", .image, "", "CleanShot X", 20, ocr: "SNCF e-billet\nParis Gare de Lyon → Lyon Part-Dieu\nDépart 14:05 · Voiture 12 · Place 47"),
        .init("digicode", "c'est au 8 rue Oberkampf, digicode 4B21, 3e étage gauche, sonne chez Roux", "Messages", 70),
        .init("payout", .image, "", "Screenshots", 33, ocr: "Stripe Dashboard\nPayout failed\nYour bank declined the transfer of 1 240,00 € on Oct 14"),
        .init("quote", "Bonjour Camille, je te renvoie le devis signé en pièce jointe. On se cale un appel jeudi ? Bonne journée, Margot", "Mail", 6),
        .init("plumber", "Rappelle le plombier au 06 98 76 54 32 avant midi", "Messages", 28),
        .init("replay", "Le replay est ici https://example.com/replay/42, mot de passe dans le coffre", "Slack", 18),
        .init("write.jf", "Tu peux écrire à jf.martaing@example.net, il répond vite", "Slack", 35),
        .init("contact.card", .image, "", "CleanShot X", 48, ocr: "Camille Roux\nResponsable produit\ncamille.roux@example.com\n06 12 34 56 78"),
        .init("broken.links", "Les liens du site sont cassés depuis la mise en prod", "Slack", 44),
        .init("phone.broken", "Mon téléphone est en panne, écris-moi plutôt", "Messages", 66),
        .init("green", "On garde le vert de la charte, pas le bleu", "Slack", 80),
        .init("pasta", "200 g de farine, 3 œufs, 50 cl de lait, une pincée de sel", "Notes", 100),
        .init("flight", "Vol AF1234 Paris CDG → Lisbonne, vendredi 7h40, terminal 2F", "Mail", 130),
        .init("invoice.files", .files, "/Users/me/Documents/Facture-2026-10.pdf\n/Users/me/Documents/Devis-Nimbus.pdf", "Finder", 58)
    ]

    /// Everything else a history holds: chat, notes, numbers, words.
    static let filler: [ClipboardMeaningCopy] = [
        "OK pour moi, on fait comme ça", "merci beaucoup !", "Lorem ipsum dolor sit amet", "La réunion est décalée à 15h",
        "Bon anniversaire Léa !", "Paris, 11 octobre 2026", "Ne pas oublier les clés du local", "Merci pour ton retour rapide",
        "v2.4.1 release notes", "À demain !", "Super, je regarde ça ce soir", "Total TTC : 1 450,00 €", "Réf. commande 88-2041-77",
        "on se retrouve devant la gare", "Je suis en retard de 10 minutes, désolé", "Projet Nimbus — point hebdo", "Sprint 42 : 18 points",
        "Can you review this before Friday?", "Thanks, that works for me", "Let's push the launch to next week", "Agenda: budget, hiring, roadmap",
        "Quarterly numbers look good", "Done ✅", "Je te laisse valider", "C'est noté", "Ça marche, à lundi", "mot de passe changé hier",
        "Liste : pain, beurre, tomates, café", "Chapitre 3 — La traversée", "TODO: relire l'intro", "Combien pour la livraison ?",
        "Le colis arrive mardi", "Taille M, couleur sable", "Rendez-vous chez le dentiste jeudi", "Mercredi 9h, salle Bleue",
        "Bravo à toute l'équipe", "Je suis malade aujourd'hui", "Cette semaine : 3 démos clients", "Je prends le train de 18h",
        "Le wifi du bureau est lent", "Penser à renouveler l'assurance", "On a dépassé le budget de 12 %", "J'arrive dans 5 min",
        "I'll send the slides tonight", "Meeting notes: ship the beta, then fix onboarding", "Le loyer passe à 1 180 €",
        "Version 3 validée par le client", "Ils veulent une démo la semaine prochaine", "Pas de réunion demain", "tracking: 1Z999AA10123456784",
        "Numéro de commande : 4412", "La clim ne marche plus au 2e", "Cool, merci !", "Il pleut encore", "Prochaine étape : le contrat"
    ].enumerated().map { index, text in
        let apps = ["Slack", "Messages", "Notes", "Mail", "Pages", "Reminders", "WhatsApp", "Calendar"]
        return ClipboardMeaningCopy("filler.\(index)", text, apps[index % apps.count], Double(index) * 3.7 + 1)
    }

    static let tune: [ClipboardMeaningCase] = [
        // A kind of copy, nothing else.
        .init("email", emails, fits: ["write.jf", "contact.card"]),
        .init("adresse mail", emails, fits: ["write.jf", "contact.card"]),
        .init("lien", links, fits: ["replay"]),
        .init("url", links, fits: ["replay"]),
        .init("numéro de téléphone", phones, fits: ["plumber", "contact.card"]),
        .init("hex color", colors),
        .init("postal address", addresses, fits: ["digicode"]),
        .init("bout de code", code),
        // A kind, and which one.
        .init("l'adresse mail de Margot", ["email.margot"]),
        .init("the email address I copied from Slack", ["email.jf"], fits: ["write.jf"]),
        .init("le lien github", ["link.github"]),
        .init("the youtube link", ["link.youtube"]),
        .init("le numéro américain", ["phone.us"]),
        .init("the SQL query", ["code.sql"]),
        .init("l'adresse à Cupertino", ["address.cupertino"]),
        // What it was about.
        .init("la facture d'électricité", ["bill"]),
        .init("le billet de train", ["ticket"]),
        .init("le message de Margot sur le devis", ["quote"]),
        .init("le numéro du plombier", ["plumber"]),
        .init("la recette des crêpes", ["pasta"])
    ]

    static let holdout: [ClipboardMeaningCase] = [
        // A kind of copy, nothing else.
        .init("e-mail address", emails, fits: ["write.jf", "contact.card"]),
        .init("mail", emails, fits: ["write.jf", "contact.card", "quote"]),
        .init("link", links, fits: ["replay"]),
        .init("phone number", phones, fits: ["plumber", "contact.card"]),
        .init("couleur", colors),
        .init("code snippet", code),
        .init("téléphone", phones, fits: ["plumber", "contact.card"]),
        .init("adresse postale", addresses, fits: ["digicode"]),
        // A kind, and which one.
        .init("l'email du support", ["email.support"]),
        .init("le lien figma", ["link.figma"]),
        .init("the google doc link", ["link.doc"]),
        .init("le numéro du bureau", ["phone.office"]),
        .init("le script shell", ["code.shell"]),
        .init("the python function", ["code.python"]),
        .init("la couleur en rgb", ["color.rgb"]),
        // What it was about.
        .init("the screenshot where the payout failed", ["payout"]),
        .init("l'adresse de l'appart avec le digicode", ["digicode"]),
        .init("le lien du replay", ["replay"]),
        .init("mon vol pour Lisbonne", ["flight"]),
        .init("les PDF de factures", ["invoice.files"])
    ]
}
#endif
