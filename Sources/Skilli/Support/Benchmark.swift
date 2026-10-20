import AppKit
import SkilliCore

/// `Skilli --benchmark`: measures the launcher hot paths on this Mac.
///
/// Does not install the event tap or touch key mappings, so it needs no
/// permissions. "Show" is measured from the call to the end of the
/// synchronous draw; the window server composites on the next frame.
@MainActor
enum Benchmark {
    struct Report: Codable {
        struct Stats: Codable {
            let samples: Int
            let medianMs: Double
            let p95Ms: Double
            let maxMs: Double

            init(_ durations: [Duration]) {
                let sorted = durations.map(\.milliseconds).sorted()
                samples = sorted.count
                medianMs = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
                p95Ms = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                maxMs = sorted.last ?? 0
            }
        }

        let launchToReadyMs: Double
        let appCount: Int
        let indexScanMs: Double
        let firstShowMs: Double
        let show: Stats
        let showPhaseResults: Stats
        let showPhaseOrderFront: Stats
        let showPhaseDraw: Stats
        let searchPerQuery: [String: Stats]
        let typeToRedraw: Stats
        let topResults: [String: [String]]
        let memoryIdleMB: Double
        let memoryAfterMB: Double
        /// Default bindings built without conflicts (a conflict would crash).
        let bindingCount: Int
        /// Time to lay out and show the which-key overlay for `✦ K`.
        let leaderOverlayShowMs: Double
        /// Key codes resolved for binding characters on the active layout.
        let layoutKeyCodes: [String: Int]
        /// `WindowCapture.edgeAlpha` per glass window ("launcher", "leader"):
        /// ~0 (≤ 0.02); higher means the window clips the glass shadow into a
        /// square edge. -1 when the capture failed.
        let glassEdgeAlpha: [String: Double]
    }

    /// Off-screen captures only render faithfully in the light appearance.
    private static let appearances: [(String, NSAppearance?)] = [
        ("light", NSAppearance(named: .aqua))
    ]

    private static let queries = ["s", "sa", "saf", "safari", "term", "vsc", "xcode", "notes", "préf", "calc", "zzzzz"]

    static func run(
        launcher: LauncherController,
        index: AppIndex,
        usage: UsageStore,
        layout: KeyboardLayout,
        overlay: LeaderOverlay,
        snapshotDirectory: URL?
    ) async -> Report {
        var engine = ShortcutStore(fileURL: nil).makeEngine()
        var layoutKeyCodes: [String: Int] = [:]
        for character in "ukltcfsv" {
            layoutKeyCodes[String(character)] = layout.keyCode(for: .character(character)).map(Int.init) ?? -1
        }

        let launchToReady = ContinuousClock.now - SkilliMain.processStart
        let memoryIdle = Metrics.memoryFootprintMB() ?? 0

        var shows: [Duration] = []
        var phases: [LauncherController.ShowPhases] = []
        var firstShow: Duration = .zero
        for iteration in 0..<40 {
            launcher.show(triggeredAt: .now)
            let duration = launcher.lastShowDuration ?? .zero
            if iteration == 0 {
                firstShow = duration
            } else {
                shows.append(duration)
                if let phase = launcher.lastShowPhases { phases.append(phase) }
            }
            try? await Task.sleep(for: .milliseconds(20))
            launcher.hide()
            try? await Task.sleep(for: .milliseconds(20))
        }

        var searchPerQuery: [String: Report.Stats] = [:]
        var topResults: [String: [String]] = [:]
        for query in queries {
            var durations: [Duration] = []
            var results: [AppIndex.Entry] = []
            for _ in 0..<300 {
                let start = ContinuousClock.now
                results = index.search(query, usage: usage, limit: 50)
                durations.append(.now - start)
            }
            searchPerQuery[query] = Report.Stats(durations)
            topResults[query] = results.prefix(3).map(\.name)
        }

        // Keystroke to redrawn list, typing "safari" one character at a time.
        launcher.show(triggeredAt: .now)
        var typing: [Duration] = []
        for _ in 0..<20 {
            var typed = ""
            for character in "safari" {
                typed.append(character)
                autoreleasepool {
                    typing.append(launcher.simulateTyping(typed))
                }
            }
        }
        launcher.hide()

        // Measured before the snapshot/overlay checks, which allocate
        // bitmaps a real session never would. Let the run loop drain
        // autorelease pools first.
        try? await Task.sleep(for: .milliseconds(500))
        let memoryAfter = Metrics.memoryFootprintMB() ?? 0

        // The glass shadow must fit inside each window (no square edges).
        var glassEdgeAlpha: [String: Double] = [:]
        launcher.show(triggeredAt: .now)
        _ = launcher.simulateTyping("sa")
        glassEdgeAlpha["launcher"] = await edgeAlpha(of: launcher.window, saveAs: "launcher-window.png", in: snapshotDirectory)
        launcher.hide()

        // Snapshot the launcher mid-query for a visual check.
        if let snapshotDirectory {
            BrandCheck.write(to: snapshotDirectory)
            launcher.show(triggeredAt: .now)
            _ = launcher.simulateTyping("sa")
            for (name, appearance) in appearances {
                try? launcher.snapshotPNG(appearance: appearance)?.write(to: snapshotDirectory.appendingPathComponent("launcher-\(name).png"))
            }
            _ = launcher.simulateTyping("settings")
            try? launcher.snapshotPNG(appearance: NSAppearance(named: .aqua))?.write(to: snapshotDirectory.appendingPathComponent("launcher-settings-light.png"))
            _ = launcher.simulateTyping("zzzz")
            try? launcher.snapshotPNG(appearance: NSAppearance(named: .aqua))?.write(to: snapshotDirectory.appendingPathComponent("launcher-empty-light.png"))
            launcher.hide()
        }

        // Which-key overlay for the leader group.
        var leaderOverlayShow: Duration = .zero
        if case .pending(let prefix, let title, let hints) = engine.handle(Chord(.character("k"), .hyper), at: .now) {
            let start = ContinuousClock.now
            overlay.show(prefix: prefix, title: title, hints: hints.map(LeaderOverlay.Row.init))
            leaderOverlayShow = .now - start
            glassEdgeAlpha["leader"] = await edgeAlpha(of: overlay.window, saveAs: "leader-window.png", in: snapshotDirectory)
            if let snapshotDirectory {
                for (name, appearance) in appearances {
                    try? overlay.snapshotPNG(appearance: appearance)?.write(to: snapshotDirectory.appendingPathComponent("leader-\(name).png"))
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
            overlay.hide()
        }

        return Report(
            launchToReadyMs: launchToReady.milliseconds,
            appCount: index.entries.count,
            indexScanMs: index.lastScanDuration?.milliseconds ?? 0,
            firstShowMs: firstShow.milliseconds,
            show: Report.Stats(shows),
            showPhaseResults: Report.Stats(phases.map(\.results)),
            showPhaseOrderFront: Report.Stats(phases.map(\.order)),
            showPhaseDraw: Report.Stats(phases.map(\.draw)),
            searchPerQuery: searchPerQuery,
            typeToRedraw: Report.Stats(typing),
            topResults: topResults,
            memoryIdleMB: memoryIdle,
            memoryAfterMB: memoryAfter,
            bindingCount: ShortcutConfig.defaults.shortcuts.filter { $0.keys != nil }.count,
            leaderOverlayShowMs: leaderOverlayShow.milliseconds,
            layoutKeyCodes: layoutKeyCodes,
            glassEdgeAlpha: glassEdgeAlpha
        )
    }

    private static func edgeAlpha(of window: NSWindow, saveAs name: String, in directory: URL?) async -> Double {
        // Let the window server composite the glass first.
        try? await Task.sleep(for: .milliseconds(250))
        guard let image = await WindowCapture.image(of: window) else { return -1 }
        if let directory, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent(name))
        }
        return WindowCapture.edgeAlpha(image)
    }

    static func emit(_ report: Report, to path: String?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        if let path {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
