import AppKit
import ColorSync
import IOKit
import SkilliCore

/// The displays connected now, each with who it is: CoreGraphics for the
/// maker, model, serial and macOS's id; the I/O Registry for what the
/// display tells beyond that (its text serial, when it was made), on Apple
/// silicon. Read on save and apply, never on a keystroke.
@MainActor
enum Displays {
    /// The menu bar's display first, like `NSScreen.screens`.
    static func current() -> [LayoutDisplay] {
        let registry = registryProducts()
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let model = CGDisplayModelNumber(id)
            let serial = CGDisplaySerialNumber(id)
            let builtIn = CGDisplayIsBuiltin(id) != 0
            let product = builtIn ? nil : registry.first { $0.model == UInt64(model) && $0.serial == UInt64(serial) }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? ""
            let fingerprint = DisplayFingerprint(
                name: screen.localizedName, vendor: CGDisplayVendorNumber(id), model: model, serial: serial,
                serialText: product?.serialText, made: product?.made, builtIn: builtIn, uuid: uuid
            )
            return LayoutDisplay(fingerprint: fingerprint, frame: WindowManager.topLeft(screen.frame), visible: WindowManager.topLeft(screen.visibleFrame))
        }
    }

    private struct Product {
        let model: UInt64
        let serial: UInt64
        let serialText: String?
        let made: String?
    }

    /// What each display's EDID says, as the display controllers publish it
    /// (`DisplayAttributes` → `ProductAttributes` on Apple silicon).
    private static func registryProducts() -> [Product] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var products: [Product] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            guard let attributes = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let product = attributes["ProductAttributes"] as? [String: Any],
                let model = product["ProductID"] as? NSNumber
            else { continue }
            let text = (product["AlphanumericSerialNumber"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let year = (product["YearOfManufacture"] as? NSNumber)?.intValue ?? 0
            let week = (product["WeekOfManufacture"] as? NSNumber)?.intValue ?? 0
            products.append(Product(
                model: model.uint64Value,
                serial: (product["SerialNumber"] as? NSNumber)?.uint64Value ?? 0,
                serialText: text?.isEmpty == false ? text : nil,
                made: year > 0 ? (1...54).contains(week) ? "\(year)-W\(week)" : "\(year)" : nil
            ))
        }
        return products
    }
}
