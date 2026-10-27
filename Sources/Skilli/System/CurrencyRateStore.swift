import AppKit
import Network
import SkilliCore

/// The day's exchange rates for the calculator (docs/currency-conversion.md):
/// one table read whole from Frankfurter (central banks), else the ECB's
/// file, kept on disk, read again when the source says it changes, on wake
/// and when the network comes back. Nothing typed is sent: the launcher
/// converts from the table in memory.
@MainActor
final class CurrencyRateStore {
    private(set) var rates: CurrencyRates?
    /// The currency last picked from each one ("EUR": "GBP").
    private(set) var lastTargets: [String: String] = [:]
    /// The last read failed and there is no table yet.
    private(set) var unreachable = false
    /// Convert Currencies is on (Settings → Catalog): nothing is read while off.
    var isOn: () -> Bool = { true }
    /// The table changed: the launcher's rows are drawn again.
    var onChange: (() -> Void)?

    private let fileURL: URL?
    private let fetches: Bool
    private var reading = false
    /// After a failed read with no table: not before then, one timer.
    private var retryAfter = Date.distantPast
    private var retryPending = false
    /// The network came back during a read: one more read after it.
    private var readAgain = false
    private var observers: [NSObjectProtocol] = []
    private let network = NWPathMonitor()
    private var online = true

    nonisolated static let frankfurter = URL(string: "https://api.frankfurter.dev/v2/rates?base=EUR")!
    nonisolated static let ecb = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!

    /// `fetches: false` (the self-tests): the table seeded, no network.
    init(fileURL: URL?, fetches: Bool = true) {
        self.fileURL = fileURL
        self.fetches = fetches
        if let fileURL, let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            rates = saved.rates
            lastTargets = saved.lastTargets
        }
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skil.li", isDirectory: true).appendingPathComponent("currency-rates.json")
    }

    /// What the calculator converts with; nil while Convert Currencies is off.
    var context: CurrencyContext? {
        guard isOn() else { return nil }
        return CurrencyContext(rates: rates, waiting: unreachable ? "No exchange rates yet: no connection" : "Getting today's rates…",
                               lastTargets: lastTargets)
    }

    func start() {
        // The names of every currency, read once off the main thread: the
        // first key typed does not pay for them.
        Task.detached(priority: .utility) { _ = Calculator.answers("1 eur", currency: CurrencyContext(rates: nil)) }
        refreshIfDue()
        guard fetches else { return }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfDue() }
        })
        network.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in
                guard let self, up != self.online else { return }
                self.online = up
                // Back online: a read now, even inside a failed read's wait.
                if up {
                    self.retryAfter = .distantPast
                    if self.reading { self.readAgain = true } else { self.refreshIfDue() }
                }
            }
        }
        network.start(queue: .main)
    }

    /// Reads the table again once the source's own validity has passed;
    /// a date compare otherwise (each launcher show calls it).
    func refreshIfDue(now: Date = .now) {
        guard fetches, isOn(), !reading, now >= retryAfter, (rates?.validUntil ?? .distantPast) <= now else { return }
        reading = true
        let etag = rates?.source == .centralBanks ? rates?.etag : nil
        Task {
            var read = await Self.readFrankfurter(etag: etag)
            // Turned off meanwhile: no second request.
            if case .failed = read, isOn() { read = await Self.readECB() }
            reading = false
            switch read {
            case .new(let table):
                retryAfter = .distantPast
                rates = table
                unreachable = false
                save()
            case .unchanged(let validUntil):
                rates?.validUntil = validUntil
                rates?.fetched = .now
                save()
            case .failed:
                // The old table stays; asked again in ten minutes, not on
                // every show or wake before then (network return still asks).
                unreachable = rates == nil
                retryAfter = Date.now.addingTimeInterval(600)
                if rates == nil, !retryPending {
                    retryPending = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
                        self?.retryPending = false
                        self?.refreshIfDue()
                    }
                }
            }
            onChange?()
            if readAgain {
                readAgain = false
                retryAfter = .distantPast
                refreshIfDue()
            }
        }
    }

    /// A conversion acted on: its target is the next default from that currency.
    func picked(_ conversion: Calculator.Conversion) {
        guard lastTargets[conversion.from] != conversion.to else { return }
        lastTargets[conversion.from] = conversion.to
        save()
    }

    /// The self-tests' table.
    func seed(_ table: CurrencyRates) {
        rates = table
        unreachable = false
        onChange?()
    }

    // MARK: - Private

    private struct Saved: Codable {
        var rates: CurrencyRates?
        var lastTargets: [String: String]
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(Saved(rates: rates, lastTargets: lastTargets)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private enum Read: Sendable {
        case new(CurrencyRates)
        case unchanged(validUntil: Date)
        case failed
    }

    /// Frankfurter first (an unchanged table costs a 304); the ECB's file
    /// when it does not answer (`readECB`).
    nonisolated private static func readFrankfurter(etag: String?) async -> Read {
        var request = URLRequest(url: frankfurter)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse {
            let now = Date.now
            let validUntil = CurrencyRates.validUntil(cacheControl: http.value(forHTTPHeaderField: "Cache-Control"), from: now)
            if http.statusCode == 304 { return .unchanged(validUntil: validUntil) }
            if http.statusCode == 200,
               let table = try? CurrencyRates.frankfurter(data, fetched: now, validUntil: validUntil, etag: http.value(forHTTPHeaderField: "ETag")) {
                return .new(table)
            }
        }
        Log.trace("Currency: Frankfurter did not answer")
        return .failed
    }

    nonisolated private static func readECB() async -> Read {
        if let (data, response) = try? await session.data(from: ecb), (response as? HTTPURLResponse)?.statusCode == 200 {
            let now = Date.now
            // The ECB publishes once a working day, around 16:00 CET.
            if let table = try? CurrencyRates.ecb(data, fetched: now, validUntil: now.addingTimeInterval(3 * 3600), etag: nil) {
                return .new(table)
            }
        }
        Log.trace("Currency: no exchange rates read")
        return .failed
    }

    /// Its own session: no cookies, no cache shared with anything else.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}
