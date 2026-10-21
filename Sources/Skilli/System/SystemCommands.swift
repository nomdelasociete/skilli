import AppKit
import Carbon.HIToolbox
import IOKit.ps
import IOKit.pwr_mgt
import SkilliCore

/// Runs `SystemCommand`s. Apple events (appearance, Trash, disks, restart)
/// go to System Events or Finder; macOS asks the user once per app.
@MainActor
final class SystemCommands {
    private var awakeAssertion: IOPMAssertionID?
    /// When a timed Keep Awake ends ("awake 1 hour"); nil until turned off.
    private(set) var awakeUntil: Date?
    private var awakeTimer: Timer?
    /// Places for the front window (✦W, the launcher, Ask, agents).
    let windows = WindowManager()
    /// Clean Keyboard's tap and card.
    let cleaner = KeyboardCleaner()
    /// "Keep Awake" is on.
    var isKeepingAwake: Bool { awakeAssertion != nil }
    /// Asks in the card before what cannot be undone.
    /// Asks in the card: the question, a line under it, the verb ↩ says.
    var confirm: ((_ question: String, _ detail: String, _ verb: String) async -> Bool)?
    /// ⌘V to the app in front, once it has its focus back (Paste Latest
    /// Screenshot).
    var pressPaste: (@MainActor () async -> Void)?
    /// Where screenshots are: macOS's folder, and the one Settings →
    /// Clipboard watches (the self-test's own).
    var screenshotFolders: @MainActor () -> [URL] = { [ImageFolderWatcher.screenshotsFolder] }
    /// Opens a linked app's link (CleanShot X's): the self-test reads it
    /// instead, nothing captured.
    var openAppLink: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The last linked app's link opened, for the self-test.
    var lastAppLink: URL?
    /// The variant a linked app's command runs when none is said (Settings
    /// → Apps: Capture Text's line breaks).
    var appLinkDefault: @MainActor (AppLinkCommand) -> AppLinkCommand.Variant? = { _ in nil }
    var onChange: (() -> Void)?
    /// Where Keep Awake is kept, so a restart of skil.li (an update, a
    /// crash) takes it again: macOS lets go of it with the process.
    private let defaults: UserDefaults
    private static let awakeKey = "SystemCommands.keepAwake"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// At launch: Keep Awake as it was, until the same time (or until
    /// turned off); nothing when it ended meanwhile.
    func restoreAwake() {
        guard let saved = defaults.object(forKey: Self.awakeKey) as? Double else { return }
        if saved == 0 {
            if awakeAssertion == nil, startAwake() {
                onChange?()
                Log.actions.notice("Keep Awake taken again after a restart")
            }
            return
        }
        let until = Date(timeIntervalSince1970: saved)
        guard until > .now else {
            defaults.removeObject(forKey: Self.awakeKey)
            return
        }
        _ = keepAwake(.awake(seconds: Int(until.timeIntervalSinceNow.rounded(.up))), until: until)
        Log.actions.notice("Keep Awake taken again after a restart, until its end")
    }
    /// Self-test hook: the last command run.
    private(set) var lastCommand: SystemCommand?
    /// Self-test hook: Wi-Fi and Bluetooth are checked, never changed (the
    /// Mac mini's SSH rides on its Wi-Fi; connecting AirPods would take
    /// them from the user's own Mac). What would be done is said instead.
    var radiosDryRun = false

    /// A Mac command or a place for the front window.
    @discardableResult
    func run(_ action: MacAction) async throws -> String {
        switch action {
        case .system(let command): return try await run(command)
        case .window(let layout): return try windows.apply(layout)
        case .sound(let target):
            let device = try AudioDevices.select(uid: target.uid, output: target.output)
            return target.output ? "Sound on “\(device.name)”." : "Microphone: “\(device.name)”."
        case .script(let command):
            // Run by the app (its card and its modes): never here.
            throw Failure(message: "The skillie “\(command.title)” runs from the launcher, Ask or a shortcut.")
        case .shortcut(let shortcut, _):
            // Run by the app too: its card shows what it gave back.
            throw Failure(message: "The shortcut “\(AppleShortcuts.name(of: shortcut))” runs from the launcher, Ask or a key.")
        case .project(let project):
            guard FileManager.default.fileExists(atPath: project.path) else { throw Failure(message: "“\(project.name)” is no longer at \(project.folder()).") }
            EditorProjects.open(project, reveal: false)
            return "Opened “\(project.name)” in \(project.editor)."
        case .settings(let pane):
            try SystemSettingsPanes.open(pane)
            return "Opened \(pane.name) in System Settings."
        case .bluetooth(let target, let connect):
            if radiosDryRun {
                guard BluetoothDevices.cached.contains(where: { $0.address == target.address }) else {
                    throw Failure(message: "That device is not paired with this Mac any more.")
                }
                return "Would \(connect ? "connect" : "disconnect") “\(target.name)”."
            }
            if connect {
                let device = try await BluetoothDevices.connect(address: target.address)
                return "Connected to “\(device.name)”."
            }
            let device = try BluetoothDevices.disconnect(address: target.address)
            return "Disconnected “\(device.name)”."
        case .volume(let level):
            return try Self.setVolume(level)
        case .appLink(let command, _):
            try openLink(command, variant: action.appLinkVariant ?? appLinkDefault(command), file: nil)
            // Seen at once in the app: nothing said.
            return ""
        }
    }

    /// A linked app's command on a file skil.li already has (⌘K on a
    /// clipboard image or a file found, an agent's `file`): checked against
    /// what its link takes, then opened. Seen at once in the app.
    func open(_ file: URL, with command: AppLinkCommand, variant: AppLinkCommand.Variant? = nil) throws {
        try openLink(command, variant: variant ?? appLinkDefault(command), file: file)
    }

    private func openLink(_ command: AppLinkCommand, variant: AppLinkCommand.Variant?, file: URL?) throws {
        let url = try LinkedApps.url(for: command, variant: variant, file: file, frontWindow: { try windows.frontWindowFrame() },
                                     latestScreenshot: { ImageFolderWatcher.latestScreenshot(in: screenshotFolders()) },
                                     finderSelection: { try FinderSelection.file() })
        lastAppLink = url
        Log.trace("App link \(command.id)\(variant.map { "/\($0.id)" } ?? "")\(file == nil ? "" : " on a file")")
        openAppLink(url)
    }

    /// What happened, in one line; throws a message for the user.
    @discardableResult
    func run(_ command: SystemCommand) async throws -> String {
        lastCommand = command
        if command.needsConfirmation {
            let detail = command == .emptyTrash ? "Its files are deleted for good." : "Open apps are asked to quit; unsaved changes may be lost."
            guard await confirm?("\(command.title)?", detail, command.title) == true else { return "Not done: you declined." }
        }
        Log.trace("System command \(command.rawValue)")
        switch command {
        case .lockScreen:
            if !Self.lockNow() {
                // login.framework gone: macOS's ⌃⌘Q, pressed as real keys.
                Self.pressLockShortcut()
            }
            return "Locked."
        case .sleep:
            try await Self.shell("/usr/bin/pmset", ["sleepnow"])
            return "Sleeping."
        case .sleepDisplays:
            try await Self.shell("/usr/bin/pmset", ["displaysleepnow"])
            return "Displays off."
        case .toggleDarkMode:
            try Self.appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            return "Appearance switched."
        case .keepAwake:
            return toggleAwake()
        case .toggleHiddenFiles:
            let shown = (try? await Self.shell("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            try await Self.shell("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", shown ? "false" : "true"])
            try await Self.shell("/usr/bin/killall", ["Finder"])
            return shown ? "Hidden files are hidden." : "Hidden files are shown."
        case .ejectDisks:
            return try await Self.ejectDisks()
        case .emptyTrash:
            try Self.appleScript("tell application \"Finder\" to empty the trash")
            return "Trash emptied."
        case .restart:
            try Self.appleScript("tell application \"System Events\" to restart")
            return "Restarting."
        case .shutDown:
            try Self.appleScript("tell application \"System Events\" to shut down")
            return "Shutting down."
        case .logOut:
            try Self.appleScript("tell application \"System Events\" to log out")
            return "Logging out."
        case .playPause:
            Self.mediaKey(16)
            return "Play / Pause."
        case .nextTrack:
            Self.mediaKey(17)
            return "Next track."
        case .previousTrack:
            Self.mediaKey(18)
            return "Previous track."
        case .volumeUp:
            Self.mediaKey(0)
            return "Volume up."
        case .volumeDown:
            Self.mediaKey(1)
            return "Volume down."
        case .mute:
            Self.mediaKey(7)
            return "Sound muted or back."
        case .speedTest:
            return try await Self.speedTest()
        case .pickColor:
            return try await Self.pickColor()
        case .pasteLatestScreenshot:
            return try await pasteLatestScreenshot()
        case .systemInfo:
            return Self.systemInfo()
        case .cleanKeyboard:
            try cleaner.start()
            return "Keyboard off for a minute: Done turns it back on."
        case .quitAllApps, .quitOtherApps:
            return try await quitApps(keepingFront: command == .quitOtherApps)
        case .hideOtherApps:
            let front = NSWorkspace.shared.frontmostApplication
            Self.openApps().filter { $0 != front && !$0.isHidden }.forEach { $0.hide() }
            return "Other apps hidden."
        case .showAllApps:
            Self.openApps().filter(\.isHidden).forEach { $0.unhide() }
            return "Every app shown."
        case .toggleMicrophone:
            return try AudioDevices.toggleInputMute() ? "Microphone muted." : "Microphone on."
        case .wifiOn, .wifiOff:
            let on = command == .wifiOn
            if radiosDryRun {
                guard let now = WiFi.isOn() else { throw WiFi.Failure(message: "This Mac has no Wi-Fi.") }
                // Asked for what it is already: the call is made, nothing changes.
                if now == on { try WiFi.setPower(on) }
                return "Would turn Wi-Fi \(on ? "on" : "off")."
            }
            try WiFi.setPower(on)
            return on ? "Wi-Fi on." : "Wi-Fi off."
        case .showDesktop:
            try Self.showDesktop()
            return "Desktop shown."
        }
    }

    /// Show Desktop. macOS has no API for it (Mission Control's own
    /// feature, no public call), so it is the user's own Show Desktop
    /// shortcut, as System Settings → Keyboard → Keyboard Shortcuts →
    /// Mission Control keeps it (F11 unless changed), pressed as a keyboard
    /// sends it: the system's own shortcut, as AGENTS.md allows where macOS
    /// has no API. Turned off there, it is said, not worked around.
    static func showDesktop() throws {
        let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        guard let key = SymbolicHotKey.read(SymbolicHotKey.showDesktopID, in: hotKeys, standard: .showDesktopDefault) else {
            throw Failure(message: "Show Desktop has no shortcut: turn it on in System Settings → Keyboard → Keyboard Shortcuts → Mission Control.")
        }
        var flags = CGEventFlags(rawValue: key.modifiers)
        if key.isFunctionKey { flags.insert(.maskSecondaryFn) }
        SyntheticKeys.press(CGKeyCode(key.keyCode), flags: flags)
    }

    /// The newest screenshot, as an image on the clipboard (as macOS puts
    /// one copied with ⌃⇧⌘4), pasted in the app in front. Seen pasted:
    /// nothing said; none found, said where it looked.
    private func pasteLatestScreenshot() async throws -> String {
        let folders = screenshotFolders()
        guard let url = ImageFolderWatcher.latestScreenshot(in: folders) else {
            var places: [String] = []
            for name in folders.map({ FileManager.default.displayName(atPath: $0.path) }) where !places.contains(name) { places.append(name) }
            throw Failure(message: "No screenshot in \(places.joined(separator: " or ")).")
        }
        guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
            throw Failure(message: "“\(url.lastPathComponent)” cannot be read.")
        }
        let item = NSPasteboardItem()
        if let png = url.pathExtension.lowercased() == "png" ? data : rep.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { throw Failure(message: "The screenshot could not go on the clipboard.") }
        await pressPaste?()
        Log.trace("Pasted the latest screenshot (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        return "Pasted “\(url.deletingPathExtension().lastPathComponent)”."
    }

    /// The apps with a Dock icon, without skil.li and Finder (always there).
    static func openApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && $0.bundleIdentifier != "com.apple.finder" && !$0.isTerminated
        }
    }

    /// Every open app, or all but the one in front, after a yes in the
    /// card naming them: each quits as Quit does (it asks to save). Gone is
    /// the answer; one still open after 5 s (a save sheet) is said.
    private func quitApps(keepingFront: Bool) async throws -> String {
        let front = NSWorkspace.shared.frontmostApplication
        let apps = Self.openApps().filter { !keepingFront || $0 != front }
        guard !apps.isEmpty else { throw Failure(message: keepingFront ? "No other app is open." : "No app is open.") }
        let names = apps.compactMap(\.localizedName).joined(separator: ", ")
        guard await confirm?("Quit \(apps.count) app\(apps.count == 1 ? "" : "s")?", "\(names). Each asks to save what is not saved.", "Quit") == true else {
            return "Not done: you declined."
        }
        apps.forEach { $0.terminate() }
        let deadline = ContinuousClock.now + .seconds(5)
        while apps.contains(where: { !$0.isTerminated }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
        let left = apps.filter { !$0.isTerminated }.compactMap(\.localizedName)
        guard left.isEmpty else { throw Failure(message: "Still open, waiting for you: \(left.joined(separator: ", ")).") }
        return "Quit \(apps.count) app\(apps.count == 1 ? "" : "s")."
    }

    /// What a command says in the card: Keep Awake (nothing on screen
    /// shows it) and the readings. The rest is seen done (Finder shows the
    /// hidden files, the disks leave the desktop): nothing said.
    static func showsResult(_ command: SystemCommand) -> Bool {
        [.speedTest, .pickColor, .systemInfo, .toggleMicrophone].contains(command)
    }

    // MARK: - Sound, music, readings

    /// The keyboard's own media keys (NX_KEYTYPE_…): whatever plays answers,
    /// Spotify, Music or a browser, and macOS shows its volume HUD.
    static func mediaKey(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: Int((key << 16) | (state << 8)), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// The output volume, 0…100; nil when the device has none (HDMI).
    static var volume: Int? { AudioDevices.outputVolume }

    static func setVolume(_ percent: Int) throws -> String {
        let percent = min(max(percent, 0), 100)
        try AudioDevices.setOutputVolume(percent)
        return "Volume at \(percent) %."
    }

    /// The path to macOS's own lock (what the lock screen shortcut does),
    /// in login.framework; nil if a macOS ever drops it.
    private static let loginFramework = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"

    /// Self-test hook: the lock is reachable (looked up, not called).
    static var canLockDirectly: Bool {
        dlopen(loginFramework, RTLD_LAZY).flatMap { dlsym($0, "SACLockScreenImmediate") } != nil
    }

    /// Locks at once through login.framework's SACLockScreenImmediate, as
    /// Raycast does. False when it cannot be found.
    private static func lockNow() -> Bool {
        guard let handle = dlopen(loginFramework, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            Log.actions.error("Lock Screen: login.framework's lock not found")
            return false
        }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
        return true
    }

    /// ⌃⌘Q as a keyboard sends it: Control and Command go down, Q, then
    /// they come up, from the hardware's own state.
    private static func pressLockShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let control = CGKeyCode(kVK_Control), command = CGKeyCode(kVK_Command), q = CGKeyCode(kVK_ANSI_Q)
        let steps: [(CGKeyCode, Bool, CGEventFlags)] = [
            (control, true, .maskControl), (command, true, [.maskControl, .maskCommand]),
            (q, true, [.maskControl, .maskCommand]), (q, false, [.maskControl, .maskCommand]),
            (command, false, .maskControl), (control, false, [])
        ]
        for (code, down, flags) in steps {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// What Finder would eject (disk images, USB and card drives, network
    /// volumes), through NSWorkspace: no other app is asked. Nothing to
    /// eject, or a disk kept, is thrown: the card says it (the disks gone
    /// from the desktop say the rest).
    static func ejectDisks() async throws -> String {
        let keys: Set<URLResourceKey> = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey,
                                         .volumeLocalizedNameKey]
        let volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? [])
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsRootFileSystem != true else { return false }
                return values.volumeIsEjectable == true || values.volumeIsRemovable == true || values.volumeIsLocal == false
            }
        guard !volumes.isEmpty else { throw Failure(message: "No disk to eject.") }
        // Unmounting can take a few seconds: off the main thread.
        let failures = await Task.detached { () -> [String] in
            volumes.compactMap { url -> String? in
                let name = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName ?? url.lastPathComponent
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                    return nil
                } catch {
                    return "“\(name)”: \(error.localizedDescription)"
                }
            }
        }.value
        let ejected = volumes.count - failures.count
        Log.actions.notice("Ejected \(ejected, privacy: .public) of \(volumes.count, privacy: .public) disks")
        if failures.isEmpty { return ejected == 1 ? "Disk ejected." : "\(ejected) disks ejected." }
        throw Failure(message: (ejected > 0 ? "\(ejected) ejected; not ejected: " : "Not ejected: ") + failures.joined(separator: "; "))
    }

    /// macOS's own `networkQuality`: about 15 seconds.
    static func speedTest() async throws -> String {
        let output = try await ClaudeCLI.run(URL(fileURLWithPath: "/usr/bin/networkQuality"), ["-c"], timeout: 60)
        guard let result = SpeedTest(json: Data(output.utf8)) else { throw Failure(message: "The speed test measured nothing: is the Mac online?") }
        Log.trace("Speed test: \(result.summary)")
        return result.summary
    }

    /// macOS's eyedropper; the hex goes on the clipboard.
    static func pickColor() async throws -> String {
        let color: NSColor? = await withCheckedContinuation { continuation in
            NSColorSampler().show { continuation.resume(returning: $0) }
        }
        guard let color = color?.usingColorSpace(.sRGB) else { throw Declined(message: "No color picked.") }
        let picked = PickedColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(picked.hex, forType: .string)
        return "\(picked.hex) copied · \(picked.rgb) · \(picked.hsl)"
    }

    /// Battery, disk, memory, Wi-Fi, address, uptime: one line each.
    static func systemInfo() -> String {
        var lines: [String] = []
        if let battery = batteryLine() { lines.append(battery) }
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity {
            lines.append("Disk: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
        }
        if let used = memoryUsed() {
            let total = Int64(ProcessInfo.processInfo.physicalMemory)
            lines.append("Memory: \(ByteCountFormatter.string(fromByteCount: used, countStyle: .memory)) used of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .memory))")
        }
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) == 3 {
            lines.append(String(format: "Load: %.1f (%d cores)", load[0], ProcessInfo.processInfo.activeProcessorCount))
        }
        if let wifi = WiFi.summary() { lines.append(wifi) }
        if let address = localAddress() { lines.append("IP: \(address)") }
        lines.append("Up: \(MacReadings.uptime(ProcessInfo.processInfo.systemUptime))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        return lines.joined(separator: "\n")
    }

    private static func batteryLine() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let percent = current * 100 / maximum
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int ?? -1
            let time = minutes > 0 ? ", \(MacReadings.uptime(TimeInterval(minutes * 60))) \(charging ? "to full" : "left")" : ""
            return "Battery: \(percent) %\(charging ? " charging" : "")\(time)"
        }
        return nil
    }

    /// Active, wired and compressed pages: what Activity Monitor calls used.
    private static func memoryUsed() -> Int64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        return pages * Int64(getpagesize())
    }

    /// The first IPv4 address of en0/en1 (Wi-Fi or Ethernet).
    private static func localAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            guard ["en0", "en1"].contains(name), let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    /// Keeps the Mac and its display awake until called again.
    private func toggleAwake() -> String {
        if awakeAssertion != nil { return allowSleep() }
        guard startAwake() else { return "macOS did not let skil.li keep the Mac awake." }
        defaults.set(0.0, forKey: Self.awakeKey)
        onChange?()
        return "Keeping the Mac awake until you run Keep Awake again."
    }

    /// "awake 1 hour", "allow sleep": awake for a while (replacing what was
    /// set), then normal sleep again on its own.
    func keepAwake(_ request: AwakeRequest) -> String {
        keepAwake(request, until: nil)
    }

    /// `until`: the end already set (taken again after a restart).
    private func keepAwake(_ request: AwakeRequest, until end: Date?) -> String {
        switch request {
        case .allowSleep:
            return awakeAssertion == nil ? "The Mac already sleeps as usual." : allowSleep()
        case .awake(let seconds):
            guard awakeAssertion != nil || startAwake() else { return "macOS did not let skil.li keep the Mac awake." }
            let until = end ?? Date.now.addingTimeInterval(TimeInterval(seconds))
            awakeUntil = until
            defaults.set(until.timeIntervalSince1970, forKey: Self.awakeKey)
            awakeTimer?.invalidate()
            awakeTimer = Timer.scheduledTimer(withTimeInterval: max(1, until.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.allowSleep() }
            }
            onChange?()
            Log.actions.notice("Keep Awake for \(seconds, privacy: .public) s")
            return "Keeping the Mac awake for \(AwakeRequest.spoken(seconds)), until \(Self.time(until))."
        }
    }

    /// "until 14:05" for the status menu; nil when not timed.
    var awakeUntilText: String? {
        awakeUntil.map { "until \(Self.time($0))" }
    }

    private func startAwake() -> Bool {
        var assertion = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "skil.li Keep Awake" as CFString,
            &assertion
        )
        guard status == kIOReturnSuccess else { return false }
        awakeAssertion = assertion
        return true
    }

    @discardableResult
    private func allowSleep() -> String {
        if let awakeAssertion { IOPMAssertionRelease(awakeAssertion) }
        awakeAssertion = nil
        awakeUntil = nil
        defaults.removeObject(forKey: Self.awakeKey)
        awakeTimer?.invalidate()
        awakeTimer = nil
        onChange?()
        return "The Mac may sleep again."
    }

    private static func time(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    // MARK: - Helpers

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The user said no (esc in the color sampler): an agent reads why, the
    /// card says nothing.
    struct Declined: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @discardableResult
    private static func shell(_ path: String, _ arguments: [String]) async throws -> String {
        try await ClaudeCLI.run(URL(fileURLWithPath: path), arguments, timeout: 20)
    }

    private static func appleScript(_ source: String) throws {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743: the user has not allowed skil.li to control that app.
            if number == -1743 {
                throw Failure(message: "skil.li may not control that app yet: allow it in System Settings → Privacy & Security → Automation.")
            }
            throw Failure(message: error[NSAppleScript.errorMessage] as? String ?? "The command failed.")
        }
    }
}
