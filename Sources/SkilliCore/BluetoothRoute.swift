import Foundation

/// Bluetooth devices the way people name them: "mes AirPods", "le clavier",
/// "l'enceinte". What IOBluetooth says (a device class, a name) turned into
/// words for the launcher, Ask and agents.
public enum BluetoothRoute {
    public enum Kind: String, Sendable, CaseIterable {
        case headphones, speaker, keyboard, mouse, trackpad, gamepad, phone, computer, watch, other

        /// The Bluetooth class of device's major and minor fields, as
        /// IOBluetooth gives them (`deviceClassMajor`, `deviceClassMinor`:
        /// the minor's six bits), and the name for what the class does not
        /// tell (a trackpad is a pointing device).
        public init(major: UInt32, minor: UInt32, name: String) {
            let lower = name.lowercased()
            switch major {
            case 0x04:
                // Audio: loudspeaker (5), portable audio (7), car (8), HiFi (10).
                self = [5, 7, 8, 10].contains(minor) ? .speaker : .headphones
            case 0x05:
                // Peripheral: bits 4–5 say keyboard (1), pointing (2) or both (3);
                // bits 0–3 a joystick (1) or a gamepad (2).
                let kind = (minor >> 4) & 0x3
                if kind == 1 || kind == 3 {
                    self = .keyboard
                } else if kind == 2 {
                    self = lower.contains("trackpad") ? .trackpad : .mouse
                } else if [1, 2].contains(minor & 0xF) || lower.contains("controller") || lower.contains("manette") {
                    self = .gamepad
                } else {
                    self = lower.contains("keyboard") || lower.contains("clavier") ? .keyboard
                        : lower.contains("trackpad") ? .trackpad : lower.contains("mouse") || lower.contains("souris") ? .mouse : .other
                }
            case 0x02: self = .phone
            case 0x01: self = .computer
            case 0x07: self = lower.contains("watch") ? .watch : .headphones
            default:
                self = lower.contains("airpods") || lower.contains("beats") ? .headphones : lower.contains("watch") ? .watch : .other
            }
        }

        /// Something one connects to use it: not a computer, a phone or a
        /// watch (paired for other things than a link from here).
        public var isAccessory: Bool {
            ![.computer, .phone, .watch].contains(self)
        }

        /// For the decision model: "Bluetooth headphones or earbuds".
        public var spoken: String {
            switch self {
            case .headphones: "Bluetooth headphones or earbuds"
            case .speaker: "a Bluetooth speaker"
            case .keyboard: "a Bluetooth keyboard"
            case .mouse: "a Bluetooth mouse"
            case .trackpad: "a Bluetooth trackpad"
            case .gamepad: "a game controller"
            case .phone: "a phone"
            case .computer: "a computer or tablet"
            case .watch: "a watch"
            case .other: "a Bluetooth device"
            }
        }

        /// Words for the kind alone: "casque", "clavier".
        public var words: [String] {
            switch self {
            case .headphones: ["headphones", "earbuds", "headset", "casque", "écouteurs", "oreillettes"]
            case .speaker: ["speaker", "enceinte", "haut-parleur"]
            case .keyboard: ["keyboard", "clavier"]
            case .mouse: ["mouse", "souris"]
            case .trackpad: ["trackpad", "pavé"]
            case .gamepad: ["controller", "gamepad", "manette"]
            case .phone: ["phone", "téléphone", "iphone"]
            case .computer: ["computer", "ordinateur", "ipad", "mac"]
            case .watch: ["watch", "montre"]
            case .other: []
            }
        }
    }

    /// "Connect AirPods Pro", "Disconnect Magic Keyboard".
    public static func title(name: String, connect: Bool) -> String {
        (connect ? "Connect " : "Disconnect ") + name
    }

    /// Words people type to reach a device's row.
    public static func keywords(kind: Kind, connect: Bool) -> [String] {
        (connect ? ["bluetooth", "connect", "connecter", "connecte", "relier"] : ["bluetooth", "disconnect", "déconnecter", "déconnecte"])
            + kind.words
    }

    /// For the decision model: what choosing it does.
    public static func description(name: String, kind: Kind, connect: Bool) -> String {
        connect
            ? "Connect \(kind.spoken) named “\(name)”, paired with this Mac and not connected now (Bluetooth)"
            : "Disconnect \(kind.spoken) named “\(name)”, connected to this Mac now (Bluetooth)"
    }

    public static func symbol(name: String, kind: Kind) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        switch kind {
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .gamepad: return "gamecontroller"
        case .phone: return "iphone"
        case .computer: return "laptopcomputer"
        case .watch: return "applewatch"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    /// The device a few words point to: its name first ("airpods" →
    /// "AirPods Pro de Camille"), else its kind ("clavier" → the keyboard). Nil
    /// when nothing fits, or several equally.
    public static func match(_ text: String, among devices: [(name: String, kind: Kind)]) -> Int? {
        let filler: Set<String> = ["le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "mes", "mon", "ma", "the", "my", "to",
                                   "bluetooth", "connect", "connecte", "connecter", "disconnect", "deconnecte", "deconnecter", "device",
                                   "appareil", "please", "stp"]
        let words = AudioRoute.fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !filler.contains($0) }
        guard !words.isEmpty else { return nil }
        let names = devices.map { AudioRoute.fold($0.name) }
        let byName = names.indices.filter { index in words.allSatisfy { names[index].contains($0) } }
        if !byName.isEmpty { return byName.count == 1 ? byName[0] : nil }
        let byKind = devices.indices.filter { index in
            let kinds = devices[index].kind.words.map(AudioRoute.fold)
            return words.contains { word in kinds.contains { $0.contains(word) || word.contains($0) } }
        }
        return byKind.count == 1 ? byKind[0] : nil
    }

    /// The text asks about Bluetooth or connecting a device: where a
    /// launcher or Ask that may not use Bluetooth yet offers to allow it.
    public static func mentions(_ text: String) -> Bool {
        let words = Set(AudioRoute.fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return !words.isDisjoint(with: ["bluetooth", "connecte", "connecter", "deconnecte", "deconnecter", "connect", "disconnect"])
    }
}
