import CoreGraphics
@testable import SkilliCore
import XCTest

final class ScreenControlTests: XCTestCase {
    private let window = CGRect(x: 100, y: 100, width: 900, height: 600)

    func testRegions() {
        XCTAssertEqual(ScreenControl.region(of: CGRect(x: 110, y: 110, width: 40, height: 20), in: window), "top left")
        XCTAssertEqual(ScreenControl.region(of: CGRect(x: 520, y: 380, width: 60, height: 20), in: window), "center")
        XCTAssertEqual(ScreenControl.region(of: CGRect(x: 900, y: 650, width: 60, height: 20), in: window), "bottom right")
        XCTAssertEqual(ScreenControl.region(of: CGRect(x: 520, y: 120, width: 60, height: 20), in: window), "top")
    }

    func testCandidatesPutWhatTheGoalNamesFirstAndKeepReadingOrder() {
        var items = (1...200).map { ScreenItem(id: "i\($0)", source: .element, role: "text", label: "Paragraph \($0)") }
        items.insert(ScreenItem(id: "save", source: .element, role: "button", label: "Enregistrer"), at: 150)
        items.insert(ScreenItem(id: "name", source: .element, role: "text field", label: "Nom"), at: 3)
        let kept = ScreenControl.candidates(items, goal: "enregistre le formulaire", limit: 20)
        XCTAssertEqual(kept.count, 20)
        XCTAssertTrue(kept.contains { $0.id == "save" }, "named by the goal")
        XCTAssertTrue(kept.contains { $0.id == "name" }, "a field before texts")
        let positions = kept.map { item in items.firstIndex { $0.id == item.id }! }
        XCTAssertEqual(positions, positions.sorted(), "reading order")
    }

    func testCandidatesKeepOnePerLabelButEveryField() {
        let items = [ScreenItem(id: "a", source: .element, role: "button", label: "OK"),
                     ScreenItem(id: "b", source: .element, role: "button", label: "ok"),
                     ScreenItem(id: "c", source: .element, role: "text field", label: ""),
                     ScreenItem(id: "d", source: .element, role: "text field", label: "")]
        XCTAssertEqual(ScreenControl.candidates(items, goal: "valide").map(\.id), ["a", "c", "d"])
    }

    func testWordlessItemsAreKeptWhenAPictureCanTellThemApart() {
        let icons = (1...3).map { ScreenItem(id: "b\($0)", source: .element, role: "button", label: "",
                                            frame: CGRect(x: 100 + 40 * $0, y: 600, width: 32, height: 28)) }
        let items = [ScreenItem(id: "save", source: .element, role: "button", label: "Save", frame: CGRect(x: 10, y: 10, width: 60, height: 24))] + icons
        XCTAssertEqual(ScreenControl.candidates(items, goal: "mets en favori").map(\.id), ["save", "b1"], "in words, one is as good as another")
        XCTAssertEqual(ScreenControl.candidates(items, goal: "mets en favori", keepsWordless: true).map(\.id), ["save", "b1", "b2", "b3"])
        XCTAssertTrue(icons[0].isWordless)
        XCTAssertFalse(items[0].isWordless)
        XCTAssertFalse(ScreenItem(id: "x", source: .element, role: "button", label: "").isWordless, "nowhere: no picture shows it")
        XCTAssertFalse(ScreenItem(id: "x", source: .element, role: "pop-up", label: "", value: "PDF", frame: .zero).isWordless, "its value says")
        XCTAssertFalse(ScreenItem(id: "x", source: .text, role: "text on screen", label: "", frame: .zero).isWordless)
    }

    /// "clique sur Snooze" with “Snooze” read on screen: words find it, the
    /// picture waits; a goal that names no item (an icon's meaning) needs it.
    func testAGoalNamingAnItemIsAskedInWordsFirst() {
        let snooze = ScreenItem(id: "s", source: .text, role: "text on screen", label: "Snooze", frame: CGRect(x: 230, y: 300, width: 60, height: 20))
        let title = ScreenItem(id: "t", source: .text, role: "text on screen", label: "Inbox — Weekly report from Paul")
        let icon = ScreenItem(id: "icon", source: .element, role: "button", label: "", frame: CGRect(x: 90, y: 0, width: 30, height: 30))
        let menu = ScreenItem(id: "m", source: .menu, role: "menu item", label: "Mail")
        let items = [snooze, title, icon, menu]
        XCTAssertTrue(ScreenControl.goalNames(items, goal: "clique sur Snooze"))
        XCTAssertTrue(ScreenControl.goalNames(items, goal: "snooze ce mail"))
        XCTAssertFalse(ScreenControl.goalNames(items, goal: "mets une étoile à ce mail"), "a menu named Mail does not count")
        XCTAssertFalse(ScreenControl.goalNames(items, goal: "clique sur la cloche"))
        XCTAssertFalse(ScreenControl.goalNames([icon], goal: "clique"), "an item without words is never named")
    }

    func testThePictureGoesWhenTheWindowSaysTooLittle() {
        func button(_ label: String, _ x: CGFloat = 0) -> ScreenItem {
            ScreenItem(id: label, source: .element, role: "button", label: label, frame: CGRect(x: x, y: 0, width: 40, height: 20))
        }
        let drawn = ScreenItem(id: "w", source: .text, role: "text on screen", label: "Archive", frame: CGRect(x: 5, y: 300, width: 60, height: 20))
        let icon = ScreenItem(id: "icon", source: .element, role: "button", label: "", frame: CGRect(x: 90, y: 0, width: 30, height: 30))
        let menu = ScreenItem(id: "m", source: .menu, role: "menu item", label: "File › Save")
        // Icon-only buttons: whatever else is there.
        XCTAssertEqual(ScreenControl.pictureNeed((1...10).map { button("B\($0)") } + [icon]), .wordless)
        // Little told to Accessibility, words on screen beside it: drawn.
        XCTAssertEqual(ScreenControl.pictureNeed([button("OK"), button("Cancel"), drawn, menu]), .drawn)
        // A simple dialog says enough: its words are its buttons.
        XCTAssertNil(ScreenControl.pictureNeed([button("Save"), button("Cancel"), button("Don't Save"), menu]))
        // Plenty told: no picture, even with words read on screen.
        XCTAssertNil(ScreenControl.pictureNeed((1...ScreenControl.fewThings).map { button("B\($0)") } + [drawn]))
        // Texts and menus are not things the window tells.
        let texts = (1...10).map { ScreenItem(id: "t\($0)", source: .element, role: "text", label: "Para \($0)") }
        XCTAssertEqual(ScreenControl.pictureNeed(texts + [menu, drawn]), .drawn)
    }

    func testUnsureIsUnderHalfForWhatToClickOrTypeInto() {
        XCTAssertTrue(ScreenControl.isUnsure(next: "click", best: 0.34))
        XCTAssertTrue(ScreenControl.isUnsure(next: "type", best: 0.49))
        XCTAssertTrue(ScreenControl.isUnsure(next: "click", best: nil), "nothing fits")
        XCTAssertFalse(ScreenControl.isUnsure(next: "click", best: 0.5))
        XCTAssertFalse(ScreenControl.isUnsure(next: "click", best: 0.92))
        for next in ["key", "scroll", "done", "stuck"] {
            XCTAssertFalse(ScreenControl.isUnsure(next: next, best: 0.1), next)
        }
    }

    func testAnIconIsNamedByItsPlaceInItsRow() {
        let row = (0..<6).map { ScreenItem(id: "b\($0)", source: .element, role: "button", label: "",
                                          frame: CGRect(x: 30 + 58 * CGFloat($0), y: 620, width: 46, height: 38)) }
        // Read in another order: the row still goes left to right.
        let read = row.reversed() + [ScreenItem(id: "alone", source: .element, role: "button", label: "", frame: CGRect(x: 30, y: 100, width: 40, height: 40)),
                                     ScreenItem(id: "save", source: .element, role: "button", label: "Save", frame: CGRect(x: 400, y: 620, width: 60, height: 38))]
        XCTAssertEqual(ScreenControl.rowPlace(of: row[0], among: read), "1st of 6 in a row")
        XCTAssertEqual(ScreenControl.rowPlace(of: row[2], among: read), "3rd of 6 in a row")
        XCTAssertNil(ScreenControl.rowPlace(of: read[6], among: read), "alone")
        XCTAssertNil(ScreenControl.rowPlace(of: read[7], among: read), "words name it")
        XCTAssertEqual(ScreenControl.ordinal(2), "2nd")
        XCTAssertEqual(ScreenControl.ordinal(12), "12th")
        XCTAssertEqual(ScreenControl.ordinal(23), "23rd")
    }

    func testNeverAPictureOfAPasswordField() {
        let field = ScreenItem(id: "p", source: .element, role: "password field", label: "Password")
        let name = ScreenItem(id: "n", source: .element, role: "text field", label: "Name")
        XCTAssertFalse(ScreenControl.mayPicture([name, field]))
        XCTAssertTrue(ScreenControl.mayPicture([name]))
    }

    func testRiskyLabels() {
        for label in ["Send", "Envoyer", "Supprimer le compte", "Delete", "Pay now", "Acheter", "Publier", "Move to Trash", "Valider la commande", "Remplacer", "Replace"] {
            XCTAssertTrue(ScreenControl.isRisky(label), label)
        }
        for label in ["Share", "Bold", "Format", "Nouveau message", "Enregistrer", "Annuler", "Next", "Sign in"] {
            XCTAssertFalse(ScreenControl.isRisky(label), label)
        }
    }

    func testOutboundItems() {
        for label in ["Fichier › Partager › Mail", "Fichier › Partager › Envoyer au format PDF", "Send", "Share…", "AirDrop", "Publier"] {
            XCTAssertTrue(ScreenControl.isOutbound(label), label)
        }
        for label in ["Fichier › Exporter au format PDF…", "Fichier › Enregistrer sous...", "Nouveau message", "Enregistrer", "Export"] {
            XCTAssertFalse(ScreenControl.isOutbound(label), label)
        }
    }

    func testOutboundOnlyWhenTheGoalSaysSo() {
        let mail = ScreenItem(id: "m", source: .menu, role: "menu item", label: "Partie › Partager › Mail", region: "menu")
        let sendPDF = ScreenItem(id: "p", source: .menu, role: "menu item", label: "Fichier › Partager › Envoyer au format PDF", region: "menu")
        let share = ScreenItem(id: "s", source: .element, role: "button", label: "Partager", region: "top right")
        let submit = ScreenItem(id: "e", source: .element, role: "button", label: "Envoyer", region: "bottom")
        // The Safari self-test's "signale ce mail avec le drapeau" once
        // clicked "Partager" when "sign" counted as submitting.
        for goal in ["joue le prochain coup", "exporte en PDF dans mes documents", "enregistre-le en PDF", "play the next move",
                     "Mets « jean@example.com » dans l'email puis enregistre", "signale ce mail avec le drapeau"] {
            XCTAssertFalse(ScreenControl.asksToSend(goal), goal)
            for item in [mail, sendPDF, share, submit] {
                XCTAssertFalse(ScreenControl.mayAct(on: item, goal: goal), "\(item.label) for \(goal)")
            }
        }
        for goal in ["partage la partie par mail", "envoie-le à Paul", "send it to Paul", "publie le post", "transfère ce mail à Léa"] {
            XCTAssertTrue(ScreenControl.asksToSend(goal), goal)
            XCTAssertTrue(ScreenControl.mayAct(on: mail, goal: goal), goal)
        }
        // A form submitted by its own button, never by sharing the page.
        for goal in ["remplis le formulaire et valide", "inscris-moi avec mes infos"] {
            XCTAssertTrue(ScreenControl.mayAct(on: submit, goal: goal), goal)
            XCTAssertFalse(ScreenControl.mayAct(on: mail, goal: goal), goal)
            XCTAssertFalse(ScreenControl.mayAct(on: share, goal: goal), goal)
        }
        let pawn = ScreenItem(id: "i5", source: .element, role: "button", label: "pion blanc, e2", region: "bottom left")
        XCTAssertTrue(ScreenControl.mayAct(on: pawn, goal: "joue le prochain coup"))
    }

    func testThePlaceASaveGoalNames() {
        let items = [ScreenItem(id: "a", source: .element, role: "text", label: "Bureau", region: "left"),
                     ScreenItem(id: "b", source: .element, role: "text", label: "Documents", region: "left"),
                     ScreenItem(id: "c", source: .element, role: "text", label: "Documents", region: "center"),
                     ScreenItem(id: "d", source: .element, role: "button", label: "Exporter", region: "bottom right")]
        XCTAssertEqual(ScreenControl.place(in: "exporte en PDF dans mes documents", among: items)?.id, "b")
        XCTAssertEqual(ScreenControl.place(in: "enregistre-le sur le bureau", among: items)?.id, "a")
        XCTAssertNil(ScreenControl.place(in: "enregistre le document en PDF", among: items))
        // The Mac in English, the goal in French; the "Where:" list open.
        let english = [ScreenItem(id: "d", source: .element, role: "text", label: "Desktop", region: "left"),
                       ScreenItem(id: "m", source: .element, role: "menu item", label: "Downloads", region: "center")]
        XCTAssertEqual(ScreenControl.place(in: "export ça en pdf sur mon bureau", among: english)?.id, "d")
        XCTAssertEqual(ScreenControl.place(in: "mets-le dans mes téléchargements", among: english)?.id, "m")
        XCTAssertEqual(ScreenControl.place(in: "save it to my desktop", among: english)?.id, "d")
        XCTAssertTrue(ScreenControl.isFinalSave("Exporter"))
        XCTAssertTrue(ScreenControl.isFinalSave("Save"))
        XCTAssertFalse(ScreenControl.isFinalSave("Annuler"))
    }

    func testFillingAloneNeverSubmits() {
        XCTAssertFalse(ScreenControl.asksToSubmit("remplis le formulaire avec mes infos"))
        XCTAssertFalse(ScreenControl.asksToSubmit("remplis ça pour Margot"))
        XCTAssertTrue(ScreenControl.asksToSubmit("remplis le formulaire avec mes infos et envoie-le"))
        XCTAssertTrue(ScreenControl.asksToSubmit("inscris-moi avec mes infos"))
        XCTAssertTrue(ScreenControl.asksToSubmit("fill it in and submit"))
    }

    func testQuotedText() {
        XCTAssertEqual(ScreenControl.quoted(in: "écris \"Bonjour Paul\" dans le sujet"), "Bonjour Paul")
        XCTAssertEqual(ScreenControl.quoted(in: "cherche « vols Rome » ici"), "vols Rome")
        XCTAssertEqual(ScreenControl.quoted(in: "tape 'hello world' puis entrée"), "hello world")
        XCTAssertNil(ScreenControl.quoted(in: "change l'objet du mail"))
        XCTAssertNil(ScreenControl.quoted(in: "clique sur partager"))
        XCTAssertEqual(ScreenControl.quotes(in: "mets « Jean Dupont » dans le nom et \"jean@example.com\" dans l'email"),
                       ["Jean Dupont", "jean@example.com"])
    }

    func testAPlanLineNamesItsItemByItsExactWords() {
        let items = [ScreenItem(id: "i5", source: .element, role: "button", label: "pion blanc, e2", region: "bottom left"),
                     ScreenItem(id: "i6", source: .element, role: "button", label: "e4", region: "center"),
                     ScreenItem(id: "i7", source: .element, role: "button", label: "e5", enabled: false, region: "center"),
                     ScreenItem(id: "i8", source: .element, role: "text", label: "Bonjour", region: "top"),
                     ScreenItem(id: "i9", source: .element, role: "text field", label: "To", region: "top"),
                     ScreenItem(id: "i10", source: .element, role: "button", label: "Annuler", region: "bottom"),
                     ScreenItem(id: "i11", source: .element, role: "button", label: "Annuler", region: "top"),
                     ScreenItem(id: "m1", source: .menu, role: "menu item", label: "Déplacements › Afficher le dernier déplacement"),
                     ScreenItem(id: "m2", source: .menu, role: "menu item", label: "Partie › Partager › Mail")]
        XCTAssertEqual(ScreenControl.named(by: "Click the button “pion blanc, e2”", among: items)?.id, "i5")
        XCTAssertEqual(ScreenControl.named(by: "Click the button \"e4\"", among: items)?.id, "i6")
        XCTAssertEqual(ScreenControl.named(by: "Click the white pawn on e4 (button “Pion  blanc, E2”)", among: items)?.id, "i5",
                       "case and spaces aside")
        XCTAssertEqual(ScreenControl.named(by: "Click the menu item “Déplacements › Afficher le dernier déplacement”", among: items)?.id, "m1")
        // Typing goes in a field, never in a word shown.
        XCTAssertEqual(ScreenControl.named(by: "Type “Bonjour” in “To”", among: items, typing: true)?.id, "i9")
        // Not named, named twice, or disabled: Jev ranks.
        XCTAssertNil(ScreenControl.named(by: "Click the white pawn in front of the king", among: items))
        XCTAssertNil(ScreenControl.named(by: "Click “Annuler”", among: items))
        XCTAssertNil(ScreenControl.named(by: "Click the button “e5”", among: items))
        XCTAssertNil(ScreenControl.named(by: "Click the queen's side pawn", among: items))
    }

    /// JB's Chess run, 2026-10-18 20:49:58: after “fou blanc, f1” was
    /// pressed, Chess answered 15 of its 73 elements in time (rank 1, most
    /// of rank 2), the plan's “b5” not among them.
    private static let cutShortBoard: [ScreenItem] = {
        let first = ["tour blanche, a1", "cavalier blanc, b1", "fou blanc, c1", "dame blanche, d1", "roi blanc, e1", "fou blanc, f1", "g1",
                     "tour blanche, h1"] + "abcdefg".map { "pion blanc, \($0)2" }
        return first.enumerated().map { ScreenItem(id: "i\($0.offset + 1)", source: .element, role: "button", label: $0.element) }
            + [ScreenItem(id: "m1", source: .menu, role: "menu item", label: "Partie › Enregistrer sous…")]
    }()

    func testAPlanLineClicksTheItemItQuotes() {
        XCTAssertEqual(ScreenControl.clickedWords(in: "Click the button “b5”"), ["b5"])
        XCTAssertEqual(ScreenControl.clickedWords(in: "Double-click the file “Notes.txt”"), ["Notes.txt"])
        XCTAssertEqual(ScreenControl.clickedWords(in: "Clique sur le bouton « Enregistrer »"), ["Enregistrer"])
        XCTAssertEqual(ScreenControl.clickedWords(in: "Choose “Partie › Nouvelle partie”"), ["Partie › Nouvelle partie"])
        XCTAssertEqual(ScreenControl.clickedWords(in: "Press the button “OK”"), ["OK"])
        // A key, text to type, something drawn: no item by its words.
        XCTAssertEqual(ScreenControl.clickedWords(in: "Press “⌘S”"), [])
        XCTAssertEqual(ScreenControl.clickedWords(in: "Press Return"), [])
        XCTAssertEqual(ScreenControl.clickedWords(in: "Type “Bonjour” in “To”"), [])
        XCTAssertEqual(ScreenControl.clickedWords(in: "Click the empty slot right below the red card, in the third column"), [])
    }

    func testAPlanLineWhoseItemWasNotReadIsReadAgain() {
        let board = Self.cutShortBoard
        XCTAssertEqual(ScreenControl.unread(by: "Click the button “b5”", among: board), "b5")
        XCTAssertNil(ScreenControl.unread(by: "Click the button “fou blanc, f1”", among: board))
        XCTAssertNil(ScreenControl.unread(by: "Click the button “b2”", among: board), "a square by its name: “pion blanc, b2”")
        XCTAssertNil(ScreenControl.unread(by: "Click the menu item “Enregistrer sous”", among: board), "the ellipsis aside")
        XCTAssertNil(ScreenControl.unread(by: "Click “Enregistrer sous…”", among: board), "a menu item by its last part")
        XCTAssertNil(ScreenControl.unread(by: "Press Return", among: board))
        XCTAssertNil(ScreenControl.unread(by: "Type “e5” in the move field", among: board), "text to type is no item")
        XCTAssertNil(ScreenControl.unread(by: "Click the black pawn in front of the king", among: board))
        // Shown but disabled: read, so not read again.
        let disabled = board + [ScreenItem(id: "i40", source: .element, role: "button", label: "b5", enabled: false)]
        XCTAssertNil(ScreenControl.unread(by: "Click the button “b5”", among: disabled))
    }

    func testOnlyAStepOnTheLinesItemDoesTheLine() {
        let board = Self.cutShortBoard
        let b2 = board.first { $0.label == "pion blanc, b2" }!
        let b5 = ScreenItem(id: "i34", source: .element, role: "button", label: "b5")
        XCTAssertFalse(ScreenControl.follows("Click the button “b5”", acted: [b2]))
        XCTAssertTrue(ScreenControl.follows("Click the button “b5”", acted: [b5]))
        XCTAssertTrue(ScreenControl.follows("Click the button “b5”", acted: [ScreenItem(id: "i9", source: .element, role: "button", label: "fou blanc, b5")]),
                      "the square, a piece on it")
        XCTAssertFalse(ScreenControl.follows("Click the button “b5”", acted: []), "a key does not click it")
        // Nothing to tell the line by: any step.
        XCTAssertTrue(ScreenControl.follows("Press Return", acted: []))
        XCTAssertTrue(ScreenControl.follows("Click the white bishop drawn on the left", acted: [b2]))
    }

    func testEveryLineDoneCountsOnlyStepsThatDidThem() {
        let board = Self.cutShortBoard
        let f1 = board.first { $0.label == "fou blanc, f1" }!
        let b2 = board.first { $0.label == "pion blanc, b2" }!
        let b5 = ScreenItem(id: "i34", source: .element, role: "button", label: "b5")
        var plan = PlanProgress(["Click the button “fou blanc, f1”", "Click the button “b5”"])
        XCTAssertEqual(plan.next, "Click the button “fou blanc, f1”")
        XCTAssertTrue(plan.step(acted: [f1]))
        // JB's run: a pawn clicked for “b5” left the move unplayed, and
        // the run said done.
        XCTAssertFalse(plan.step(acted: [b2]))
        XCTAssertFalse(plan.isFinished)
        XCTAssertEqual(plan.next, "Click the button “b5”")
        XCTAssertTrue(plan.step(acted: [b5]))
        XCTAssertTrue(plan.isFinished)
        XCTAssertNil(plan.next)
        XCTAssertFalse(plan.step(acted: [b5]), "nothing left to do")

        // A click in the picture for the line, or the item Jev was sure of
        // when none read its words: done; the writer checks spots after.
        var drawn = PlanProgress(["Click the button “b5”", "Click the button “Enregistrer”"])
        XCTAssertTrue(drawn.step(acted: [], spot: true))
        XCTAssertTrue(drawn.step(acted: [ScreenItem(id: "i2", source: .element, role: "button", label: "Save")], grounded: true))
        XCTAssertTrue(drawn.isFinished)
        XCTAssertFalse(PlanProgress().isFinished, "no plan is never done")
    }

    func testMergeKeepsOnlyTheWordsAccessibilityMissed() {
        let elements = [ScreenItem(id: "e1", source: .element, role: "button", label: "Share", frame: CGRect(x: 0, y: 0, width: 100, height: 30))]
        let text = [ScreenItem(id: "t1", source: .text, role: "text", label: "Share", frame: CGRect(x: 10, y: 5, width: 40, height: 20)),
                    ScreenItem(id: "t2", source: .text, role: "text", label: "Canvas title", frame: CGRect(x: 300, y: 300, width: 80, height: 20))]
        XCTAssertEqual(ScreenControl.merge(elements: elements, text: text).map(\.id), ["e1", "t2"])
    }

    func testDescriptionForTheModel() {
        XCTAssertEqual(ScreenItem(id: "i1", source: .element, role: "checkbox", label: "Subscribe", value: "0", region: "center").description,
                       "checkbox “Subscribe” (off) · center")
        XCTAssertEqual(ScreenItem(id: "i2", source: .element, role: "text field", label: "To", value: "paul@example.com", region: "top").description,
                       "text field “To” = “paul@example.com” · top")
    }
}
