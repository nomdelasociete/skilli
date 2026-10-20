import OSLog

/// Stream with `./script/build_and_run.sh --telemetry`.
///
/// `.info` is not persisted by macOS; use `.notice` for events worth reading
/// after the fact: `/usr/bin/log show --last 10m --predicate
/// 'subsystem == "com.nomdelasociete.Skilli"'` (full path: in zsh, `log` is a
/// shell builtin).
enum Log {
    static let subsystem = "com.nomdelasociete.Skilli"
    static let perf = Logger(subsystem: subsystem, category: "perf")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let actions = Logger(subsystem: subsystem, category: "actions")
    static let dev = Logger(subsystem: subsystem, category: "dev")

    /// Everything, in Debug builds only: what was asked, the candidates, the
    /// decision, what was sent, every tool call and the answer — in clear.
    /// Release builds log none of it, except the developer's own (`daily`
    /// in `script/build_and_run.sh`, built with SKILLI_TRACE). Read with
    /// `/usr/bin/log show --last 10m --predicate 'subsystem ==
    /// "com.nomdelasociete.Skilli" AND category == "dev"'`.
    static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG || SKILLI_TRACE
        let text = message()
        dev.notice("\(text.count > 2000 ? String(text.prefix(2000)) + "…" : text, privacy: .public)")
        #endif
    }
}

/// Where a hot path's time went, step by step, for the perf log: "apps
/// 1.2 ms · snippets 8.4 ms" (steps under 0.3 ms left out).
struct Laps {
    private var last = ContinuousClock.now
    private(set) var steps: [(name: String, took: Duration)] = []

    mutating func lap(_ name: String) {
        let now = ContinuousClock.now
        steps.append((name, now - last))
        last = now
    }

    var summary: String {
        steps.filter { $0.took >= .microseconds(300) }.map { "\($0.name) \($0.took.compact)" }.joined(separator: " · ")
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }

    var microseconds: Double {
        milliseconds * 1_000
    }

    /// Compact human rendering: µs below a millisecond, ms otherwise.
    var compact: String {
        let ms = milliseconds
        if ms < 1 {
            return String(format: "%.0f µs", microseconds)
        }
        return String(format: "%.1f ms", ms)
    }
}
