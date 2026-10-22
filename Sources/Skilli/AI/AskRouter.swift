import Foundation
import SkilliCore

/// What Ask does with what the user typed.
enum AskRoute: String, CaseIterable, Sendable {
    /// Answer in the card: explain, summarize, translate to read, a question.
    case answer
    /// Change the selected text in place: fix, shorten, rewrite.
    case rewrite
    /// Find a feature of the app in front in its menus, to show or choose it.
    case find
    /// Open one of the apps installed on this Mac.
    case open
    /// Run a Mac command: lock, sleep, dark mode, keep awake, Trash…
    case command
    /// Start a countdown: "mets un minuteur de dix minutes pour les pâtes"
    /// (its length and what it is for read by the model, `AskValues`).
    case timer
    /// Their Calendar and Reminders: add a reminder or an event, the day's
    /// agenda, the next meeting, free time, the to-dos (what and every
    /// value read by the model, `AskValues.plan`).
    case plans
    /// One of their contacts: who they are, or a mail to write them (the
    /// person and what is asked read by the model, `AskValues.contact`).
    case contact
    /// Do it in the window in front: press, tick, fill what it shows, a
    /// few steps in that app (`ComputerControl`).
    case control
    /// Do something else: a reminder, a message, another app, several steps.
    case act
    /// Do it later, again and again: "every Monday at 9 sum up my PRs"
    /// (`AskSchedule`, kept by `AskScheduler`). Not an option of the route
    /// question: a question of its own, asked only when the request says
    /// "every", "chaque"… (`scheduleQuestion`).
    case schedule

    /// What the card offers when Ask is unsure.
    var choice: String {
        switch self {
        case .answer: "Answer here"
        case .rewrite: "Rewrite the selection"
        case .find: "Find it in the menus"
        case .open: "Open an app"
        case .command: "Run a Mac command"
        case .timer: "Start a timer"
        case .plans: "Use Calendar or Reminders"
        case .contact: "Find the contact"
        case .control: "Do it in this app"
        case .act: "Do it with tools"
        case .schedule: "Do it on a schedule"
        }
    }

    var title: String {
        switch self {
        case .answer: "Answer"
        case .rewrite: "Rewrite"
        case .find: "Found"
        case .open: "Open"
        case .command: "Done"
        case .timer: "Timer"
        case .plans: "Calendar"
        case .contact: "Contact"
        case .control: "Doing"
        case .act: "Act"
        case .schedule: "Scheduled"
        }
    }
}

/// Picks Ask's route in one typed decision (~0.3 s) with the user's
/// decision key (TypeSafe Jev, then OpenAI Decisions). Only the instruction,
/// whether something is selected, the app's name and the connected
/// services' and their tools' names are sent, never the selection.
@MainActor
enum AskRouter {
    static let question = DecisionQuestion(
        name: "route",
        instructions: "The user typed a request to skil.li, an assistant in their Mac apps (they may have selected text). What should skil.li do?",
        options: [
            .init(value: AskRoute.answer.rawValue,
                  description: "Reply in words for them to read: explain or summarize the selected text, translate it to read, define a word, answer a general knowledge question. Not about finding or using something in their apps, nor about their own things in a connected service"),
            .init(value: AskRoute.rewrite.rawValue,
                  description: "Change the selected text itself and put it back: fix it, rewrite, shorten, make it more formal, translate it in place"),
            .init(value: AskRoute.find.rawValue,
                  description: "Find where one feature of the app they are in is in its menus (where is…, which menu…), or run one menu command that does everything by itself: show the sidebar, a new window, zoom in, check for updates of this app"),
            .init(value: AskRoute.open.rawValue,
                  description: "Open or switch to one app installed on their Mac, named or described by what it does: my vector drawing app, my mail, the calculator"),
            .init(value: AskRoute.command.rawValue,
                  description: "A Mac command: lock the screen, sleep, dark or light mode, keep the Mac awake (for a while, until a time), show the desktop (montre le bureau), show hidden files, eject disks, empty the Trash, restart, shut down; music and sound (play, pause, next song, louder, mute, the volume at a level); test the internet speed; pick a color on screen; paste their latest screenshot; battery, disk, memory or IP; turn the keyboard off to clean it; or put the front window somewhere: left or right half, full, center, the other display; or play the sound through other speakers, headphones, AirPods or the display, or switch the microphone; or quit, force quit or uninstall an app they name (kill creative cloud, désinstalle Slack); or open one of their recent code projects in its editor (Cursor, VS Code, Zed…); or run one of their own commands (skillies) by its name or what it does; or take a screenshot or a screen recording with CleanShot X (an area, the window in front, the whole screen, a scrolling page), read the text in an area, annotate or pin their latest screenshot, hide the desktop icons"),
            .init(value: AskRoute.timer.rawValue,
                  description: "Start a timer: a countdown that rings when the time is up. The request gives only a length or an end time, and at most what the countdown is for (the pasta, a nap), nothing to do or remember (un minuteur de dix minutes, timer for an hour and a half, préviens-moi dans 20 minutes). As soon as it says something to do or remember, even after a delay, it is a reminder, not a timer (rappelle-moi dans 20 minutes d'appeler Paul, remind me in 2 hours to pick up the parcel). Not keeping the Mac awake for a while or until a time (pas de veille jusqu'à 18h30)"),
            .init(value: AskRoute.plans.rawValue,
                  description: "Their Calendar and Reminders on this Mac: add a reminder, something to do or remember, with or without a date, a time, a delay or a place (rappelle-moi d'appeler Paul demain, rappelle-moi dans 20 minutes d'appeler Paul, remind me to buy bread, n'oublie pas de…), or a to-do; add an event (rdv demain 14h avec Paul, bloque 2h demain matin); or tell them what is in them (qu'est-ce que j'ai demain, ma prochaine réunion, rejoins la réunion, suis-je libre jeudi, mes dispos, mes rappels). Not tasks or issues in a connected service, not a countdown with nothing to do (un minuteur de dix minutes)"),
            .init(value: AskRoute.contact.rawValue,
                  description: "Someone they may know, named: who they are, their number, email or address (qui est Paul Durand, c'est qui Jean-François de chez Lumière, le numéro de Paul), or write an email to them (crée un mail à François de chez Horizon, écris à Paul pour lui dire que…). Their contacts are looked in first. Not a message on Slack or another app"),
            .init(value: AskRoute.control.rawValue,
                  description: "Do it in the app in front, through its menus and what its window shows, when it takes steps or a choice: export or save as PDF into a folder, save it somewhere, click a button, a link or a tab, tick a box, turn a switch on, fill a field or a form, write the subject then send"),
            .init(value: AskRoute.act.rawValue,
                  description: "Look something up in, or do something with, one of their connected services (listed with the request: their tasks, deployments, issues, pages…); or do something else on their Mac: send or share something, message someone, open a link, several steps, use one of their tools")
        ]
    )

    /// The command question's option for a volume level said: the level
    /// itself is read afterwards (`values`), `.volume(levelToRead)` until then.
    static let volumeLevel = "volumeLevel"
    static let levelToRead = -1

    /// Options of the command question done to an app the request names
    /// ("kill creative cloud", "désinstalle Slack"): the name is read
    /// afterwards (`AskValues.target`).
    enum AppAction: String, CaseIterable, Sendable {
        case quit = "appQuit"
        case forceQuit = "appForceQuit"
        case uninstall = "appUninstall"

        var description: String {
            switch self {
            case .quit: "Quit or kill an app or program they name, with its helpers: quitte Slack, kill creative cloud, tue Teams, ferme complètement Chrome"
            case .forceQuit: "Force quit an app they name: quitte de force Teams, force quit Chrome"
            case .uninstall: "Uninstall an app they name, with what it leaves behind: désinstalle Slack, uninstall Figma, supprime l'app Zoom"
            }
        }
    }

    /// The values a decided route acts with (`AskValues`: where, who, when
    /// it repeats), read by the model in one more request sent only when
    /// the route needs one: the parts it picked and how sure of each. A
    /// timer's, the volume's and Keep Awake's come with the route
    /// (`speculativeValues`). Nil without a key, or when every provider
    /// failed.
    static func values(_ questions: [AskValues.Question], instruction: String,
                       keys: [DecisionProvider: String]) async -> [String: AskValues.Answer]? {
        let asked = questions.map { question in
            DecisionQuestion(name: question.name, instructions: question.instructions,
                             options: question.options.map { .init(value: $0.value, description: $0.description) })
        }
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            do {
                let start = ContinuousClock.now
                let answers = try await DecisionClient.decide(asked, input: "Request: \(instruction)", provider: provider, key: key)
                Log.trace("Ask values “\(instruction)” in \((ContinuousClock.now - start).compact): "
                          + answers.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.choice) \(Int($0.value.confidence * 100))%" }.joined(separator: ", "))
                return answers.mapValues { AskValues.Answer(choice: $0.choice, confidence: $0.confidence) }
            } catch {
                Log.actions.error("Ask values by \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    /// Asked only when the request says "every", "chaque", "tous les"…
    /// (`AskSchedule.mentionsRepeat`): an option of the route question
    /// moved OpenAI's routes of other requests (System Settings' panes went
    /// to "do it here"); a question of its own leaves them as they were.
    static let scheduleQuestion = DecisionQuestion(
        name: "schedule",
        instructions: "Does the user ask skil.li itself to do this later, again and again, at times they give (every Monday at 9 sum up my PRs, each morning tell me my day, every weekday at 8:30 check…), rather than now? A reminder to themselves (rappelle-moi…, n'oublie pas de payer le loyer le 5 de chaque mois, remind me every Monday to…) or a calendar event is not, even when it repeats; nor a question about their agenda.",
        options: [
            .init(value: "yes", description: "skil.li runs the request again and again at those times"),
            .init(value: "no", description: "Do it now, or it is a reminder or an event for themselves (even a repeating one), or a question")
        ]
    )

    /// Wi-Fi turned off or its pane opened, AirPods connected or Bluetooth's
    /// pane: "open the wifi settings" is the pane, "coupe le wifi" is done.
    /// Read by the model (a list of settings words once decided it).
    static let opensSettings = DecisionQuestion(
        name: "opens_settings",
        instructions: "Does the user ask to open a settings pane (open the Wi-Fi settings, les réglages Bluetooth, les paramètres de l'écran), rather than to do something (turn Wi-Fi off, connect my AirPods, passe en mode sombre)?",
        options: [
            .init(value: "yes", description: "Open a settings pane"),
            .init(value: "no", description: "Do something, or anything else")
        ]
    )

    /// What Ask decided, in one request.
    struct Decision {
        let route: AskRoute
        let confidence: Double
        /// For `find`: the menu items that fit best, best first.
        let menu: [(item: MenuReader.Item, probability: Double)]
        /// For `open`: the installed apps that fit best, best first.
        var apps: [(app: AppCandidates.App, probability: Double)] = []
        /// Every route with its probability, best first.
        var routes: [(route: AskRoute, probability: Double)] = []
        /// For `command`: the Mac command, if one fits.
        var command: (command: MacAction, probability: Double)?
        /// The likeliest Mac commands (10 % and up, best first): the card
        /// offers them when the one picked is under 50 %.
        var commands: [(command: MacAction, probability: Double)] = []
        /// For `command`: done to an app the request names, when that is
        /// the command question's answer (from 50 %).
        var appAction: AppAction?
        /// "Jev · 0.27 s".
        let label: String
        /// Connected services the request names ("nimbus-deployment"):
        /// another route than the agent's is then put to the user.
        var services: [String] = []
        /// How long, until when, how loud and what for, read in the same
        /// request (`speculativeValues`): a timer, the volume or Keep Awake
        /// act on them without a second request.
        var values: [String: AskValues.Answer] = [:]
    }

    /// The values a timer, the volume or Keep Awake act with, asked with
    /// the route (D8, 2026-10-17: one request, more tokens; plans and
    /// the rest keep their second request).
    static func speculativeValues(_ instruction: String) -> [AskValues.Question] {
        AskValues.durationQuestions + AskValues.levelQuestions + [AskValues.labelQuestion(spans: AskValues.spans(of: instruction))]
    }

    /// A route this likely (its probability, not the answer's confidence)
    /// is sure of itself: what another question read (an app named, a
    /// quit) does not move it.
    static let sureRoute = 0.8

    /// Two routes this close are a close call (Decisions on "rappelle-moi
    /// dans une heure trente de sortir le linge": timer 51 %, plans 41 %).
    static let closeCall = 0.15

    /// The route answer, or, on a close call, the two likeliest routes
    /// asked again alone, eleven options down to two: one more request,
    /// for close calls only. Their shared probability is split as the
    /// second answer says (its probabilities: on two options both engines'
    /// confidence is the lead over the other, 51 / 49 → 2 %); the other
    /// routes keep theirs. The first answer when the second fails.
    private static func settled(_ routed: DecisionResult, instruction: String, input: String, provider: DecisionProvider,
                                key: String) async -> DecisionResult {
        let ranked = routed.probabilities.sorted { $0.value > $1.value }
        guard ranked.count >= 2, ranked[0].value - ranked[1].value < closeCall else { return routed }
        let pair = [ranked[0].key, ranked[1].key]
        let options = question.options.filter { pair.contains($0.value) }
        guard options.count == 2 else { return routed }
        let narrow = DecisionQuestion(name: question.name,
                                      instructions: question.instructions + " It is one of these two: which one does the request ask for?",
                                      options: options)
        guard let answer = try? await DecisionClient.decide(narrow, input: input, provider: provider, key: key) else { return routed }
        let shared = ranked[0].value + ranked[1].value
        var probabilities = routed.probabilities
        for value in pair {
            probabilities[value] = shared * (answer.probabilities[value] ?? (answer.choice == value ? 1 : 0))
        }
        let confidence = probabilities[answer.choice] ?? answer.confidence
        Log.trace("Ask close call by \(provider.rawValue) “\(instruction)”: \(pair[0]) \(Int(ranked[0].value * 100))%, \(pair[1]) \(Int(ranked[1].value * 100))% → "
                  + "\(answer.choice) \(Int(answer.confidence * 100))% [" + pair.map { "\($0) \(Int((answer.probabilities[$0] ?? -1) * 100))" }.joined(separator: ", ") + "]")
        return DecisionResult(choice: answer.choice, confidence: confidence, probabilities: probabilities)
    }

    /// The route and who picked it ("Jev · 0.27 s"); nil without a decision
    /// key, or when every provider failed.
    static func route(_ instruction: String, hasSelection: Bool, ai: AIStore) async -> (route: AskRoute, label: String)? {
        await decide(instruction, hasSelection: hasSelection, app: "", menu: [], apps: [], keys: keys(ai)).map { ($0.route, $0.label) }
    }

    static func route(_ instruction: String, hasSelection: Bool, keys: [DecisionProvider: String]) async -> (route: AskRoute, label: String)? {
        await decide(instruction, hasSelection: hasSelection, app: "", menu: [], apps: [], keys: keys).map { ($0.route, $0.label) }
    }

    static func keys(_ ai: AIStore) -> [DecisionProvider: String] {
        var keys: [DecisionProvider: String] = [:]
        for provider in DecisionProvider.allCases { keys[provider] = ai.decisionKey(for: provider) }
        return keys
    }

    /// The route and, speculatively, the menu item: the menu's questions
    /// ride in the same request (answered in parallel, ~no extra time), so
    /// "find" costs nothing more. Menu items are only the app's own
    /// commands (`MenuCandidates.isShareable`), never the selection.
    /// `services`: the connected MCP servers the agent can use, with their
    /// tools' names; only those names are sent, with the request.
    static func decide(_ instruction: String, hasSelection: Bool, app: String, menu: [MenuReader.Item],
                       apps: [AppCandidates.App] = [], projects: [EditorProject] = [], scripts: [ScriptCommand] = [],
                       shortcuts: [AppleShortcut] = [],
                       settings: [SystemSettingsPane] = [],
                       bluetooth: [MacAction] = [],
                       services: [(name: String, tools: [String])] = [],
                       keys: [DecisionProvider: String]) async -> Decision? {
        var input = "Request: \(instruction)\nSelected text: \(hasSelection ? "yes" : "no")"
        if !app.isEmpty { input += "\nApp in front: \(app)" }
        // The services, and what the request says of them: a name said is
        // weighed by the model and, if it goes elsewhere, put to the user.
        let named = ServiceMention.named(in: instruction, services: services.map(\.name))
        if !services.isEmpty {
            input += "\n" + ServiceMention.describe(services)
            if !named.isEmpty { input += "\nThe request names the connected service \(named.joined(separator: ", "))." }
            let hinted = services.compactMap { service -> String? in
                let words = ServiceMention.toolWords(in: instruction, tools: service.tools)
                return words.isEmpty || named.contains(service.name) ? nil : "\(service.name) (\(words.joined(separator: ", ")))"
            }
            if !hinted.isEmpty { input += "\nWords of the request match tools of: \(hinted.joined(separator: "; "))." }
        }
        // The user's own things the request names whole ("ouvre mon
        // portfolio": the project, 21 % for Decisions when not told): told,
        // as services are; the questions still decide.
        let said = [("recent project", ServiceMention.said(in: instruction, names: projects.prefix(40).map(\.name))),
                    ("command (skillie)", ServiceMention.said(in: instruction, names: scripts.prefix(60).map(\.title))),
                    ("shortcut", ServiceMention.said(in: instruction, names: shortcuts.map(\.name)))]
        for (kind, names) in said where !names.isEmpty {
            input += "\nThe request says the name of the user's \(kind) " + names.map { "“\($0)”" }.joined(separator: ", ") + "."
        }
        let chunks = MenuCandidates.chunks(menu)
        var questions = [question, opensSettings]
        let values = speculativeValues(instruction)
        questions += values.map { value in
            DecisionQuestion(name: value.name, instructions: value.instructions,
                             options: value.options.map { .init(value: $0.value, description: $0.description) })
        }
        let mentionsRepeat = AskSchedule.mentionsRepeat(instruction)
        if mentionsRepeat { questions.append(scheduleQuestion) }
        // Sound devices by position: their ids ("BuiltInSpeakerDevice")
        // read as words and pulled every "son" toward the speakers.
        let sounds = MacAction.sounds()
        // Bluetooth devices by position too, each both ways: "connecte mes
        // AirPods" asked when they are already connected says so.
        let radios = bluetooth.flatMap { action -> [MacAction] in
            guard case .bluetooth(let target, _) = action else { return [] }
            return [.bluetooth(target, connect: true), .bluetooth(target, connect: false)]
        }
        questions.append(DecisionQuestion(
            name: "command",
            instructions: "Which Mac command, window placement, sound device or app command (CleanShot X's screenshots, recordings, text recognition) does the user ask for? A sound device is where the sound plays, named or described: a screen or TV (l'écran, la télé) plays through its own speakers. Answer none when it is not one of these.",
            options: (MacAction.all + MacAction.appLinks()).map { .init(value: $0.rawValue, description: $0.description) }
                + [.init(value: volumeLevel, description: "Set the sound's volume to a level they say, also when they turn it up or down to a level: le son à 30 %, baisse le son à 20, monte le volume à 80, volume à fond, à la moitié")]
                + AppAction.allCases.map { .init(value: $0.rawValue, description: $0.description) }
                + sounds.enumerated().map { .init(value: "sound\($0.offset)", description: $0.element.description) }
                + radios.enumerated().map { .init(value: "radio\($0.offset)", description: $0.element.description) }
                + [.init(value: "none", description: "None of these commands")]
        ))
        /// An option of the command question: a sound or Bluetooth device
        /// by position, else a Mac command by id.
        func action(_ key: String) -> MacAction? {
            if key == volumeLevel { return .volume(Self.levelToRead) }
            if key.hasPrefix("sound"), let index = Int(key.dropFirst(5)) { return sounds.indices.contains(index) ? sounds[index] : nil }
            if key.hasPrefix("radio"), let index = Int(key.dropFirst(5)) { return radios.indices.contains(index) ? radios[index] : nil }
            return MacAction(rawValue: key)
        }
        // Recent projects and the user's own commands each in a question of
        // their own, in the same request: one crowded list made every
        // wording move another answer.
        let projectActions = projects.prefix(40).map(MacAction.project)
        let scriptActions = scripts.prefix(60).map(MacAction.script)
        let shortcutActions = shortcuts.map { MacAction.shortcut($0, withSelection: false) }
        // Every shortcut, 60 a question (as apps are split): a name said
        // must be found whoever has many.
        let shortcutQuestions = MenuCandidates.chunks(Array(shortcutActions.indices), size: 60).enumerated().map { ("shortcut\($0.offset)", $0.element) }
        if !projectActions.isEmpty {
            questions.append(DecisionQuestion(
                name: "project",
                instructions: "Which of the user's recent projects (folders they open in their code editor) do they want to open or work on? One they name, even in passing, or describe counts. Answer none when they ask for something else.",
                options: projectActions.enumerated().map { .init(value: "project\($0.offset)", description: $0.element.description) }
                    + [.init(value: "none", description: "Not one of these projects")]
            ))
        }
        // System Settings' panes, described by what Settings' own search
        // finds in each: "la partie display" is Displays (Moniteurs).
        let paneActions = settings.map(MacAction.settings)
        if !paneActions.isEmpty {
            questions.append(DecisionQuestion(
                name: "settings",
                instructions: "Does the user ask to open or go to one pane of System Settings (the Mac's own settings app), or where to change a Mac setting? Which pane? Answer none when they ask for something else: to do it directly (dark mode, louder, lock the screen, connect or disconnect their AirPods or another device, turn Wi-Fi on or off), the settings of another app, or System Settings with no pane named or described.",
                options: paneActions.enumerated().map { .init(value: "pane\($0.offset)", description: $0.element.description) }
                    + [.init(value: "none", description: "Not one of these panes")]
            ))
        }
        if !scriptActions.isEmpty {
            questions.append(DecisionQuestion(
                name: "skillie",
                instructions: "Does the user ask to run one of their own commands (skillies), by its name or by what it does? Which one? Answer none when they ask for something else.",
                options: scriptActions.enumerated().map { .init(value: "script\($0.offset)", description: $0.element.description) }
                    + [.init(value: "none", description: "Not one of these commands")]
            ))
        }
        // The user's shortcuts by name only: Shortcuts says nothing more of
        // them.
        for (name, indices) in shortcutQuestions {
            questions.append(DecisionQuestion(
                name: name,
                instructions: "Does the user ask to run one of their shortcuts (made in Apple's Shortcuts app), by its name or by what its name says it does? Which one? Answer none when they ask for something else.",
                options: indices.map { .init(value: "shortcut-\($0)", description: shortcutActions[$0].description) }
                    + [.init(value: "none", description: "Not one of these shortcuts")]
            ))
        }
        let appChunks = MenuCandidates.chunks(apps)
        for (index, chunk) in appChunks.enumerated() {
            questions.append(DecisionQuestion(
                name: "app\(index)",
                instructions: "Which of these installed apps does the user want to open, by its name or by what it does? Answer none when no app fits.",
                options: chunk.map { .init(value: $0.name, description: $0.kind.isEmpty ? "App" : "App for \($0.kind)") }
                    + [.init(value: "none", description: "None of these apps fits the request")]
            ))
        }
        for (index, chunk) in chunks.enumerated() {
            questions.append(DecisionQuestion(
                name: "menu\(index)",
                instructions: "Which menu item of \(app.isEmpty ? "the app" : app) does what the user asks, or is the place they ask about? Answer none when no item fits.",
                options: chunk.map { .init(value: $0.path, description: $0.shortcut.map { "Shortcut \($0)" } ?? "Menu item") }
                    + [.init(value: "none", description: "None of these menu items fits the request")]
            ))
        }
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            let start = ContinuousClock.now
            do {
                let answers = try await DecisionClient.decide(questions, input: input, provider: provider, key: key)
                guard let first = answers[question.name] else { continue }
                let routed = await settled(first, instruction: instruction, input: input, provider: provider, key: key)
                guard let picked = AskRoute(rawValue: routed.choice) else { continue }
                let elapsed = ContinuousClock.now - start
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                var ranked: [(item: MenuReader.Item, probability: Double)] = []
                for (index, chunk) in chunks.enumerated() {
                    guard let answer = answers["menu\(index)"] else { continue }
                    for item in chunk {
                        if let probability = answer.probabilities[item.path], probability > 0 { ranked.append((item, probability)) }
                    }
                }
                ranked.sort { $0.probability > $1.probability }
                var rankedApps: [(app: AppCandidates.App, probability: Double)] = []
                for (index, chunk) in appChunks.enumerated() {
                    guard let answer = answers["app\(index)"] else { continue }
                    for candidate in chunk {
                        if let probability = answer.probabilities[candidate.name], probability > 0 { rankedApps.append((candidate, probability)) }
                    }
                }
                rankedApps.sort { $0.probability > $1.probability }
                // The list with a sure candidate wins: "find" vs "open" is
                // often a matter of words ("va dans le dossier Applications"
                // is a menu; "ouvre les réglages" is an app), and a sure
                // menu item or app beats the agent, faster and exact.
                // The surest of the Mac command, the project and the skillie.
                // A project or a skillie: the likeliest one even when "none"
                // edges it; the rules below weigh its probability.
                func pick(_ question: String, _ actions: [MacAction], prefix: String) -> (MacAction, Double)? {
                    guard let answer = answers[question] else { return nil }
                    if prefix.isEmpty {
                        var choice = answer.choice
                        // The route sure it is a Mac command, the list unsure
                        // ("monte le son": none 36 %, volumeUp 28 %): its
                        // likeliest command, from 25 %; under 50 % the card
                        // offers the likeliest ones (`commands`).
                        if choice == "none", picked == .command, routed.confidence >= 0.8,
                           let best = answer.probabilities.filter({ $0.key != "none" }).max(by: { $0.value < $1.value }), best.value >= 0.25 {
                            choice = best.key
                        }
                        guard choice != "none" else { return nil }
                        return action(choice).map { ($0, answer.probabilities[choice] ?? answer.confidence) }
                    }
                    guard let best = answer.probabilities.filter({ $0.key != "none" }).max(by: { $0.value < $1.value }),
                          let index = Int(best.key.dropFirst(prefix.count)), actions.indices.contains(index) else { return nil }
                    return (actions[index], best.value)
                }
                let menuBest = ranked.first?.probability ?? 0
                let appBest = rankedApps.first?.probability ?? 0
                // A project or a skillie counts only from its threshold,
                // whatever the route: "met la chanson suivante" once opened a
                // 0 % project in Zed (route "command", no Mac command found).
                // Asked to open something no app is, a project counts from
                // 25 %: "ouvre mon portfolio" (Decisions: open, Photos 8 %,
                // the portfolio project 32 %) offered Photos.
                let projectBar = picked == .open && appBest < 0.5 ? 0.25 : 0.4
                let direct = pick("command", [], prefix: "")
                // Connecting a device or turning Wi-Fi off is done, not its
                // pane opened: "connecte mes AirPods" once went to the
                // Bluetooth pane (Decisions, pane over device). Unless the
                // settings are named: "open the wifi settings".
                let namesSettings = answers[opensSettings.name].map { ($0.probabilities["yes"] ?? ($0.choice == "yes" ? 1 : 0)) >= 0.5 } ?? false
                let isRadio: Bool = switch direct?.0 {
                case .bluetooth?, .system(.wifiOn)?, .system(.wifiOff)?: true
                default: false
                }
                let doesIt = isRadio && !namesSettings && (direct?.1 ?? 0) >= 0.4
                // And the other way: "open the wifi settings" is the pane,
                // never Wi-Fi turned on: Wi-Fi's or Bluetooth's settings
                // named are their pane, whatever the questions found (Wi-Fi
                // offered as a switch pulled Decisions to System Settings).
                let letters = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter(\.isLetter) }
                let namedPane: (MacAction, Double)? = namesSettings ? settings.first { pane in
                    let name = letters(pane.name)
                    return (name == "wifi" || name == "bluetooth") && letters(instruction).contains(name)
                }.map { (MacAction.settings($0), 0.9) } : nil
                let command = ([isRadio && namesSettings ? nil : direct, pick("project", projectActions, prefix: "project"),
                                pick("skillie", scriptActions, prefix: "script"), namedPane]
                               + shortcutQuestions.map { pick($0.0, shortcutActions, prefix: "shortcut-") }
                               + (doesIt ? [] : [pick("settings", paneActions, prefix: "pane")]))
                    .compactMap { $0 }
                    .filter { action, probability in
                        switch action {
                        case .project: probability >= projectBar
                        case .script, .shortcut: probability >= 0.6
                        case .settings: probability >= 0.5
                        default: true
                        }
                    }
                    .max { $0.1 < $1.1 }
                let commands: [(command: MacAction, probability: Double)] = (answers["command"]?.probabilities ?? [:])
                    .filter { $0.key != "none" && $0.value >= 0.1 }
                    .sorted { $0.value > $1.value }
                    .compactMap { key, value in action(key).map { ($0, value) } }
                for name in [question.name, "command", "project", "skillie", "settings"] + shortcutQuestions.map(\.0) {
                    guard let answer = answers[name] else { continue }
                    let top = answer.probabilities.sorted { $0.value > $1.value }.prefix(4).map { key, value in
                        let pane = key.hasPrefix("pane") ? Int(key.dropFirst(4)).flatMap { settings.indices.contains($0) ? settings[$0].name : nil } : nil
                        return "\(pane ?? key) \(Int(value * 100))%"
                    }
                    Log.trace("Ask \(name) “\(instruction)”: \(top.joined(separator: ", "))")
                }
                var route = picked
                // Quit, force quit or uninstall an app named: the name is
                // read once the route is known.
                // Not over a route sure of itself: "lance Zoom" (Jev: open
                // 78 %, quit 62 %) quit Zoom.
                var appAction = answers["command"].flatMap { answer in
                    AppAction(rawValue: answer.choice).flatMap { (answer.probabilities[$0.rawValue] ?? 0) >= 0.5 ? $0 : nil }
                }
                if appAction != nil, route == .act || route == .open || route == .answer && !hasSelection {
                    if (routed.probabilities[route.rawValue] ?? 0) < sureRoute { route = .command } else { appAction = nil }
                }
                // "Command" with no command that fits: "ouvre les réglages
                // système" sounds like one (Decisions: command 40 %, act
                // 8 %). An app or a menu item that fits (60 %, what opens at
                // once) does it; else the agent, unless a list below has a
                // sure candidate.
                if route == .command, command == nil, appAction == nil {
                    route = max(menuBest, appBest) >= 0.6 ? (menuBest >= appBest ? .find : .open) : .act
                }
                // A sure Mac command beats the agent and a written answer:
                // "il me reste combien de batterie" is System Info. A pane
                // does not beat an answer: "comment changer la résolution"
                // is asked to be told.
                let isPane = if case .settings? = command?.0 { true } else { false }
                if route == .act || route == .answer && !isPane, (command?.1 ?? 0) >= 0.85 { route = .command }
                // Not when the agent is sure: an app named in what it is
                // asked to do is not an app to open ("dis à Thomas sur Slack
                // que…": act 88 %, Slack sure, opened Slack; Jev, 4 of the
                // 10 agent requests `AskRouteCorpus` tunes on).
                switch route {
                case .find where menuBest < 0.5 && appBest >= 0.85: route = .open
                case .open where appBest < 0.5 && menuBest >= 0.85: route = .find
                case .act where (menuBest >= 0.85 || appBest >= 0.85) && (routed.probabilities[AskRoute.act.rawValue] ?? 0) < sureRoute:
                    route = menuBest >= appBest ? .find : .open
                default: break
                }
                // "ouvre les réglages système dans la partie display": the
                // pane named beats System Settings itself (98 % as an app),
                // a menu item and the agent; asked as a question, the
                // answer stays.
                if isPane, let probability = command?.1, probability >= 0.6,
                   route == .open || route == .act || route == .find && menuBest < 0.85 {
                    route = .command
                }
                // "ouvre mon portfolio": a recent project that fits (40 %,
                // 25 % when no app fits) beats an unsure app, the agent and,
                // with nothing selected, a written answer ("je veux bosser
                // sur l'api"); opening it changes nothing. One of the user's
                // scripts or shortcuts that fits beats the agent and doing it by hand in
                // the app in front too, asked first in the card under 85 %.
                if appBest < 0.85, menuBest < 0.85, let (action, probability) = command {
                    switch action {
                    case .project:
                        if (route == .open || route == .act || route == .answer && !hasSelection) && probability >= projectBar {
                            route = .command
                        }
                    case .script:
                        if (route == .open || route == .act || route == .control) && probability >= 0.6 { route = .command }
                    // A shortcut named whole ("lance ma routine du matin":
                    // Jev routed it to plans, the shortcut 96 %) is run, even
                    // over a reminder or an answer.
                    case .shortcut:
                        if (route == .open || route == .act || route == .control) && probability >= 0.6
                            || (route == .plans || route == .answer && !hasSelection) && probability >= 0.85 { route = .command }
                    default:
                        break
                    }
                }
                // Again and again at times said: kept on a schedule, whatever it does then.
                if mentionsRepeat, let answer = answers[scheduleQuestion.name], answer.choice == "yes", (answer.probabilities["yes"] ?? 0) >= 0.5 {
                    route = .schedule
                }
                Log.trace("Ask decided “\(instruction)” in \(app): \(route.rawValue) (\(picked.rawValue) \(Int(routed.confidence * 100))%); services named \(named); menu \(ranked.prefix(3).map { "\($0.item.path) \(Int($0.probability * 100))%" }); apps \(rankedApps.prefix(3).map { "\($0.app.name) \(Int($0.probability * 100))%" }); \(menu.count) menu items, \(apps.count) apps")
                let name = provider == .typeSafe ? "Jev" : "Decisions"
                Log.actions.notice("Ask routed to \(route.rawValue, privacy: .public) by \(name, privacy: .public) (\(Int(routed.confidence * 100))%), \(menu.count) menu items, in \(String(format: "%.2f", seconds), privacy: .public) s")
                let routes = routed.probabilities.compactMap { key, value in AskRoute(rawValue: key).map { ($0, value) } }
                    .sorted { $0.1 > $1.1 }
                var read: [String: AskValues.Answer] = [:]
                for value in values {
                    if let answer = answers[value.name] { read[value.name] = AskValues.Answer(choice: answer.choice, confidence: answer.confidence) }
                }
                return Decision(route: route, confidence: routed.confidence, menu: Array(ranked.prefix(3)),
                                apps: Array(rankedApps.prefix(3)), routes: routes, command: command, commands: Array(commands.prefix(3)),
                                appAction: appAction, label: "\(name) · \(String(format: "%.2f s", seconds))", services: named, values: read)
            } catch {
                Log.actions.error("Ask route by \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}
