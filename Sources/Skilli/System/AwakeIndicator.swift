import AppKit
import SkilliCore

/// While the Mac is kept awake: a cup in the menu bar with the time left
/// ("59 min", "1 h 20"), so it is seen to work; its menu says until when
/// and lets the Mac sleep again. Gone when it sleeps as usual.
@MainActor
final class AwakeIndicator: NSObject {
    /// Turn Off Keep Awake, from its menu.
    var allowSleep: (() -> Void)?
    private var item: NSStatusItem?
    private var until: Date?
    private var timer: Timer?

    /// Self-test hook: the time shown beside the cup, "" when it has none,
    /// nil when no cup is shown.
    var shown: String? { item?.button?.title }

    /// The cup shown or gone, as Keep Awake is now.
    func update(awake: Bool, until: Date?) {
        guard awake else {
            timer?.invalidate()
            timer = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            self.until = nil
            return
        }
        self.until = until
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = Self.cup
            item.button?.setAccessibilityLabel("Keeping the Mac awake")
            item.button?.imagePosition = .imageLeading
            self.item = item
        }
        refresh()
        timer?.invalidate()
        timer = nil
        guard until != nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard let item else { return }
        item.button?.title = until.map { " " + AwakeStatus.left(until: $0) } ?? ""
        let menu = NSMenu()
        let said = NSMenuItem(title: until.map { "Keep Awake on until \($0.formatted(date: .omitted, time: .shortened))" }
                                  ?? "Keep Awake on until you turn it off",
                              action: nil, keyEquivalent: "")
        said.isEnabled = false
        menu.addItem(said)
        menu.addItem(.separator())
        let sleep = NSMenuItem(title: AwakeStatus.turnOff, action: #selector(allowSleepNow), keyEquivalent: "")
        sleep.target = self
        menu.addItem(sleep)
        item.menu = menu
    }

    @objc private func allowSleepNow() {
        allowSleep?()
    }

    /// A full cup (2026-10-16: "the cup should be filled, not empty"):
    /// the symbol's cup and saucer with the opening of the cup, its
    /// largest closed gap, filled; the handle and the saucer's line kept.
    /// Drawn for 1× and 2× screens.
    static let cup: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) else { return nil }
        let image = NSImage(size: symbol.size)
        for scale in [1, 2] {
            if let rep = filled(symbol, scale: scale) { image.addRepresentation(rep) }
        }
        image.isTemplate = true
        return image.representations.isEmpty ? symbol : image
    }()

    /// `symbol` drawn at `scale`, the largest gap it closes filled, with
    /// the soft edge around that gap, as one solid shape.
    static func filled(_ symbol: NSImage, scale: Int) -> NSBitmapImageRep? {
        let width = Int((symbol.size.width * CGFloat(scale)).rounded(.up))
        let height = Int((symbol.size.height * CGFloat(scale)).rounded(.up))
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)
        else { return nil }
        rep.size = symbol.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(x: 0, y: 0, width: symbol.size.width, height: symbol.size.height))
        NSColor.black.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }
        func alpha(_ index: Int) -> UInt8 { data[index * 4 + 3] }
        // -1: ink or outside (reached from an edge); n > 0: a closed gap.
        var region = [Int](repeating: 0, count: width * height)
        func flood(_ start: Int, mark: Int) -> Int {
            var stack = [start], count = 0
            region[start] = mark
            while let index = stack.popLast() {
                count += 1
                let x = index % width, y = index / width
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let next = ny * width + nx
                    if region[next] == 0, alpha(next) < 128 {
                        region[next] = mark
                        stack.append(next)
                    }
                }
            }
            return count
        }
        for index in 0..<(width * height) where alpha(index) >= 128 { region[index] = -1 }
        for x in 0..<width { for y in [0, height - 1] where region[y * width + x] == 0 { _ = flood(y * width + x, mark: -1) } }
        for y in 0..<height { for x in [0, width - 1] where region[y * width + x] == 0 { _ = flood(y * width + x, mark: -1) } }
        var largest = (id: 0, size: 0)
        var next = 1
        for index in 0..<(width * height) where region[index] == 0 {
            let size = flood(index, mark: next)
            if size > largest.size { largest = (next, size) }
            next += 1
        }
        guard largest.id > 0 else { return rep }
        let reach = scale
        for index in 0..<(width * height) where region[index] == largest.id {
            let x = index % width, y = index / width
            for ny in max(0, y - reach)...min(height - 1, y + reach) {
                for nx in max(0, x - reach)...min(width - 1, x + reach) {
                    let near = ny * width + nx
                    guard region[near] == largest.id || alpha(near) > 0 else { continue }
                    data[near * 4] = 0
                    data[near * 4 + 1] = 0
                    data[near * 4 + 2] = 0
                    data[near * 4 + 3] = 255
                }
            }
        }
        return rep
    }
}
