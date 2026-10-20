import CoreGraphics
import Foundation

/// Whether a window's picture changed between two captures. A canvas (a
/// board, a map) tells Accessibility nothing when it redraws, so a click
/// on it settles on the picture (`ComputerControl.settlePicture`). Small
/// gray thumbnails: a 40 pt chess piece moving in a 900 pt window changes
/// a few of their pixels well past the threshold.
public enum PictureChange {
    public static let width = 96
    public static let height = 72

    /// `image` as `width` × `height` gray levels, top row first.
    public static func thumbnail(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// At least `pixels` of the thumbnails differ by more than `threshold`
    /// levels: something moved, not noise.
    public static func differs(_ a: [UInt8], _ b: [UInt8], threshold: Int = 18, pixels: Int = 2) -> Bool {
        guard a.count == b.count else { return true }
        var count = 0
        for index in a.indices where abs(Int(a[index]) - Int(b[index])) > threshold {
            count += 1
            if count >= pixels { return true }
        }
        return false
    }
}
