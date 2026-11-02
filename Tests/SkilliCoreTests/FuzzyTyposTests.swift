import XCTest
@testable import SkilliCore

final class FuzzyTyposTests: XCTestCase {
    private func typoScore(_ query: String, _ name: String) -> Int? {
        FuzzyTypos(FuzzyMatcher.Query(query)).score(FuzzyCandidate(name))
    }

    func testEachSlipIsUndone() {
        XCTAssertNotNil(typoScore("wahtsapp", "WhatsApp"), "swapped")
        XCTAssertNotNil(typoScore("whqtsapp", "WhatsApp"), "QWERTY neighbour")
        XCTAssertNotNil(typoScore("slzck", "Slack"), "AZERTY neighbour (a beside z)")
        XCTAssertNotNil(typoScore("safaari", "Safari"), "a letter too many")
        XCTAssertNotNil(typoScore("visula studio", "Visual Studio Code"), "spaces aside")
    }

    func testTwoSlipsOrScatteredLettersFindNothing() {
        XCTAssertNil(typoScore("wahtsqpp", "WhatsApp"))
        // "safr" in Safari's letters, but not in runs from its word starts.
        XCTAssertNil(typoScore("sfaai", "Safari"))
        XCTAssertNil(typoScore("zzzz", "Safari"))
    }

    func testShortAndLongQueriesAreLeftAlone() {
        XCTAssertTrue(FuzzyTypos(FuzzyMatcher.Query("mial")).isEmpty == false)
        XCTAssertTrue(FuzzyTypos(FuzzyMatcher.Query("mai")).isEmpty)
        XCTAssertTrue(FuzzyTypos(FuzzyMatcher.Query("what is the weather today")).isEmpty)
    }

    /// Always under what the query finds as typed.
    func testATypoRanksUnderAMatch() throws {
        let typo = try XCTUnwrap(typoScore("slakc", "Slack"))
        let typed = try XCTUnwrap(FuzzyMatcher.score(FuzzyMatcher.Query("slack"), FuzzyCandidate("Slack")))
        XCTAssertLessThan(typo, typed)
    }

    func testNeighboursOfBothLayouts() {
        let a = FuzzyTypos.neighbours["a"] ?? []
        XCTAssertTrue(a.contains("s"), "QWERTY")
        XCTAssertTrue(a.contains("z"), "AZERTY")
        XCTAssertFalse(a.contains("p"))
    }

    // MARK: - Volume

    /// Names the launcher finds: apps of a usual Mac and skil.li's own rows.
    private static let names = [
        "Safari", "Mail", "Messages", "Calendar", "Contacts", "Reminders", "Notes", "Music", "Podcasts",
        "Photos", "Preview", "TextEdit", "Terminal", "Finder", "System Settings", "App Store", "Activity Monitor",
        "Disk Utility", "Keychain Access", "Screenshot", "QuickTime Player", "FaceTime", "Maps", "Weather",
        "Calculator", "Dictionary", "Font Book", "Shortcuts", "Automator", "Xcode", "Simulator", "Instruments",
        "Google Chrome", "Firefox", "Arc", "Brave Browser", "Microsoft Edge", "Slack", "Discord", "WhatsApp",
        "Telegram", "Signal", "Zoom", "Microsoft Teams", "Spotify", "Figma", "Sketch", "Notion", "Obsidian",
        "Visual Studio Code", "Cursor", "Sublime Text", "Docker", "Postman", "iTerm", "Transmit", "1Password",
        "Bitwarden", "Things", "Todoist", "Fantastical", "Microsoft Word", "Microsoft Excel", "Keynote",
        "Pages", "Numbers", "Pixelmator Pro", "Affinity Photo", "Final Cut Pro", "Logic Pro", "GarageBand",
        "CleanShot X", "Raycast", "Alfred", "Bartender", "Rectangle", "Linear", "Tower", "Fork", "GitHub Desktop",
        "Search Snippets", "Search Clipboard", "Search Files", "Search Contacts", "Search Menu Items",
        "Search Browser History", "Switch Window", "Kill Process", "Record Meeting", "Copy Availability",
        "Keep Awake", "Lock Screen", "Empty Trash", "Toggle Dark Mode", "Check for Updates",
    ]

    /// Each name's first word (four letters or more), cut at eight letters
    /// as typed, with one slip of each kind. Counts how often the name is
    /// first among all the names for the slip, when what was typed finds
    /// nothing as it is (the only time typos are looked at). First with
    /// others is first: "serach" is every "Search …" row alike, as
    /// "search" is.
    func testTyposFindTheNameMeantOnVolume() {
        let candidates = Self.names.map(FuzzyCandidate.init)
        var asked = 0
        var first = 0
        var missed: [String] = []
        for (meant, name) in Self.names.enumerated() {
            let word = name.lowercased().split(separator: " ").first { $0.count >= 4 }.map(String.init)
                ?? name.lowercased().filter { $0 != " " }
            let typed = Array(word.prefix(8).unicodeScalars)
            guard typed.count >= FuzzyTypos.minLength else { continue }
            for slip in Self.slips(typed) {
                let query = FuzzyMatcher.Query(slip)
                guard !candidates.contains(where: { FuzzyMatcher.score(query, $0) != nil }) else { continue }
                asked += 1
                let typos = FuzzyTypos(query)
                let scores = candidates.map { typos.score($0) }
                let best = scores.compactMap { $0 }.max()
                if let best, scores[meant] == best {
                    first += 1
                } else {
                    missed.append("\(slip) → \(name)")
                }
            }
        }
        let rate = Double(first) / Double(max(asked, 1))
        print("FuzzyTypos volume: \(first)/\(asked) first (\(Int(rate * 100)) %); missed: \(missed.joined(separator: ", "))")
        XCTAssertGreaterThan(asked, 150)
        XCTAssertGreaterThanOrEqual(rate, 0.95)
    }

    /// A swap in the middle, the second letter's first neighbour, the
    /// third letter doubled.
    private static func slips(_ word: [Unicode.Scalar]) -> [String] {
        var out: [[Unicode.Scalar]] = []
        var swapped = word
        let middle = word.count / 2 - 1
        if word[middle] != word[middle + 1] {
            swapped.swapAt(middle, middle + 1)
            out.append(swapped)
        }
        if let neighbour = FuzzyTypos.neighbours[word[1]]?.first {
            var replaced = word
            replaced[1] = neighbour
            out.append(replaced)
        }
        var doubled = word
        doubled.insert(word[2], at: 2)
        out.append(doubled)
        return out.map { var view = String.UnicodeScalarView(); view.append(contentsOf: $0); return String(view) }
    }

    /// A key that finds nothing looks at every name through the variants:
    /// bounded, since it runs on that key.
    func testWorstQueryOverManyNamesIsBounded() {
        let candidates = (0..<2_000).map { FuzzyCandidate("\(Self.names[$0 % Self.names.count]) \($0)") }
        let typos = FuzzyTypos(FuzzyMatcher.Query("qwertzuiopas"))
        let start = ContinuousClock.now
        for candidate in candidates { _ = typos.score(candidate) }
        let elapsed = ContinuousClock.now - start
        print("FuzzyTypos 2000 names, 12 letters: \(elapsed)")
        // Debug build here; the launcher's own lap measures Release.
        XCTAssertLessThan(elapsed, .milliseconds(50))
    }
}
