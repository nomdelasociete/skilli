import AppKit
import SkilliCore

/// Transcribe Again (docs/meeting-recorder-views.md, phase 4): a panel
/// under its button in a recording's window, the language and the engine
/// used as picked. The languages listed are the engine's; an engine that
/// cannot be used says why and Transcribe dims. When the lines were
/// changed by hand, it says the changes are replaced: the panel is the
/// question (rule 1: overwriting asks first).
@MainActor
final class TranscribeAgainPanel: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let content = TranscribeAgainView()
    private let engines: [(engine: TranscriptEngine, unusable: String?)]
    private let languages: (TranscriptEngine) async -> [(id: String, name: String)]
    private var language: String
    private var engine: TranscriptEngine
    private var languageIDs: [String] = []
    /// The engine's languages are read (none: it has none here).
    private var loaded = false
    private var loading: Task<Void, Never>?
    var onTranscribe: ((String, TranscriptEngine) -> Void)?
    var onClose: (() -> Void)?

    init(language: String, engine: TranscriptEngine, engines: [(engine: TranscriptEngine, unusable: String?)], edited: Bool,
         languages: @escaping (TranscriptEngine) async -> [(id: String, name: String)]) {
        self.language = language
        self.engine = engines.contains { $0.engine == engine } ? engine : engines.first?.engine ?? .macOS
        self.engines = engines
        self.languages = languages
        super.init()
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        content.engineMenu.removeAllItems()
        for (index, each) in engines.enumerated() {
            content.engineMenu.addItem(withTitle: each.engine.title)
            content.engineMenu.item(at: index)?.representedObject = each.engine.rawValue
        }
        content.engineMenu.selectItem(at: engines.firstIndex { $0.engine == self.engine } ?? 0)
        content.engineMenu.target = self
        content.engineMenu.action = #selector(enginePicked)
        content.languageMenu.target = self
        content.languageMenu.action = #selector(languagePicked)
        content.edited = edited
        content.cancel.target = self
        content.cancel.action = #selector(cancelPressed)
        content.transcribe.target = self
        content.transcribe.action = #selector(transcribePressed)
        loadLanguages()
    }

    var isShown: Bool { popover.isShown }
    /// Self-test hooks.
    var shownLanguages: [String] { content.languageMenu.itemTitles }
    var shownEngines: [String] { content.engineMenu.itemTitles }
    var shownNote: String { content.noteText ?? "" }
    var canTranscribe: Bool { content.transcribe.isEnabled }
    var window: NSWindow? { content.window }
    /// The engine's languages are read.
    var isLoaded: Bool { loaded }

    func show(relativeTo button: NSView) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeFirstResponder(content.languageMenu)
    }

    func close() {
        loading?.cancel()
        popover.close()
    }

    #if SKILLI_SELFTEST
    /// Self-test: a language and an engine picked, as the menus would.
    func pick(language id: String?, engine: TranscriptEngine?) async {
        if let engine, let index = engines.firstIndex(where: { $0.engine == engine }) {
            content.engineMenu.selectItem(at: index)
            enginePicked()
            await loading?.value
        }
        if let id, let index = languageIDs.firstIndex(of: id) {
            content.languageMenu.selectItem(at: index)
            languagePicked()
        }
    }

    func press() {
        transcribePressed()
    }
    #endif

    /// The engine's languages, the recording's selected when it has it.
    private func loadLanguages() {
        loading?.cancel()
        let engine = engine
        content.languageMenu.isEnabled = false
        loaded = false
        loading = Task { [weak self] in
            guard let self else { return }
            let languages = await self.languages(engine)
            guard !Task.isCancelled, self.engine == engine else { return }
            self.languageIDs = languages.map(\.id)
            self.content.languageMenu.removeAllItems()
            self.content.languageMenu.addItems(withTitles: languages.map(\.name))
            let code = Locale(identifier: self.language).language.languageCode?.identifier
            let index = self.languageIDs.firstIndex(of: self.language)
                ?? self.languageIDs.firstIndex { Locale(identifier: $0).language.languageCode?.identifier == code } ?? 0
            if !languages.isEmpty {
                self.content.languageMenu.selectItem(at: index)
                self.language = self.languageIDs[index]
            }
            self.content.languageMenu.isEnabled = !languages.isEmpty
            self.loaded = true
            self.updateNote()
        }
        updateNote()
    }

    private func updateNote() {
        let unusable = engines.first { $0.engine == engine }?.unusable
        content.unusable = unusable ?? (loaded && languageIDs.isEmpty ? "\(engine.title) has no language on this Mac." : nil)
        content.transcribe.isEnabled = content.unusable == nil && !languageIDs.isEmpty
        popover.contentSize = NSSize(width: TranscribeAgainView.width, height: content.preferredHeight)
    }

    @objc private func enginePicked() {
        let index = content.engineMenu.indexOfSelectedItem
        guard engines.indices.contains(index) else { return }
        engine = engines[index].engine
        loadLanguages()
    }

    @objc private func languagePicked() {
        let index = content.languageMenu.indexOfSelectedItem
        guard languageIDs.indices.contains(index) else { return }
        language = languageIDs[index]
    }

    @objc private func cancelPressed() {
        close()
    }

    @objc private func transcribePressed() {
        guard content.transcribe.isEnabled else { return }
        let (language, engine) = (language, engine)
        close()
        onTranscribe?(language, engine)
    }

    func popoverDidClose(_ notification: Notification) {
        loading?.cancel()
        onClose?()
    }
}

/// The panel's content: a title, the two menus, what is replaced or why
/// it cannot be, Cancel esc and Transcribe ↩.
private final class TranscribeAgainView: NSView {
    private let title = NSTextField(labelWithString: "Transcribe again")
    private let languageLabel = NSTextField(labelWithString: "Language")
    private let engineLabel = NSTextField(labelWithString: "Engine")
    let languageMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    let engineMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    let note = NSTextField(wrappingLabelWithString: "")
    let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    let transcribe = NSButton(title: "Transcribe", target: nil, action: nil)
    var edited = false {
        didSet { needsLayout = true }
    }
    /// Why the engine picked cannot be used; nil: it can.
    var unusable: String? {
        didSet { needsLayout = true }
    }
    static let width: CGFloat = 320

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 170))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        for label in [languageLabel, engineLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
        }
        note.font = .systemFont(ofSize: 12)
        cancel.bezelStyle = .push
        cancel.keyEquivalent = "\u{1b}"
        transcribe.bezelStyle = .push
        transcribe.keyEquivalent = "\r"
        for subview in [title, languageLabel, languageMenu, engineLabel, engineMenu, note, cancel, transcribe] as [NSView] {
            addSubview(subview)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Its height for what it says now.
    var preferredHeight: CGFloat {
        let inner = Self.width - 32
        var height: CGFloat = 14 + 28 + 60 + 4 + 32 + 14
        if let text = noteText {
            height += ceil((text as NSString).boundingRect(with: NSSize(width: inner, height: .greatestFiniteMagnitude),
                                                           options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: note.font!]).height) + 12
        }
        return height
    }

    fileprivate var noteText: String? {
        unusable ?? (edited ? "Your changes to the lines are replaced." : nil)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 16
        let inner = bounds.width - inset * 2
        var y: CGFloat = 14
        title.frame = NSRect(x: inset, y: y, width: inner, height: 17)
        y += 28
        for (label, menu) in [(languageLabel, languageMenu), (engineLabel, engineMenu)] {
            label.frame = NSRect(x: inset, y: y + 3, width: 70, height: 17)
            menu.sizeToFit()
            menu.frame = NSRect(x: inset + 74, y: y - 1, width: inner - 74, height: menu.frame.height)
            y += 30
        }
        note.isHidden = noteText == nil
        if let text = noteText {
            note.stringValue = text
            note.textColor = unusable == nil ? .secondaryLabelColor : .systemOrange
            let height = ceil((text as NSString).boundingRect(with: NSSize(width: inner, height: .greatestFiniteMagnitude),
                                                              options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: note.font!]).height)
            note.frame = NSRect(x: inset, y: y + 2, width: inner, height: height + 2)
            y += height + 12
        }
        y += 4
        transcribe.sizeToFit()
        cancel.sizeToFit()
        transcribe.frame.origin = NSPoint(x: bounds.width - inset - transcribe.frame.width, y: y)
        cancel.frame.origin = NSPoint(x: transcribe.frame.minX - 8 - cancel.frame.width, y: y)
    }
}
