import AppKit
import Carbon.HIToolbox
import SkilliCore

/// Settings → Launcher → Type in English while open: the launcher opens,
/// the keyboard types with the user's own English layout (ABC, else U.S.,
/// `EnglishInput.pick`); it closes, their source comes back. Only sources
/// the user turned on in System Settings are selected: none is ever added
/// or turned on, and none English means nothing happens. Shortcuts keep
/// their keys: bindings read the user's own layout meanwhile
/// (`KeyboardLayout.hold`), and so do the launcher's ⌘ and ⌃ keys
/// (`chordEvent`). Secure Input is never touched: while it is on, nothing
/// is switched.
@MainActor
final class EnglishTyping {
    private let layout: KeyboardLayout
    /// The setting.
    var isOn: () -> Bool = { false }
    /// The source to put back as the launcher closes, and the one selected
    /// for it; nil while nothing was switched.
    private var switched: (previous: TISInputSource, english: TISInputSource)?
    /// Self-test hook: the last switch made, by source id.
    private(set) var lastSwitch: (from: String, to: String)?

    init(layout: KeyboardLayout) {
        self.layout = layout
    }

    /// Whether skil.li selected the English layout for the launcher now.
    var isSwitched: Bool { switched != nil }

    /// The user's English layout, when they turned one on.
    static func english() -> (source: TISInputSource, info: EnglishInput.Source)? {
        let enabled = enabledSources()
        guard let picked = EnglishInput.pick(enabled.map(\.info)) else { return nil }
        return enabled.first { $0.info.id == picked.id }
    }

    /// The keyboard sources the user turned on and may select.
    static func enabledSources() -> [(source: TISInputSource, info: EnglishInput.Source)] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.map { ($0, info($0)) }
    }

    /// The source typing now.
    static func current() -> (source: TISInputSource, info: EnglishInput.Source) {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return (source, info(source))
    }

    static func info(_ source: TISInputSource) -> EnglishInput.Source {
        func string(_ key: CFString) -> String? {
            TISGetInputSourceProperty(source, key).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        }
        func flag(_ key: CFString) -> Bool {
            TISGetInputSourceProperty(source, key).map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) } ?? false
        }
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .map { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] ?? [] } ?? []
        return EnglishInput.Source(id: string(kTISPropertyInputSourceID) ?? "", name: string(kTISPropertyLocalizedName) ?? "",
                                   languages: languages, asciiCapable: flag(kTISPropertyInputSourceIsASCIICapable),
                                   isKeyboardLayout: string(kTISPropertyInputSourceType) == (kTISTypeKeyboardLayout as String))
    }

    /// The launcher is up: the English layout, unless the user types
    /// English already or has none.
    func launcherOpened() {
        guard isOn(), switched == nil, !IsSecureEventInputEnabled(), let english = Self.english() else { return }
        let current = Self.current()
        guard EnglishInput.switches(from: current.info, to: english.info) else { return }
        // Bindings stay on the user's layout before the change is announced.
        layout.hold()
        guard TISSelectInputSource(english.source) == noErr else {
            layout.release()
            Log.input.error("Type in English: \(english.info.id, privacy: .public) could not be selected")
            return
        }
        switched = (current.source, english.source)
        lastSwitch = (current.info.id, english.info.id)
        Log.trace("Type in English: \(current.info.id) → \(english.info.id)")
    }

    /// The launcher closed: the user's source again, unless they chose
    /// another one meanwhile (theirs stays).
    func launcherClosed() {
        guard let switched else { return }
        self.switched = nil
        if Self.current().info.id == Self.info(switched.english).id {
            TISSelectInputSource(switched.previous)
        }
        layout.release()
    }

    /// A key with ⌘ or ⌃ while switched, as the user's own layout reads
    /// it: ⌘K, ⌘, and ⌃N stay where their hands know them. Anything else
    /// as it came.
    func chordEvent(_ event: NSEvent) -> NSEvent {
        guard switched != nil, !event.modifierFlags.intersection([.command, .control]).isEmpty,
              let character = layout.character(for: CGKeyCode(event.keyCode)) else { return event }
        let shown = event.modifierFlags.contains(.shift) ? character.uppercased() : character
        return NSEvent.keyEvent(with: event.type, location: event.locationInWindow, modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                                windowNumber: event.windowNumber, context: nil, characters: shown, charactersIgnoringModifiers: shown,
                                isARepeat: event.isARepeat, keyCode: event.keyCode) ?? event
    }
}
