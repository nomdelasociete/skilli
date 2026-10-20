import AppKit
import ScreenCaptureKit

/// Self-test: skil.li's glass windows exactly as the user sees them, over
/// test backdrops and in both appearances, captured from the screen.
///
/// A window that clips its glass shadow shows a straight edge: pixels just
/// inside the window's outline change when it appears, pixels just outside do
/// not. `edgeStep` measures that change on the outline. Needs Screen Recording
/// for skil.li (asked on first run).
@MainActor
enum GlassCheck {
    enum Backdrop: String, CaseIterable {
        case dark, light, photo
    }

    static let appearances: [(name: String, appearance: NSAppearance?)] = [
        ("light", NSAppearance(named: .aqua)),
        ("dark", NSAppearance(named: .darkAqua))
    ]

    /// Largest brightness change allowed on a window's outline (0...1).
    static let edgeLimit = 0.02

    struct Measure {
        let backdrop: Backdrop
        let appearance: String
        /// Brightness change just inside the outline: the visible edge.
        let edgeStep: Double
        /// Same just outside: should be 0; above it the capture is noisy.
        let outsideStep: Double
    }

    /// Asks ScreenCaptureKit itself: `CGPreflightScreenCaptureAccess` can
    /// report false for a granted app. Returns macOS's error when denied.
    static func accessError() async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Granted, but "bypass the system private window picker" not
            // allowed: windows are listed, displays are not.
            return content.displays.isEmpty ? "no display shareable: answer Allow to “bypass the system private window picker”" : nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Shows the system prompt and adds skil.li to the Screen Recording list.
    static func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Shows `window` (through `show`/`hide`) over each backdrop and
    /// appearance, captures the screen around it before and after, and
    /// saves what the user would see as `<name>-<backdrop>-<appearance>.png`.
    static func measure(
        window: NSWindow,
        name: String,
        show: () -> Void,
        hide: () -> Void,
        into directory: URL?
    ) async -> [Measure]? {
        show()
        let frame = window.frame
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else {
            Log.perf.error("Glass check: no screen under \(NSStringFromRect(frame), privacy: .public)")
            return nil
        }
        let area = frame.insetBy(dx: -24, dy: -24)
        let previousAppearance = window.appearance
        defer { window.appearance = previousAppearance }

        var measures: [Measure] = []
        for backdrop in Backdrop.allCases {
            let backdropWindow = makeBackdrop(backdrop, covering: area.insetBy(dx: -40, dy: -40))
            backdropWindow.orderFrontRegardless()
            defer { backdropWindow.orderOut(nil) }
            for (appearanceName, appearance) in appearances {
                window.appearance = appearance
                try? await Task.sleep(for: .milliseconds(200))
                guard let before = await capture(area, on: screen) else {
                    Log.perf.error("Glass check: capture before showing failed")
                    return nil
                }
                show()
                try? await Task.sleep(for: .milliseconds(350))
                let after = await capture(area, on: screen)
                hide()
                guard let after, window.frame == frame else {
                    Log.perf.error("Glass check: capture after showing failed (\(after == nil, privacy: .public)) or window moved to \(NSStringFromRect(window.frame), privacy: .public) from \(NSStringFromRect(frame), privacy: .public)")
                    return nil
                }
                let steps = edgeSteps(before: before, after: after, window: frame, area: area)
                measures.append(Measure(backdrop: backdrop, appearance: appearanceName, edgeStep: steps.inside, outsideStep: steps.outside))
                if let directory, let png = NSBitmapImageRep(cgImage: after).representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent("\(name)-\(backdrop.rawValue)-\(appearanceName).png"))
                }
            }
        }
        return measures
    }

    // MARK: - Capture

    /// The screen around `window` (Screen Recording), for design review.
    static func screenshot(around window: NSWindow, padding: CGFloat = 24) async -> CGImage? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) }) else { return nil }
        return await capture(window.frame.insetBy(dx: -padding, dy: -padding), on: screen)
    }

    /// A part of a screen, `rect` in AppKit global coordinates.
    static func screenshot(of rect: NSRect) async -> CGImage? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else { return nil }
        return await capture(rect, on: screen)
    }

    /// `rect` in AppKit global coordinates, every window included.
    private static func capture(_ rect: NSRect, on screen: NSScreen) async -> CGImage? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            Log.perf.error("Glass check: screen has no display ID")
            return nil
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                Log.perf.error("Glass check: display \(displayID, privacy: .public) not shareable; shareable displays \(content.displays.map(\.displayID), privacy: .public), windows \(content.windows.count, privacy: .public), screens \(NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }, privacy: .public)")
                return nil
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            // Display-local points, origin at the top left.
            configuration.sourceRect = CGRect(
                x: rect.minX - screen.frame.minX,
                y: screen.frame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int(rect.width * scale)
            configuration.height = Int(rect.height * scale)
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            Log.perf.error("Screen capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Largest brightness change between the two captures on a 3-pixel band
    /// just inside, and just outside, the window's outline.
    private static func edgeSteps(before: CGImage, after: CGImage, window: NSRect, area: NSRect) -> (inside: Double, outside: Double) {
        let old = NSBitmapImageRep(cgImage: before), new = NSBitmapImageRep(cgImage: after)
        let width = min(old.pixelsWide, new.pixelsWide), height = min(old.pixelsHigh, new.pixelsHigh)
        let scale = CGFloat(width) / area.width
        // Window outline in image pixels (origin top left).
        let left = Int(((window.minX - area.minX) * scale).rounded())
        let right = Int(((window.maxX - area.minX) * scale).rounded()) - 1
        let top = Int(((area.maxY - window.maxY) * scale).rounded())
        let bottom = Int(((area.maxY - window.minY) * scale).rounded()) - 1

        func change(_ x: Int, _ y: Int) -> Double {
            guard x >= 0, y >= 0, x < width, y < height,
                  let a = old.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                  let b = new.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            else { return 0 }
            func luminance(_ c: NSColor) -> Double {
                0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
            }
            return abs(luminance(a) - luminance(b))
        }
        func band(_ offset: Int) -> Double {
            // offset > 0 steps inside the outline, < 0 outside.
            var highest = 0.0
            for x in (left + offset)...(right - offset) {
                highest = max(highest, change(x, top + offset), change(x, bottom - offset))
            }
            for y in (top + offset)...(bottom - offset) {
                highest = max(highest, change(left + offset, y), change(right - offset, y))
            }
            return highest
        }
        return (inside: [1, 2, 3].map(band).max() ?? 0, outside: [-2, -3, -4].map(band).max() ?? 0)
    }

    // MARK: - Backdrops

    private static func makeBackdrop(_ backdrop: Backdrop, covering rect: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        // Under the launcher (.floating) and the overlay (.popUpMenu), over apps.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = BackdropView(backdrop)
        return window
    }

    private final class BackdropView: NSView {
        let backdrop: Backdrop

        init(_ backdrop: Backdrop) {
            self.backdrop = backdrop
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func draw(_ dirtyRect: NSRect) {
            switch backdrop {
            case .dark:
                NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).setFill()
                bounds.fill()
            case .light:
                NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill()
                bounds.fill()
            case .photo:
                // Sky, a dark diagonal band and bright spots: high contrast
                // under every edge, like a wallpaper or a photo.
                NSGradient(colors: [
                    NSColor(srgbRed: 0.55, green: 0.72, blue: 0.95, alpha: 1),
                    NSColor(srgbRed: 0.98, green: 0.70, blue: 0.52, alpha: 1)
                ])?.draw(in: bounds, angle: -70)
                let band = NSBezierPath()
                band.move(to: NSPoint(x: bounds.minX, y: bounds.minY + bounds.height * 0.15))
                band.line(to: NSPoint(x: bounds.minX + bounds.width * 0.55, y: bounds.maxY))
                band.line(to: NSPoint(x: bounds.minX + bounds.width * 0.72, y: bounds.maxY))
                band.line(to: NSPoint(x: bounds.minX + bounds.width * 0.12, y: bounds.minY))
                band.close()
                NSColor(srgbRed: 0.10, green: 0.12, blue: 0.20, alpha: 1).setFill()
                band.fill()
                NSColor(white: 1, alpha: 0.85).setFill()
                for (x, y, r) in [(0.85, 0.85, 40.0), (0.9, 0.2, 28.0), (0.3, 0.9, 22.0)] {
                    NSBezierPath(ovalIn: NSRect(x: bounds.width * x - r, y: bounds.height * y - r, width: 2 * r, height: 2 * r)).fill()
                }
            }
        }
    }
}
