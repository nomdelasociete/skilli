import AppKit
import ScreenCaptureKit

/// Self-test hook: one of skil.li's own windows as the compositor shows it,
/// glass included (`cacheDisplay` leaves glass and sidebars blank). Only the
/// app's own windows are captured, which needs no Screen Recording
/// permission.
@MainActor
enum WindowCapture {
    static func image(of window: NSWindow) async -> CGImage? {
        // A window not on screen yet has no number (-1).
        guard window.windowNumber > 0, let windowID = CGWindowID(exactly: window.windowNumber) else { return nil }
        do {
            let content = try await SCShareableContent.currentProcess
            guard let target = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            // A size macOS cannot say (a menu bar item's window): nothing.
            let width = filter.contentRect.width * CGFloat(filter.pointPixelScale)
            let height = filter.contentRect.height * CGFloat(filter.pointPixelScale)
            guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(width)
            configuration.height = Int(height)
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            Log.perf.error("Window capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Self-test hook: the menu open in skil.li, alone (its window on the
    /// pop-up menu layer; the tallest when a submenu is open too).
    static func openMenuImage() async -> CGImage? {
        do {
            let content = try await SCShareableContent.currentProcess
            // Exactly the menu layer: the leader overlay sits higher.
            let layer = Int(CGWindowLevelForKey(.popUpMenuWindow))
            guard let menu = content.windows.filter({ $0.windowLayer == layer && $0.isOnScreen && $0.frame.height > 20 })
                .max(by: { $0.frame.height < $1.frame.height }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: menu)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            Log.perf.error("Menu capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Self-test hook: several of skil.li's windows together as they show
    /// on the display (a window and its popover), the rest left out;
    /// `withMenu`: the menu open over them too.
    static func png(of windows: [NSWindow], withMenu: Bool = false) async -> Data? {
        // A status item's window has a number past CGWindowID's range: left out.
        let ids = Set(windows.compactMap { $0.windowNumber > 0 ? CGWindowID(exactly: $0.windowNumber) : nil })
        do {
            let content = try await SCShareableContent.currentProcess
            let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
            let targets = content.windows.filter {
                ids.contains($0.windowID) || (withMenu && $0.windowLayer == menuLayer && $0.isOnScreen && $0.frame.height > 20)
            }
            guard let first = targets.first,
                  let display = content.displays.first(where: { $0.frame.intersects(first.frame) }) ?? content.displays.first
            else { return nil }
            let union = targets.dropFirst().reduce(first.frame) { $0.union($1.frame) }
            let filter = SCContentFilter(display: display, including: targets)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = union.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            let width = union.width * CGFloat(filter.pointPixelScale), height = union.height * CGFloat(filter.pointPixelScale)
            guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
            configuration.width = Int(width)
            configuration.height = Int(height)
            configuration.showsCursor = false
            configuration.backgroundColor = .clear
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        } catch {
            Log.perf.error("Windows capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func png(of window: NSWindow) async -> Data? {
        guard let image = await image(of: window) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Highest opacity on the outermost ring of pixels. 0 means everything
    /// the window draws, Liquid Glass shadows included, fits inside it; above
    /// 0 the window cuts something off with a straight edge.
    static func edgeAlpha(_ image: CGImage) -> Double {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        guard width > 1, height > 1 else { return 0 }
        var edge: [(Int, Int)] = []
        for x in 0..<width { edge += [(x, 0), (x, height - 1)] }
        for y in 0..<height { edge += [(0, y), (width - 1, y)] }
        return edge.reduce(0) { highest, point in
            max(highest, Double(bitmap.colorAt(x: point.0, y: point.1)?.alphaComponent ?? 0))
        }
    }
}
