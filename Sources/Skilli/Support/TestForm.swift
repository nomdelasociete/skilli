import AppKit

/// `Skilli testform <state.json>`: another app for the "do it here"
/// self-test, an AppKit form like any app's: two fields, a checkbox, Save,
/// Delete Account, and an Archive control drawn without Accessibility (found
/// by reading the screen, clicked with the mouse). What it holds is written
/// to `state.json` as it changes; with `edited`, its window holds unsaved
/// work. `Skilli testform <state.json> photos`: a
/// photo with a row of icon-only buttons Accessibility has no words for,
/// so only a picture of the window tells them apart.
@MainActor
enum TestForm {
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == "testform" else { return nil }
        guard arguments.count == 3 || arguments.count == 4 && ["photos", "edited"].contains(arguments[3]) else {
            FileHandle.standardError.write(Data("usage: Skilli testform <state.json> [photos|edited]\n".utf8))
            return 2
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let output = URL(fileURLWithPath: arguments[2])
        // "edited": its window holds unsaved work, as a document's does
        // (Auto Quit's self-test reads it through Accessibility).
        let mode = arguments.count == 4 ? arguments[3] : ""
        let form: AnyObject = mode == "photos" ? Photos(output: output) : Form(output: output, edited: mode == "edited")
        withExtendedLifetime(form) {
            app.run()
        }
        return 0
    }

    /// A photo and its toolbar of icons, none with a word for
    /// Accessibility: an info button first (no goal names it), then star,
    /// printer, magnifying glass, pencil, trash. Each press is counted.
    /// The photos' icons, left to right, by what each press counts.
    static var photoIcons: [String] { Photos.icons.map(\.key) }

    @MainActor
    private final class Photos: NSObject {
        static let icons: [(symbol: String, key: String)] = [("info.circle", "info"), ("star", "starred"), ("printer", "printed"),
                                                             ("magnifyingglass", "zoomed"), ("pencil", "edited"), ("trash", "trashed")]
        private let output: URL
        private let window: NSWindow
        private var counts: [String: Int] = [:]
        private var written = ""
        private var timer: Timer?
        private weak var star: NSButton?

        init(output: URL) {
            self.output = output
            // Large, at the top of the screen: the card that asks for it
            // shows over it (the self-test captures the card on it).
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = NSSize(width: 820, height: min(700, visible.height - 40))
            window = NSWindow(contentRect: NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 30, width: size.width, height: size.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
            super.init()
            window.title = "Vacances"
            let content = NSView(frame: NSRect(origin: .zero, size: size))
            let photo = PhotoView(frame: NSRect(x: 30, y: 110, width: size.width - 60, height: size.height - 170))
            let caption = NSTextField(labelWithString: "Plage de Biarritz, août 2026")
            caption.font = .systemFont(ofSize: 15, weight: .semibold)
            caption.frame = NSRect(x: 30, y: size.height - 45, width: 400, height: 22)
            content.addSubview(photo)
            content.addSubview(caption)
            for (index, icon) in Self.icons.enumerated() {
                counts[icon.key] = 0
                let button = NSButton(image: Self.image(icon.symbol), target: self, action: #selector(pressed(_:)))
                button.bezelStyle = .texturedRounded
                button.frame = NSRect(x: 30 + CGFloat(index) * 58, y: 40, width: 46, height: 38)
                button.identifier = NSUserInterfaceItemIdentifier(icon.key)
                if icon.key == "starred" { star = button }
                // No words for Accessibility: no title, no description, no help.
                button.setAccessibilityLabel(nil)
                button.toolTip = nil
                content.addSubview(button)
            }
            window.contentView = content
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.write() }
            }
            write()
        }

        /// The symbol drawn into a plain image: no name, no description.
        private static func image(_ symbol: String) -> NSImage {
            let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            let source = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            let size = NSSize(width: 24, height: 24)
            let image = NSImage(size: size, flipped: false) { rect in
                guard let source else { return false }
                let fitted = source.size.width > 0 ? source.size : rect.size
                let scale = min(rect.width / fitted.width, rect.height / fitted.height, 1)
                let drawn = NSSize(width: fitted.width * scale, height: fitted.height * scale)
                source.draw(in: NSRect(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
                return true
            }
            // Tinted by the button, light or dark, as an app's icons are.
            image.isTemplate = true
            return image
        }

        @objc private func pressed(_ sender: NSButton) {
            guard let key = sender.identifier?.rawValue else { return }
            counts[key, default: 0] += 1
            // A favorite shows: the star fills (the self-test's "after").
            if key == "starred" { sender.image = Self.image("star.fill") }
        }

        private func write() {
            // An "unstar" file beside the state: not a favorite any more (a
            // run through Ask starts from a photo that is not one).
            let unstar = output.deletingLastPathComponent().appendingPathComponent("unstar")
            if FileManager.default.fileExists(atPath: unstar.path) {
                try? FileManager.default.removeItem(at: unstar)
                star?.image = Self.image("star")
            }
            // A "dark" file beside the state: the self-test's dark captures.
            let dark = FileManager.default.fileExists(atPath: output.deletingLastPathComponent().appendingPathComponent("dark").path)
            let wanted: NSAppearance.Name = dark ? .darkAqua : .aqua
            if NSApp.appearance?.name != wanted { NSApp.appearance = NSAppearance(named: wanted) }
            var state: [String: Any] = counts
            state["pid"] = Int(getpid())
            guard let data = try? JSONSerialization.data(withJSONObject: state, options: .sortedKeys),
                  let text = String(data: data, encoding: .utf8), text != written else { return }
            written = text
            try? data.write(to: output, options: .atomic)
        }
    }

    /// A beach, drawn: sky, sea, sand, sun. Not an Accessibility element.
    private final class PhotoView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let clip = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
            clip.addClip()
            NSGradient(starting: NSColor(calibratedRed: 0.55, green: 0.78, blue: 0.95, alpha: 1),
                       ending: NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.7, alpha: 1))?.draw(in: bounds, angle: -90)
            NSColor(calibratedRed: 0.1, green: 0.45, blue: 0.7, alpha: 1).setFill()
            NSRect(x: 0, y: bounds.height * 0.25, width: bounds.width, height: bounds.height * 0.2).fill()
            NSColor(calibratedRed: 0.93, green: 0.82, blue: 0.6, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.25).fill()
            NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.width * 0.75, y: bounds.height * 0.65, width: 70, height: 70)).fill()
        }

        override func isAccessibilityElement() -> Bool { false }
    }

    @MainActor
    private final class Form: NSObject {
        private let output: URL
        private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380), styleMask: [.titled], backing: .buffered, defer: false)
        private let name = NSTextField()
        private let email = NSTextField()
        private let siret = NSTextField()
        private let iban = NSTextField()
        private let subscribe = NSButton(checkboxWithTitle: "Subscribe to the newsletter", target: nil, action: nil)
        private var saved = 0
        private var deleted = 0
        private var archived = 0
        private var written = ""
        private var timer: Timer?

        init(output: URL, edited: Bool = false) {
            self.output = output
            super.init()
            // With unsaved work it can be closed, as a document window: its
            // close button holds the dot.
            if edited { window.styleMask.insert(.closable) }
            window.isDocumentEdited = edited
            window.title = "Test Form"
            let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
            name.placeholderString = "Name"
            name.frame = NSRect(x: 30, y: 310, width: 400, height: 24)
            email.placeholderString = "Email"
            email.frame = NSRect(x: 30, y: 270, width: 400, height: 24)
            siret.placeholderString = "SIRET"
            siret.frame = NSRect(x: 30, y: 230, width: 400, height: 24)
            iban.placeholderString = "IBAN"
            iban.frame = NSRect(x: 30, y: 190, width: 400, height: 24)
            subscribe.frame = NSRect(x: 30, y: 150, width: 300, height: 22)
            let save = NSButton(title: "Save", target: self, action: #selector(saveForm))
            save.frame = NSRect(x: 30, y: 100, width: 100, height: 30)
            let delete = NSButton(title: "Delete Account", target: self, action: #selector(deleteAccount))
            delete.frame = NSRect(x: 150, y: 100, width: 150, height: 30)
            let archive = DrawnButton(frame: NSRect(x: 30, y: 30, width: 160, height: 40))
            archive.onClick = { [weak self] in self?.archived += 1 }
            for view in [name, email, siret, iban, subscribe, save, delete, archive] as [NSView] { content.addSubview(view) }
            window.contentView = content
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.write() }
            }
            write()
        }

        @objc private func saveForm() { saved += 1 }

        @objc private func deleteAccount() { deleted += 1 }

        private func write() {
            let state: [String: Any] = ["name": name.stringValue, "email": email.stringValue, "siret": siret.stringValue, "iban": iban.stringValue,
                                        "subscribe": subscribe.state == .on,
                                        "saved": saved, "deleted": deleted, "archived": archived, "pid": Int(getpid())]
            guard let data = try? JSONSerialization.data(withJSONObject: state, options: .sortedKeys),
                  let text = String(data: data, encoding: .utf8), text != written else { return }
            written = text
            try? data.write(to: output, options: .atomic)
        }
    }

    /// A control Accessibility does not see: only its drawn word tells it.
    private final class DrawnButton: NSView {
        var onClick: (() -> Void)?

        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemBlue.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            let text = NSAttributedString(string: "Archive", attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                                                                          .foregroundColor: NSColor.labelColor])
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }

        override func isAccessibilityElement() -> Bool { false }
        override func accessibilityChildren() -> [Any]? { [] }
    }
}
