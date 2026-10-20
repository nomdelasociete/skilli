import Foundation

/// The values Ask acts with (how long, until when, how loud, what for),
/// read by the decision model (TypeSafe Jev, else OpenAI Decisions), never
/// by a regex reading the sentence: a sentence a regex half reads ("une
/// heure trente" read as one hour, "rappelle-moi dans 1h et quart…" as a
/// timer) is acted on wrong. Each value is picked among fixed options (a
/// length as one option however it is said; an end time as its hour and
/// its minutes), asked together in one request (answered in parallel),
/// and put together here, in code. The model never computes a value; a
/// part it is unsure of (under `sureFrom`) makes Ask check with the user
/// first. A value the request does not give is asked in the card
/// (`Missing`), the answer read the same way.
public enum AskValues {
    /// One question of the request, as the decision client sends it.
    public struct Question: Equatable, Sendable {
        public let name: String
        public let instructions: String
        public let options: [Option]
    }

    public struct Option: Equatable, Sendable {
        public let value: String
        public let description: String

        init(_ value: String, _ description: String) {
            self.value = value
            self.description = description
        }
    }

    /// One answer: the option picked and how sure the model is of it.
    public struct Answer: Equatable, Sendable {
        public let choice: String
        public let confidence: Double
        /// Words picked in the user's answer to the card's question
        /// (`Missing`), not in the request: a name, what a reminder says.
        /// They stand for the request's words this value would be.
        public let said: String?

        public init(choice: String, confidence: Double, said: String? = nil) {
            self.choice = choice
            self.confidence = confidence
            self.said = said
        }
    }

    /// Under this, a part is unsure: Ask says what it understood and waits
    /// for ↩ (TypeSafe's review threshold).
    public static let sureFrom = 0.6

    static let none = Option("none", "Not said in the request")

    // MARK: - How long, or until when

    /// The lengths a request can say, each one option: "une heure trente",
    /// "an hour and a half" and "90 minutes" are the same option, so no
    /// split of it can be read two ways. Asked as parts (an amount, a unit,
    /// minutes after), Jev read "an hour and a half" as 90 for the amount
    /// and hours for the unit: 3 days 18 h 30, at 69 %. Seconds to 45,
    /// every minute to an hour, every 5 to 4 h, every 15 to 12 h, every
    /// hour to a day, then 36 h and days to a week.
    static let lengths: [(value: String, seconds: Int, description: String)] = {
        var minutes = Array(1...60) + Array(stride(from: 65, through: 240, by: 5)) + Array(stride(from: 255, through: 720, by: 15))
            + Array(stride(from: 780, through: 1_440, by: 60)) + [2_160]
        minutes += (2...7).map { $0 * 1_440 }
        let seconds = [5, 10, 15, 20, 30, 45].map { ("\($0) s", $0, "\($0) seconds") }
        let halves = [("1 min 30 s", 90, "1 minute 30 seconds = 90 seconds"), ("2 min 30 s", 150, "2 minutes 30 seconds = 150 seconds")]
        return seconds + halves + minutes.map { total in
            let hours = total / 60, rest = total % 60
            let words: String
            switch (hours, rest) {
            case (0, 15): words = "15 minutes = a quarter of an hour = un quart d'heure"
            case (0, 30): words = "30 minutes = half an hour = une demi-heure"
            case (0, 45): words = "45 minutes = three quarters of an hour = trois quarts d'heure"
            case (0, _): words = total == 1 ? "1 minute" : "\(total) minutes"
            case (_, 0) where hours % 24 == 0: words = hours == 24 ? "1 day = 24 hours" : "\(hours / 24) days = \(hours) hours"
            case (_, 0): words = hours == 1 ? "1 hour = 60 minutes" : "\(hours) hours = \(total) minutes"
            default:
                let english = [15: " and a quarter", 30: " and a half", 45: " and three quarters"][rest].map { " = \(hours == 1 ? "an hour" : "\(hours) hours")\($0)" } ?? ""
                let french = [15: " et quart", 30: " et demie"][rest].map { " = \(hours == 1 ? "une heure" : "\(hours) heures")\($0)" } ?? ""
                let part = english + french
                words = "\(hours) h \(String(format: "%02d", rest)) = \(total) minutes" + part
            }
            let value = hours == 0 ? "\(total) min" : (rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))")
            return (value, total * 60, words)
        }
    }()

    static let lengthQuestion = Question(
        name: "length",
        instructions: "How long does the request say to last or to wait? Read the whole length, hours and minutes together, and pick it among these: une heure trente, 1h30, an hour and a half, une heure et demie, 90 minutes → 1 h 30; 1h et quart, an hour and a quarter → 1 h 15; une heure → 1 h; une demi-heure → 30 min; un quart d'heure → 15 min; dans 20 minutes, in 20 minutes → 20 min; deux jours → 48 h. Pick until when it says a time of day to last until instead (until 6pm, jusqu'à 18h30, jusqu'à midi), none when it says no length.",
        options: lengths.map { Option($0.value, $0.description) }
            + [Option("until", "Until a time of day: until 6pm, jusqu'à 18h30, jusqu'à midi"),
               Option("none", "No length and no time of day")])

    static let untilHour = Question(
        name: "until_hour",
        instructions: "The hour of the time of day it should last until, on a 24-hour clock: until 6pm → 18; jusqu'à 18h30 → 18; until noon, jusqu'à midi → 12; jusqu'à minuit → 0. None when it says no time of day.",
        options: (0...23).map { Option("\($0)", "\($0) h") } + [none])

    static let untilMinute = Question(
        name: "until_minute",
        instructions: "The minutes of the time of day it should last until: jusqu'à 18h30 → 30; until 6pm → 0; until a quarter past five → 15. None when it says no time of day.",
        options: (0...59).map { Option("\($0)", ":\(String(format: "%02d", $0))") } + [none])

    /// The questions that read a length of time or an end time.
    public static let durationQuestions = [lengthQuestion, untilHour, untilMinute]

    static let secondsByLength = Dictionary(uniqueKeysWithValues: lengths.map { ($0.value, $0.seconds) })

    /// A length question of another meaning (in how long, how long an
    /// event lasts): the same lengths, and none.
    static func lengthQuestion(name: String, instructions: String) -> Question {
        Question(name: name, instructions: instructions, options: lengths.map { Option($0.value, $0.description) } + [none])
    }

    /// What the answers say, in seconds from `now`, and how sure: the
    /// least sure part used. Nil when no time is said or a part is missing.
    public static func duration(_ answers: [String: Answer], now: Date = .now, calendar: Calendar = .current) -> (seconds: Int, confidence: Double)? {
        guard let length = answers[lengthQuestion.name] else { return nil }
        if let seconds = secondsByLength[length.choice] {
            return (seconds, length.confidence)
        }
        guard length.choice == "until", let hourAnswer = answers[untilHour.name], let hour = Int(hourAnswer.choice) else { return nil }
        let minuteAnswer = answers[untilMinute.name]
        let minute = minuteAnswer.flatMap { Int($0.choice) } ?? 0
        var parts = [length.confidence, hourAnswer.confidence]
        if let minuteAnswer, Int(minuteAnswer.choice) != nil { parts.append(minuteAnswer.confidence) }
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        let end = today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return (Int(end.timeIntervalSince(now).rounded()), parts.min() ?? 0)
    }

    // MARK: - How loud

    static let levelQuestion = Question(
        name: "level",
        instructions: "The level in percent the request asks for: le son à 30 → 30; trente pour cent → 30; volume à la moitié, half → 50; à fond, max, full → 100; tout bas → 10.",
        options: (0...100).map { Option("\($0)", "\($0) %") } + [none])

    public static let levelQuestions = [levelQuestion]

    /// The level the answers say, 0 to 100, and how sure.
    public static func level(_ answers: [String: Answer]) -> (level: Int, confidence: Double)? {
        guard let answer = answers[levelQuestion.name], let level = Int(answer.choice), (0...100).contains(level) else { return nil }
        return (level, answer.confidence)
    }

    // MARK: - What for: words of the request

    /// "What for" picked among the request's own words, never written by
    /// the model (`phrases`): "mets un minuteur de dix minutes pour les
    /// pâtes" offers "les pâtes".
    public static func spans(of request: String, longest: Int = 6) -> [String] {
        phrases(of: words(of: request), longest: longest)
    }

    /// A timer's name, picked among `spans`: what it is for, as said.
    public static func labelQuestion(spans: [String]) -> Question {
        phraseQuestion(name: "label",
                       instructions: "What is the timer for, in the request's own words? mets un minuteur de dix minutes pour les pâtes → les pâtes; timer 5 min tea → tea; set a timer for the oven → the oven. Pick none when it says nothing it is for.",
                       phrases: spans, none: "It says nothing the timer is for")
    }

    /// The span picked, or nil for none.
    public static func label(_ answers: [String: Answer], spans: [String]) -> String? {
        phrase(answers, "label", phrases: spans)?.text
    }
}
