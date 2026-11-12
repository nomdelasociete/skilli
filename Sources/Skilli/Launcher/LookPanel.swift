import AppKit
import QuickLookUI

/// A copy seen large over the launcher (⌘Y in the history): a picture, a
/// PDF's pages, a file as Quick Look draws it. The launcher keeps the
/// keys: the arrows show the next copy, esc or ⌘Y close it. A window of
/// the launcher's, never key, so nothing typed is lost and the launcher
/// stays open under it.
final class LookPanel: NSPanel {
    private let box = NSVisualEffectView()
    private let name = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "Close esc · Next copy ↑↓")
    private let preview: QLPreviewView?
    /// The file shown; nil when closed.
    private(set) var file: URL?

    private static let inset: CGFloat = 12
    private static let bar: CGFloat = 34

    init() {
        preview = QLPreviewView(frame: .zero, style: .normal)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        box.material = .popover
        box.blendingMode = .behindWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 14
        box.layer?.cornerCurve = .continuous
        box.layer?.masksToBounds = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.keycapStroke.cgColor
        contentView = box
        name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingMiddle
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .right
        box.addSubview(name)
        box.addSubview(hint)
        if let preview {
            preview.shouldCloseWithWindow = false
            preview.autostarts = true
            box.addSubview(preview)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Where it shows on a screen: all of it but a margin, up to
    /// 1,800 by 1,200 on a large one (a picture wants the room).
    static func frame(on visible: NSRect) -> NSRect {
        let width = min(visible.width - 48, 1_800)
        let height = min(visible.height - 48, 1_200)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height).integral
    }

    /// Shows `file` under `name`, over `parent`, on its screen.
    func show(_ file: URL, named name: String, over parent: NSWindow) {
        self.file = file
        self.name.stringValue = name
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        setFrame(Self.frame(on: visible), display: false)
        layout()
        preview?.previewItem = file as NSURL
        if self.parent == nil { parent.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    func close(from parent: NSWindow) {
        guard file != nil else { return }
        file = nil
        preview?.previewItem = nil
        parent.removeChildWindow(self)
        orderOut(nil)
    }

    private func layout() {
        let bounds = NSRect(origin: .zero, size: frame.size)
        box.frame = bounds
        let top = bounds.height - Self.bar
        let hintWidth: CGFloat = 220
        name.frame = NSRect(x: Self.inset + 4, y: top + 8, width: bounds.width - hintWidth - Self.inset * 3, height: 18)
        hint.frame = NSRect(x: bounds.width - hintWidth - Self.inset - 4, y: top + 8, width: hintWidth, height: 18)
        preview?.frame = NSRect(x: Self.inset, y: Self.inset, width: bounds.width - Self.inset * 2, height: top - Self.inset)
    }
}
