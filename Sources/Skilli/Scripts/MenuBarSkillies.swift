import AppKit
import SkilliCore

/// Inline skillies the user put in the menu bar (Settings → Skillies): each
/// shows its last line there, read again at its own refresh time (10 s at
/// least, a minute when it says none), like the next meeting does. A click
/// shows the whole line, Refresh Now, and Remove from Menu Bar. An emoji
/// icon goes before the line; an image icon is the item's image.
@MainActor
final class MenuBarSkillies: NSObject {
    private let library: ScriptLibrary
    private let preferences: Preferences
    private var items: [String: NSStatusItem] = [:]
    private var lines: [String: String] = [:]
    private var timers: [String: Timer] = [:]
    private var running: Set<String> = []

    init(library: ScriptLibrary, preferences: Preferences) {
        self.library = library
        self.preferences = preferences
    }

    /// Self-test hook: the line each one shows, by path.
    var shown: [String: String] {
        items.compactMapValues { $0.button?.title }
    }

    /// Self-test hook: the paths whose item draws an image icon.
    var withImage: Set<String> {
        Set(items.filter { $0.value.button?.image != nil }.keys)
    }

    /// The menu bar matches `skilliesInMenuBar`: new ones appear and are
    /// read at once, removed ones go. Only inline skillies with no argument.
    func apply() {
        let commands = library.all().filter { $0.mode == .inline && $0.arguments.isEmpty }
        let wanted = Dictionary(uniqueKeysWithValues: commands.filter { preferences.skilliesInMenuBar.contains($0.path) }.map { ($0.path, $0) })
        for path in items.keys where wanted[path] == nil { remove(path) }
        for (path, command) in wanted where items[path] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = Self.titled(command.title, command)
            item.button?.image = Self.image(command)
            item.button?.imagePosition = .imageLeading
            items[path] = item
            refresh(command)
            let seconds = TimeInterval(max(10, command.refreshSeconds ?? 60))
            timers[path] = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(path: path) }
            }
        }
    }

    private func remove(_ path: String) {
        timers.removeValue(forKey: path)?.invalidate()
        if let item = items.removeValue(forKey: path) { NSStatusBar.system.removeStatusItem(item) }
        lines.removeValue(forKey: path)
    }

    private func refresh(path: String) {
        guard let command = library.all().first(where: { $0.path == path }) else {
            remove(path)
            return
        }
        refresh(command)
    }

    private func refresh(_ command: ScriptCommand) {
        guard !running.contains(command.path) else { return }
        running.insert(command.path)
        Task {
            let run = try? await library.run(command, arguments: [], timeout: 10)
            running.remove(command.path)
            guard let item = items[command.path] else { return }
            let line = run.map { ScriptCommand.lastLine($0.output) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? (run == nil ? "\(command.title) did not answer" : command.title)
            lines[command.path] = line
            item.button?.title = Self.short(Self.titled(line, command))
            // Read again with the line: its icon may have changed.
            item.button?.image = Self.image(command)
            item.menu = menu(for: command, line: line)
        }
    }

    private func menu(for command: ScriptCommand, line: String) -> NSMenu {
        let menu = NSMenu()
        let shown = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        shown.isEnabled = false
        menu.addItem(shown)
        menu.addItem(.separator())
        let again = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow(_:)), keyEquivalent: "")
        again.target = self
        again.representedObject = command.path
        menu.addItem(again)
        let away = NSMenuItem(title: "Remove from Menu Bar", action: #selector(removeFromMenuBar(_:)), keyEquivalent: "")
        away.target = self
        away.representedObject = command.path
        menu.addItem(away)
        return menu
    }

    @objc private func refreshNow(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        refresh(path: path)
    }

    @objc private func removeFromMenuBar(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        preferences.skilliesInMenuBar.removeAll { $0 == path }
    }

    /// The line with its emoji before it; an image icon is drawn apart.
    static func titled(_ line: String, _ command: ScriptCommand) -> String {
        command.emojiIcon.map { "\($0) \(line)" } ?? line
    }

    /// Its image icon at menu bar size; nil for an emoji, none, or a file
    /// that is not there.
    private static func image(_ command: ScriptCommand) -> NSImage? {
        guard let image = command.iconImagePath.flatMap(NSImage.init(contentsOfFile:)) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    /// The menu bar is narrow: 32 characters at most.
    static func short(_ text: String) -> String {
        text.count > 32 ? String(text.prefix(31)) + "…" : text
    }
}
