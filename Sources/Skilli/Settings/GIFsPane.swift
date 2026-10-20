import SkilliCore
import SwiftUI

/// Settings → GIFs, everything about Search GIFs in one place: how to
/// reach it (a shortcut, its prefix in the launcher), where Klipy's GIFs
/// come from (skil.li's key, or the user's own under Advanced), what
/// leaves the Mac. Keys and Catalog list it too, as they list everything.
struct GIFsPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Keys, Privacy).
    let open: (SettingsPane) -> Void
    @State private var keyDraft = ""
    @State private var source: GIFLibrary.KeySource = .none
    @State private var keyNote: String?

    var body: some View {
        Form {
            Section {
                if let entry = context.shortcuts.config.shortcuts.first(where: { $0.action == .searchGIFs }) {
                    ShortcutRow(store: context.shortcuts, id: entry.id, title: SkilliAction.searchGIFs.title, chords: entry.chords)
                } else {
                    LabeledContent {
                        PaneLink(pane: .keys, open: open)
                    } label: {
                        LabelDetail(SkilliAction.searchGIFs.title, "No shortcut yet: Keys → Add Shortcut → Search GIFs.")
                    }
                }
                if let prefix = LauncherPrefix.shown(for: .searchGIFs)?.trimmingCharacters(in: .whitespaces) {
                    LabeledContent {
                        KeycapLabel(prefix)
                            .padding(.trailing, 8)
                    } label: {
                        LabelDetail("From the launcher", "Type “\(prefix)” and a space, then what the GIF should say.")
                    }
                }
            } header: {
                PaneHeader(pane: .gifs)
            } footer: {
                Text("↩ pastes the GIF animated in the app you are in (its Markdown in a terminal or a code editor), ⌘↩ only copies it.")
            }

            Section {
                LabeledContent {
                    StatusPill(text: source == .none ? "Not searched" : "Searched", tint: source == .none ? .orange : .green)
                } label: {
                    LabelDetail("Klipy", sourceLine)
                }
            } footer: {
                Text("Klipy's GIFs load from Klipy as they are; none is kept on this Mac. The GIFs on this Mac are found by Spotlight, here.")
            }

            // The self-test draws it as set up (`PrivacyPane.sample`).
            if let line = PrivacyMap.line(for: SettingsPane.gifs.rawValue, PrivacyPane.sample ?? .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }

            AdvancedSection(summary: "Your own Klipy key", footer: "Kept in the Keychain of this Mac; Search GIFs asks Klipy with it instead of skil.li's.",
                            anchors: ["klipyKey"]) {
                keyRow
            }
        }
        .formStyle(.grouped)
        .onAppear { source = context.gifs?.keySource ?? .none }
        .onReceive(NotificationCenter.default.publisher(for: SettingTools.changed)) { _ in source = context.gifs?.keySource ?? .none }
    }

    private var sourceLine: String {
        switch source {
        case .own: "With your own key, below."
        case .skilli: "With skil.li's key: nothing to set up."
        case .none: "This build has no Klipy key: add your own under Advanced (free at partner.klipy.com). The GIFs on this Mac are found without it."
        }
    }

    @ViewBuilder
    private var keyRow: some View {
        if source == .own {
            LabeledContent("Your Klipy key") {
                HStack(spacing: 8) {
                    StatusPill(text: "Saved", tint: .green)
                    Button("Remove", role: .destructive) {
                        // At once; ⌘Z in the card saves it again.
                        if let gifs = context.gifs { context.deletes.klipyKey(in: gifs) }
                        source = context.gifs?.keySource ?? .none
                    }
                }
            }
            .settingAnchor("klipyKey")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SecureField("Your Klipy key", text: $keyDraft, prompt: Text("Paste your key from partner.klipy.com"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let keyNote {
                    Text(keyNote).font(.callout).foregroundStyle(.red)
                }
            }
            .settingAnchor("klipyKey")
        }
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let gifs = context.gifs else { return }
        // Klipy's keys are letters and digits; anything else could not be one.
        guard Klipy.itemsURL(["x"], key: key) != nil else {
            keyNote = "That does not look like a Klipy key: letters and digits only."
            return
        }
        do {
            try gifs.saveOwnKey(key)
            keyDraft = ""
            keyNote = nil
            source = gifs.keySource
        } catch {
            keyNote = "The Keychain did not keep it: \(error.localizedDescription)"
        }
    }
}
