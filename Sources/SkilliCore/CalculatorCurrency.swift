import Foundation

/// What the calculator needs to convert currencies; nil when Convert
/// Currencies is off (Settings → Catalog).
public struct CurrencyContext: Sendable {
    /// The day's table; nil until the first one is read.
    public var rates: CurrencyRates?
    /// Said in the row while there is no table yet: "Getting today's rates…".
    public var waiting: String
    /// The currency last picked from each currency ("USD": "EUR"), for an
    /// amount typed in the user's own currency with no target.
    public var lastTargets: [String: String]
    /// The user's currency, when it is not the number locale's (a tool
    /// reads numbers in English for a Canadian user: "dollars" is CAD).
    public var home: String?

    public init(rates: CurrencyRates?, waiting: String = "Getting today's rates…", lastTargets: [String: String] = [:], home: String? = nil) {
        self.rates = rates
        self.waiting = waiting
        self.lastTargets = lastTargets
        self.home = home
    }
}

extension Calculator {
    /// The ISO code `name` stands for ("euros", "€", "try"), the
    /// ambiguous ones ("$", "dollars") read for a user of `home`.
    public static func currencyCode(_ name: String, home: String) -> String? {
        Money.code(name, home: home)
    }

    /// A currency conversion's parts, for ⌘K (Copy Rate) and for learning
    /// the target picked.
    public struct Conversion: Equatable, Sendable {
        public let from: String
        public let to: String
        /// "1 TRY = 0,01797 EUR".
        public let rate: String
    }

    // MARK: - Currencies

    /// "800 TRY", "800 TRY in €", "€49 en dollars", "100 usd in eur, gbp":
    /// one row per target. Read as it is typed: while the target is half
    /// typed ("800 TRY in e") the row stays on the user's own currency.
    static func currencies(_ text: String, locale: Locale, now: Date, context: CurrencyContext) -> [Result] {
        // Most keys typed are words: nothing more to read.
        guard text.contains(where: \.isNumber) else { return [] }
        let home = context.home ?? locale.currency?.identifier ?? "USD"
        let known: (String) -> Bool = { code in context.rates.map { $0.rates[code] != nil } ?? true }
        for separator in [" in ", " to ", " en ", " into ", " → ", " -> ", " = "] {
            guard let range = text.range(of: separator, options: [.backwards, .caseInsensitive]) else { continue }
            guard let source = Money.source(String(text[..<range.lowerBound]), locale: locale, home: home), known(source.code) else { continue }
            let parts = text[range.upperBound...].lowercased().split(whereSeparator: { $0 == "," || $0 == "+" }).flatMap { $0.components(separatedBy: " and ") }
                .flatMap { $0.components(separatedBy: " et ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var targets: [String] = []
            var partial = parts.isEmpty
            for part in parts {
                if let code = Money.code(part, home: home) {
                    // A currency the day's table lacks: no guess.
                    guard known(code) else { return [] }
                    if code != source.code, !targets.contains(code) { targets.append(code) }
                } else if Money.couldStart(part) {
                    partial = true
                } else {
                    return []
                }
            }
            if targets.isEmpty {
                // "800 TRY in e": the answer it had, in the user's currency.
                guard partial, let fallback = defaultTarget(for: source.code, home: home, context: context) else { return [] }
                targets = [fallback]
            }
            return targets.compactMap { answer(source, to: $0, locale: locale, now: now, context: context) }
        }
        // "800 TRY i", "800 TRY in": the separator on its way.
        var stem = text
        if let space = text.lastIndex(of: " "), Money.separatorStarts.contains(text[text.index(after: space)...].lowercased()) {
            stem = String(text[..<space])
        }
        guard let source = Money.source(stem, locale: locale, home: home), known(source.code),
              let target = defaultTarget(for: source.code, home: home, context: context)
        else { return [] }
        return answer(source, to: target, locale: locale, now: now, context: context).map { [$0] } ?? []
    }

    /// The user's own currency; from it, the one last picked, else the
    /// dollar (the euro for dollar users).
    static func defaultTarget(for source: String, home: String, context: CurrencyContext) -> String? {
        if source != home { return home }
        if let last = context.lastTargets[source], last != source { return last }
        return source == "USD" ? "EUR" : "USD"
    }

    static func answer(_ source: Money.Read, to target: String, locale: Locale, now: Date, context: CurrencyContext) -> Result? {
        let what = "\(Money.plain(source.amount, locale: locale)) \(source.code) → \(target)"
        guard let rates = context.rates else {
            return Result(display: context.waiting, copy: "", detail: what, isWaiting: true)
        }
        guard let rate = rates.rate(from: source.code, to: target), let day = rates.day(from: source.code, to: target) else { return nil }
        let value = source.amount * rate
        let digits = Money.fractionDigits(target)
        var rounded = Decimal()
        var exact = value
        NSDecimalRound(&rounded, &exact, digits, .plain)
        // Less than a cent: three significant digits rather than "0,00 €".
        let tiny = rounded == 0 && value != 0
        let display = tiny
            ? value.formatted(.currency(code: target).precision(.significantDigits(1...3)).locale(locale))
            : rounded.formatted(.currency(code: target).precision(.fractionLength(digits)).locale(locale))
        let copy = tiny
            ? value.formatted(.number.precision(.significantDigits(1...3)).grouping(.never).locale(locale))
            : rounded.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale))
        let rateText = "1 \(source.code) = \(Money.rate(rate, locale: locale)) \(target)"
        return Result(display: display, copy: copy, detail: "\(what) · \(rateText) · \(Money.day(day, locale: locale, now: now))",
                      conversion: Conversion(from: source.code, to: target, rate: rateText))
    }

    /// Reading amounts and currencies as people type them.
    enum Money {
        struct Read: Equatable {
            let amount: Decimal
            let code: String
        }

        /// What may follow an amount on its way to " in …": "i", "in", "t"…
        static let separatorStarts: Set<String> = ["i", "in", "int", "into", "t", "to", "e", "en", "-", "->", "→", "="]

        /// An amount with its currency, before or after it: "800 TRY",
        /// "€49", "1 299 $", "USD 100", "2,5k usd".
        static func source(_ text: String, locale: Locale, home: String) -> Read? {
            let typed = text.trimmingCharacters(in: .whitespaces)
            guard !typed.isEmpty, typed.contains(where: \.isNumber) else { return nil }
            // After the amount: the longest name it ends with.
            for split in typed.indices where split != typed.startIndex {
                let before = typed[typed.index(before: split)].lowercased()
                guard before.first?.isNumber == true || before == " " || before == "k" || before == "m" else { continue }
                let name = typed[split...].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let code = code(name, home: home),
                      let amount = amount(typed[..<split].lowercased(), locale: locale) else { continue }
                return Read(amount: amount, code: code)
            }
            // Before it: a symbol ("$1,299", "€49") or a code in capitals
            // ("USD 100"); "try 800" is not a currency.
            for split in typed.indices where split != typed.startIndex {
                let after = typed[split]
                guard after.isNumber || after == " " || after == "-" else { continue }
                let name = typed[..<split].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, symbols[name.lowercased()] != nil || (codes.contains(name) && name == name.uppercased()),
                      let code = code(name, home: home), let amount = amount(typed[split...].lowercased(), locale: locale) else { continue }
                return Read(amount: amount, code: code)
            }
            return nil
        }

        /// "800", "1 299,50", "2,5k", "3m", "2 * 49".
        static func amount(_ text: String, locale: Locale) -> Decimal? {
            var text = text.trimmingCharacters(in: .whitespaces)
            var factor: Decimal = 1
            if text.hasSuffix("k") {
                factor = 1_000
                text.removeLast()
            } else if text.hasSuffix("m") {
                factor = 1_000_000
                text.removeLast()
            }
            text = text.trimmingCharacters(in: .whitespaces)
            guard let first = text.first, first.isNumber || first == "-" || first == "(" || first == "." else { return nil }
            var parser = Parser(text: text, decimalComma: usesDecimalComma(text, locale: locale))
            guard let value = parser.parse(), value.isFinite, let decimal = CurrencyRates.decimal(value) else { return nil }
            return decimal * factor
        }

        /// A currency by its code, symbol or name, in any case; the
        /// ambiguous ones by the user's own currency ("$" in Canada is CAD).
        static func code(_ name: String, home: String) -> String? {
            let key = name.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
            if codes.contains(key.uppercased()) { return key.uppercased() }
            if let symbol = symbols[key] { return resolve(symbol, home: home) }
            if let word = words[singular(key)] { return resolve(word, home: home) }
            return nil
        }

        /// Whether `partial` could still become a currency as typing goes on.
        static func couldStart(_ partial: String) -> Bool {
            let key = partial.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            guard !key.isEmpty else { return true }
            return startKeys.contains { $0.hasPrefix(key) }
        }

        // MARK: Names

        /// The ambiguous ones, decided by the user's currency.
        private static let dollars: Set<String> = ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "TWD"]
        private static let dollarSigns: Set<String> = ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "TWD", "MXN", "ARS", "CLP", "COP"]
        private static let pesos: Set<String> = ["MXN", "ARS", "CLP", "COP", "PHP", "UYU", "DOP", "CUP"]
        private static let kronor: Set<String> = ["SEK", "NOK", "DKK", "ISK"]

        private static func resolve(_ found: String, home: String) -> String? {
            switch found {
            case "$": dollarSigns.contains(home) ? home : "USD"
            case "dollar": dollars.contains(home) ? home : "USD"
            case "peso": pesos.contains(home) ? home : nil
            case "kr": kronor.contains(home) ? home : nil
            case "¥": home == "CNY" ? "CNY" : "JPY"
            default: found
            }
        }

        /// ISO 4217 codes, as Foundation knows them.
        static let codes: Set<String> = Set(Locale.commonISOCurrencyCodes)

        static let symbols: [String: String] = [
            "$": "$", "€": "EUR", "£": "GBP", "¥": "¥", "円": "JPY", "₹": "INR", "₺": "TRY", "₽": "RUB", "₩": "KRW", "₪": "ILS",
            "₫": "VND", "฿": "THB", "₱": "PHP", "₴": "UAH", "₦": "NGN", "₸": "KZT", "₾": "GEL", "zł": "PLN", "kč": "CZK",
            "kr": "kr", "r$": "BRL", "us$": "USD", "c$": "CAD", "ca$": "CAD", "a$": "AUD", "au$": "AUD", "nz$": "NZD",
            "hk$": "HKD", "s$": "SGD", "mx$": "MXN", "nt$": "TWD", "fr": "CHF", "sfr": "CHF"
        ]

        /// Names in English, French and the Mac's languages ("livre
        /// turque", "turkish lira"), and the words people say, singular.
        static let words: [String: String] = {
            var words: [String: String] = [:]
            let languages = (["en", "fr"] + Locale.preferredLanguages.prefix(3)).map { Locale(identifier: $0) }
            for code in Locale.commonISOCurrencyCodes {
                for language in languages {
                    guard let name = language.localizedString(forCurrencyCode: code) else { continue }
                    let key = singular(name.lowercased().folding(options: .diacriticInsensitive, locale: nil))
                    if words[key] == nil { words[key] = code }
                }
            }
            let said: [String: [String]] = [
                "dollar": ["dollar", "buck"],
                // Named, never the user's own dollar.
                "USD": ["us dollar", "dollar americain", "american dollar", "dollar us", "dollar des etats-uni"],
                "EUR": ["euro", "balle"], "GBP": ["pound", "livre", "livre sterling", "sterling", "quid"],
                "JPY": ["yen"], "CNY": ["yuan", "rmb", "renminbi"], "CHF": ["franc suisse", "swiss franc", "franc"],
                "TRY": ["lira", "lire", "livre turque", "turkish lira"], "RUB": ["rouble", "ruble"], "INR": ["rupee", "roupie"],
                "BRL": ["real", "reai"], "KRW": ["won"], "THB": ["baht"], "PLN": ["zloty"], "HUF": ["forint"], "ZAR": ["rand"],
                "ILS": ["shekel", "sheqel"], "AED": ["dirham"], "VND": ["dong"], "MYR": ["ringgit"], "peso": ["peso"],
                "kr": ["krona", "krone", "couronne", "kronor", "kroner"]
            ]
            for (code, names) in said {
                for name in names { words[singular(name)] = code }
            }
            return words
        }()

        /// Every name a typed target may still grow into.
        private static let startKeys: [String] = Array(Set(codes.map { $0.lowercased() }).union(symbols.keys).union(words.keys))

        /// "dollars canadiens" and "dollar canadien" alike: each word
        /// without its final s.
        static func singular(_ name: String) -> String {
            name.split(separator: " ").map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : String($0) }.joined(separator: " ")
        }

        // MARK: Numbers

        /// The currency's own decimals: 2 for EUR, 0 for JPY, 3 for KWD.
        static func fractionDigits(_ code: String) -> Int {
            decimals[code] ?? 2
        }

        /// Read once for every currency (ICU's minor units).
        private static let decimals: [String: Int] = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            var decimals: [String: Int] = [:]
            for code in Locale.commonISOCurrencyCodes {
                formatter.currencyCode = code
                decimals[code] = formatter.maximumFractionDigits
            }
            return decimals
        }()

        static func plain(_ value: Decimal, locale: Locale) -> String {
            value.formatted(.number.precision(.fractionLength(0...4)).locale(locale))
        }

        /// "0,01797", "1,1186", "28 867".
        static func rate(_ value: Decimal, locale: Locale) -> String {
            value >= 1
                ? value.formatted(.number.precision(.fractionLength(0...4)).locale(locale))
                : value.formatted(.number.precision(.significantDigits(1...4)).locale(locale))
        }

        /// "27 Oct"; older than four days (a long weekend is three):
        /// "rates of 23 Oct, not updated".
        static func day(_ day: String, locale: Locale, now: Date) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return day }
            var style = Date.FormatStyle(date: .omitted, time: .omitted).day().month(.abbreviated).locale(locale)
            style.timeZone = calendar.timeZone
            let shown = date.formatted(style)
            return now.timeIntervalSince(date) > 4.5 * 86_400 ? "rates of \(shown), not updated" : shown
        }
    }
}
