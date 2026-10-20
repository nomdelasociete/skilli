import Foundation

/// Sound devices the way people name them: "les AirPods", "les
/// haut-parleurs", "l'écran", "le micro". What CoreAudio says (a transport
/// code, a name) turned into words for the launcher, Ask and agents.
public enum AudioRoute {
    public enum Transport: String, Sendable, CaseIterable {
        case builtIn, bluetooth, usb, display, airPlay, iPhone, virtual, other

        /// CoreAudio's `kAudioDeviceTransportType…` four-character codes.
        public init(code: UInt32) {
            switch Self.fourCC(code) {
            case "bltn": self = .builtIn
            case "blue", "blea": self = .bluetooth
            case "usb ": self = .usb
            case "hdmi", "dprt", "thun": self = .display
            case "airp": self = .airPlay
            case "ccwd", "ccwl": self = .iPhone
            case "virt", "grup", "auto": self = .virtual
            default: self = .other
            }
        }

        static func fourCC(_ code: UInt32) -> String {
            let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
            return String(bytes: bytes, encoding: .ascii) ?? ""
        }
    }

    /// "Bluetooth headphones or speaker", "built-in microphone".
    public static func kind(_ transport: Transport, output: Bool) -> String {
        switch transport {
        case .builtIn: output ? "the speakers built into the Mac itself (not a screen's)" : "the microphone built into the Mac"
        case .bluetooth: output ? "Bluetooth headphones or speaker" : "a Bluetooth microphone"
        case .usb: output ? "USB speakers or headset" : "a USB microphone"
        case .display: output ? "the screen or TV plugged into the Mac (HDMI, DisplayPort), with its own speakers" : "a screen's microphone"
        case .airPlay: "an AirPlay speaker or TV"
        case .iPhone: "the iPhone's microphone"
        case .virtual: output ? "a virtual output (for apps)" : "a virtual input (for apps)"
        case .other: output ? "a sound output" : "a microphone"
        }
    }

    /// "Sound Output: AirPods Pro", "Microphone: MacBook Pro Microphone".
    public static func title(name: String, output: Bool) -> String {
        (output ? "Sound Output: " : "Microphone: ") + name
    }

    /// For the decision model: what choosing it does.
    public static func description(name: String, transport: Transport, output: Bool) -> String {
        output
            ? "Play the sound through \(kind(transport, output: true)), named “\(name)”: where it plays, not how loud"
            : "Record with \(kind(transport, output: false)), named “\(name)”, as the microphone"
    }

    public static func symbol(name: String, transport: Transport, output: Bool) -> String {
        guard output else { return "mic.fill" }
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        switch transport {
        case .builtIn: return "speaker.wave.2.fill"
        case .bluetooth: return "headphones"
        case .display: return "tv"
        case .airPlay: return "airplayaudio"
        default: return "hifispeaker.fill"
        }
    }

    /// Other words people type, in English and French.
    public static func keywords(transport: Transport, output: Bool) -> [String] {
        (output ? ["sound", "audio", "output", "son", "sortie"] : ["microphone", "mic", "input", "micro", "entrée"])
            + kindWords(transport, output: output)
    }

    /// Words for the kind of device alone: "casque", "écran".
    static func kindWords(_ transport: Transport, output: Bool) -> [String] {
        switch transport {
        case .builtIn: output ? ["speakers", "haut-parleurs", "built-in", "intégrés"] : ["built-in", "intégré"]
        case .bluetooth: output ? ["headphones", "casque", "écouteurs", "bluetooth", "enceinte"] : ["bluetooth", "casque"]
        case .display: ["display", "écran", "tv", "télé", "hdmi"]
        case .airPlay: ["airplay", "tv", "télé", "enceinte"]
        case .usb: ["usb", "casque", "headset"]
        case .iPhone: ["iphone", "téléphone"]
        case .virtual, .other: []
        }
    }

    /// The device a few words point to: its name first ("airpods" →
    /// "AirPods Pro de JB"), else its kind ("haut-parleurs" → built-in,
    /// "écran" → HDMI). Nil when nothing fits, or several equally.
    public static func match(_ text: String, among devices: [(name: String, transport: Transport)], output: Bool) -> Int? {
        let words = significantWords(text)
        guard !words.isEmpty else { return nil }
        let names = devices.map { fold($0.name) }
        let byName = names.indices.filter { index in words.allSatisfy { names[index].contains($0) } }
        if !byName.isEmpty { return byName.count == 1 ? byName[0] : nil }
        let byKind = devices.indices.filter { index in
            let kinds = kindWords(devices[index].transport, output: output).map(fold)
            return words.contains { word in kinds.contains { $0.contains(word) } }
        }
        return byKind.count == 1 ? byKind[0] : nil
    }

    static func significantWords(_ text: String) -> [String] {
        let filler: Set<String> = ["le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "sur", "the", "my", "mes", "mon", "ma",
                                   "to", "on", "son", "sound", "audio", "output", "sortie", "micro", "mic", "microphone", "input", "entree"]
        return fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { !filler.contains($0) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
