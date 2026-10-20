import AppKit
import Carbon.HIToolbox
import SkilliCore

/// Maps hardware key codes to layout characters and back, for the active
/// keyboard layout. Bindings say `u`; on AZERTY that is still the key that
/// types "u". Rebuilt when the user switches input source.
@MainActor
final class KeyboardLayout {
    private var keysByCode: [CGKeyCode: Key] = [:]
    private var codesByKey: [Key: CGKeyCode] = [:]
    /// The layout `rebuild` read: the user's own while held.
    private var layoutData: Data?
    /// What each key types with ⇧ and ⌥, made the first time it is asked.
    private var typing: TypingKeys?
    private var observer: NSObjectProtocol?
    /// While skil.li switched the input source for the launcher
    /// (`EnglishTyping`): bindings keep the user's own layout, so ✦A stays
    /// the key that types "a" for them.
    private(set) var isHeld = false

    private static let namedKeys: [(Int, NamedKey)] = [
        (kVK_Space, .space),
        (kVK_Return, .return),
        (kVK_ANSI_KeypadEnter, .return),
        (kVK_Tab, .tab),
        (kVK_Escape, .escape),
        (kVK_Delete, .delete),
        (kVK_ForwardDelete, .forwardDelete),
        (kVK_LeftArrow, .left),
        (kVK_RightArrow, .right),
        (kVK_UpArrow, .up),
        (kVK_DownArrow, .down),
        (kVK_Home, .home),
        (kVK_End, .end),
        (kVK_PageUp, .pageUp),
        (kVK_PageDown, .pageDown)
    ]

    init() {
        rebuild()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.isHeld == false else { return }
                self?.rebuild()
            }
        }
    }

    /// Keeps the layout as it is now until `release`, whatever source is
    /// selected meanwhile.
    func hold() {
        isHeld = true
    }

    /// The layout selected now again.
    func release() {
        guard isHeld else { return }
        isHeld = false
        rebuild()
    }

    /// What `code` types on the layout bindings read (the user's own while
    /// held): "k" for ⌘K wherever the English layout puts it.
    func character(for code: CGKeyCode) -> String? {
        if case .character(let character)? = keysByCode[code] { return String(character) }
        return nil
    }

    func key(for code: CGKeyCode) -> Key? {
        keysByCode[code]
    }

    func keyCode(for key: Key) -> CGKeyCode? {
        codesByKey[key]
    }

    func rebuild() {
        var keys: [CGKeyCode: Key] = [:]
        for (code, named) in Self.namedKeys {
            keys[CGKeyCode(code)] = .named(named)
        }

        layoutData = Self.currentLayoutData()
        typing = nil
        if let layoutData {
            layoutData.withUnsafeBytes { raw in
                guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
                for code in CGKeyCode(0)..<128 where keys[code] == nil {
                    if let character = Self.character(for: code, layout: layout) {
                        keys[code] = .character(character)
                    }
                }
            }
        } else {
            Log.input.error("No Unicode keyboard layout data; only named keys are bindable")
        }

        // Typing a character uses what each key types (on AZERTY the number
        // row types & é "…): built before the shortcut names below.
        // Lowest code wins so main-row keys beat their keypad twins.
        codesByKey = Dictionary(keys.map { ($1, $0) }, uniquingKeysWith: min)
        // Shortcuts name the number row 1 to 0 whatever it types alone.
        for (code, digit) in Self.numberRow {
            var deadKeyState: UInt32 = 0
            let shifted = typedText(for: CGKeyCode(code), flags: .maskShift, deadKeyState: &deadKeyState)
            if case .character(let alone)? = keys[CGKeyCode(code)],
               let named = NumberRow.shortcutDigit(digit, unshifted: String(alone), shifted: shifted) {
                keys[CGKeyCode(code)] = .character(named)
            }
        }
        keysByCode = keys
    }

    /// The keys that type `character` on the user's own layout, with at
    /// most ⇧ and ⌥ held: "⌥⇧K" for the Apple logo on U.S., "⌥$" for €
    /// on French. Nil when no key types it, or only through a dead key.
    func keys(typing character: String) -> String? {
        if typing == nil { typing = makeTyping() }
        return typing?.chord(typing: character)?.description
    }

    private func makeTyping() -> TypingKeys {
        guard let layoutData else { return TypingKeys([]) }
        let held: [(Modifiers, UInt32)] = [([], 0), (.shift, UInt32(shiftKey)), (.option, UInt32(optionKey)),
                                           ([.option, .shift], UInt32(optionKey | shiftKey))]
        var typed: [(chord: Chord, text: String)] = []
        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in CGKeyCode(0)..<128 {
                guard let key = keysByCode[code], case .character = key else { continue }
                for (modifiers, carbon) in held {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), (carbon >> 8) & 0xFF, UInt32(LMGetKbdType()),
                                                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                                                characters.count, &length, &characters)
                    guard status == noErr, length > 0 else { continue }
                    let text = String(utf16CodeUnits: characters, count: length)
                    // Function keys type U+F700…U+F7FF; U+F8FF is the Apple logo.
                    guard text.count == 1, let scalar = text.unicodeScalars.first, scalar.value > 0x20, scalar.value != 0x7F,
                          !(0xF700...0xF7FF).contains(scalar.value)
                    else { continue }
                    typed.append((Chord(key, modifiers), text))
                }
            }
        }
        return TypingKeys(typed)
    }

    private static let numberRow: [(Int, Character)] = [
        (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
        (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"), (kVK_ANSI_0, "0")
    ]

    /// What `code` types with `flags` on the current layout, for text typed
    /// into skil.li's card. Dead keys (^ then e → ê) carry over through
    /// `deadKeyState`; a dead key alone types nothing yet.
    func typedText(for code: CGKeyCode, flags: CGEventFlags, deadKeyState: inout UInt32) -> String {
        guard let layoutData = Self.currentLayoutData() else { return "" }
        // Carbon modifier bits, shifted down by 8 as UCKeyTranslate wants.
        var carbon: UInt32 = 0
        if flags.contains(.maskShift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.maskAlphaShift) { carbon |= UInt32(alphaLock) }
        if flags.contains(.maskAlternate) { carbon |= UInt32(optionKey) }
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout,
                code,
                UInt16(kUCKeyActionDown),
                (carbon >> 8) & 0xFF,
                UInt32(LMGetKbdType()),
                0,
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return "" }
        // Function keys type U+F700…U+F7FF; ⌥⇧K's U+F8FF is the Apple logo.
        return String(utf16CodeUnits: characters, count: length)
            .filter { character in character.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF7FF).contains($0.value) } }
    }

    private static func currentLayoutData() -> Data? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    /// Unmodified character for `code`, lowercased; `nil` for function keys,
    /// control characters and whitespace (those are named keys).
    private static func character(for code: CGKeyCode, layout: UnsafePointer<UCKeyboardLayout>) -> Character? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            code,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }

        let string = String(utf16CodeUnits: characters, count: length).lowercased()
        guard string.count == 1,
              let scalar = string.unicodeScalars.first,
              scalar.value > 0x20,
              scalar.value != 0x7F,
              !(0xF700...0xF8FF).contains(scalar.value)
        else { return nil }
        return string.first
    }
}
