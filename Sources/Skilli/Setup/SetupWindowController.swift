import AppKit
import SwiftUI

/// The welcome window (docs/onboarding.md): centred, in front, closed by
/// Start, Later or ✕. Later and ✕ mean "later" (D7): it never comes back
/// by itself, only when asked (the menu bar's and Settings → General's Set
/// Up skil.li… while Accessibility is off, the launcher's Welcome to
/// skil.li).
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let permissions: PermissionCenter
    let model: WelcomeModel
    private let guide = SettingsGuide()
    private var window: NSWindow?
    /// Hyper sent as ⌘⌃⌥⇧ by another Hyper Key app (Raycast's tap runs
    /// before ours): read from the modifier flags while the welcome is key.
    private var flagsMonitor: Any?
    /// Closed by Start, Later or ✕: whether every required permission was
    /// granted then.
    var onClose: ((Bool) -> Void)?

    /// Shown by itself only on the first launch: once closed, never again
    /// on its own.
    static func showsByItself(closedOnce: Bool) -> Bool { !closedOnce }

    /// Set Up skil.li… offered (menu bar, Settings → General) while the
    /// key tap cannot run or Accessibility is off.
    static func isOffered(tapRunning: Bool, ready: Bool) -> Bool { !tapRunning || !ready }

    init(permissions: PermissionCenter, ai: AIStore, preferences: Preferences) {
        self.permissions = permissions
        model = WelcomeModel(permissions: permissions, ai: ai, preferences: preferences)
        super.init()
        // Back in front as soon as a switch flips or a prompt is answered:
        // System Settings and macOS's prompts take the front from it.
        permissions.onChange = { [weak self] in self?.comeBack() }
        model.onGrantAccessibility = { [weak self] in self?.showGuide() }
        model.onFinish = { [weak self] in self?.close() }
    }

    /// In front again once nothing waits at System Settings' switch.
    func comeBack() {
        guard let window, window.isVisible else { return }
        guard permissions.state(.accessibility) != .waiting else { return }
        guide.hide()
        Foreground.bring(window)
    }

    var isVisible: Bool { window?.isVisible == true }
    /// Self-test hooks: the window and the guide, for captures and checks.
    var shownWindow: NSWindow? { window }
    var shownGuide: SettingsGuide { guide }

    /// From the first step, or `step` (Set Up skil.li… opens on
    /// Accessibility).
    func show(at step: WelcomeModel.Step = .welcome) {
        let window = self.window ?? makeWindow()
        self.window = window
        permissions.startWatching([.accessibility])
        model.start(at: step)
        model.isActive = true
        watchFlags()
        window.center()
        // From the launcher or the menu bar: another app is in front and
        // may decline a plain activation.
        Foreground.bring(window)
    }

    func close() {
        window?.close()
    }

    /// Start, Later and ✕ all end here.
    func windowWillClose(_ notification: Notification) {
        model.isActive = false
        guide.hide()
        permissions.stopWatching([.accessibility])
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        onClose?(permissions.isReady)
    }

    /// Self-test hooks: the window in light or dark, and as it shows.
    func setAppearance(_ appearance: NSAppearance?) {
        window?.appearance = appearance
    }

    func snapshotPNG() async -> Data? {
        guard let window else { return nil }
        if let png = await WindowCapture.png(of: window) { return png }
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func showGuide() {
        guide.show(listName: AccessibilityStage.listName) { [weak self] in
            self?.permissions.state(.accessibility) == .granted || self?.isVisible != true
        }
    }

    private func watchFlags() {
        guard flagsMonitor == nil else { return }
        var held = false
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let hyper: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            let now = event.modifierFlags.intersection(hyper) == hyper
            if now != held {
                held = now
                self?.model.hyperChanged(held: now)
            }
            return event
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: WelcomeView(model: model))
        // The window keeps the welcome's size; the view never resizes it
        // (it would add the title bar's height under the stage).
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to skil.li"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        // The whole window is the welcome: the stage runs under the title bar.
        window.setFrame(NSRect(origin: .zero, size: WelcomeView.size), display: false)
        window.delegate = self
        return window
    }
}
