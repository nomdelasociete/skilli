import Foundation

/// What macOS's own `networkQuality` measured, said in one line.
public struct SpeedTest: Equatable, Sendable {
    /// Bits per second.
    public let download: Double
    public let upload: Double
    /// Round trips per minute under load (Apple's responsiveness).
    public let responsiveness: Double?
    /// Milliseconds, idle.
    public let latency: Double?

    public init(download: Double, upload: Double, responsiveness: Double?, latency: Double?) {
        self.download = download
        self.upload = upload
        self.responsiveness = responsiveness
        self.latency = latency
    }

    /// `networkQuality -c`'s JSON; nil when it measured nothing.
    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
        guard let download = number("dl_throughput"), let upload = number("ul_throughput") else { return nil }
        self.init(download: download, upload: upload,
                  responsiveness: number("responsiveness") ?? number("dl_responsiveness"),
                  latency: number("base_rtt"))
    }

    /// "↓ 330 Mbps · ↑ 41 Mbps · Responsiveness: High (1 337 RPM) · Latency 9 ms".
    public var summary: String {
        var parts = ["↓ \(Self.megabits(download))", "↑ \(Self.megabits(upload))"]
        if let responsiveness {
            parts.append("Responsiveness: \(Self.grade(responsiveness)) (\(Int(responsiveness.rounded()).formatted()) RPM)")
        }
        if let latency { parts.append("Latency \(Int(latency.rounded())) ms") }
        return parts.joined(separator: " · ")
    }

    /// Apple's own words for its responsiveness scale.
    public static func grade(_ rpm: Double) -> String {
        rpm >= 1_000 ? "High" : rpm >= 300 ? "Medium" : "Low"
    }

    static func megabits(_ bitsPerSecond: Double) -> String {
        let mbps = bitsPerSecond / 1_000_000
        if mbps >= 1_000 { return String(format: "%.1f Gbps", mbps / 1_000) }
        return mbps >= 10 ? "\(Int(mbps.rounded())) Mbps" : String(format: "%.1f Mbps", mbps)
    }
}

/// A picked color, the ways people paste it.
public struct PickedColor: Equatable, Sendable {
    /// 0…255, sRGB.
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Double, green: Double, blue: Double) {
        func channel(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        self.red = channel(red)
        self.green = channel(green)
        self.blue = channel(blue)
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }

    public var hsl: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        var hue = 0.0, saturation = 0.0
        if high != low {
            let delta = high - low
            saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
            switch high {
            case r: hue = (g - b) / delta + (g < b ? 6 : 0)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            hue *= 60
        }
        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }
}

public enum MacReadings {
    /// "3 days 4 h", "5 h 12 min", "8 min".
    public static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let days = minutes / 1_440, hours = (minutes % 1_440) / 60, rest = minutes % 60
        if days > 0 { return "\(days) day\(days == 1 ? "" : "s") \(hours) h" }
        if hours > 0 { return "\(hours) h \(rest) min" }
        return "\(rest) min"
    }

    /// A volume level from what people say: "30", "30 %", "30%".
    public static func percent(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits), (0...100).contains(value) else { return nil }
        return value
    }
}

extension MacReadings {
    /// A Wi-Fi signal in words, from its strength in dBm, as macOS's own
    /// bars read it: good from −60, fair from −70, else weak.
    public static func signal(rssi: Int) -> String {
        rssi >= -60 ? "good" : rssi >= -70 ? "fair" : "weak"
    }
}
