import XCTest
@testable import SkilliCore

final class CalculatorCurrencyTests: XCTestCase {
    private let french = Locale(identifier: "fr_FR")
    private let english = Locale(identifier: "en_US")
    private let canadian = Locale(identifier: "en_CA")
    /// 2026-10-27, 18:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_124_000)

    /// Frankfurter v2's answer, as it came on 2026-10-27 (a few rows).
    private let frankfurterAnswer = """
    [{"date":"2026-10-27","base":"EUR","quote":"USD","rate":1.1186},
     {"date":"2026-10-27","base":"EUR","quote":"TRY","rate":55.666},
     {"date":"2026-10-27","base":"EUR","quote":"JPY","rate":175.97},
     {"date":"2026-10-27","base":"EUR","quote":"GBP","rate":0.83658},
     {"date":"2026-10-27","base":"EUR","quote":"CAD","rate":1.5641},
     {"date":"2026-10-27","base":"EUR","quote":"CHF","rate":0.9239},
     {"date":"2026-10-27","base":"EUR","quote":"KWD","rate":0.3425},
     {"date":"2026-10-27","base":"EUR","quote":"CUP","rate":26.846},
     {"date":"2026-10-23","base":"EUR","quote":"ANG","rate":2.0023}]
    """

    private let ecbFile = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
      <gesmes:subject>Reference rates</gesmes:subject>
      <Cube><Cube time='2026-10-27'>
        <Cube currency='USD' rate='1.115'/><Cube currency='JPY' rate='175.97'/><Cube currency='TRY' rate='55.6'/>
      </Cube></Cube>
    </gesmes:Envelope>
    """

    private var rates: CurrencyRates {
        try! CurrencyRates.frankfurter(Data(frankfurterAnswer.utf8), fetched: now, validUntil: now.addingTimeInterval(3600), etag: "\"abc\"")
    }

    private func context(_ lastTargets: [String: String] = [:]) -> CurrencyContext {
        CurrencyContext(rates: rates, lastTargets: lastTargets)
    }

    private func answer(_ text: String, _ locale: Locale = Locale(identifier: "fr_FR"), lastTargets: [String: String] = [:]) -> Calculator.Result? {
        Calculator.evaluate(text, locale: locale, now: now, currency: context(lastTargets))
    }

    private func pair(_ text: String, _ locale: Locale = Locale(identifier: "fr_FR")) -> String? {
        answer(text, locale)?.conversion.map { "\($0.from)→\($0.to)" }
    }

    // MARK: - The sources

    func testFrankfurterIsReadWithEachRatesDay() throws {
        let rates = self.rates
        XCTAssertEqual(rates.source, .centralBanks)
        XCTAssertEqual(rates.etag, "\"abc\"")
        XCTAssertEqual(rates.rates["USD"]?.perEuro, Decimal(string: "1.1186"))
        XCTAssertEqual(rates.rates["EUR"]?.perEuro, 1)
        XCTAssertEqual(rates.rates["ANG"]?.day, "2026-10-23")
        // A pair is as old as its older rate.
        XCTAssertEqual(rates.day(from: "USD", to: "ANG"), "2026-10-23")
        XCTAssertThrowsError(try CurrencyRates.frankfurter(Data("[]".utf8), fetched: now, validUntil: now, etag: nil))
    }

    func testECBFileIsTheFallback() throws {
        let rates = try CurrencyRates.ecb(Data(ecbFile.utf8), fetched: now, validUntil: now, etag: nil)
        XCTAssertEqual(rates.source, .ecb)
        XCTAssertEqual(rates.rates["USD"], .init(perEuro: Decimal(string: "1.115")!, day: "2026-10-27"))
        XCTAssertEqual(rates.rates.count, 4)
        XCTAssertThrowsError(try CurrencyRates.ecb(Data("<html></html>".utf8), fetched: now, validUntil: now, etag: nil))
    }

    func testCrossRatesAreDecimal() {
        // 1 / 1.1186, not a double's noise.
        XCTAssertEqual(rates.rate(from: "EUR", to: "USD"), Decimal(string: "1.1186"))
        let usdToTry = rates.rate(from: "USD", to: "TRY")!
        XCTAssertEqual(NSDecimalNumber(decimal: usdToTry).doubleValue, 55.666 / 1.1186, accuracy: 1e-12)
    }

    func testCacheControlSaysWhenToReadAgain() {
        XCTAssertEqual(CurrencyRates.validUntil(cacheControl: "public, max-age=25156, stale-if-error=86400", from: now), now.addingTimeInterval(25_156))
        XCTAssertEqual(CurrencyRates.validUntil(cacheControl: nil, from: now), now.addingTimeInterval(6 * 3600))
        // Never every second, never a week.
        XCTAssertEqual(CurrencyRates.validUntil(cacheControl: "max-age=0", from: now), now.addingTimeInterval(600))
        XCTAssertEqual(CurrencyRates.validUntil(cacheControl: "max-age=999999", from: now), now.addingTimeInterval(86_400))
    }

    // MARK: - Reading what is typed

    func testAnAmountAloneGoesToTheUsersCurrency() {
        XCTAssertEqual(pair("800 TRY"), "TRY→EUR")
        XCTAssertEqual(pair("800 try"), "TRY→EUR")
        XCTAssertEqual(pair("800 TRY", english), "TRY→USD")
        // 800 / 55.666 = 14.3714…
        XCTAssertEqual(answer("800 TRY")?.copy, "14,37")
        XCTAssertEqual(answer("800 TRY", english)?.copy, "16.08")
        XCTAssertEqual(answer("800 TRY")?.display, Decimal(string: "14.37")!.formatted(.currency(code: "EUR").locale(french)))
    }

    func testTargetsAsCodesSymbolsAndNames() {
        for text in ["800 TRY in €", "800 TRY en EUR", "800 try to eur", "800 try → eur", "800 TRY en euros", "800 livres turques en euros",
                     "800 turkish lira in euro", "₺800 in €"] {
            XCTAssertEqual(pair(text, english), "TRY→EUR", text)
        }
        XCTAssertEqual(pair("€49 in $", english), "EUR→USD")
        XCTAssertEqual(pair("49 € en dollars"), "EUR→USD")
        XCTAssertEqual(pair("$1,299", french), "USD→EUR")
        XCTAssertEqual(answer("$1,299", english, lastTargets: [:])?.conversion?.to, "EUR")
        XCTAssertEqual(pair("1 299 $"), "USD→EUR")
        XCTAssertEqual(pair("USD 100"), "USD→EUR")
        XCTAssertEqual(pair("10 £ en ¥"), "GBP→JPY")
        XCTAssertEqual(pair("2,5k usd"), "USD→EUR")
        XCTAssertEqual(answer("2,5k usd")?.copy, Calculator.evaluate("2500 usd", locale: french, now: now, currency: context())?.copy)
    }

    func testTheUsersOwnCurrencyGoesToTheLastPicked() {
        XCTAssertEqual(pair("100 €"), "EUR→USD")
        XCTAssertEqual(answer("100 €", lastTargets: ["EUR": "GBP"])?.conversion?.to, "GBP")
        XCTAssertEqual(pair("100 usd", english), "USD→EUR")
    }

    func testTheDollarSignFollowsTheRegion() {
        XCTAssertEqual(pair("100 $ in €", canadian), "CAD→EUR")
        XCTAssertEqual(pair("100 dollars in €", canadian), "CAD→EUR")
        XCTAssertEqual(pair("100 us$ in €", canadian), "USD→EUR")
        XCTAssertEqual(pair("100 $ in €", french), "USD→EUR")
    }

    func testTheUsersCurrencyCanDifferFromTheNumbersLocale() {
        // A tool reads numbers in English for a Canadian user: "dollars" is CAD.
        var context = context()
        context.home = "CAD"
        let result = Calculator.evaluate("100 dollars in €", locale: english, now: now, currency: context)
        XCTAssertEqual(result?.conversion?.from, "CAD")
        XCTAssertEqual(Calculator.evaluate("100 eur", locale: english, now: now, currency: context)?.conversion?.to, "CAD")
        XCTAssertEqual(Calculator.currencyCode("dollars", home: "CAD"), "CAD")
        // A dollar named stays that dollar.
        for name in ["US dollars", "dollars américains", "dollars US", "dollars des États-Unis", "us$"] {
            XCTAssertEqual(Calculator.currencyCode(name, home: "CAD"), "USD", name)
        }
        XCTAssertEqual(Calculator.currencyCode("dollars canadiens", home: "USD"), "CAD")
        XCTAssertEqual(Calculator.currencyCode("€", home: "USD"), "EUR")
        XCTAssertEqual(Calculator.currencyCode("try", home: "USD"), "TRY")
        XCTAssertNil(Calculator.currencyCode("pesos", home: "EUR"))
    }

    func testATargetTheTableLacksGivesNoRow() {
        // XOF is a currency, but not in this table: no fallback to the user's.
        XCTAssertNil(answer("800 TRY in xof", english))
        XCTAssertNil(answer("800 TRY in eur, xof", english))
    }

    func testEachCurrencyKeepsItsOwnDecimals() {
        XCTAssertEqual(answer("100 eur in jpy", english)?.copy, "17597")
        XCTAssertEqual(answer("100 eur in kwd", english)?.copy, "34.250")
        XCTAssertEqual(answer("1 jpy in kwd", english)?.copy, "0.002")
        // Less than a cent: still a number, not 0.00.
        XCTAssertEqual(answer("0.1 jpy in eur", english)?.copy, "0.000568")
    }

    func testSeveralTargets() {
        let rows = Calculator.answers("100 usd in eur, gbp et chf", locale: french, now: now, currency: context())
        XCTAssertEqual(rows.compactMap(\.conversion?.to), ["EUR", "GBP", "CHF"])
    }

    func testTheDetailSaysTheRateAndItsDay() {
        let result = answer("800 TRY in €", english)
        XCTAssertEqual(result?.detail, "800 TRY → EUR · 1 TRY = 0.01796 EUR · Oct 27")
        XCTAssertEqual(result?.conversion?.rate, "1 TRY = 0.01796 EUR")
        XCTAssertEqual(answer("100 eur in usd", english)?.conversion?.rate, "1 EUR = 1.1186 USD")
        // A table from days ago says so.
        let old = Calculator.evaluate("800 TRY in €", locale: english, now: now.addingTimeInterval(6 * 86_400), currency: context())
        XCTAssertEqual(old?.detail.hasSuffix("rates of Oct 27, not updated"), true)
    }

    // MARK: - As it is typed

    func testTheRowStaysWhileTheTargetIsTyped() {
        let typed = "800 TRY in €"
        var shown: [String] = []
        for end in typed.indices.dropFirst() + [typed.endIndex] {
            let text = String(typed[..<end])
            shown.append(pair(text, english) ?? "-")
        }
        // "8", "80", "800", "800 ", "800 T", "800 TR": not a currency yet.
        XCTAssertEqual(Array(shown.prefix(6)), ["-", "-", "-", "-", "-", "-"])
        XCTAssertEqual(Array(shown.dropFirst(6)), ["TRY→USD", "TRY→USD", "TRY→USD", "TRY→USD", "TRY→USD", "TRY→EUR"])
        // A target being spelled: still the user's currency, then it.
        XCTAssertEqual(pair("800 TRY in e", english), "TRY→USD")
        XCTAssertEqual(pair("800 TRY in eu", english), "TRY→USD")
        XCTAssertEqual(pair("800 TRY in eur", english), "TRY→EUR")
        XCTAssertEqual(pair("800 TRY en euro", english), "TRY→EUR")
        // No currency is spelled that way: no row.
        XCTAssertNil(answer("800 TRY in xyz", english))
    }

    // MARK: - Calculations with money

    private func rows(_ text: String, _ locale: Locale, rates: CurrencyRates? = nil, waiting: Bool = false) -> [String] {
        let context = CurrencyContext(rates: waiting ? nil : (rates ?? self.rates))
        return Calculator.answers(text, locale: locale, now: now, currency: context).map { "\($0.copy) \($0.currency ?? "-")" }
    }

    func testMoneyAddsUpInTheFirstCurrency() {
        // 30 USD at 1.1186 USD a euro is 26.82 EUR.
        XCTAssertEqual(rows("120 € + 30 $", french), ["146,82 EUR"])
        XCTAssertEqual(rows("120€+30$", french), ["146,82 EUR"])
        // Then in the user's own currency, when it is another.
        XCTAssertEqual(rows("120 € + 30 $", english), ["146.82 EUR", "164.23 USD"])
        XCTAssertEqual(rows("$10 + €5", english), ["15.59 USD"])
        XCTAssertEqual(rows("120 eur - 30 usd", english), ["93.18 EUR", "104.23 USD"])
        let result = answer("120 € + 30 $", english)
        XCTAssertEqual(result?.detail, "120 € + 30 $ → EUR · 1 USD = 0.894 EUR · Oct 27")
        XCTAssertEqual(result?.conversion?.rate, "1 USD = 0.894 EUR")
    }

    func testMoneyTimesANumber() {
        XCTAssertEqual(rows("49 $ * 12", english), ["588.00 USD"])
        XCTAssertEqual(answer("49 $ * 12", english)?.detail, "49 $ * 12 → USD")
        XCTAssertEqual(rows("49 $ * 12", french), ["588,00 USD", "525,66 EUR"])
        XCTAssertEqual(rows("2 * 49 €", french), ["98,00 EUR"])
        XCTAssertEqual(rows("120 € / 3", french), ["40,00 EUR"])
        XCTAssertEqual(rows("85 € + 20 %", french), ["102,00 EUR"])
        XCTAssertEqual(rows("20 % de 85 €", french), ["17,00 EUR"])
        XCTAssertEqual(rows("(10 € + 5 €) * 2", french), ["30,00 EUR"])
        XCTAssertEqual(rows("1 000 ¥ x 3", english), ["3000 JPY", "19.07 USD"])
    }

    func testASumGoesToTheTargetsTyped() {
        // 1 000 EUR + 200 GBP (239.07 EUR), in dollars.
        XCTAssertEqual(rows("1k € + 200 £ en dollars", english), ["1386.02 USD"])
        XCTAssertEqual(answer("1k € + 200 £ en dollars", english)?.detail,
                       "1k € + 200 £ → USD · 1 GBP = 1.3371 USD, 1 EUR = 1.1186 USD · Oct 27")
        // Two currencies converted: no one rate to copy.
        XCTAssertNil(answer("1k € + 200 £ en dollars", english)?.conversion)
        XCTAssertEqual(rows("49 $ * 12 in eur, gbp", english), ["525.66 EUR", "439.75 GBP"])
        // A target being spelled: the rows it had.
        XCTAssertEqual(rows("120 € + 30 $ in g", english), ["146.82 EUR", "164.23 USD"])
        XCTAssertEqual(rows("120 € + 30 $ i", english), ["146.82 EUR", "164.23 USD"])
        XCTAssertEqual(rows("120 € + 30 $ in xyz", english), [])
    }

    func testMoneyThatIsNotACalculation() {
        // Money times money, a power of money, a function of it: nothing.
        XCTAssertEqual(rows("3 € * 2 €", french), [])
        XCTAssertEqual(rows("3 € ^ 2", french), [])
        XCTAssertEqual(rows("sqrt(9 €)", french), [])
        // A currency the day's table lacks: no guess.
        XCTAssertEqual(rows("100 € + 50 xof", french), [])
        // An amount alone is still a conversion.
        XCTAssertEqual(pair("800 TRY", english), "TRY→USD")
        // "3 x 4" and "5 mars" are no money.
        XCTAssertEqual(rows("3 x 4", english), ["12 -"])
    }

    func testASumWaitsForTheFirstTableOnlyWhenItConverts() {
        XCTAssertEqual(Calculator.evaluate("120 € + 30 $", locale: french, now: now, currency: CurrencyContext(rates: nil))?.isWaiting, true)
        // One currency, the user's: no rate needed.
        XCTAssertEqual(rows("49 $ * 12", english, waiting: true), ["588.00 USD"])
    }

    // MARK: - Not a currency

    func testWhatIsNotAConversionStaysAsItWas() {
        XCTAssertNil(answer("usd"))
        XCTAssertNil(answer("800"))
        XCTAssertNil(answer("try 800"))
        XCTAssertNil(answer("1password"))
        // A currency the table lacks: no guess.
        XCTAssertNil(answer("100 xof"))
        // Units first: "cup" is a volume when both sides are units.
        XCTAssertEqual(Calculator.evaluate("2 cup in ml", locale: english, currency: context())?.detail, "2 cup → mL")
        XCTAssertEqual(pair("2 cup in eur", english), "CUP→EUR")
        // Arithmetic and the rest unchanged.
        XCTAssertEqual(Calculator.evaluate("2 + 3 * 4", locale: english, currency: context())?.copy, "14")
        XCTAssertEqual(Calculator.evaluate("10 km in miles", locale: english, currency: context())?.conversion, nil)
        // Convert Currencies off: no context, no conversion.
        XCTAssertNil(Calculator.evaluate("800 TRY", locale: english))
    }

    func testWaitingForTheFirstTable() {
        let result = Calculator.evaluate("800 TRY in €", locale: english, now: now, currency: CurrencyContext(rates: nil))
        XCTAssertEqual(result?.isWaiting, true)
        XCTAssertEqual(result?.display, "Getting today's rates…")
        XCTAssertEqual(result?.detail, "800 TRY → EUR")
        XCTAssertEqual(result?.copy, "")
    }
}
