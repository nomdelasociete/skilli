import AppKit
import SkilliCore

/// A command's question inside the AI card: the question, then its options
/// as numbered chips (the selected one filled with the accent), or a line
/// that shows what the user types. Draws only; `AIActionController` reads
/// the keys through the event tap.
@MainActor
final class QuestionView: NSView {
    private enum Layout {
        static let questionToAnswer: CGFloat = 10
        static let chipHeight: CGFloat = 28
        static let chipSpacing: CGFloat = 8
        static let chipPadding: CGFloat = 10
        static let numberToLabel: CGFloat = 7
        static let fieldHeight: CGFloat = 30
        static let contextToQuestion: CGFloat = 12
    }

    /// What the question follows on from (the answer being followed up),
    /// dimmed, a few lines at most.
    private let contextLabel = NSTextField(wrappingLabelWithString: "")
    private let questionLabel = NSTextField(wrappingLabelWithString: "")
    private let chips = NSView()
    private let field = AnswerField()
    /// An option clicked (its index): answered as its number key would.
    var onPick: ((Int) -> Void)?

    /// Self-test hook: where option `index` is on screen (AppKit, bottom-left).
    func optionFrameOnScreen(_ index: Int) -> NSRect? {
        guard !chips.isHidden, chips.subviews.indices.contains(index), let window else { return nil }
        let chip = chips.subviews[index]
        return window.convertToScreen(chip.convert(chip.bounds, to: nil))
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        questionLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        questionLabel.textColor = .labelColor
        questionLabel.isSelectable = false
        contextLabel.font = NSFont.systemFont(ofSize: 13)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.isSelectable = false
        contextLabel.maximumNumberOfLines = 4
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.cell?.truncatesLastVisibleLine = true
        addSubview(contextLabel)
        addSubview(questionLabel)
        addSubview(chips)
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Lays out for `width` and returns the height used.
    @discardableResult
    func update(question: PromptQuestion, selected: Int, typed: String, context: String? = nil, width: CGFloat) -> CGFloat {
        var top: CGFloat = 0
        if let context, !context.isEmpty {
            contextLabel.isHidden = false
            contextLabel.attributedStringValue = CardMarkdown.render(context, font: NSFont.systemFont(ofSize: 13), color: .secondaryLabelColor)
            contextLabel.preferredMaxLayoutWidth = width
            let height = ceil(contextLabel.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height)
            contextLabel.frame = NSRect(x: 0, y: 0, width: width, height: height)
            top = height + Layout.contextToQuestion
        } else {
            contextLabel.isHidden = true
        }
        questionLabel.stringValue = question.question
        questionLabel.preferredMaxLayoutWidth = width
        let questionHeight = ceil(questionLabel.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height)
        questionLabel.frame = NSRect(x: 0, y: top, width: width, height: questionHeight)
        let answerY = top + questionHeight + Layout.questionToAnswer

        if question.options.isEmpty {
            chips.isHidden = true
            field.isHidden = false
            field.frame = NSRect(x: 0, y: answerY, width: width, height: Layout.fieldHeight)
            field.show(typed: typed, placeholder: question.defaultValue.map { "\($0) (default)" } ?? "Type your answer")
            return answerY + Layout.fieldHeight
        }

        field.isHidden = true
        chips.isHidden = false
        chips.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for (index, option) in question.options.enumerated() {
            let chip = Chip(number: index < 9 ? "\(index + 1)" : nil, label: option, isSelected: index == selected)
            chip.onClick = { [weak self] in self?.onPick?(index) }
            let chipWidth = min(chip.fittingWidth, width)
            if x > 0, x + chipWidth > width {
                x = 0
                y += Layout.chipHeight + Layout.chipSpacing
            }
            chip.frame = NSRect(x: x, y: y, width: chipWidth, height: Layout.chipHeight)
            chips.addSubview(chip)
            x += chipWidth + Layout.chipSpacing
        }
        let chipsHeight = y + Layout.chipHeight
        chips.frame = NSRect(x: 0, y: answerY, width: width, height: chipsHeight)
        return answerY + chipsHeight
    }

    /// A key typed: only the answer line, nothing measured again.
    func showTyped(_ typed: String) {
        field.showTyped(typed)
    }

    /// Self-test hook: where the typed text ends and where the caret is.
    var answerCaret: (textEnd: CGFloat, caret: CGFloat) { (field.textEnd, field.caretX) }
    /// Self-test hook: the caret on screen (AppKit global coordinates).
    var answerCaretOnScreen: NSRect? { field.caretOnScreen }

    // MARK: - Pieces

    /// "1  Friendly" on a soft capsule; filled with the accent when selected.
    private final class Chip: NSView {
        var onClick: (() -> Void)?
        private let isSelected: Bool
        private let numberLabel: NSTextField?
        private let label: NSTextField

        override var isFlipped: Bool { true }

        init(number: String?, label text: String, isSelected: Bool) {
            self.isSelected = isSelected
            numberLabel = number.map { NSTextField(labelWithString: $0) }
            label = NSTextField(labelWithString: text)
            super.init(frame: .zero)
            if let numberLabel {
                numberLabel.font = Theme.Font.keycap
                numberLabel.textColor = isSelected ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
                numberLabel.sizeToFit()
                addSubview(numberLabel)
            }
            label.font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
            label.textColor = isSelected ? .white : .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.sizeToFit()
            addSubview(label)
            wantsLayer = true
            layer?.cornerRadius = Layout.chipHeight / 2
            applyColors()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        // The card never becomes key: the first click is the click, and
        // its labels are the chip's.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            frame.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        var fittingWidth: CGFloat {
            let number = numberLabel.map { ceil($0.frame.width) + Layout.numberToLabel } ?? 0
            return ceil(Layout.chipPadding * 2 + number + label.frame.width)
        }

        override func layout() {
            super.layout()
            var x = Layout.chipPadding
            if let numberLabel {
                numberLabel.frame.origin = NSPoint(x: x, y: (bounds.height - numberLabel.frame.height) / 2)
                x += numberLabel.frame.width + Layout.numberToLabel
            }
            label.frame = NSRect(x: x, y: (bounds.height - label.frame.height) / 2,
                                 width: max(0, bounds.width - x - Layout.chipPadding), height: label.frame.height)
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyColors()
        }

        private func applyColors() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.07)).cgColor
            }
        }
    }

    /// One line with what was typed and the system's caret right after it;
    /// the default as placeholder. A long answer scrolls left, as in a text
    /// field. Drawn here (no label padding): typing measures one string.
    private final class AnswerField: NSView {
        private static let inset: CGFloat = 10
        private static let font = NSFont.systemFont(ofSize: 14)
        private let caret = NSTextInsertionIndicator()
        private var typed = ""
        private var placeholder = ""
        /// Where the text is drawn, and where it ends (the caret's place).
        private var textOrigin = NSPoint.zero
        private(set) var textEnd: CGFloat = 0

        override var isFlipped: Bool { true }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 8
            layer?.borderWidth = 1
            // No dictation glow: skil.li listens on its own.
            caret.automaticModeOptions = []
            addSubview(caret)
            applyColors()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        var caretX: CGFloat { caret.frame.minX }
        var caretOnScreen: NSRect? { caret.window?.convertToScreen(caret.convert(caret.bounds, to: nil)) }

        func show(typed: String, placeholder: String) {
            self.placeholder = placeholder
            showTyped(typed)
        }

        func showTyped(_ typed: String) {
            self.typed = typed
            let shown = typed.isEmpty ? placeholder : typed
            let size = (shown as NSString).size(withAttributes: [.font: Self.font])
            let available = bounds.width - 2 * Self.inset
            // The end of what was typed stays in view.
            let shift = typed.isEmpty ? 0 : max(0, ceil(size.width) - available)
            textOrigin = NSPoint(x: Self.inset - shift, y: (bounds.height - ceil(size.height)) / 2)
            textEnd = typed.isEmpty ? Self.inset : textOrigin.x + size.width
            let height = ceil(Self.font.ascender - Self.font.descender) + 2
            caret.frame = NSRect(x: round(textEnd), y: (bounds.height - height) / 2, width: 2, height: height)
            // Typing keeps the caret solid; it blinks again on its own.
            caret.displayMode = .visible
            caret.displayMode = .automatic
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            NSBezierPath(rect: bounds.insetBy(dx: Self.inset - 2, dy: 0)).setClip()
            let shown = typed.isEmpty ? placeholder : typed
            (shown as NSString).draw(at: textOrigin, withAttributes: [
                .font: Self.font,
                .foregroundColor: typed.isEmpty ? NSColor.tertiaryLabelColor : NSColor.labelColor
            ])
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyColors()
        }

        private func applyColors() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
                layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            }
        }
    }
}
