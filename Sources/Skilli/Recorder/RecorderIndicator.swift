import AppKit
import SkilliCore

/// The menu bar while recording (docs/meeting-recorder-views.md): a red
/// dot, the time, the two waves (the microphone above, the Mac's sound
/// below); paused, the dot hollow and the clock still. Its menu pauses,
/// resumes and stops, names each source with its level (a click turns it
/// off or on for the rest of the recording) and the call's app. After
/// Stop, a ring fills as the transcript is made. Never a hidden
/// recording: it shows for as long as one runs.
@MainActor
final class RecorderIndicator: NSObject, NSMenuDelegate {
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onStop: (() -> Void)?
    var onShowFolder: ((URL) -> Void)?
    /// A source's item chosen: off or on.
    var onToggleSource: ((Speaker) -> Void)?
    /// The call's app picked (nil: None).
    var onPickApp: ((MicrophoneApp?) -> Void)?
    /// The apps on the microphone now, and the call's app.
    var calls: () -> (apps: [MicrophoneApp], picked: MicrophoneApp?) = { ([], nil) }

    private let recorder: MeetingRecorder
    private var item: NSStatusItem?
    private var ticker: Timer?
    /// The sources' items while the menu is open: their levels move.
    private var sourceItems: [Speaker: NSMenuItem] = [:]
    private var menuOpen = false
    /// The last 1.5 s of each track's level, eight a second.
    private var mic = [Double](repeating: 0, count: 12)
    private var mac = [Double](repeating: 0, count: 12)

    init(recorder: MeetingRecorder) {
        self.recorder = recorder
    }

    /// Self-test hooks: the time or progress it says, nil while hidden.
    var shown: String? { item == nil ? nil : said }
    private(set) var said = ""
    var button: NSStatusBarButton? { item?.button }

    /// Shown, changed or gone as the recorder is now.
    func update() {
        let live = recorder.isRecording || recorder.phase == .stopping
        guard live || recorder.transcribing != nil else {
            ticker?.invalidate()
            ticker = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            item.button?.imagePosition = .imageOnly
            self.item = item
        }
        if ticker == nil {
            let ticker = Timer(timeInterval: 1.0 / 8, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            ticker.tolerance = 0.03
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        }
        tick()
    }

    private func tick() {
        guard let button = item?.button else { return }
        if recorder.isRecording || recorder.phase == .stopping {
            let paused = recorder.phase == .paused
            let levels = recorder.levels
            mic.removeFirst()
            mac.removeFirst()
            mic.append(paused ? 0 : levels.mic)
            mac.append(paused ? 0 : levels.mac)
            said = MeetingTranscript.clock(recorder.elapsed)
            button.image = Self.recording(time: said, paused: paused, mic: mic, mac: mac)
            button.setAccessibilityLabel(paused ? "Recording paused, \(said)" : "Recording, \(said)")
            button.toolTip = paused ? "“\(recorder.title)” paused" : "Recording “\(recorder.title)”"
            if menuOpen { updateSourceItems() }
        } else if let transcribing = recorder.transcribing {
            switch transcribing.step {
            case .downloading(let language):
                said = "Downloading \(language)…"
                button.image = Self.progress(nil, text: said)
            case .transcribing(let done):
                said = "\(Int((done * 100).rounded())) %"
                button.image = Self.progress(done, text: said)
            }
            button.setAccessibilityLabel("Transcribing “\(transcribing.title)”, \(said)")
            button.toolTip = "Transcribing “\(transcribing.title)”"
        }
    }

    // MARK: - The menu

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        sourceItems = [:]
        if recorder.isRecording {
            let title = NSMenuItem(title: "\(recorder.phase == .paused ? "Paused" : "Recording") “\(recorder.title)” · \(said)", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            if recorder.phase == .paused {
                menu.addItem(entry("Resume Recording", #selector(resume)))
            } else {
                menu.addItem(entry("Pause Recording", #selector(pause)))
            }
            menu.addItem(entry("Stop and Transcribe", #selector(stop)))
            // Each source with its level: a click turns it off or on.
            menu.addItem(.separator())
            for speaker in Speaker.allCases {
                let item = entry("", #selector(toggleSource(_:)))
                item.tag = speaker == .me ? 0 : 1
                sourceItems[speaker] = item
                menu.addItem(item)
            }
            updateSourceItems()
            // The call: the apps on the microphone, the one picked kept.
            let calls = calls()
            if recorder.record?.kind != .inPerson || calls.picked != nil, !calls.apps.isEmpty || calls.picked != nil {
                let call = NSMenuItem(title: "The Call: \(calls.picked?.name ?? "None")", action: nil, keyEquivalent: "")
                let choices = NSMenu()
                var apps = calls.apps
                if let picked = calls.picked, !apps.contains(where: { $0.pid == picked.pid }) { apps.insert(picked, at: 0) }
                for (index, app) in apps.enumerated() {
                    let choice = entry(app.name, #selector(pickApp(_:)))
                    choice.tag = index
                    choice.representedObject = app.pid
                    choice.state = app.pid == calls.picked?.pid && app.bundleID == calls.picked?.bundleID ? .on : .off
                    choices.addItem(choice)
                }
                choices.addItem(.separator())
                let none = entry("None", #selector(pickApp(_:)))
                none.tag = -1
                none.state = calls.picked == nil ? .on : .off
                choices.addItem(none)
                pickable = apps
                call.submenu = choices
                menu.addItem(call)
            }
            if recorder.folder != nil {
                menu.addItem(.separator())
                menu.addItem(entry("Show in Finder", #selector(showFolder)))
            }
        } else if let transcribing = recorder.transcribing {
            let title = NSMenuItem(title: "Transcribing “\(transcribing.title)”… \(said)", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
            menu.addItem(entry("Show in Finder", #selector(showFolder)))
        }
    }

    /// Self-test hook: the menu's items as it would open now.
    var menuTitles: [String] {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    /// The apps the call's submenu offers, in its order.
    private var pickable: [MicrophoneApp] = []

    /// "Microphone · NDI Audio", checked while on, its level as a small
    /// meter.
    private func updateSourceItems() {
        let levels = recorder.levels
        let sources = recorder.sources
        for (speaker, item) in sourceItems {
            let on = speaker == .me ? sources.microphone : sources.macSound
            let device: String
            if speaker == .me {
                if case .on(let name) = recorder.microphone.state { device = name } else { device = "Off" }
            } else {
                device = on ? (recorder.macSoundFailure == nil ? "Every app" : "Not available") : "Off"
            }
            let title = "\(speaker == .me ? "Microphone" : "The Mac's Sound") · \(on ? device : "Off")"
            if item.title != title { item.title = title }
            item.state = on ? .on : .off
            item.image = Self.meter(on ? (speaker == .me ? levels.mic : levels.mac) : 0, on: on)
        }
    }

    /// A small level meter for a menu item: four bars.
    static func meter(_ level: Double, on: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 12), flipped: false) { _ in
            let lit = on ? Int((level.squareRoot() * 4).rounded(.up)) : 0
            for index in 0..<4 {
                let height = CGFloat(3 + index * 2)
                let bar = NSRect(x: CGFloat(index) * 5 + 1, y: (12 - height) / 2, width: 3, height: height)
                (index < lit ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.2)).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func toggleSource(_ item: NSMenuItem) {
        onToggleSource?(item.tag == 0 ? .me : .them)
    }

    @objc private func pickApp(_ item: NSMenuItem) {
        onPickApp?(pickable.indices.contains(item.tag) ? pickable[item.tag] : nil)
    }

    private func entry(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pause() { onPause?() }
    @objc private func resume() { onResume?() }
    @objc private func stop() { onStop?() }
    @objc private func showFolder() {
        if let folder = recorder.folder ?? recorder.transcribing?.folder { onShowFolder?(folder) }
    }

    // MARK: - Drawing

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let height: CGFloat = 16

    /// The dot, the time, the waves: drawn when the menu bar draws it, in
    /// its appearance (the label color is light on a dark bar).
    static func recording(time: String, paused: Bool, mic: [Double], mac: [Double]) -> NSImage {
        let text = NSAttributedString(string: time, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let textWidth = ceil(text.size().width)
        // Whole points: 2 pt bars a point apart stay sharp on a 1x screen.
        let wavesWidth = CGFloat(mic.count) * 3 - 1
        let size = NSSize(width: 8 + 5 + textWidth + 6 + wavesWidth, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            let dot = NSRect(x: 0.5, y: (height - 8) / 2, width: 7.5, height: 7.5)
            if paused {
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                NSColor.secondaryLabelColor.setStroke()
                ring.stroke()
            } else {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            let textSize = text.size()
            text.draw(at: NSPoint(x: 13, y: (height - textSize.height) / 2))
            // The microphone grows up from the middle, the Mac's sound down,
            // a point apart; quiet speech still shows (square root).
            let left = (13 + textWidth + 6).rounded()
            let middle = (height / 2).rounded()
            let room = middle - 2
            NSColor.labelColor.withAlphaComponent(paused ? 0.35 : 0.85).setFill()
            for index in mic.indices {
                let x = left + CGFloat(index) * 3
                let up = max(1, (CGFloat(mic[index]).squareRoot() * room).rounded())
                let down = max(1, (CGFloat(mac[index]).squareRoot() * room).rounded())
                NSRect(x: x, y: middle + 1, width: 2, height: up).fill()
                NSRect(x: x, y: middle - 1 - down, width: 2, height: down).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// A ring filled to `done` (nil: a quarter turning, while macOS
    /// downloads a language), then what it says.
    static func progress(_ done: Double?, text said: String) -> NSImage {
        let text = NSAttributedString(string: said, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let textWidth = ceil(text.size().width)
        let size = NSSize(width: 13 + 5 + textWidth, height: height)
        let start = Date.now.timeIntervalSinceReferenceDate
        let image = NSImage(size: size, flipped: false) { _ in
            let ring = NSRect(x: 1, y: (height - 12) / 2, width: 12, height: 12)
            let track = NSBezierPath(ovalIn: ring.insetBy(dx: 1, dy: 1))
            track.lineWidth = 2
            NSColor.labelColor.withAlphaComponent(0.2).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            let center = NSPoint(x: ring.midX, y: ring.midY)
            let from: CGFloat = done == nil ? CGFloat(start.truncatingRemainder(dividingBy: 1)) * -360 + 90 : 90
            let to = done.map { 90 - 360 * CGFloat(max(0.02, min(1, $0))) } ?? from - 90
            arc.appendArc(withCenter: center, radius: 5, startAngle: from, endAngle: to, clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            arc.stroke()
            let textSize = text.size()
            text.draw(at: NSPoint(x: 18, y: (height - textSize.height) / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}
