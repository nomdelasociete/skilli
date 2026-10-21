import AppKit
import Carbon.HIToolbox
import SkilliCore
import os

/// Ask's "do it here": acts in the window in front toward a goal, one step
/// at a time. Each step reads the window (Accessibility, the app's menus,
/// and the words on screen where Accessibility tells little), asks the
/// decision model in one request what to do next and on what, and does it:
/// Accessibility first, the mouse where it cannot. Where what was read says
/// too little (`ScreenControl.pictureNeed`, `isUnsure`), Jev also gets one
/// picture of that window (`WindowPicture`). The model only picks among
/// what was read, or a place in the picture where what to click is only
/// drawn (Jev's Box, `pickSpot`); where choosing the next step needs
/// thinking (a move in a game), the writer plans and Jev grounds each line
/// (docs/click-what-you-see.md). Text to type comes from the goal's quotes,
/// then the writer, then the user. What cannot be taken back is asked first.
@MainActor
final class ComputerControl {
    enum Outcome: Equatable {
        case done
        /// It could not go on: why, for the card.
        case stopped(String)
        case cancelled
    }

    /// What one step acts on.
    private enum Target {
        case element(UIReader.Element)
        case menu(MenuReader.Item)
        /// Words read on screen: clicked where they are.
        case words(CGRect)
    }

    /// The window as one step sees it.
    private struct Look {
        var app = ""
        var window = ""
        /// Where the window is on screen (Accessibility).
        var frame: CGRect?
        var items: [ScreenItem] = []
        var targets: [String: Target] = [:]
        /// Changes when the window does.
        var signature = ""
        /// The capture its words were read in, when they were: the picture
        /// reuses it.
        var capture: ScreenSight.Capture?
        /// Its time ran out before the whole window was read (an app slow
        /// to answer).
        var cutShort = false
        /// The app's menu items read: a look read again for a plan's line
        /// keeps them.
        var menus: [MenuReader.Item] = []
    }

    /// The window's picture for one decision, and the items outlined in it.
    private struct Picture {
        let image: JevImages.Image
        let marked: Set<String>
        let need: ScreenControl.PictureNeed
        let size: CGSize
        let captureMilliseconds: Int
    }

    /// One picture sent to Jev: why, how big, what it cost.
    struct PictureSent: Sendable {
        let need: ScreenControl.PictureNeed
        let width: Int
        let height: Int
        let bytes: Int
        let marks: Int
        let tokens: Int
        /// Jev's answer, with the picture.
        let milliseconds: Int
        /// Capturing and making the JPEG.
        let captureMilliseconds: Int
    }

    /// One decision: with a picture or not, its input tokens, its time.
    struct DecisionCost: Sendable {
        let picture: Bool
        let tokens: Int
        let milliseconds: Int
    }

    /// What the model answered for one step.
    private struct Decision {
        let next: String
        /// Items with their probability, likeliest first.
        var targets: [(id: String, probability: Double)]
        let key: String?
        let risky: Double
        /// The steps done so far complete the goal.
        let finished: Double
        /// Which of the profile's details goes in the field typed into.
        let detail: String?
        /// The goal fills this window's fields with the profile's details.
        let fillsForm: Double
        /// For each field shown: the detail that goes in it.
        let fields: [String: String]
        /// Choosing the next step needs thinking (a move, a puzzle).
        var thinks: Double = 0
    }

    /// A place in the window's picture to click (`pickSpot`).
    private struct Spot {
        let point: CGPoint
        /// The box or small cell found: ringed first.
        let ring: CGRect
        let region: String
        /// The plan's line it was for.
        let meant: String?
    }

    /// How a place in the picture is found: Jev's Box around the thing
    /// (its words: the plan's line, else the goal), or a numbered cell of
    /// a grid over the picture (measured: Jev does not read the numbers
    /// back, docs/click-what-you-see.md).
    enum SpotWay: String, Sendable {
        case box, grid
    }

    /// One spot picked: the first look and the close-up, where, what it
    /// cost ("box 0.41–0.47 × 0.62–0.70 88 %, there 97 %", "cell 53 71 %").
    struct SpotPick: Sendable {
        let way: SpotWay
        let first: String
        let second: String?
        /// On screen, points.
        let point: CGPoint
        let tokens: Int
        let milliseconds: Int
        let meant: String?
    }

    private let keys: [DecisionProvider: String]
    private let selection: SelectionService
    /// Text for a field when the goal quotes none (the writer); nil when the
    /// goal does not say it.
    var write: ((_ goal: String, _ field: ScreenItem, _ typed: [String]) async -> String?)?
    /// The user types it, asked in the card; nil when they cancel.
    var askText: ((_ question: String) async -> String?)?
    /// "Press “Send”?": true to go on.
    var confirm: ((_ question: String) async -> Bool)?
    /// Unsure which item: the user picks; nil when they cancel.
    var choose: ((_ question: String, _ options: [String]) async -> Int?)?
    /// The steps so far, for the card.
    var progress: ((_ steps: [AIPopover.Step]) -> Void)?
    /// Whose details a form gets ("Margot", or the user's own card): the
    /// model reads what each detail is, never its value.
    var profile: (name: String, details: [FormProfile.Detail])?
    /// The card: clicks go through it while the mouse acts.
    weak var cardWindow: NSWindow?
    /// What was done, one line a step ("Clicked button “Save”").
    private(set) var history: [String] = []
    /// The same for the model: a profile's values left out.
    private var told: [String] = []
    /// Values typed from the profile: shown to the model as "filled".
    private var typedDetails: Set<String> = []
    /// "Jev · 0.21 s" for the last decision.
    private(set) var decider = ""
    /// Self-test hook: the last decision, in short ("click, [button 2nd of
    /// 6 in a row 62%], finished 3%, risky 1%").
    private(set) var lastDecision = ""
    /// Self-test hook: what was sent to the decision model, step by step.
    private(set) var sentStates: [String] = []
    /// One request to the decision model, as it went: the self-test
    /// replays it (`keepsRequests`).
    struct SentRequest: Sendable {
        let questions: [DecisionQuestion]
        let state: String
        let picture: JevImages.Image?
        /// The items offered, as the model read them.
        let candidates: [ScreenItem]
        let planLine: String?
    }
    /// Self-test hook: every request kept, its picture too.
    var keepsRequests = false
    private(set) var requests: [SentRequest] = []
    /// Self-test hooks: whether a picture of the window may go at all
    /// (before and after, measured), and whether items without words are
    /// outlined in it with their id. Off: measured on the mini, Jev told
    /// icons apart better from the window as it is, each item named by
    /// its place ("3rd of 6 in a row"), than with outlines and tags
    /// (`selftest sight` keeps measuring both).
    var picturesAllowed = true
    var marksInPicture = false
    /// While Jev looks at the window's picture: the card says so.
    var seeing: ((_ steps: [AIPopover.Step]) -> Void)?
    /// The steps that finish the goal, from the writer, when choosing them
    /// needs thinking (a move in a game, a puzzle): one click or key a line,
    /// as the window names things, a drawn thing by its look and where it
    /// is; `.stuck` when it cannot be done here, `.done` when it is done;
    /// nil when the writer did not answer. Jev grounds each line.
    var plan: ((_ goal: String, _ state: String, _ picture: JevImages.Image?) async -> Plan?)?

    enum Plan: Equatable, Sendable {
        case steps([String])
        case stuck
        case done
    }
    /// While the writer thinks: the card says so.
    var thinking: ((_ steps: [AIPopover.Step]) -> Void)?
    /// Self-test hooks: items left out of what is read (a board hidden to
    /// measure the picture alone), and the fine pick after the coarse one.
    var hides: ((ScreenItem) -> Bool)?
    var fineSpot = true
    var spotWay = SpotWay.box
    /// Each spot picked, and each plan as the writer wrote it.
    private(set) var spots: [SpotPick] = []
    private(set) var plans: [[String]] = []
    /// Self-test hook: a look cut short after this many elements, as an
    /// app slow to answer gives them (nil: read whole); given the steps
    /// done so far.
    var cutsLook: ((_ history: [String]) -> Int?)?
    /// Looks read again for a plan's line whose item was not read.
    private(set) var rereads = 0
    /// The plan followed and its lines done, whether the window changed
    /// since it was made, and whether a line was clicked in the picture
    /// (such a click may not take: the writer checks).
    private var planProgress = PlanProgress()
    private var changedSincePlan = false
    private var spotSincePlan = false
    /// What the last decision was asked: the writer plans from the same.
    private var lastState = ""
    /// Each picture sent, and each decision with what it cost.
    private(set) var pictures: [PictureSent] = []
    private(set) var costs: [DecisionCost] = []
    /// Self-test hook: the last picture sent, as Jev got it.
    private(set) var lastPicture: Data?
    /// It would have read the words on screen and Screen Recording is
    /// off: the card asks for it where it stopped (D7).
    private(set) var missedScreen = false
    private var steps: [AIPopover.Step] = []
    private var pendingTold: String?
    /// Items without words clicked, where, at which step: told to the
    /// model beside the item (its words cannot say what was clicked).
    private var clickedSpots: [(frame: CGRect, step: Int)] = []
    /// Windows whose fields were filled from the card already.
    private var formFilled: Set<String> = []
    /// Sensitive details the user let type in this run: not asked again.
    private var allowedDetails: Set<String> = []
    private let highlight = TargetHighlight()

    static let maxSteps = 12
    /// Plans a run asks the writer for at most.
    static let maxPlans = 3
    /// A plan's line whose item was not read waits this long for it in a
    /// window cut short (Chess answered slowly for about 12 s after a piece
    /// was picked up), each read given `rereadBudget`: a slow app's whole
    /// board at ~150 ms an element.
    static let rereadFor: Duration = .seconds(12)
    static let rereadBudget: Duration = .seconds(6)
    /// None read the line's words, and the decision model is this sure of
    /// another item for it: that item, the line said in other words
    /// ("Click “Save”" for “Enregistrer”). Under it, never another item.
    static let sureOfUnread = 0.6
    /// The target question, and what tells sending from exporting (Jev
    /// once ran "Send PDF" for "export en PDF"). With a plan's line to
    /// follow, the question is that line's item: the guide pulled Jev to
    /// "Partie › Partager › Mail" for a planned chess move, the planned
    /// square down to 20–28 % (docs/click-what-you-see.md, "Grounding a
    /// plan's line").
    static let targetQuestion = "Which item shown is the one to act on next for the goal: the one to click, or the field to type into?"
    static let targetGuide = " Pick what does exactly what the goal says: Send and Share items mail or share it to someone; Save As and Export put a file in a folder."
    static let planTargetQuestion = "Which item shown does the plan's next line act on: the one to click, or the field to type into? Pick the item that line names."

    init(keys: [DecisionProvider: String], selection: SelectionService) {
        self.keys = keys
        self.selection = selection
    }

    func run(goal: String, pid: pid_t) async -> Outcome {
        var quotes = ScreenControl.quotes(in: goal)
        var retried = false
        var savedThrough = false
        // Nothing found to act on: the next look reads the screen too, once.
        var readScreen = false
        var readScreenTried = false
        var typed: [String] = []
        defer { highlight.hide() }
        for _ in 0..<Self.maxSteps {
            guard !Task.isCancelled else { return .cancelled }
            var look = await self.look(pid: pid, goal: goal, readScreen: readScreen)
            readScreen = false
            // The plan's next line clicks an item by its words and this look
            // did not read it: the window read again, or waited for, before
            // anything is clicked (a real Chess game, 2026-10-18: Chess answered 15
            // of its 73 elements in time, “b5” not among them, and a pawn
            // was clicked instead).
            if let line = planLine, let wanted = ScreenControl.unread(by: line, among: look.items) {
                look = await lookAgain(for: wanted, line: line, after: look, pid: pid, goal: goal)
            }
            guard !Task.isCancelled else { return .cancelled }
            guard !look.items.isEmpty else {
                return .stopped("skil.li cannot read \(look.app.isEmpty ? "the window in front" : look.app + "'s window").")
            }
            // Still cut short without it: nothing is decided on a part of
            // the window.
            if look.cutShort, let line = planLine, let wanted = ScreenControl.unread(by: line, among: look.items) {
                return .stopped("\(look.app) answered too slowly: its window was read without “\(wanted)”, the plan's next step. Nothing else was clicked.")
            }
            // A picture can tell apart what words cannot: every item without
            // words is offered with it. A goal that names an item by its
            // words is asked in words first, without them: picked blind, one
            // was Safari's Back button.
            let picturing = mayPicture(look)
            let inWords = ScreenControl.candidates(look.items, goal: goal, limit: 150)
            let wordsFirst = picturing && ScreenControl.goalNames(inWords, goal: goal)
            var candidates = picturing && !wordsFirst ? ScreenControl.candidates(look.items, goal: goal, limit: 150, keepsWordless: true) : inWords
            Log.trace("Control sees in \(look.app) “\(look.window)”: " + candidates.filter { $0.source != .menu }.prefix(80).map { "\($0.id) \($0.description)" }.joined(separator: " | "))
            // What was read says too little: the picture goes with the words.
            var picture: Picture?
            if picturing, !wordsFirst, let need = ScreenControl.pictureNeed(candidates) {
                picture = await self.picture(of: look, pid: pid, candidates: candidates, need: need)
            }
            guard var decision = await decide(goal: goal, look: look, candidates: candidates, picture: picture) else {
                return .stopped("No decision model answered. Add a TypeSafe or OpenAI key in Settings → SI Accounts.")
            }
            // Choosing needs thinking (a move, a puzzle): the writer plans
            // what finishes the goal and Jev grounds each line; planned
            // again once every line was done and the goal is not.
            // Its lines done after clicks in the picture: the writer checks,
            // whatever Jev thinks of it (a click there may have missed).
            let linesDone = planProgress.isFinished
            // A plan written at this step says what is left: Jev's "done"
            // does not end it.
            var planned = false
            if let plan, plans.count < Self.maxPlans, decision.finished < 0.5 || linesDone && spotSincePlan,
               planProgress.isEmpty ? decision.thinks >= 0.5 : linesDone {
                thinking?(steps)
                // The writer sees the window too: what is only drawn, it
                // describes by its look and where it is.
                let shown = mayPicture(look) ? await plainPicture(of: look, pid: pid) : nil
                let started = ContinuousClock.now
                let answer = await plan(goal, lastState, shown)
                Log.trace("Control plan in \((ContinuousClock.now - started).compact)\(shown == nil ? "" : " with a picture"): \(answer.map { "\($0)" } ?? "(no answer)")")
                switch answer {
                case .stuck?:
                    return .stopped("Nothing in \(look.app) does that here.")
                case .done?:
                    return .done
                case .steps(let lines)?:
                    plans.append(lines)
                    planProgress = PlanProgress(lines)
                    changedSincePlan = false
                    spotSincePlan = false
                    planned = true
                    if let again = await decide(goal: goal, look: look, candidates: candidates, picture: picture) { decision = again }
                case nil:
                    break
                }
            }
            // The plan's line quotes an item's exact words ("Click the button
            // “pion blanc, e2”"): that item, whatever Jev ranked first (the
            // same request swung 36–59 % for it); Jev still says what to do.
            var namedByPlan: (item: ScreenItem, ranked: Double)?
            if let line = planLine, let named = ScreenControl.named(by: line, among: candidates, typing: decision.next == "type") {
                namedByPlan = (named, decision.targets.first { $0.id == named.id }?.probability ?? 0)
                decision.targets = [(named.id, 1)] + decision.targets.filter { $0.id != named.id }
            }
            // Read in words, unsure which item: once more with the picture,
            // the items without words offered too.
            if picture == nil, picturing, ScreenControl.isUnsure(next: decision.next, best: decision.targets.first?.probability) {
                let all = ScreenControl.candidates(look.items, goal: goal, limit: 150, keepsWordless: true)
                picture = await self.picture(of: look, pid: pid, candidates: all, need: .unsure)
                if let picture, let again = await decide(goal: goal, look: look, candidates: all, picture: picture) {
                    decision = again
                    candidates = all
                }
            }
            guard !Task.isCancelled else { return .cancelled }
            // A dialog's last button clicked and the dialog gone: done.
            if savedThrough, !look.items.contains(where: { ScreenControl.isFinalSave($0.label) }) { return .done }
            savedThrough = false
            lastDecision = "\(decision.next), \(decision.targets.prefix(3).map { target in "\(candidates.first { $0.id == target.id }.map(Self.name) ?? target.id) \(Int(target.probability * 100))%" }), finished \(Int(decision.finished * 100))%, risky \(Int(decision.risky * 100))%" + (wordsFirst ? ", in words first" : "")
            if let namedByPlan { lastDecision += ", “\(namedByPlan.item.label)” named by the plan (Jev \(Int(namedByPlan.ranked * 100))%)" }
            Log.trace("Control “\(goal)”: \(lastDecision), key \(decision.key ?? "-")")
            // A form from the card: every field at once, where it does not
            // already hold that detail; the next step then reads the result.
            if profile != nil {
                Log.trace("Control form: fills \(Int(decision.fillsForm * 100))%, fields \(decision.fields.map { id, key in "\(candidates.first { $0.id == id }.map(Self.name) ?? id) → \(key)" })")
            }
            if decision.fillsForm >= 0.5, let profile, !decision.fields.isEmpty, !formFilled.contains(look.signature) {
                formFilled.insert(look.signature)
                var filledAny = false
                // Every field and its detail, known together.
                let fills = candidates.compactMap { item -> (item: ScreenItem, detail: FormProfile.Detail, target: Target)? in
                    guard let key = decision.fields[item.id], let detail = profile.details.first(where: { $0.key == key }),
                          item.value != detail.value, let target = look.targets[item.id] else { return nil }
                    return (item, detail, target)
                }
                // The sensitive ones (an IBAN, a BIC) only once the user said
                // so, all in one question: "Type your IBAN and BIC in Safari?".
                var unique = Set<String>()
                let sensitive = fills.map(\.detail).filter { $0.isSensitive && !allowedDetails.contains($0.key) && unique.insert($0.key).inserted }
                if !sensitive.isEmpty {
                    if await confirm?(FormProfile.typingQuestion(sensitive, whose: Self.whose(profile.name), in: look.app)) == true {
                        allowedDetails.formUnion(sensitive.map(\.key))
                    }
                }
                var filled: [ScreenItem] = []
                for (item, detail, target) in fills {
                    guard !detail.isSensitive || allowedDetails.contains(detail.key) else { continue }
                    let line = "Typed “\(detail.value)” in \(Self.name(item))"
                    begin(line)
                    await show(item)
                    await type(detail.value, into: target)
                    typedDetails.insert(detail.value)
                    finish(.done)
                    history.append(line)
                    told.append("Typed \(profile.name)'s \(detail.description.components(separatedBy: " (").first?.lowercased() ?? detail.key) in \(Self.name(item))")
                    filledAny = true
                    filled.append(item)
                }
                highlight.hide()
                if filledAny {
                    planProgress.step(acted: filled)
                    // Filled, not sent: the user sends it, or asked to.
                    if !ScreenControl.asksToSubmit(goal) { return .done }
                    await settle(pid: pid, from: look.signature)
                    continue
                }
            }
            if decision.finished >= 0.5, !planned { return .done }
            // A save dialog up and the place the goal names not chosen yet
            // ("sur mon bureau"): that place first, whatever was picked.
            var place: ScreenItem?
            if ["click", "key"].contains(decision.next), look.items.contains(where: { ScreenControl.isFinalSave($0.label) }),
               let named = ScreenControl.place(in: goal, among: look.items), look.targets[named.id] != nil,
               !history.contains("Clicked \(Self.name(named))") {
                place = named
            }
            var line: String
            // A spot clicked: the picture before, to settle on.
            var pictureBefore: [UInt8]?
            let next = planned && decision.next == "done" && !decision.targets.isEmpty ? "click" : decision.next
            // The plan's line clicks an item no item read is, even read
            // again, and Jev is not sure of another for it: never another
            // item instead. (Planned again, Opus described the square it
            // named as drawn, and Jev pressed squares beside it.)
            let followed = planLine
            if place == nil, let wanted = strays(decision, next: next, line: followed, look: look) {
                return .stopped("“\(wanted)” is not in \(look.app)'s window, the plan's next step: stopped rather than click something else.")
            }
            // Jev sure of an item for a line whose words none reads: that
            // item does the line.
            let grounded = place == nil && followed.flatMap { ScreenControl.unread(by: $0, among: look.items) } != nil
                && ["click", "type"].contains(next) && decision.targets.first.map { $0.id != ScreenControl.spotID } == true
            // What the step acted on, for the plan's line (`PlanProgress`);
            // a scroll does no line.
            var acted: [ScreenItem] = []
            var spotted = false
            var doesLine = true
            switch place == nil ? next : "click" {
            case "done":
                return .done
            case "stuck":
                // The window may still be drawing (a dialog sliding in): one
                // more look after a pause before giving up.
                if !retried {
                    retried = true
                    readScreen = ScreenSight.isAllowed
                    if !readScreen { missedScreen = true }
                    try? await Task.sleep(for: .milliseconds(800))
                    continue
                }
                return .stopped(history.isEmpty ? "Nothing in \(look.app) does that here." : "Stopped: the rest cannot be done here.")
            case "scroll" where !readScreenTried && ScreenSight.isAllowed:
                // Not shown in what Accessibility lists: maybe drawn on
                // screen without it. The words on screen first, then scroll.
                readScreen = true
                readScreenTried = true
                continue
            case "scroll":
                if !readScreenTried { missedScreen = true }
                let frames = look.items.compactMap(\.frame)
                guard let first = frames.first else { return .stopped("Nothing to scroll.") }
                let frame = frames.dropFirst().reduce(first) { $0.union($1) }
                line = "Scrolled down"
                begin(line)
                scroll(at: CGPoint(x: frame.midX, y: frame.midY))
                doesLine = false
            case "click" where place == nil && decision.targets.first?.id == ScreenControl.spotID && mayPicture(look):
                // Only drawn (a board, a map): a place in the picture; the
                // click settles on the picture.
                guard let spot = await pickSpot(goal: goal, look: look, pid: pid), let frame = look.frame else {
                    return .stopped("Found nothing to click for that in the picture.")
                }
                if decision.risky >= 0.5 || ScreenControl.isRisky(goal) {
                    highlight.show(spot.ring)
                    if await confirm?("Click the place ringed in \(look.app)? It may \(Self.riskWords(goal)).") != true {
                        return .stopped("Stopped before clicking it.")
                    }
                }
                line = "Clicked in the picture (\(spot.region))" + (spot.meant.map { ": \($0)" } ?? "")
                begin(line)
                highlight.show(spot.ring)
                try? await Task.sleep(for: .milliseconds(220))
                pictureBefore = await Self.within(.seconds(1)) { await ScreenSight.capture(pid: pid, window: frame) }?
                    .map { PictureChange.thumbnail($0.image) }
                await click(at: spot.point)
                spotSincePlan = true
                spotted = true
            case "key":
                guard let key = decision.key else { return .stopped("No key fits.") }
                if key == "return", decision.risky >= 0.5, await confirm?("Press Return? It may \(Self.riskWords(goal)).") != true {
                    return .stopped("Stopped before pressing Return.")
                }
                line = "Pressed \(Self.keyTitle(key))"
                begin(line)
                press(key)
            default:
                // Click or type: on which item.
                let picked: String?
                if let place {
                    picked = place.id
                } else {
                    picked = await pick(decision, goal: goal, candidates: candidates, typing: decision.next == "type")
                }
                guard let id = picked, let item = candidates.first(where: { $0.id == id }) ?? look.items.first(where: { $0.id == id }),
                      let target = look.targets[id] else {
                    if Task.isCancelled { return .cancelled }
                    // What Accessibility listed has nothing for it: the
                    // words on screen too, then decide again.
                    if !readScreenTried, ScreenSight.isAllowed {
                        readScreen = true
                        readScreenTried = true
                        continue
                    }
                    if !readScreenTried { missedScreen = true }
                    return .stopped("Found nothing to \(decision.next == "type" ? "type into" : "press") for that.")
                }
                if decision.next == "type" && item.isField {
                    guard item.role != "password field" else { return .stopped("skil.li does not type passwords: type it yourself.") }
                    let text: String
                    var toldLine: String?
                    if !quotes.isEmpty {
                        text = quotes.removeFirst()
                    } else if let key = decision.detail, let detail = profile?.details.first(where: { $0.key == key }) {
                        // Only known at this step: asked here, unless allowed
                        // already in this run.
                        if detail.isSensitive, !allowedDetails.contains(detail.key) {
                            guard await confirm?("Type \(Self.whose(profile?.name ?? "the user")) \(detail.name) in \(Self.name(item))?") == true else {
                                return .stopped("Stopped before typing \(detail.name).")
                            }
                            allowedDetails.insert(detail.key)
                        }
                        text = detail.value
                        typedDetails.insert(detail.value)
                        toldLine = "Typed \(profile?.name ?? "the user")'s \(detail.description.components(separatedBy: " (").first?.lowercased() ?? key) in \(Self.name(item))"
                    } else if let written = await write?(goal, item, typed) {
                        text = written
                    } else if let answered = await askText?("What should I type in \(Self.name(item))?") {
                        text = answered
                    } else {
                        return .cancelled
                    }
                    line = "Typed “\(text)” in \(Self.name(item, among: candidates))"
                    begin(line)
                    await show(item)
                    await type(text, into: target)
                    acted = [item]
                    typed.append(toldLine == nil ? text : "(a detail)")
                    pendingTold = toldLine
                } else {
                    let label = item.source == .menu ? (item.label.components(separatedBy: " › ").last ?? item.label) : item.label
                    if ScreenControl.isRisky(label), await confirm?("Press “\(label)” in \(look.app)?") != true {
                        return .stopped("Stopped before “\(label)”.")
                    }
                    // The same icon again, right after: done (an icon often
                    // toggles; a second press would take the first back).
                    if item.isWordless, let frame = item.frame, let last = clickedSpots.last, last.step == told.count,
                       abs(last.frame.midX - frame.midX) < 3, abs(last.frame.midY - frame.midY) < 3 {
                        return .done
                    }
                    // Without words (an icon picked from the picture) for a
                    // goal that cannot be taken back: ringed, then asked.
                    if item.isWordless, decision.risky >= 0.5 || ScreenControl.isRisky(goal) {
                        await show(item)
                        if await confirm?("Press the \(item.role) ringed in \(look.app)? It may \(Self.riskWords(goal)).") != true {
                            return .stopped("Stopped before pressing it.")
                        }
                    }
                    savedThrough = ScreenControl.isFinalSave(item.label)
                    line = item.source == .menu ? "Chose \(item.label)" : "Clicked \(Self.name(item, among: candidates))"
                    // The same menu item again: the goal was done, or it is going round.
                    if item.source == .menu, history.contains(line) {
                        return .done
                    }
                    begin(line)
                    await show(item)
                    await press(target, item: item)
                    acted = [item]
                    if item.isWordless, let frame = item.frame { clickedSpots.append((frame, told.count + 1)) }
                }
            }
            highlight.hide()
            finish(.done)
            // Doing the same thing again and again: it is not working.
            if history.suffix(2).allSatisfy({ $0 == line }), history.count >= 2 {
                return .stopped("It keeps doing “\(line)”: stopped.")
            }
            readScreenTried = false
            history.append(line)
            told.append(pendingTold ?? line)
            pendingTold = nil
            // A line is done only by a step that did what it says.
            if doesLine, let followed, !planProgress.step(acted: acted, spot: spotted, grounded: grounded) {
                Log.trace("Control “\(line)” did not do the plan's line “\(followed)”: it stays next")
            }
            let changed: Bool
            if let pictureBefore, let frame = look.frame {
                changed = await settlePicture(pid: pid, window: frame, from: pictureBefore)
            } else {
                changed = await settle(pid: pid, from: look.signature)
            }
            if changed { changedSincePlan = true }
            // Every line of the plan done and the window changed: the plan
            // was what finishes the goal (planned again, a quick app had
            // already answered and a second move was played). Lines clicked
            // in the picture may have missed: the writer looks again first
            // (DONE, or what is left).
            if planProgress.isFinished, changedSincePlan, !spotSincePlan { return .done }
        }
        return .stopped("Stopped after \(Self.maxSteps) steps.")
    }

    // MARK: - Seeing

    /// The window in front as one step sees it: its elements read in
    /// `budget`, the app's menu items (`menus`: those of a look before).
    private func look(pid: pid_t, goal: String, readScreen: Bool = false, budget: Duration = .seconds(2),
                      menus kept: [MenuReader.Item]? = nil) async -> Look {
        // skil.li's own windows on the main thread (see UIReader.snapshot).
        let own = pid == getpid()
        let start = ContinuousClock.now
        let nothing: (app: String, window: String, frame: CGRect?, elements: [UIReader.Element], cutShort: Bool) = ("", "", nil, [], false)
        var snapshot = own ? UIReader.snapshot(pid: pid)
            : await Self.within(budget + .seconds(1)) { UIReader.snapshot(pid: pid, budget: budget) } ?? nothing
        if let cut = cutsLook?(history), snapshot.elements.count > cut {
            snapshot.elements = Array(snapshot.elements.prefix(cut))
            snapshot.cutShort = true
        }
        let read = ContinuousClock.now
        var menus: [MenuReader.Item] = []
        if let kept {
            menus = kept
        } else if !own {
            menus = await Self.within(.milliseconds(2_500)) { MenuReader.shareableItems(pid: pid) } ?? []
        }
        let menusRead = ContinuousClock.now
        defer {
            Log.trace("Control look: \(snapshot.elements.count) elements in \((read - start).compact)\(snapshot.cutShort ? " (cut short)" : ""), "
                + (kept == nil ? "\(menus.count) menu items in \((menusRead - read).compact)" : "menus kept") + ", all in \((ContinuousClock.now - start).compact)")
        }
        var look = Look(app: snapshot.app, window: snapshot.window, frame: snapshot.frame, cutShort: snapshot.cutShort, menus: menus)
        look.signature = Self.signature(snapshot.window, snapshot.elements)
        func region(_ frame: CGRect?) -> String {
            guard let frame, let window = snapshot.frame else { return "" }
            return ScreenControl.region(of: frame, in: window)
        }
        var found: [(item: ScreenItem, target: Target)] = snapshot.elements.map { element in
            (ScreenItem(id: "", source: .element, role: element.role, label: element.label, value: element.value, enabled: element.enabled,
                        frame: element.frame, region: region(element.frame)), .element(element))
        }
        // Little told to Accessibility (a canvas, some web views), or icons
        // without words a picture would show: the words on screen too, where
        // they are (the same capture goes as the picture). A drawn word the
        // goal names is then found in words.
        let wordless = picturesAllowed && found.contains { $0.item.isWordless }
        if readScreen || wordless || found.filter({ $0.item.role != "text" }).count < 6, let window = snapshot.frame {
            let read = await Self.within(.seconds(3)) { await ScreenSight.lines(pid: pid, window: window) }
            look.capture = read?.capture
            let words = (read?.lines ?? []).map { line in
                ScreenItem(id: "", source: .text, role: "text on screen", label: line.text, frame: line.frame, region: region(line.frame))
            }
            let kept = ScreenControl.merge(elements: found.map(\.item), text: words).dropFirst(found.count)
            found += kept.compactMap { item in item.frame.map { (item, Target.words($0)) } }
        }
        if let hides { found.removeAll { hides($0.item) } }
        found += menus.prefix(200).map { menu in
            (ScreenItem(id: "", source: .menu, role: "menu item", label: MenuCandidates.display(menu.components)), .menu(menu))
        }
        for (index, entry) in found.enumerated() {
            let id = "i\(index + 1)"
            let item = entry.item
            look.items.append(ScreenItem(id: id, source: item.source, role: item.role, label: item.label, value: item.value,
                                         enabled: item.enabled, frame: item.frame, region: item.region))
            look.targets[id] = entry.target
        }
        return look
    }

    /// `first` did not read `wanted`, the item the plan's next `line`
    /// clicks by its words: the window read again until it does. Cut short
    /// (an app slow to answer), again and again with more time, for
    /// `rereadFor` at most; read whole, once after a moment (still
    /// drawing). The last look.
    private func lookAgain(for wanted: String, line: String, after first: Look, pid: pid_t, goal: String) async -> Look {
        let start = ContinuousClock.now
        var look = first
        var tries = 0
        seeing?(steps)
        while !Task.isCancelled, look.cutShort ? ContinuousClock.now - start < Self.rereadFor : tries == 0 {
            tries += 1
            rereads += 1
            try? await Task.sleep(for: .milliseconds(look.cutShort ? 300 : 800))
            look = await self.look(pid: pid, goal: goal, budget: Self.rereadBudget, menus: first.menus)
            if ScreenControl.unread(by: line, among: look.items) == nil { break }
        }
        let found = ScreenControl.unread(by: line, among: look.items) == nil
        Log.trace("Control read \(look.app) again \(tries)× for “\(wanted)” in \((ContinuousClock.now - start).compact): "
            + (found ? "read" : look.cutShort ? "still cut short" : "not shown"))
        return look
    }

    /// What the plan's `line` clicks by its words, when no item `look` read
    /// is it and Jev would click or type into another item it is not sure
    /// of (under `sureOfUnread`; a place in the picture aside: what is only
    /// drawn is no item); nil otherwise.
    private func strays(_ decision: Decision, next: String, line: String?, look: Look) -> String? {
        guard let line, let wanted = ScreenControl.unread(by: line, among: look.items),
              ["click", "type"].contains(next), let best = decision.targets.first,
              best.id != ScreenControl.spotID, best.probability < Self.sureOfUnread else { return nil }
        return wanted
    }

    private static func signature(_ window: String, _ elements: [UIReader.Element]) -> String {
        window + "\n" + elements.map { "\($0.role)|\($0.label)|\($0.value ?? "")|\($0.enabled)" }.joined(separator: "\n")
    }

    /// Until the window changed after a step and stays still for 300 ms
    /// (a dialog slides in, a value reads back), 2.5 s at most: the next
    /// step reads what the last one did, drawn. Whether it changed.
    @discardableResult
    private func settle(pid: pid_t, from signature: String) async -> Bool {
        let start = ContinuousClock.now
        let deadline = start + .milliseconds(2_500)
        var last = signature
        var stillSince: ContinuousClock.Instant?
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            let own = pid == getpid()
            guard let snapshot = own ? UIReader.snapshot(pid: pid) : await Self.within(.seconds(3), { UIReader.snapshot(pid: pid) }) else { return last != signature }
            let now = Self.signature(snapshot.window, snapshot.elements)
            if now != last {
                last = now
                stillSince = ContinuousClock.now
            } else if let since = stillSince, ContinuousClock.now - since >= .milliseconds(300) {
                return true
            } else if stillSince == nil, ContinuousClock.now - start >= .milliseconds(1_500) {
                // Nothing changed at all: the step showed nothing.
                return false
            }
        }
        return last != signature
    }

    /// `work`'s result, or nil once `limit` passed first: a system call that
    /// does not return (an app or the window server stuck) leaves the run
    /// going with what it has. The work finishes on its own.
    nonisolated static func within<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = OSAllocatedUnfairLock(initialState: false)
            func resume(_ value: T?) {
                if gate.withLock({ done in defer { done = true }; return !done }) { continuation.resume(returning: value) }
            }
            Task.detached(priority: .userInitiated) { resume(await work()) }
            Task.detached { try? await Task.sleep(for: limit); resume(nil) }
        }
    }

    // MARK: - Deciding

    private func decide(goal: String, look: Look, candidates: [ScreenItem], picture: Picture? = nil) async -> Decision? {
        var state = "Goal: \(goal)\nApp: \(look.app)" + (look.window.isEmpty ? "" : ", window “\(look.window)”")
        state += told.isEmpty ? "\nDone so far: nothing yet" : "\nDone so far:\n" + told.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        if let next = nextPlanLine {
            state += "\nPlan for the goal, thought through by another model (follow it, one line a step):\n"
                + planProgress.lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            state += "\nNext in the plan: " + next
        }
        // What skil.li typed from a profile reads "filled": values stay here.
        let hidden = typedDetails.union(profile?.details.map(\.value) ?? [])
        let candidates = candidates.map { item in
            guard let value = item.value, hidden.contains(value) else { return item }
            return ScreenItem(id: item.id, source: item.source, role: item.role, label: item.label, value: "(filled)",
                              enabled: item.enabled, frame: item.frame, region: item.region)
        }
        // Items outlined in the picture say so: their id is drawn there.
        let marked = picture?.marked ?? []
        func describe(_ item: ScreenItem) -> String {
            var text = item.description
            if let place = ScreenControl.rowPlace(of: item, among: candidates) { text += " · \(place)" }
            if marked.contains(item.id) { text += " · outlined as \(item.id) in the picture" }
            // An icon clicked before: which one the steps cannot say.
            if item.isWordless, let frame = item.frame,
               let spot = clickedSpots.last(where: { abs($0.frame.midX - frame.midX) < 3 && abs($0.frame.midY - frame.midY) < 3 }) {
                text += " · clicked at step \(spot.step)"
            }
            return text
        }
        state += "\nShown now (id: item · where):\n" + candidates.map { "\($0.id): \(describe($0))" }.joined(separator: "\n")
        lastState = state
        let seen = picture == nil ? "" : " (`window_picture` is a picture of it)"
        let looks = picture == nil ? "" : marked.isEmpty ? " `window_picture` shows how the window looks."
            : " `window_picture` shows how the window looks; each item without words is outlined there in magenta, its id written in white on a magenta tag just above it: pick the one whose icon does what the goal says."
        let questions: [DecisionQuestion] = [
            DecisionQuestion(name: "next", instructions: "The user wants the goal done in this app. Given what was done so far and what the window shows now\(seen), what is the next step?", options: [
                .init(value: "click", description: "Click or press one item shown: a button, a link, a tab, a checkbox, a switch, a menu item, a row"),
                .init(value: "type", description: "Type text into one field shown that does not hold yet what the goal asks for"),
                .init(value: "key", description: "Press a key: Return to confirm, search or send, Escape to close, Tab to move on, or a keyboard shortcut"),
                .init(value: "scroll", description: "Scroll down: what the goal needs is not shown yet"),
                .init(value: "done", description: "Nothing is left to do: every part of the goal was done, or the window already shows it done"),
                .init(value: "stuck", description: "The goal cannot be done here: what it needs is neither shown nor in the menus, or only the user can do it (a password, a choice of theirs)")
            ]),
            DecisionQuestion(name: "target", instructions: (planLine == nil ? Self.targetQuestion + Self.targetGuide : Self.planTargetQuestion) + looks,
                             options: candidates.map { .init(value: $0.id, description: describe($0)) }
                                + (picture == nil ? [] : [.init(value: ScreenControl.spotID, description: "A place in the window's picture: something drawn there that no item above names (a board, a map, a photo, a canvas)")])
                                + [.init(value: "none", description: "None of these items")]),
            DecisionQuestion(name: "key", instructions: "If a key is to be pressed next for the goal, which one?",
                             options: Self.keyOptions.map { .init(value: $0.0, description: $0.1) } + [.init(value: "none", description: "No key")]),
            DecisionQuestion(name: "finished", instructions: "Do the steps done so far already complete the whole goal? A dialog's final button (Save, Enregistrer, Export, Exporter, Send, OK) clicked after its choices finishes what that dialog was opened for; the window then looks as it did before.", options: [
                .init(value: "yes", description: "Yes: every part of the goal was done by the steps so far"),
                .init(value: "no", description: "No: something the goal asks is still to do")
            ]),
            DecisionQuestion(name: "risky", instructions: "Does the goal ask for something that cannot be taken back once done: sending a message or a mail, posting or publishing, deleting, buying, paying, transferring money?", options: [
                .init(value: "yes", description: "Yes, the goal does something that cannot be taken back"),
                .init(value: "no", description: "No")
            ])
        ]
        var asked = questions
        // Before a plan: whether one is needed.
        if plan != nil, planProgress.isEmpty {
            asked.append(DecisionQuestion(name: "thinks", instructions: "Is choosing the next step a matter of reasoning a model must think through (a move in a game, a puzzle, a calculation, picking the best of many valid options), rather than finding the item the goal names?", options: [
                .init(value: "yes", description: "Yes: what to do next has to be worked out first"),
                .init(value: "no", description: "No: the goal says what to click, type or press, or it is plain from the window")
            ]))
        }
        // Fields with a name: a save dialog's file names are fields too.
        let fields = candidates.filter { $0.isField && $0.role != "password field" && $0.enabled && !$0.label.isEmpty }.prefix(20)
        if let profile, !profile.details.isEmpty {
            let details: [DecisionQuestion.Option] = profile.details.map { .init(value: $0.key, description: $0.description) }
                + [.init(value: "none", description: "None of these details")]
            asked.append(DecisionQuestion(
                name: "detail",
                instructions: "If text is to be typed next into the target field, which of \(profile.name)'s details goes in it? Answer none when the field asks for something else, or when nothing is to be typed.",
                options: details))
            // The whole form in the same request: one question a field.
            if !fields.isEmpty {
                asked.append(DecisionQuestion(name: "fillsForm", instructions: "Does the goal ask to fill this window's fields with \(profile.name)'s details (name, email, phone, address…)?", options: [
                    .init(value: "yes", description: "Yes, fill the fields with those details"),
                    .init(value: "no", description: "No")
                ]))
                for field in fields {
                    asked.append(DecisionQuestion(name: "field_\(field.id)", instructions: "Which of \(profile.name)'s details goes in this field: \(field.description)? Answer none when it asks for something else.",
                                                  options: details))
                }
            }
        }
        sentStates.append(state + (picture == nil ? "" : "\n[a picture of the window]") + "\n"
            + asked.map { "\($0.instructions) " + $0.options.map(\.description).joined(separator: " | ") }.joined(separator: "\n"))
        if keepsRequests {
            requests.append(SentRequest(questions: asked, state: state, picture: picture?.image, candidates: candidates, planLine: planLine))
        }
        for provider in [DecisionProvider.typeSafe, .openAI] {
            guard let key = keys[provider] else { continue }
            // Only Jev sees the picture; OpenAI decides from the words.
            let shown = provider == .typeSafe ? picture : nil
            let start = ContinuousClock.now
            do {
                let reply = try await DecisionClient.reply(asked, input: state, picture: shown?.image, provider: provider, key: key)
                let answers = reply.answers
                guard let next = answers["next"]?.choice else { continue }
                let elapsed = ContinuousClock.now - start
                let milliseconds = Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                costs.append(DecisionCost(picture: shown != nil, tokens: reply.inputTokens, milliseconds: milliseconds))
                if let shown {
                    pictures.append(PictureSent(need: shown.need, width: Int(shown.size.width), height: Int(shown.size.height),
                                                bytes: shown.image.data.count, marks: shown.marked.count, tokens: reply.inputTokens,
                                                milliseconds: milliseconds, captureMilliseconds: shown.captureMilliseconds))
                    Log.trace("Control picture (\(shown.need.rawValue)): \(Int(shown.size.width))×\(Int(shown.size.height)), \(shown.image.data.count / 1024) KB, \(shown.marked.count) outlined, made in \(shown.captureMilliseconds) ms; Jev \(reply.inputTokens) tokens in \(milliseconds) ms")
                }
                decider = "\(provider == .typeSafe ? "Jev" : "Decisions") · \(elapsed.compact)" + (shown == nil ? "" : " · with a picture")
                let targets = (answers["target"]?.probabilities ?? [:]).filter { $0.key != "none" && $0.value > 0 }
                    .sorted { $0.value > $1.value }.map { (id: $0.key, probability: $0.value) }
                let key = answers["key"]?.choice
                func yes(_ name: String) -> Double { answers[name]?.probabilities["yes"] ?? (answers[name]?.choice == "yes" ? 1 : 0) }
                let detail = answers["detail"]?.choice
                var fieldDetails: [String: String] = [:]
                for field in fields {
                    // A sure answer only: an unsure field is left for the steps.
                    if let answer = answers["field_\(field.id)"], answer.choice != "none", (answer.probabilities[answer.choice] ?? answer.confidence) >= 0.5 {
                        fieldDetails[field.id] = answer.choice
                    }
                }
                return Decision(next: next, targets: targets, key: key == "none" ? nil : key, risky: yes("risky"),
                                finished: history.isEmpty ? 0 : yes("finished"), detail: detail == "none" ? nil : detail,
                                fillsForm: yes("fillsForm"), fields: fieldDetails, thinks: yes("thinks"))
            } catch {
                Log.actions.error("Control decision by \(provider.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    // MARK: - The window's picture

    /// A picture may go: Screen Recording on, a TypeSafe key (only Jev
    /// sees pictures), the window's place known, no password field shown
    /// and no Secure Input on.
    private func mayPicture(_ look: Look) -> Bool {
        picturesAllowed && keys[.typeSafe] != nil && look.frame != nil && ScreenSight.isAllowed
            && ScreenControl.mayPicture(look.items) && !IsSecureEventInputEnabled()
    }

    /// The window in front, captured (or the capture its words were read
    /// in), as the JPEG Jev gets: that window only, 512 to 1024 px.
    private func picture(of look: Look, pid: pid_t, candidates: [ScreenItem], need: ScreenControl.PictureNeed) async -> Picture? {
        guard let frame = look.frame else { return nil }
        let start = ContinuousClock.now
        var capture = look.capture
        if capture == nil {
            capture = await Self.within(.seconds(2)) { await ScreenSight.capture(pid: pid, window: frame) } ?? nil
        }
        guard let capture else { return nil }
        let marks = marksInPicture ? WindowPicture.marks(candidates, window: capture.frame) : []
        let data = await Task.detached(priority: .userInitiated) {
            WindowPicture.jpeg(capture.image, window: capture.frame, marks: marks)
        }.value
        guard let data else { return nil }
        let layout = WindowPicture.layout(pixels: CGSize(width: capture.image.width, height: capture.image.height),
                                          longest: WindowPicture.longest(forPoints: capture.frame.size))
        let elapsed = ContinuousClock.now - start
        lastPicture = data
        seeing?(steps)
        return Picture(image: JevImages.Image(reference: WindowPicture.reference(), data: data, format: "jpeg"),
                       marked: Set(marks.map(\.id)), need: need, size: layout.canvas,
                       captureMilliseconds: Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000))
    }

    /// The window as it is, for the writer's plan.
    private func plainPicture(of look: Look, pid: pid_t) async -> JevImages.Image? {
        guard let frame = look.frame else { return nil }
        var capture = look.capture
        if capture == nil {
            capture = await Self.within(.seconds(2)) { await ScreenSight.capture(pid: pid, window: frame) } ?? nil
        }
        guard let capture else { return nil }
        let data = await Task.detached(priority: .userInitiated) { WindowPicture.jpeg(capture.image, window: capture.frame) }.value
        return data.map { JevImages.Image(reference: WindowPicture.reference(), data: $0, format: "jpeg") }
    }

    // MARK: - A place in the picture

    /// The plan's line for the next step; nil without a plan, a marker once
    /// every line was done.
    private var nextPlanLine: String? {
        guard !planProgress.isEmpty else { return nil }
        return planLine ?? "nothing: every line of it was done"
    }

    /// The plan's line to follow now; nil without a plan or once every
    /// line was done.
    private var planLine: String? {
        planProgress.next
    }

    /// Self-test hook: where the spot pick would click for `goal` in the
    /// window in front, without clicking.
    func locate(goal: String, pid: pid_t) async -> CGPoint? {
        let look = await look(pid: pid, goal: goal)
        return await pickSpot(goal: goal, look: look, pid: pid)?.point
    }

    /// Where to click something only drawn, in two looks: the window's
    /// picture, then a close-up around what the first look found, at the
    /// capture's own pixels. Jev's Box, or (`spotWay`, measured) a numbered
    /// cell of a grid then a small cell of a finer one (`CanvasGrid`). Nil
    /// when it is not in the picture.
    private func pickSpot(goal: String, look: Look, pid: pid_t) async -> Spot? {
        guard let key = keys[.typeSafe], let frame = look.frame else { return nil }
        var capture = look.capture
        if capture == nil {
            capture = await Self.within(.seconds(2)) { await ScreenSight.capture(pid: pid, window: frame) } ?? nil
        }
        guard let capture else { return nil }
        let start = ContinuousClock.now
        var state = "Goal: \(goal)\nApp: \(look.app)" + (look.window.isEmpty ? "" : ", window “\(look.window)”")
        state += told.isEmpty ? "\nDone so far: nothing yet" : "\nDone so far:\n" + told.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let meant = planProgress.isEmpty ? nil : nextPlanLine
        if let meant { state += "\nNext step, decided already: \(meant)" }
        seeing?(steps)
        let found = switch spotWay {
        case .box: await boxSpot(state: state, meant: meant, capture: capture, key: key)
        case .grid: await gridSpot(state: state, meant: meant, capture: capture, key: key)
        }
        guard let found else { return nil }
        let elapsed = ContinuousClock.now - start
        let milliseconds = Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        spots.append(SpotPick(way: spotWay, first: found.first, second: found.second, point: found.point, tokens: found.tokens,
                              milliseconds: milliseconds, meant: meant))
        Log.trace("Control spot (\(spotWay.rawValue)): \(found.first)" + (found.second.map { ", then \($0)" } ?? "")
            + " → \(found.point) in \(elapsed.compact), \(found.tokens) tokens" + (meant.map { " for “\($0)”" } ?? ""))
        return Spot(point: found.point, ring: found.ring.insetBy(dx: -3, dy: -3), region: ScreenControl.region(of: found.ring, in: capture.frame), meant: meant)
    }

    private typealias Found = (point: CGPoint, ring: CGRect, first: String, second: String?, tokens: Int)

    /// The first look's longest side: TypeSafe's most.
    static let boxSide = 1568
    /// Under this, Jev's Noul says the thing is not in the picture.
    static let thereFrom = 0.2

    /// Jev's Box around the thing, in the window's picture (up to 1568 px,
    /// TypeSafe's most: small things stay seen), then again in a close-up
    /// three times its size (160 pt at least); the click goes to the box's
    /// middle. The close-up's box counts only when Jev is sure enough of it
    /// and it lies about where the first one was: measured, a close-up
    /// guess (14 %) elsewhere once replaced a right first box (57 %).
    private func boxSpot(state: String, meant: String?, capture: ScreenSight.Capture, key: String) async -> Found? {
        let window = capture.frame
        let target = meant.map { "what this step clicks, in `window_picture`: \($0)" } ?? "the thing to click next in `window_picture` for the goal in `step`"
        let presence = meant.map { "Does `window_picture` show what this step clicks: \($0)?" }
            ?? "Does `window_picture` show the thing to click next for the goal in `step`?"
        let longest = min(Self.boxSide, max(WindowPicture.longest(forPoints: window.size), Int(max(window.width, window.height) * 2)))
        let layout = WindowPicture.layout(pixels: CGSize(width: capture.image.width, height: capture.image.height), longest: longest)
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            WindowPicture.jpeg(capture.image, window: window, longest: longest)
        }).value,
              let first = await locate(state + "\n`window_picture` shows the window.", picture: data, target: target, presence: presence, key: key)
        else { return nil }
        let firstLine = Self.describe(first)
        guard first.present >= Self.thereFrom else {
            Log.trace("Control spot (box): not in the picture, \(firstLine)")
            return nil
        }
        var rect = WindowPicture.unplace(first.box, window: window, layout: layout)
        var tokens = first.inputTokens
        var second: String?
        if fineSpot {
            let side = max(160, max(rect.width, rect.height) * 3)
            let area = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            if let close = await Task.detached(priority: .userInitiated, operation: {
                WindowPicture.closeUp(capture.image, window: window, area: area)
            }).value, let again = await locate(state + "\n`window_picture` is a close-up of the part of the window around it.", picture: close.data,
                                               target: target, presence: presence, key: key) {
                tokens += again.inputTokens
                second = Self.describe(again)
                let closer = WindowPicture.unplace(again.box, window: close.shown, layout: close.layout)
                let near = rect.insetBy(dx: -rect.width / 2, dy: -rect.height / 2).contains(CGPoint(x: closer.midX, y: closer.midY))
                if again.present >= Self.thereFrom, again.confidence >= 0.3, near {
                    rect = closer
                } else {
                    second? += " (kept the first)"
                }
            }
        }
        return (CGPoint(x: rect.midX, y: rect.midY), rect, firstLine, second, tokens)
    }

    /// "box 0.41–0.47 × 0.62–0.70 88 %, there 97 %".
    private static func describe(_ found: JevImages.Located) -> String {
        func two(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
        return "box \(two(found.box.minX))–\(two(found.box.maxX)) × \(two(found.box.minY))–\(two(found.box.maxY)) \(Int(found.confidence * 100)) %, there \(Int(found.present * 100)) %"
    }

    private func locate(_ state: String, picture: Data, target: String, presence: String, key: String) async -> JevImages.Located? {
        let image = JevImages.Image(reference: WindowPicture.reference(), data: picture, format: "jpeg")
        do {
            return try await JevImages.locate(state: ["step": state, "window_picture": image.reference], images: [image], target: target,
                                              presence: presence, key: key)
        } catch {
            Log.actions.error("Control spot by Jev failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// A numbered cell of a grid over the window's picture, then a small
    /// cell of a finer grid over the 3 × 3 cells around it.
    private func gridSpot(state: String, meant: String?, capture: ScreenSight.Capture, key: String) async -> Found? {
        let window = capture.frame
        let coarse = CanvasGrid.over(window)
        let what = meant.map { "what this step clicks (\($0))" } ?? "what to click next for the goal"
        guard let coarseData = await Task.detached(priority: .userInitiated, operation: {
            WindowPicture.jpeg(capture.image, window: window, grid: coarse)
        }).value, let first = await askCell(state + "\nNow: one click on something drawn in the window. `window_picture` shows the window with a grid of numbered cells over it: magenta lines, each cell's number on a magenta tag in its top left corner.",
                                             question: "Which cell holds the middle of \(what)?", grid: coarse, picture: coarseData, key: key),
              let best = first.cell, var point = coarse.point(best), var ring = coarse.rect(best) else { return nil }
        var tokens = first.tokens
        var second: String?
        if fineSpot, let area = coarse.around(best, within: window) {
            let grid = CanvasGrid.over(area, side: CanvasGrid.fineSide)
            if let close = await Task.detached(priority: .userInitiated, operation: {
                WindowPicture.closeUp(capture.image, window: window, area: area, grid: grid)
            }).value, let again = await askCell(state + "\nNow: one click on something drawn in the window. `window_picture` is a close-up of the part of the window around it, with a finer grid of numbered cells over it: magenta lines, each cell's number on a magenta tag in its top left corner.",
                                                question: "Which cell holds the middle of \(what)?", grid: grid, picture: close.data, key: key) {
                tokens += again.tokens
                second = again.cell.map { "cell \($0) \(Int(again.probability * 100)) %" } ?? "none"
                if let cell = again.cell, let middle = grid.point(cell), let rect = grid.rect(cell) {
                    point = middle
                    ring = rect
                }
            }
        }
        return (point, ring, "cell \(best) \(Int(first.probability * 100)) %", second, tokens)
    }

    /// One cell of `grid` from Jev with its picture; nil when it did not
    /// answer, a nil cell when it says the thing is not there.
    private func askCell(_ state: String, question: String, grid: CanvasGrid, picture: Data, key: String) async
        -> (cell: Int?, probability: Double, tokens: Int)? {
        let image = JevImages.Image(reference: WindowPicture.reference(), data: picture, format: "jpeg")
        let cells = DecisionQuestion(name: "cell", instructions: question,
                                     options: grid.numbers.map { .init(value: "\($0)", description: grid.describe($0)) }
                                        + [.init(value: "none", description: "None: it is not in the picture")])
        do {
            let reply = try await DecisionClient.reply([cells], input: state, picture: image, provider: .typeSafe, key: key)
            guard let answer = reply.answers["cell"] else { return nil }
            return (Int(answer.choice), answer.probabilities[answer.choice] ?? answer.confidence, reply.inputTokens)
        } catch {
            Log.actions.error("Control spot by Jev failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// After a click on something drawn: until the window's picture changed
    /// and holds still 300 ms, 2.5 s at most (its Accessibility does not
    /// move when a canvas redraws).
    @discardableResult
    private func settlePicture(pid: pid_t, window: CGRect, from before: [UInt8]) async -> Bool {
        let start = ContinuousClock.now
        var last = before
        var stillSince: ContinuousClock.Instant?
        while ContinuousClock.now - start < .milliseconds(2_500) {
            try? await Task.sleep(for: .milliseconds(120))
            guard let capture = await Self.within(.seconds(1), { await ScreenSight.capture(pid: pid, window: window) }) ?? nil else { return stillSince != nil }
            let now = PictureChange.thumbnail(capture.image)
            if PictureChange.differs(last, now) {
                last = now
                stillSince = ContinuousClock.now
            } else if let since = stillSince, ContinuousClock.now - since >= .milliseconds(300) {
                return true
            } else if stillSince == nil, ContinuousClock.now - start >= .milliseconds(1_500) {
                return false
            }
        }
        return stillSince != nil
    }

    /// The item to act on: the likeliest, a field when typing, never one
    /// that sends or shares when the goal's words ask for none of that
    /// (`ScreenControl.mayAct`; not Jev's "risky", a probability); under
    /// 40 % with others close, the user picks among the best three.
    private func pick(_ decision: Decision, goal: String, candidates: [ScreenItem], typing: Bool) async -> String? {
        let fitting = decision.targets.filter { target in
            guard let item = candidates.first(where: { $0.id == target.id }) else { return false }
            if typing && !item.isField { return false }
            return ScreenControl.mayAct(on: item, goal: goal)
        }
        guard let best = fitting.first else { return nil }
        let close = fitting.prefix(3).filter { $0.probability >= best.probability / 3 }
        guard best.probability < 0.4, close.count > 1, let choose else { return best.id }
        let options = close.compactMap { target in candidates.first { $0.id == target.id }.map { Self.name($0, among: candidates) } }
        guard let index = await choose("Which one?", options), close.indices.contains(index) else { return nil }
        return close[index].id
    }

    // MARK: - Acting

    /// The ring on screen, a moment before acting.
    private func show(_ item: ScreenItem) async {
        guard let frame = item.frame else { return }
        highlight.show(frame)
        try? await Task.sleep(for: .milliseconds(220))
    }

    private func press(_ target: Target, item: ScreenItem) async {
        let start = ContinuousClock.now
        defer { Log.trace("Control acted on \(Self.name(item)) in \((ContinuousClock.now - start).compact)") }
        switch target {
        case .element(let element):
            if item.isField {
                AXUIElementSetAttributeValue(element.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                return
            }
            for action in [kAXPressAction, kAXConfirmAction, kAXPickAction] where await Self.perform(action, on: element.element) {
                return
            }
            if let frame = element.frame { await click(at: CGPoint(x: frame.midX, y: frame.midY)) }
        case .menu(let menu):
            _ = await Self.perform(kAXPressAction, on: menu.element)
        case .words(let frame):
            await click(at: CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    /// An Accessibility action, off the main thread and 2 s at most: an
    /// app opening a modal dialog may hold its answer until the dialog
    /// closes (the action is done all the same; the reply only times out).
    private static func perform(_ action: String, on element: AXUIElement) async -> Bool {
        nonisolated(unsafe) let element = element
        let result = await Task.detached(priority: .userInitiated) { () -> AXError in
            AXUIElementSetMessagingTimeout(element, 2)
            return AXUIElementPerformAction(element, action as CFString)
        }.value
        // Timed out waiting for the app: it is acting.
        return result == .success || result == .cannotComplete
    }

    /// Its value set through Accessibility; where it does not read back, the
    /// field focused, its text selected and the new text pasted.
    private func type(_ text: String, into target: Target) async {
        switch target {
        case .element(let element):
            AXUIElementSetAttributeValue(element.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(element.element, kAXValueAttribute as CFString, text as CFString)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element.element, kAXValueAttribute as CFString, &value) == .success, value as? String == text { return }
            if let frame = element.frame { await click(at: CGPoint(x: frame.midX, y: frame.midY)) }
        case .words(let frame):
            await click(at: CGPoint(x: frame.midX, y: frame.midY))
        case .menu:
            return
        }
        selection.press("a", flags: .maskCommand)
        await selection.replace(with: text)
    }

    /// The mouse moves there and clicks; the card lets the click through.
    private func click(at point: CGPoint) async {
        let card = cardWindow
        let ignored = card?.ignoresMouseEvents ?? false
        card?.ignoresMouseEvents = true
        defer { card?.ignoresMouseEvents = ignored }
        let source = CGEventSource(stateID: .hidSystemState)
        // Marked as skil.li's own: the card does not take it for the user
        // clicking elsewhere (which closes it).
        func post(_ type: CGEventType) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.setIntegerValueField(.eventSourceUserData, value: SyntheticKeys.marker)
            event?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved)
        try? await Task.sleep(for: .milliseconds(40))
        post(.leftMouseDown)
        try? await Task.sleep(for: .milliseconds(30))
        post(.leftMouseUp)
    }

    private func scroll(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for event in [CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
                      CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: -8, wheel2: 0, wheel3: 0)] {
            event?.setIntegerValueField(.eventSourceUserData, value: SyntheticKeys.marker)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static let keyOptions: [(String, String)] = [
        ("return", "Return: confirm, search, send, validate"), ("escape", "Escape: close or cancel"), ("tab", "Tab: the next field"),
        ("space", "Space"), ("down", "Down arrow"), ("up", "Up arrow"), ("cmd+s", "⌘S: save"), ("cmd+f", "⌘F: find in this window"),
        ("cmd+n", "⌘N: new document, message or window"), ("cmd+t", "⌘T: new tab"), ("cmd+w", "⌘W: close the window or tab"),
        ("cmd+l", "⌘L: the address bar"), ("cmd+a", "⌘A: select all"), ("cmd+z", "⌘Z: undo"), ("cmd+comma", "⌘,: the app's settings")
    ]

    private func press(_ key: String) {
        let codes = ["return": kVK_Return, "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space, "down": kVK_DownArrow, "up": kVK_UpArrow]
        if let code = codes[key] {
            selection.press(code: code)
        } else if key == "cmd+comma" {
            selection.press(",", flags: .maskCommand)
        } else if key.hasPrefix("cmd+"), let character = key.last {
            selection.press(character, flags: .maskCommand)
        }
    }

    private static func keyTitle(_ key: String) -> String {
        keyOptions.first { $0.0 == key }.map { $0.1.components(separatedBy: ":").first ?? key } ?? key
    }

    /// `button “Save”`, `the field “Email”`: for the card and its questions.
    private static func name(_ item: ScreenItem) -> String {
        let label = item.label.isEmpty ? (item.region.isEmpty ? "" : " (\(item.region))") : " “\(item.label)”"
        return item.role + label
    }

    /// The same, an item without words by its place in its row: `button,
    /// 3rd of 6 in a row (bottom left)`.
    private static func name(_ item: ScreenItem, among items: [ScreenItem]) -> String {
        guard let place = ScreenControl.rowPlace(of: item, among: items) else { return name(item) }
        return "\(item.role), \(place)" + (item.region.isEmpty ? "" : " (\(item.region))")
    }

    /// "your", "Margot's".
    private static func whose(_ name: String) -> String {
        name == "the user" ? "your" : "\(name)'s"
    }

    private static func riskWords(_ goal: String) -> String {
        ScreenControl.isRisky(goal) ? "do what cannot be taken back" : "send or confirm"
    }

    // MARK: - The card

    private func begin(_ title: String) {
        steps.append(AIPopover.Step(id: "\(steps.count)", title: title, state: .running))
        progress?(steps)
    }

    private func finish(_ state: AIPopover.Step.State) {
        guard !steps.isEmpty else { return }
        steps[steps.count - 1].state = state
        progress?(steps)
    }
}
