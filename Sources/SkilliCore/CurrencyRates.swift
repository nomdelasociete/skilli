import Foundation

/// The day's exchange rates, as one table against the euro: what the
/// calculator converts currencies with, on this Mac. Read whole from the
/// source (Frankfurter's blend of central banks, else the ECB's own file),
/// never per pair: nothing typed leaves the Mac (docs/currency-conversion.md).
public struct CurrencyRates: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Frankfurter v2: mid-market rates blended from central banks.
        case centralBanks
        /// The ECB's euro reference rates, the fallback.
        case ecb

        public var title: String {
            switch self {
            case .centralBanks: "central banks"
            case .ecb: "ECB"
            }
        }
    }

    public struct Rate: Codable, Equatable, Sendable {
        /// Units of the currency for one euro.
        public let perEuro: Decimal
        /// The day the source published it, "2026-10-27".
        public let day: String

        public init(perEuro: Decimal, day: String) {
            self.perEuro = perEuro
            self.day = day
        }
    }

    public var rates: [String: Rate]
    public var source: Source
    public var fetched: Date
    /// Until when the source says the table holds (`Cache-Control:
    /// max-age`); read again after.
    public var validUntil: Date
    public var etag: String?

    public init(rates: [String: Rate], source: Source, fetched: Date, validUntil: Date, etag: String? = nil) {
        self.rates = rates
        self.source = source
        self.fetched = fetched
        self.validUntil = validUntil
        self.etag = etag
    }

    /// What one unit of `from` is in `to`, computed in `Decimal`.
    public func rate(from: String, to: String) -> Decimal? {
        guard let from = rates[from], let to = rates[to], from.perEuro > 0 else { return nil }
        return to.perEuro / from.perEuro
    }

    /// The older of the two rates' days: the pair is no newer than that.
    public func day(from: String, to: String) -> String? {
        guard let from = rates[from]?.day, let to = rates[to]?.day else { return nil }
        return min(from, to)
    }

    // MARK: - Reading the sources

    public enum ReadError: Error, Equatable {
        case notRates
    }

    /// Frankfurter v2's `/v2/rates?base=EUR`: `[{"date","base","quote","rate"}]`.
    public static func frankfurter(_ data: Data, fetched: Date, validUntil: Date, etag: String?) throws -> CurrencyRates {
        struct Row: Decodable {
            let date: String
            let base: String
            let quote: String
            let rate: Double
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        var rates: [String: Rate] = [:]
        for row in rows where row.base == "EUR" && row.rate > 0 {
            guard let perEuro = decimal(row.rate) else { continue }
            rates[row.quote] = Rate(perEuro: perEuro, day: row.date)
        }
        guard !rates.isEmpty else { throw ReadError.notRates }
        let newest = rates.values.map(\.day).max() ?? ""
        rates["EUR"] = Rate(perEuro: 1, day: newest)
        return CurrencyRates(rates: rates, source: .centralBanks, fetched: fetched, validUntil: validUntil, etag: etag)
    }

    /// The ECB's `eurofxref-daily.xml`: `<Cube time="…">` holding
    /// `<Cube currency="USD" rate="1.115"/>`.
    public static func ecb(_ data: Data, fetched: Date, validUntil: Date, etag: String?) throws -> CurrencyRates {
        let reader = ECBReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), !reader.rates.isEmpty, let day = reader.day else { throw ReadError.notRates }
        var rates = reader.rates.mapValues { Rate(perEuro: $0, day: day) }
        rates["EUR"] = Rate(perEuro: 1, day: day)
        return CurrencyRates(rates: rates, source: .ecb, fetched: fetched, validUntil: validUntil, etag: etag)
    }

    /// "1.1186" as written, not the binary double's 1.11860000000000003.
    static func decimal(_ value: Double) -> Decimal? {
        Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
    }

    private final class ECBReader: NSObject, XMLParserDelegate {
        var rates: [String: Decimal] = [:]
        var day: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            guard elementName == "Cube" else { return }
            if let time = attributes["time"] { day = time }
            if let currency = attributes["currency"], let text = attributes["rate"],
               let rate = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), rate > 0 {
                rates[currency] = rate
            }
        }
    }

    /// `Cache-Control: max-age=…` from now; `fallback` when it says none.
    public static func validUntil(cacheControl: String?, from now: Date, fallback: TimeInterval = 6 * 3600) -> Date {
        let maxAge = cacheControl?.split(separator: ",").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("max-age=") }
            .flatMap { TimeInterval($0.dropFirst("max-age=".count)) }
        // At least ten minutes, at most a day: a source's mistake does not
        // make skil.li ask every second nor keep a week-old table.
        return now.addingTimeInterval(min(max(maxAge ?? fallback, 600), 86_400))
    }
}
