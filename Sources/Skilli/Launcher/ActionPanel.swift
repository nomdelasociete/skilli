import AppKit
import Carbon.HIToolbox

/// One thing ⌘K can do with the launcher's selected row.
struct LauncherAction {
    /// The keys an action can have. Each means the same everywhere: ↩ the
    /// row's own action, ⌘↩ and ⇧↩ its next two, ⌘C copies its main value,
    /// ⇧⌘C its second, ⌘⌫ removes it.
    enum Key: Equatable {
        case open, openSecond, openThird, copy, copySecond, delete

        var label: String {
            switch self {
            case .open: "↩"
            case .openSecond: "⌘↩"
            case .openThird: "⇧↩"
            case .copy: "⌘C"
            case .copySecond: "⇧⌘C"
            case .delete: "⌘⌫"
            }
        }

        /// The key `event` presses, when it is one of these. C by its
        /// character, so any keyboard layout has it where it prints it.
        init?(_ event: NSEvent) {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let code = Int(event.keyCode)
            let isReturn = code == kVK_Return || code == kVK_ANSI_KeypadEnter
            switch flags {
            case [] where isReturn: self = .open
            case .command where isReturn: self = .openSecond
            case .shift where isReturn: self = .openThird
            case .command where code == kVK_Delete: self = .delete
            case .command where event.charactersIgnoringModifiers?.lowercased() == "c": self = .copy
            case [.command, .shift] where event.charactersIgnoringModifiers?.lowercased() == "c": self = .copySecond
            default: return nil
            }
        }
    }

    /// Doing, copying, removing: a hairline between them in the list.
    enum Group {
        case act, copy, remove
    }

    let title: String
    /// An SF Symbol.
    let symbol: String
    var key: Key?
    var group = Group.act
    /// The list stays open: the action asks something in it (an alias).
    var keepsOpen = false
    /// Copies the row's `skilli://` link: never what ⌘C copies.
    var isLink = false
    let run: @MainActor () -> Void

    /// The action for `key` in `list`; ⌘C falls back to the first copy
    /// (⌘↩ where that copies: clipboard, snippets, the calculator, links),
    /// never the skil.li link.
    static func find(_ key: Key, in list: [LauncherAction]) -> LauncherAction? {
        list.first { $0.key == key } ?? (key == .copy ? list.first { $0.group == .copy && !$0.isLink } : nil)
    }
}

/// ⌘K's list over the launcher's results, bottom right: the selected row's
/// actions, each with its key. Built from what the row holds, nothing
/// fetched, so it opens at once. The launcher routes the keys to it (typing
/// filters, arrows move, ↩ runs); a click on a row runs it, a click beside
/// the list closes it.
final class ActionPanelView: NSView {
    var onRun: ((LauncherAction) -> Void)?
    var onDismiss: (() -> Void)?
    /// Every action of the row, unfiltered.
    private(set) var actions: [LauncherAction] = []
    /// What the filter keeps, in the list's order.
    private(set) var shown: [LauncherAction] = []
    private(set) var filter = ""
    /// One line in place of the filter (a key that does nothing here),
    /// until the next key.
    private(set) var note: String?
    private(set) var selected = 0
    private var first = 0
    private let box = NSVisualEffectView()
    private let header = NSTextField(labelWithString: "")
    private let field = NSTextField(labelWithString: "")
    private let fieldLine = HairlineView()
    private var rows: [NSView] = []
    /// The list's bottom edge in this view: just above the footer.
    var bottom: CGFloat = 50
    /// In a card (a contact's): the list takes the card's width, from its
    /// bottom; over the launcher, 330 pt at the right.
    var fillsWidth = false
    /// Rows shown at once; the rest scroll with the selection.
    var maxRows = 10

    private var listWidth: CGFloat { fillsWidth ? bounds.width : 330 }
    private static let rowHeight: CGFloat = 30
    private static let headerHeight: CGFloat = 30
    private static let fieldHeight: CGFloat = 36
    private static let gap: CGFloat = 9

    override init(frame: NSRect) {
        super.init(frame: frame)
        box.material = .popover
        box.blendingMode = .withinWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 14
        box.layer?.masksToBounds = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.keycapStroke.cgColor
        addSubview(box)
        header.font = Theme.Font.sectionHeader
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingTail
        box.addSubview(header)
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingHead
        box.addSubview(fieldLine)
        box.addSubview(field)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Actions")
    }

    required init?(coder: NSCoder) { nil }

    /// Typing a value instead of choosing ("Alias for Emoji"): ↩ submits.
    private var prompt: (title: String, submit: (String) -> Void)?
    var isPrompting: Bool { prompt != nil }

    func ask(_ title: String, initial: String, submit: @escaping (String) -> Void) {
        prompt = (title, submit)
        header.stringValue = title
        filter = initial
        note = nil
        layoutList()
    }

    /// What a key did not do, and what to do instead, in the list itself
    /// (rule 6: never a bare beep). Gone with the next key.
    func say(_ line: String) {
        note = line
        layoutList()
    }

    /// What was typed, to the prompt.
    func submit() {
        guard let prompt else { return }
        self.prompt = nil
        prompt.submit(filter)
    }

    func show(_ actions: [LauncherAction], for title: String) {
        prompt = nil
        self.actions = actions
        header.stringValue = title
        filter = ""
        note = nil
        apply()
        isHidden = false
    }

    var selectedAction: LauncherAction? { shown.indices.contains(selected) ? shown[selected] : nil }

    func type(_ text: String) {
        filter += text
        note = nil
        if isPrompting { layoutList() } else { apply() }
    }

    func deleteBackward() {
        let said = note != nil
        note = nil
        guard !filter.isEmpty else {
            if said { layoutList() }
            return
        }
        filter.removeLast()
        if isPrompting { layoutList() } else { apply() }
    }

    /// Past an end, round to the other: ↑ on the first action selects the
    /// last. Not while the key is held (`wraps` false on its repeats): it
    /// stops at the end instead of spinning past it.
    func move(by delta: Int, wraps: Bool = true) {
        note = nil
        guard !shown.isEmpty else { return }
        let next = selected + delta
        if wraps, !shown.indices.contains(next) {
            selected = next < 0 ? shown.count - 1 : 0
        } else {
            selected = min(max(next, 0), shown.count - 1)
        }
        layoutList()
    }

    /// Every word typed starts a word of the title: "co ph" keeps "Copy
    /// Phone (mobile)". Accents and case aside.
    private func apply() {
        let words = filter.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(separator: " ")
        shown = words.isEmpty ? actions : actions.filter { action in
            let title = action.title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return words.allSatisfy { word in title.contains { $0.hasPrefix(word) } }
        }
        selected = 0
        first = 0
        layoutList()
    }

    private func layoutList() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        // The selection stays in sight in a long list.
        if selected < first { first = selected }
        if selected >= first + maxRows { first = selected - maxRows + 1 }
        let visible = isPrompting ? [] : Array(shown.indices.dropFirst(first).prefix(maxRows))
        let gaps = zip(visible, visible.dropFirst()).filter { shown[$0].group != shown[$1].group }.count
        let listHeight = visible.isEmpty ? Self.rowHeight : CGFloat(visible.count) * Self.rowHeight + CGFloat(gaps) * Self.gap
        let height = Self.headerHeight + listHeight + 8 + Self.fieldHeight
        box.frame = fillsWidth ? NSRect(x: 0, y: 0, width: listWidth, height: height)
            : NSRect(x: bounds.width - listWidth - 12, y: bottom, width: listWidth, height: height)

        header.frame = NSRect(x: 14, y: height - Self.headerHeight + 7, width: listWidth - 28, height: 16)
        var y = height - Self.headerHeight
        if visible.isEmpty {
            let none = NSTextField(labelWithString: isPrompting ? "Type it, ↩ saves, esc goes back" : "No action matches")
            none.font = .systemFont(ofSize: 13)
            none.textColor = .tertiaryLabelColor
            none.frame = NSRect(x: 14, y: y - Self.rowHeight + 7, width: listWidth - 28, height: 17)
            box.addSubview(none)
            rows.append(none)
        }
        for (position, index) in visible.enumerated() {
            if position > 0, shown[visible[position - 1]].group != shown[index].group {
                let line = HairlineView(frame: NSRect(x: 12, y: y - (Self.gap + 1) / 2, width: listWidth - 24, height: 1))
                box.addSubview(line)
                rows.append(line)
                y -= Self.gap
            }
            y -= Self.rowHeight
            let row = ActionRowView(frame: NSRect(x: 6, y: y, width: listWidth - 12, height: Self.rowHeight),
                                    action: shown[index], selected: index == selected)
            row.onClick = { [weak self] in
                guard let self, self.shown.indices.contains(index) else { return }
                self.onRun?(self.shown[index])
            }
            box.addSubview(row)
            rows.append(row)
        }
        fieldLine.frame = NSRect(x: 0, y: Self.fieldHeight, width: listWidth, height: 1)
        field.frame = NSRect(x: 14, y: (Self.fieldHeight - 17) / 2, width: listWidth - 28, height: 17)
        if let note {
            field.stringValue = note
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = note
            return
        }
        field.lineBreakMode = .byTruncatingHead
        field.toolTip = nil
        field.stringValue = filter.isEmpty ? (isPrompting ? "e, cl, todo…" : "Search actions…") : filter
        field.textColor = filter.isEmpty ? .tertiaryLabelColor : .labelColor
    }

    /// How tall the list is now (a card sizes itself to it).
    var listHeight: CGFloat {
        let visible = isPrompting ? [] : Array(shown.indices.dropFirst(first).prefix(maxRows))
        let gaps = zip(visible, visible.dropFirst()).filter { shown[$0].group != shown[$1].group }.count
        let rows = visible.isEmpty ? Self.rowHeight : CGFloat(visible.count) * Self.rowHeight + CGFloat(gaps) * Self.gap
        return Self.headerHeight + rows + 8 + Self.fieldHeight
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if fillsWidth, changed { layoutList() }
    }

    override func mouseDown(with event: NSEvent) {
        // Beside the list: back to the results.
        if !box.frame.contains(convert(event.locationInWindow, from: nil)) { onDismiss?() }
    }
}

/// A row of the actions list: its symbol, its title, its key on the right;
/// red when it removes something.
private final class ActionRowView: NSView {
    var onClick: (() -> Void)?
    private let isSelected: Bool

    init(frame: NSRect, action: LauncherAction, selected: Bool) {
        isSelected = selected
        super.init(frame: frame)
        let tint: NSColor = action.group == .remove ? .systemRed : .secondaryLabelColor
        let icon = NSImageView(frame: NSRect(x: 8, y: (frame.height - 18) / 2, width: 18, height: 18))
        icon.image = Theme.symbol(action.symbol, pointSize: 13, weight: .medium)
        icon.contentTintColor = tint
        addSubview(icon)
        var titleEnd = frame.width - 8
        if let key = action.key {
            let cap = KeycapView(key.label)
            cap.frame.origin = NSPoint(x: frame.width - 8 - cap.frame.width, y: (frame.height - cap.frame.height) / 2)
            addSubview(cap)
            titleEnd = cap.frame.minX - 8
        }
        let title = NSTextField(labelWithString: action.title)
        title.font = .systemFont(ofSize: 13, weight: selected ? .medium : .regular)
        title.textColor = action.group == .remove ? .systemRed : .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 34, y: (frame.height - 17) / 2, width: max(0, titleEnd - 34), height: 17)
        addSubview(title)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(action.title)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        Theme.selectionFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// ⌘K's list in a card: as wide as the card, as tall as its rows.
extension ActionPanelView: CardContent {
    func height(forWidth width: CGFloat) -> CGFloat { listHeight }
}
