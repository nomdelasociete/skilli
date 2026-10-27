import Foundation

/// The launcher's calculator: arithmetic as people type it ("12,5 × 4",
/// "20 % de 85", "85 + 20%"), unit conversions ("10 km en miles",
/// "32 °F to °C"), currencies ("800 TRY in €", CalculatorCurrency.swift)
/// and the time elsewhere ("heure à Tokyo"). A hand-written parser: no
/// `NSExpression`, nothing evaluated but numbers.
public enum Calculator {
    public struct Result: Equatable, Sendable {
        /// What the row shows: "1 234,5", "16,09 km".
        public let display: String
        /// The same without grouping, what Return pastes and ⌘Return or ⌘C
        /// copy: "1234,5".
        public let copy: String
        /// What it understood: "10 mi → km", "20 % of 85".
        public let detail: String
        /// A currency read while the day's rates are not here yet: shown,
        /// nothing to paste.
        public var isWaiting = false
        /// A currency conversion's parts.
        public var conversion: Conversion?
    }

    /// Nil when the text is not a calculation (a word, a lone number).
    public static func evaluate(_ text: String, locale: Locale = .current, now: Date = .now, currency: CurrencyContext? = nil) -> Result? {
        answers(text, locale: locale, now: now, currency: currency).first
    }

    /// Every answer, first the one shown first: "100 usd in eur, gbp" is two.
    public static func answers(_ text: String, locale: Locale = .current, now: Date = .now, currency: CurrencyContext? = nil) -> [Result] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return [] }
        if let zone = timeIn(trimmed, now: now, locale: locale) { return [zone] }
        if let converted = conversion(trimmed, locale: locale) { return [converted] }
        if let currency {
            let money = currencies(trimmed, locale: locale, now: now, context: currency)
            if !money.isEmpty { return money }
        }
        return arithmetic(trimmed, locale: locale).map { [$0] } ?? []
    }

    // MARK: - Arithmetic

    static func arithmetic(_ text: String, locale: Locale) -> Result? {
        var parser = Parser(text: text, decimalComma: usesDecimalComma(text, locale: locale))
        guard let value = parser.parse(), value.isFinite, parser.sawOperation else { return nil }
        let display = format(value, locale: locale, grouping: true)
        return Result(display: display, copy: format(value, locale: locale, grouping: false), detail: text)
    }

    /// "12,5" is a decimal in French; "1,234.5" groups in English.
    static func usesDecimalComma(_ text: String, locale: Locale) -> Bool {
        if text.contains(".") && text.contains(",") { return text.lastIndex(of: ",")! > text.lastIndex(of: ".")! }
        if text.contains(",") {
            // "1,234" in English groups thousands; "12,5" is a decimal.
            if locale.decimalSeparator == "," { return true }
            let parts: [Substring] = text.split(separator: Character(","))
            let afterComma = parts.dropFirst().allSatisfy { part in
                part.prefix { $0.isNumber }.count == 3
            }
            return !afterComma
        }
        return false
    }

    struct Parser {
        let characters: [Character]
        let decimalComma: Bool
        var index = 0
        /// A lone number is not a calculation.
        var sawOperation = false

        init(text: String, decimalComma: Bool) {
            characters = Array(text.lowercased()
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: "\u{202F}", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: ""))
            self.decimalComma = decimalComma
        }

        mutating func parse() -> Double? {
            guard let value = expression() else { return nil }
            skipSpaces()
            return index == characters.count ? value.number : nil
        }

        /// A value, and whether it was written as a percentage ("20%").
        struct Value {
            var number: Double
            var isPercent = false
        }

        private mutating func expression() -> Value? {
            guard var left = term() else { return nil }
            while true {
                skipSpaces()
                guard let op = peek(), op == "+" || op == "-" else { return left }
                index += 1
                guard let right = term() else { return nil }
                sawOperation = true
                // "85 + 20%" is 85 and its 20 %.
                let amount = right.isPercent ? left.number * right.number : right.number
                left = Value(number: op == "+" ? left.number + amount : left.number - amount)
            }
        }

        private mutating func term() -> Value? {
            guard var left = power() else { return nil }
            while true {
                skipSpaces()
                if let op = peek(), op == "*" || op == "/" || (op == "x" && isOperatorX()) {
                    index += 1
                    guard let right = power() else { return nil }
                    sawOperation = true
                    left = Value(number: op == "/" ? left.number / right.number : left.number * right.number)
                } else if matchWord(["of", "de", "du", "des", "sur"]) {
                    // "20 % de 85": a percentage of something.
                    guard left.isPercent, let right = power() else { return nil }
                    sawOperation = true
                    left = Value(number: left.number * right.number)
                } else {
                    return left
                }
            }
        }

        private mutating func power() -> Value? {
            guard let base = unary() else { return nil }
            skipSpaces()
            guard peek() == "^" else { return base }
            index += 1
            guard let exponent = power() else { return nil }
            sawOperation = true
            return Value(number: Foundation.pow(base.number, exponent.number))
        }

        private mutating func unary() -> Value? {
            skipSpaces()
            if peek() == "-" {
                index += 1
                return unary().map { Value(number: -$0.number, isPercent: $0.isPercent) }
            }
            if peek() == "+" {
                index += 1
                return unary()
            }
            guard var value = primary() else { return nil }
            skipSpaces()
            if peek() == "%" {
                index += 1
                value = Value(number: value.number / 100, isPercent: true)
            }
            return value
        }

        private mutating func primary() -> Value? {
            skipSpaces()
            guard let character = peek() else { return nil }
            if character == "(" {
                index += 1
                guard let inner = expression() else { return nil }
                skipSpaces()
                guard peek() == ")" else { return nil }
                index += 1
                return inner
            }
            if character.isNumber || character == "." || character == "," { return number() }
            if character == "π" {
                index += 1
                return Value(number: .pi)
            }
            if character.isLetter || character == "√" { return function() }
            return nil
        }

        private mutating func number() -> Value? {
            var text = ""
            while let character = peek(), character.isNumber || character == "." || character == "," || character == " " {
                if character == " " {
                    // "1 234" groups thousands; "2 3" is not a number.
                    let next = characters[index...].dropFirst().prefix { $0.isNumber }
                    guard !text.isEmpty, next.count == 3 else { break }
                    index += 1
                    continue
                }
                text.append(character)
                index += 1
            }
            let normalized = decimalComma
                ? text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                : text.replacingOccurrences(of: ",", with: "")
            return Double(normalized).map { Value(number: $0) }
        }

        private mutating func function() -> Value? {
            if peek() == "√" {
                index += 1
                sawOperation = true
                return unary().map { Value(number: $0.number.squareRoot()) }
            }
            var name = ""
            while let character = peek(), character.isLetter { name.append(character); index += 1 }
            switch name {
            case "pi": return Value(number: .pi)
            case "e": return Value(number: M_E)
            default: break
            }
            let functions: [String: (Double) -> Double] = [
                "sqrt": { $0.squareRoot() }, "racine": { $0.squareRoot() },
                "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
                "ln": { Foundation.log($0) }, "log": { Foundation.log10($0) },
                "abs": { Swift.abs($0) }, "round": { $0.rounded() }, "floor": { Foundation.floor($0) }, "ceil": { Foundation.ceil($0) }
            ]
            guard let function = functions[name] else { return nil }
            skipSpaces()
            guard peek() == "(" else { return nil }
            guard let argument = primary() else { return nil }
            sawOperation = true
            return Value(number: function(argument.number))
        }

        /// "x" multiplies between numbers ("3 x 4"), not inside a word.
        private func isOperatorX() -> Bool {
            let next = characters[(index + 1)...].first { $0 != " " }
            return next.map { $0.isNumber || $0 == "(" || $0 == "." } ?? false
        }

        private mutating func matchWord(_ words: [String]) -> Bool {
            skipSpaces()
            for word in words {
                let end = index + word.count
                guard end <= characters.count, String(characters[index..<end]) == word else { continue }
                if end < characters.count, characters[end].isLetter { continue }
                index = end
                return true
            }
            return false
        }

        private func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " { index += 1 }
        }
    }

    // MARK: - Units

    /// "10 km en miles", "32 °F to °C", "1,5 Go en Mo", "100 km/h in mph".
    static func conversion(_ text: String, locale: Locale) -> Result? {
        let lower = text.lowercased()
        for separator in [" in ", " to ", " en ", " into ", " → ", " -> ", " = "] {
            guard let range = lower.range(of: separator, options: .backwards) else { continue }
            let source = lower[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let target = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard let to = Units.unit(target) else { continue }
            // The unit is the longest name the source ends with.
            for split in source.indices.reversed() where split == source.startIndex || source[source.index(before: split)].isNumber || source[source.index(before: split)] == " " {
                let name = source[split...].trimmingCharacters(in: .whitespaces)
                let amount = source[..<split].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !amount.isEmpty, let from = Units.unit(name), Units.kind(from) == Units.kind(to) else { continue }
                var parser = Parser(text: amount, decimalComma: usesDecimalComma(amount, locale: locale))
                guard let value = parser.parse() else { continue }
                let converted = Measurement(value: value, unit: from).converted(to: to).value
                let display = format(converted, locale: locale, grouping: true) + " " + Units.symbol(to)
                return Result(display: display, copy: format(converted, locale: locale, grouping: false),
                              detail: "\(format(value, locale: locale, grouping: true)) \(Units.symbol(from)) → \(Units.symbol(to))")
            }
        }
        return nil
    }

    enum Units {
        static func unit(_ name: String) -> Dimension? {
            let key = name.lowercased().replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
            return table[key] ?? (key.hasSuffix("s") ? table[String(key.dropLast())] : nil)
        }

        /// Length, mass…: Foundation's own units are private subclasses,
        /// so `type(of:)` cannot tell.
        static func kind(_ unit: Dimension) -> String {
            switch unit {
            case is UnitLength: "length"
            case is UnitMass: "mass"
            case is UnitTemperature: "temperature"
            case is UnitVolume: "volume"
            case is UnitInformationStorage: "storage"
            case is UnitDuration: "duration"
            case is UnitSpeed: "speed"
            case is UnitArea: "area"
            case is UnitEnergy: "energy"
            default: String(describing: Swift.type(of: unit))
            }
        }

        static func symbol(_ unit: Dimension) -> String {
            if unit == UnitTemperature.celsius { return "°C" }
            if unit == UnitTemperature.fahrenheit { return "°F" }
            return unit.symbol
        }

        static let table: [String: Dimension] = {
            var table: [String: Dimension] = [:]
            func add(_ unit: Dimension, _ names: [String]) { for name in names { table[name] = unit } }
            add(UnitLength.kilometers, ["km", "kilometer", "kilometre", "kilomètre"])
            add(UnitLength.meters, ["m", "meter", "metre", "mètre"])
            add(UnitLength.centimeters, ["cm", "centimeter", "centimetre", "centimètre"])
            add(UnitLength.millimeters, ["mm", "millimeter", "millimetre", "millimètre"])
            add(UnitLength.miles, ["mi", "mile"])
            add(UnitLength.feet, ["ft", "foot", "feet", "pied"])
            add(UnitLength.inches, ["in", "inch", "inche", "pouce", "\""])
            add(UnitLength.yards, ["yd", "yard"])
            add(UnitLength.nauticalMiles, ["nmi", "nautical mile", "mille marin"])
            add(UnitMass.kilograms, ["kg", "kilo", "kilogram", "kilogramme"])
            add(UnitMass.grams, ["g", "gram", "gramme"])
            add(UnitMass.milligrams, ["mg"])
            // Exact definitions where Foundation rounds (0.453592 for a pound).
            add(UnitMass(symbol: "lb", converter: UnitConverterLinear(coefficient: 0.45359237)), ["lb", "lbs", "pound", "livre"])
            add(UnitMass(symbol: "oz", converter: UnitConverterLinear(coefficient: 0.028349523125)), ["oz", "ounce", "once"])
            add(UnitMass(symbol: "st", converter: UnitConverterLinear(coefficient: 6.35029318)), ["st", "stone"])
            add(UnitMass.metricTons, ["t", "ton", "tonne"])
            add(UnitTemperature.celsius, ["c", "celsius", "degré celsius"])
            add(UnitTemperature.fahrenheit, ["f", "fahrenheit"])
            add(UnitTemperature.kelvin, ["k", "kelvin"])
            add(UnitVolume.liters, ["l", "liter", "litre"])
            add(UnitVolume.milliliters, ["ml", "milliliter", "millilitre"])
            add(UnitVolume.centiliters, ["cl", "centilitre", "centiliter"])
            // US customary, exact (liters).
            add(UnitVolume(symbol: "gal", converter: UnitConverterLinear(coefficient: 3.785411784)), ["gal", "gallon"])
            add(UnitVolume(symbol: "cup", converter: UnitConverterLinear(coefficient: 0.2365882365)), ["cup", "tasse"])
            add(UnitVolume(symbol: "fl oz", converter: UnitConverterLinear(coefficient: 0.0295735295625)), ["fl oz", "floz"])
            add(UnitVolume(symbol: "tbsp", converter: UnitConverterLinear(coefficient: 0.01478676478125)), ["tbsp", "tablespoon", "cuillère à soupe", "cas"])
            add(UnitVolume(symbol: "tsp", converter: UnitConverterLinear(coefficient: 0.00492892159375)), ["tsp", "teaspoon", "cuillère à café", "cac"])
            add(UnitInformationStorage.bytes, ["b", "byte", "octet", "o"])
            add(UnitInformationStorage.kilobytes, ["kb", "ko", "kilobyte", "kilooctet"])
            add(UnitInformationStorage.megabytes, ["mb", "mo", "megabyte", "mégaoctet", "megaoctet"])
            add(UnitInformationStorage.gigabytes, ["gb", "go", "gigabyte", "gigaoctet"])
            add(UnitInformationStorage.terabytes, ["tb", "to", "terabyte", "téraoctet"])
            add(UnitInformationStorage.bits, ["bit"])
            add(UnitInformationStorage.megabits, ["mbit", "mbits", "megabit"])
            add(UnitDuration.seconds, ["s", "sec", "second", "seconde"])
            add(UnitDuration.minutes, ["min", "minute"])
            add(UnitDuration.hours, ["h", "hr", "hour", "heure"])
            add(UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400)), ["d", "day", "jour", "j"])
            add(UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800)), ["wk", "week", "semaine"])
            add(UnitSpeed(symbol: "km/h", converter: UnitConverterLinear(coefficient: 1_000.0 / 3_600.0)), ["km/h", "kmh", "kph"])
            add(UnitSpeed.milesPerHour, ["mph", "mi/h"])
            add(UnitSpeed.metersPerSecond, ["m/s"])
            add(UnitSpeed(symbol: "kn", converter: UnitConverterLinear(coefficient: 1_852.0 / 3_600.0)), ["kn", "knot", "noeud", "nœud"])
            add(UnitArea.squareMeters, ["m2", "m²", "square meter", "mètre carré"])
            add(UnitArea.squareKilometers, ["km2", "km²"])
            add(UnitArea.squareFeet, ["ft2", "ft²", "sq ft", "square foot", "square feet"])
            add(UnitArea.hectares, ["ha", "hectare"])
            add(UnitArea.acres, ["ac", "acre"])
            add(UnitEnergy.kilocalories, ["kcal", "calorie"])
            add(UnitEnergy.kilojoules, ["kj", "kilojoule"])
            return table
        }()
    }

    // MARK: - Time zones

    /// "heure à Tokyo", "time in New York", "Tokyo time".
    static func timeIn(_ text: String, now: Date, locale: Locale) -> Result? {
        let lower = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let prefixes = ["time in ", "heure a ", "heure à ", "l'heure a ", "quelle heure a ", "quelle heure est-il a "]
        var city: String?
        for prefix in prefixes where lower.hasPrefix(prefix.folding(options: .diacriticInsensitive, locale: nil)) {
            city = String(lower.dropFirst(prefix.count))
        }
        if city == nil, lower.hasSuffix(" time") { city = String(lower.dropLast(5)) }
        guard let name = city?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)), !name.isEmpty,
              let zone = timeZone(named: name)
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("EEE jj:mm")
        let offset = (zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 60
        let difference = offset == 0 ? "same time as here"
            : "\(offset > 0 ? "+" : "−")\(abs(offset) / 60)\(abs(offset) % 60 == 0 ? "" : ":\(String(format: "%02d", abs(offset) % 60))") h from here"
        let place = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        let time = formatter.string(from: now)
        return Result(display: "\(time) in \(place)", copy: time, detail: difference)
    }

    /// A city as people name it: "new york", "tokyo", "los angeles", and a
    /// few the zone database names after another city.
    static func timeZone(named name: String) -> TimeZone? {
        let aliases = ["san francisco": "America/Los_Angeles", "seattle": "America/Los_Angeles", "boston": "America/New_York",
                       "miami": "America/New_York", "washington": "America/New_York", "pekin": "Asia/Shanghai", "beijing": "Asia/Shanghai",
                       "londres": "Europe/London", "bombay": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
                       "new delhi": "Asia/Kolkata", "montreal": "America/Toronto", "geneve": "Europe/Zurich", "geneva": "Europe/Zurich",
                       "barcelone": "Europe/Madrid", "barcelona": "Europe/Madrid", "milan": "Europe/Rome", "munich": "Europe/Berlin",
                       "pekin ": "Asia/Shanghai", "seoul": "Asia/Seoul", "sydney": "Australia/Sydney", "dubai": "Asia/Dubai",
                       "utc": "UTC", "gmt": "GMT"]
        if let identifier = aliases[name] { return TimeZone(identifier: identifier) }
        let wanted = name.replacingOccurrences(of: " ", with: "_")
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            if city.lowercased().folding(options: .diacriticInsensitive, locale: nil) == wanted { return TimeZone(identifier: identifier) }
        }
        return nil
    }

    // MARK: - Numbers

    /// Up to 10 significant digits, no float noise ("0.1 + 0.2" is 0.3).
    static func format(_ value: Double, locale: Locale, grouping: Bool) -> String {
        // "32 °F to °C" lands a hair off 0.
        let value = value.magnitude < 1e-9 ? 0 : value
        if value.magnitude >= 1e15 || (value != 0 && value.magnitude < 1e-6) {
            return value.formatted(.number.notation(.scientific).precision(.significantDigits(1...8)).locale(locale))
        }
        let rounded = (value * 1e10).rounded() / 1e10
        return rounded.formatted(.number.precision(.fractionLength(0...8)).grouping(grouping ? .automatic : .never).locale(locale))
    }
}
