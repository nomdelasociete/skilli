# Currency conversion, skil.li's way

Proposal, 2026-10-27. **Status**: phase 1 built the same day ("Daily
rates are enough. Build phase 1"); AGENTS.md → Calculator says how it
works. Two choices made while building: the switch is the Catalog's
Convert Currencies (no new Settings pane, no "Your currency" setting:
the Mac's region decides, a typed target overrides), and an amount
already in your currency goes to the last target picked, else the dollar
(the euro for dollar users) rather than showing nothing.

## Short answer

A part of the calculator, not a new feature: "100 usd en eur", "€49 in
yen", "1 299 $" give the first launcher row, like "10 km en miles" today.
All deterministic (MANIFESTO 4): no SI anywhere.

Accurate and up to date comes from three rules:

1. **One honest source, its date shown.** Daily mid-market rates from
   central banks (Frankfurter v2: 170 currencies, 106 central banks, each
   rate with its own date), the ECB's own file as the fallback. The row's
   detail always says which day the rate is from. A rate is never shown
   as newer than it is.
2. **Fetched as a whole table, converted on the Mac.** One small request
   for every rate, never the amount nor the pair typed: nothing you type
   leaves the Mac (MANIFESTO 11). The launcher computes from the table on
   disk, so a conversion is as instant as "2 + 2" (MANIFESTO 3) and works
   offline, with the rate's age said.
3. **Refreshed when the source publishes, not on a timer.** The source
   says when its next update is (`Cache-Control: max-age`, `ETag`): the
   table is read again then, on wake and on network return, with
   `If-None-Match` (an unchanged table costs a 304).

Live intraday rates (minutes old) are a phase 2, only if wanted: see
[Live rates](#phase-2-live-rates).

## Moment

1. **When.**
   - A price in another currency in front of you: a shop, a hotel, a SaaS
     pricing page, an invoice or a quote in Mail, a number in Slack.
   - Planning: a trip budget, a salary or a freelance rate abroad.
   - Writing: you need the amount in your currency in the email you are
     typing.
   - Each case is short, and the amount is usually on screen or in your
     head; you want a number, not a page.
2. **The path.** The launcher's first row, as for units, answered as you
   type: no ↩ needed to see it (the calculator is evaluated on every
   keystroke, `controlTextDidChange` → `updateResults` →
   `Calculator.evaluate`). "800 TRY" shows it in your own currency at
   once; "800 TRY in €", "800 TRY en EUR", "800 try → eur" in another.
   ↩ only acts: it types the result in the app in front, ⌘↩ and ⌘C copy
   it (the calculator's keys, MANIFESTO 7). With a price selected and nothing
   typed, the launcher's first row is that price converted (the selection
   is already the query for quicklinks): select "$1,299", open the
   launcher, read the answer.
3. **Hint or push.** Neither: a row where you already look. No card, no
   notification, no "rates updated". A stale table (offline for days) is
   said in that row's detail only, when you convert.
4. **Deterministic or AI.** Deterministic. Currency names come from
   Foundation (`Locale.commonISOCurrencyCodes`,
   `localizedString(forCurrencyCode:)`) in every language the Mac has,
   plus a few words people say ("bucks", "balles", "quid"). Sent off the
   Mac: one GET of the day's table to the rate source, no input in it.
5. **Wrong.** A wrong guess is a wrong number someone may paste in an
   email: what was read is always in the detail ("USD → EUR · 1 USD =
   0,8940 EUR · central banks, 27 Oct"). "$" read as US dollars when you
   meant Canadian: type "cad" and it is fixed; "$" alone follows your
   region (CAD in Canada, AUD in Australia). A rate from an old table says
   its date. A currency the table lacks gives no row, never a guess.

## Rate sources, compared

Checked live on 2026-10-27 at ~17:20 UTC (curl from this Mac). EUR→USD the
same afternoon: ECB 1.115, Frankfurter blended 1.1186, Coinbase 1.11386.
Different sources and times give different numbers in the third decimal:
hence the source and date in every row.

| Source | What | Freshness | Terms | Verdict |
|--------|------|-----------|-------|---------|
| **Frankfurter v2** `api.frankfurter.dev/v2/rates?base=EUR` | 170 currencies, mid-market, blended from 106 central banks; each rate carries its own date (ANG was 23 Oct) | Daily; `Cache-Control: max-age` until the next update, `ETag`, `stale-if-error` | No key, no quota (rate-limited against abuse); blended rates "free to use"; open source, self-hostable | **First** |
| **ECB** `ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml` | 29 currencies against EUR, the reference rates | Working days, ~16:00 CET | Public, no key | **Fallback** (Frankfurter down, or as a check) |
| open.er-api.com (ExchangeRate-API open access) | ~160 currencies | Daily | No key; attribution required, rate limits | No: weaker provenance than central banks, attribution in the UI |
| fawazahmed0 currency-api (jsDelivr) | 200+ currencies and crypto | Daily (was a day behind: 26 Oct) | Free | No: unclear provenance |
| Coinbase `api.coinbase.com/v2/exchange-rates` | ~660 codes, fiat and crypto | Live (`max-age=60`) | No key for this read; terms for use in another app **not found** | Phase 2 candidate, terms first |
| Open Exchange Rates, Fixer, XE… | Live, many currencies | Hourly or better | Paid or a key per user | No: a key to set breaks "right by default" (MANIFESTO 10) |

macOS's own Spotlight converts currencies, but through Apple's private
service: no public API.

## How it works

### Data

- `CurrencyRates` (SkilliCore, pure): a table `[code: Decimal]` against
  EUR, each with its date, plus where it came from and when it was
  fetched. A pair is a cross rate (`rate[to] / rate[from]`), computed in
  `Decimal`, never `Double`.
- `CurrencyRateStore` (app): the table in Application Support as JSON,
  read once at launch; a refresh off the main thread (AGENTS.md: heavy
  work, network, off main) when the stored `max-age` has passed, on wake
  and on network return, like the other refreshers (`on wake and network
  return; on each launcher show when older than…`). A failed refresh keeps
  the old table; Frankfurter failing twice → the ECB file.
- The first launch has no table: the first conversion row says
  "Getting today's rates…" and fills in once the fetch lands (one fetch,
  started at launch, not on a keystroke).

### Reading what was typed

In `Calculator.evaluate`, beside `conversion`, a `currency(_:rates:)`
step:

- Amount: the calculator's own number parser (French decimal comma, "1
  234", "1,234.5"), plus "1k", "2,5 M".
- Currency, before or after the amount: ISO code ("usd"), symbol ("$",
  "€", "£", "¥", "₹", "CHF"), or a name in any Mac language ("dollars
  canadiens", "yen", "livres sterling"). Ambiguous symbols follow the
  user's region first ("$" → the region's dollar, else USD; "¥" → JPY,
  "yuan"/"rmb" → CNY; "kr" → the region's krone/krona, else no guess).
- Any case: "800 TRY", "800 try", "800 Try". An ISO code that is also a
  word ("try", "all", "top", "mad", "cop") counts only right after a
  number, where a search for the word is unlikely.
- Target: after " in ", " to ", " en ", " → " (the separators units
  use), read like the source: code, symbol or name ("in €", "en EUR",
  "to euros"). Missing: the user's currency (`Locale.current.currency`).
  When the amount is already in it: the last target picked from this
  currency (history, like the launcher's other learning), else USD (EUR
  for a dollar user).
- As you type, the row never flickers away: while a target is
  incomplete ("800 TRY i", "800 TRY in e"), the row stays on the last
  answer it had (your currency), then switches once the target reads as
  a currency ("€" or "eur"). A typed target that is no currency
  ("800 TRY in xyz") gives no row.
- Units first when both sides are units: "2 cup in ml" stays a volume;
  "2 cup in eur" is Cuban pesos only because "eur" is no unit.
- Each keystroke is one parse and one multiplication on the table in
  memory: no disk, no network while typing.
- Several targets ("100 usd in eur, gbp, chf"): one row each.

### The row

- Title: the amount formatted for its currency (`FormatStyle.currency`,
  the currency's own decimals: 0 for JPY, 3 for KWD): "89,40 €".
- Detail: "100 USD → EUR · 1 USD = 0,8940 EUR · central banks, 27 Oct".
  Older than 3 days: "rates from 23 Oct (offline)".
- ↩ pastes "89,40", ⌘↩ / ⌘C copy it (the calculator's `copy`). ⌘K adds
  Copy Rate and Copy with Currency ("89,40 €").

### Mixed arithmetic (later in phase 1)

"120 € + 30 $" and "49 $ * 12" in one currency (the first one's, or the
target's): the parser's values get an optional currency, like units do.

### Reachable from skillies

- `"$SKILLI_CLI" call convert_currency amount=100 from=USD to=EUR`:
  `{amount, from, to, result, rate, rateDay, source}`, exit 1 when a
  currency is not in the day's table.
- A link: `skilli://run/<entry>` takes no text today, so the launcher
  opened on a query (`q=`) is new work, shared with every calculator
  answer; until then the `call` tool is the scripted path. Documented in
  `skillies/README.md`.

### Settings and privacy

- No setting needed to work (MANIFESTO 10). The switch is the Catalog's
  own entry, Convert Currencies (Settings → Catalog, "?"): off, no row
  and nothing read.
- Settings → Privacy → What Leaves This Mac: its own destination,
  "Frankfurter and the ECB" (`PrivacyMap.exchangeRates`): the day's
  table, nothing of yours; its switch links to Catalog.

### Tests

- `CalculatorTests`: parsing (codes, symbols, names in English and
  French, amount before and after, "1k"), cross rates in `Decimal` against
  a fixed table, each currency's decimals, a region's "$", no row for an
  unknown code or a lone "usd".
- `CurrencyRates` decoding of a saved Frankfurter answer and a saved ECB
  file (fixtures, no network in unit tests); stale and missing tables.
- Each prefix of "800 TRY in €" typed one key at a time: the row from
  "800 TRY" on, never gone in between, EUR once "€" is typed.
- `selftest calc` extended: "800 TRY" then "800 TRY in €" typed key by
  key, the first row read before any ↩, its detail dated, ↩ pasted, from
  a seeded table (no network).

## Phase 2: live rates

Not planned: daily rates were judged enough (2026-10-27). Daily central-bank
rates are what statements and invoices use, but EUR/USD moves ~0.5 % in a
day and crypto far more.

- Source: Coinbase's public `exchange-rates` (live, fiat and crypto, no
  key), once its terms are checked for use in another app. Otherwise
  crypto stays out.
- When: only once a currency row is on screen, at most once a minute,
  whole table again (nothing typed sent). The row updates in place, its
  detail says "live, 1 min ago".
- Crypto codes (BTC, ETH…) only in this phase: a daily crypto rate is
  wrong by design.

## Not now

- A card's fee or a bank's spread ("+2 %"): mid-market is the honest
  number; "100 usd en eur + 2%" already works once arithmetic mixes.
- Historical rates ("100 usd en eur le 3 mars"): Frankfurter has them
  back to 1948 (`date=`); waits for the calculator's dates.
- A rates chart.

## Open point

Frankfurter's public server, or a copy on a skil.li server of its own
(same API, self-hostable), so skil.li does not depend on one person's
server?
