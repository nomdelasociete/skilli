import SwiftUI

/// "Welcome to skil.li" (docs/onboarding.md): one step at a time, each
/// with its live picture on top (the stage), its words below, and one
/// filled button. ↩ continues, esc goes back; the live steps take only
/// their own keys.
struct WelcomeView: View {
    @Bindable var model: WelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 720, height: 540)
    static let stageHeight: CGFloat = 300
    /// skil.li's teal (the asset catalog's AccentColor), on the live parts.
    static let mint = Color("AccentColor")

    /// The title bar's height: the stage runs under it, its content below.
    static let titleBar: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            stage
                .padding(.top, Self.titleBar)
                .frame(height: Self.stageHeight)
                .frame(maxWidth: .infinity)
                .background(StageBackground())
                .clipped()
            words
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .onChange(of: model.permissions.state(.accessibility)) { model.accessibilityChanged() }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            stageContent(model.step)
                .id(model.step)
                .transition(stageTransition)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.18), value: model.step)
    }

    private var stageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let forward = model.direction >= 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func stageContent(_ step: WelcomeModel.Step) -> some View {
        switch step {
        case .welcome: WelcomeMarkStage()
        case .accessibility: AccessibilityStage(model: model)
        case .hyperKey: HyperKeyStage(model: model)
        case .launcher: LauncherStage(model: model)
        case .intelligence: IntelligenceStage(model: model)
        case .practice: PracticeStage(model: model)
        case .ready: ReadyStage(model: model)
        }
    }

    // MARK: - Words

    private var words: some View {
        VStack(spacing: 0) {
            ProgressDots(count: model.steps.count, current: model.position)
                .padding(.top, 22)
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                line
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .id(model.step)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: model.step)
            Spacer(minLength: 12)
            controls
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
    }

    private var title: String {
        switch model.step {
        case .welcome: "Let’s set up skil.li."
        case .accessibility: model.accessibilityOn ? "skil.li works in every app." : "One switch, and skil.li works in every app."
        case .hyperKey:
            switch model.hyperKey {
            case .custom: "Your Hyper Key"
            case .own, .shared: model.hyperFelt ? "That’s ✦, your Hyper Key." : "Caps Lock is your Hyper Key now."
            }
        case .launcher: model.launcherTried ? "That’s the launcher." : "Open skil.li with one key."
        case .intelligence: "Bring your own SI."
        case .practice:
            switch model.practice {
            case .waiting: "Try it: fix any text, in any app."
            case .fixed: "Fixed."
            case .undone: "It acts. ⌘Z undoes."
            }
        case .ready: model.setUp.allSatisfy(\.done) ? "skil.li is set up." : "Almost set up."
        }
    }

    @ViewBuilder
    private var line: some View {
        switch model.step {
        case .welcome:
            Text("A minute: one switch, your keys and your SI. Then it works in every app. Free, open source, no account.")
        case .accessibility:
            if model.accessibilityOn {
                Text("Its keys work everywhere, and it can read and replace the text you select.")
            } else if model.permissions.state(.accessibility) == .notAsked {
                Text("It lets skil.li hear its keys, and read and replace the text you select. Nothing leaves your Mac for it.")
            } else {
                Text("In the list that opened, turn on skil.li. This moves on by itself.")
            }
        case .hyperKey:
            switch model.hyperKey {
            case .custom:
                Text("Caps Lock already has a custom mapping, left as is. Choose your Hyper Key in Settings → Keys.")
            case .own, .shared:
                if model.hyperFelt {
                    Text(model.hyperKey == .shared
                         ? "Hold it with a letter: ✦A asks, ✦C opens your clipboard. Shared with your other Hyper Key app: both work."
                         : "Hold it with a letter: ✦A asks, ✦C opens your clipboard. Tapped alone, it’s Escape.")
                } else {
                    Text("Hold Caps Lock now. With a letter, it runs skil.li’s shortcuts; tapped alone, it’s Escape.")
                }
            }
        case .launcher:
            if model.launcherTried {
                Text("Apps, files, what you copied, commands: everything skil.li does starts there.")
            } else if model.launcherOpen {
                Text("Type a few letters, then esc.")
            } else {
                Text("Choose its keys, then press them: the launcher opens. Type a few letters; ↩ opens, esc closes.")
            }
        case .intelligence:
            Text("Your Claude or ChatGPT writes, TypeSafe Jev chooses in a blink. No credits, no account with us: only what a request needs leaves your Mac (Settings → Privacy).")
        case .practice:
            switch model.practice {
            case .waiting:
                Text(model.practiceAction == .aiPrompt("fix")
                     ? "The sentence is selected. Press ✦K, then G; ↩ puts the fix in place."
                     : "The sentence is selected. Press ✦U: UPPERCASE. With your SI, ✦K G fixes spelling and grammar.")
            case .fixed:
                Text("Now press ⌘Z: it comes back as it was.")
            case .undone:
                Text("What can be taken back happens at once, with ⌘Z right after.")
            }
        case .ready:
            Text(model.setUp.allSatisfy(\.done)
                 ? "Everything else: type ? in the launcher."
                 : "What is missing can be set later, where each line says. Everything else: type ? in the launcher.")
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 18) {
            Button(model.position == 0 ? "Later" : "Back", action: model.back)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            if let skip = skipTitle {
                Button(skip, action: model.skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button(action: model.next) {
                HStack(spacing: 8) {
                    Text(primaryTitle)
                    Text("↩").opacity(0.6)
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.mint)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(primaryDisabled)
        }
        .font(.system(size: 14))
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: "Get Started"
        case .accessibility: "Continue"
        case .intelligence: model.intelligenceReady ? "Continue" : "Later"
        case .ready: "Start"
        default: "Continue"
        }
    }

    /// Continue waits for the switch once macOS was asked (Skip goes on
    /// without it).
    private var primaryDisabled: Bool {
        model.step == .accessibility && !model.accessibilityOn && model.permissions.state(.accessibility) != .notAsked
    }

    private var skipTitle: String? {
        switch model.step {
        case .accessibility: model.accessibilityOn ? nil : "Later"
        case .hyperKey: model.hyperKey == .custom || model.hyperFelt ? nil : "Skip"
        case .launcher: model.launcherTried ? nil : "Skip"
        case .practice: model.practice == .undone ? nil : "Skip"
        default: nil
        }
    }
}

/// The steps as dots: the current one long and teal, the done ones
/// filled, the rest outlined.
private struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? WelcomeView.mint : index < current ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.18))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(duration: 0.35), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// The stage's light: a soft teal halo from the top, deeper in dark mode.
private struct StageBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [WelcomeView.mint.opacity(scheme == .dark ? 0.32 : 0.20), .clear],
                center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 420
            )
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
