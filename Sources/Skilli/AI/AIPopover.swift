import AppKit
import SkilliCore

/// The answer to an AI action, in a glass card next to the selection.
///
/// Never takes focus or mouse events: the selection stays live in the
/// user's app, ⌘V replaces it there, and keys reach skil.li through the
/// event tap (`KeyRouter`). Asks the command's questions first, streams
/// plain text while Claude writes, then highlights what changed.
@MainActor
final class AIPopover {
    enum Phase: Equatable {
        case asking
        /// "Allow …?" for a tool.
        case approving
        case streaming
        case done
        case failed
    }

    /// Where the card goes: in the launcher's place (its glass frame) when
    /// the launcher started it, it reads as the launcher turned answer;
    /// else under the selection it works on (above when there is no room).
    enum Placement {
        case launcher(NSRect)
        case selection(NSRect)
    }

    private enum Layout {
        static let width: CGFloat = 460
        static let padding: CGFloat = 16
        static let headerHeight: CGFloat = 22
        static let footerHeight: CGFloat = 26
        static let gap: CGFloat = 10
        static let maxBodyHeight: CGFloat = 280
        /// In the launcher's place: as tall as the launcher's list.
        static let launcherMaxBodyHeight: CGFloat = 400
        static let minBodyHeight: CGFloat = 22
        static let distanceFromSelection: CGFloat = 8
    }

    private lazy var panel = makePanel()
    private let content = NSView()
    private lazy var glass = Theme.glass(cornerRadius: Theme.Radius.overlay, content: content)
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let scrollView = NSScrollView()
    private let body = NSTextView()
    private let hints = HintBar()
    private let questionView = QuestionView()
    /// A purpose-made view in place of the text (`showContent`).
    private var custom: CardContent?
    /// While asking: what `QuestionView` shows.
    private var asked: (question: PromptQuestion, selected: Int, typed: String, context: String?)?
    /// Re-applied in `layout`: `HintBar` places keys from its current width.
    private var currentHints: [(label: String, key: String)] = []
    private var placement: Placement = .selection(.zero)
    private var shownSymbol = "sparkles"
    /// Where the card stays while it grows, set once per show: its left
    /// edge, and its top (growing down) or its bottom (growing up). Laid out
    /// again on every chunk, it never jumps.
    private var pin: (x: CGFloat, edge: CGFloat, growsDown: Bool)?

    private var width: CGFloat {
        if case .launcher(let frame) = placement { return frame.width }
        return Layout.width
    }

    private var maxBodyHeight: CGFloat {
        if case .launcher = placement { return Layout.launcherMaxBodyHeight }
        return Layout.maxBodyHeight
    }

    private(set) var phase: Phase = .done
    var isVisible: Bool { panel.isVisible }
    /// Self-test hook: the text shown, without highlighting (struck
    /// deletions included once done).
    var shownText: String { body.string }
    /// Self-test hook: the keys' labels at the bottom ("Allow", "Always", "Deny").
    var shownHints: [String] { currentHints.map(\.label) }
    /// The rewrite, once done.
    private(set) var result = ""
    /// Self-test hook: the question shown and the option selected.
    var shownQuestion: (text: String, selected: Int, typed: String)? {
        asked.map { ($0.question.question, $0.selected, $0.typed) }
    }
    /// Self-test hook: the options the question offers.
    var shownOptions: [String] { asked?.question.options ?? [] }
    /// Self-test hook: what the question follows on from, above it.
    var shownContext: String? { asked?.context }
    /// Self-test hook: where the typed answer ends and where the caret is.
    var answerCaret: (textEnd: CGFloat, caret: CGFloat) { questionView.answerCaret }
    var answerCaretOnScreen: NSRect? { questionView.answerCaretOnScreen }
    /// Self-test hook: the window, for screen captures.
    var window: NSWindow { panel }

    /// An option of the question clicked (its index).
    var onOptionPicked: ((Int) -> Void)?
    /// Self-test hook: where option `index` shows on screen.
    func optionFrameOnScreen(_ index: Int) -> NSRect? { questionView.optionFrameOnScreen(index) }

    init() {
        buildViews()
        questionView.onPick = { [weak self] index in self?.onOptionPicked?(index) }
    }

    /// Screen coordinates (AppKit, bottom-left origin). `symbol`: the SF
    /// Symbol before the title (SI's sparkles; Dictate's microphone).
    func show(title text: String, at placement: Placement, symbol: String = "sparkles") {
        self.placement = placement
        pin = nil
        result = ""
        asked = nil
        dropContent()
        title.stringValue = text
        setSymbol(symbol)
        setBody(NSAttributedString(string: ""))
        setPhase(.streaming, status: "Writing…")
        layout()
        panel.orderFrontRegardless()
    }

    /// A question from the command: options as numbered chips with
    /// `selected` filled, or the text typed so far. `position` is
    /// (number, total).
    /// `context`: what the question follows on from, dimmed above it.
    /// `returnTitle`: what Return does when it is not Run or Next
    /// (Dictate: "Insert").
    func ask(_ question: PromptQuestion, position: (Int, Int), selected: Int, typed: String, context: String? = nil,
             returnTitle: String? = nil) {
        let statusText = position.1 > 1 ? "\(position.0) of \(position.1)" : ""
        // A key typed: only the answer line changes, the card keeps its
        // size; nothing else is measured or drawn again.
        if phase == .asking, let current = asked, current.question == question, current.selected == selected,
           current.context == context, status.stringValue == statusText, question.options.isEmpty {
            asked?.typed = typed
            questionView.showTyped(typed)
            return
        }
        asked = (question, selected, typed, context)
        dropContent()
        setPhase(.asking, status: statusText)
        let isLast = position.0 == position.1
        let next = returnTitle ?? (isLast ? "Run" : "Next")
        currentHints = question.options.isEmpty
            ? [(next, "↩"), ("Cancel", "esc")]
            : [("Choose", question.options.count > 1 ? "1–\(min(question.options.count, 9))" : "1"), (next, "↩"), ("Cancel", "esc")]
        layout()
    }

    /// One thing an agent did, for the card.
    struct Step: Equatable {
        enum State: Equatable {
            case running
            case done
            case failed
        }

        let id: String
        let title: String
        var state: State
        /// Which of the user's rules let it run or refused it.
        var note: String?

        init(id: String, title: String, state: State, note: String? = nil) {
            self.id = id
            self.title = title
            self.state = state
            self.note = note
        }
    }

    /// An agent at work: its steps so far, then what it is writing.
    func activity(_ steps: [Step], text: String, status statusText: String = "Working…") {
        asked = nil
        setBody(Self.activityText(steps, text: text))
        if phase != .streaming || status.stringValue != statusText { setPhase(.streaming, status: statusText) }
        layout()
    }

    /// "Allow …?" with what the tool would do; `header` replaces the title
    /// (an agent outside a command: "Claude Code"). Without `offersAlways`,
    /// ⌘↩ is not shown (it allows once).
    /// `reason`: the user's rule that asked ("Asked because of your rule: …").
    /// `verb`: a question the user answers with what it does ("Restart?",
    /// ↩ Restart, esc Cancel); without it, an agent's tool to allow
    /// ("Allow “Send a message”?", ↩ Allow, esc Deny).
    func approve(_ title: String, detail: String, header: String? = nil, offersAlways: Bool = true, reason: String? = nil, verb: String? = nil) {
        asked = nil
        if let header { self.title.stringValue = header }
        let headline = verb == nil ? "Allow “\(title)”?" : title.hasSuffix("?") ? title : title + "?"
        let text = NSMutableAttributedString(string: headline, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor
        ])
        if !detail.isEmpty {
            text.append(Self.plain("\n" + detail, color: .secondaryLabelColor))
        }
        if let reason {
            // A little apart from what the tool sends: it says why it asks.
            text.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)]))
            text.append(NSAttributedString(string: "\n" + reason, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        setBody(text)
        setPhase(.approving, status: "")
        let (yes, no) = verb.map { ($0, "Cancel") } ?? ("Allow", "Deny")
        currentHints = offersAlways ? [(yes, "↩"), ("Always", "⌘↩"), (no, "esc")] : [(yes, "↩"), (no, "esc")]
        layout()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Shows the card for someone outside a command (an agent's question).
    func present(title text: String, at placement: Placement) {
        if !panel.isVisible {
            self.placement = placement
            pin = nil
        }
        result = ""
        title.stringValue = text
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Self-test hook: the title shown.
    var shownTitle: String { title.stringValue }
    /// Self-test hook: the status line ("Done by Jev · 2 steps · 1.2 s").
    var shownStatus: String { status.stringValue }

    private static func activityText(_ steps: [Step], text: String) -> NSAttributedString {
        let body = NSMutableAttributedString()
        for (index, step) in steps.enumerated() {
            let (mark, color): (String, NSColor) = switch step.state {
            case .running: ("◌ ", .labelColor)
            case .done: ("✓ ", .secondaryLabelColor)
            case .failed: ("✕ ", .systemRed)
            }
            body.append(NSAttributedString(string: mark, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: step.state == .done ? NSColor.controlAccentColor : color]))
            body.append(NSAttributedString(string: step.title + (step.state == .running ? "…" : ""), attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: color
            ]))
            if let note = step.note {
                body.append(NSAttributedString(string: " · " + note, attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            if index < steps.count - 1 || !text.isEmpty { body.append(NSAttributedString(string: "\n")) }
        }
        if !text.isEmpty {
            if !steps.isEmpty { body.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)])) }
            body.append(rendered(text))
        }
        return body
    }

    /// Answers given: Claude writes (or Ask chooses what to do).
    func startWriting(status text: String = "Writing…") {
        asked = nil
        setPhase(.streaming, status: text)
        layout()
    }

    /// `markdown`: an answer for the card (its Markdown shown styled); a
    /// rewrite to be pasted shows exactly what will be pasted.
    func stream(_ text: String, markdown: Bool = false) {
        setBody(markdown ? Self.rendered(text) : Self.plain(text))
        layout()
    }

    /// Final text. A rewrite (`.replace` of a selection) shows what changed
    /// against `original`; the keys offered follow `output`.
    /// "In Claude Code ⌘↩", offered after an answer when a CLI is there.
    var continueHint: (String, String)?
    /// Self-test hook: the hints shown.
    var hintTitles: [String] { currentHints.map(\.0) }
    /// Self-test hook: their keys ("⌘Z", "esc").
    var hintKeys: [String] { currentHints.map(\.1) }

    /// `followUp`: ⇥ asks a follow-up (an answer in the card).
    func finish(original: String, result: String, status text: String, output: OutputMode = .replace,
                hints customHints: [(String, String)]? = nil, followUp: Bool = false) {
        self.result = result
        let isRewrite = output == .replace && !original.isEmpty
        let isAnswer = output == .card || output == .copy
        setBody(isRewrite ? Self.highlighted(from: original, to: result) : isAnswer ? Self.rendered(result) : Self.plain(result))
        setPhase(.done, status: text)
        switch output {
        case .replace: currentHints = [(original.isEmpty ? "Insert" : "Replace", "↩"), ("Copy", "⌘C"), ("Cancel", "esc")]
        case .insert: currentHints = [("Insert After", "↩"), ("Copy", "⌘C"), ("Cancel", "esc")]
        case .copy: currentHints = [("Done", "↩")]
        case .card: break
        }
        // A changed text followed up (⇥) is changed again.
        if followUp, output != .card { currentHints.insert(("Follow up", "⇥"), at: 1) }
        switch output {
        case .replace, .insert, .copy: break
        case .card: currentHints = followUp ? [("Copy", "↩"), ("Follow up", "⇥"), ("Close", "esc")] : [("Copy", "↩"), ("Close", "esc")]
        }
        if let customHints {
            currentHints = customHints
        } else if let continueHint {
            currentHints.insert(continueHint, at: max(0, currentHints.count - 1))
        }
        layout()
    }

    /// The command left the text as it was: say so, instead of offering to
    /// paste the same text back.
    func unchanged(_ message: String, text: String, status: String, followUp: Bool = false) {
        result = text
        setBody(Self.plain(message, color: .secondaryLabelColor))
        setPhase(.done, status: status)
        currentHints = followUp ? [("Done", "↩"), ("Follow up", "⇥")] : [("Done", "↩")]
        layout()
    }

    func fail(_ message: String, status text: String = "", hints failureHints: [(String, String)] = [("Close", "esc")],
              color: NSColor = .secondaryLabelColor) {
        asked = nil
        // An agent's note may come in Markdown.
        setBody(Self.rendered(message, color: color))
        setPhase(.failed, status: text)
        currentHints = failureHints
        layout()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
        // Whatever shows next without `show` (an agent's card) is SI's.
        setSymbol("sparkles")
    }

    func applyGlassStyle(_ style: NSGlassEffectView.Style) {
        glass.style = style
    }

    // MARK: - Content

    private func setSymbol(_ symbol: String) {
        guard symbol != shownSymbol else { return }
        shownSymbol = symbol
        icon.image = Theme.symbol(symbol, pointSize: 14, weight: .semibold)
    }

    private func setPhase(_ phase: Phase, status text: String) {
        self.phase = phase
        // The card takes clicks only while its options can be clicked; it
        // never becomes key, so the app keeps its selection and focus.
        let clickable = phase == .asking && asked?.question.options.isEmpty == false
        if panel.ignoresMouseEvents == clickable { panel.ignoresMouseEvents = !clickable }
        status.stringValue = text
        spinner.isHidden = phase != .streaming
        if phase == .streaming { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        if phase == .streaming { currentHints = [("Cancel", "esc")] }
    }

    private func setBody(_ text: NSAttributedString) {
        dropContent()
        body.textStorage?.setAttributedString(text)
    }

    /// A purpose-made view in place of the text (a contact's card), with
    /// its keys. Gone with the next text, question or card.
    func showContent(_ view: CardContent, status text: String = "", hints customHints: [(String, String)]) {
        asked = nil
        if custom !== view {
            dropContent()
            custom = view
            content.addSubview(view)
        }
        setPhase(.done, status: text)
        currentHints = customHints
        layout()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Self-test hook: the purpose-made view shown, if any.
    var shownContent: NSView? { custom }

    private func dropContent() {
        custom?.removeFromSuperview()
        custom = nil
    }

    private static let bodyFont = NSFont.systemFont(ofSize: 14)

    /// An answer, its Markdown styled.
    private static func rendered(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        CardMarkdown.render(text, font: bodyFont, color: color)
    }

    /// Self-test hook: the body as shown, with its styles.
    var shownBody: NSAttributedString { body.textStorage.map { NSAttributedString(attributedString: $0) } ?? NSAttributedString() }

    private static func plain(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: bodyFont, .foregroundColor: color])
    }

    /// Insertions on a soft accent wash, deletions struck through. A
    /// translation shares almost nothing with its original: shown plainly
    /// (letter-level likeness under 0.75, see `TextDiffTests`).
    private static func highlighted(from original: String, to result: String) -> NSAttributedString {
        guard let likeness = TextDiff.characterSimilarity(original, result), likeness >= 0.75,
              let segments = TextDiff.segments(from: original, to: result)
        else { return plain(result) }
        let text = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            switch segment.kind {
            case .same:
                text.append(plain(segment.text))
            case .inserted:
                text.append(NSAttributedString(string: segment.text, attributes: [
                    .font: bodyFont,
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28)
                ]))
            case .deleted:
                guard !segment.text.allSatisfy(\.isWhitespace) else { continue }
                // l → L: the highlighted capital says it all.
                if index + 1 < segments.count, segments[index + 1].kind == .inserted,
                   segments[index + 1].text.lowercased() == segment.text.lowercased() {
                    continue
                }
                text.append(NSAttributedString(string: segment.text, attributes: [
                    .font: bodyFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.systemRed.withAlphaComponent(0.7)
                ]))
                // A whole word replaced (~~cat~~ dog) gets a thin space so the
                // two do not read as one; letters inside a word (mang~~er~~é)
                // do not.
                if Self.replacesWholeWord(segments, at: index) {
                    text.append(plain("\u{2009}"))
                }
            }
        }
        return text
    }

    /// A deletion followed by an insertion, with no letters glued on either
    /// side.
    private static func replacesWholeWord(_ segments: [TextDiff.Segment], at index: Int) -> Bool {
        guard index + 1 < segments.count, segments[index + 1].kind == .inserted else { return false }
        let before = index > 0 ? segments[index - 1].text.last : nil
        let after = index + 2 < segments.count ? segments[index + 2].text.first : nil
        let isLetter = { (character: Character?) in character.map { $0.isLetter || $0.isNumber } ?? false }
        return !isLetter(before) && !isLetter(after)
    }

    // MARK: - Layout

    private func layout() {
        let textWidth = width - 2 * Layout.padding
        let bodyHeight: CGFloat
        if let asked {
            bodyHeight = questionView.update(question: asked.question, selected: asked.selected, typed: asked.typed, context: asked.context,
                                             width: textWidth)
        } else if let custom {
            bodyHeight = min(maxBodyHeight, max(Layout.minBodyHeight, custom.height(forWidth: textWidth)))
        } else {
            body.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
            body.layoutManager?.ensureLayout(for: body.textContainer!)
            let used = body.layoutManager?.usedRect(for: body.textContainer!).height ?? 0
            bodyHeight = min(maxBodyHeight, max(Layout.minBodyHeight, ceil(used) + 2))
        }
        scrollView.isHidden = asked != nil || custom != nil
        questionView.isHidden = asked == nil
        let height = Layout.padding * 2 + Layout.headerHeight + Layout.gap + bodyHeight + Layout.gap + Layout.footerHeight

        // Top-down inside the card (AppKit origin is bottom-left).
        let headerY = height - Layout.padding - Layout.headerHeight
        icon.frame = NSRect(x: Layout.padding, y: headerY + 2, width: 18, height: 18)
        spinner.frame = NSRect(x: width - Layout.padding - 16, y: headerY + 3, width: 16, height: 16)
        let statusRight = spinner.isHidden ? width - Layout.padding : spinner.frame.minX - 6
        // The status keeps its full width ("Copied · Claude API · Sonnet ·
        // 1.2 s"); the title takes the rest.
        // A few points more than measured: the label's cell clipped the last letter.
        let statusWidth = min(ceil(status.intrinsicContentSize.width) + 4, 240)
        status.frame = NSRect(x: statusRight - statusWidth, y: headerY + 3, width: statusWidth, height: 16)
        let titleX = Layout.padding + 26
        title.frame = NSRect(x: titleX, y: headerY + 2, width: max(80, status.frame.minX - 12 - titleX), height: 18)
        scrollView.frame = NSRect(x: Layout.padding, y: Layout.padding + Layout.footerHeight + Layout.gap, width: textWidth, height: bodyHeight)
        body.frame.size.width = textWidth
        questionView.frame = scrollView.frame
        custom?.frame = scrollView.frame
        hints.frame = NSRect(x: Layout.padding, y: Layout.padding, width: textWidth, height: Layout.footerHeight)
        hints.setHints(currentHints)

        let margin = Theme.glassMargin
        glass.frame = NSRect(x: margin, y: margin, width: width, height: height)
        let panelFrame = frame(height: height).insetBy(dx: -margin, dy: -margin)
        if panel.frame != panelFrame { panel.setFrame(panelFrame, display: true) }
    }

    /// Card frame in screen coordinates: pinned on the first layout of a
    /// show, then only its height changes.
    private func frame(height: CGFloat) -> NSRect {
        let pin = self.pin ?? makePin()
        self.pin = pin
        return NSRect(x: pin.x, y: pin.growsDown ? pin.edge - height : pin.edge, width: width, height: height)
    }

    /// From the launcher: its top-left. Under a selection: below it when the
    /// tallest card fits there, else above it; on the selection's screen.
    private func makePin() -> (x: CGFloat, edge: CGFloat, growsDown: Bool) {
        let tallest = Layout.padding * 2 + Layout.headerHeight + Layout.gap * 2 + maxBodyHeight + Layout.footerHeight
        switch placement {
        case .launcher(let frame):
            return (frame.minX, frame.maxY, true)
        case .selection(let anchor):
            // A caret is a rect without width: nothing intersects it.
            let screen = NSScreen.screens.first { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            let x = min(max(anchor.minX, visible.minX + 8), visible.maxX - width - 8)
            let below = anchor.minY - Layout.distanceFromSelection
            if below - tallest >= visible.minY + 8 {
                return (x, min(below, visible.maxY - 8), true)
            }
            let above = min(anchor.maxY + Layout.distanceFromSelection, visible.maxY - 8 - tallest)
            return (x, max(above, visible.minY + 8), false)
        }
    }

    private func buildViews() {
        icon.image = Theme.symbol("sparkles", pointSize: 14, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        content.addSubview(icon)

        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        content.addSubview(title)

        status.font = Theme.Font.hint
        status.textColor = .secondaryLabelColor
        status.alignment = .right
        content.addSubview(status)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        content.addSubview(spinner)

        body.isEditable = false
        body.isSelectable = false
        body.drawsBackground = false
        body.textContainerInset = .zero
        body.textContainer?.lineFragmentPadding = 0
        body.textContainer?.widthTracksTextView = true
        scrollView.documentView = body
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        body.frame = NSRect(x: 0, y: 0, width: Layout.width - 2 * Layout.padding, height: 10)
        body.autoresizingMask = [.width]
        body.isVerticallyResizable = true
        content.addSubview(scrollView)
        questionView.isHidden = true
        content.addSubview(questionView)

        content.addSubview(hints)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass draws its own edge and depth; `glassMargin` leaves room
        // for its shadow.
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let root = NSView()
        root.addSubview(glass)
        panel.contentView = root
        return panel
    }
}
