import AppKit
import CoreText
import SkilliCore

/// The emoji picker as a grid, as Raycast and Apple show emoji: eight
/// across, Unicode's groups under their names while browsing. It draws the
/// launcher's rows (`LauncherController.results`); the launcher's table
/// stays the selection every action reads (↩, ⌘↩, ⌘K), the grid shows it
/// and moves it in two directions.
final class EmojiGridView: NSView {
    enum Direction {
        case left, right, up, down
    }

    static let columns = 8
    private static let inset: CGFloat = 14
    private static let rowHeight: CGFloat = 58
    private static let headerHeight: CGFloat = 30

    private let scroll = NSScrollView()
    private let collection = EmojiCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    /// What each tile shows, toned, and its name (VoiceOver).
    private var tiles: [(character: String, name: String)] = []
    /// Never empty once shown: one unnamed section for a search.
    private var sections: [EmojiList.Section] = []
    /// Where each section starts among the tiles.
    private var starts: [Int] = []
    private(set) var selected = 0

    /// A click on a tile: selects it; a double click opens it.
    var onSelect: ((Int) -> Void)?
    var onOpen: ((Int) -> Void)?
    /// The group at the top as the grid scrolls, for the launcher's header;
    /// nil without groups.
    var onTopSection: ((String?) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layout.itemSize = NSSize(width: ((frame.width - 2 * Self.inset) / CGFloat(Self.columns)).rounded(.down), height: Self.rowHeight)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = NSEdgeInsets(top: 0, left: Self.inset, bottom: 4, right: Self.inset)
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiGridItem.self, forItemWithIdentifier: EmojiGridItem.identifier)
        collection.register(EmojiGridHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                            withIdentifier: EmojiGridHeader.identifier)
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = collection
        addSubview(scroll)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `tiles` (each toned, with its name) under `sections` (their
    /// counts adding up to the tiles; none for a search), from the top.
    func show(_ tiles: [(character: String, name: String)], sections: [EmojiList.Section]) {
        self.tiles = tiles
        self.sections = sections.isEmpty || sections.map(\.count).reduce(0, +) != tiles.count
            ? [EmojiList.Section(name: "", count: tiles.count)] : sections
        var start = 0
        starts = self.sections.map { section in
            defer { start += section.count }
            return start
        }
        selected = 0
        collection.reloadData()
        collection.layoutSubtreeIfNeeded()
        collection.scroll(.zero)
        scrolled()
    }

    /// Shows `index` selected, scrolled into sight.
    func select(_ index: Int) {
        guard tiles.indices.contains(index) else { return }
        let old = selected
        selected = index
        for flat in [old, index] {
            (collection.item(at: path(of: flat)) as? EmojiGridItem)?.isChosen = flat == index
        }
        collection.scrollToItems(at: [path(of: index)], scrollPosition: .nearestHorizontalEdge)
    }

    /// The tile `direction` of `index`: beside it, or the nearest one in
    /// the row above or below (rows end early before a group's name).
    func neighbor(of index: Int, _ direction: Direction) -> Int? {
        guard tiles.indices.contains(index) else { return nil }
        switch direction {
        case .left: return index > 0 ? index - 1 : nil
        case .right: return index + 1 < tiles.count ? index + 1 : nil
        case .up, .down:
            guard let here = frame(of: index) else { return nil }
            let step = direction == .down ? 1 : -1
            var row: CGFloat?
            var best: (index: Int, distance: CGFloat)?
            var next = index + step
            while tiles.indices.contains(next), let there = frame(of: next) {
                let other = direction == .down ? there.minY > here.midY : there.maxY < here.midY
                if other {
                    if row == nil { row = there.minY }
                    // Past that row: the nearest of it is known.
                    if there.minY != row { break }
                    let distance = abs(there.midX - here.midX)
                    if best == nil || distance < best!.distance { best = (next, distance) }
                }
                next += step
            }
            return best?.index
        }
    }

    /// Self-test hook: where a tile is in the grid.
    func frame(of index: Int) -> NSRect? {
        collection.layoutAttributesForItem(at: path(of: index))?.frame
    }

    /// Self-test hook: the group names shown in the grid, in order.
    var groupNames: [String] { sections.map(\.name).filter { !$0.isEmpty } }

    private func path(of index: Int) -> IndexPath {
        let section = (starts.lastIndex { $0 <= index }) ?? 0
        return IndexPath(item: index - (starts.indices.contains(section) ? starts[section] : 0), section: section)
    }

    private func index(of path: IndexPath) -> Int {
        (starts.indices.contains(path.section) ? starts[path.section] : 0) + path.item
    }

    @objc private func scrolled() {
        guard sections.count > 1 else {
            onTopSection?(nil)
            return
        }
        let top = collection.indexPathsForVisibleItems().min() ?? IndexPath(item: 0, section: 0)
        onTopSection?(sections[top.section].name)
    }

    fileprivate func clicked(_ item: EmojiGridItem, count: Int) {
        guard let path = collection.indexPath(for: item) else { return }
        let flat = index(of: path)
        onSelect?(flat)
        if count > 1 { onOpen?(flat) }
    }
}

extension EmojiGridView: NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections.indices.contains(section) ? sections[section].count : 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: EmojiGridItem.identifier, for: indexPath)
        if let tile = item as? EmojiGridItem {
            let flat = index(of: indexPath)
            if tiles.indices.contains(flat) { tile.show(tiles[flat].character, name: tiles[flat].name) }
            tile.isChosen = flat == selected
            tile.grid = self
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: EmojiGridHeader.identifier, for: indexPath)
        (view as? EmojiGridHeader)?.label.stringValue = sections.indices.contains(indexPath.section) ? sections[indexPath.section].name : ""
        return view
    }

    /// The first group's name is the launcher's header; the others sit
    /// above their rows.
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> NSSize {
        NSSize(width: collectionView.bounds.width, height: section == 0 ? 0 : Self.headerHeight)
    }
}

/// Never takes the keys: the search field keeps them while the grid
/// shows what they select.
private final class EmojiCollectionView: NSCollectionView {
    override var acceptsFirstResponder: Bool { false }
}

/// One emoji on a tile; the chosen one on the launcher's selection fill.
final class EmojiGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("EmojiGridItem")
    weak var grid: EmojiGridView?

    var isChosen = false {
        didSet { (view as? EmojiTile)?.isChosen = isChosen }
    }

    override func loadView() {
        let tile = EmojiTile()
        tile.item = self
        view = tile
    }

    func show(_ character: String, name: String) {
        (view as? EmojiTile)?.character = character
        view.setAccessibilityLabel(name)
    }

    fileprivate func clicked(count: Int) {
        grid?.clicked(self, count: count)
    }
}

/// Draws its emoji itself, centered on the glyph's own bounds: a label
/// clipped those that reach past their advance (🫡's face was cut).
private final class EmojiTile: NSView {
    private static let font = NSFont.systemFont(ofSize: 32)
    weak var item: EmojiGridItem?
    var character = "" {
        didSet { if character != oldValue { needsDisplay = true } }
    }
    var isChosen = false {
        didSet { if isChosen != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isChosen {
            Theme.selectionFill.setFill()
            let rect = bounds.insetBy(dx: 3, dy: 3)
            NSBezierPath(roundedRect: rect, xRadius: Theme.Radius.row, yRadius: Theme.Radius.row).fill()
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // A symbol is a glyph in the text color (an emoji brings its own):
        // black on dark glass could not be seen.
        let color = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: [.font: Self.font, color: NSColor.labelColor.cgColor]))
        // The glyph's own box, from the baseline: centered whatever its advance.
        let glyph = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: bounds.midX - glyph.midX, y: bounds.midY - glyph.midY)
        CTLineDraw(line, context)
    }

    override func mouseDown(with event: NSEvent) {
        item?.clicked(count: event.clickCount)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
}

/// A group's name above its rows, in the launcher's section style.
final class EmojiGridHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("EmojiGridHeader")
    let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = Theme.Font.sectionHeader
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
