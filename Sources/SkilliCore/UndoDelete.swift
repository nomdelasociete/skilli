import Foundation

/// Rule 2 of the interactions (AGENTS.md): a delete of the user's data
/// happens at once, and Undo ⌘Z in the card brings it back for 10 s
/// (`AIActionController.offerUndo`, `UndoableDeletes` in the app). What
/// the card says, and how what went finds its place again: pure parts.
public enum UndoDelete {
    /// How long ⌘Z brings it back.
    public static let seconds: Double = 10

    /// The card's line: the item's name in bold, then what more there is
    /// to say, as written ("**Home address** (;addr)", "**Work**: its
    /// windows stay where they are."). The name is cut to one short line
    /// and its Markdown characters escaped, so a name never styles the
    /// card ("my_server" stays as typed).
    public static func details(_ name: String, _ more: String = "") -> String {
        "**\(escaped(shortened(name)))**" + more
    }

    /// One line, at most `limit` characters ("Réunion budget jeudi…").
    public static func shortened(_ text: String, limit: Int = 60) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let words = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard words.count > limit else { return words }
        let cut = words.prefix(limit - 1)
        let lastSpace = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return (lastSpace.count > limit / 2 ? String(lastSpace) : String(cut)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Markdown's own characters, escaped as CommonMark does.
    public static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\*_`[]~<>#".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Room an undo card takes: its title, a line or two, its keys.
    public static let cardRoom: CGFloat = 150

    /// Where the undo card's top-left goes while the launcher is open (a
    /// copy forgotten with ⌘⌫): right under the launcher's glass, as wide,
    /// so it never covers the rows; above it when the screen has no room
    /// below (the launcher dragged low). The rect is the card's top edge
    /// (no height): the card grows down from it.
    public static func spot(under glass: CGRect, in visible: CGRect, gap: CGFloat = 10) -> CGRect {
        let below = glass.minY - gap
        if below - cardRoom >= visible.minY {
            return CGRect(x: glass.minX, y: below, width: glass.width, height: 0)
        }
        let above = min(glass.maxY + gap + cardRoom, visible.maxY)
        return CGRect(x: glass.minX, y: above, width: glass.width, height: 0)
    }

    /// The name a file put back takes when its place got taken meanwhile,
    /// as the Finder names a copy: "report 2.pdf", "report 3.pdf"…; a
    /// folder or a name without an extension: "Notes 2". Never one taken.
    public static func freeName(for name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let ext = (name as NSString).pathExtension
        let hasExtension = !ext.isEmpty && !name.hasPrefix(".") && ext.count <= 8 && !ext.contains(" ")
        let base = hasExtension ? String(name.dropLast(ext.count + 1)) : name
        var number = 2
        while true {
            let candidate = hasExtension ? "\(base) \(number).\(ext)" : "\(base) \(number)"
            if !isTaken(candidate) { return candidate }
            number += 1
        }
    }
}

/// An element taken out of a list and where it was: ⌘Z puts it back at
/// the same place (at the end when the list got shorter meanwhile), once.
public struct RemovedElement<Element> {
    public let element: Element
    public let index: Int

    public init(element: Element, index: Int) {
        self.element = element
        self.index = index
    }

    /// Takes the first element that matches out of `list`; nil when none.
    public static func take(from list: inout [Element], where matches: (Element) -> Bool) -> RemovedElement? {
        guard let index = list.firstIndex(where: matches) else { return nil }
        return RemovedElement(element: list.remove(at: index), index: index)
    }

    /// Back where it was, unless `isSame` finds it there already (put back
    /// by another way meanwhile). Returns whether it went back.
    @discardableResult
    public func putBack(into list: inout [Element], unlessThere isSame: (Element) -> Bool) -> Bool {
        guard !list.contains(where: isSame) else { return false }
        list.insert(element, at: min(index, list.count))
        return true
    }
}

extension RemovedElement where Element: Identifiable {
    /// Takes the element with this id out of `list`.
    public static func take(_ id: Element.ID, from list: inout [Element]) -> RemovedElement? {
        take(from: &list) { $0.id == id }
    }

    /// Back where it was, unless one with its id is there.
    @discardableResult
    public func putBack(into list: inout [Element]) -> Bool {
        putBack(into: &list) { $0.id == element.id }
    }
}
