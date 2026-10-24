import AppKit

@main
@MainActor
enum SkilliMain {
    /// Captured first thing so the benchmark can report launch-to-ready time.
    static let processStart = ContinuousClock.now

    static func main() {
        _ = processStart
        // `Skilli mcp` / `Skilli call`: a command-line bridge, no app.
        if let status = MCPBridge.runIfRequested(ProcessInfo.processInfo.arguments) {
            exit(status)
        }
        // `Skilli relaunch`: reopens skil.li once System Settings has quit it.
        if let status = Relaunch.runIfRequested(ProcessInfo.processInfo.arguments) {
            exit(status)
        }
        // `Skilli testform`: the form "do it here" acts in, for the self-test.
        if let status = TestForm.runIfRequested(ProcessInfo.processInfo.arguments) {
            exit(status)
        }
        #if SKILLI_SELFTEST
        // `Skilli recorderprobe …`: the meeting recorder's measurements.
        if let status = RecorderProbe.runIfRequested(ProcessInfo.processInfo.arguments) {
            exit(status)
        }
        // `Skilli recorderchild …`: a recording the self-test kills.
        if let status = RecorderChild.runIfRequested(ProcessInfo.processInfo.arguments) {
            exit(status)
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate(mode: LaunchMode(arguments: ProcessInfo.processInfo.arguments))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

enum LaunchMode: Equatable {
    case normal
    /// `--benchmark [--output <path>]`: measure the launcher without touching
    /// key mappings or event taps, print a JSON report, quit.
    case benchmark(outputPath: String?)
    /// `--selftest --output <path> [--scope settings]`: full app with event
    /// tap, driven by synthetic hardware-like keys; writes a JSON report,
    /// quits. `--scope settings` runs only the Settings checks, `--scope glass`
    /// only the on-screen glass checks, `--scope ai` only the AI checks.
    case selftest(outputPath: String?, scope: String)

    init(arguments: [String]) {
        var outputPath: String?
        if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
            outputPath = arguments[index + 1]
        }
        if arguments.contains("--benchmark") {
            self = .benchmark(outputPath: outputPath)
        } else if arguments.contains("--selftest") {
            var scope = "all"
            if let index = arguments.firstIndex(of: "--scope"), arguments.indices.contains(index + 1) {
                scope = arguments[index + 1]
            }
            self = .selftest(outputPath: outputPath, scope: scope)
        } else {
            self = .normal
        }
    }
}
