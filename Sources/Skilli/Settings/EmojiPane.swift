import SkilliCore
import SwiftUI

/// Settings → Emoji, everything about the emoji picker in one place, in
/// the order of the Settings plan's rules: how to reach it first (⌃⌘Space,
/// in place of macOS's Emoji & Symbols, and its prefix in the launcher),
/// the skin tone; finding one by feeling and the words learned from what
/// you picked; what leaves the Mac. Keys and Catalog list it too, as they
/// list everything.
struct EmojiPane: View {
    @Bindable var preferences: Preferences
    let context: SettingsContext
    /// Shows another pane (Privacy, SI Accounts).
    let open: (SettingsPane) -> Void
    /// Read as the pane opens, after Forget and after ⌘Z.
    @State private var learned = 0

    var body: some View {
        Form {
            Section {
                if let entry = context.shortcuts.config.shortcuts.first(where: { $0.action == .searchEmoji }) {
                    ShortcutRow(store: context.shortcuts, id: entry.id, title: SkilliAction.searchEmoji.title, chords: entry.chords)
                }
                if let prefix = LauncherPrefix.shown(for: .emoji)?.trimmingCharacters(in: .whitespaces) {
                    LabeledContent {
                        KeycapLabel(prefix)
                            .padding(.trailing, 8)
                    } label: {
                        LabelDetail("From the launcher", "Type “\(prefix)” then an emoji's name, in your language or in English.")
                    }
                }
                LabeledContent {
                    SkinTonePicker(tone: $preferences.emojiSkinTone)
                } label: {
                    // The examples in the tone chosen, by the same code.
                    LabelDetail("Skin tone", "Emoji that come in tones use it: "
                                + ["👍", "👋", "🙏"].map(preferences.emojiSkinTone.apply).joined(separator: " "))
                }
                .settingAnchor("emojiSkinTone")
            } header: {
                PaneHeader(pane: .emoji)
            } footer: {
                Text("↩ types the emoji in the app you are in, ⌘↩ only copies it.")
            }

            Section {
                Toggle(isOn: $preferences.emojiMeaningSearch) {
                    LabelDetail("Find emoji by feeling with ⇥",
                                "Say it as you would (“trop content mais crevé”), then ⇥. When no name fits, it asks by itself.")
                }
                .settingAnchor("emojiMeaningSearch")
                LabeledContent {
                    // At once, nothing asked: ⌘Z in the card brings them back (rule 2).
                    Button("Forget") {
                        if let emoji = context.emoji { context.deletes.wordsLearned(in: emoji) }
                        learned = context.emoji?.saidCount ?? 0
                    }
                    .disabled(learned == 0)
                } label: {
                    LabelDetail("Words learned", learned == 0
                                ? "None yet. An emoji you pick after ⇥ is then found by the same words, at once."
                                : "\(learned == 1 ? "1 phrase" : "\(learned) phrases") from your picks after ⇥: the same words find the emoji at once.")
                }
                .settingAnchor("section.wordsLearned")
            } footer: {
                Text("Your TypeSafe Jev or OpenAI Decisions key picks it, in SI Accounts. The words learned stay on this Mac.")
            }

            // The self-test draws it as set up (`PrivacyPane.sample`).
            if let line = PrivacyMap.line(for: SettingsPane.emoji.rawValue, PrivacyPane.sample ?? .current(preferences, context)) {
                Section {
                    LeavesMacRow(line: line, open: open)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { learned = context.emoji?.saidCount ?? 0 }
        .onReceive(NotificationCenter.default.publisher(for: SettingTools.changed)) { _ in learned = context.emoji?.saidCount ?? 0 }
    }
}

/// The six skin tones as hands, drawn by the same code that tones the
/// emoji typed (`EmojiSkinTone.apply`); the chosen one on a tile.
struct SkinTonePicker: View {
    @Binding var tone: EmojiSkinTone

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EmojiSkinTone.allCases, id: \.self) { option in
                let chosen = option == tone
                Button {
                    tone = option
                } label: {
                    Text(option.apply(to: "🖐️"))
                        .font(.system(size: 17))
                        .frame(width: 32, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(chosen ? Color.accentColor.opacity(0.18) : .clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(chosen ? 0.9 : 0), lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}
