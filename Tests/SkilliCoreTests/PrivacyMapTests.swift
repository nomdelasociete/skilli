@testable import SkilliCore
import XCTest

final class PrivacyMapTests: XCTestCase {
    /// Everything set up: Claude Code signed in writes Ask, both deciding
    /// keys, GitHub with a relay, a server and a webhook.
    private var everything: PrivacyMap.Setup {
        var setup = PrivacyMap.Setup()
        setup.claude = .claudeCode
        setup.chatGPT = true
        setup.openAIKey = true
        setup.typeSafeKey = true
        setup.claudeCode = true
        setup.askWriter = .claude
        setup.commands = [.init(title: "Fix Spelling & Grammar", writer: .claude),
                          .init(title: "Translate", writer: .chatGPT),
                          .init(title: "Summarize", writer: .openAI),
                          .init(title: "Plan My Day", writer: nil, acts: true)]
        setup.continueIn = .chatGPT
        setup.imageFolder = "Screenshots"
        setup.githubLogin = "camille"
        setup.relayHost = "relay.example.com"
        setup.servers = ["linear"]
        setup.webhooks = ["n8n"]
        setup.scheduledAsks = ["Every Monday at 9:00"]
        return setup
    }

    private func section(_ destination: PrivacyMap.Destination, _ setup: PrivacyMap.Setup) -> PrivacyMap.Section {
        PrivacyMap.sections(for: setup).first { $0.destination == destination }!
    }

    private func ids(_ destination: PrivacyMap.Destination, _ setup: PrivacyMap.Setup) -> [String] {
        section(destination, setup).rows.map(\.id)
    }

    func testEveryPlaceOnceInOrder() {
        XCTAssertEqual(PrivacyMap.sections(for: PrivacyMap.Setup()).map(\.destination), PrivacyMap.Destination.allCases)
        XCTAssertEqual(PrivacyMap.sections(for: everything).map(\.destination), PrivacyMap.Destination.allCases)
    }

    func testEveryFlowSaysWhatAndWhenInTheBrandsWords() {
        XCTAssertEqual(Set(PrivacyMap.all.map(\.id)).count, PrivacyMap.all.count, "ids are unique")
        XCTAssertEqual(Set(PrivacyMap.all.map(\.title)).count, PrivacyMap.all.count, "titles are unique")
        // The panes rows may point to (`SettingsPane` raw values).
        let panes: Set<String> = ["ask", "commands", "tools", "aiAccounts", "clipboard", "snippets", "emoji", "gifs", "launcher", "github", "reminders", "windows",
                                   "recorder", "catalog"]
        for flow in PrivacyMap.all {
            XCTAssertFalse(flow.sends.isEmpty, flow.title)
            XCTAssertFalse(flow.when.isEmpty, flow.title)
            XCTAssertTrue(flow.sends.hasSuffix("."), "\(flow.title): a sentence")
            XCTAssertTrue(flow.when.hasSuffix("."), "\(flow.title): a sentence")
            if let pane = flow.pane { XCTAssertTrue(panes.contains(pane), "\(flow.title): \(pane)") }
            for text in [flow.title, flow.sends, flow.when, flow.toggle ?? ""] {
                XCTAssertNil(text.range(of: #"\bAI\b"#, options: .regularExpression), "\(flow.title): the brand says SI")
            }
        }
        for text in [PrivacyMap.statement, PrivacyMap.staysHere, PrivacyMap.syncs] {
            XCTAssertNil(text.range(of: #"\bAI\b"#, options: .regularExpression))
        }
    }

    func testEveryFlowShowsWhenEverythingIsSetUp() {
        var placed = Set(PrivacyMap.sections(for: everything).flatMap(\.rows).map(\.id))
        // With both keys OpenAI only gets what Jev did not answer; with
        // OpenAI's key alone, the choices themselves.
        var openAIOnly = everything
        openAIOnly.typeSafeKey = false
        placed.formUnion(PrivacyMap.sections(for: openAIOnly).flatMap(\.rows).map(\.id))
        // The rules' checks only while there are rules.
        var withRules = everything
        withRules.rules = true
        placed.formUnion(PrivacyMap.sections(for: withRules).flatMap(\.rows).map(\.id))
        // Server sync: GitHub only for actions, the relay reads.
        var serverSync = everything
        serverSync.githubServerSync = true
        placed.formUnion(PrivacyMap.sections(for: serverSync).flatMap(\.rows).map(\.id))
        XCTAssertEqual(placed, Set(PrivacyMap.all.map(\.id)))
    }

    func testEachWriterGetsAskWhenItWrites() {
        for provider in WritingProvider.allCases {
            var setup = PrivacyMap.Setup()
            setup.askWriter = provider
            let destination = PrivacyMap.Destination(writer: provider)
            XCTAssertEqual(ids(destination, setup), ["ask", "followUps", "mail", "fieldWords", "plannedSteps", "meetings"], provider.title)
            for other in PrivacyMap.Destination.allCases where other != destination {
                XCTAssertFalse(ids(other, setup).contains("ask"), "\(provider.title): not to \(other.title)")
            }
        }
    }

    func testCommandsGoWhereTheyWrite() {
        let sections = PrivacyMap.sections(for: everything)
        func note(_ destination: PrivacyMap.Destination) -> String? {
            sections.first { $0.destination == destination }?.rows.first { $0.id == "commands" }?.note
        }
        XCTAssertEqual(note(.claude), "Fix Spelling & Grammar")
        XCTAssertEqual(note(.chatGPT), "Translate")
        XCTAssertEqual(note(.openAI), "Summarize")
        // ChatGPT writes no Ask here: a command and its follow-ups only.
        XCTAssertEqual(ids(.chatGPT, everything), ["commands", "followUps", "continueIn", "rightsHelp"])
    }

    func testActingIsClaudeCodeOnly() {
        var setup = everything
        setup.askWriter = .chatGPT
        let agent = section(.claude, setup).rows.first { $0.id == "agent" }
        XCTAssertEqual(agent?.note, "Through Claude Code. Commands: Plan My Day")
        for destination in PrivacyMap.Destination.allCases where destination != .claude {
            XCTAssertFalse(ids(destination, setup).contains("agent"), destination.title)
        }
        setup.claudeCode = false
        XCTAssertFalse(ids(.claude, setup).contains("agent"), "no Claude Code, no agent")
    }

    /// A scheduled ask sends what Ask sends, at its time: through Claude
    /// Code when it can act, else to whoever writes Ask's answers; none
    /// scheduled, nothing said.
    func testScheduledAsksGoWhereAskGoes() {
        var setup = everything
        XCTAssertEqual(section(.claude, setup).rows.first { $0.id == "scheduled" }?.note, "Through Claude Code: Every Monday at 9:00")
        setup.claudeCode = false
        setup.askWriter = .chatGPT
        XCTAssertFalse(ids(.claude, setup).contains("scheduled"))
        XCTAssertEqual(section(.chatGPT, setup).rows.first { $0.id == "scheduled" }?.note, "Every Monday at 9:00")
        setup.scheduledAsks = []
        XCTAssertFalse(PrivacyMap.sections(for: setup).flatMap(\.rows).contains { $0.id == "scheduled" })
    }

    func testNothingSetUpSendsNothingToTheModels() {
        let setup = PrivacyMap.Setup()
        for destination in [PrivacyMap.Destination.claude, .chatGPT, .openAI, .typeSafe, .github] {
            let placed = section(destination, setup)
            XCTAssertTrue(placed.rows.isEmpty, destination.title)
            XCTAssertFalse(placed.inUse)
            XCTAssertTrue(placed.status.contains("nothing goes to"), "\(destination.title): \(placed.status)")
        }
        // Agents connected to skil.li, a place, a speed test: always possible.
        XCTAssertEqual(ids(.yours, setup), ["agents"])
        XCTAssertEqual(ids(.apple, setup), ["places", "speedTest"])
    }

    func testJevDecidesFirstThenOpenAI() {
        let deciding = ["route", "doItHere", "quit", "files", "history", "clipboard", "snippets", "emoji", "findControl", "autoQuit"]
        var setup = PrivacyMap.Setup()
        setup.typeSafeKey = true
        XCTAssertEqual(ids(.typeSafe, setup), deciding + ["imagesCopied", "imagesFolder"])
        XCTAssertEqual(ids(.openAI, setup), [])

        setup.openAIKey = true
        XCTAssertEqual(ids(.openAI, setup), ["fallback"], "OpenAI only when Jev does not answer")

        setup.typeSafeKey = false
        XCTAssertEqual(ids(.openAI, setup), deciding, "OpenAI's key alone decides, never images")
        XCTAssertEqual(ids(.typeSafe, setup), [])
    }

    func testDoingItHereSaysWhoGetsItsPictures() {
        let flow = PrivacyMap.doItHere
        XCTAssertTrue(flow.sends.contains("pictures of that window"), flow.sends)
        XCTAssertTrue(flow.sends.hasSuffix("to TypeSafe Jev."), flow.sends)
        XCTAssertTrue(flow.when.contains("Screen Recording"), flow.when)
        XCTAssertTrue(PrivacyMap.fallback.sends.contains("never images"), "OpenAI decides from the words")
        // Planning, the writer sees the window too: Claude only, said so.
        let plan = PrivacyMap.plannedSteps
        XCTAssertTrue(plan.sends.contains("to Claude, one picture of that window"), plan.sends)
        XCTAssertTrue(plan.when.contains("Screen Recording"), plan.when)
    }

    func testRulesGoToWhoDecidesOnlyWhileThereAreRules() {
        var setup = PrivacyMap.Setup()
        setup.typeSafeKey = true
        XCTAssertFalse(ids(.typeSafe, setup).contains("rules"))
        setup.rules = true
        XCTAssertEqual(Array(ids(.typeSafe, setup).prefix(3)), ["route", "doItHere", "rules"])
        setup.typeSafeKey = false
        setup.openAIKey = true
        XCTAssertTrue(ids(.openAI, setup).contains("rules"), "OpenAI's key alone checks them")
        setup.openAIKey = false
        XCTAssertTrue(PrivacyMap.sections(for: setup).allSatisfy { !$0.rows.map(\.id).contains("rules") }, "no key: nothing checks them")
        XCTAssertEqual(PrivacyMap.rules.pane, "ask")
    }

    func testSwitchesSayWhetherItGoes() {
        var setup = PrivacyMap.Setup()
        setup.typeSafeKey = true
        setup.fileMeaning = false
        setup.imagesCopied = false
        setup.imageFolder = "Desktop"
        let rows = section(.typeSafe, setup).rows
        func isOn(_ id: String) -> Bool? { rows.first { $0.id == id }?.isOn }
        XCTAssertEqual(isOn("files"), false)
        XCTAssertEqual(isOn("history"), true)
        XCTAssertEqual(isOn("imagesCopied"), false)
        XCTAssertEqual(isOn("imagesFolder"), true)
        XCTAssertNil(isOn("route"), "no switch: it goes when used")
        XCTAssertEqual(isOn("autoQuit"), false, "Auto Quit is off by default")
        XCTAssertEqual(rows.first { $0.id == "imagesFolder" }?.note, "Folder: Desktop")
        XCTAssertEqual(isOn("snippets"), true)

        // Snippets by meaning off; screenshots kept out of the history:
        // the folder's images are not looked at either.
        setup.snippetMeaning = false
        setup.screenshots = false
        let quieter = section(.typeSafe, setup).rows
        XCTAssertEqual(quieter.first { $0.id == "snippets" }?.isOn, false)
        XCTAssertEqual(quieter.first { $0.id == "imagesFolder" }?.isOn, false)
        XCTAssertEqual(quieter.first { $0.id == "imagesCopied" }?.isOn, false)
        setup.screenshots = true

        // No clipboard history: no image is kept, none is sent.
        setup.clipboardHistory = false
        let off = section(.typeSafe, setup).rows
        XCTAssertEqual(off.first { $0.id == "imagesFolder" }?.isOn, false)
        XCTAssertEqual(off.first { $0.id == "clipboard" }?.isOn, false)
    }

    func testSetUpButUnusedSaysNothingGoes() {
        var setup = PrivacyMap.Setup()
        setup.chatGPT = true
        setup.askWriter = .claude
        setup.claude = .claudeCode
        let chatGPT = section(.chatGPT, setup)
        XCTAssertFalse(chatGPT.inUse)
        XCTAssertEqual(chatGPT.status, "Your ChatGPT account, through Codex on this Mac; nothing goes there now")
        XCTAssertEqual(section(.claude, setup).status, "Your Claude plan, through Claude Code on this Mac")
    }

    func testGitHubAndYours() {
        XCTAssertEqual(ids(.github, everything), ["github", "githubWorkflows", "relay"])
        XCTAssertEqual(section(.github, everything).status, "Signed in as @camille")
        XCTAssertEqual(section(.github, everything).rows.last?.note, "relay.example.com")
        XCTAssertEqual(ids(.yours, everything), ["servers", "webhooks", "agents"])
    }

    func testLongListsAreCut() {
        XCTAssertEqual(PrivacyMap.list(["A", "B", "C", "D"]), "A, B, C, D")
        XCTAssertEqual(PrivacyMap.list(["A", "B", "C", "D", "E"]), "A, B, C and 2 more")
    }

    // MARK: - One line in a pane

    func testAskSaysWhoWritesWhoActsAndWhoChooses() throws {
        let full = try XCTUnwrap(PrivacyMap.line(for: "ask", everything))
        XCTAssertEqual(full.text, "When you ask, your request, the text you selected and About You go to Claude; your asks on a schedule send "
            + "their request and About You at their times; TypeSafe Jev gets your request "
            + "to choose what to do, and what the window shows when it acts there.")
        XCTAssertEqual(full.more, "privacy")

        // OpenAI writes and chooses; Claude Code still acts.
        var openAI = PrivacyMap.Setup()
        openAI.askWriter = .openAI
        openAI.openAIKey = true
        openAI.claudeCode = true
        XCTAssertEqual(PrivacyMap.line(for: "ask", openAI)?.text,
                       "When you ask, your request, the text you selected and About You go to OpenAI, and to Claude when it acts with your "
                           + "tools; OpenAI also chooses what to do, and reads the window when it acts there.")

        // No deciding key: only the writer.
        var chatGPT = PrivacyMap.Setup()
        chatGPT.askWriter = .chatGPT
        XCTAssertEqual(PrivacyMap.line(for: "ask", chatGPT)?.text,
                       "When you ask, your request, the text you selected and About You go to ChatGPT.")
    }

    func testAskSaysTheRulesAreChecked() {
        var setup = everything
        setup.rules = true
        XCTAssertEqual(PrivacyMap.line(for: "ask", setup)?.text,
                       "When you ask, your request, the text you selected and About You go to Claude; your asks on a schedule send their "
                           + "request and About You at their times; TypeSafe Jev gets your request to choose what to do, and what the window "
                           + "shows when it acts there, and each step an agent takes, to check it against your rules.")
    }

    func testCommandsSayWhereTheyWrite() {
        XCTAssertEqual(PrivacyMap.line(for: "commands", everything)?.text,
                       "When you run a command, its prompt and what it names (the text you selected, the clipboard, About You when it "
                           + "includes it) go to Claude, ChatGPT or OpenAI, as each command says; commands with tools go to Claude "
                           + "through Claude Code, with what its tools read.")
        var claude = PrivacyMap.Setup()
        claude.commands = [.init(title: "Fix", writer: .claude), .init(title: "Improve", writer: .claude)]
        XCTAssertEqual(PrivacyMap.line(for: "commands", claude)?.text,
                       "When you run a command, its prompt and what it names (the text you selected, the clipboard, About You when it "
                           + "includes it) go to Claude.")
        var nothing = PrivacyMap.Setup()
        nothing.commands = [.init(title: "Fix", writer: nil)]
        XCTAssertEqual(PrivacyMap.line(for: "commands", nothing), PrivacyMap.PaneLine(
            text: "Nothing leaves this Mac yet: commands need an account to write with.", more: "aiAccounts"))
    }

    func testToolsSayWhatAgentsServersAndRulesGet() {
        XCTAssertEqual(PrivacyMap.line(for: "tools", PrivacyMap.Setup())?.text, "What skil.li's tools read goes to the agent that asked for it.")
        var setup = everything
        setup.rules = true
        XCTAssertEqual(PrivacyMap.line(for: "tools", setup)?.text,
                       "What skil.li's tools read goes to the agent that asked for it; what an agent sends your servers' tools goes to "
                           + "those servers, with your sign-in; your tools get the text an agent sends them; TypeSafe Jev checks each step "
                           + "against your rules.")
        // Rules and no key to check them: nothing goes for them.
        setup.typeSafeKey = false
        setup.openAIKey = false
        XCTAssertFalse(PrivacyMap.line(for: "tools", setup)?.text.contains("rules") ?? true)
    }

    func testAskWithNothingToWriteWithSaysWhatItNeeds() {
        let line = PrivacyMap.line(for: "ask", PrivacyMap.Setup())
        XCTAssertEqual(line?.text, "Nothing leaves this Mac yet: Ask needs an account to write with.")
        XCTAssertEqual(line?.more, "aiAccounts")
    }

    func testAccountsSayWhatGoesToEach() {
        var usual = PrivacyMap.Setup()
        usual.claude = .claudeCode
        usual.askWriter = .claude
        usual.typeSafeKey = true
        usual.imagesCopied = false
        usual.imagesFolder = false
        XCTAssertEqual(PrivacyMap.line(for: "aiAccounts", usual)?.text,
                       "What you ask goes to Claude; Ask's choices and searches by meaning go to TypeSafe Jev.")

        XCTAssertEqual(PrivacyMap.line(for: "aiAccounts", everything)?.text,
                       "What you ask, your commands and what Ask does with tools go to Claude; the commands set to it and conversations "
                           + "you continue go to ChatGPT; the commands set to it and Ask's choices when Jev fails go to OpenAI; Ask's "
                           + "choices, searches by meaning and the images you copy and your screenshots go to TypeSafe Jev.")
        XCTAssertEqual(PrivacyMap.line(for: "aiAccounts", PrivacyMap.Setup())?.text, "Nothing leaves this Mac: no account is set up.")
    }

    func testGitHubSaysTheSignInGoesWithEachReadAndTheRelayGetsItsToken() {
        XCTAssertEqual(PrivacyMap.line(for: "github", PrivacyMap.Setup())?.text, "Nothing leaves this Mac: you are not signed in to GitHub.")
        var signedIn = PrivacyMap.Setup()
        signedIn.githubLogin = "camille"
        XCTAssertEqual(PrivacyMap.line(for: "github", signedIn)?.text,
                       "GitHub gets your sign-in with each read, every minute while the strip or “pr” shows, and what you do there: merge, "
                           + "update a branch, mark read, a workflow you start, then its run read every 5 s until it ends.")
        XCTAssertEqual(PrivacyMap.line(for: "github", everything)?.text,
                       "GitHub gets your sign-in with each read, every minute while the strip or “pr” shows, and what you do there: merge, "
                           + "update a branch, mark read, a workflow you start, then its run read every 5 s until it ends; relay.example.com gets only its own token, never your GitHub sign-in.")
    }

    func testServerSyncSaysGitHubGetsTheSignInOnlyForActions() {
        var setup = everything
        setup.githubServerSync = true
        XCTAssertEqual(PrivacyMap.line(for: "github", setup)?.text,
                       "GitHub gets your sign-in only for what you do there (merge, update a branch, mark read, a workflow you start, "
                           + "then its run read every 5 s until it ends) and to check which "
                           + "account this Mac uses for the relay; relay.example.com reads "
                           + "your pull requests and notifications on GitHub with its own authorization and keeps one copy for your Macs.")
        XCTAssertEqual(ids(.github, setup), ["githubActions", "githubWorkflows", "serverSync"])
        XCTAssertEqual(ids(.github, everything), ["github", "githubWorkflows", "relay"])
        // This Mac's relay access gone, server sync still on: said all the same.
        setup.relayHost = nil
        XCTAssertEqual(PrivacyMap.line(for: "github", setup)?.text,
                       "GitHub gets your sign-in only for what you do there (merge, update a branch, mark read, a workflow you start, "
                           + "then its run read every 5 s until it ends) and to check which "
                           + "account this Mac uses for the relay; the relay reads "
                           + "your pull requests and notifications on GitHub with its own authorization and keeps one copy for your Macs.")
        XCTAssertEqual(ids(.github, setup), ["githubActions", "githubWorkflows", "serverSync"])
    }

    func testBackupSaysWhereBackupsGoAndWhoSyncsThem() {
        var setup = PrivacyMap.Setup()
        XCTAssertEqual(PrivacyMap.line(for: "backup", setup)?.text, "Nothing leaves this Mac: until you choose a folder, nothing is backed up.")
        setup.backupFolder = "Documents › skil.li Backups"
        XCTAssertEqual(PrivacyMap.line(for: "backup", setup)?.text, "Nothing leaves this Mac: backups stay in Documents › skil.li Backups.")
        setup.backupFolder = "iCloud Drive › skil.li"
        setup.backupSyncs = "iCloud"
        XCTAssertEqual(PrivacyMap.line(for: "backup", setup)?.text,
                       "skil.li sends nothing: backups go to iCloud Drive › skil.li, which iCloud syncs like your other files there.")
    }

    func testYourDetailsAreTypedHereAndAboutYouGoesWithAsk() {
        // Jev chooses where each detail goes; About You goes with Ask
        // (Claude writes it and acts with tools) and the commands that
        // include it (Translate, written by ChatGPT).
        var setup = everything
        setup.commands[1].aboutYou = true
        XCTAssertEqual(PrivacyMap.line(for: "yourDetails", setup)?.text,
                       "Forms are typed on this Mac: TypeSafe Jev reads the fields and the kinds of details they ask for, never the details "
                           + "themselves; About You goes to Claude and ChatGPT with Ask and the commands that include it.")
        XCTAssertEqual(PrivacyMap.line(for: "yourDetails", setup)?.more, "privacy")
        // No key to choose with: nothing fills forms, the details stay; the
        // way to a key.
        var chatGPT = PrivacyMap.Setup()
        chatGPT.askWriter = .chatGPT
        XCTAssertEqual(PrivacyMap.line(for: "yourDetails", chatGPT)?.text,
                       "Your details stay on this Mac, and forms wait for a key that chooses where each goes; About You goes to ChatGPT "
                           + "with Ask and the commands that include it.")
        XCTAssertEqual(PrivacyMap.line(for: "yourDetails", chatGPT)?.more, "aiAccounts")
        XCTAssertEqual(PrivacyMap.line(for: "yourDetails", PrivacyMap.Setup())?.text,
                       "Your details stay on this Mac, and forms wait for a key that chooses where each goes.")
    }

    func testPaneLinesNameNoAIAndPointToPanesThatExist() {
        let setups = [PrivacyMap.Setup(), everything]
        for pane in ["ask", "aiAccounts", "commands", "tools", "windows", "clipboard", "snippets", "github", "backup", "yourDetails", "launcher",
                     "skillies", "recorder"] {
            for setup in setups {
                let line = PrivacyMap.line(for: pane, setup)
                XCTAssertNotNil(line, pane)
                XCTAssertNil(line?.text.range(of: #"\bAI\b"#, options: .regularExpression), pane)
                XCTAssertTrue(["privacy", "aiAccounts"].contains(line?.more ?? ""), pane)
            }
        }
        XCTAssertNil(PrivacyMap.line(for: "general", everything))
        XCTAssertNil(PrivacyMap.line(for: "keys", everything))
    }

    /// Launcher: pages and files by meaning, each only while its switch
    /// is on and a key can choose; Skillies: their names and what they do
    /// when Ask picks one.
    func testLauncherAndSkilliesSayWhatGoes() {
        XCTAssertEqual(PrivacyMap.line(for: "launcher", everything)?.text,
                       "When you press ⇥ in Search Browser History, your words and the titles, sites and dates of your pages go to "
                           + "TypeSafe Jev; in Search Files, your words and the names, kinds, folders and dates of the files that may fit go to "
                           + "TypeSafe Jev. Typing alone stays here.")
        var filesOff = everything
        filesOff.fileMeaning = false
        filesOff.historyMeaning = false
        XCTAssertEqual(PrivacyMap.line(for: "launcher", filesOff)?.text, "Nothing leaves this Mac: what you type and what it finds stay here.")
        XCTAssertEqual(PrivacyMap.line(for: "launcher", PrivacyMap.Setup())?.text.hasPrefix("Nothing"), true)
        XCTAssertEqual(PrivacyMap.line(for: "skillies", everything)?.text,
                       "Skillies run on this Mac and send only what their own code sends. To pick one when you ask, Ask sends their names "
                           + "and what they do to TypeSafe Jev.")
        XCTAssertEqual(PrivacyMap.line(for: "skillies", PrivacyMap.Setup())?.text,
                       "Nothing: skillies run on this Mac and send only what their own code sends.")
    }

    func testClipboardSaysWhatGoesFromItsSwitches() {
        XCTAssertEqual(PrivacyMap.line(for: "clipboard", everything)?.text,
                       "When you press ⇥, short excerpts of your copies go to TypeSafe Jev; each image you copy and each screenshot "
                           + "go once to TypeSafe Jev, as a small picture, to say what it shows; a link you look at is opened, without your "
                           + "cookies, to read its title and picture. Words in images are read here.")
        var openAIOnly = everything
        openAIOnly.typeSafeKey = false
        openAIOnly.linkPreviews = false
        XCTAssertEqual(PrivacyMap.line(for: "clipboard", openAIOnly)?.text,
                       "When you press ⇥, short excerpts of your copies go to OpenAI. Words in images are read here.", "never images to OpenAI")
        var noScreenshots = everything
        noScreenshots.screenshots = false
        noScreenshots.clipboardMeaning = false
        noScreenshots.linkPreviews = false
        XCTAssertEqual(PrivacyMap.line(for: "clipboard", noScreenshots)?.text,
                       "Each image you copy goes once to TypeSafe Jev, as a small picture, to say what it shows. Words in images are read here.")
        // No key at all: only the links looked at leave, to their sites.
        XCTAssertEqual(PrivacyMap.line(for: "clipboard", PrivacyMap.Setup())?.text,
                       "A link you look at is opened, without your cookies, to read its title and picture. Words in images are read here.")
        var off = everything
        off.clipboardHistory = false
        XCTAssertEqual(PrivacyMap.line(for: "clipboard", off)?.text,
                       "Nothing leaves this Mac: what you copy, your screenshots and the words read in them stay here.")
    }

    /// A link looked at in the history goes to its own site, nowhere else;
    /// off, nothing goes to websites.
    /// Better transcription's download: Hugging Face, a request for two
    /// files and nothing else, only on the user's click.
    func testBetterTranscriptionsDownloadIsListed() {
        let section = section(.huggingFace, PrivacyMap.Setup())
        XCTAssertEqual(section.rows.map(\.id), ["betterTranscription"])
        XCTAssertEqual(section.status, "Better transcription's download, only when you click it")
        XCTAssertEqual(section.rows.first?.flow.pane, "recorder")
        XCTAssertTrue(PrivacyMap.betterTranscription.sends.contains("nothing of yours"))
    }

    /// A recording's transcript goes to Ask's writer only from its window's
    /// ⌘K; the pane says so, and where.
    func testRecordedMeetingsGoToAsksWriterOnlyFromTheirWindow() {
        XCTAssertTrue(ids(.claude, everything).contains("meetings"))
        XCTAssertFalse(ids(.chatGPT, everything).contains("meetings"))
        XCTAssertEqual(PrivacyMap.line(for: "recorder", everything)?.text.hasPrefix(
            "When you pick a summary, chapters, action items or a recap in a recording's ⌘K, its transcript goes to Claude."), true)
        XCTAssertEqual(PrivacyMap.line(for: "recorder", PrivacyMap.Setup())?.text.hasPrefix("Nothing else leaves this Mac."), true)
        XCTAssertTrue(PrivacyMap.meetings.sends.contains("never its sound or pictures"))
    }

    func testLinkPreviewsGoToTheirSites() {
        let on = section(.websites, PrivacyMap.Setup())
        XCTAssertEqual(on.rows.map(\.id), ["linkPreviews"])
        XCTAssertEqual(on.rows.first?.isOn, true)
        XCTAssertEqual(on.rows.first?.flow.toggle, "Show link previews")
        XCTAssertEqual(on.status, "The sites of the links you look at in Clipboard History")
        for destination in PrivacyMap.Destination.allCases where destination != .websites {
            XCTAssertFalse(ids(destination, everything).contains("linkPreviews"), destination.title)
        }
        var off = PrivacyMap.Setup()
        off.linkPreviews = false
        XCTAssertEqual(section(.websites, off).rows.first?.isOn, false)
        XCTAssertEqual(section(.websites, off).status, "Link previews off: nothing goes to websites")
        var noHistory = PrivacyMap.Setup()
        noHistory.clipboardHistory = false
        XCTAssertEqual(section(.websites, noHistory).rows.first?.isOn, false)
    }

    func testSnippetsSayWhatGoesOnTab() {
        XCTAssertEqual(PrivacyMap.line(for: "snippets", everything)?.text,
                       "When you press ⇥ in Search Snippets, your words and each snippet's name, keyword and first 80 characters go to "
                           + "TypeSafe Jev; what you type stays here.")
        var off = everything
        off.snippetMeaning = false
        XCTAssertEqual(PrivacyMap.line(for: "snippets", off)?.text, "Nothing leaves this Mac: your snippets and what you type stay here.")
        XCTAssertEqual(PrivacyMap.line(for: "snippets", PrivacyMap.Setup())?.text, "Nothing leaves this Mac: your snippets and what you type stay here.")
    }

    /// Settings → Emoji: what was typed, with emoji names, while its
    /// switch is on and a key decides; the words learned never go.
    func testEmojiSaysWhatGoesOnTab() {
        let goes = "When you press ⇥, or when no emoji's name fits, what you typed goes to TypeSafe Jev with emoji names; the words learned stay here."
        let stays = "Nothing leaves this Mac: what you type and the words learned stay here."
        XCTAssertEqual(PrivacyMap.line(for: "emoji", everything)?.text, goes)
        XCTAssertEqual(section(.typeSafe, everything).rows.first { $0.id == "emoji" }?.isOn, true)
        var off = everything
        off.emojiMeaning = false
        XCTAssertEqual(PrivacyMap.line(for: "emoji", off)?.text, stays)
        XCTAssertEqual(section(.typeSafe, off).rows.first { $0.id == "emoji" }?.isOn, false)
        XCTAssertEqual(PrivacyMap.line(for: "emoji", PrivacyMap.Setup())?.text, stays)
    }

    /// Calendar, Reminders and Windows say what leaves the Mac from them,
    /// from the same flows as Settings → Privacy. Windows sends nothing
    /// while Quit apps you stopped using is off: the only flow living there.
    func testCalendarRemindersAndWindowsSayWhatLeaves() {
        // Ask reads what is said about them with the decision model: the
        // request and the calendars' or lists' names go there.
        XCTAssertEqual(PrivacyMap.line(for: "calendar", everything)?.text,
                       "Your calendars are read here; when you ask about them, your request and your calendars' names go to TypeSafe Jev to read it. "
                           + "Check Camera & Mic shows you only here.")
        XCTAssertTrue(PrivacyMap.line(for: "calendar", PrivacyMap.Setup())?.text.hasPrefix("Nothing leaves this Mac") == true, "no decision key")
        XCTAssertEqual(PrivacyMap.line(for: "reminders", everything)?.text,
                       "To Apple: the address you type, to find it on Apple Maps; for a reminder at home or at work with no place saved, "
                           + "your card's Home or Work address, once. When you add a place, or a reminder at home or at work with none saved. "
                           + "When you ask about your reminders, your request and your lists' names go to TypeSafe Jev to read it.")
        XCTAssertEqual(PrivacyMap.all.filter { $0.pane == "windows" }.map(\.id), ["autoQuit"])
        XCTAssertEqual(PrivacyMap.line(for: "windows", everything)?.text.hasPrefix("Nothing"), true, "Auto Quit is off")
        var autoQuit = everything
        autoQuit.autoQuit = true
        XCTAssertEqual(PrivacyMap.line(for: "windows", autoQuit)?.text.hasPrefix("To TypeSafe Jev, for Quit apps you stopped using: "
            + PrivacyMap.sentence(PrivacyMap.autoQuit)), true, PrivacyMap.line(for: "windows", autoQuit)?.text ?? "")
        XCTAssertTrue(PrivacyMap.line(for: "aiAccounts", autoQuit)?.text.contains("the apps Auto Quit may quit") == true,
                      PrivacyMap.line(for: "aiAccounts", autoQuit)?.text ?? "")
        var noKey = PrivacyMap.Setup()
        noKey.autoQuit = true
        XCTAssertEqual(PrivacyMap.line(for: "windows", noKey)?.text.hasPrefix("Nothing"), true, "no deciding key: decided here")
    }
}
