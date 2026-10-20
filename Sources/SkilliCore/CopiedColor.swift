import Foundation

/// A copy that is one color, whole: "#3E8E7E", "3E8E7E" (as design tools
/// copy it), "rgb(62 142 126 / 50%)", "hsl(168, 39%, 40%)",
/// "Color(red: 0.24, green: 0.56, blue: 0.49)", "NSColor(srgbRed: 62 / 255,
/// …)". A parse of the copied text, never a color found inside a sentence.
/// sRGB, each component 0…1.
public struct CopiedColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
        self.alpha = Self.unit(alpha)
    }

    /// The color the whole text is; nil when it is anything else.
    public static func parse(_ text: String) -> CopiedColor? {
        // Cheap first: a color is short and starts with one of a few things.
        guard text.utf8.count <= 160 else { return nil }
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(";") { value.removeLast() }
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        if value.hasPrefix("#") || lower.hasPrefix("0x") || value.allSatisfy(\.isHexDigit) { return hex(value) }
        for name in ["rgba", "rgb", "hsla", "hsl"] where lower.hasPrefix(name + "(") {
            return css(name, arguments: lower)
        }
        return literal(value)
    }

    // MARK: - Shown

    /// "#3E8E7E", or "#3E8E7E80" when it is not opaque.
    public var hex: String {
        let digits = [red, green, blue].map { String(format: "%02X", Self.byte($0)) }.joined()
        return "#" + digits + (alpha < 1 ? String(format: "%02X", Self.byte(alpha)) : "")
    }

    /// "rgb(62, 142, 126)", "rgba(62, 142, 126, 0.5)".
    public var rgb: String {
        let parts = [red, green, blue].map { String(Self.byte($0)) }.joined(separator: ", ")
        return alpha < 1 ? "rgba(\(parts), \(Self.short(alpha)))" : "rgb(\(parts))"
    }

    /// "hsl(168, 39%, 40%)", "hsla(168, 39%, 40%, 0.5)".
    public var hsl: String {
        let (hue, saturation, lightness) = hslComponents
        let parts = "\(Int(hue.rounded()) % 360), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%"
        return alpha < 1 ? "hsla(\(parts), \(Self.short(alpha)))" : "hsl(\(parts))"
    }

    /// Opacity in percent: "50%".
    public var opacity: String { "\(Int((alpha * 100).rounded()))%" }

    /// Hue in degrees, saturation and lightness 0…1.
    public var hslComponents: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high > low else { return (0, 0, lightness) }
        let delta = high - low
        let saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        var hue: Double
        switch high {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        return (hue, saturation, lightness)
    }

    /// WCAG relative luminance, 0 (black) … 1 (white).
    public var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Text drawn on it reads dark on light colors, else white: white as
    /// long as it keeps 3:1, what large text needs (mid-tones read
    /// better in white).
    public var prefersDarkText: Bool {
        luminance > 0.3
    }

    // MARK: - Hex

    /// "#RGB", "#RGBA", "#RRGGBB", "#RRGGBBAA", "0xRRGGBB"; without "#",
    /// only six digits mixing figures and letters ("3E8E7E", not "123456"
    /// nor "decade").
    private static func hex(_ value: String) -> CopiedColor? {
        var digits = Substring(value)
        let marked: Bool
        if digits.hasPrefix("#") {
            digits = digits.dropFirst()
            marked = true
        } else if digits.lowercased().hasPrefix("0x") {
            digits = digits.dropFirst(2)
            marked = digits.count == 6
        } else {
            marked = false
        }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if !marked {
            guard digits.count == 6, digits.contains(where: \.isNumber), digits.contains(where: \.isLetter) else { return nil }
        }
        let chars = Array(digits)
        func pair(_ index: Int) -> Double? {
            UInt8(String(chars[index..<index + 2]), radix: 16).map { Double($0) / 255 }
        }
        func single(_ index: Int) -> Double? {
            UInt8(String([chars[index], chars[index]]), radix: 16).map { Double($0) / 255 }
        }
        switch chars.count {
        case 3, 4:
            guard let red = single(0), let green = single(1), let blue = single(2) else { return nil }
            return CopiedColor(red: red, green: green, blue: blue, alpha: chars.count == 4 ? single(3) ?? 1 : 1)
        case 6, 8:
            guard let red = pair(0), let green = pair(2), let blue = pair(4) else { return nil }
            return CopiedColor(red: red, green: green, blue: blue, alpha: chars.count == 8 ? pair(6) ?? 1 : 1)
        default:
            return nil
        }
    }

    // MARK: - CSS

    /// rgb()/rgba()/hsl()/hsla(), with commas or spaces and "/ alpha".
    private static func css(_ name: String, arguments lower: String) -> CopiedColor? {
        guard lower.hasSuffix(")") else { return nil }
        let inside = lower.dropFirst(name.count + 1).dropLast()
        // "62 142 126 / 50%" or "62, 142, 126, 0.5".
        let halves = inside.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count <= 2 else { return nil }
        let separators = CharacterSet(charactersIn: ", ").union(.whitespaces)
        var parts = halves[0].components(separatedBy: separators).filter { !$0.isEmpty }
        if halves.count == 2 {
            let alpha = halves[1].trimmingCharacters(in: .whitespaces)
            guard parts.count == 3, !alpha.isEmpty, !alpha.contains(" ") else { return nil }
            parts.append(alpha)
        }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let alpha = parts.count == 4 ? fraction(parts[3], scale: 1) : 1
        guard let alpha else { return nil }
        if name.hasPrefix("rgb") {
            guard let red = fraction(parts[0], scale: 255), let green = fraction(parts[1], scale: 255),
                  let blue = fraction(parts[2], scale: 255) else { return nil }
            return CopiedColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        var hueText = parts[0]
        if hueText.hasSuffix("deg") { hueText.removeLast(3) }
        guard let hue = Double(hueText), let saturation = percent(parts[1]), let lightness = percent(parts[2]) else { return nil }
        return fromHSL(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
    }

    /// "62" of 255, "50%", "0.5" of 1; nil out of range.
    private static func fraction(_ text: String, scale: Double) -> Double? {
        if text.hasSuffix("%") {
            return percent(text)
        }
        guard let number = Double(text), number >= 0, number <= scale else { return nil }
        return number / scale
    }

    /// "40%" (or "40", as CSS 4 allows) → 0.4.
    private static func percent(_ text: String) -> Double? {
        let digits = text.hasSuffix("%") ? String(text.dropLast()) : text
        guard let number = Double(digits), number >= 0, number <= 100 else { return nil }
        return number / 100
    }

    private static func fromHSL(hue: Double, saturation: Double, lightness: Double, alpha: Double) -> CopiedColor {
        let hue = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        guard saturation > 0 else { return CopiedColor(red: lightness, green: lightness, blue: lightness, alpha: alpha) }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ shift: Double) -> Double {
            var t = hue + shift
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return CopiedColor(red: channel(1 / 3), green: channel(0), blue: channel(-1 / 3), alpha: alpha)
    }

    private static func fromHSB(hue: Double, saturation: Double, brightness: Double, alpha: Double) -> CopiedColor {
        let sector = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = brightness - chroma
        return CopiedColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    // MARK: - Code literals

    /// `Color(red:green:blue:opacity:)`, `Color(.sRGB, red:…)`,
    /// `Color(white:)`, `Color(hue:saturation:brightness:)`, and the same
    /// for NSColor and UIColor (`srgbRed:`, `calibratedRed:`, `alpha:`);
    /// a component may be "62 / 255". Display P3 is not sRGB: left out.
    private static func literal(_ value: String) -> CopiedColor? {
        let types = ["SwiftUI.Color(", "Color(", "NSColor(", "UIColor(", "CGColor("]
        guard let type = types.first(where: value.hasPrefix), value.hasSuffix(")") else { return nil }
        let inside = value.dropFirst(type.count).dropLast()
        var labeled: [String: Double] = [:]
        for argument in inside.split(separator: ",") {
            let part = argument.trimmingCharacters(in: .whitespaces)
            guard let colon = part.firstIndex(of: ":") else {
                // Only the sRGB color space, unlabeled first.
                guard part == ".sRGB" else { return nil }
                continue
            }
            let label = part[..<colon].trimmingCharacters(in: .whitespaces)
            guard let number = expression(part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)),
                  number >= 0, number <= 1 else { return nil }
            labeled[label] = number
        }
        let alpha = labeled["alpha"] ?? labeled["opacity"] ?? 1
        let reds = ["red", "srgbRed", "calibratedRed", "deviceRed"]
        if let red = reds.lazy.compactMap({ labeled[$0] }).first, let green = labeled["green"], let blue = labeled["blue"] {
            let known = Set(reds + ["green", "blue", "alpha", "opacity"])
            guard labeled.keys.allSatisfy(known.contains) else { return nil }
            return CopiedColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        let whites = ["white", "calibratedWhite", "deviceWhite", "genericGrayGamma2_2Gray"]
        if let white = whites.lazy.compactMap({ labeled[$0] }).first, labeled.count <= 2 {
            return CopiedColor(red: white, green: white, blue: white, alpha: alpha)
        }
        if let hue = labeled["hue"] ?? labeled["calibratedHue"] ?? labeled["deviceHue"],
           let saturation = labeled["saturation"], let brightness = labeled["brightness"] {
            return fromHSB(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        }
        return nil
    }

    /// "0.24", "62 / 255", "62.0/255.0".
    private static func expression(_ text: String) -> Double? {
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        switch parts.count {
        case 1: return Double(parts[0])
        case 2:
            guard let top = Double(parts[0]), let bottom = Double(parts[1]), bottom != 0 else { return nil }
            return top / bottom
        default: return nil
        }
    }

    // MARK: - Numbers

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func byte(_ value: Double) -> Int {
        Int((value * 255).rounded())
    }

    /// "0.5", "0.25", "1".
    private static func short(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
    }
}
