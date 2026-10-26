import SkilliCore
import SwiftUI

/// Something Keys → Add Shortcut… can give a key: a command, or Open App…
/// (an app chosen in a panel first).
struct ShortcutChoice: Identifiable {
    enum Kind {
        case action(SkilliAction)
        case chooseApp
    }

    let id: String
    let section: String
    let title: String
    let kind: Kind

    /// Every choice, in the order the menu listed them (docs/adding-a-shortcut.md).
    @MainActor
    static func all(_ context: SettingsContext) -> [ShortcutChoice] {
        var choices: [ShortcutChoice] = []
        func add(_ section: String, _ actions: [SkilliAction], title: (SkilliAction) -> String = { $0.title }) {
            choices += actions.map { ShortcutChoice(id: "\(section)/\($0.id)", section: section, title: title($0), kind: .action($0)) }
        }
        add("skil.li", ActionCatalog.general)
        add("\(Brand.intelligence) Commands", ActionCatalog.ai)
        add("Windows", ActionCatalog.windows)
        add("Mac", ActionCatalog.mac)
        add("Sound", ActionCatalog.sound())
        add("System Settings", ActionCatalog.settingsPanes())
        for group in ActionCatalog.launcherCommands {
            add(group.group, group.actions)
        }
        add("Window Layouts", context.windowLayouts().map { .windowLayout($0.id) })
        add("Projects", context.recentProjects().prefix(12).map { .mac(.project($0)) })
        add("Skillies", context.scriptCommands().map { .mac(.script($0)) })
        add("Snippets", context.snippets.all.map { .snippet($0.id) })
        add("Quicklinks", context.quicklinks.links.map { .quicklink($0.id) })
        // An app's commands, each variant its own choice.
        for installed in LinkedApps.installed() {
            for command in installed.app.commands.filter({ $0.runs(onVersion: installed.version) }) {
                add(installed.app.name, [.mac(.appLink(command, variant: nil))]) { _ in command.title }
                for variant in command.variants(forVersion: installed.version) {
                    add(installed.app.name, [.mac(.appLink(command, variant: variant.id))]) { _ in "\(command.title): \(variant.title)" }
                }
            }
        }
        // The user's shortcuts in Apple's Shortcuts app, as they are or on the selection.
        for shortcut in AppleShortcuts.all() {
            add("Shortcuts", [.mac(.shortcut(shortcut, withSelection: false))]) { _ in shortcut.name }
            add("Shortcuts", [.mac(.shortcut(shortcut, withSelection: true))]) { _ in "\(shortcut.name), with the Selection" }
        }
        choices.append(ShortcutChoice(id: "openApp", section: "Apps", title: "Open App…", kind: .chooseApp))
        return choices
    }

    /// Whether every word typed is in its title or its section's name,
    /// case and accents aside.
    func matches(_ words: [String]) -> Bool {
        let text = "\(title) \(section)"
        return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// Keys → Add Shortcut…: every command, found by typing a few letters of
/// its name; ↑↓ and ↩ pick one, as a click does. Picking adds its row
/// without keys: Keys shows it, the user records there.
struct AddShortcutSheet: View {
    /// Read as the sheet opens: what exists now (a skillie just added).
    let load: () -> [ShortcutChoice]
    let pick: (ShortcutChoice) -> Void
    @State private var choices: [ShortcutChoice] = []
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: String?
    @FocusState private var searchFocused: Bool

    private var shown: [ShortcutChoice] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.isEmpty ? choices : choices.filter { $0.matches(words) }
    }

    /// The shown choices by section, in their order.
    private var sections: [(title: String, choices: [ShortcutChoice])] {
        var order: [String] = []
        var bySection: [String: [ShortcutChoice]] = [:]
        for choice in shown {
            if bySection[choice.section] == nil { order.append(choice.section) }
            bySection[choice.section, default: []].append(choice)
        }
        return order.map { ($0, bySection[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Find a command", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(12)
                .onSubmit(choose)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
            Divider()
            if shown.isEmpty {
                Text("No command named so.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selected) {
                        ForEach(sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.choices) { choice in
                                    Text(choice.title)
                                        .tag(choice.id)
                                        .id(choice.id)
                                }
                            }
                        }
                    }
                    .onChange(of: selected) { if let selected { proxy.scrollTo(selected) } }
                    // A click picks it, as ↩ does.
                    .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
                        if let id = ids.first { selected = id; choose() }
                    }
                }
            }
            Divider()
            HStack {
                Text("↩ adds it to Keys, where you press its shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { choose() }
                    .disabled(current == nil)
            }
            .padding(12)
        }
        .frame(width: 420, height: 460)
        .onAppear {
            choices = load()
            searchFocused = true
            selected = shown.first?.id
        }
        // Typing narrows the list: the first one left is the one ↩ adds.
        .onChange(of: query) { selected = shown.first?.id }
    }

    /// The selected choice when it is still shown, else the first one.
    private var current: ShortcutChoice? {
        shown.first { $0.id == selected } ?? shown.first
    }

    private func move(_ by: Int) {
        let list = shown
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selected } ?? (by > 0 ? -1 : list.count)
        selected = list[min(max(index + by, 0), list.count - 1)].id
    }

    private func choose() {
        guard let choice = current else { return }
        dismiss()
        pick(choice)
    }
}
