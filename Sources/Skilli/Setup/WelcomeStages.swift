import AppKit
import SwiftUI

// The welcome's stages: each step's live picture (docs/onboarding.md).
// Drawn, never a copy of macOS's own alerts; teal only on what is live.

// MARK: - 1. Welcome

/// The glass S on its halo, turning toward the pointer (the one 3D
/// transform AGENTS.md → Brand allows).
struct WelcomeMarkStage: View {
    @State private var tilt = MarkTilt()
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the next steps set up, said before they start.
    private static let setsUp = [("hand.raised", "Accessibility"), ("capslock", "Hyper Key"), ("command", "Launcher key"),
                                 ("sparkles", "Your SI")]

    var body: some View {
        VStack(spacing: 18) {
            mark
            HStack(spacing: 8) {
                ForEach(Self.setsUp, id: \.1) { symbol, name in
                    Label(name == "Your SI" ? "Your \(Brand.intelligence)" : name, systemImage: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.background.opacity(0.7), in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                }
            }
            .opacity(appeared ? 1 : 0)
        }
        .padding(.bottom, 26)
    }

    private var mark: some View {
        GlassMark(tilt: tilt, size: 118)
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .named(MarkTilt.space))
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { tilt.center = $0 }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.82)
            .offset(y: appeared || reduceMotion ? 0 : 18)
            .opacity(appeared ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(.named(MarkTilt.space))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tilt.paneSize = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): tilt.pointer(at: location)
                case .ended: tilt.pointer(at: nil)
                }
            }
            .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.25)) { appeared = true } }
    }
}

// MARK: - 2. Accessibility

/// What to do in System Settings, drawn: its list's title as this macOS
/// names it, skil.li's row, and a switch that turns itself on until the
/// real one is.
struct AccessibilityStage: View {
    let model: WelcomeModel

    /// macOS 27 renamed the list.
    static var listName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left").foregroundStyle(.tertiary)
                Text("Privacy & Security").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                Text(Self.listName).fontWeight(.semibold)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider().opacity(0.6)
            HStack(spacing: 12) {
                // The icon System Settings shows: the app's own.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                Text("skil.li").font(.system(size: 14, weight: .medium))
                Spacer()
                if model.accessibilityOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
                DrawnSwitch(lockedOn: model.accessibilityOn)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .animation(.spring(duration: 0.45, bounce: 0.35), value: model.accessibilityOn)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityOn ? "skil.li is on in \(Self.listName)" : "Turn on skil.li in \(Self.listName)")
    }
}

/// A switch drawn like macOS's: flips on and off on its own as a hint,
/// or stays on once the real one is.
struct DrawnSwitch: View {
    let lockedOn: Bool
    @State private var hint = false

    private var on: Bool { lockedOn || hint }

    var body: some View {
        Capsule()
            .fill(on ? WelcomeView.mint : Color.secondary.opacity(0.3))
            .frame(width: 38, height: 22)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 18, height: 18).padding(2).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            }
            .animation(.spring(duration: 0.35), value: on)
            .task(id: lockedOn) {
                guard !lockedOn else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.1))
                    hint.toggle()
                }
            }
    }
}

// MARK: - 3. The Hyper Key

/// The keyboard's left side. Caps Lock reads ✦; held, it sinks and glows,
/// and the keys it reaches say what they do.
struct HyperKeyStage: View {
    let model: WelcomeModel

    private static let unit: CGFloat = 44
    private static let gap: CGFloat = 6

    private var held: Bool { model.hyperHeld && model.hyperKey != .custom }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            row([("tab", 1.5, nil), ("Q", 1, nil), ("W", 1, nil), ("E", 1, nil), ("R", 1, nil), ("T", 1, nil)])
            HStack(spacing: Self.gap) {
                capsLock
                ForEach([("A", "Ask"), ("S", nil), ("D", nil), ("F", nil), ("G", nil)], id: \.0) { key, does in
                    DrawnKey(label: key, width: Self.unit, lit: held && does != nil, caption: held ? does : nil)
                }
            }
            row([("shift", 2.3, nil), ("Z", 1, nil), ("X", 1, nil), ("C", 1, "Clipboard"), ("V", 1, nil)])
            HStack(spacing: Self.gap) {
                DrawnKey(label: "fn", width: Self.unit, lit: false, caption: nil)
                DrawnKey(label: "⌃", width: Self.unit, lit: false, caption: nil)
                DrawnKey(label: "⌥", width: Self.unit, lit: false, caption: nil)
                DrawnKey(label: "⌘", width: Self.unit * 1.25, lit: false, caption: nil)
                DrawnKey(label: "", width: Self.unit * 3.2, lit: held, caption: held ? "Launcher" : nil)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: held)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(held ? "Caps Lock held: ✦ is on" : "Caps Lock is the Hyper Key, ✦")
    }

    private func row(_ keys: [(String, CGFloat, String?)]) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(keys, id: \.0) { key, width, does in
                DrawnKey(label: key, width: Self.unit * width, lit: held && does != nil, caption: held ? does : nil)
            }
        }
    }

    private var capsLock: some View {
        let custom = model.hyperKey == .custom
        return ZStack(alignment: .bottomLeading) {
            DrawnKey(label: custom ? "caps lock" : "✦", width: Self.unit * 1.8, lit: held, caption: nil, pressed: held, accent: !custom)
            if !custom {
                Text("caps lock")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(held ? .white.opacity(0.8) : .secondary)
                    .padding(.leading, 7)
                    .padding(.bottom, 5)
            }
        }
    }
}

/// One key: a rounded cap with a hairline, teal when lit, a word under
/// its letter when it says what it does.
struct DrawnKey: View {
    let label: String
    let width: CGFloat
    let lit: Bool
    let caption: String?
    var pressed = false
    /// The Hyper Key itself: teal outline even at rest.
    var accent = false
    var height: CGFloat = 44
    var fontSize: CGFloat = 15

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(lit ? AnyShapeStyle(WelcomeView.mint.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent && !lit ? WelcomeView.mint.opacity(0.7) : Color.primary.opacity(lit ? 0 : 0.14), lineWidth: accent && !lit ? 1.5 : 1)
            )
            .overlay {
                VStack(spacing: 1) {
                    Text(label)
                        .font(.system(size: label.count > 2 ? 11 : fontSize, weight: .medium))
                    if let caption {
                        Text(caption)
                            .font(.system(size: 8.5, weight: .semibold))
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(lit ? Color.white : accent ? WelcomeView.mint : .primary.opacity(0.75))
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(pressed ? 0 : 0.10), radius: 0, y: pressed ? 0 : 2)
            .offset(y: pressed ? 2 : 0)
    }
}

// MARK: - 4. The launcher

/// How skil.li opens: ⌘ Space (recommended, instead of Spotlight), ✦ Space,
/// or the person's own keys, recorded here; the chosen one teal, glowing
/// while the launcher is open. Refusals and notes as Settings → Keys says
/// them (`ShortcutNote`).
struct LauncherStage: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ForEach(Array(WelcomeModel.launcherChoices.enumerated()), id: \.element.spec) { index, choice in
                    LauncherChoice(keys: [choice.keys], name: choice.name, badge: index == 0 ? "Recommended" : nil,
                                   chosen: chosen == choice.spec, lit: chosen == choice.spec && lit) {
                        model.chooseLauncher(choice.spec)
                    }
                }
                LauncherChoice(keys: ownKeys, name: model.recordsLauncher ? "Press your keys…" : "Your own keys",
                               badge: nil, chosen: chosen != nil && !isPreset && !model.recordsLauncher, lit: !isPreset && lit,
                               recording: model.recordsLauncher) {
                    model.recordLauncher()
                }
            }
            status
                .font(.system(size: 12.5, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560, minHeight: 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: model.hyperHeld)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: model.launcherOpen)
        .animation(.spring(duration: 0.3), value: chosen)
        .animation(.spring(duration: 0.3), value: model.recordsLauncher)
    }

    /// The launcher's keys now.
    private var chosen: String? { model.launcherKeys }
    private var isPreset: Bool { WelcomeModel.launcherChoices.contains { $0.spec == chosen } }
    /// Its keys glow while it is open (✦ while Caps Lock is held).
    private var lit: Bool { model.launcherOpen || (chosen?.hasPrefix("hyper") == true && model.hyperHeld) }
    /// "Your own": the keys recorded, or a keyboard to say "record".
    private var ownKeys: [[String]] {
        isPreset || chosen == nil || model.recordsLauncher ? [] : model.launcherKeycaps
    }

    @ViewBuilder
    private var status: some View {
        if let error = model.launcherError {
            Text(error).foregroundStyle(.red)
        } else if let shortcuts = model.shortcuts, let id = shortcuts.launcherEntry?.id, ShortcutNote.shows(shortcuts, id),
                  !(chosen == "cmd+space" && shortcuts.warnings[id]?.isNote == true) {
            // Refused keys and why (red, with Open Keyboard Settings when
            // macOS has them), what to press while recording.
            ShortcutNote(store: shortcuts, id: id)
        } else if model.launcherTried {
            Label("Opened and closed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if model.launcherOpen {
            Label("The launcher is open", systemImage: "circle.fill").foregroundStyle(WelcomeView.mint)
        } else if chosen == "cmd+space" {
            Text("⌘ Space opens skil.li; Spotlight’s own ⌘ Space is turned off, and comes back if you choose other keys.")
                .foregroundStyle(.secondary)
        } else {
            Text("Press it: the launcher opens.").foregroundStyle(.secondary)
        }
    }
}

/// One way to open skil.li: its keys as caps (a keyboard to record when
/// none yet), its name, a badge; chosen, teal and checked.
private struct LauncherChoice: View {
    let keys: [[String]]
    let name: String
    let badge: String?
    let chosen: Bool
    let lit: Bool
    var recording = false
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 12) {
                Group {
                    if keys.isEmpty {
                        Image(systemName: recording ? "record.circle" : "keyboard")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(recording ? Color.red : WelcomeView.mint)
                            .symbolEffect(.pulse, isActive: recording)
                            .frame(height: 48)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(Array(keys.enumerated()), id: \.offset) { index, chord in
                                if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary) }
                                ForEach(chord, id: \.self) { cap in
                                    DrawnKey(label: cap, width: cap.count > 1 ? 74 : 44, lit: lit, caption: nil,
                                             pressed: lit, accent: cap == "✦", height: 48, fontSize: cap.count > 1 ? 13 : 20)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(chosen ? WelcomeView.mint : Color.secondary.opacity(0.6))
                    Text(name).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(chosen || recording ? .primary : .secondary)
                }
            }
            .frame(width: 196, height: 118)
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(WelcomeView.mint)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(WelcomeView.mint.opacity(0.14), in: Capsule())
                        .padding(8)
                }
            }
            .background(.background.opacity(chosen ? 0.9 : 0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(chosen || recording ? WelcomeView.mint.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: chosen || recording ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(keys.joined().joined(separator: " ")) \(name)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// MARK: - 5. Your SI

/// The providers found on this Mac, each with its state read live and
/// its one way to get ready; a key pasted in place, verified like
/// Settings → SI Accounts does.
struct IntelligenceStage: View {
    @Bindable var model: WelcomeModel
    @State private var showsKeyField = false

    private var ai: AIStore { model.ai }

    var body: some View {
        VStack(spacing: 6) {
            sectionHeader("Writes", detail: "answers and rewrites") {
                if !showsKeyField, model.keyTest == nil {
                    Button("Use an API key instead") { withAnimation(.spring(duration: 0.35)) { showsKeyField = true } }
                        .buttonStyle(.link)
                }
            }
            card {
                claudeRow
                Divider().padding(.leading, 62)
                chatGPTRow
                if showsKeyField || model.keyTest != nil {
                    Divider().padding(.leading, 62)
                    keyRow
                }
            }
            sectionHeader("Chooses", detail: "Ask in a blink, search by meaning, Do It Here") { EmptyView() }
                .padding(.top, 6)
            card { decisionRow }
        }
        .frame(width: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await ai.refresh()
            model.chooseReadyWriter()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from a sign-in in Terminal or the browser.
            Task {
                await ai.refresh()
                model.chooseReadyWriter()
            }
        }
    }

    /// "WRITES · answers and rewrites", a control at the right.
    private func sectionHeader<Trailing: View>(_ title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            Spacer()
            trailing().font(.system(size: 11))
        }
        .padding(.horizontal, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    /// TypeSafe Jev: saved (or the OpenAI key chooses), else a field and
    /// Verify, as Settings → SI Accounts.
    @ViewBuilder
    private var decisionRow: some View {
        // Ready only once a key works: a failed Verify keeps the field,
        // its reason and Verify, to paste another.
        if let chooser = model.chooser {
            ProviderRow(symbol: "arrow.triangle.branch", tint: .orange, title: chooser == .typeSafe ? "TypeSafe Jev" : "OpenAI Decisions",
                        detail: decisionDetail, ready: true, chosen: false) { EmptyView() }
        } else {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.triangle.branch", tint: .orange, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("TypeSafe Jev").font(.system(size: 14, weight: .semibold))
                        Text("Recommended").font(.system(size: 10, weight: .semibold)).foregroundStyle(WelcomeView.mint)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(WelcomeView.mint.opacity(0.14), in: Capsule())
                    }
                    SecureField("Paste your key from typesafe.ai", text: $model.pastedDecisionKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await model.verifyDecisionKey() } }
                    decisionStatus
                }
                Button("Verify") { Task { await model.verifyDecisionKey() } }
                    .disabled(model.pastedDecisionKey.trimmingCharacters(in: .whitespaces).isEmpty || model.decisionTest == .running)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var decisionDetail: String {
        if case .passed(_, let latency)? = model.decisionTest {
            return "Works · \(latency.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))"
        }
        return model.chooser == .typeSafe ? "Chooses in a fraction of a second, a fraction of a cent a choice" : "Your OpenAI key chooses"
    }

    @ViewBuilder
    private var decisionStatus: some View {
        switch model.decisionTest {
        case .failed(let why)?:
            Text(why).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
        case .running?:
            Text("Verifying…").font(.system(size: 11)).foregroundStyle(.secondary)
        case .passed?, nil:
            Text("Without it, Ask waits for Claude Code and nothing is found by meaning.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var claudeRow: some View {
        ProviderRow(symbol: "sparkle", tint: Color(red: 0.85, green: 0.47, blue: 0.34), title: "Claude",
                    detail: claudeDetail, ready: claudeReady, chosen: model.preferences.writingModel.provider == .claude && claudeReady) {
            switch ai.claudeStatus {
            case .notInstalled?:
                Button("Install Claude Code…") { NSWorkspace.shared.open(URL(string: "https://claude.com/claude-code")!) }
            case .signedOut?:
                Button("Sign In…") { ai.signIn() }
            case nil:
                ProgressView().controlSize(.small)
            case .signedIn?:
                EmptyView()
            }
        }
    }

    private var claudeReady: Bool { ai.availability(.claude) == .ready }

    private var claudeDetail: String {
        switch ai.claudeStatus {
        case .signedIn(let plan)?: "Your subscription, through Claude Code" + (plan.map { " · \($0.capitalized)" } ?? "")
        case .signedOut?: "Claude Code is here: sign in once, in Terminal."
        case .notInstalled?: ai.hasAPIKey ? "Your API key" : "Your subscription, through Claude Code"
        case nil: "Looking for Claude Code…"
        }
    }

    private var chatGPTRow: some View {
        let ready = ai.availability(.chatGPT) == .ready && ai.codexStatus != nil
        return ProviderRow(symbol: "bubble.left.and.text.bubble.right", tint: Color(red: 0.2, green: 0.2, blue: 0.22), title: "ChatGPT",
                           detail: chatGPTDetail, ready: ready, chosen: model.preferences.writingModel.provider == .chatGPT && ready) {
            switch ai.codexStatus {
            case .notInstalled?:
                Button("Install Codex…") { NSWorkspace.shared.open(URL(string: "https://learn.chatgpt.com/docs/codex/cli")!) }
            case .signedOut?:
                Button("Sign In…") { ai.signInToChatGPT() }
            case nil:
                ProgressView().controlSize(.small)
            case .signedIn?:
                EmptyView()
            }
        }
    }

    private var chatGPTDetail: String {
        switch ai.codexStatus {
        case .signedIn?: "Your ChatGPT plan, through Codex"
        case .signedOut?: "Codex is here: sign in once, in Terminal."
        case .notInstalled?: "Your ChatGPT plan, through Codex"
        case nil: "Looking for Codex…"
        }
    }

    private var keyRow: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "key.fill", tint: .gray, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                SecureField("Claude API key", text: $model.pastedKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.verifyKey() } }
                switch model.keyTest {
                case .passed(_, _, let total)?:
                    Label("Works · \(total.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.green)
                case .failed(let why)?:
                    Text(why).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                case .running?:
                    Text("Verifying…").font(.system(size: 11)).foregroundStyle(.secondary)
                case nil:
                    Text("Kept in your Keychain.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Button("Verify") { Task { await model.verifyKey() } }
                .disabled(model.pastedKey.trimmingCharacters(in: .whitespaces).isEmpty || model.keyTest == .running)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// One provider: its tile, name and state; a check when it writes, else
/// its one way in.
private struct ProviderRow<Action: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let ready: Bool
    let chosen: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if chosen {
                        Text("Writes for you")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WelcomeView.mint)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(WelcomeView.mint.opacity(0.14), in: Capsule())
                    }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if ready {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.green)
            } else {
                action().controlSize(.regular)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - 6. Try it on text

/// A note with one sentence, selected: a real field the commands act on,
/// as in any app.
struct PracticeStage: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 16) {
            PracticeField(model: model)
                .frame(width: 460, height: 74)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(model.practice == .waiting ? Color.primary.opacity(0.08) : WelcomeView.mint.opacity(0.6), lineWidth: model.practice == .waiting ? 1 : 1.5))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
            HStack(spacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, chord in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
                    HStack(spacing: 4) {
                        ForEach(chord, id: \.self) { cap in
                            DrawnKey(label: cap, width: 34, lit: false, caption: nil, accent: cap == "✦", height: 30, fontSize: 13)
                        }
                    }
                }
                if model.practice != .waiting {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        DrawnKey(label: "⌘", width: 34, lit: model.practice == .undone, caption: nil, height: 30, fontSize: 13)
                        DrawnKey(label: "Z", width: 34, lit: model.practice == .undone, caption: nil, height: 30, fontSize: 13)
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.35), value: model.practice)
    }

    private var keys: [[String]] {
        let keys = model.keys(model.practiceAction)
        if !keys.isEmpty { return keys }
        return model.practiceAction == .aiPrompt("fix") ? [["✦", "K"], ["G"]] : [["✦", "U"]]
    }
}

/// The practice sentence in an editable field, selected whole when the
/// step shows; reports each change of its text.
struct PracticeField: NSViewRepresentable {
    let model: WelcomeModel

    func makeNSView(context: Context) -> NSTextField {
        let field = PracticeTextField(wrappingLabelWithString: WelcomeModel.practiceSentence)
        // Selected whole once it is in the window, as if the person had.
        field.onWindow = { [coordinator = context.coordinator] in coordinator.selectAll() }
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 17)
        field.focusRingType = .none
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Practice sentence")
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.model = model
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    /// Tells when it is in a window: the step slid in, ready to select.
    final class PracticeTextField: NSTextField {
        var onWindow: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // After the hosting view's own first responder settles.
            DispatchQueue.main.async { [weak self] in self?.onWindow?() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var model: WelcomeModel
        weak var field: NSTextField?

        init(model: WelcomeModel) { self.model = model }

        func selectAll() {
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field else { return }
            model.practiceText(field.stringValue)
        }

        /// ↩ in the field is the window's Continue, not a new line.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            model.next()
            return true
        }
    }
}

// MARK: - 7. Ready

/// What the welcome set up, line by line: on (a check) or missing (where
/// to set it later); Open at login under them.
struct ReadyStage: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.setUp.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 40) }
                    HStack(spacing: 12) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(item.done ? Color.green : Color.orange)
                            .frame(width: 18)
                        Text(item.title).font(.system(size: 13.5, weight: .medium))
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.state).font(.system(size: 13)).foregroundStyle(item.done ? .primary : .secondary)
                            if let fix = item.fix {
                                Text(fix).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
            }
            .frame(width: 440)
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            Toggle("Open skil.li at login", isOn: $model.openAtLogin)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
