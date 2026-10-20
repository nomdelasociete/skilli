import AppKit
import SwiftUI

/// "SI": skil.li's public word for AI (JB, 2026-10-13; the website's
/// `si-label.js`). It stands wherever AI would ("SI Accounts", "SI
/// Command"); pointing at it reveals "AI" in place. Never replace it.
enum Brand {
    static let intelligence = "SI"

    /// The same text with every SI read as AI ("SIRET" stays).
    static func revealed(_ text: String) -> String {
        text.replacing(/\bSI\b/, with: "AI")
    }

    static func hasSI(_ text: String) -> Bool {
        text.contains(/\bSI\b/)
    }
}

/// Text that says SI and reveals AI while the pointer is over it, in the
/// same room: both are laid out, the one not shown is hidden, so nothing
/// moves. Plain text when there is no SI in it. VoiceOver reads "SI (AI)".
struct SIText: View {
    private let text: String
    private let alignment: Alignment
    @State private var revealed = false

    init(_ text: String, alignment: Alignment = .leading) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        if Brand.hasSI(text) {
            ZStack(alignment: alignment) {
                Text(text).opacity(revealed ? 0 : 1)
                Text(Brand.revealed(text)).opacity(revealed ? 1 : 0)
            }
            .onHover { revealed = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.replacing(/\bSI\b/, with: "SI (AI)"))
        } else {
            Text(text)
        }
    }
}

/// An AppKit label that says SI and reveals AI while the pointer is over
/// it (the launcher's "SI Command"). Set `text`, not `stringValue`.
final class SIRevealLabel: NSTextField {
    var text = "" {
        didSet { stringValue = text }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // The launcher is a panel that never activates skil.li.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        if Brand.hasSI(text) { stringValue = Brand.revealed(text) }
    }

    override func mouseExited(with event: NSEvent) {
        stringValue = text
    }
}
