// The recorder's Dock icon, `Sources/Skilli/Resources/RecorderIcon.icns`,
// made from `RecorderIcon.icon` (Icon Composer). skil.li sets it with
// `NSApp.applicationIconImage` while a recording's window is open, and the
// Dock draws that picture as given: so each size is Icon Composer's Default
// render placed on the macOS icon grid (824 of 1024, centered) with the
// shadow Xcode's own icns gives the app icon (measured on the 256 px one).
//
// From the repository's root, with Xcode installed:
//   swift assets/brand/recorder-icon/make-icns.swift
import AppKit

let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let source = "assets/brand/recorder-icon/RecorderIcon.icon"
let output = "Sources/Skilli/Resources/RecorderIcon.icns"
let sizes = [16, 32, 128, 256, 512]

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-icon-\(getpid())", isDirectory: true)
let iconset = scratch.appendingPathComponent("RecorderIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tool]) }
}

/// The icon `pixels` wide: the squircle Icon Composer renders, 824/1024 of
/// it, centered, over its shadow.
func icon(pixels: Int) throws -> Data {
    let side = (Double(pixels) * 824 / 1024).rounded()
    let body = scratch.appendingPathComponent("body-\(pixels).png")
    try run(ictool, [source, "--export-image", "--output-file", body.path, "--platform", "macOS", "--rendition", "Default",
                     "--width", "\(Int(side))", "--height", "\(Int(side))", "--scale", "1"])
    guard let image = NSImage(contentsOf: body),
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: body.path]) }
    let size = CGFloat(pixels)
    // In points before the context, or it draws 1:1 in pixels.
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
    shadow.set()
    image.draw(in: NSRect(x: (size - side) / 2, y: (size - side) / 2, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return png
}

for size in sizes {
    try icon(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try icon(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output])
print("Wrote \(output)")
