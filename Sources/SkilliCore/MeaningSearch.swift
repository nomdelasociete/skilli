import Foundation

/// What a request says about when and what, read here before anything is
/// sent: "l'adresse mail d'avant-hier" → the days around the day before
/// yesterday, copies with an email address in them. A search by meaning
/// over a long history narrows it with this first, so the decision model
/// reads only the part the request can mean (`MeaningRounds`).
public struct MeaningNarrowing: Equatable, Sendable {
    /// A kind of thing the request names.
    public enum Kind: String, CaseIterable, Sendable {
        case email
        case link
        case image
        case phone
        case iban
        case file
    }

    /// The days the request names, one day of slack on each side; nil
    /// when it names none.
    public var window: DateInterval?
    public var kinds: Set<Kind>

    public init(window: DateInterval? = nil, kinds: Set<Kind> = []) {
        self.window = window
        self.kinds = kinds
    }

    /// "yesterday", "avant-hier", "la semaine dernière", "Monday", "3 days
    /// ago"; "email", "lien", "screenshot", "téléphone", "IBAN", "fichier".
    /// English and French, accents and case ignored.
    public init(_ request: String, now: Date = .now, calendar: Calendar = .current) {
        let text = NSMutableString(string: Self.folded(request))
        let today = calendar.startOfDay(for: now)
        var days: [DateInterval] = []
        // In order: a phrase read is blanked, so "hier" is not read again
        // in "avant-hier", nor "yesterday" in "the day before yesterday".
        for (pattern, read) in Self.times {
            for match in pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)).reversed() {
                let groups = (1..<match.numberOfRanges).map { index -> String in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? "" : text.substring(with: range)
                }
                if let interval = read(groups, today, calendar) { days.append(interval) }
                text.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
            }
        }
        if let start = days.map(\.start).min(), let end = days.map(\.end).max(),
           let from = calendar.date(byAdding: .day, value: -1, to: start), let to = calendar.date(byAdding: .day, value: 1, to: end) {
            window = DateInterval(start: from, end: to)
        }
        let rest = text as String
        kinds = Set(Self.kindWords.compactMap { kind, pattern in
            pattern.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) == nil ? nil : kind
        })
    }

    /// The candidates the request can mean, in the order given. A list one
    /// question holds is kept whole, as before; a longer one keeps those
    /// inside the window, then those of a kind named. A step that would
    /// leave nothing is skipped: a day misremembered still finds the copy
    /// among all of them. `date` nil: never inside a window.
    public func narrowed<T>(_ all: [T], fitting limit: Int = MeaningRounds.questionSize, date: (T) -> Date?,
                            holds: (T, Kind) -> Bool) -> [T] {
        guard all.count > limit else { return all }
        var found = all
        if let window {
            let inside = found.filter { date($0).map(window.contains) ?? false }
            if !inside.isEmpty { found = inside }
        }
        if !kinds.isEmpty {
            let named = found.filter { item in kinds.contains { holds(item, $0) } }
            if !named.isEmpty { found = named }
        }
        return found
    }

    /// Whether a copy holds this kind: an address or a link anywhere in
    /// its words, a phone number, an IBAN or a RIB (checked as the masking
    /// checks it), an image (or image files), files.
    public static func holds(_ kind: Kind, copy: ClipboardMeaning.Kind, text: String, ocr: String? = nil) -> Bool {
        let words = ocr.map { text + "\n" + $0 } ?? text
        switch kind {
        case .image:
            return copy == .image || (copy == .files && text.split(separator: "\n").contains { line in
                imageExtensions.contains((String(line) as NSString).pathExtension.lowercased())
            })
        case .file:
            return copy == .files
        case .email:
            return words.contains("@") && emailPattern.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)) != nil
        case .link:
            return linkPattern.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)) != nil
        case .phone:
            return phonePattern.matches(in: words, range: NSRange(words.startIndex..., in: words)).contains { match in
                let number = (words as NSString).substring(with: match.range)
                return (7...15).contains(number.filter(\.isNumber).count) && datePattern.firstMatch(
                    in: number, range: NSRange(number.startIndex..., in: number)) == nil
            }
        case .iban:
            guard words.contains(where: \.isNumber) else { return false }
            // The masking reads words between spaces: a line break is one.
            let masked = ToolCallSummary.maskingSecrets(words.split(whereSeparator: \.isWhitespace).joined(separator: " "))
            return masked.contains("(an IBAN)") || masked.contains("(a bank account number)")
        }
    }

    // MARK: - Reading

    /// Lowercased, accents off, one kind of apostrophe.
    static func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private typealias Days = @Sendable (_ groups: [String], _ today: Date, _ calendar: Calendar) -> DateInterval?

    private static func pattern(_ source: String) -> NSRegularExpression {
        // Constant patterns: a typo is caught by the unit tests.
        try! NSRegularExpression(pattern: source)
    }

    /// The day `offset` days from today, whole.
    private static func day(_ offset: Int, _ today: Date, _ calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(byAdding: .day, value: offset, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The week or month `offset` from this one, whole (this one: up to the
    /// end of today).
    private static func period(_ unit: Calendar.Component, _ offset: Int, _ today: Date, _ calendar: Calendar) -> DateInterval? {
        guard let inside = calendar.date(byAdding: unit, value: offset, to: today),
              let interval = calendar.dateInterval(of: unit == .month ? .month : .weekOfYear, for: inside) else { return nil }
        guard offset == 0, let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return interval }
        return DateInterval(start: interval.start, end: min(interval.end, tomorrow))
    }

    private static let numbers: [String: Int] = [
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "sept": 7
    ]

    /// Gregorian weekday numbers (Sunday 1).
    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7
    ]

    private static let spokenCount = "(\\d{1,2}|two|three|four|five|six|seven|deux|trois|quatre|cinq|sept)"

    private static let times: [(NSRegularExpression, Days)] = [
        (pattern("\\b(?:the )?day before yesterday\\b|\\bavant[- ]hier\\b"), { _, today, calendar in day(-2, today, calendar) }),
        (pattern("\\byesterday\\b|\\bhier\\b"), { _, today, calendar in day(-1, today, calendar) }),
        (pattern("\\btoday\\b|\\baujourd'?hui\\b|\\bthis (?:morning|afternoon|evening)\\b|\\btonight\\b|\\bce (?:matin|soir)\\b|\\bcet apres[- ]midi\\b"),
         { _, today, calendar in day(0, today, calendar) }),
        (pattern("\\b\(spokenCount) days? ago\\b|\\bil y a \(spokenCount) jours?\\b"), { groups, today, calendar in
            guard let word = groups.first(where: { !$0.isEmpty }), let days = Int(word) ?? numbers[word], days <= 60 else { return nil }
            return day(-days, today, calendar)
        }),
        (pattern("\\blast week\\b|\\bthe week before\\b|\\b(?:la )?semaine (?:derniere|passee)\\b"), { _, today, calendar in
            period(.weekOfYear, -1, today, calendar)
        }),
        (pattern("\\bthis week\\b|\\bcette semaine\\b"), { _, today, calendar in period(.weekOfYear, 0, today, calendar) }),
        (pattern("\\blast month\\b|\\b(?:le )?mois (?:dernier|passe)\\b"), { _, today, calendar in period(.month, -1, today, calendar) }),
        (pattern("\\bthis month\\b|\\bce mois(?:-ci)?\\b"), { _, today, calendar in period(.month, 0, today, calendar) }),
        // The last one before today: today is "today".
        (pattern("\\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\\b"),
         { groups, today, calendar in
            guard let weekday = groups.first.flatMap({ weekdays[$0] }) else { return nil }
            let back = (1...7).first { offset in
                calendar.date(byAdding: .day, value: -offset, to: today).map { calendar.component(.weekday, from: $0) == weekday } ?? false
            }
            return back.flatMap { day(-$0, today, calendar) }
        })
    ]

    private static let kindWords: [(Kind, NSRegularExpression)] = [
        (.email, pattern("\\be-?mails?\\b|\\bcourriels?\\b|\\badresses? (?:e-?)?mail\\b|\\bmail address(?:es)?\\b")),
        (.link, pattern("\\b(?:links?|liens?|urls?)\\b")),
        (.image, pattern("\\b(?:images?|screenshots?|screen shots?|captures?|photos?|pictures?)\\b")),
        (.phone, pattern("\\b(?:phone|telephone)s?\\b|\\bnumeros? de tel\\b|\\bmobile number\\b")),
        (.iban, pattern("\\b(?:iban|rib)s?\\b")),
        (.file, pattern("\\b(?:files?|fichiers?)\\b"))
    ]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "tif", "webp", "bmp"]
    private static let emailPattern = try! NSRegularExpression(pattern: "[A-Z0-9._%+-]+@[A-Z0-9-]+(?:\\.[A-Z0-9-]+)*\\.[A-Z]{2,}",
                                                               options: .caseInsensitive)
    private static let linkPattern = try! NSRegularExpression(pattern: "\\bhttps?://\\S|\\bwww\\.[a-z0-9-]+\\.", options: .caseInsensitive)
    /// Digits and the signs numbers are written with, as `CopiedValue`
    /// reads a phone number; checked for 7 to 15 digits.
    private static let phonePattern = try! NSRegularExpression(pattern: "(?<![\\w@.])\\+?\\(?\\d[\\d .\\-()\\u00A0]{5,}\\d(?![\\w@])")
    /// "2026-10-28": a date, not a phone number.
    private static let datePattern = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
}

/// A Choice question holds at most 255 options (Jev's limit), so a search
/// by meaning among more candidates asks in rounds: 240 to a question,
/// all asked at once, each one's likely picks kept (≥ 4 %, eight at most),
/// then one question among those picks; again if they are still too many.
public enum MeaningRounds {
    /// Candidates in one question (with "none", under Jev's 255).
    public static let questionSize = 240
    /// What a part's answer keeps: likely enough, a few at most.
    public static let keptShare = 0.04
    public static let keptCount = 8
    /// Questions waiting on an answer at once; the rest start as those end.
    public static let inFlight = 16

    /// One answer: the choice and every option's probability, by value.
    public struct Answer: Equatable, Sendable {
        public var choice: String
        public var probabilities: [String: Double]

        public init(choice: String, probabilities: [String: Double]) {
            self.choice = choice
            self.probabilities = probabilities
        }

        /// "none", sure: nothing fits.
        public static let nothing = Answer(choice: "none", probabilities: ["none": 1])
    }

    /// The last answer; how many questions were asked, in how many
    /// rounds; how many parts the first round had, and how many questions
    /// got no answer (left out).
    public struct Outcome: Equatable, Sendable {
        public var answer: Answer
        public var questions: Int
        public var rounds: Int
        public var parts: Int
        public var unanswered: Int
    }

    /// The values a part's answer keeps, best first.
    public static func kept(_ probabilities: [String: Double]) -> [String] {
        probabilities
            .filter { $0.key != "none" && $0.value >= keptShare }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(keptCount)
            .map(\.key)
    }

    /// `values` in parts of `size`, in their order.
    public static func parts<T>(_ values: [T], size: Int = questionSize) -> [[T]] {
        stride(from: 0, to: values.count, by: max(1, size)).map { Array(values[$0..<min(values.count, $0 + max(1, size))]) }
    }

    /// Asks about every value: one question when they fit in one, else
    /// each part (`inFlight` at a time), then the same again among the
    /// picks kept, in their first order. `ask` gets the values of one
    /// question and answers it (with "none" among the options), nil when
    /// its model did not answer in time. Nil: no part answered, or the one
    /// question did not; an error of the one question, or of every part,
    /// is thrown. Parts that did not answer are counted and left out.
    public static func decide(_ values: [String], size: Int = questionSize, inFlight: Int = inFlight,
                              ask: @escaping @Sendable ([String]) async throws -> Answer?) async throws -> Outcome? {
        guard values.count > size else {
            guard let answer = try await ask(values) else { return nil }
            return Outcome(answer: answer, questions: 1, rounds: 1, parts: 1, unanswered: 0)
        }
        let parts = Self.parts(values, size: size)
        var picked = Set<String>()
        var answered = 0
        var failure: Error?
        try await withThrowingTaskGroup(of: Result<Answer?, Error>.self) { group in
            var next = 0
            func start() {
                guard next < parts.count else { return }
                let part = parts[next]
                next += 1
                group.addTask {
                    do {
                        return .success(try await ask(part))
                    } catch {
                        // A newer search: stop every part.
                        if error is CancellationError || Task.isCancelled { throw CancellationError() }
                        return .failure(error)
                    }
                }
            }
            for _ in 0..<min(max(1, inFlight), parts.count) { start() }
            while let result = try await group.next() {
                switch result {
                case .success(let answer?):
                    answered += 1
                    picked.formUnion(kept(answer.probabilities))
                case .success(nil):
                    break
                case .failure(let error):
                    failure = failure ?? error
                }
                start()
            }
        }
        try Task.checkCancellation()
        guard answered > 0 else {
            if let failure { throw failure }
            return nil
        }
        let unanswered = parts.count - answered
        let picks = values.filter(picked.contains)
        guard !picks.isEmpty else {
            return Outcome(answer: .nothing, questions: parts.count, rounds: 1, parts: parts.count, unanswered: unanswered)
        }
        // The picks of every part side by side: the one answer.
        guard let final = try await decide(picks, size: size, inFlight: inFlight, ask: ask) else { return nil }
        return Outcome(answer: final.answer, questions: parts.count + final.questions, rounds: 1 + final.rounds, parts: parts.count,
                       unanswered: unanswered + final.unanswered)
    }
}
