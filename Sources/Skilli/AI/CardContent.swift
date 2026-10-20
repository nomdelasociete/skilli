import AppKit
import SwiftUI

/// A purpose-made view the card shows in place of its text (a contact's
/// card, ⌘K's actions): it says how tall it is at the card's width.
@MainActor
protocol CardContent: NSView {
    func height(forWidth width: CGFloat) -> CGFloat
}

/// A SwiftUI view in the card, as tall as it needs at the card's width.
final class CardHostingView<Content: View>: NSView, CardContent {
    private let controller: NSHostingController<Content>

    init(_ root: Content) {
        controller = NSHostingController(rootView: root)
        super.init(frame: .zero)
        controller.view.translatesAutoresizingMaskIntoConstraints = true
        controller.view.autoresizingMask = [.width, .height]
        addSubview(controller.view)
    }

    required init?(coder: NSCoder) { nil }

    func height(forWidth width: CGFloat) -> CGFloat {
        ceil(controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    override func layout() {
        super.layout()
        controller.view.frame = bounds
    }
}
