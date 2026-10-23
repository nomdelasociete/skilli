// Requests for the self-tests: compiled only with SKILLI_SELFTEST, never
// in a release (script/release/build.sh checks).
#if SKILLI_SELFTEST
import Foundation

/// Requests labeled with the route Ask should take, in French and English,
/// to measure the route decision on volume rather than on one sentence
/// (`SelfTest.askRoutesOnVolume`). Two halves: `tune` is the half a change
/// to the route question may be looked at against; `holdout` is never
/// tuned on, only counted, and decides whether a change holds.
///
/// Each request has one clear route; requests two routes could fairly
/// take are left out. `item` names what a `command` must pick when it is
/// one of the user's own things: a project, a skillie or a shortcut of
/// the fixture (`SelfTest.volumeFixture`).
struct AskRouteCase: Sendable {
    let text: String
    let route: AskRoute
    var selected = false
    var item: String?

    init(_ text: String, _ route: AskRoute, selected: Bool = false, item: String? = nil) {
        self.text = text
        self.route = route
        self.selected = selected
        self.item = item
    }
}

enum AskRouteCorpus {
    static let tune: [AskRouteCase] = [
        // Timers: a length and nothing to do.
        .init("mets un minuteur de 10 minutes", .timer),
        .init("minuteur 25 minutes pour les pâtes", .timer),
        .init("set a timer for 45 minutes", .timer),
        .init("lance un compte à rebours de 3 minutes", .timer),
        .init("préviens-moi dans 20 minutes", .timer),
        .init("timer 90 seconds", .timer),
        .init("un minuteur d'une heure et demie", .timer),
        .init("sonne dans un quart d'heure", .timer),
        .init("start a 5 minute timer for the tea", .timer),
        .init("minuteur de 8 minutes pour les œufs", .timer),
        .init("countdown 2 minutes", .timer),
        .init("dis-moi quand 40 minutes sont passées", .timer),
        .init("mets un timer de 12 minutes", .timer),
        .init("fais sonner une alarme dans 30 minutes", .timer),
        .init("timer pour la sieste, 20 minutes", .timer),

        // Reminders after a delay: something to do, then the time.
        .init("rappelle-moi dans une heure trente de sortir le linge", .plans),
        .init("rappelle-moi dans 2 heures d'appeler le garage", .plans),
        .init("remind me in 30 minutes to check the oven", .plans),
        .init("rappelle-moi dans 10 minutes de rappeler Sophie", .plans),
        .init("n'oublie pas de me rappeler dans une heure de prendre mes médicaments", .plans),
        .init("remind me in 3 hours to water the plants", .plans),
        .init("dans 45 minutes rappelle-moi d'aller chercher les enfants", .plans),
        // Reminders at a date, a place; to-dos.
        .init("rappelle-moi demain à 8h de sortir les poubelles", .plans),
        .init("remind me on Friday to send the invoice", .plans),
        .init("rappelle-moi ce soir d'acheter du lait", .plans),
        .init("n'oublie pas de payer l'électricité le 15", .plans),
        .init("remind me every Monday to back up my laptop", .plans),
        .init("rappelle-moi de répondre à Julie quand j'arrive au bureau", .plans),
        .init("ajoute acheter des piles à ma liste de courses", .plans),
        .init("add call the dentist to my to-dos", .plans),
        // Events.
        .init("crée un rendez-vous vendredi à 10h chez le dentiste", .plans),
        .init("bloque une heure demain après-midi pour le sport", .plans),
        .init("schedule a meeting with Anna next Tuesday at 3pm", .plans),
        .init("déjeuner avec Marc jeudi midi", .plans),
        .init("ajoute à mon agenda le concert samedi soir", .plans),
        .init("book 30 minutes tomorrow morning to review the budget", .plans),
        // The agenda, read.
        .init("qu'est-ce que j'ai cet après-midi ?", .plans),
        .init("what's on my calendar tomorrow?", .plans),
        .init("c'est quand ma prochaine réunion ?", .plans),
        .init("rejoins mon prochain appel", .plans),
        .init("est-ce que je suis libre vendredi matin ?", .plans),
        .init("am I free on Thursday at 2?", .plans),
        .init("montre mes rappels", .plans),
        .init("what do I have to do today?", .plans),
        .init("quels sont mes rendez-vous de la semaine ?", .plans),
        .init("join the meeting", .plans),

        // Mac commands, keeping the Mac awake for a while among them.
        .init("verrouille l'écran", .command),
        .init("mets le Mac en veille", .command),
        .init("passe en mode sombre", .command),
        .init("garde le Mac éveillé pendant 2 heures", .command),
        .init("empêche la veille jusqu'à 18h", .command),
        .init("keep the mac awake for 45 minutes", .command),
        .init("mets le son à 30 %", .command),
        .init("chanson suivante", .command),
        .init("mets la fenêtre à gauche", .command),
        .init("vide la corbeille", .command),
        .init("quitte Slack", .command),
        .init("force quit Chrome", .command),
        .init("fais une capture de la fenêtre", .command),
        .init("capture d'écran d'une zone", .command),
        .init("il me reste combien de batterie ?", .command),
        .init("teste ma connexion internet", .command),
        .init("ouvre les réglages Bluetooth", .command),
        .init("open the display settings", .command),
        // The user's own projects, skillies and shortcuts.
        .init("ouvre le projet skilli dans cursor", .command, item: "skilli"),
        .init("je veux bosser sur l'api nimbus", .command, item: "nimbus-api"),
        .init("ouvre mon portfolio", .command, item: "portfolio"),
        .init("lance la sauvegarde de mes photos", .command, item: "Backup Photos"),
        .init("relance le wifi", .command, item: "Restart Wi-Fi"),
        .init("lance ma routine du matin", .command, item: "Morning Routine"),
        .init("log water", .command, item: "Log Water"),

        // Apps opened.
        .init("ouvre Safari", .open),
        .init("open Slack", .open),
        .init("lance Spotify", .open),
        .init("ouvre mon appli de dessin vectoriel", .open),
        .init("ouvre la calculette", .open),
        .init("open my mail", .open),
        .init("passe sur Figma", .open),
        .init("ouvre Notes", .open),
        .init("open Xcode", .open),
        .init("ouvre le terminal", .open),
        .init("ouvre Photos", .open),
        .init("lance Zoom", .open),

        // Answers to read.
        .init("c'est quoi un déploiement continu ?", .answer),
        .init("quelle heure est-il à Tokyo ?", .answer),
        .init("combien font 15 % de 240 ?", .answer),
        .init("explain this paragraph", .answer, selected: true),
        .init("résume ce texte", .answer, selected: true),
        .init("que veut dire serendipity ?", .answer),
        .init("who wrote Les Misérables?", .answer),
        .init("quelle est la capitale de l'Australie ?", .answer),
        .init("explique-moi la différence entre TCP et UDP", .answer),
        .init("what does this error mean?", .answer, selected: true),
        .init("c'est quoi ce mot ?", .answer, selected: true),
        .init("donne-moi une idée de dîner rapide", .answer),

        // The selection rewritten.
        .init("corrige les fautes", .rewrite, selected: true),
        .init("make this more formal", .rewrite, selected: true),
        .init("raccourcis ce paragraphe", .rewrite, selected: true),
        .init("rends ce mail plus poli", .rewrite, selected: true),
        .init("fix the grammar", .rewrite, selected: true),
        .init("reformule cette phrase", .rewrite, selected: true),
        .init("mets ça en liste à puces", .rewrite, selected: true),
        .init("rewrite this to sound friendlier", .rewrite, selected: true),
        .init("enlève le jargon", .rewrite, selected: true),
        .init("traduis ce texte en anglais et remplace-le", .rewrite, selected: true),

        // Contacts.
        .init("qui est Paul Durand ?", .contact),
        .init("c'est qui Jean-François de chez Lumière", .contact),
        .init("le numéro de Sophie Martin", .contact),
        .init("what's Anna Keller's email?", .contact),
        .init("écris un mail à François de chez Horizon", .contact),
        .init("envoie un mail à Marie pour lui dire que je serai en retard", .contact),
        .init("l'adresse de Thomas Leroy", .contact),
        .init("who is Mark at Acme?", .contact),

        // In the app in front.
        .init("coche la case newsletter et enregistre", .control),
        .init("clique sur le bouton partager", .control),
        .init("remplis le champ nom avec Jean Dupont", .control),
        .init("exporte en PDF dans mes documents", .control),
        .init("click the Save button", .control),
        .init("active l'interrupteur des notifications dans cette fenêtre", .control),
        .init("écris l'objet puis envoie", .control),
        .init("press the Next button", .control),

        // The agent: connected services, messages, links, several steps.
        .init("dis à Thomas sur Slack que j'ai 5 minutes de retard", .act),
        .init("liste mes déploiements", .act),
        .init("j'ai des taches nimbus deployment en cours ?", .act),
        .init("crée une issue linear pour le bug de connexion", .act),
        .init("ouvre le lien github.com/apple", .act),
        .init("envoie ce fichier à Marc par Messages", .act),
        .init("send a message to the team channel on Slack saying the deploy is done", .act),
        .init("trouve mes issues linear assignées", .act),
        .init("partage cette page avec Julie sur Slack", .act),
        .init("télécharge la facture et envoie-la à la compta", .act),
        // An app named, something else asked of it: not opened.
        .init("mets Chrome comme navigateur par défaut", .act),
        .init("make Safari my default browser", .act),
        .init("fais que les PDF s'ouvrent toujours avec Preview", .act),

        // A menu of the app in front (Finder in the fixture).
        .init("où est le menu pour créer un nouveau dossier ?", .find),
        .init("dans quel menu je trouve Nouvelle fenêtre ?", .find),
        .init("where's the option to show the path bar?", .find),
        .init("affiche la barre latérale", .find),
        .init("which menu has Duplicate?", .find),

        // Again and again, by skil.li.
        .init("tous les lundis à 9h résume mes PR", .schedule),
        .init("every weekday at 8:30 tell me what's on my calendar", .schedule),
        .init("est-ce que tu pourrais me faire un résumé de mes mails chaque soir", .schedule),
        .init("chaque matin donne-moi la météo", .schedule),
        .init("every Friday at 5 list my open linear issues", .schedule)
    ]

    static let holdout: [AskRouteCase] = [
        .init("minuteur 15 min", .timer),
        .init("mets-moi un minuteur de 7 minutes pour le riz", .timer),
        .init("set a 10-minute timer", .timer),
        .init("timer of an hour", .timer),
        .init("compte à rebours de 50 minutes pour la réunion", .timer),
        .init("préviens-moi dans une heure", .timer),
        .init("ring in 25 minutes", .timer),
        .init("lance un minuteur de 4 minutes", .timer),
        .init("un timer de 2 heures", .timer),
        .init("alert me in 15 minutes", .timer),
        .init("minuteur pomodoro de 25 minutes", .timer),
        .init("dans 6 minutes fais sonner", .timer),
        .init("timer for the pizza, 12 minutes", .timer),
        .init("mets un minuteur d'une minute trente", .timer),
        .init("start a countdown of 3 minutes", .timer),

        .init("rappelle-moi dans 20 minutes de vérifier le four", .plans),
        .init("remind me in an hour to call mom", .plans),
        .init("dans deux heures rappelle-moi d'envoyer le devis", .plans),
        .init("rappelle-moi dans 5 minutes de rebrancher le chargeur", .plans),
        .init("remind me in 15 minutes to stretch", .plans),
        .init("rappelle-moi dans une demi-heure de relancer Paul", .plans),
        .init("rappelle-moi lundi de renouveler mon passeport", .plans),
        .init("remind me tomorrow at noon to book the flights", .plans),
        .init("rappelle-moi samedi matin de laver la voiture", .plans),
        .init("n'oublie pas l'anniversaire de Léa le 3 mars", .plans),
        .init("rappelle-moi tous les soirs de prendre ma vitamine", .plans),
        .init("remind me when I leave home to take the keys", .plans),
        .init("ajoute du café à la liste des courses", .plans),
        .init("put renew insurance on my to-do list", .plans),
        .init("crée un événement mardi 9h réunion d'équipe", .plans),
        .init("bloque mon vendredi après-midi", .plans),
        .init("set up a call with Tom on Monday at 11", .plans),
        .init("dîner chez mes parents dimanche à 19h", .plans),
        .init("ajoute un rdv chez le médecin le 12 à 16h30", .plans),
        .init("reserve two hours on Wednesday for deep work", .plans),
        .init("qu'est-ce que j'ai demain matin ?", .plans),
        .init("what's my next meeting?", .plans),
        .init("j'ai quoi aujourd'hui ?", .plans),
        .init("rejoins la réunion de 14h", .plans),
        .init("suis-je dispo lundi après-midi ?", .plans),
        .init("when am I free this week?", .plans),
        .init("mes tâches du jour dans Rappels", .plans),
        .init("show me my reminders", .plans),
        .init("est-ce que j'ai des réunions vendredi ?", .plans),
        .init("connect me to my next call", .plans),

        .init("lock my screen", .command),
        .init("éteins le Mac", .command),
        .init("switch to light mode", .command),
        .init("ne mets pas le Mac en veille pendant une heure", .command),
        .init("keep awake until 6pm", .command),
        .init("monte le son", .command),
        .init("pause la musique", .command),
        .init("maximize the window", .command),
        .init("move this window to the other screen", .command),
        .init("empty the trash", .command),
        .init("quitte Zoom", .command),
        .init("désinstalle Spotify", .command),
        .init("capture tout l'écran", .command),
        .init("copie le texte de cette zone de l'écran", .command),
        .init("quelle est mon adresse IP ?", .command),
        .init("éjecte les disques", .command),
        .init("ouvre les réglages de l'écran", .command),
        .init("open wifi settings", .command),
        .init("ouvre nimbus-web", .command, item: "nimbus-web"),
        .init("work on my dotfiles", .command, item: "dotfiles"),
        .init("open the portfolio project", .command, item: "portfolio"),
        .init("mets le site en ligne", .command, item: "Deploy Website"),
        .init("vide le cache DNS", .command, item: "Clear DNS Cache"),
        .init("démarre une session focus", .command, item: "Start Focus Session"),
        .init("envoie mon heure d'arrivée", .command, item: "Envoyer mon heure d'arrivée"),

        .init("ouvre Mail", .open),
        .init("open Spotify", .open),
        .init("lance Notion", .open),
        .init("open the calculator", .open),
        .init("ouvre mon éditeur de code", .open),
        .init("ouvre Calendrier", .open),
        .init("switch to Messages", .open),
        .init("ouvre Keynote", .open),
        .init("open Preview", .open),
        .init("ouvre les Réglages Système", .open),
        .init("lance 1Password", .open),
        .init("open Obsidian", .open),

        .init("c'est quoi la photosynthèse ?", .answer),
        .init("how far is the moon?", .answer),
        .init("résume-moi ce passage", .answer, selected: true),
        .init("explique ce code", .answer, selected: true),
        .init("qu'est-ce que ça veut dire ?", .answer, selected: true),
        .init("define ephemeral", .answer),
        .init("quand a été construite la tour Eiffel ?", .answer),
        .init("how many ounces in a pound?", .answer),
        .init("pourquoi le ciel est bleu ?", .answer),
        .init("what is the main point here?", .answer, selected: true),
        .init("comment on dit merci en japonais ?", .answer),
        .init("give me three ideas for a birthday gift", .answer),

        .init("corrige l'orthographe", .rewrite, selected: true),
        .init("shorten this", .rewrite, selected: true),
        .init("rends ce texte plus direct", .rewrite, selected: true),
        .init("replace this with a French translation", .rewrite, selected: true),
        .init("mets tout en majuscules", .rewrite, selected: true),
        .init("rewrite this as a tweet", .rewrite, selected: true),
        .init("améliore ce paragraphe", .rewrite, selected: true),
        .init("simplifie ce texte", .rewrite, selected: true),
        .init("make it more concise", .rewrite, selected: true),
        .init("mets ce texte au vouvoiement", .rewrite, selected: true),

        .init("qui c'est Claire Dubois ?", .contact),
        .init("donne-moi le téléphone de Lucas Bernard", .contact),
        .init("email Tom Becker about the contract", .contact),
        .init("crée un mail pour Julien", .contact),
        .init("c'est quoi l'adresse mail de Nadia ?", .contact),
        .init("who is Sarah Chen", .contact),
        .init("écris à Pierre pour décaler la réunion", .contact),
        .init("find John Smith's phone number", .contact),

        .init("enregistre ce document en PDF sur le bureau", .control),
        .init("click on the Settings tab", .control),
        .init("tick the remember me box", .control),
        .init("remplis le champ email avec jean@example.com", .control),
        .init("appuie sur le bouton suivant", .control),
        .init("save this as a PDF in Downloads", .control),
        .init("sélectionne l'onglet Général", .control),
        .init("turn on the dark theme switch in this window", .control),

        .init("show my open linear issues", .act),
        .init("quel est le statut du dernier déploiement ?", .act),
        .init("create a task in nimbus to update the docs", .act),
        .init("message Léa on WhatsApp that I'm on my way", .act),
        .init("go to apple.com", .act),
        .init("share this file with Paul on Slack", .act),
        .init("liste les milestones nimbus", .act),
        .init("poste sur Slack que la release est sortie", .act),
        .init("envoie un SMS à maman pour lui dire que j'arrive", .act),
        .init("cherche le dernier mail de la banque et transfère-le à mon comptable", .act),
        .init("change default browser to Arc", .act),
        .init("définis Google Chrome comme navigateur par défaut", .act),
        .init("use TextEdit as the default app for text files", .act),

        .init("où se trouve l'option pour afficher la barre d'état ?", .find),
        .init("in which menu is Print?", .find),
        .init("show the toolbar", .find),
        .init("où est Aller au dossier ?", .find),
        .init("where do I rename this file in the menus?", .find),

        .init("tous les jours à 18h fais le point sur mes déploiements", .schedule),
        .init("each morning at 9 summarize my unread mails", .schedule),
        .init("chaque lundi envoie-moi mes tâches de la semaine", .schedule),
        .init("every hour check if the website is up", .schedule),
        .init("tous les soirs à 22h résume ma journée", .schedule)
    ]
}
#endif
